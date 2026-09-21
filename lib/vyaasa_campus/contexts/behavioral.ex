defmodule VyaasaCampus.Contexts.Behavioral do
  @moduledoc """
  Context for the Behavioral Assessment service.
  Uses the native Elixir engine — no Python service needed.

  Session state is managed in-process (ETS or LiveView assigns).
  The engine handles multi-turn conversation, scenario generation, and evaluation.
  """

  import Ecto.Query, warn: false
  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.StudentBehavioralAssessment
  alias VyaasaCampus.AI.BehavioralEngine

  require Logger

  # ============================================================================
  # SESSION LIFECYCLE (native Elixir — no Python)
  # ============================================================================

  @doc """
  Start a new behavioral assessment session.

  Accepts the student's id and full_name (pulled from the student record —
  no in-conversation profile collection).

  Returns `{:ok, %{session_id, session_state, response}}` with the hard-coded
  greeting (no LLM call).
  """
  def start_session(student_id, full_name \\ "Candidate") do
    session_id = Ecto.UUID.generate()
    session_state = BehavioralEngine.new_session(session_id, student_id, full_name)

    {:ok, new_state, response} = BehavioralEngine.process_turn(session_state)

    Logger.info(
      "BEHAVIORAL | Session started | session=#{session_id} student=#{student_id}"
    )

    {:ok, %{session_id: session_id, session_state: new_state, response: response}}
  end

  @doc """
  Advance the session by one turn with a free-text message.
  Returns `{:ok, new_state, response}`.
  """
  def send_message(session_state, message) do
    BehavioralEngine.process_turn(session_state, message)
  end

  @doc """
  Submit a scenario choice (1 or 2). Used during the `:presenting` phase.
  """
  def choose_scenario(session_state, choice) when choice in [1, 2] do
    BehavioralEngine.process_turn(session_state, nil, choice)
  end

  @doc """
  Submit the candidate's STAR answer. Used during the `:answering` phase.
  """
  def submit_answer(session_state, response) do
    BehavioralEngine.process_turn(session_state, response)
  end

  @doc """
  Force-end a session early (proctoring auto-finalize). See
  `BehavioralEngine.force_finish/1`.
  """
  def force_finish(session_state), do: BehavioralEngine.force_finish(session_state)

  # ============================================================================
  # DATABASE OPERATIONS
  # ============================================================================

  @doc """
  Creates a new behavioral assessment record when a session starts.
  """
  def create_assessment(student_id, tenant_id, session_id, tenant_schema \\ "public") do
    with :ok <- VyaasaCampus.Contexts.AttemptGuard.check(student_id, :behavioral, tenant_id, tenant_schema) do
      do_create_assessment(student_id, tenant_id, session_id, tenant_schema)
    end
  end

  defp do_create_assessment(student_id, tenant_id, session_id, tenant_schema) do
    attempt_number = next_attempt_number(student_id, tenant_schema)

    StudentBehavioralAssessment.start_changeset(%{
      student_id: student_id,
      tenant_id: tenant_id,
      session_id: session_id,
      attempt_number: attempt_number
    })
    |> Repo.insert(prefix: tenant_schema)
  end

  @doc """
  Saves the completed report to the database.
  """
  def save_report(session_id, report_response, tenant_schema \\ "public") do
    case get_assessment_by_session(session_id, tenant_schema) do
      nil ->
        Logger.error("No behavioral assessment found for session: #{session_id}")
        {:error, :not_found}

      assessment ->
        assessment
        |> StudentBehavioralAssessment.complete_changeset(report_response)
        |> Repo.update(prefix: tenant_schema)
        |> case do
          {:ok, updated} = ok ->
            DashboardEvents.broadcast_session_event(:behavioral, :completed, tenant_schema, updated.student_id)
            publish_ai8(updated, tenant_schema)
            VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:behavioral, updated.id, tenant_schema)
            ok

          other ->
            other
        end
    end
  end

  # Publish behavioral competency scores into the AI8 framework. The behavioral
  # engine's 5 competencies map directly onto AI8 dimensions.
  defp publish_ai8(assessment, tenant_schema) do
    # NOTE: the `communication_score` column holds the 5th competency, which the
    # dev-behavioral engine assesses as Cultural Fit & EQ (it maps
    # cultural_fit → communication_rating). So it feeds the AI8 cultural_fit
    # dimension, matching the production config (behavioral has no communication).
    scores = %{
      "work_ethics" => assessment.work_ethics_score,
      "collaboration" => assessment.teamwork_score,
      "adaptability" => assessment.adaptability_score,
      "leadership" => assessment.leadership_score,
      "cultural_fit" => assessment.communication_score
    }

    AI8.publish_module(
      "behavioral",
      scores,
      %{
        student_id: assessment.student_id,
        tenant_id: assessment.tenant_id,
        source_type: "student_behavioral_assessment",
        source_id: assessment.id
      },
      tenant_schema
    )
  end

  @doc """
  Updates the status of a behavioral assessment.
  """
  def update_assessment_status(session_id, status, tenant_schema \\ "public") do
    case get_assessment_by_session(session_id, tenant_schema) do
      nil ->
        {:error, :not_found}

      assessment ->
        assessment
        |> StudentBehavioralAssessment.status_changeset(status)
        |> Repo.update(prefix: tenant_schema)
    end
  end

  @doc """
  Gets a behavioral assessment by session_id.
  """
  def get_assessment_by_session(session_id, tenant_schema \\ "public") do
    Repo.get_by(StudentBehavioralAssessment, [session_id: session_id], prefix: tenant_schema)
  end

  @doc """
  Records a proctoring violation on the behavioral session and returns the new
  total count. `type` is "tab_switch" | "window_blur" | "fullscreen_exit".
  Log-only (the assessment is never cut off) — surfaced to admins afterwards.
  """
  def record_violation(session_id, type, tenant_schema \\ "public") do
    case get_assessment_by_session(session_id, tenant_schema) do
      nil ->
        {:error, :not_found}

      assessment ->
        meta = assessment.metadata || %{}
        entry = %{"type" => type, "at" => DateTime.utc_now() |> DateTime.to_iso8601()}
        violations = (meta["violations"] || []) ++ [entry]
        count = length(violations)
        meta = meta |> Map.put("violations", violations) |> Map.put("violation_count", count)

        case assessment |> Ecto.Changeset.change(metadata: meta) |> Repo.update(prefix: tenant_schema) do
          {:ok, _} -> {:ok, count}
          {:error, _} = err -> err
        end
    end
  end

  @doc """
  Readable proctoring flags across a student's behavioral attempts, for the
  admin Integrity panel. Empty unless a session logged >= 2 violations.
  """
  def student_integrity_flags(student_id, prefix) do
    StudentBehavioralAssessment
    |> where(student_id: ^student_id)
    |> Repo.all(prefix: prefix)
    |> Enum.flat_map(fn a -> behavioral_violation_flags(a.metadata || %{}) end)
    |> Enum.uniq()
  end

  defp behavioral_violation_flags(meta) do
    violations = meta["violations"] || []
    count = meta["violation_count"] || length(violations)

    if count >= 2 do
      breakdown =
        violations
        |> Enum.frequencies_by(& &1["type"])
        |> Enum.map(fn {t, c} -> "#{c} #{humanize_violation(t)}" end)
        |> Enum.join(", ")

      detail = if breakdown == "", do: "#{count} focus losses", else: breakdown
      ["Behavioral — proctoring: #{count} violations (#{detail})"]
    else
      []
    end
  end

  defp humanize_violation("tab_switch"), do: "tab switch"
  defp humanize_violation("window_blur"), do: "window switch"
  defp humanize_violation("fullscreen_exit"), do: "full-screen exit"
  defp humanize_violation(other), do: to_string(other)

  @doc """
  Gets the latest behavioral assessment for a student.
  """
  def get_latest_assessment(student_id, tenant_schema \\ "public") do
    from(ba in StudentBehavioralAssessment,
      where: ba.student_id == ^student_id,
      order_by: [desc: ba.attempt_number],
      limit: 1
    )
    |> Repo.one(prefix: tenant_schema)
  end

  @doc """
  Gets all behavioral assessments for a student.
  """
  def list_student_assessments(student_id, tenant_schema \\ "public") do
    from(ba in StudentBehavioralAssessment,
      where: ba.student_id == ^student_id,
      order_by: [desc: ba.inserted_at]
    )
    |> Repo.all(prefix: tenant_schema)
  end

  @doc """
  Gets all behavioral assessments for a tenant with optional filters.
  """
  def list_by_tenant(tenant_id, opts \\ [], tenant_schema \\ "public") do
    query = from(ba in StudentBehavioralAssessment, where: ba.tenant_id == ^tenant_id)

    query =
      if status = opts[:status] do
        from(ba in query, where: ba.status == ^status)
      else
        query
      end

    query = from(ba in query, order_by: [desc: ba.inserted_at])

    Repo.all(query, prefix: tenant_schema)
  end

  @doc """
  Checks if a student has a completed behavioral assessment.
  """
  def assessment_completed?(student_id, tenant_schema \\ "public") do
    case get_latest_assessment(student_id, tenant_schema) do
      %StudentBehavioralAssessment{status: "completed"} -> true
      _ -> false
    end
  end

  @doc """
  Gets the overall behavioral score for a student (latest completed attempt).
  """
  def get_student_score(student_id, tenant_schema \\ "public") do
    case get_latest_assessment(student_id, tenant_schema) do
      %StudentBehavioralAssessment{status: "completed", overall_score: score} -> score || 0
      _ -> 0
    end
  end

  defp next_attempt_number(student_id, tenant_schema) do
    case from(ba in StudentBehavioralAssessment,
           where: ba.student_id == ^student_id,
           select: max(ba.attempt_number)
         )
         |> Repo.one(prefix: tenant_schema) do
      nil -> 1
      max -> max + 1
    end
  end

  @terminal_statuses ~w(completed failed)

  @doc """
  Force-completes an assessment abandoned mid-conversation (tab closed /
  crashed).

  Unlike JAM/Interview, there is genuinely nothing partial to recover here:
  per-scenario ratings/reasoning live only in the conversational engine's
  in-memory state (`session_state`, held in LiveView assigns) and are written
  to the DB in one shot at final completion (`save_report/3`) — nothing is
  persisted incrementally as the student answers, unlike JAM's recording path
  or Interview's `questions_data`. So this always writes a direct zero-score
  completed record; there is no "partial evaluation" branch possible.

  Reuses `save_report/3` with an empty report — its own field extraction
  (`complete_changeset/2`) already defaults every score/list/map to
  zero/empty when absent, so this isn't a second completion shape to keep in
  sync.

  Idempotent: a session already in a terminal status is left untouched.
  """
  def force_complete(session_id, prefix) do
    case get_assessment_by_session(session_id, prefix) do
      nil ->
        {:error, :not_found}

      %{status: status} when status in @terminal_statuses ->
        {:ok, :already_terminal}

      _assessment ->
        report = %{
          "report" => %{
            "summary" => "This behavioral assessment was abandoned before completion.",
            "overall_score" => 0
          }
        }

        save_report(session_id, report, prefix)
    end
  end
end
