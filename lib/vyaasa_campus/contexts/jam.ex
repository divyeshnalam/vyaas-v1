defmodule VyaasaCampus.Contexts.Jam do
  @moduledoc """
  The Jam context for managing JAM (Just A Minute) sessions.

  Handles the complete JAM session lifecycle including:
  - Session creation and management
  - Topic generation and decision workflow
  - Audio recording and speech processing
  - AI evaluation and scoring
  - Integration with Python JAM service
  """

  import Ecto.Query, warn: false
  require Logger
  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Jam.JamSession

  # ============================================================================
  # PUBLIC API FUNCTIONS
  # ============================================================================

  @doc """
  Returns all JAM sessions for a student in a tenant.
  """
  def list_jam_sessions(student_id, prefix) do
    JamSession
    |> where(student_id: ^student_id)
    |> order_by([j], desc: j.created_at)
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Get JAM session by ID in a tenant
  """
  def get_jam_session(id, prefix) do
    Repo.get(JamSession, id, prefix: prefix)
  end

  @doc """
  Get JAM session by session token
  """
  def get_jam_session_by_token(session_token, prefix) do
    JamSession
    |> where(session_token: ^session_token)
    |> Repo.one(prefix: prefix)
  end

  @doc "Log a proctoring violation on the JAM session (log-only); returns new count."
  def record_violation(session_token, type, prefix) do
    case get_jam_session_by_token(session_token, prefix) do
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

  @doc "Readable JAM proctoring flags for the admin Integrity panel."
  def student_integrity_flags(student_id, prefix) do
    JamSession
    |> where([s], s.student_id == ^student_id)
    |> Repo.all(prefix: prefix)
    |> Enum.flat_map(fn s -> jam_flags(s.metadata || %{}) end)
    |> Enum.uniq()
  end

  defp jam_flags(meta) do
    case meta["violation_count"] || 0 do
      c when c >= 2 ->
        breakdown =
          (meta["violations"] || [])
          |> Enum.frequencies_by(& &1["type"])
          |> Enum.map(fn {t, n} -> "#{n} #{jam_humanize(t)}" end)
          |> Enum.join(", ")

        detail = if breakdown == "", do: "#{c} focus losses", else: breakdown
        ["JAM — proctoring: #{c} violations (#{detail})"]

      _ ->
        []
    end
  end

  defp jam_humanize("tab_switch"), do: "tab switch"
  defp jam_humanize("window_blur"), do: "window switch"
  defp jam_humanize("fullscreen_exit"), do: "full-screen exit"
  defp jam_humanize(other), do: to_string(other)

  @doc """
  Create a new JAM session for a student
  """
  def create_jam_session(attrs, prefix) do
    student_id = attrs[:student_id] || attrs["student_id"]

    with :ok <- VyaasaCampus.Contexts.AttemptGuard.check(student_id, :jam, prefix) do
      do_create_jam_session(attrs, prefix)
    end
  end

  defp do_create_jam_session(attrs, prefix) do
    case %JamSession{}
         |> JamSession.create_changeset(attrs)
         |> Repo.insert(prefix: prefix) do
      {:ok, jam_session} ->
        Logger.info("JAM session created: #{jam_session.session_token}")
        {:ok, jam_session}

      {:error, changeset} ->
        Logger.error("Failed to create JAM session: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Update JAM session status
  """
  def update_jam_session_status(jam_session, status, prefix) do
    case jam_session
         |> JamSession.status_changeset(status)
         |> Repo.update(prefix: prefix) do
      {:ok, updated_session} ->
        Logger.info("JAM session status updated: #{jam_session.session_token} -> #{status}")
        {:ok, updated_session}

      {:error, changeset} ->
        Logger.error("Failed to update JAM session status: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Update JAM session with topic information
  """
  def update_jam_session_topic(jam_session, topic_attrs, prefix) do
    case jam_session
         |> JamSession.topic_generated_changeset(topic_attrs)
         |> Repo.update(prefix: prefix) do
      {:ok, updated_session} ->
        Logger.info("JAM session topic updated: #{jam_session.session_token}")
        {:ok, updated_session}

      {:error, changeset} ->
        Logger.error("Failed to update JAM session topic: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Update JAM session with topic decision
  """
  def update_jam_session_decision(jam_session, decision_attrs, prefix) do
    case jam_session
         |> JamSession.topic_decision_changeset(decision_attrs)
         |> Repo.update(prefix: prefix) do
      {:ok, updated_session} ->
        Logger.info("JAM session decision updated: #{jam_session.session_token}")
        {:ok, updated_session}

      {:error, changeset} ->
        Logger.error("Failed to update JAM session decision: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Start preparation phase
  """
  def start_preparation(jam_session, prefix) do
    case jam_session
         |> JamSession.start_preparation_changeset()
         |> Repo.update(prefix: prefix) do
      {:ok, updated_session} ->
        Logger.info("JAM session preparation started: #{jam_session.session_token}")
        {:ok, updated_session}

      {:error, changeset} ->
        Logger.error("Failed to start JAM session preparation: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Start speaking phase
  """
  def start_speaking(jam_session, preparation_time_used, prefix) do
    case jam_session
         |> JamSession.start_speaking_changeset(preparation_time_used)
         |> Repo.update(prefix: prefix) do
      {:ok, updated_session} ->
        Logger.info("JAM session speaking started: #{jam_session.session_token}")
        {:ok, updated_session}

      {:error, changeset} ->
        Logger.error("Failed to start JAM session speaking: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Complete speaking phase with audio data
  """
  def complete_speaking(jam_session, speech_time_used, audio_data, prefix) do
    case jam_session
         |> JamSession.complete_speaking_changeset(speech_time_used, audio_data)
         |> Repo.update(prefix: prefix) do
      {:ok, updated_session} ->
        Logger.info("JAM session speaking completed: #{jam_session.session_token}")
        {:ok, updated_session}

      {:error, changeset} ->
        Logger.error("Failed to complete JAM session speaking: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Complete processing with evaluation results
  """
  def complete_processing(jam_session, evaluation_data, prefix) do
    case jam_session
         |> JamSession.processing_complete_changeset(evaluation_data)
         |> Repo.update(prefix: prefix) do
      {:ok, updated_session} ->
        Logger.info("JAM session processing completed: #{jam_session.session_token}")
        DashboardEvents.broadcast_session_event(:jam, :completed, prefix, updated_session.student_id)
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:jam, updated_session.id, prefix)
        publish_ai8(updated_session, prefix)
        {:ok, updated_session}

      {:error, changeset} ->
        Logger.error("Failed to complete JAM session processing: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # Moved here from the LiveView (previously only reachable from the
  # connected, live processing-result handler) so every path that reaches
  # complete_processing/3 — a normal finish or force_complete/2 — publishes
  # the same way. Reads "ai8_scores" back off the just-persisted
  # evaluation_data column rather than taking eval_data as a separate
  # argument, since evaluation_to_completion_attrs/1 already stores the full
  # eval map there. A force-completed session with no real evaluation
  # (abandoned_zero_score_attrs/1) has no "ai8_scores" key, so this cleanly
  # skips rather than publishing fabricated scores.
  defp publish_ai8(session, prefix) do
    skill_scores = (session.evaluation_data || %{})["ai8_scores"] || %{}

    if map_size(skill_scores) > 0 and is_binary(prefix) do
      AI8.publish_evaluation(
        %{
          student_id: session.student_id,
          tenant_id: session.tenant_id,
          module: "jam",
          source_type: "jam_session",
          source_id: session.id,
          skill_scores: skill_scores,
          raw_payload: %{"final_score" => session.final_score}
        },
        prefix
      )
    end
  end

  @doc """
  Mark processing as failed
  """
  def fail_processing(jam_session, error_message, prefix) do
    case jam_session
         |> JamSession.processing_failed_changeset(error_message)
         |> Repo.update(prefix: prefix) do
      {:ok, updated_session} ->
        Logger.info("JAM session processing failed: #{jam_session.session_token} - #{error_message}")
        {:ok, updated_session}

      {:error, changeset} ->
        Logger.error("Failed to mark JAM session as failed: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Retry a failed JAM session
  """
  def retry_jam_session(jam_session, prefix) do
    case jam_session
         |> JamSession.retry_changeset()
         |> Repo.update(prefix: prefix) do
      {:ok, updated_session} ->
        Logger.info("JAM session retry initiated: #{jam_session.session_token}")
        {:ok, updated_session}

      {:error, changeset} ->
        Logger.error("Failed to retry JAM session: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # ============================================================================
  # AI SERVICE INTEGRATION (native Elixir — no Python needed)
  # ============================================================================

  alias VyaasaCampus.AI.JamEngine
  alias VyaasaCampus.AI.Tracing

  # Opik: every AI call of one JAM attempt joins one thread keyed by the
  # jam_session's id. Wrappers below only scope the thread id around the
  # original (unchanged) bodies — results and errors pass through as-is.
  defp jam_thread_id(%{id: id}), do: id
  defp jam_thread_id(_), do: nil

  @doc """
  Generate a JAM topic using native Groq integration.
  """
  def generate_topic(jam_session, preferences \\ %{}) do
    Tracing.with_thread_id(jam_thread_id(jam_session), fn -> do_generate_topic(jam_session, preferences) end)
  end

  defp do_generate_topic(_jam_session, _preferences) do
    case JamEngine.generate_topic() do
      {:ok, topic_data} ->
        Logger.info("Topic generated natively: #{topic_data.topic_title}")
        {:ok, %{
          "topic_title" => topic_data.topic_title,
          "topic_explanation" => topic_data.topic_explanation,
          "guidance" => topic_data.guidance,
          "audio_data" => topic_data.audio_data,
          "audio_type" => topic_data.audio_type
        }}

      {:error, reason} ->
        Logger.error("Failed to generate topic: #{inspect(reason)}")
        {:error, {:service_error, reason}}
    end
  end

  @doc """
  Explain a topic in more detail using native Groq integration.
  """
  def explain_topic(topic_title) do
    case JamEngine.explain_topic(topic_title) do
      {:ok, data} ->
        Logger.info("Topic explanation generated for: #{topic_title}")
        {:ok, %{
          "explanation" => data.explanation,
          "audio_data" => data.audio_data,
          "audio_type" => data.audio_type
        }}

      {:error, reason} ->
        Logger.error("Failed to explain topic: #{inspect(reason)}")
        {:error, {:service_error, reason}}
    end
  end

  @doc """
  Generate a different topic using native Groq integration.
  """
  def change_topic(jam_session, previous_topic) do
    Tracing.with_thread_id(jam_thread_id(jam_session), fn -> do_change_topic(jam_session, previous_topic) end)
  end

  defp do_change_topic(_jam_session, previous_topic) do
    case JamEngine.change_topic(previous_topic) do
      {:ok, topic_data} ->
        Logger.info("Topic changed natively, new: #{topic_data.topic_title}")
        {:ok, %{
          "topic_title" => topic_data.topic_title,
          "topic_explanation" => topic_data.topic_explanation,
          "guidance" => topic_data.guidance,
          "audio_data" => topic_data.audio_data,
          "audio_type" => topic_data.audio_type
        }}

      {:error, reason} ->
        Logger.error("Failed to change topic: #{inspect(reason)}")
        {:error, {:service_error, reason}}
    end
  end

  @doc """
  Process audio: transcribe + evaluate using native Groq integration.
  No Python service needed — sends audio directly to Groq Whisper API.
  """
  def process_audio(jam_session, audio_file_path) do
    Tracing.with_thread_id(jam_thread_id(jam_session), fn -> do_process_audio(jam_session, audio_file_path) end)
  end

  defp do_process_audio(jam_session, audio_file_path) do
    topic_title = jam_session.topic_title || ""

    duration =
      jam_session.actual_speech_time_used || jam_session.recording_duration_seconds ||
        jam_session.speech_time_seconds

    case JamEngine.process_audio(audio_file_path, topic_title, duration, jam_session.topic_explanation) do
      {:ok, result} ->
        Logger.info("Audio processed natively for session: #{jam_session.session_token}")
        {:ok, result}

      {:error, %{message: message} = info} ->
        Logger.error("Audio processing failed: #{message}")
        {:error, {:validation_error, info}}

      {:error, reason} ->
        Logger.error("Audio processing failed: #{inspect(reason)}")
        {:error, {:service_error, reason}}
    end
  end

  # ============================================================================
  # SESSION LIFECYCLE MANAGEMENT
  # ============================================================================

  @doc """
  Get active JAM sessions for a student
  """
  def get_active_jam_sessions(student_id, prefix) do
    JamSession
    |> where(student_id: ^student_id)
    |> where([j], j.status not in ["completed", "failed"])
    |> order_by([j], desc: j.created_at)
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Get completed JAM sessions for a student
  """
  def get_completed_jam_sessions(student_id, prefix) do
    JamSession
    |> where(student_id: ^student_id)
    |> where(status: "completed")
    |> order_by([j], desc: j.completed_at)
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Clean up expired JAM sessions
  """
  def cleanup_expired_sessions(prefix, hours_old \\ 24) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -hours_old, :hour)

    JamSession
    |> where([j], j.created_at < ^cutoff_time)
    |> where([j], j.status in ["created", "topic_generated", "decision_phase", "preparation", "speaking"])
    |> Repo.delete_all(prefix: prefix)
    |> case do
      {count, _} ->
        Logger.info("Cleaned up #{count} expired JAM sessions")
        {:ok, count}
    end
  end

  @doc """
  Get JAM session statistics for a student
  """
  def get_jam_session_stats(student_id, prefix) do
    total_sessions =
      JamSession
      |> where(student_id: ^student_id)
      |> Repo.aggregate(:count, prefix: prefix)

    completed_sessions =
      JamSession
      |> where(student_id: ^student_id)
      |> where(status: "completed")
      |> Repo.aggregate(:count, prefix: prefix)

    avg_score =
      JamSession
      |> where(student_id: ^student_id)
      |> where(status: "completed")
      |> where([j], not is_nil(j.final_score))
      |> Repo.aggregate(:avg, :final_score, prefix: prefix)

    %{
      total_sessions: total_sessions,
      completed_sessions: completed_sessions,
      success_rate: if(total_sessions > 0, do: completed_sessions / total_sessions, else: 0),
      average_score: avg_score
    }
  end

  # ============================================================================
  # VALIDATION HELPERS
  # ============================================================================

  @doc """
  Validate if a student can start a new JAM session
  """
  def can_start_new_session?(student_id, prefix) do
    active_sessions = get_active_jam_sessions(student_id, prefix)
    Enum.empty?(active_sessions)
  end

  @doc """
  Validate session status transition
  """
  def valid_status_transition?(current_status, new_status) do
    valid_transitions = %{
      "created" => ["topic_generated", "failed"],
      "topic_generated" => ["decision_phase", "failed"],
      "decision_phase" => ["preparation", "failed"],
      "preparation" => ["speaking", "failed"],
      "speaking" => ["processing", "failed"],
      "processing" => ["completed", "failed"],
      "failed" => ["created"] # for retry
    }

    valid_transitions
    |> Map.get(current_status, [])
    |> Enum.member?(new_status)
  end

  # ============================================================================
  # BACKGROUND JOB HELPERS
  # ============================================================================

  @doc """
  Process JAM session asynchronously
  """
  def process_jam_session_async(jam_session, audio_data, prefix) do
    # This would typically enqueue a background job
    # For now, we'll process synchronously
    case process_audio(jam_session, audio_data) do
      {:ok, evaluation_data} ->
        complete_processing(jam_session, evaluation_data, prefix)

      {:error, reason} ->
        fail_processing(jam_session, "Audio processing failed: #{inspect(reason)}", prefix)
    end
  end

  # ============================================================================
  # SESSION VALIDATION HELPERS
  # ============================================================================

  @doc """
  Check if session can be retried
  """
  def can_retry?(%JamSession{status: "failed", retry_count: retry_count}) do
    retry_count < 3
  end
  def can_retry?(_), do: false

  @doc """
  Maps a raw evaluation result (from `process_audio/2`, string-keyed) onto
  `complete_processing/3`'s attrs shape. Extracted so the LiveView's normal
  completion path and `force_complete/2`'s abandoned-session path score
  through the exact same mapping — one implementation, not two to keep in
  sync.
  """
  def evaluation_to_completion_attrs(eval_data) do
    %{
      transcript: eval_data["transcript"] || "",
      word_count: eval_data["word_count"],
      speech_duration_seconds: eval_data["speech_duration_seconds"],
      final_score: eval_data["final_score"],
      clarity_score: eval_data["clarity_score"],
      structure_score: eval_data["structure_score"],
      relevance_score: eval_data["relevance_score"],
      impact_score: eval_data["impact_score"],
      confidence_score: eval_data["confidence_score"],
      overall_summary: eval_data["overall_summary"],
      evaluation_data: eval_data
    }
  end

  @terminal_statuses ~w(completed failed)

  @doc """
  Force-completes a session abandoned mid-attempt (tab closed / crashed),
  regardless of which phase it reached.

  If a speaking recording was captured AND its temp file still exists on
  disk, evaluates it for real through the same `process_audio/2` +
  `complete_processing/3` pipeline a normal completion uses (the async
  evaluation task keeps running via `Task.Supervisor` even after the LiveView
  dies — this covers the case where recording finished but the tab closed
  before the result could be written back). Otherwise — never reached
  speaking, or the temp recording is gone by the time this runs — writes a
  direct zero-score completed record; there is nothing left to meaningfully
  evaluate, so no point spending an LLM call to learn that.

  Idempotent: a session already in a terminal status is left untouched, so
  this is safe to call from both `terminate/2` and the abandonment sweep
  without risking a double-completion.
  """
  def force_complete(session_id, prefix) do
    case get_jam_session(session_id, prefix) do
      nil ->
        {:error, :not_found}

      %{status: status} when status in @terminal_statuses ->
        {:ok, :already_terminal}

      session ->
        do_force_complete(session, prefix)
    end
  end

  defp do_force_complete(session, prefix) do
    # Opik filter labels for the re-scoring trace (runs in the finalizer job, no LiveView).
    VyaasaCampus.AI.Tracing.put_metadata(%{student_id: session.student_id, module: "jam", tenant: prefix})

    path = session.recording_file_path

    if is_binary(path) and File.exists?(path) do
      case process_audio(session, path) do
        {:ok, eval_data} ->
          complete_processing(session, evaluation_to_completion_attrs(eval_data), prefix)

        {:error, reason} ->
          Logger.warning("JAM force_complete: re-evaluation failed for #{session.id}: #{inspect(reason)}")
          complete_processing(session, abandoned_zero_score_attrs(reason), prefix)
      end
    else
      complete_processing(session, abandoned_zero_score_attrs(:no_recording), prefix)
    end
  end

  defp abandoned_zero_score_attrs(reason) do
    summary =
      case reason do
        :no_recording -> "Session was abandoned before any response was recorded."
        other -> "Session was abandoned and automated re-scoring failed: #{inspect(other)}"
      end

    %{
      # validate_required treats "" as blank on a string field — a real
      # placeholder is needed, not empty.
      transcript: "(no response recorded)",
      final_score: 0,
      # clarity/structure/relevance/impact are on a 1-10 scale
      # (validate_number greater_than_or_equal_to: 1) — 0 would fail the
      # changeset, unlike final_score which is 0-100.
      clarity_score: 1,
      structure_score: 1,
      relevance_score: 1,
      impact_score: 1,
      confidence_score: 1,
      overall_summary: summary,
      evaluation_data: %{"abandoned" => true, "reason" => to_string(reason)}
    }
  end
end
