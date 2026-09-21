defmodule VyaasaCampus.Jobs.AssessmentAbandonmentSweep do
  @moduledoc """
  Safety net for abandoned assessment sessions that `terminate/2` structurally
  can't catch — a BEAM node crash / brutal kill skips `terminate/2` entirely,
  so nothing ever enqueues `AssessmentFinalizer` for that session. Runs on a
  cron schedule (see `config/config.exs`), sweeps every tenant schema, and
  enqueues the same finalize job `terminate/2` would have.

  This is genuinely rare in the common case — `terminate/2` handles graceful
  disconnects (tab close, nav-away, normal connection drop) on its own — so
  this is a backstop, not the primary detection path.

  Staleness rule, per type:
    * Types with a real deadline (MCQ via duration_minutes, Mini Project v1/v4
      via `submission_deadline`) are only swept once that deadline has
      actually passed — never a student still validly mid-session just
      because they've been quiet for a while.
    * Everything else (no deadline concept: JAM, Interview, Behavioral,
      Psychometric, Case Study; and the pre-deadline phases of Mini Project,
      before a deadline is even assigned) uses a flat inactivity grace window
      — `updated_at` is bumped by every incremental write these sessions make
      (a discovery message, a viva answer, a proctoring log), so an untouched
      row past the grace window has nothing left happening in it.

  MCQ bypasses `AssessmentFinalizer` — same as its `terminate/2` — and calls
  `Assessments.force_submit_assessment/3` directly: synchronous, no LLM, safe
  to run inline against the DB-persisted `answers` (already kept current by
  `save_answers/5` for exactly this reason: resuming across reloads).
  """

  use Oban.Worker, queue: :assessment_finalize, max_attempts: 3, priority: 3

  import Ecto.Query, warn: false

  alias VyaasaCampus.Contexts.{Assessments, Tenants}
  alias VyaasaCampus.Jobs.AssessmentFinalizer
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Assessments.{Assessment, AssessmentAttempt}
  alias VyaasaCampus.Schema.CaseStudy.CaseStudySession
  alias VyaasaCampus.Schema.Interview.InterviewSession
  alias VyaasaCampus.Schema.Jam.JamSession
  alias VyaasaCampus.Schema.Students.{
    StudentBehavioralAssessment,
    StudentMiniProjectSession,
    StudentPsychometricAssessment
  }

  require Logger

  @grace_minutes 30

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    cutoff = DateTime.add(now, -@grace_minutes * 60, :second)

    Tenants.list_tenants()
    |> Enum.each(fn tenant -> sweep_tenant(tenant.schema_name, now, cutoff) end)

    {:ok, :swept}
  end

  defp sweep_tenant(prefix, now, cutoff) do
    sweep_mcq(prefix, now, cutoff)
    sweep_by_field(JamSession, "jam", :id, prefix, cutoff, ~w(completed failed))
    sweep_by_field(InterviewSession, "interview", :id, prefix, cutoff, ~w(completed failed))
    sweep_by_field(StudentBehavioralAssessment, "behavioral", :session_id, prefix, cutoff, ~w(completed failed))
    sweep_by_field(StudentPsychometricAssessment, "psychometric", :session_id, prefix, cutoff, ~w(completed failed))
    sweep_by_field(CaseStudySession, "case_study", :session_token, prefix, cutoff, ~w(completed failed terminated))
    sweep_mini_project(prefix, now, cutoff)
  rescue
    e ->
      Logger.error("AssessmentAbandonmentSweep | tenant=#{prefix} failed: #{Exception.message(e)}")
  end

  # ── MCQ — synchronous, no AssessmentFinalizer hop ───────────────────────────

  defp sweep_mcq(prefix, now, cutoff) do
    from(a in AssessmentAttempt,
      join: asm in Assessment,
      on: asm.id == a.assessment_id,
      where: a.status in ["started", "in_progress"],
      select: %{id: a.id, answers: a.answers, started_at: a.started_at, duration_minutes: asm.duration_minutes, updated_at: a.updated_at}
    )
    |> Repo.all(prefix: prefix)
    |> Enum.filter(&mcq_overdue?(&1, now, cutoff))
    |> Enum.each(fn a ->
      Logger.info("AssessmentAbandonmentSweep | mcq attempt=#{a.id} tenant=#{prefix}")
      Assessments.force_submit_assessment(a.id, a.answers || %{}, prefix)
    end)
  end

  defp mcq_overdue?(%{duration_minutes: minutes, started_at: started_at}, now, _cutoff)
       when is_integer(minutes) and not is_nil(started_at) do
    DateTime.compare(DateTime.add(started_at, minutes * 60, :second), now) == :lt
  end

  defp mcq_overdue?(%{updated_at: updated_at}, _now, cutoff),
    do: DateTime.compare(updated_at, cutoff) == :lt

  # ── Mini Project v1 / v4 — share one table, split by engine_version ────────

  defp sweep_mini_project(prefix, now, cutoff) do
    from(s in StudentMiniProjectSession,
      where: s.phase != "completed",
      select: %{
        id: s.id,
        engine_version: s.engine_version,
        submission_deadline: s.submission_deadline,
        updated_at: s.updated_at
      }
    )
    |> Repo.all(prefix: prefix)
    |> Enum.filter(&mini_project_overdue?(&1, now, cutoff))
    |> Enum.each(fn s ->
      type = if s.engine_version == "v4", do: "mini_project_v4", else: "mini_project"
      Logger.info("AssessmentAbandonmentSweep | #{type} session=#{s.id} tenant=#{prefix}")
      AssessmentFinalizer.enqueue(type, s.id, prefix)
    end)
  end

  defp mini_project_overdue?(%{submission_deadline: deadline}, now, _cutoff) when not is_nil(deadline),
    do: DateTime.compare(deadline, now) == :lt

  defp mini_project_overdue?(%{updated_at: updated_at}, _now, cutoff),
    do: DateTime.compare(updated_at, cutoff) == :lt

  # ── Types with no deadline concept — flat grace window ──────────────────────

  defp sweep_by_field(schema, type, id_field, prefix, cutoff, terminal_statuses) do
    from(s in schema,
      where: s.status not in ^terminal_statuses and s.updated_at < ^cutoff,
      select: field(s, ^id_field)
    )
    |> Repo.all(prefix: prefix)
    |> Enum.each(fn id ->
      Logger.info("AssessmentAbandonmentSweep | #{type} session=#{id} tenant=#{prefix}")
      AssessmentFinalizer.enqueue(type, id, prefix)
    end)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end
