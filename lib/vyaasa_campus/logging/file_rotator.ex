defmodule VyaasaCampus.Logging.FileRotator do
  @moduledoc """
  Writes application logs to a dated file and rotates them at midnight IST.

  On start it attaches an Erlang `:logger_std_h` handler pointing at
  `log/vyaasa_campus-YYYY-MM-DD.log` (the date being *today* in the configured
  zone, `Asia/Kolkata` by default). At 00:00 IST it swaps the handler onto the
  new day's file, zips the day that just closed, and deletes archives beyond the
  retention window (3 days by default).

  Log lines themselves are timestamped in UTC (see `config :logger, utc_log: true`);
  only the rotation boundary and the file name follow IST.

  Configure with:

      config :vyaasa_campus, VyaasaCampus.Logging.FileRotator,
        enabled: true,
        dir: "log",
        basename: "vyaasa_campus",
        time_zone: "Asia/Kolkata",
        keep_days: 3
  """

  use GenServer

  require Logger

  @handler_id :vyaasa_campus_file_log
  @defaults [
    enabled: true,
    dir: "log",
    basename: "vyaasa_campus",
    time_zone: "Asia/Kolkata",
    keep_days: 3,
    format: "$date $time $metadata[$level] $message\n",
    metadata: [:request_id]
  ]

  def start_link(opts) do
    config =
      @defaults
      |> Keyword.merge(config_from_env())
      |> Keyword.merge(opts)

    if config[:enabled] do
      GenServer.start_link(__MODULE__, config, name: __MODULE__)
    else
      :ignore
    end
  end

  @doc "Rotates immediately, regardless of the clock. Useful in IEx and tests."
  def rotate_now, do: GenServer.call(__MODULE__, :rotate)

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)
    File.mkdir_p!(config[:dir])

    date = today(config)
    :ok = attach_handler(config, date)

    # Anything left over from a previous run (crash, deploy, downtime) still
    # needs archiving before we start appending to today's file.
    archive_closed_days(config, date)
    prune(config)

    {:ok, schedule_rotation(%{config: config, date: date})}
  end

  @impl true
  def handle_call(:rotate, _from, state), do: {:reply, :ok, rotate(state)}

  @impl true
  def handle_info(:rotate, state), do: {:noreply, schedule_rotation(rotate(state))}

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state) do
    :logger.remove_handler(@handler_id)
    :ok
  end

  ## Rotation

  defp rotate(%{config: config, date: previous} = state) do
    date = today(config)

    if date == previous do
      # Timer fired a hair early; nothing to close yet.
      state
    else
      :logger.remove_handler(@handler_id)
      :ok = attach_handler(config, date)
      archive_closed_days(config, date)
      prune(config)
      %{state | date: date}
    end
  end

  defp attach_handler(config, date) do
    formatter =
      Logger.Formatter.new(
        format: config[:format],
        metadata: config[:metadata],
        utc_log: true
      )

    :logger.add_handler(@handler_id, :logger_std_h, %{
      level: :all,
      config: %{
        type: {:file, String.to_charlist(log_path(config, date))},
        file_check: 1_000
      },
      formatter: formatter
    })
  end

  # Zip every `*.log` that is not the file we are currently writing to.
  defp archive_closed_days(config, date) do
    current = Path.basename(log_path(config, date))

    config
    |> list_files(".log")
    |> Enum.reject(&(&1 == current))
    |> Enum.each(&zip(config, &1))
  end

  defp zip(config, name) do
    dir = config[:dir]
    archive = Path.join(dir, name <> ".zip")

    case :zip.create(String.to_charlist(archive), [String.to_charlist(name)], cwd: String.to_charlist(dir)) do
      {:ok, _} ->
        File.rm(Path.join(dir, name))

      {:error, reason} ->
        Logger.error("log rotation: could not zip #{name}: #{inspect(reason)}")
    end
  end

  # Keep only the newest `keep_days` archives. Names are date-suffixed, so
  # lexical order is chronological order.
  defp prune(config) do
    config
    |> list_files(".log.zip")
    |> Enum.sort(:desc)
    |> Enum.drop(config[:keep_days])
    |> Enum.each(&File.rm(Path.join(config[:dir], &1)))
  end

  defp list_files(config, suffix) do
    prefix = config[:basename] <> "-"

    case File.ls(config[:dir]) do
      {:ok, names} ->
        Enum.filter(names, &(String.starts_with?(&1, prefix) and String.ends_with?(&1, suffix)))

      {:error, _} ->
        []
    end
  end

  ## Clock

  defp log_path(config, date) do
    Path.join(config[:dir], "#{config[:basename]}-#{Date.to_iso8601(date)}.log")
  end

  defp today(config), do: config |> now() |> DateTime.to_date()

  defp now(config) do
    case DateTime.now(config[:time_zone]) do
      {:ok, datetime} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp schedule_rotation(%{config: config} = state) do
    Process.send_after(self(), :rotate, ms_until_midnight(config))
    state
  end

  defp ms_until_midnight(config) do
    now = now(config)
    midnight = Date.add(DateTime.to_date(now), 1)

    next =
      case DateTime.new(midnight, ~T[00:00:00], config[:time_zone]) do
        {:ok, datetime} -> datetime
        # Gaps/ambiguity at midnight (DST); IST has none, but stay safe.
        {:ambiguous, _, datetime} -> datetime
        {:gap, _, datetime} -> datetime
        {:error, _} -> DateTime.add(now, 86_400, :second)
      end

    # A second of slack so the timer never lands just before the boundary.
    max(DateTime.diff(next, now, :millisecond) + 1_000, 1_000)
  end

  defp config_from_env do
    Application.get_env(:vyaasa_campus, __MODULE__, [])
  end
end
