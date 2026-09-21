defmodule VyaasaCampus.AI.GroqRateLimiter do
  @moduledoc """
  GenServer-based rate limiter for Groq API requests.
  Uses a token bucket pattern with a bounded queue for backpressure.

  When in-flight requests are below max_concurrent, requests proceed immediately.
  Otherwise they queue with a caller-specified timeout.
  When Groq returns 429, the limiter pauses all new requests for the retry-after duration.
  """

  use GenServer

  require Logger

  @default_max_concurrent 50
  @default_max_queue_size 500

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Acquire a slot to make a Groq API request.
  Blocks the caller until a slot is available or timeout is reached.

  Returns :ok | {:error, :queue_timeout} | {:error, :queue_full}
  """
  def acquire(timeout \\ 30_000) do
    GenServer.call(__MODULE__, {:acquire, timeout}, timeout + 5_000)
  catch
    :exit, {:timeout, _} -> {:error, :queue_timeout}
  end

  @doc """
  Release a slot after a Groq API request completes.
  Must be called in an `after` block to prevent leaks.
  """
  def release do
    GenServer.cast(__MODULE__, :release)
  end

  @doc """
  Pause all new requests for the given duration (ms).
  Called when Groq returns a 429 with retry-after header.
  """
  def pause(duration_ms) when is_integer(duration_ms) and duration_ms > 0 do
    GenServer.cast(__MODULE__, {:pause, duration_ms})
  end

  @doc """
  Get current rate limiter stats.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(opts) do
    config = Application.get_env(:vyaasa_campus, __MODULE__, [])

    max_concurrent = opts[:max_concurrent] || config[:max_concurrent] || @default_max_concurrent
    max_queue_size = opts[:max_queue_size] || config[:max_queue_size] || @default_max_queue_size

    Logger.info("GroqRateLimiter started | max_concurrent=#{max_concurrent} | max_queue=#{max_queue_size}")

    state = %{
      in_flight: 0,
      max_concurrent: max_concurrent,
      queue: :queue.new(),
      max_queue_size: max_queue_size,
      paused_until: nil,
      total_processed: 0,
      total_queued: 0,
      total_rejected: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:acquire, timeout}, from, state) do
    cond do
      # Paused due to 429 — check if pause expired
      state.paused_until && System.monotonic_time(:millisecond) < state.paused_until ->
        if :queue.len(state.queue) >= state.max_queue_size do
          {:reply, {:error, :queue_full}, %{state | total_rejected: state.total_rejected + 1}}
        else
          timer_ref = Process.send_after(self(), {:queue_timeout, from}, timeout)
          entry = {from, timer_ref, System.monotonic_time(:millisecond)}
          {:noreply, %{state |
            queue: :queue.in(entry, state.queue),
            total_queued: state.total_queued + 1
          }}
        end

      # Slot available — grant immediately
      state.in_flight < state.max_concurrent ->
        {:reply, :ok, %{state | in_flight: state.in_flight + 1}}

      # Queue full — reject
      :queue.len(state.queue) >= state.max_queue_size ->
        {:reply, {:error, :queue_full}, %{state | total_rejected: state.total_rejected + 1}}

      # Queue the caller
      true ->
        timer_ref = Process.send_after(self(), {:queue_timeout, from}, timeout)
        entry = {from, timer_ref, System.monotonic_time(:millisecond)}
        {:noreply, %{state |
          queue: :queue.in(entry, state.queue),
          total_queued: state.total_queued + 1
        }}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      in_flight: state.in_flight,
      max_concurrent: state.max_concurrent,
      queue_size: :queue.len(state.queue),
      max_queue_size: state.max_queue_size,
      total_processed: state.total_processed,
      total_queued: state.total_queued,
      total_rejected: state.total_rejected,
      paused: state.paused_until != nil && System.monotonic_time(:millisecond) < state.paused_until
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast(:release, state) do
    state = %{state |
      in_flight: max(state.in_flight - 1, 0),
      total_processed: state.total_processed + 1
    }

    # Grant to next queued caller if available
    state = maybe_grant_next(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:pause, duration_ms}, state) do
    pause_until = System.monotonic_time(:millisecond) + duration_ms
    Logger.warning("GroqRateLimiter | PAUSED for #{duration_ms}ms due to 429 rate limit")

    # Schedule unpause
    Process.send_after(self(), :unpause, duration_ms)

    {:noreply, %{state | paused_until: pause_until}}
  end

  @impl true
  def handle_info(:unpause, state) do
    Logger.info("GroqRateLimiter | UNPAUSED — resuming requests")
    state = %{state | paused_until: nil}

    # Drain queued requests
    state = drain_queue(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:queue_timeout, from}, state) do
    # Remove the timed-out caller from the queue
    new_queue =
      state.queue
      |> :queue.to_list()
      |> Enum.reject(fn {queued_from, _timer, _enqueued_at} -> queued_from == from end)
      |> :queue.from_list()

    # Reply with timeout error
    try do
      GenServer.reply(from, {:error, :queue_timeout})
    catch
      _, _ -> :ok
    end

    {:noreply, %{state | queue: new_queue}}
  end

  # ============================================================================
  # PRIVATE
  # ============================================================================

  defp maybe_grant_next(state) do
    paused? = is_integer(state.paused_until) and System.monotonic_time(:millisecond) < state.paused_until

    if not paused? and state.in_flight < state.max_concurrent and not :queue.is_empty(state.queue) do
      case :queue.out(state.queue) do
        {{:value, {from, timer_ref, _enqueued_at}}, new_queue} ->
          Process.cancel_timer(timer_ref)

          try do
            GenServer.reply(from, :ok)
          catch
            _, _ -> :ok
          end

          new_state = %{state | queue: new_queue, in_flight: state.in_flight + 1}
          maybe_grant_next(new_state)

        {:empty, _} ->
          state
      end
    else
      state
    end
  end

  defp drain_queue(state) do
    maybe_grant_next(state)
  end
end
