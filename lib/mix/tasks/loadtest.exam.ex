defmodule Mix.Tasks.Loadtest.Exam do
  @moduledoc """
  Concurrency load test that drives real students through a real assessment
  path — the gap `loadtest.login` and `loadtest.rehash` don't cover (they
  test the bcrypt/login hot path in isolation, no DB, no assessment flow).

  Two profiles, matching the two load classes flagged in
  `docs/1000-user-readiness.md`:

    * `mcq`  (default) — pure DB path, no LLM. Each simulated student calls
      the exact context functions the real MCQ flow uses:
      `get_or_create_dynamic_assessment/2` -> `start_assessment_attempt/3` ->
      `force_submit_assessment/3`. Safe to run at any burst size — no Groq
      cost, no rate limit to worry about. This is what actually exercises
      the `assessment_attempts` index/lock contention question.

    * `jam`  — Groq-backed. Each simulated student calls
      `JamEngine.generate_topic/0` directly (same call the real JAM
      "Start" step makes), and the burst is followed by a
      `GroqRateLimiter.stats()` snapshot. **This burns real Groq API
      quota** — sized bursts deliberately, don't default to anything large.

  Usage:

      mix loadtest.exam --tenant Bites
      mix loadtest.exam --tenant Bites --bursts 10,50,100,500,1000
      mix loadtest.exam --tenant Bites --type jam --bursts 5,10,20

  Requires seeded load-test students first — see
  `priv/scripts/seed_load_test_students.exs`:

      mix run priv/scripts/seed_load_test_students.exs Bites 1000

  Reuses students across runs on the same day: `get_or_create_dynamic_assessment/2`
  caches by day, and `force_submit_assessment/3` no-ops once an attempt is
  already terminal — so a second run against the *same* seeded batch mostly
  measures fast no-op reads, not the fresh-write path. Reseed a new batch
  (or pass `--tenant` at a fresh college) before a run you want real
  first-attempt numbers from.

  Each burst uses a *disjoint* slice of the seeded pool — reusing the same
  student across bursts would need a second real attempt, which for most
  assessment types is guarded by attempt limits and would misleadingly show
  up as failures rather than reflecting DB throughput.
  """
  use Mix.Task

  import Ecto.Query

  @shortdoc "Load test a real assessment path (mcq: DB-only; jam: burns Groq quota)"

  @default_bursts [10, 50, 100, 500, 1000]
  @default_jam_bursts [5, 10, 20]

  @impl true
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [type: :string, tenant: :string, bursts: :string, window: :integer]
      )

    type = opts[:type] || "mcq"
    tenant_alias = opts[:tenant] || Mix.raise("Pass --tenant <alias> (the college to load-test against)")
    window = opts[:window] || 60_000

    Mix.Task.run("app.start")

    tenant =
      case VyaasaCampus.Contexts.Tenants.get_tenant_by_alias(tenant_alias) do
        nil -> Mix.raise("No tenant found for alias #{inspect(tenant_alias)}")
        t -> t
      end

    prefix = tenant.schema_name

    case type do
      "mcq" -> run_mcq(prefix, opts[:bursts] |> parse_ints() || @default_bursts, window)
      "jam" -> run_jam(opts[:bursts] |> parse_ints() || @default_jam_bursts, window)
      other -> Mix.raise("Unknown --type #{inspect(other)}. Use \"mcq\" or \"jam\".")
    end
  end

  # ── MCQ: real DB path, no LLM ────────────────────────────────────────────

  defp run_mcq(prefix, bursts, window) do
    total_needed = Enum.sum(bursts)
    students = load_test_student_ids(prefix, total_needed)

    IO.puts("""
    MCQ exam load test (real DB path: get_or_create_assessment -> start_attempt -> submit)
    ────────────────────────────────────────────────────────────────────────────────────
    tenant_schema=#{prefix}  window=#{window}ms  seeded pool available=#{length(students)}
    bursts=#{inspect(bursts)}
    """)

    if length(students) < total_needed do
      IO.puts(
        "⚠ Only #{length(students)} loadtest_ students found, need #{total_needed} for these bursts " <>
          "(sum, since each burst uses fresh students). Seed more: " <>
          "mix run priv/scripts/seed_load_test_students.exs <tenant> #{total_needed}\n"
      )
    end

    IO.puts(row(["Burst", "success%", "p95", "errors (sample)"]))
    IO.puts(String.duplicate("─", 60))

    {_remaining, _} =
      Enum.reduce(bursts, {students, :ok}, fn burst, {pool, _} ->
        {slice, rest} = Enum.split(pool, burst)
        {succ_pct, p95, errors} = run_mcq_burst(slice, prefix, window)
        sample = errors |> Enum.take(2) |> Enum.map_join("; ", &inspect/1)
        IO.puts(row([Integer.to_string(burst), "#{succ_pct}%", "#{p95}s", sample]))
        {rest, :ok}
      end)

    IO.puts("\nDone.")
  end

  defp run_mcq_burst(student_ids, prefix, window) do
    results =
      for student_id <- student_ids do
        Task.async(fn ->
          start = System.monotonic_time(:millisecond)
          result = simulate_mcq_attempt(student_id, prefix)
          {result, System.monotonic_time(:millisecond) - start}
        end)
      end
      |> Enum.map(fn t ->
        case Task.yield(t, window) || Task.shutdown(t, :brutal_kill) do
          {:ok, {result, ms}} -> {result, ms}
          _ -> {{:error, :timeout}, window}
        end
      end)

    total = length(results)
    succeeded = Enum.count(results, fn {r, _ms} -> match?(:ok, r) end)
    latencies = Enum.map(results, fn {_r, ms} -> ms end)
    errors = for {{:error, reason}, _ms} <- results, do: reason

    succ_pct = if total == 0, do: 0.0, else: Float.round(succeeded / total * 100, 1)
    p95 = if latencies == [], do: 0.0, else: percentile(latencies, 95) / 1000
    {succ_pct, Float.round(p95, 1), errors}
  end

  defp simulate_mcq_attempt(student_id, prefix) do
    alias VyaasaCampus.Contexts.Assessments

    with {:ok, assessment} <- Assessments.get_or_create_dynamic_assessment(student_id, prefix),
         {:ok, attempt} <- Assessments.start_assessment_attempt(assessment.id, student_id, prefix),
         {:ok, _submitted} <- Assessments.force_submit_assessment(attempt.id, %{}, prefix) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ── JAM: Groq-backed, burns real quota ───────────────────────────────────

  defp run_jam(bursts, window) do
    alias VyaasaCampus.AI.{GroqRateLimiter, JamEngine}

    IO.puts("""
    JAM topic-generation load test (real Groq call — JamEngine.generate_topic/0)
    ─────────────────────────────────────────────────────────────────────────
    ⚠ This burns real Groq API quota. window=#{window}ms  bursts=#{inspect(bursts)}
    """)

    IO.puts(row(["Burst", "success%", "p95", "rate-limiter stats"]))
    IO.puts(String.duplicate("─", 70))

    for burst <- bursts do
      results =
        for _i <- 1..burst do
          Task.async(fn ->
            start = System.monotonic_time(:millisecond)
            result = JamEngine.generate_topic()
            {result, System.monotonic_time(:millisecond) - start}
          end)
        end
        |> Enum.map(fn t ->
          case Task.yield(t, window) || Task.shutdown(t, :brutal_kill) do
            {:ok, {result, ms}} -> {result, ms}
            _ -> {{:error, :timeout}, window}
          end
        end)

      total = length(results)
      succeeded = Enum.count(results, fn {r, _ms} -> match?({:ok, _}, r) end)
      latencies = Enum.map(results, fn {_r, ms} -> ms end)

      succ_pct = if total == 0, do: 0.0, else: Float.round(succeeded / total * 100, 1)
      p95 = if latencies == [], do: 0.0, else: percentile(latencies, 95) / 1000
      stats = GroqRateLimiter.stats()

      IO.puts(
        row([
          Integer.to_string(burst),
          "#{succ_pct}%",
          "#{Float.round(p95, 1)}s",
          "in_flight=#{stats.in_flight} queued=#{stats.queue_size} rejected=#{stats.total_rejected} paused=#{stats.paused}"
        ])
      )
    end

    IO.puts("\nDone.")
  end

  # ── Shared helpers ────────────────────────────────────────────────────────

  defp load_test_student_ids(prefix, limit) do
    from(s in VyaasaCampus.Schema.Students.Student,
      where: like(s.email, "loadtest_%"),
      order_by: s.inserted_at,
      limit: ^limit,
      select: s.id
    )
    |> VyaasaCampus.Repo.all(prefix: prefix)
  end

  defp percentile(list, p) do
    sorted = Enum.sort(list)
    idx = round(p / 100 * (length(sorted) - 1))
    Enum.at(sorted, idx)
  end

  defp row([a, b, c, d]) do
    String.pad_trailing(a, 8) <> String.pad_trailing(b, 12) <> String.pad_trailing(c, 8) <> d
  end

  defp parse_ints(nil), do: nil

  defp parse_ints(str),
    do: str |> String.split(",") |> Enum.map(&(&1 |> String.trim() |> String.to_integer()))
end
