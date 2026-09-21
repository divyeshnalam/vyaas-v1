defmodule VyaasaCampus.Contexts.Assessments do
  @moduledoc """
  The Assessments context for managing assessments and attempts within a tenant.
  Handles assessment creation, publishing, and student attempts with scoring.
  """

  import Ecto.Query, warn: false
  import VyaasaCampus.Types
  require Logger
  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.Contexts.AssessmentConfigs
  alias VyaasaCampus.Contexts.Jobs
  alias VyaasaCampus.Contexts.StudentAts
  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampus.Jobs.ReportGenerator
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Assessments.{Assessment, AssessmentAttempt}
  alias VyaasaCampus.Schema.Students.Student
  alias VyaasaCampus.Schema.Accounts.User

  # ============================================================================
  # ASSESSMENT MANAGEMENT
  # ============================================================================

  @doc """
  Lists all assessments in a tenant
  """
  def list_assessments(prefix) do
    Assessment
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Lists published assessments in a tenant
  """
  def list_published_assessments(prefix) do
    Assessment
    |> where([a], a.status == ^assessment_status_published())
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Gets a specific assessment
  """
  def get_assessment!(id, prefix) do
    Repo.get!(Assessment, id, prefix: prefix)
  end

  @doc """
  Creates a new assessment
  """
  def create_assessment(attrs, prefix) do
    # Only convert if attrs are string keys, otherwise use as-is
    safe_attrs =
      if is_map(attrs) and Map.keys(attrs) |> Enum.any?(&is_binary/1) do
        safe_atom_conversion(attrs)
      else
        attrs
      end

    case %Assessment{}
         |> Assessment.changeset(safe_attrs)
         |> Repo.insert(prefix: prefix) do
      {:ok, assessment} ->
        Logger.info("Assessment created: #{assessment.title}")
        {:ok, assessment}

      {:error, changeset} ->
        Logger.error("Failed to create assessment: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Updates an assessment
  """
  def update_assessment(assessment, attrs, prefix) do
    safe_attrs = safe_atom_conversion(attrs)

    assessment
    |> Assessment.changeset(safe_attrs)
    |> Repo.update(prefix: prefix)
    |> case do
      {:ok, updated_assessment} ->
        Logger.info("Assessment updated: #{updated_assessment.title}")
        {:ok, updated_assessment}

      {:error, changeset} ->
        Logger.error("Failed to update assessment: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Publishes an assessment
  """
  def publish_assessment(assessment, prefix) do
    update_assessment(assessment, %{status: assessment_status_published()}, prefix)
  end

  @doc """
  Archives an assessment
  """
  def archive_assessment(assessment, prefix) do
    update_assessment(assessment, %{status: assessment_status_archived()}, prefix)
  end

  @doc """
  Deletes an assessment
  """
  def delete_assessment(assessment, prefix) do
    Repo.delete(assessment, prefix: prefix)
    |> case do
      {:ok, deleted_assessment} ->
        Logger.info("Assessment deleted: #{deleted_assessment.title}")
        {:ok, deleted_assessment}

      {:error, changeset} ->
        Logger.error("Failed to delete assessment: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # ============================================================================
  # ASSESSMENT ATTEMPT MANAGEMENT
  # ============================================================================

  @doc """
  Starts an assessment attempt for a student
  """
  def start_assessment_attempt(assessment_id, student_id, prefix) do
    # Check if student already has an active attempt
    case get_active_attempt(assessment_id, student_id, prefix) do
      nil ->
        # Also check for already submitted attempts (prevent retake)
        case get_submitted_attempt(assessment_id, student_id, prefix) do
          nil ->
            # Create new attempt
            case create_attempt(assessment_id, student_id, prefix) do
              {:ok, attempt} ->
                Logger.info("Assessment attempt started: assessment_id=#{assessment_id}, student_id=#{student_id}")
                {:ok, attempt}

              {:error, changeset} ->
                Logger.error("Failed to start assessment attempt: #{inspect(changeset.errors)}")
                {:error, changeset}
            end

          _submitted ->
            {:error, :already_submitted}
        end

      existing_attempt ->
        # Return the existing attempt so the user can resume
        Logger.info("Resuming active attempt: #{existing_attempt.id}")
        {:ok, existing_attempt}
    end
  end

  @doc """
  Starts an assessment for a student (alias for start_assessment_attempt)
  """
  def start_assessment(assessment_id, student_id, prefix) do
    start_assessment_attempt(assessment_id, student_id, prefix)
  end

  @doc """
  Creates a brand-new attempt for retake. Bypasses the "already submitted"
  guard by incrementing attempt_number, so previous attempts stay in history.
  """
  def restart_assessment_attempt(assessment_id, student_id, prefix) do
    student_id = if is_binary(student_id), do: student_id, else: to_string(student_id)

    next_num =
      AssessmentAttempt
      |> where([a], a.assessment_id == ^assessment_id and a.student_id == ^student_id)
      |> Repo.aggregate(:max, :attempt_number, prefix: prefix)
      |> case do
        nil -> 1
        n -> n + 1
      end

    %AssessmentAttempt{
      assessment_id: assessment_id,
      student_id: student_id,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second),
      status: attempt_status_started(),
      attempt_number: next_num
    }
    |> AssessmentAttempt.changeset(%{})
    |> Repo.insert(prefix: prefix)
  end

  @doc """
  Retake with a **fresh** question set (Vya-001).

  Generates a brand-new dynamic assessment — newly randomised questions (and,
  with the role blueprint, a fresh draw) — and starts attempt #1 on it, instead
  of re-serving the previous assessment's identical questions in the same order.
  Returns `{:ok, assessment, attempt}` or an error (e.g. `:no_questions_available`).
  """
  def retake_with_new_assessment(student_id, prefix) do
    with :ok <- VyaasaCampus.Contexts.AttemptGuard.check(student_id, :mcq, prefix),
         {:ok, assessment} <- create_dynamic_assessment_for_student(student_id, prefix),
         {:ok, attempt} <- restart_assessment_attempt(assessment.id, student_id, prefix) do
      {:ok, assessment, attempt}
    end
  end

  @doc """
  Force-submits an assessment attempt, bypassing the minimum-time guard.
  Used only for auto-submit when the timer expires (server or client side).
  """
  def force_submit_assessment(attempt_id, answers, prefix) do
    case Repo.get(AssessmentAttempt, attempt_id, prefix: prefix) do
      nil ->
        {:error, :attempt_not_found}

      attempt ->
        if attempt.status not in [attempt_status_started(), attempt_status_in_progress()] do
          {:ok, attempt}
        else
          do_submit_assessment(attempt, answers, prefix)
        end
    end
  end

  @doc """
  Submits an assessment attempt.
  Guards against double submission — only allows submit from started/in_progress status.
  Also enforces a minimum elapsed time (1 second per question) to prevent impossibly
  fast submissions that indicate automated cheating.
  """
  def submit_assessment(attempt_id, answers, prefix) do
    case Repo.get(AssessmentAttempt, attempt_id, prefix: prefix) do
      nil ->
        {:error, :attempt_not_found}

      attempt ->
        # Guard: only allow submission from active statuses
        if attempt.status not in [attempt_status_started(), attempt_status_in_progress()] do
          Logger.warning("Attempt #{attempt_id} already submitted (status: #{attempt.status})")
          {:ok, attempt}
        else
          # Guard: enforce minimum elapsed time (1 second per question answered)
          # A student cannot legitimately answer questions faster than 1 second each
          with :ok <- check_minimum_submission_time(attempt, answers, prefix) do
            do_submit_assessment(attempt, answers, prefix)
          end
        end
    end
  end

  # Enforces minimum time before allowing submission.
  # Rule: elapsed time must be >= number_of_answered_questions * 1 second
  # (minimum 10 seconds total regardless).
  defp check_minimum_submission_time(attempt, answers, prefix) do
    assessment = Repo.get(Assessment, attempt.assessment_id, prefix: prefix)
    total_questions = if assessment, do: length(assessment.settings["questions"] || []), else: 0

    elapsed_seconds =
      if attempt.started_at do
        DateTime.diff(DateTime.utc_now(), attempt.started_at, :second)
      else
        0
      end

    answered_count = map_size(answers)
    # Minimum: 1 second per answered question, at least 10 seconds total
    min_seconds = max(10, answered_count * 1)

    if elapsed_seconds < min_seconds do
      Logger.warning(
        "Suspicious submission: attempt #{attempt.id} submitted after only #{elapsed_seconds}s " <>
          "with #{answered_count}/#{total_questions} answers (minimum #{min_seconds}s required)"
      )
      {:error, :submitted_too_fast}
    else
      :ok
    end
  end

  defp do_submit_assessment(attempt, answers, prefix) do
    case Repo.get(Assessment, attempt.assessment_id, prefix: prefix) do
      nil ->
        {:error, :assessment_not_found}

      assessment ->
        questions = assessment.settings["questions"] || []
        negative_marking = assessment.settings["negative_marking"] || 0.25
        detailed = calculate_detailed_score(answers, questions, negative_marking)

        score = detailed.score
        total = assessment.total_marks || 0

        percentage =
          if total > 0 do
            min(100.0, max(0.0, score / total * 100))
          else
            0.0
          end

        # Clamp score to 0 minimum for storage (negative scores display via evaluation_data)
        clamped_score = max(0.0, score)

        # Detect suspicious answer patterns and log them
        integrity_flags = detect_integrity_issues(answers, questions, attempt)

        evaluation_data = %{
          "correct" => detailed.correct,
          "wrong" => detailed.wrong,
          "unanswered" => detailed.unanswered,
          "negative_marks" => Float.round(detailed.negative, 2),
          "gross_score" => detailed.correct,
          "net_score" => Float.round(score, 2),
          "total_marks" => total,
          "total_questions" => length(questions),
          "integrity_flags" => integrity_flags
        }

        attempt
        |> AssessmentAttempt.changeset(%{
          submitted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          status: attempt_status_submitted(),
          answers: answers,
          score: Decimal.new(to_string(Float.round(clamped_score, 2))),
          percentage: Decimal.new(to_string(Float.round(percentage, 2))),
          obtained_marks: detailed.correct,
          total_marks: total,
          evaluation_data: evaluation_data
        })
        |> Repo.update(prefix: prefix)
        |> case do
          {:ok, updated_attempt} ->
            Logger.info(
              "Assessment submitted: attempt=#{attempt.id}, correct=#{detailed.correct}, wrong=#{detailed.wrong}, score=#{Float.round(score, 2)}"
            )

            DashboardEvents.broadcast_assessment_event(:submitted, prefix, updated_attempt.student_id)
            enqueue_report_email(:mcq, updated_attempt, prefix)

            # Publish MCQ result into AI8: the percentage reflects domain
            # knowledge and problem-solving (filtered to whatever the admin
            # configured for the mcq module).
            mcq_pct = round(percentage)

            AI8.publish_module(
              "mcq",
              %{"domain_expertise" => mcq_pct, "problem_solving" => mcq_pct},
              %{
                student_id: updated_attempt.student_id,
                source_type: "assessment_attempt",
                source_id: updated_attempt.id
              },
              prefix
            )

            {:ok, updated_attempt}

          {:error, changeset} ->
            Logger.error("Failed to submit assessment attempt: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end

  @doc """
  Completes an assessment attempt with final scoring
  """
  def complete_assessment_attempt(attempt_id, score, percentage, prefix) do
    attempt = Repo.get!(AssessmentAttempt, attempt_id, prefix: prefix)

    attempt
    |> AssessmentAttempt.complete_attempt_changeset(score, percentage)
    |> Repo.update(prefix: prefix)
    |> case do
      {:ok, completed_attempt} ->
        Logger.info("Assessment attempt completed: attempt_id=#{attempt_id}, score=#{score}, percentage=#{percentage}")

        DashboardEvents.broadcast_assessment_event(:completed, prefix, completed_attempt.student_id)

        {:ok, completed_attempt}

      {:error, changeset} ->
        Logger.error("Failed to complete assessment attempt: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Gets a specific assessment attempt
  """
  def get_attempt(attempt_id, prefix) do
    Repo.get(AssessmentAttempt, attempt_id, prefix: prefix)
  end

  @doc """
  Gets a specific assessment attempt, raises if not found
  """
  def get_attempt!(attempt_id, prefix) do
    Repo.get!(AssessmentAttempt, attempt_id, prefix: prefix)
  end

  @doc """
  Saves answers to an in-progress attempt (for persistence across page reloads).
  Also persists per-question answer timestamps and change counts into metadata
  for integrity analysis at submission time.
  """
  def save_answers(attempt_id, answers, answer_timestamps \\ %{}, answer_change_counts \\ %{}, prefix) do
    attempt = Repo.get(AssessmentAttempt, attempt_id, prefix: prefix)

    if attempt && attempt.status in [attempt_status_started(), attempt_status_in_progress()] do
      updated_metadata =
        (attempt.metadata || %{})
        |> Map.put("answer_timestamps", answer_timestamps)
        |> Map.put("answer_change_counts", answer_change_counts)

      attempt
      |> AssessmentAttempt.changeset(%{
        answers: answers,
        status: attempt_status_in_progress(),
        metadata: updated_metadata
      })
      |> Repo.update(prefix: prefix)
    else
      {:error, :attempt_not_active}
    end
  end

  @doc """
  Lists all attempts for a student
  """
  def list_student_attempts(student_id, prefix) do
    AssessmentAttempt
    |> where(student_id: ^student_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Lists all attempts for an assessment
  """
  def list_assessment_attempts(assessment_id, prefix) do
    AssessmentAttempt
    |> where(assessment_id: ^assessment_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Resets a student's assessment by deleting all their attempts.
  This allows the student to retake the assessment.
  """
  def reset_student_assessment(student_id, prefix) do
    student_id = if is_binary(student_id), do: student_id, else: to_string(student_id)

    {count, _} =
      AssessmentAttempt
      |> where([a], a.student_id == ^student_id)
      |> Repo.delete_all(prefix: prefix)

    Logger.info("Reset assessment for student #{student_id}: deleted #{count} attempt(s)")
    DashboardEvents.broadcast_assessment_event(:reset, prefix, student_id)
    {:ok, count}
  end

  @doc """
  Gets the latest submitted attempt for a student (across all assessments).
  Used to check if a student has completed their test.
  """
  def get_student_latest_submitted_attempt(student_id, prefix) do
    student_id = if is_binary(student_id), do: student_id, else: to_string(student_id)

    AssessmentAttempt
    |> where([a], a.student_id == ^student_id and a.status == ^attempt_status_submitted())
    |> order_by([a], desc: a.submitted_at)
    |> limit(1)
    |> Repo.one(prefix: prefix)
  end

  @doc """
  The latest SUBMITTED attempt for a specific assessment, by submission time.
  The result screen must show this — not the newest-*started* attempt — so a
  retake that was submitted last is shown even if an earlier attempt was started
  first.
  """
  def get_latest_submitted_attempt(assessment_id, student_id, prefix) do
    student_id = if is_binary(student_id), do: student_id, else: to_string(student_id)

    AssessmentAttempt
    |> where([a], a.assessment_id == ^assessment_id and a.student_id == ^student_id)
    |> where([a], a.status == ^attempt_status_submitted())
    |> order_by([a], desc: a.submitted_at)
    |> limit(1)
    |> Repo.one(prefix: prefix)
  end

  # ============================================================================
  # DYNAMIC ASSESSMENT GENERATION
  # ============================================================================

  @doc """
  Creates a dynamic assessment for a student based on their curriculum and branch.
  Uses the SQL function `create_question_set` to generate personalized questions.

  NOTE: student_id parameter is actually the student's ID from the students table.
  We need to find the corresponding user_id for the created_by field.
  """
  def create_dynamic_assessment_for_student(student_id, prefix, opts \\ []) do
    # Get student record
    student = Repo.get(Student, student_id, prefix: prefix)

    if is_nil(student) do
      {:error, :student_not_found}
    else
      # Find corresponding user by email
      user_id = get_user_id_for_student(student, prefix)

      if is_nil(user_id) do
        {:error, :user_not_found_for_student}
      else
        create_assessment_for_student(student, user_id, prefix, opts)
      end
    end
  end

  defp get_user_id_for_student(student, prefix) do
    # Try to find user by matching email
    case Repo.get_by(User, [email: student.email], prefix: prefix) do
      nil ->
        # If no user with student's email, find any admin/faculty user as creator
        query =
          from u in User,
            where: u.role in ["admin", "faculty"],
            limit: 1,
            select: u.id

        case Repo.one(query, prefix: prefix) do
          nil -> nil
          user_id -> user_id
        end

      user ->
        user.id
    end
  end

  defp create_assessment_for_student(student, user_id, prefix, opts) do
    # Load tenant config or use defaults
    config = AssessmentConfigs.get_or_default_config_for_tenant(student.tenant_id)

    # Use config values, allow opts override
    total_questions = Keyword.get(opts, :total_questions, config.total_questions)
    easy_pct = Keyword.get(opts, :easy_pct, config.easy_percentage / 100)
    medium_pct = Keyword.get(opts, :medium_pct, config.medium_percentage / 100)
    hard_pct = Keyword.get(opts, :hard_pct, config.hard_percentage / 100)
    duration_minutes = Keyword.get(opts, :duration_minutes, config.duration_minutes)

    # Role-aware selection first (Vya-036 / MBA→CS fix): the student's chosen
    # job role drives the question set via its subject blueprint. Only if the
    # role has no blueprint do we fall back to the academic degree path — and
    # that path now fails clearly instead of silently defaulting to Computer
    # Science.
    questions_result =
      case select_role_based_questions(student, prefix, easy_pct, medium_pct, hard_pct) do
        {:ok, [_ | _] = qs} ->
          Logger.info("Dynamic assessment: role-based selection = #{length(qs)} questions")
          {:ok, qs}

        _ ->
          select_degree_based_questions(
            student,
            config,
            total_questions,
            easy_pct,
            medium_pct,
            hard_pct
          )
      end

    case questions_result do
      {:ok, [_ | _] = questions} ->
        create_assessment_from_question_set(
          student,
          user_id,
          nil,
          questions,
          duration_minutes,
          length(questions),
          prefix
        )

      {:ok, []} ->
        Logger.error("No questions available for student #{student.id} (role + degree paths empty)")
        {:error, :no_questions_available}

      {:error, reason} ->
        Logger.error("Failed to select questions: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── Role-based question selection (via job_role_subjects blueprint) ─────────
  defp select_role_based_questions(student, prefix, easy_pct, medium_pct, hard_pct) do
    with role_title when is_binary(role_title) and role_title != "" <-
           StudentAts.get_student_preferred_role(student.id, prefix),
         %{id: role_id} <- Jobs.get_job_role_by_title(role_title),
         [_ | _] = blueprint <- Jobs.role_blueprint(role_id) do
      questions =
        blueprint
        |> Enum.flat_map(fn {subject_id, count} ->
          case select_questions_from_subjects([subject_id], count, easy_pct, medium_pct, hard_pct) do
            {:ok, qs} -> qs
            _ -> []
          end
        end)
        |> Enum.shuffle()
        |> Enum.with_index(1)
        |> Enum.map(fn {q, i} -> Map.put(q, :display_order, i) end)

      {:ok, questions}
    else
      _ -> {:error, :no_role_question_set}
    end
  end

  defp select_questions_from_subjects(subject_ids, count, easy_pct, medium_pct, hard_pct) do
    query = "SELECT * FROM select_questions_by_subjects($1, $2, $3, $4, $5)"

    case Repo.query(query, [subject_ids, count, easy_pct, medium_pct, hard_pct]) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &format_sql_question_row/1)}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.error("select_questions_by_subjects failed: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  # ── Degree-based fallback (academic branch/curriculum) ─────────────────────
  # Last-resort question set: every subject that actually has questions. Ensures
  # the assessment always generates instead of hard-failing.
  defp select_generic_questions(total, easy_pct, medium_pct, hard_pct) do
    subject_ids =
      case Repo.query(
             "SELECT DISTINCT s.id FROM subjects s JOIN topics t ON t.subject_id = s.id JOIN qa q ON q.topic_id = t.id"
           ) do
        {:ok, %{rows: rows}} -> List.flatten(rows)
        _ -> []
      end

    if subject_ids == [] do
      {:error, :no_questions_available}
    else
      select_questions_from_subjects(subject_ids, total, easy_pct, medium_pct, hard_pct)
    end
  end

  defp select_degree_based_questions(student, config, total_questions, easy_pct, medium_pct, hard_pct) do
    case resolve_branch_and_curriculum(student) do
      :no_match ->
        # No role blueprint and the specialization didn't resolve to a curriculum.
        # Rather than hard-fail ("Failed to generate assessment"), fall back to a
        # general pool drawn from every subject that has questions. Not
        # role-specific — configure a role blueprint (Admin → Jobs → MCQ
        # subjects) to get a targeted set (Vya-036).
        Logger.warning(
          "No role blueprint / curriculum match for student #{student.id} " <>
            "(specialization=#{Map.get(student, :specialization)}) — using the general question pool."
        )

        select_generic_questions(total_questions, easy_pct, medium_pct, hard_pct)

      {curricula_id, branch_id} ->
        aptitude_count = round(total_questions * config.aptitude_percentage / 100)
        technical_count = total_questions - aptitude_count

        select_split_questions(
          curricula_id,
          branch_id,
          aptitude_count,
          technical_count,
          easy_pct,
          medium_pct,
          hard_pct
        )
    end
  end

  @doc """
  Gets or creates a dynamic assessment for a student.
  Reuses existing assessment if found, otherwise creates a new one.
  """
  def get_or_create_dynamic_assessment(student_id, prefix) do
    # Check if student already has an assessment created today
    case find_recent_assessment_for_student(student_id, prefix) do
      nil ->
        # Create new dynamic assessment
        create_dynamic_assessment_for_student(student_id, prefix)

      existing_assessment ->
        {:ok, existing_assessment}
    end
  end

  @doc """
  Loads questions for an assessment.

  Two storage paths are supported:

    1. `settings["question_set_id"]` is set — questions are read fresh from the
       `question_set_items` join (used if a tenant has pre-built question sets).
    2. Otherwise the embedded `settings["questions"]` JSONB array (populated by
       the dynamic-assessment generator) is normalised back into the same
       atom-keyed shape that the test LiveView expects.

  Returns `[]` when no questions exist — callers (e.g. `TestLive.mount_test`)
  surface this as a flash + redirect rather than silently swapping in stub data.
  """
  def load_assessment_questions(assessment_id, prefix) do
    assessment = get_assessment!(assessment_id, prefix)
    question_set_id = get_in(assessment.settings, ["question_set_id"])
    embedded_questions = get_in(assessment.settings, ["questions"]) || []

    cond do
      question_set_id ->
        load_questions_from_question_set(question_set_id, prefix)

      embedded_questions != [] ->
        Enum.map(embedded_questions, &normalize_embedded_question/1)

      true ->
        []
    end
  end

  # Convert a string-keyed question (as stored in assessment.settings["questions"]
  # by format_questions_for_assessment/1) back into the atom-keyed shape produced
  # by format_question/1, so the rest of the test pipeline can stay uniform.
  defp normalize_embedded_question(q) when is_map(q) do
    %{
      id: q["id"],
      question: q["question"],
      answer: q["correct_answer"],
      options: normalize_options(q["options"]),
      difficulty_level: q["difficulty"],
      type: q["type"] || "multiple_choice",
      weightage: q["weightage"] || q["points"] || 1,
      marks: q["points"] || 1,
      display_order: q["display_order"],
      topic_name: q["topic"],
      subject_name: q["subject"]
    }
  end

  defp normalize_options(opts) when is_map(opts), do: opts
  defp normalize_options(_), do: %{}

  # ============================================================================
  # BRANCH/CURRICULUM RESOLUTION
  # ============================================================================

  @aptitude_subject_id 7

  defp resolve_branch_and_curriculum(student) do
    spec_id = Map.get(student, :specialization_id)

    # Strategy 1: Use specialization_id FK (new path via curricula.specialization_id)
    if spec_id do
      case resolve_via_specialization_id(spec_id) do
        {:ok, curricula_id, branch_id} -> {curricula_id, branch_id}
        :not_found -> resolve_via_text_match(student)
      end
    else
      resolve_via_text_match(student)
    end
  end

  defp resolve_via_specialization_id(spec_id) do
    {:ok, spec_uuid} = Ecto.UUID.dump(spec_id)

    query = """
    SELECT c.id AS curricula_id, c.branch_id
    FROM curricula c
    WHERE c.specialization_id = $1
    ORDER BY c.id ASC
    LIMIT 1
    """

    case Repo.query(query, [spec_uuid]) do
      {:ok, %{rows: [[curricula_id, branch_id] | _]}} ->
        Logger.info("Resolved via specialization_id: curricula=#{curricula_id}, branch=#{branch_id}")
        {:ok, curricula_id, branch_id}

      _ ->
        :not_found
    end
  end

  defp resolve_via_text_match(student) do
    specialization = Map.get(student, :specialization) || ""
    degree = Map.get(student, :degree) || ""

    # Fallback: match on branch name/code using free-text fields
    query = """
    SELECT b.id AS branch_id, c.id AS curricula_id
    FROM branches b
    JOIN curricula c ON c.branch_id = b.id
    WHERE LOWER(b.name) LIKE $1
       OR LOWER(b.code) LIKE $1
       OR LOWER(b.name) LIKE $2
       OR LOWER(b.code) LIKE $2
       OR LOWER(b.code) = $3
    ORDER BY c.id ASC
    LIMIT 1
    """

    spec_normalized = "%" <> String.downcase(String.trim(specialization)) <> "%"
    degree_normalized = "%" <> String.downcase(String.trim(degree)) <> "%"
    spec_code = lookup_specialization_code(specialization)

    case Repo.query(query, [spec_normalized, degree_normalized, String.downcase(spec_code)]) do
      {:ok, %{rows: [[branch_id, curricula_id] | _]}} ->
        Logger.info("Resolved via text match: branch=#{branch_id}, curricula=#{curricula_id}")
        {curricula_id, branch_id}

      _ ->
        # Do NOT default to curriculum/branch (1,1) = Computer Science — that
        # served CS questions to MBA/other programs. Signal no match so the
        # caller fails clearly instead.
        Logger.info("No curriculum match for specialization=#{specialization} — no_match")
        :no_match
    end
  end

  defp lookup_specialization_code(specialization) do
    query = """
    SELECT s.code FROM public.specializations s
    WHERE LOWER(s.name) = $1
    LIMIT 1
    """
    case Repo.query(query, [String.downcase(String.trim(specialization))]) do
      {:ok, %{rows: [[code] | _]}} -> code
      _ -> ""
    end
  end

  # ============================================================================
  # APTITUDE/TECHNICAL SPLIT QUESTION SELECTION
  # ============================================================================

  defp select_split_questions(curricula_id, branch_id, aptitude_count, technical_count, easy_pct, medium_pct, hard_pct) do
    # Select aptitude questions (subject_id = 7)
    aptitude_result =
      if aptitude_count > 0 do
        select_questions_by_subject(curricula_id, branch_id, [@aptitude_subject_id], aptitude_count, easy_pct, medium_pct, hard_pct)
      else
        {:ok, []}
      end

    # Select technical questions (all subjects except aptitude)
    technical_result =
      if technical_count > 0 do
        select_questions_excluding_subject(curricula_id, branch_id, @aptitude_subject_id, technical_count, easy_pct, medium_pct, hard_pct)
      else
        {:ok, []}
      end

    case {aptitude_result, technical_result} do
      {{:ok, apt_qs}, {:ok, tech_qs}} ->
        # Aptitude first, then technical - assign sequential display_order
        combined =
          (apt_qs ++ tech_qs)
          |> Enum.with_index(1)
          |> Enum.map(fn {q, idx} -> Map.put(q, :display_order, idx) end)

        {:ok, combined}

      {{:error, reason}, _} ->
        {:error, reason}

      {_, {:error, reason}} ->
        {:error, reason}
    end
  end

  defp select_questions_by_subject(curricula_id, branch_id, subject_ids, count, easy_pct, medium_pct, hard_pct) do
    query = """
    SELECT * FROM select_questions($1, $2, NULL, $3, $4, $5, $6, $7)
    """

    case Repo.query(query, [curricula_id, branch_id, subject_ids, count, easy_pct, medium_pct, hard_pct]) do
      {:ok, %{rows: rows, columns: _columns}} ->
        questions = Enum.map(rows, &format_sql_question_row/1)
        {:ok, questions}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("select_questions_by_subject failed: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp select_questions_excluding_subject(curricula_id, branch_id, exclude_subject_id, count, easy_pct, medium_pct, hard_pct) do
    # Get all technical subject IDs for this curriculum (excluding aptitude)
    subject_query = """
    SELECT DISTINCT cs.subject_id FROM curricula_subjects cs
    WHERE cs.curricula_id = $1
      AND (cs.branch_id = $2 OR cs.branch_id IS NULL)
      AND cs.subject_id != $3
    """

    case Repo.query(subject_query, [curricula_id, branch_id, exclude_subject_id]) do
      {:ok, %{rows: rows}} when rows != [] ->
        subject_ids = Enum.map(rows, fn [id] -> id end)
        select_questions_by_subject(curricula_id, branch_id, subject_ids, count, easy_pct, medium_pct, hard_pct)

      _ ->
        Logger.warning("No technical subjects found for curricula=#{curricula_id}, branch=#{branch_id}")
        {:ok, []}
    end
  end

  defp format_sql_question_row([qa_id, question, answer, options, difficulty_level, question_type, weightage, topic_id, topic_name, subject_id, subject_name, _selection_reason, display_order]) do
    %{
      id: qa_id,
      question: question,
      answer: answer,
      options: options,
      difficulty_level: difficulty_level,
      type: question_type,
      weightage: weightage,
      marks: if(is_nil(weightage), do: 1, else: Decimal.to_integer(Decimal.round(weightage))),
      display_order: display_order,
      topic_id: topic_id,
      topic_name: topic_name,
      subject_id: subject_id,
      subject_name: subject_name
    }
  end

  # ============================================================================
  # PRIVATE HELPER FUNCTIONS
  # ============================================================================

  defp create_question_set_via_sql(
         name,
         curricula_id,
         branch_id,
         user_id,
         total_questions,
         easy_pct,
         medium_pct,
         hard_pct,
         duration_minutes,
         _prefix
       ) do
    # Convert user_id (binary UUID) to integer for SQL function
    # In production, you might need to adjust this based on your user ID type
    user_id_int = hash_uuid_to_int(user_id)

    query = """
    SELECT create_question_set(
      $1::VARCHAR,
      $2::INTEGER,
      $3::INTEGER,
      $4::INTEGER,
      $5::INTEGER,
      $6::NUMERIC,
      $7::NUMERIC,
      $8::NUMERIC,
      $9::INTEGER
    ) AS question_set_id
    """

    try do
      case Repo.query(
             query,
             [
               name,
               curricula_id,
               branch_id,
               user_id_int,
               total_questions,
               Decimal.new(to_string(easy_pct)),
               Decimal.new(to_string(medium_pct)),
               Decimal.new(to_string(hard_pct)),
               duration_minutes
             ]
           ) do
        {:ok, %{rows: [[question_set_id]]}} ->
          {:ok, question_set_id}

        {:error, reason} ->
          Logger.error("SQL function failed: #{inspect(reason)}")
          {:error, reason}

        unexpected ->
          Logger.error("Unexpected SQL result: #{inspect(unexpected)}")
          {:error, :unexpected_result}
      end
    rescue
      error ->
        Logger.error("Exception calling SQL function: #{inspect(error)}")
        {:error, :sql_exception}
    end
  end

  defp load_questions_from_question_set(question_set_id, _prefix) do
    query = """
    SELECT
      qsi.qa_id,
      qa.question,
      qa.answer,
      qa.options,
      qa.difficulty_level,
      qa.type,
      qa.weightage,
      qsi.display_order,
      qsi.marks,
      t.name as topic_name,
      s.name as subject_name
    FROM question_set_items qsi
    INNER JOIN qa ON qsi.qa_id = qa.id
    LEFT JOIN topics t ON qa.topic_id = t.id
    LEFT JOIN subjects s ON t.subject_id = s.id
    WHERE qsi.question_set_id = $1
    ORDER BY qsi.display_order
    """

    case Repo.query(query, [question_set_id]) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          columns
          |> Enum.zip(row)
          |> Enum.into(%{})
          |> format_question()
        end)

      {:error, _reason} ->
        []
    end
  end

  defp format_question(raw_question) do
    %{
      id: raw_question["qa_id"],
      question: raw_question["question"],
      answer: raw_question["answer"],
      options: raw_question["options"] || %{},
      difficulty_level: raw_question["difficulty_level"],
      type: raw_question["type"],
      weightage: raw_question["weightage"],
      marks: raw_question["marks"] || 1,
      display_order: raw_question["display_order"],
      topic_name: raw_question["topic_name"],
      subject_name: raw_question["subject_name"]
    }
  end

  defp create_assessment_from_question_set(
         student,
         user_id,
         question_set_id,
         questions,
         duration_minutes,
         total_questions,
         prefix
       ) do
    # Load config for negative marking and passing percentage
    config = AssessmentConfigs.get_or_default_config_for_tenant(student.tenant_id)
    negative_marking = Decimal.to_float(config.negative_marking)
    passing_marks = round(total_questions * config.passing_percentage / 100)

    # Build settings map conditionally
    settings =
      %{
        "total_questions" => total_questions,
        "section_navigation" => "sequential",
        "negative_marking" => negative_marking,
        "shuffle_questions" => false,
        "shuffle_options" => true,
        "questions" => format_questions_for_assessment(questions)
      }
      |> maybe_add_question_set_id(question_set_id)

    # Use user_id for created_by (references users table)
    attrs = %{
      title:
        "Employability Assessment - #{Map.get(student, :degree) || "General"} #{Map.get(student, :specialization) || ""}",
      description: "Personalized assessment based on your curriculum",
      assessment_type: "quiz",
      duration_minutes: duration_minutes,
      total_marks: total_questions,
      passing_marks: passing_marks,
      weightage: Decimal.new("100.0"),
      status: "published",
      # This references the users table
      created_by: user_id,
      tenant_id: ensure_uuid_string(Map.get(student, :tenant_id)),
      settings: settings
    }

    create_assessment(attrs, prefix)
  end

  defp maybe_add_question_set_id(settings, nil), do: settings

  defp maybe_add_question_set_id(settings, question_set_id) do
    Map.put(settings, "question_set_id", question_set_id)
  end

  defp format_questions_for_assessment(questions) do
    formatted =
      Enum.map(questions, fn q ->
        %{
          "id" => q.id,
          "question" => q.question,
          "options" => q.options,
          "correct_answer" => q.answer,
          "points" => q.marks || 1,
          "difficulty" => q.difficulty_level,
          "subject" => q.subject_name,
          "topic" => q.topic_name
        }
      end)

    # Sort so Aptitude questions come first (Section 1), then technical subjects
    {aptitude, technical} = Enum.split_with(formatted, fn q -> q["subject"] == "Aptitude" end)
    aptitude ++ technical
  end

  defp find_recent_assessment_for_student(student_id, prefix) do
    # Find assessments created in the last 24 hours for this student
    # created_by stores user_id, so we need to resolve student -> user first
    student = Repo.get(Student, student_id, prefix: prefix)
    user_id = if student, do: get_user_id_for_student(student, prefix)

    if is_nil(user_id) do
      nil
    else
      yesterday = DateTime.utc_now() |> DateTime.add(-86400, :second)

      Assessment
      |> where([a], a.created_by == ^user_id)
      |> where([a], a.inserted_at > ^yesterday)
      |> where([a], a.status == ^assessment_status_published())
      |> order_by([a], desc: a.inserted_at)
      |> limit(1)
      |> Repo.one(prefix: prefix)
    end
  end

  defp hash_uuid_to_int(uuid) when is_binary(uuid) do
    # Simple hash function to convert UUID to integer
    # This is a simplistic approach - adjust based on your needs
    uuid
    |> String.replace("-", "")
    |> String.slice(0..7)
    |> String.to_integer(16)
    |> rem(2_147_483_647)
  end

  defp ensure_uuid_string(nil), do: nil

  defp ensure_uuid_string(uuid) when is_binary(uuid) do
    # If it's already a string, try to validate and return
    case Ecto.UUID.cast(uuid) do
      {:ok, valid_uuid} -> valid_uuid
      # Return as-is if invalid
      :error -> uuid
    end
  end

  defp ensure_uuid_string(uuid) do
    # If it's binary data, convert to UUID string
    Ecto.UUID.cast!(uuid)
  end

  defp get_active_attempt(assessment_id, student_id, prefix) do
    student_id = if is_binary(student_id), do: student_id, else: to_string(student_id)

    AssessmentAttempt
    |> where([a], a.assessment_id == ^assessment_id and a.student_id == ^student_id)
    |> where([a], a.status in [^attempt_status_started(), ^attempt_status_in_progress()])
    |> order_by([a], desc: a.inserted_at)
    |> limit(1)
    |> Repo.one(prefix: prefix)
  end

  defp get_submitted_attempt(assessment_id, student_id, prefix) do
    student_id = if is_binary(student_id), do: student_id, else: to_string(student_id)

    AssessmentAttempt
    |> where([a], a.assessment_id == ^assessment_id and a.student_id == ^student_id)
    |> where([a], a.status == ^attempt_status_submitted())
    |> limit(1)
    |> Repo.one(prefix: prefix)
  end

  defp create_attempt(assessment_id, student_id, prefix) do
    # Ensure student_id is properly cast to binary_id
    student_id = if is_binary(student_id), do: student_id, else: to_string(student_id)

    %AssessmentAttempt{
      assessment_id: assessment_id,
      student_id: student_id,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second),
      status: attempt_status_started()
    }
    |> AssessmentAttempt.changeset(%{})
    |> Repo.insert(prefix: prefix)
  end

  defp calculate_detailed_score(answers, questions, negative_marking) do
    answers = answers || %{}

    Enum.reduce(questions, %{correct: 0, wrong: 0, unanswered: 0, score: 0.0, negative: 0.0}, fn q, acc ->
      question_id_str = to_string(q["id"])
      answer = Map.get(answers, question_id_str) || Map.get(answers, q["id"])
      points = parse_points(q["points"])
      correct_answer = q["correct_answer"]

      cond do
        is_nil(answer) or answer == "" ->
          %{acc | unanswered: acc.unanswered + 1}

        is_nil(correct_answer) ->
          # Skip questions with no correct answer defined
          %{acc | unanswered: acc.unanswered + 1}

        to_string(answer) == to_string(correct_answer) ->
          %{acc | correct: acc.correct + 1, score: acc.score + points}

        true ->
          penalty = points * negative_marking
          %{acc | wrong: acc.wrong + 1, negative: acc.negative + penalty, score: acc.score - penalty}
      end
    end)
  end

  defp parse_points(nil), do: 1
  defp parse_points(points) when is_integer(points), do: points
  defp parse_points(points) when is_float(points), do: points

  defp parse_points(points) when is_binary(points) do
    case Float.parse(points) do
      {val, _} -> val
      :error -> 1
    end
  end

  defp parse_points(%Decimal{} = points), do: Decimal.to_float(points)
  defp parse_points(_), do: 1

  # ============================================================================
  # INTEGRITY CHECKS
  # ============================================================================

  @doc """
  Records the number of tab switches for an attempt.
  Called by LiveView when the client reports focus loss events.
  """
  @doc """
  Appends a structured proctoring violation to the attempt's metadata and
  returns the new total violation count. `type` is one of "tab_switch",
  "window_blur", "fullscreen_exit". Keeps `tab_switch_count` in sync so the
  existing integrity heuristics keep working.
  """
  def record_violation(attempt_id, type, prefix) do
    case Repo.get(AssessmentAttempt, attempt_id, prefix: prefix) do
      nil ->
        {:error, :attempt_not_found}

      attempt ->
        meta = attempt.metadata || %{}
        entry = %{"type" => type, "at" => DateTime.utc_now() |> DateTime.to_iso8601()}
        violations = (meta["violations"] || []) ++ [entry]
        count = length(violations)

        meta =
          meta
          |> Map.put("violations", violations)
          |> Map.put("violation_count", count)

        meta =
          if type == "tab_switch",
            do: Map.put(meta, "tab_switch_count", (meta["tab_switch_count"] || 0) + 1),
            else: meta

        case attempt
             |> AssessmentAttempt.changeset(%{metadata: meta})
             |> Repo.update(prefix: prefix) do
          {:ok, _} -> {:ok, count}
          {:error, _} = err -> err
        end
    end
  end

  @doc """
  Readable MCQ proctoring flags for the admin Integrity panel, read directly from
  each attempt's `metadata.violations`. Unlike the evaluation-time
  `integrity_flags` (only computed on a normal submission), this surfaces
  violations from ANY attempt — including ones force-closed at the strike limit
  or abandoned mid-exam.
  """
  def student_integrity_flags(student_id, prefix) do
    AssessmentAttempt
    |> where(student_id: ^student_id)
    |> Repo.all(prefix: prefix)
    |> Enum.flat_map(fn a -> mcq_violation_flags(a.metadata || %{}) end)
    |> Enum.uniq()
  end

  defp mcq_violation_flags(meta) do
    violations = meta["violations"] || []
    count = meta["violation_count"] || length(violations)

    if count >= 2 do
      breakdown =
        violations
        |> Enum.frequencies_by(& &1["type"])
        |> Enum.map(fn {t, c} -> "#{c} #{humanize_violation(t)}" end)
        |> Enum.join(", ")

      detail = if breakdown == "", do: "#{count} focus losses", else: breakdown
      ["MCQ — proctoring: #{count} violations (#{detail})"]
    else
      []
    end
  end

  defp humanize_violation("tab_switch"), do: "tab switch"
  defp humanize_violation("window_blur"), do: "window switch"
  defp humanize_violation("fullscreen_exit"), do: "full-screen exit"
  defp humanize_violation(other), do: to_string(other)

  def record_tab_switch(attempt_id, tab_switch_count, prefix) do
    case Repo.get(AssessmentAttempt, attempt_id, prefix: prefix) do
      nil ->
        {:error, :attempt_not_found}

      attempt ->
        metadata = Map.put(attempt.metadata || %{}, "tab_switch_count", tab_switch_count)

        attempt
        |> AssessmentAttempt.changeset(%{metadata: metadata})
        |> Repo.update(prefix: prefix)
    end
  end

  # Detects suspicious answer patterns and submission timing anomalies.
  # Reads per-question timestamps and change counts from attempt metadata.
  # Returns a list of flag strings (empty = no issues detected).
  defp detect_integrity_issues(answers, questions, attempt) do
    metadata = attempt.metadata || %{}
    answer_timestamps   = metadata["answer_timestamps"]   || %{}
    answer_change_counts = metadata["answer_change_counts"] || %{}
    tab_switches        = metadata["tab_switch_count"]    || 0

    # Build ordered list of answered question IDs (by the question display order)
    ordered_question_ids =
      questions
      |> Enum.map(fn q -> to_string(q["id"]) end)
      |> Enum.filter(&Map.has_key?(answers, &1))

    answered_values = Enum.map(ordered_question_ids, &Map.get(answers, &1))

    flags = []

    # -----------------------------------------------------------------------
    # Flag 1: ALL answers are the same option (e.g., all "a")
    # -----------------------------------------------------------------------
    flags =
      if length(answered_values) >= 5 and length(Enum.uniq(answered_values)) == 1 do
        Logger.warning(
          "Integrity: all #{length(answered_values)} answers are '#{hd(answered_values)}' — attempt #{attempt.id}"
        )
        ["all_same_answer" | flags]
      else
        flags
      end

    # -----------------------------------------------------------------------
    # Flag 2: CONSECUTIVE same-option run of 8 or more
    # -----------------------------------------------------------------------
    flags =
      if length(answered_values) >= 8 do
        max_run = max_consecutive_run(answered_values)
        if max_run >= 8 do
          Logger.warning("Integrity: #{max_run} consecutive identical answers — attempt #{attempt.id}")
          ["long_consecutive_same_answer" | flags]
        else
          flags
        end
      else
        flags
      end

    # -----------------------------------------------------------------------
    # Flag 3: Answer map size exceeds question count (data corruption)
    # -----------------------------------------------------------------------
    flags =
      if map_size(answers) > length(questions) and length(questions) > 0 do
        ["answer_count_exceeds_questions" | flags]
      else
        flags
      end

    # -----------------------------------------------------------------------
    # Flag 4: Proctoring violations — tab switches, window/alt-tab blur, and
    # full-screen exits (auto-submit fires at the limit, so this surfaces the
    # run-up and anyone force-submitted). Uses the structured violation log.
    # -----------------------------------------------------------------------
    violations = metadata["violations"] || []
    total_violations = metadata["violation_count"] || tab_switches

    flags =
      if total_violations >= 2 do
        breakdown =
          violations
          |> Enum.frequencies_by(& &1["type"])
          |> Enum.map(fn {t, c} -> "#{c} #{humanize_violation(t)}" end)
          |> Enum.join(", ")

        detail = if breakdown == "", do: "#{total_violations} focus losses", else: breakdown

        Logger.warning(
          "Integrity: #{total_violations} proctoring violations (#{detail}) — attempt #{attempt.id}"
        )

        ["Proctoring: #{total_violations} violations (#{detail})" | flags]
      else
        flags
      end

    # -----------------------------------------------------------------------
    # Flag 5: Rapid answering — any two consecutive answers < 3 seconds apart
    # Only checked if we have timestamps for at least half the answered questions.
    # -----------------------------------------------------------------------
    flags =
      if map_size(answer_timestamps) >= max(2, div(length(ordered_question_ids), 2)) do
        timestamps_in_order =
          ordered_question_ids
          |> Enum.map(&Map.get(answer_timestamps, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()

        rapid_pairs =
          timestamps_in_order
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.count(fn [a, b] -> b - a < 3 end)

        if rapid_pairs >= 5 do
          Logger.warning(
            "Integrity: #{rapid_pairs} answer pairs < 3s apart — attempt #{attempt.id}"
          )
          ["rapid_answering" | flags]
        else
          flags
        end
      else
        flags
      end

    # -----------------------------------------------------------------------
    # Flag 6: Excessive answer changes on a single question (> 3 times)
    # -----------------------------------------------------------------------
    flags =
      if map_size(answer_change_counts) > 0 do
        max_changes =
          answer_change_counts
          |> Map.values()
          |> Enum.max(fn -> 0 end)

        if max_changes > 3 do
          Logger.warning(
            "Integrity: a question was re-answered #{max_changes} times — attempt #{attempt.id}"
          )
          ["excessive_answer_changes" | flags]
        else
          flags
        end
      else
        flags
      end

    flags
  end

  # Returns the length of the longest consecutive run of identical values.
  defp max_consecutive_run([]), do: 0
  defp max_consecutive_run(list) do
    list
    |> Enum.chunk_by(& &1)
    |> Enum.map(&length/1)
    |> Enum.max()
  end

  # Enqueues an Oban job to render the report PDF and email it to the student.
  # Failures here do not block the submission — the student still sees their score.
  defp enqueue_report_email(report_type, attempt, tenant_schema) do
    tenant_alias =
      case Tenants.get_tenant_by_schema_name(tenant_schema) do
        %{alias: a} -> a
        _ -> nil
      end

    case ReportGenerator.enqueue(report_type, attempt.id, tenant_schema, tenant_alias) do
      {:ok, %Oban.Job{id: id}} ->
        Logger.info("Report job enqueued: #{id} (#{report_type} / attempt=#{attempt.id})")

      {:error, reason} ->
        Logger.error("Failed to enqueue report job: #{inspect(reason)}")
    end
  rescue
    exception ->
      Logger.error("Exception enqueuing report job: #{inspect(exception)}")
  end
end
