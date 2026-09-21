defmodule VyaasaCampus.Contexts.StudentRankings do
  @moduledoc """
  Context for computing student scores and rankings across all assessment types.
  Used by the student dashboard to display scores, ranks, and progress.
  """

  import Ecto.Query, warn: false
  import VyaasaCampus.Types
  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Assessments.AssessmentAttempt
  alias VyaasaCampus.Schema.Students.{StudentAtsPhase, StudentBehavioralAssessment}
  alias VyaasaCampus.Schema.Jam.JamSession
  alias VyaasaCampus.Schema.Interview.InterviewSession
  alias VyaasaCampus.Schema.Students.StudentPsychometricAssessment
  alias VyaasaCampus.Schema.CaseStudy.CaseStudySession
  alias VyaasaCampus.Schema.Students.StudentMiniProjectSession

  @doc """
  Gets all scores and ranks for a student across all assessment types.
  Returns a map with score data for each module.
  """
  def get_student_scores_and_ranks(student_id, tenant_schema) do
    %{
      mcq: get_mcq_rank(student_id, tenant_schema),
      behavioral: get_behavioral_rank(student_id, tenant_schema),
      ats: get_ats_rank(student_id, tenant_schema),
      jam: get_jam_rank(student_id, tenant_schema),
      interview: get_interview_rank(student_id, tenant_schema),
      psychometric: get_psychometric_rank(student_id, tenant_schema),
      case_study: get_case_study_rank(student_id, tenant_schema),
      mini_project: get_mini_project_rank(student_id, tenant_schema)
    }
  end

  @doc """
  Gets MCQ score and rank for a student.
  Uses the latest submitted attempt's percentage for ranking.
  """
  def get_mcq_rank(student_id, prefix) do
    # Get this student's latest submitted attempt
    student_attempt =
      AssessmentAttempt
      |> where([a], a.student_id == ^student_id and a.status == ^attempt_status_submitted())
      |> order_by([a], desc: a.submitted_at)
      |> limit(1)
      |> Repo.one(prefix: prefix)

    case student_attempt do
      nil ->
        %{score: nil, percentage: nil, rank: nil, total: count_mcq_students(prefix), completed: false}

      attempt ->
        percentage = safe_decimal_to_float(attempt.percentage)
        score = safe_decimal_to_float(attempt.score)

        # Count students with higher percentage
        higher_count =
          from(a in AssessmentAttempt,
            where: a.status == ^attempt_status_submitted(),
            group_by: a.student_id,
            select: %{student_id: a.student_id, max_pct: max(a.percentage)}
          )
          |> subquery()
          |> where([s], s.max_pct > ^(attempt.percentage || Decimal.new(0)))
          |> Repo.aggregate(:count, prefix: prefix)

        total = count_mcq_students(prefix)

        %{
          score: score,
          percentage: percentage,
          obtained_marks: attempt.obtained_marks,
          total_marks: attempt.total_marks,
          rank: higher_count + 1,
          total: total,
          completed: true,
          evaluation_data: attempt.evaluation_data
        }
    end
  end

  @doc """
  Gets behavioral score and rank for a student.
  """
  def get_behavioral_rank(student_id, prefix) do
    # Get this student's latest completed assessment
    student_assessment =
      from(ba in StudentBehavioralAssessment,
        where: ba.student_id == ^student_id and ba.status == "completed",
        order_by: [desc: ba.attempt_number],
        limit: 1
      )
      |> Repo.one(prefix: prefix)

    case student_assessment do
      nil ->
        %{score: nil, rank: nil, total: count_behavioral_students(prefix), completed: false}

      assessment ->
        score = assessment.overall_score || 0

        # Count students with higher score
        higher_count =
          from(ba in StudentBehavioralAssessment,
            where: ba.status == "completed",
            group_by: ba.student_id,
            select: %{student_id: ba.student_id, max_score: max(ba.overall_score)}
          )
          |> subquery()
          |> where([s], s.max_score > ^score)
          |> Repo.aggregate(:count, prefix: prefix)

        total = count_behavioral_students(prefix)

        %{
          score: score,
          rank: higher_count + 1,
          total: total,
          completed: true,
          strengths: assessment.strengths,
          areas_for_development: assessment.areas_for_development,
          competencies: %{
            work_ethics: assessment.work_ethics_score,
            teamwork: assessment.teamwork_score,
            adaptability: assessment.adaptability_score,
            leadership: assessment.leadership_score,
            communication: assessment.communication_score
          }
        }
    end
  end

  @doc """
  Gets ATS (resume) score and rank for a student.
  """
  def get_ats_rank(student_id, prefix) do
    student_ats =
      StudentAtsPhase
      |> where(student_id: ^student_id)
      |> where([a], a.status in ["completed", "manual_review", "errored"])
      |> limit(1)
      |> Repo.one(prefix: prefix)

    case student_ats do
      nil ->
        %{score: nil, rank: nil, total: count_ats_students(prefix), completed: false}

      ats ->
        score = safe_decimal_to_float(ats.ats_score) || 0

        # Count students with higher ATS score
        higher_count =
          from(a in StudentAtsPhase,
            where: a.status in ["completed", "manual_review", "errored"] and a.ats_score > ^(ats.ats_score || Decimal.new(0))
          )
          |> Repo.aggregate(:count, prefix: prefix)

        total = count_ats_students(prefix)

        %{
          score: score,
          rank: higher_count + 1,
          total: total,
          completed: true
        }
    end
  end

  @doc """
  Gets JAM score and rank for a student.
  Uses the best (highest) completed session score.
  """
  def get_jam_rank(student_id, prefix) do
    # Get this student's best completed JAM score
    best_score =
      JamSession
      |> where(student_id: ^student_id, status: "completed")
      |> where([j], not is_nil(j.final_score))
      |> Repo.aggregate(:max, :final_score, prefix: prefix)

    case best_score do
      nil ->
        %{score: nil, rank: nil, total: count_jam_students(prefix), completed: false}

      score ->
        # Count students with higher best score
        higher_count =
          from(j in JamSession,
            where: j.status == "completed" and not is_nil(j.final_score),
            group_by: j.student_id,
            select: %{student_id: j.student_id, best: max(j.final_score)}
          )
          |> subquery()
          |> where([s], s.best > ^score)
          |> Repo.aggregate(:count, prefix: prefix)

        total = count_jam_students(prefix)

        %{
          score: score,
          rank: higher_count + 1,
          total: total,
          completed: true
        }
    end
  end

  @doc """
  Gets interview score and rank for a student.
  """
  def get_interview_rank(student_id, prefix) do
    # Get this student's best completed interview score
    student_interview =
      from(i in InterviewSession,
        where: i.student_id == ^student_id and i.status == "completed" and not is_nil(i.overall_score),
        order_by: [desc: i.overall_score],
        limit: 1
      )
      |> Repo.one(prefix: prefix)

    case student_interview do
      nil ->
        %{score: nil, rank: nil, total: count_interview_students(prefix), completed: false}

      interview ->
        score = safe_decimal_to_float(interview.overall_score) || 0

        # Count students with higher interview score
        higher_count =
          from(i in InterviewSession,
            where: i.status == "completed" and not is_nil(i.overall_score),
            group_by: i.student_id,
            select: %{student_id: i.student_id, best: max(i.overall_score)}
          )
          |> subquery()
          |> where([s], s.best > ^(interview.overall_score || Decimal.new(0)))
          |> Repo.aggregate(:count, prefix: prefix)

        total = count_interview_students(prefix)

        %{
          score: score,
          rank: higher_count + 1,
          total: total,
          completed: true
        }
    end
  end

  @doc """
  Gets Psychometric score and rank for a student.
  Uses the average of the Big Five factor scores (each 0-5, normalized to 0-100).
  """
  def get_psychometric_rank(student_id, prefix) do
    # Get latest completed psychometric assessment
    student_assessment =
      from(a in StudentPsychometricAssessment,
        where: a.student_id == ^student_id and a.status == "completed",
        order_by: [desc: a.attempt_number],
        limit: 1
      )
      |> Repo.one(prefix: prefix)

    case student_assessment do
      nil ->
        %{score: nil, rank: nil, total: count_psychometric_students(prefix), completed: false,
          factors: %{}}

      assessment ->
        # Calculate overall score as average of Big Five factors normalized to 0-100
        factors = %{
          openness: assessment.openness_score,
          conscientiousness: assessment.conscientiousness_score,
          extraversion: assessment.extraversion_score,
          agreeableness: assessment.agreeableness_score,
          neuroticism: assessment.neuroticism_score
        }

        factor_values = factors |> Map.values() |> Enum.reject(&is_nil/1)

        score =
          if factor_values != [] do
            avg = Enum.sum(factor_values) / length(factor_values)
            # Normalize from 0-5 scale to 0-100
            Float.round(avg / 5 * 100, 1)
          else
            0.0
          end

        total = count_psychometric_students(prefix)

        # Rank: count students with higher average factor score
        higher_count =
          from(a in StudentPsychometricAssessment,
            where: a.status == "completed",
            group_by: a.student_id,
            select: %{
              student_id: a.student_id,
              avg_score: fragment(
                "MAX((COALESCE(?, 0) + COALESCE(?, 0) + COALESCE(?, 0) + COALESCE(?, 0) + COALESCE(?, 0)) / 5.0)",
                a.openness_score, a.conscientiousness_score, a.extraversion_score,
                a.agreeableness_score, a.neuroticism_score
              )
            }
          )
          |> subquery()
          |> where([s], s.avg_score > ^(score / 100 * 5))
          |> Repo.aggregate(:count, prefix: prefix)

        %{
          score: score,
          rank: higher_count + 1,
          total: total,
          completed: true,
          factors: factors
        }
    end
  end

  @doc """
  Gets Case Study score and rank for a student (best `total_score` across
  completed sessions).
  """
  def get_case_study_rank(student_id, prefix) do
    best_score =
      CaseStudySession
      |> where(student_id: ^student_id, status: "completed")
      |> where([c], not is_nil(c.total_score))
      |> Repo.aggregate(:max, :total_score, prefix: prefix)

    case best_score do
      nil ->
        %{score: nil, rank: nil, total: count_case_study_students(prefix), completed: false}

      score ->
        higher_count =
          from(c in CaseStudySession,
            where: c.status == "completed" and not is_nil(c.total_score),
            group_by: c.student_id,
            select: %{student_id: c.student_id, best: max(c.total_score)}
          )
          |> subquery()
          |> where([s], s.best > ^score)
          |> Repo.aggregate(:count, prefix: prefix)

        %{
          score: score,
          rank: higher_count + 1,
          total: count_case_study_students(prefix),
          completed: true
        }
    end
  end

  @doc """
  Gets Mini Project score and rank for a student (best `final_score` across
  sessions at `phase == "completed"` — this type tracks completion via
  phase, not status).
  """
  def get_mini_project_rank(student_id, prefix) do
    best_score =
      StudentMiniProjectSession
      |> where(student_id: ^student_id, phase: "completed")
      |> where([m], not is_nil(m.final_score))
      |> Repo.aggregate(:max, :final_score, prefix: prefix)

    case best_score do
      nil ->
        %{score: nil, rank: nil, total: count_mini_project_students(prefix), completed: false}

      score ->
        higher_count =
          from(m in StudentMiniProjectSession,
            where: m.phase == "completed" and not is_nil(m.final_score),
            group_by: m.student_id,
            select: %{student_id: m.student_id, best: max(m.final_score)}
          )
          |> subquery()
          |> where([s], s.best > ^score)
          |> Repo.aggregate(:count, prefix: prefix)

        %{
          score: score,
          rank: higher_count + 1,
          total: count_mini_project_students(prefix),
          completed: true
        }
    end
  end

  # Count helpers - count distinct students who have completed each assessment

  defp count_mcq_students(prefix) do
    from(a in AssessmentAttempt,
      where: a.status == ^attempt_status_submitted(),
      select: count(a.student_id, :distinct)
    )
    |> Repo.one(prefix: prefix) || 0
  end

  defp count_behavioral_students(prefix) do
    from(ba in StudentBehavioralAssessment,
      where: ba.status == "completed",
      select: count(ba.student_id, :distinct)
    )
    |> Repo.one(prefix: prefix) || 0
  end

  defp count_ats_students(prefix) do
    from(a in StudentAtsPhase,
      where: a.status in ["completed", "manual_review", "errored"],
      select: count(a.student_id, :distinct)
    )
    |> Repo.one(prefix: prefix) || 0
  end

  defp count_jam_students(prefix) do
    from(j in JamSession,
      where: j.status == "completed" and not is_nil(j.final_score),
      select: count(j.student_id, :distinct)
    )
    |> Repo.one(prefix: prefix) || 0
  end

  defp count_interview_students(prefix) do
    from(i in InterviewSession,
      where: i.status == "completed" and not is_nil(i.overall_score),
      select: count(i.student_id, :distinct)
    )
    |> Repo.one(prefix: prefix) || 0
  end

  defp count_psychometric_students(prefix) do
    from(a in StudentPsychometricAssessment,
      where: a.status == "completed",
      select: count(a.student_id, :distinct)
    )
    |> Repo.one(prefix: prefix) || 0
  end

  defp count_case_study_students(prefix) do
    from(c in CaseStudySession,
      where: c.status == "completed",
      select: count(c.student_id, :distinct)
    )
    |> Repo.one(prefix: prefix) || 0
  end

  defp count_mini_project_students(prefix) do
    from(m in StudentMiniProjectSession,
      where: m.phase == "completed",
      select: count(m.student_id, :distinct)
    )
    |> Repo.one(prefix: prefix) || 0
  end

  # ============================================================================
  # VYAASA SCORE - Average of all completed assessment scores (0-100)
  # ============================================================================

  @doc """
  The student's **AI8 score card** — the single composite score shown everywhere
  (student dashboard, profile, shared profile, admin list, PDF reports).

  Delegates to `Contexts.AI8.ai8_index/2`, so every surface reads the one AI8
  engine. This previously computed a separate, unweighted mean of the 6 assessment
  scores it happened to know about (ignoring case study and mini project) and
  divided by *completed* assessments only — which is why the admin dashboard and
  the student's AI8 Overview disagreed.

  Returns `%{ai8_score: float, completed_count: int, total_assessments: int}`.
  """
  def get_ai8_score(student_id, prefix), do: calculate_ai8_score(student_id, prefix)

  def calculate_ai8_score(student_id, prefix) do
    student_id |> AI8.ai8_index(prefix) |> score_card()
  end

  @doc """
  Shape an AI8 profile (from `AI8.ai8_index/2` or a `AI8.ai8_indexes/2` entry)
  into the score-card map the views expect. Kept separate so list views can reuse
  the bulk loader without a query per student.
  """
  def score_card(nil), do: %{ai8_score: 0.0, completed_count: 0, total_assessments: 0}

  def score_card(profile) do
    %{
      ai8_score: Float.round((profile[:index] || 0.0) * 1.0, 1),
      completed_count: Map.get(profile, :modules_completed, 0),
      total_assessments: Map.get(profile, :modules_total, 0)
    }
  end

  # ============================================================================
  # BULK STUDENT SCORES - For admin dashboard
  # ============================================================================

  @doc """
  Gets scores for a single student (lightweight, used per-student in admin list).
  Returns a flat map of scores suitable for enhancing the student struct.
  """
  def get_student_score_summary(student_id, prefix) do
    mcq_pct = get_mcq_percentage(student_id, prefix)
    behavioral_score = get_behavioral_score(student_id, prefix)
    jam_score = get_jam_best_score(student_id, prefix)
    interview_score = get_interview_best_score(student_id, prefix)
    psychometric_score = get_psychometric_score(student_id, prefix)
    case_study_score = get_case_study_score(student_id, prefix)
    mini_project_score = get_mini_project_score(student_id, prefix)

    scores =
      [mcq_pct, behavioral_score, jam_score, interview_score, psychometric_score,
       case_study_score, mini_project_score]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&safe_to_number/1)
      |> Enum.reject(&is_nil/1)

    %{
      mcq_percentage: mcq_pct,
      behavioral_score: behavioral_score,
      jam_score: jam_score,
      interview_score: interview_score,
      psychometric_score: psychometric_score,
      case_study_score: case_study_score,
      mini_project_score: mini_project_score,
      completed_assessments: length(scores)
    }
  end

  # Lightweight score fetchers (no rank calculation)

  defp get_mcq_percentage(student_id, prefix) do
    AssessmentAttempt
    |> where([a], a.student_id == ^student_id and a.status == ^attempt_status_submitted())
    |> order_by([a], desc: a.submitted_at)
    |> limit(1)
    |> select([a], a.percentage)
    |> Repo.one(prefix: prefix)
    |> safe_decimal_to_float()
  end

  defp get_behavioral_score(student_id, prefix) do
    StudentBehavioralAssessment
    |> where(student_id: ^student_id, status: "completed")
    |> where([ba], not is_nil(ba.overall_score) and ba.overall_score > 0)
    |> Repo.aggregate(:max, :overall_score, prefix: prefix)
  end

  defp get_jam_best_score(student_id, prefix) do
    JamSession
    |> where(student_id: ^student_id, status: "completed")
    |> where([j], not is_nil(j.final_score))
    |> Repo.aggregate(:max, :final_score, prefix: prefix)
  end

  defp get_case_study_score(student_id, prefix) do
    CaseStudySession
    |> where(student_id: ^student_id, status: "completed")
    |> where([c], not is_nil(c.total_score))
    |> Repo.aggregate(:max, :total_score, prefix: prefix)
  end

  # The mini project tracks completion via `phase`, not `status`.
  defp get_mini_project_score(student_id, prefix) do
    StudentMiniProjectSession
    |> where(student_id: ^student_id, phase: "completed")
    |> where([m], not is_nil(m.final_score))
    |> Repo.aggregate(:max, :final_score, prefix: prefix)
  end

  defp get_interview_best_score(student_id, prefix) do
    from(i in InterviewSession,
      where: i.student_id == ^student_id and i.status == "completed" and not is_nil(i.overall_score),
      select: max(i.overall_score)
    )
    |> Repo.one(prefix: prefix)
    |> safe_decimal_to_float()
  end

  defp get_psychometric_score(student_id, prefix) do
    case from(a in StudentPsychometricAssessment,
           where: a.student_id == ^student_id and a.status == "completed",
           order_by: [desc: a.attempt_number],
           limit: 1,
           select: %{
             openness: a.openness_score,
             conscientiousness: a.conscientiousness_score,
             extraversion: a.extraversion_score,
             agreeableness: a.agreeableness_score,
             neuroticism: a.neuroticism_score
           }
         )
         |> Repo.one(prefix: prefix) do
      nil ->
        nil

      factors ->
        values = [factors.openness, factors.conscientiousness, factors.extraversion, factors.agreeableness, factors.neuroticism]
        |> Enum.reject(&is_nil/1)

        if values != [] do
          Float.round(Enum.sum(values) / length(values) / 5 * 100, 1)
        else
          nil
        end
    end
  end

  # ============================================================================
  # TENANT-WIDE STATISTICS - For admin dashboard
  # ============================================================================

  @doc """
  Gets overview statistics for the entire tenant.
  Returns student counts, assessment completion rates, and avg Vyaasa Score.
  """
  def get_tenant_overview_stats(students_with_scores) do
    total = length(students_with_scores)
    verified = Enum.count(students_with_scores, &(&1.status == "verified"))
    unverified = Enum.count(students_with_scores, &(&1.status == "unverified"))

    # Vyaasa scores
    ai8_scores =
      students_with_scores
      |> Enum.map(&Map.get(&1, :ai8_score))
      |> Enum.reject(&is_nil/1)

    avg_ai8 =
      if length(ai8_scores) > 0,
        do: Enum.sum(ai8_scores) / length(ai8_scores) |> Float.floor() |> trunc(),
        else: 0

    highest_ai8 = if ai8_scores != [], do: ai8_scores |> Enum.max() |> Float.floor() |> trunc(), else: 0
    students_with_scores_count = length(ai8_scores)

    # Assessment completion counts, one entry per AI8 module (all 8).
    done = fn key -> Enum.count(students_with_scores, &(not is_nil(Map.get(&1, key)))) end

    all_done =
      Enum.count(students_with_scores, fn s ->
        Enum.all?(module_score_keys(), &(not is_nil(Map.get(s, &1))))
      end)

    %{
      total_students: total,
      verified: verified,
      unverified: unverified,
      avg_ai8_score: avg_ai8,
      highest_ai8_score: highest_ai8,
      students_with_scores: students_with_scores_count,
      all_assessments_completed: all_done,
      assessments: %{
        ats: %{completed: done.(:ats_score), total: total},
        mcq: %{completed: done.(:mcq_percentage), total: total},
        behavioral: %{completed: done.(:behavioral_score), total: total},
        jam: %{completed: done.(:jam_score), total: total},
        interview: %{completed: done.(:interview_score), total: total},
        psychometric: %{completed: done.(:psychometric_score), total: total},
        case_study: %{completed: done.(:case_study_score), total: total},
        mini_project: %{completed: done.(:mini_project_score), total: total}
      }
    }
  end

  @doc """
  The score key on an enhanced student map for each AI8 module counted toward
  "fully assessed", in display order. Single source of truth for "which
  modules count" so the drawer, the completion panel and the fully-assessed
  tile can't drift apart. Mini project is excluded from this completion check.
  """
  def module_score_keys do
    [
      :ats_score,
      :mcq_percentage,
      :behavioral_score,
      :psychometric_score,
      :jam_score,
      :interview_score,
      :case_study_score
    ]
  end

  @doc """
  Gets department/specialization-wise statistics from pre-loaded students.
  Groups by specialization and calculates avg scores per group.
  """
  def get_department_stats(students_with_scores) do
    students_with_scores
    |> Enum.group_by(&(&1.specialization || "Unknown"))
    |> Enum.map(fn {dept, students} ->
      ai8_scores =
        students
        |> Enum.map(&Map.get(&1, :ai8_score))
        |> Enum.reject(&is_nil/1)

      avg_ai8 =
        if length(ai8_scores) > 0,
          do: Float.round(Enum.sum(ai8_scores) / length(ai8_scores), 1),
          else: 0.0

      highest = if ai8_scores != [], do: Enum.max(ai8_scores), else: 0

      # Find topper
      topper =
        students
        |> Enum.filter(&(not is_nil(Map.get(&1, :ai8_score))))
        |> Enum.max_by(&Map.get(&1, :ai8_score), fn -> nil end)

      %{
        department: dept,
        student_count: length(students),
        avg_ai8_score: avg_ai8,
        highest_ai8_score: highest,
        scored_count: length(ai8_scores),
        topper: if(topper, do: %{name: "#{topper.first_name} #{topper.last_name}", score: topper.ai8_score}, else: nil)
      }
    end)
    |> Enum.sort_by(& &1.avg_ai8_score, :desc)
  end

  @doc """
  Gets per-assessment statistics (avg, high, low, distribution) from pre-loaded students.
  """
  def get_assessment_stats(students_with_scores) do
    %{
      ats: compute_assessment_stat(students_with_scores, :ats_score, "Resume Score"),
      mcq: compute_assessment_stat(students_with_scores, :mcq_percentage, "MCQ Assessment"),
      behavioral: compute_assessment_stat(students_with_scores, :behavioral_score, "Behavioral"),
      jam: compute_assessment_stat(students_with_scores, :jam_score, "JAM Session"),
      interview: compute_assessment_stat(students_with_scores, :interview_score, "Interactive Session")
    }
  end

  defp compute_assessment_stat(students, field, label) do
    scores =
      students
      |> Enum.map(&Map.get(&1, field))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&safe_to_number/1)
      |> Enum.reject(&is_nil/1)

    count = length(scores)

    if count > 0 do
      %{
        label: label,
        count: count,
        avg: Float.round(Enum.sum(scores) / count, 1),
        high: Float.round(Enum.max(scores) * 1.0, 1),
        low: Float.round(Enum.min(scores) * 1.0, 1),
        bands: %{
          excellent: Enum.count(scores, &(&1 >= 80)),
          good: Enum.count(scores, &(&1 >= 60 and &1 < 80)),
          average: Enum.count(scores, &(&1 >= 40 and &1 < 60)),
          below: Enum.count(scores, &(&1 < 40))
        }
      }
    else
      %{label: label, count: 0, avg: 0.0, high: 0.0, low: 0.0, bands: %{excellent: 0, good: 0, average: 0, below: 0}}
    end
  end

  @doc """
  Gets top N students by Vyaasa Score from pre-loaded data.

  Only students who have completed **all** six assessments (Resume, MCQ,
  Behavioral, JAM, Interactive Session, Psychometric) are eligible — a partial
  Vyaasa Score should not be allowed to crown someone as top 1 / top 2 over
  candidates who finished the full evaluation.
  """
  def get_top_rankers(students_with_scores, limit \\ 10) do
    students_with_scores
    |> Enum.filter(&completed_all_assessments?/1)
    |> Enum.filter(&(not is_nil(Map.get(&1, :ai8_score))))
    |> Enum.sort_by(&Map.get(&1, :ai8_score), :desc)
    |> Enum.take(limit)
    |> Enum.with_index(1)
    |> Enum.map(fn {student, rank} ->
      %{
        rank: rank,
        name: "#{student.first_name} #{student.last_name}",
        email: student.email,
        degree: student.degree || "N/A",
        specialization: student.specialization || "N/A",
        registration_id: student.registration_id,
        ai8_score: student.ai8_score,
        ats_score: safe_to_number(Map.get(student, :ats_score)),
        mcq_percentage: Map.get(student, :mcq_percentage),
        behavioral_score: Map.get(student, :behavioral_score),
        jam_score: Map.get(student, :jam_score),
        interview_score: Map.get(student, :interview_score),
        psychometric_score: Map.get(student, :psychometric_score)
      }
    end)
  end

  @doc """
  Returns true only when the student has a score for EVERY assessment module.

  "All modules" here = the 6 assessments this list view carries a column for:
  ATS/resume, MCQ, behavioral, JAM, interview, and psychometric. A module is
  considered complete only when its score on the enhanced student map is non-nil.

  NOTE: this is a *display* gate, narrower than the AI8 itself — the AI8 index
  spans 8 modules (these 6 plus case study and mini project). Use
  `ai8_completed`/`ai8_total` on the enhanced student for true AI8 completion.

  Used to gate the leaderboard / top-performers view so only fully-assessed
  students are ranked.
  """
  def completed_all_modules?(student) do
    not is_nil(Map.get(student, :ats_score)) and
      not is_nil(Map.get(student, :mcq_percentage)) and
      not is_nil(Map.get(student, :behavioral_score)) and
      not is_nil(Map.get(student, :jam_score)) and
      not is_nil(Map.get(student, :interview_score)) and
      not is_nil(Map.get(student, :psychometric_score))
  end

  defp completed_all_assessments?(student), do: completed_all_modules?(student)

  @doc """
  Gets top 5 students per assessment type.
  """
  def get_assessment_toppers(students_with_scores, limit \\ 5) do
    %{
      ats: get_toppers_for(students_with_scores, :ats_score, limit),
      mcq: get_toppers_for(students_with_scores, :mcq_percentage, limit),
      behavioral: get_toppers_for(students_with_scores, :behavioral_score, limit),
      jam: get_toppers_for(students_with_scores, :jam_score, limit),
      interview: get_toppers_for(students_with_scores, :interview_score, limit),
      psychometric: get_toppers_for(students_with_scores, :psychometric_score, limit)
    }
  end

  defp get_toppers_for(students, field, limit) do
    students
    |> Enum.filter(&(not is_nil(Map.get(&1, field))))
    |> Enum.sort_by(&(safe_to_number(Map.get(&1, field)) || 0), :desc)
    |> Enum.take(limit)
    |> Enum.with_index(1)
    |> Enum.map(fn {student, rank} ->
      %{
        rank: rank,
        name: "#{student.first_name} #{student.last_name}",
        specialization: student.specialization || "N/A",
        score: safe_to_number(Map.get(student, field))
      }
    end)
  end

  @doc """
  Gets low performers (below threshold) for admin attention.
  """
  def get_low_performers(students_with_scores, threshold \\ 40) do
    students_with_scores
    |> Enum.filter(fn s ->
      vs = Map.get(s, :ai8_score)
      not is_nil(vs) and vs < threshold
    end)
    |> Enum.sort_by(&Map.get(&1, :ai8_score))
    |> Enum.map(fn s ->
      %{
        name: "#{s.first_name} #{s.last_name}",
        email: s.email,
        specialization: s.specialization || "N/A",
        ai8_score: s.ai8_score
      }
    end)
  end

  # ============================================================================
  # ALERTS & ACTION CENTER
  # ============================================================================

  @doc """
  Gets alert counts for the action center.
  """
  def get_alerts(all_students, scored_students) do
    low_performers =
      scored_students
      |> Enum.filter(fn s ->
        vs = Map.get(s, :ai8_score)
        not is_nil(vs) and vs < 40
      end)
      |> Enum.sort_by(&Map.get(&1, :ai8_score))

    incomplete_profiles =
      all_students
      |> Enum.filter(&(&1.status in ["pending", "profile_incomplete"]))

    # Verified students who haven't completed ANY assessment
    not_started =
      scored_students
      |> Enum.filter(fn s ->
        s.status == "verified" and
        is_nil(Map.get(s, :ats_score)) and
        is_nil(Map.get(s, :mcq_percentage)) and
        is_nil(Map.get(s, :behavioral_score)) and
        is_nil(Map.get(s, :jam_score)) and
        is_nil(Map.get(s, :interview_score))
      end)

    integrity_flagged =
      scored_students
      |> Enum.filter(fn s ->
        flags = Map.get(s, :integrity_flags, [])
        is_list(flags) and length(flags) > 0
      end)

    %{
      low_performers: %{count: length(low_performers), students: low_performers},
      incomplete_profiles: %{count: length(incomplete_profiles), students: incomplete_profiles},
      not_started: %{count: length(not_started), students: not_started},
      integrity_flags: %{count: length(integrity_flagged), students: integrity_flagged}
    }
  end

  @doc """
  Gets enhanced overview stats including profile completion and assessment rates.
  """
  def get_full_overview_stats(all_students, scored_students) do
    base = get_tenant_overview_stats(scored_students)

    total_all = length(all_students)
    profile_completed = Enum.count(all_students, &(&1.profile_completed == true))
    profile_rate = if total_all > 0, do: Float.round(profile_completed / total_all * 100, 1), else: 0.0

    # Avg assessment completion rate per student (out of 5)
    avg_completion_rate =
      if length(scored_students) > 0 do
        total_completions =
          scored_students
          |> Enum.map(fn s ->
            count = 0
            count = if not is_nil(Map.get(s, :ats_score)), do: count + 1, else: count
            count = if not is_nil(Map.get(s, :mcq_percentage)), do: count + 1, else: count
            count = if not is_nil(Map.get(s, :behavioral_score)), do: count + 1, else: count
            count = if not is_nil(Map.get(s, :jam_score)), do: count + 1, else: count
            count = if not is_nil(Map.get(s, :interview_score)), do: count + 1, else: count
            count
          end)
          |> Enum.sum()

        Float.round(total_completions / (length(scored_students) * 5) * 100, 1)
      else
        0.0
      end

    Map.merge(base, %{
      total_all_students: total_all,
      profile_completed: profile_completed,
      profile_completion_rate: profile_rate,
      avg_assessment_completion_rate: avg_completion_rate
    })
  end

  # ============================================================================
  # YEAR-WISE BREAKDOWN
  # ============================================================================

  @doc """
  Gets year-wise student breakdown and performance stats.
  """
  def get_year_wise_stats(students_with_scores) do
    students_with_scores
    |> Enum.group_by(&(&1.year_of_passing || "Unknown"))
    |> Enum.map(fn {year, students} ->
      ai8_scores =
        students
        |> Enum.map(&Map.get(&1, :ai8_score))
        |> Enum.reject(&is_nil/1)

      avg = if length(ai8_scores) > 0, do: Float.round(Enum.sum(ai8_scores) / length(ai8_scores), 1), else: 0.0

      %{
        year: year,
        student_count: length(students),
        scored_count: length(ai8_scores),
        avg_ai8_score: avg
      }
    end)
    |> Enum.sort_by(& &1.year, :desc)
  end

  # ============================================================================
  # CGPA CORRELATION
  # ============================================================================

  @doc """
  Gets CGPA vs Vyaasa Score data for scatter plot.
  """
  def get_cgpa_correlation(students_with_scores) do
    students_with_scores
    |> Enum.filter(fn s ->
      cgpa = Map.get(s, :cgpa)
      vs = Map.get(s, :ai8_score)
      not is_nil(cgpa) and not is_nil(vs) and cgpa > 0
    end)
    |> Enum.map(fn s ->
      cgpa = safe_to_number(Map.get(s, :cgpa)) || 0
      %{
        name: "#{s.first_name} #{s.last_name}",
        specialization: s.specialization || "N/A",
        cgpa: Float.round(cgpa * 1.0, 2),
        ai8_score: s.ai8_score
      }
    end)
    |> Enum.sort_by(& &1.cgpa, :desc)
  end

  @doc """
  Gets ATS score distribution for resume quality chart.
  """
  def get_ats_distribution(students_with_scores) do
    scores =
      students_with_scores
      |> Enum.map(&Map.get(&1, :ats_score))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&(safe_to_number(&1) || 0))

    %{
      total: length(scores),
      excellent: Enum.count(scores, &(&1 >= 80)),
      good: Enum.count(scores, &(&1 >= 60 and &1 < 80)),
      average: Enum.count(scores, &(&1 >= 40 and &1 < 60)),
      below: Enum.count(scores, &(&1 < 40)),
      avg: if(length(scores) > 0, do: Float.round(Enum.sum(scores) / length(scores), 1), else: 0.0)
    }
  end

  defp safe_decimal_to_float(nil), do: nil
  defp safe_decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp safe_decimal_to_float(n) when is_number(n), do: n
  defp safe_decimal_to_float(_), do: nil

  defp safe_to_number(nil), do: nil
  defp safe_to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp safe_to_number(n) when is_number(n), do: n * 1.0
  defp safe_to_number(_), do: nil
end
