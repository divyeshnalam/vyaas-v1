defmodule VyaasaCampus.Contexts.CaseStudy do
  @moduledoc """
  Context for the AI-Generated Case Study module.

  Flow: `start_session/4` generates a scenario and persists an in-progress
  session → `submit/4` evaluates the 7-section answers, stores the three
  dimension scores + report, and publishes the result into the AI8 framework.

  AI8 mapping (scores normalised to 0–100):
    domain_score (0-40)          → domain_expertise
    problem_solving_score (0-30) → problem_solving
    leadership_score (0-30)      → leadership
  """

  import Ecto.Query, warn: false

  alias VyaasaCampus.Repo
  alias VyaasaCampus.AI.CaseStudyEngine
  alias VyaasaCampus.AI.CaseStudy.Specializations
  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.Schema.CaseStudy.CaseStudySession

  require Logger

  @doc "Generate the two scenarios shown on the choose-your-scenario step."
  def generate_scenarios(sub), do: CaseStudyEngine.generate_scenarios(sub, 2)

  @doc """
  Persist a session for the scenario the student chose. Returns `{:ok, session}`.
  """
  def start_session(student_id, tenant_id, sub, scenario, prefix)
      when is_binary(prefix) and is_map(scenario) do
    with :ok <- VyaasaCampus.Contexts.AttemptGuard.check(student_id, :case_study, tenant_id, prefix) do
      do_start_session(student_id, tenant_id, sub, scenario, prefix)
    end
  end

  defp do_start_session(student_id, tenant_id, sub, scenario, prefix) do
    attrs = %{
      student_id: student_id,
      tenant_id: tenant_id,
      session_token: Ecto.UUID.generate(),
      specialization_sub: sub,
      specialization_group: Specializations.group_for(sub),
      scenario: stringify(scenario),
      status: "in_progress",
      attempt_number: next_attempt_number(student_id, prefix)
    }

    %CaseStudySession{}
    |> CaseStudySession.create_changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  @doc "Fetch a session by token."
  def get_session_by_token(token, prefix) do
    Repo.get_by(CaseStudySession, [session_token: token], prefix: prefix)
  end

  @doc "Log a proctoring violation on the case-study session; returns new count."
  def record_violation(token, type, prefix) do
    case get_session_by_token(token, prefix) do
      nil ->
        {:error, :not_found}

      s ->
        meta = s.metadata || %{}
        entry = %{"type" => type, "at" => DateTime.utc_now() |> DateTime.to_iso8601()}
        violations = (meta["violations"] || []) ++ [entry]
        count = length(violations)
        meta = meta |> Map.put("violations", violations) |> Map.put("violation_count", count)

        case s |> Ecto.Changeset.change(metadata: meta) |> Repo.update(prefix: prefix) do
          {:ok, _} -> {:ok, count}
          {:error, _} = err -> err
        end
    end
  end

  @doc "End a case-study session with no score (proctoring auto-finalize, no answers)."
  def terminate(%CaseStudySession{} = session, prefix) do
    session
    |> Ecto.Changeset.change(
      status: "terminated",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update(prefix: prefix)
  end

  @doc "Readable proctoring flags for the admin Integrity panel."
  def student_integrity_flags(student_id, prefix) do
    CaseStudySession
    |> where([s], s.student_id == ^student_id)
    |> Repo.all(prefix: prefix)
    |> Enum.flat_map(fn s -> case_study_flags(s.metadata || %{}) end)
    |> Enum.uniq()
  end

  defp case_study_flags(meta) do
    case meta["violation_count"] || 0 do
      c when c >= 2 ->
        breakdown =
          (meta["violations"] || [])
          |> Enum.frequencies_by(& &1["type"])
          |> Enum.map(fn {t, n} -> "#{n} #{humanize_violation(t)}" end)
          |> Enum.join(", ")

        detail = if breakdown == "", do: "#{c} focus losses", else: breakdown
        ["Case Study — proctoring: #{c} violations (#{detail})"]

      _ ->
        []
    end
  end

  defp humanize_violation("tab_switch"), do: "tab switch"
  defp humanize_violation("window_blur"), do: "window switch"
  defp humanize_violation("fullscreen_exit"), do: "full-screen exit"
  defp humanize_violation(other), do: to_string(other)

  @doc "All case study sessions for a student (newest attempt first)."
  def list_student_sessions(student_id, prefix) do
    CaseStudySession
    |> where([s], s.student_id == ^student_id)
    |> order_by([s], desc: s.attempt_number)
    |> Repo.all(prefix: prefix)
  end

  @doc "Latest completed session for a student."
  def get_latest(student_id, prefix) do
    CaseStudySession
    |> where([s], s.student_id == ^student_id and s.status == "completed")
    |> order_by([s], desc: s.attempt_number)
    |> limit(1)
    |> Repo.one(prefix: prefix)
  end

  @doc """
  Submit answers, evaluate, persist scores + report, and publish to AI8.
  `answers` is a map keyed by question key (see `CaseStudy.Questions`).
  """
  def submit(%CaseStudySession{} = session, answers, prefix) when is_map(answers) do
    # Opik: scope this session's thread id (session_token — same id the
    # finalizer uses) around the (unchanged) body so the evaluation LLM call
    # joins the session thread. Result passes through as-is.
    VyaasaCampus.AI.Tracing.with_thread_id(session.session_token, fn ->
      do_submit(session, answers, prefix)
    end)
  end

  defp do_submit(session, answers, prefix) do
    group = session.specialization_group || Specializations.group_for(session.specialization_sub)
    sub = session.specialization_sub

    case CaseStudyEngine.evaluate(session.scenario, answers, group, sub) do
      {:ok, report} ->
        domain = to_int(report["domain_score"])
        problem = to_int(report["problem_solving_score"])
        leadership = to_int(report["leadership_score"])
        total = to_int(report["total_score"]) || (clamp(domain, 0, 40) + clamp(problem, 0, 30) + clamp(leadership, 0, 30))

        attrs = %{
          answers: stringify(answers),
          domain_score: clamp(domain, 0, 40),
          problem_solving_score: clamp(problem, 0, 30),
          leadership_score: clamp(leadership, 0, 30),
          total_score: clamp(total, 0, 100),
          report: report,
          status: "completed",
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        case session
             |> CaseStudySession.complete_changeset(attrs)
             |> Repo.update(prefix: prefix) do
          {:ok, updated} = ok ->
            finalize_side_effects(updated, prefix)
            ok

          other ->
            other
        end

      {:error, reason} ->
        Logger.error("CASE_STUDY | submit evaluation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp finalize_side_effects(session, prefix) do
    publish_ai8(session, prefix)
    VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:case_study, session.id, prefix)
  end

  @terminal_statuses ~w(completed failed terminated)

  @doc """
  Force-completes a session abandoned mid-attempt (tab closed / crashed).

  Unlike JAM/Interview, there is nothing partial to recover: the 7 section
  answers live only in LiveView assigns (`update_answers` merges into
  `socket.assigns.answers`, never persisted incrementally) and are written to
  the DB in one shot at `submit/3` — so, same as Behavioral, this always
  writes a direct zero-score completed record; there is no "partial
  evaluation" branch possible.

  Note this is deliberately a `"completed"` record with a zero score, not the
  pre-existing `"terminated"` status (used by `terminate/2` above for the
  proctoring auto-finalize case, which leaves scores nil) — abandonment
  should read the same as any other force-completed assessment across all 8
  types: a real terminal record with a score, not a distinct unscored state.

  Idempotent: a session already in a terminal status (including
  `"terminated"`) is left untouched.
  """
  def force_complete(session_token, prefix) do
    case get_session_by_token(session_token, prefix) do
      nil ->
        {:error, :not_found}

      %{status: status} when status in @terminal_statuses ->
        {:ok, :already_terminal}

      session ->
        attrs = %{
          answers: %{},
          domain_score: 0,
          problem_solving_score: 0,
          leadership_score: 0,
          total_score: 0,
          report: %{"summary" => "This case study assessment was abandoned before completion."},
          status: "completed",
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        case session
             |> CaseStudySession.complete_changeset(attrs)
             |> Repo.update(prefix: prefix) do
          {:ok, updated} = ok ->
            finalize_side_effects(updated, prefix)
            ok

          other ->
            other
        end
    end
  end

  # AI8: normalise the three dimension scores to 0–100 and publish (filtered to
  # the admin's configured dimensions for the case_study module).
  defp publish_ai8(session, prefix) do
    scores = %{
      "domain_expertise" => normalize(session.domain_score, 40),
      "problem_solving" => normalize(session.problem_solving_score, 30),
      "leadership" => normalize(session.leadership_score, 30)
    }

    AI8.publish_module(
      "case_study",
      scores,
      %{
        student_id: session.student_id,
        tenant_id: session.tenant_id,
        source_type: "case_study_session",
        source_id: session.id
      },
      prefix
    )
  end

  defp normalize(nil, _max), do: nil
  defp normalize(score, max) when is_integer(score) and max > 0, do: round(score / max * 100) |> min(100) |> max(0)
  defp normalize(_, _), do: nil

  defp next_attempt_number(student_id, prefix) do
    n =
      CaseStudySession
      |> where([s], s.student_id == ^student_id)
      |> select([s], max(s.attempt_number))
      |> Repo.one(prefix: prefix)

    (n || 0) + 1
  end

  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: round(n)
  defp to_int(n) when is_binary(n), do: (case Integer.parse(n) do {i, _} -> i; _ -> nil end)
  defp to_int(_), do: nil

  defp clamp(nil, _lo, _hi), do: 0
  defp clamp(n, lo, hi), do: n |> max(lo) |> min(hi)

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
  defp stringify(other), do: other
end