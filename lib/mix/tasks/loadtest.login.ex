defmodule Mix.Tasks.Loadtest.Login do
  @moduledoc """
  Concurrency load test for the login hot path (bcrypt password verification),
  which the earlier burst test identified as the serializing step under load.

  Fires N concurrent verifications per burst, and reports — per burst — the
  success rate within a time window and the p95 latency, mirroring the login
  burst-test table. Runs each configured bcrypt cost so you can compare directly.

      mix loadtest.login
      mix loadtest.login --bursts 1,10,25,50,100,200 --window 45000 --costs 12,10 --reps 2

  This measures the CPU-bound hashing ceiling in isolation (no web server / DB),
  so numbers are a clean upper bound for how many logins a single node's cores
  can clear. Real end-to-end login adds DB + network on top.
  """
  use Mix.Task

  @shortdoc "Burst load test of bcrypt login verification (compare costs)"

  @default_bursts [1, 10, 25, 50, 100, 200]
  @default_costs [12, 10]

  @impl true
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [bursts: :string, window: :integer, costs: :string, reps: :integer]
      )

    bursts = parse_ints(opts[:bursts]) || @default_bursts
    costs = parse_ints(opts[:costs]) || @default_costs
    window = opts[:window] || 45_000
    reps = opts[:reps] || 2

    Mix.Task.run("app.start")

    cores = System.schedulers_online()

    IO.puts("""
    Login burst load test
    ─────────────────────
    cores(schedulers)=#{cores}  window=#{window}ms  reps=#{reps}
    costs=#{inspect(costs, charlists: :as_lists)}  bursts=#{inspect(bursts, charlists: :as_lists)}
    """)

    for cost <- costs do
      # A stored hash AT this cost; verification reads the cost from the hash.
      hash = Bcrypt.Base.hash_password("Vyaasa#Load1", Bcrypt.Base.gen_salt(cost, true))

      IO.puts("\n== bcrypt cost #{cost} ==")
      IO.puts(row(["Burst", "success%", "p95"]))
      IO.puts(String.duplicate("─", 34))

      for burst <- bursts do
        {succ_pct, p95} = run_burst(hash, burst, window, reps)
        IO.puts(row([Integer.to_string(burst), "#{succ_pct}%", "#{p95}s"]))
      end
    end

    IO.puts("\nDone.")
  end

  # Run `reps` repetitions of a `burst`-wide concurrent verification, pool the
  # per-call latencies, and return {rounded success %, pooled p95 seconds}.
  defp run_burst(hash, burst, window, reps) do
    results =
      for _rep <- 1..reps, _i <- 1..burst do
        Task.async(fn ->
          start = System.monotonic_time(:millisecond)
          Bcrypt.verify_pass("Vyaasa#Load1", hash)
          System.monotonic_time(:millisecond) - start
        end)
      end
      |> Enum.map(fn t ->
        case Task.yield(t, window) || Task.shutdown(t, :brutal_kill) do
          {:ok, ms} -> {:ok, ms}
          _ -> :timeout
        end
      end)

    total = length(results)
    latencies = for {:ok, ms} <- results, do: ms
    # Strict deadline: a login "succeeds" only if it cleared within the window.
    succeeded = Enum.count(latencies, &(&1 <= window))

    succ_pct = Float.round(succeeded / total * 100, 1)
    p95 = if latencies == [], do: 0.0, else: percentile(latencies, 95) / 1000
    {succ_pct, Float.round(p95, 1)}
  end

  defp percentile(list, p) do
    sorted = Enum.sort(list)
    idx = round(p / 100 * (length(sorted) - 1))
    Enum.at(sorted, idx)
  end

  defp row(cells) do
    [a, b, c] = cells
    String.pad_trailing(a, 8) <> String.pad_trailing(b, 12) <> c
  end

  defp parse_ints(nil), do: nil

  defp parse_ints(str),
    do: str |> String.split(",") |> Enum.map(&(&1 |> String.trim() |> String.to_integer()))
end
