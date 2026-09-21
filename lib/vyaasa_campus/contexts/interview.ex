defmodule VyaasaCampus.Contexts.Interview do
  @moduledoc """
  Context for the AI-led Resume Interview.

  Uses the native Elixir interview engine (`VyaasaCampus.AI.Interview.Session`
  — Profile → Planner → Interviewer + GitHub ownership → Evaluator → report).
  No Python service. Parsed resume data is read from `student_ats_phases`
  (latest attempt for the student). Session state is held in-process
  (LiveView assigns) between turns; this module handles DB CRUD, session
  start/step, and completion persistence.
  """

  import Ecto.Query, warn: false

  require Logger

  alias VyaasaCampus.AI.Interview.Extractor
  alias VyaasaCampus.AI.Interview.Profile
  alias VyaasaCampus.AI.Interview.Session, as: Engine
  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.Contexts.Jobs
  alias VyaasaCampus.Contexts.StudentAts
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Interview.InterviewSession

  # ============================================================================
  # SESSION LIFECYCLE (native engine)
  # ============================================================================

  @doc """
  Start a new interview session for a student.

  Reads the latest parsed resume from `student_ats_phases`, adapts it to the
  engine's internal shape, and returns the engine state + greeting.

  Returns `{:ok, %{session_id, session_state, greeting}}` or
  `{:error, reason}` (no resume, missing name, no projects + no experience).
  """
  def start_session(student_id, tenant_schema \\ "public") do
    with :ok <- VyaasaCampus.Contexts.AttemptGuard.check(student_id, :interview, tenant_schema) do
      do_start_session(student_id, tenant_schema)
    end
  end

  defp do_start_session(student_id, tenant_schema) do
    case StudentAts.get_by_student_id(student_id, tenant_schema) do
      nil ->
        {:error, :no_resume}

      %{status: status} when status != "completed" ->
        {:error, :resume_not_ready}

      ats ->
        session_id = Ecto.UUID.generate()

        # Tag this process with the session id now, so the Extractor LLM call
        # below lands in the session's Opik thread instead of as a loose trace.
        VyaasaCampus.AI.Tracing.put_thread_id(session_id)

        profile =
          ats
          |> Profile.from_ats_phase()
          |> attach_job_description(ats.preferred_role)

        # Extractor agent: classify primary/secondary skills + strong/weak/missing
        # areas against the JD (degrades to the input profile on failure).
        profile = Extractor.enrich(profile, profile.jd_text)

        case Engine.new_session(session_id, student_id, profile) do
          {:ok, state} ->
            # Ask the LLM for a warmer, resume-aware greeting. Falls back to
            # the built-in template silently if Groq errors.
            state = Engine.generate_greeting(state)

            Logger.info("INTERVIEW | Session started | session=#{session_id} student=#{student_id}")

            {:ok,
             %{
               session_id: session_id,
               session_state: state,
               greeting: Engine.greeting(state),
               candidate_name: state.candidate_name,
               max_questions: state.max_questions
             }}

          {:error, reason} ->
            Logger.warning("INTERVIEW | Cannot start session | reason=#{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # Resolve the student's preferred role to the super-admin's global job role and
  # attach its skills + JD description so the interview targets role requirements.
  defp attach_job_description(profile, preferred_role) do
    case Jobs.get_active_job_role_by_title(to_string(preferred_role || "")) do
      %{skills: skills, description: description} ->
        Profile.put_jd(profile, skills || [], description || "")

      _ ->
        profile
    end
  end

  @doc """
  Advance from the greeting stage to the first question.
  Blocking — returns the first question.
  """
  def proceed(session_state) do
    Engine.proceed(session_state)
  end

  @doc """
  Submit the candidate's answer to the current question. Returns either the
  next question or the final placement-readiness report.
  """
  def submit_answer(session_state, answer) when is_binary(answer) do
    Engine.submit_answer(session_state, answer)
  end

  @doc """
  Transcribe audio (base64-encoded WAV/WebM bytes) via Groq Whisper.
  Returns `{:ok, transcript}` or `{:error, reason}`.
  """
  def transcribe_audio(audio_base64, opts \\ []) when is_binary(audio_base64) do
    case Base.decode64(audio_base64) do
      {:ok, bytes} ->
        VyaasaCampus.AI.GroqClient.transcribe_audio(bytes, opts)

      :error ->
        {:error, :invalid_base64}
    end
  end


  # ============================================================================
  # DB OPERATIONS
  # ============================================================================

  def create_interview_session(attrs, prefix) do
    case %InterviewSession{}
         |> InterviewSession.create_changeset(attrs)
         |> Repo.insert(prefix: prefix) do
      {:ok, session} ->
        Logger.info("Interview session created: #{session.session_token}")
        {:ok, session}

      {:error, changeset} ->
        Logger.error("Failed to create interview session: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def get_interview_session(id, prefix) do
    Repo.get(InterviewSession, id, prefix: prefix)
  end

  def get_interview_session_by_token(token, prefix) do
    InterviewSession
    |> where(session_token: ^token)
    |> Repo.one(prefix: prefix)
  end

  @doc "Log a proctoring violation on the interview session (log-only); returns new count."
  def record_violation(token, type, prefix) do
    case get_interview_session_by_token(token, prefix) do
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

  def mark_initialized(session, attrs, prefix) do
    case session
         |> InterviewSession.resume_indexed_changeset(attrs)
         |> Repo.update(prefix: prefix) do
      {:ok, updated} ->
        {:ok, updated}

      {:error, changeset} ->
        Logger.error("Failed to mark interview initialized: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def start_interview(session, prefix) do
    case session
         |> InterviewSession.start_interview_changeset()
         |> Repo.update(prefix: prefix) do
      {:ok, updated} ->
        Logger.info("Interview started: #{session.session_token}")
        {:ok, updated}

      {:error, changeset} ->
        Logger.error("Failed to start interview: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def add_question(session, question_data, prefix) do
    session
    |> InterviewSession.add_question_changeset(question_data)
    |> Repo.update(prefix: prefix)
  end

  def update_question_answer(session, question_number, answer_data, prefix) do
    session
    |> InterviewSession.update_question_answer_changeset(question_number, answer_data)
    |> Repo.update(prefix: prefix)
  end

  def complete_interview(session, attrs, prefix) do
    attrs = apply_ai8_weighted_score(session, attrs, prefix)

    case session
         |> InterviewSession.complete_changeset(attrs)
         |> Repo.update(prefix: prefix) do
      {:ok, updated} ->
        Logger.info("Interview completed: #{session.session_token}")
        DashboardEvents.broadcast_session_event(:interview, :completed, prefix, updated.student_id)
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:interview, updated.id, prefix)
        {:ok, updated}

      {:error, changeset} ->
        Logger.error("Failed to complete interview: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # Moved here from the LiveView (previously only reachable from the
  # connected, live evaluation-done handler) so every caller of
  # complete_interview/3 — a normal finish or force_complete/2 — publishes
  # the same way. Also preserves the live path's original behavior of using
  # the AI8-weighted module score (super-admin-configured dimension weights)
  # as the STORED overall_score when available, falling back to whatever
  # the caller already put in attrs[:overall_score] (each caller pre-computes
  # a plain average from answered questions for exactly this fallback).
  defp apply_ai8_weighted_score(session, attrs, prefix) do
    metrics = attrs[:session_summary] || attrs["session_summary"] || %{}
    skill_scores = metrics["skill_scores"] || %{}

    if map_size(skill_scores) > 0 and is_binary(prefix) do
      case AI8.publish_evaluation(
             %{
               student_id: session.student_id,
               tenant_id: session.tenant_id,
               module: "interview",
               source_type: "interview_session",
               source_id: session.id,
               skill_scores: skill_scores,
               raw_payload: metrics
             },
             prefix
           ) do
        {:ok, %{module_score: score}} when is_number(score) -> Map.put(attrs, :overall_score, round(score))
        _ -> attrs
      end
    else
      attrs
    end
  end

  @doc """
  Record a content-moderation integrity flag (a warning) on the session without
  ending it. Returns `{:ok, updated}` so the caller can keep the fresh session.
  """
  def add_integrity_flag(session, flag, prefix) when is_binary(flag) do
    session
    |> InterviewSession.add_integrity_flags_changeset([flag])
    |> Repo.update(prefix: prefix)
  end

  @doc """
  Mark an interview terminated for a content-moderation violation, recording
  integrity flag(s) onto the session so the tenant-admin dashboard surfaces them.
  The session is left unscored.
  """
  def mark_terminated(session, flags, prefix) when is_list(flags) do
    case session
         |> InterviewSession.terminate_changeset(flags)
         |> Repo.update(prefix: prefix) do
      {:ok, updated} ->
        Logger.warning("Interview terminated (integrity): #{session.session_token} — #{Enum.join(flags, "; ")}")
        DashboardEvents.broadcast_session_event(:interview, :terminated, prefix, updated.student_id)
        {:ok, updated}

      {:error, changeset} ->
        Logger.error("Failed to mark interview terminated: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def fail_interview(session, error_message, prefix) do
    case session
         |> InterviewSession.fail_changeset(error_message)
         |> Repo.update(prefix: prefix) do
      {:ok, updated} ->
        Logger.info("Interview failed: #{session.session_token} - #{error_message}")
        {:ok, updated}

      {:error, changeset} ->
        Logger.error("Failed to mark interview as failed: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def retry_interview(session, prefix) do
    case session
         |> InterviewSession.retry_changeset()
         |> Repo.update(prefix: prefix) do
      {:ok, updated} ->
        Logger.info("Interview retry initiated: #{session.session_token}")
        {:ok, updated}

      {:error, changeset} ->
        Logger.error("Failed to retry interview: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # ============================================================================
  # QUERY HELPERS
  # ============================================================================

  def list_student_interviews(student_id, prefix) do
    InterviewSession
    |> where(student_id: ^student_id)
    |> order_by([i], desc: i.created_at)
    |> Repo.all(prefix: prefix)
  end

  def get_completed_interviews(student_id, prefix) do
    InterviewSession
    |> where(student_id: ^student_id)
    |> where(status: "completed")
    |> order_by([i], desc: i.completed_at)
    |> Repo.all(prefix: prefix)
  end

  def get_active_interviews(student_id, prefix) do
    InterviewSession
    |> where(student_id: ^student_id)
    |> where([i], i.status not in ["completed", "failed"])
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Integrity flags on a student's interview sessions — content-moderation
  (warnings + terminations) plus proctoring violations (tab/window/fullscreen).
  """
  def student_integrity_flags(student_id, prefix) do
    InterviewSession
    |> where(student_id: ^student_id)
    |> Repo.all(prefix: prefix)
    |> Enum.flat_map(fn s ->
      moderation = get_in(s.session_summary || %{}, ["integrity_flags"]) || []
      moderation ++ interview_proctoring_flags(s.metadata || %{})
    end)
    |> Enum.uniq()
  end

  defp interview_proctoring_flags(meta) do
    case meta["violation_count"] || 0 do
      c when c >= 2 ->
        breakdown =
          (meta["violations"] || [])
          |> Enum.frequencies_by(& &1["type"])
          |> Enum.map(fn {t, n} -> "#{n} #{interview_humanize(t)}" end)
          |> Enum.join(", ")

        detail = if breakdown == "", do: "#{c} focus losses", else: breakdown
        ["Interactive Session — proctoring: #{c} violations (#{detail})"]

      _ ->
        []
    end
  end

  defp interview_humanize("tab_switch"), do: "tab switch"
  defp interview_humanize("window_blur"), do: "window switch"
  defp interview_humanize("fullscreen_exit"), do: "full-screen exit"
  defp interview_humanize(other), do: to_string(other)

  @doc """
  Average score across whatever questions were answered and scored — the same
  fallback the live completion path uses when the full engine's
  metrics/report aren't available. Extracted so it isn't a second
  implementation to keep in sync with `force_complete/2`.
  """
  def average_question_score(questions) when is_list(questions) do
    scores = Enum.map(questions, fn q -> q["score"] || q[:score] || 0 end)
    if scores == [], do: 0, else: Enum.sum(scores) / length(scores)
  end

  def average_question_score(_), do: 0

  @doc """
  Force-completes a session abandoned mid-interview (tab closed / crashed),
  regardless of how many questions were answered — this is the FIRST
  force-submit path this type has ever had; previously the countdown timer
  reaching zero did nothing even for a connected student.

  Scores from whatever questions were already answered
  (`average_question_score/1`) rather than re-invoking the conversational
  engine — its state lives only in the now-dead LiveView process's memory
  (`session_state` in assigns), not in the DB, so there is nothing left to
  resume. If nothing was ever answered, writes a direct zero-score completed
  record.

  Idempotent: a session already in a terminal status
  (`InterviewSession.terminal_status?/1`) is left untouched.
  """
  def force_complete(session_id, prefix) do
    case get_interview_session(session_id, prefix) do
      nil ->
        {:error, :not_found}

      session ->
        if InterviewSession.terminal_status?(session) do
          {:ok, :already_terminal}
        else
          do_force_complete(session, prefix)
        end
    end
  end

  defp do_force_complete(session, prefix) do
    questions = get_in(session.questions_data, ["questions"]) || []
    avg = average_question_score(questions)

    attrs = %{
      overall_score: round(avg),
      final_report: abandoned_report(questions),
      session_summary: %{"abandoned" => true, "answered_questions" => length(questions)},
      strengths: [],
      improvements: []
    }

    complete_interview(session, attrs, prefix)
  end

  defp abandoned_report([]) do
    "This interview was abandoned before any questions were answered."
  end

  defp abandoned_report(questions) do
    "This interview was abandoned after #{length(questions)} question(s) were answered. " <>
      "The score reflects only the questions completed before the session ended."
  end
end
