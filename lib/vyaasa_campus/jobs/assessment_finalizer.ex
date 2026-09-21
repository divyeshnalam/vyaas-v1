defmodule VyaasaCampus.Jobs.AssessmentFinalizer do
  @moduledoc """
  Finalizes an assessment session that was abandoned mid-attempt — closes the
  tab / navigates away / disconnects, or a BEAM crash orphaned it — instead of
  leaving it stuck non-terminal forever.

  Two triggers enqueue this job with identical args, sharing one completion
  path per type:

    * A LiveView's `terminate/2` (immediate — see e.g.
      `VyaasaCampusWeb.Student.Jam.JamSessionLive`), the moment a connected
      session's socket goes away.
    * `AssessmentAbandonmentSweep` (safety net — catches what `terminate/2`
      structurally can't: a node crash skips it entirely).

  MCQ is NOT dispatched through here — its scoring is objective (no LLM), so
  its `terminate/2` calls `Assessments.force_submit_assessment/3` directly and
  synchronously. Everything else evaluates via an LLM, which has no place
  running inline inside a dying LiveView process — hence a real job, with
  Oban's retries and the already-configured `Oban.Plugins.Lifeline` covering
  transient failures and orphaned executions the same way they do for
  `AtsResumeProcessor`.

  Each `force_complete/2` is idempotent — safe to run twice if `terminate/2`
  and the sweep both catch the same session — so this worker doesn't need its
  own dedup logic beyond what each context function already does.
  """

  use Oban.Worker,
    queue: :assessment_finalize,
    max_attempts: 3,
    priority: 1,
    # terminate/2 and the safety-net sweep can both enqueue for the same
    # session (a terminate/2-enqueued job still queued when the sweep next
    # runs, or two sweep ticks either side of a slow job) — dedupe so a
    # session is never force_complete'd twice concurrently. Each type's
    # force_complete/2 is already idempotent against a *sequential* repeat
    # (status re-checked from DB), but that doesn't protect against two
    # instances reading "not yet terminal" at the same time and both
    # re-running the real evaluation (e.g. JAM re-transcribing/re-scoring the
    # same recording twice while status is still "processing").
    unique: [fields: [:args], period: 300, states: [:available, :scheduled, :executing]]

  require Logger

  # Dispatched via apply/3 (module resolved by name, not a compile-time
  # &Module.fun/2 capture) — deliberately, so this worker compiles and is
  # independently testable before every type's force_complete/2 exists yet.
  @dispatch %{
    "jam" => VyaasaCampus.Contexts.Jam,
    "interview" => VyaasaCampus.Contexts.Interview,
    "behavioral" => VyaasaCampus.Contexts.Behavioral,
    "psychometric" => VyaasaCampus.Contexts.Psychometric,
    "case_study" => VyaasaCampus.Contexts.CaseStudy,
    "mini_project" => VyaasaCampus.Contexts.MiniProject,
    "mini_project_v4" => VyaasaCampus.Contexts.MiniProjectV4
  }

  @doc "Enqueue finalization for one abandoned session. `type` is one of #{inspect(Map.keys(@dispatch))}."
  def enqueue(type, session_id, tenant_schema) when is_binary(type) and is_binary(tenant_schema) do
    %{"type" => type, "session_id" => to_string(session_id), "tenant_schema" => tenant_schema}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => type, "session_id" => session_id, "tenant_schema" => tenant_schema}}) do
    case Map.fetch(@dispatch, type) do
      {:ok, module} ->
        Logger.info("AssessmentFinalizer | type=#{type} session=#{session_id} tenant=#{tenant_schema}")
        apply(module, :force_complete, [session_id, tenant_schema])

      :error ->
        Logger.error("AssessmentFinalizer | unknown type=#{inspect(type)}")
        {:discard, "unknown assessment type: #{type}"}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 1min, 4min, 9min — mirrors AtsResumeProcessor.
    attempt * attempt * 60
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end
