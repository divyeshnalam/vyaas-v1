defmodule VyaasaCampus.AI.EmbeddingServer do
  @moduledoc """
  Sentence embedding service backed by `Nx.Serving` and Bumblebee.

  Loads `sentence-transformers/all-MiniLM-L6-v2` once and batches encode
  requests across concurrent BEAM processes — the BEAM-side fix for the
  Python GIL bottleneck on resume scoring.

  Reliability:
  - The supervision child *always* starts. Model load happens after init
    via `handle_continue/2`, so a transient HuggingFace fetch failure can
    NEVER crash the application.
  - Failed loads retry with backoff (capped at 10 minutes).
  - `embed/1` blocks waiting for the model to become ready, with a hard
    timeout so a stuck load doesn't hang Oban workers forever.
  """

  use GenServer

  require Logger

  @model_repo {:hf, "sentence-transformers/all-MiniLM-L6-v2"}
  @serving_name __MODULE__.Serving

  # Hard cap on how long a caller will wait for the model to be ready
  # before giving up. Resume scoring is run inside an Oban worker with
  # its own timeout, so we want to fail fast rather than block forever.
  @ready_wait_timeout 120_000

  # ----------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "True once the model is loaded and the Nx.Serving is running."
  def ready?, do: GenServer.call(__MODULE__, :ready?)

  @doc """
  Encode a string into an L2-normalised embedding (list of floats).

  Returns `{:ok, vector}` or `{:error, reason}`. Blocks up to
  #{@ready_wait_timeout}ms if the model is still loading.
  """
  def embed(text) when is_binary(text) do
    case wait_ready() do
      :ok ->
        try do
          %{embedding: tensor} = Nx.Serving.batched_run(@serving_name, text)
          {:ok, Nx.to_flat_list(tensor)}
        rescue
          e -> {:error, "Embedding inference failed: #{Exception.message(e)}"}
        end

      {:error, _} = err ->
        err
    end
  end

  def embed(texts) when is_list(texts) do
    Enum.reduce_while(texts, {:ok, []}, fn t, {:ok, acc} ->
      case embed(t) do
        {:ok, vec} -> {:cont, {:ok, [vec | acc]}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  @doc "Cosine similarity between two L2-normalised vectors."
  def cosine_similarity(v1, v2) when is_list(v1) and is_list(v2) and length(v1) == length(v2) do
    Enum.zip(v1, v2)
    |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
  end

  @doc "Highest cosine similarity between `query` and any vector in `pool`."
  def max_similarity(query_vec, pool_vecs) when is_list(pool_vecs) do
    pool_vecs
    |> Enum.map(&cosine_similarity(query_vec, &1))
    |> Enum.max(fn -> 0.0 end)
  end

  # ----------------------------------------------------------------------
  # GenServer
  # ----------------------------------------------------------------------

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)
    spawn_loader(self(), 1)
    {:ok, %{ready?: false, attempts: 0, error: nil}}
  end

  @impl true
  def handle_call(:ready?, _from, state), do: {:reply, state.ready?, state}

  @impl true
  def handle_info({:loaded_serving, serving, attempt}, state) do
    case start_nx_serving(serving) do
      :ok ->
        Logger.info("EMBED | Model loaded — embedding server ready")
        {:noreply, %{state | ready?: true, error: nil}}

      {:error, reason} ->
        send(self(), {:load_failed, attempt, reason})
        {:noreply, state}
    end
  end

  def handle_info({:load_failed, attempt, reason}, state) do
    delay = min(60_000 * attempt, 600_000)

    Logger.error(
      "EMBED | Model load failed (attempt #{attempt}): #{inspect(reason)} — retrying in #{div(delay, 1000)}s"
    )

    Process.send_after(self(), {:retry_load, attempt + 1}, delay)
    {:noreply, %{state | ready?: false, attempts: attempt, error: reason}}
  end

  def handle_info({:retry_load, attempt}, state) do
    spawn_loader(self(), attempt)
    {:noreply, state}
  end

  # Loader runs in a separate Task so GenServer.call (e.g. :ready?) is never
  # blocked while Bumblebee downloads weights. The Task only loads the model
  # and builds the Serving struct — the actual Nx.Serving process is started
  # back in the GenServer (linked to it, not to the short-lived Task).
  defp spawn_loader(parent, attempt) do
    Task.start(fn ->
      case load_serving_struct() do
        {:ok, serving} -> send(parent, {:loaded_serving, serving, attempt})
        {:error, reason} -> send(parent, {:load_failed, attempt, reason})
      end
    end)
  end

  defp load_serving_struct do
    with {:ok, model_info} <- safe_call(fn -> Bumblebee.load_model(@model_repo) end),
         {:ok, tokenizer} <- safe_call(fn -> Bumblebee.load_tokenizer(@model_repo) end) do
      # No `compile:` option — let the serving JIT lazily on first request shape.
      # Fixed-shape pre-compile triggered an LLVM "scalable vector" crash on
      # this host's EXLA build.
      serving =
        Bumblebee.Text.text_embedding(model_info, tokenizer,
          output_attribute: :hidden_state,
          output_pool: :mean_pooling,
          embedding_processor: :l2_norm
        )

      {:ok, serving}
    end
  end

  defp start_nx_serving(serving) do
    case Nx.Serving.start_link(serving: serving, name: @serving_name, batch_timeout: 50) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_call(fun) do
    try do
      fun.()
    rescue
      e -> {:error, Exception.message(e)}
    catch
      :exit, reason -> {:error, "exit: #{inspect(reason)}"}
    end
  end

  defp wait_ready do
    deadline = System.monotonic_time(:millisecond) + @ready_wait_timeout
    poll_ready(deadline)
  end

  defp poll_ready(deadline) do
    if ready?() do
      :ok
    else
      now = System.monotonic_time(:millisecond)

      if now >= deadline do
        {:error, :embedding_server_not_ready}
      else
        Process.sleep(500)
        poll_ready(deadline)
      end
    end
  end
end
