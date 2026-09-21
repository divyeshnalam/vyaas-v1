defmodule VyaasaCampus.Reports do
  @moduledoc """
  Server-side report generation for student assessments.

  Loads context data and delegates PDF rendering to TypstRenderer, which
  compiles Typst templates (priv/typst/*.typ) — no Chrome or browser required.
  """

  require Logger

  alias VyaasaCampus.AI8.Dimensions
  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.Contexts.Assessments
  alias VyaasaCampus.Contexts.Interview
  alias VyaasaCampus.Contexts.Jam
  alias VyaasaCampus.Contexts.StudentRankings
  alias VyaasaCampus.Contexts.Students
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Assessments.AssessmentAttempt
  alias VyaasaCampus.Schema.CaseStudy.CaseStudySession
  alias VyaasaCampus.Schema.Students.StudentAtsPhase
  alias VyaasaCampus.Schema.Students.StudentBehavioralAssessment
  alias VyaasaCampus.Schema.Students.StudentMiniProjectSession
  alias VyaasaCampus.Schema.Students.StudentPsychometricAssessment

  @type report_type ::
          :mcq
          | :jam
          | :psychometric
          | :behavioral
          | :interview
          | :case_study
          | :ai8
          | :resume
          | :leaderboard
          | :specialization
          | :analytics
          | :readiness
          | :employability_card
          | :certificate

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  @spec generate_pdf(report_type, String.t() | integer, String.t()) ::
          {:ok, binary} | {:error, term}
  def generate_pdf(type, id, tenant_schema) do
    Logger.info("REPORT_PDF | generate_pdf start | type=#{type} id=#{inspect(id)} tenant=#{tenant_schema}")

    case load_context(type, id, tenant_schema) do
      {:ok, context} ->
        VyaasaCampus.Reports.TypstRenderer.render(type, context)

      {:error, reason} = err ->
        Logger.error("REPORT_PDF | load_context FAILED | type=#{type} id=#{inspect(id)} reason=#{inspect(reason)}")
        err
    end
  end

  @doc """
  Returns a suggested filename for the given report.
  """
  def filename(:mcq, %{assessment: %{title: title}}), do: build_filename("MCQ", title)
  def filename(:jam, %{session: %{topic_title: topic}}), do: build_filename("JAM", topic || "Session")
  def filename(:psychometric, _ctx), do: build_filename("Psychometric", "BigFive")
  def filename(:behavioral, %{candidate_name: name}), do: build_filename("Behavioral", name || "Report")
  def filename(:interview, %{candidate_name: name}), do: build_filename("Interview", name || "Session")
  def filename(:case_study, %{scenario_title: title}), do: build_filename("CaseStudy", title || "Report")
  def filename(:mini_project, ctx), do: build_filename("mini-project", student_slug(ctx[:student]))
  def filename(:ai8, ctx), do: build_filename("AI8", student_slug(ctx[:student]))
  def filename(:resume, ctx), do: build_filename("Resume", student_slug(ctx[:student]))
  def filename(:leaderboard, _ctx), do: build_filename("Leaderboard", "Overall")
  def filename(:specialization, _ctx), do: build_filename("Specializations", "Performance")
  def filename(:analytics, %{tenant_name: name}), do: build_filename("Analytics", name || "Overview")
  def filename(:readiness, %{tenant_name: name}), do: build_filename("PlacementReadiness", name || "Overview")
  def filename(:employability_card, ctx), do: build_filename("EmployabilityCard", student_slug(ctx[:student]))
  def filename(:certificate, ctx), do: build_filename("Certificate", student_slug(ctx[:student]))

  @doc """
  Loads the render context for a report type. Exposed so callers (controller,
  Oban worker) can share the lookup + authorization check.
  """
  def load_context(:mcq, id, tenant_schema), do: load_mcq_context(id, tenant_schema)
  def load_context(:jam, id, tenant_schema), do: load_jam_context(id, tenant_schema)
  def load_context(:psychometric, id, tenant_schema), do: load_psychometric_context(id, tenant_schema)
  def load_context(:behavioral, id, tenant_schema), do: load_behavioral_context(id, tenant_schema)
  def load_context(:interview, id, tenant_schema), do: load_interview_context(id, tenant_schema)
  def load_context(:case_study, id, tenant_schema), do: load_case_study_context(id, tenant_schema)
  def load_context(:mini_project, id, tenant_schema), do: load_mini_project_context(id, tenant_schema)
  def load_context(:ai8, student_id, tenant_schema), do: load_ai8_context(student_id, tenant_schema)
  def load_context(:resume, id, tenant_schema), do: load_resume_context(id, tenant_schema)
  def load_context(:leaderboard, filters, tenant_schema), do: load_leaderboard_context(filters, tenant_schema)
  def load_context(:specialization, _params, tenant_schema), do: load_specialization_context(tenant_schema)
  def load_context(:analytics, _params, tenant_schema), do: load_analytics_context(tenant_schema)
  def load_context(:readiness, _params, tenant_schema), do: load_readiness_context(tenant_schema)

  def load_context(:employability_card, student_id, tenant_schema),
    do: load_employability_card_context(student_id, tenant_schema)

  def load_context(:certificate, student_id, tenant_schema),
    do: load_certificate_context(student_id, tenant_schema)

  @doc false
  def pdf_from_html(_html), do: {:error, :html_rendering_removed}

  # ============================================================================
  # MCQ
  # ============================================================================

  def load_mcq_context(attempt_id, tenant_schema) do
    case Repo.get(AssessmentAttempt, attempt_id, prefix: tenant_schema) do
      nil ->
        {:error, :attempt_not_found}

      attempt ->
        assessment = Assessments.get_assessment!(attempt.assessment_id, tenant_schema)
        student = Students.get_student(attempt.student_id, tenant_schema)

        {:ok, build_mcq_context(attempt, assessment, student)}
    end
  end

  defp build_mcq_context(attempt, assessment, student) do
    eval = attempt.evaluation_data || %{}
    percentage = safe_decimal_to_float(attempt.percentage)
    score = safe_decimal_to_float(attempt.score)

    correct = eval["correct"] || 0
    wrong = eval["wrong"] || 0
    unanswered = eval["unanswered"] || 0
    negative_marks = safe_to_float(eval["negative_marks"])
    total_questions = eval["total_questions"] || length(assessment.settings["questions"] || [])

    time_taken =
      if attempt.started_at && attempt.submitted_at do
        DateTime.diff(attempt.submitted_at, attempt.started_at, :second)
      else
        0
      end

    avg_time_per_question =
      if total_questions > 0,
        do: Float.round(time_taken / 60 / total_questions, 2),
        else: 0.0

    accuracy =
      if correct + wrong > 0, do: correct / (correct + wrong) * 100, else: 0.0

    completion =
      if total_questions > 0, do: (correct + wrong) / total_questions * 100, else: 0.0

    base_context(student, %{
      attempt: attempt,
      assessment: assessment,
      owner_id: attempt.student_id,
      score: score,
      total_marks: assessment.total_marks || 0,
      percentage: percentage,
      correct: correct,
      wrong: wrong,
      unanswered: unanswered,
      negative_marks: negative_marks,
      total_questions: total_questions,
      time_taken: time_taken,
      avg_time_per_question: avg_time_per_question,
      accuracy: accuracy,
      completion: completion,
      performance_label: performance_label(percentage),
      performance_color: performance_color(percentage)
    })
  end

  # ============================================================================
  # JAM
  # ============================================================================

  def load_jam_context(session_id, tenant_schema) do
    case Jam.get_jam_session(session_id, tenant_schema) do
      nil ->
        {:error, :session_not_found}

      session ->
        student = Students.get_student(session.student_id, tenant_schema)
        {:ok, build_jam_context(session, student)}
    end
  end

  defp build_jam_context(session, student) do
    eval = session.evaluation_data || %{}
    final_score = session.final_score || eval["final_score"] || 0

    base_context(student, %{
      session: session,
      owner_id: session.student_id,
      topic_title: session.topic_title || "JAM Session",
      topic_explanation: session.topic_explanation,
      transcript: session.transcript || eval["transcript"],
      word_count: session.word_count || eval["word_count"] || 0,
      speech_duration: session.speech_duration_seconds || eval["speech_duration_seconds"] || 0,
      final_score: final_score,
      overall_score: final_score,
      clarity: session.clarity_score || eval["clarity_score"],
      structure: session.structure_score || eval["structure_score"],
      relevance: session.relevance_score || eval["relevance_score"],
      impact: session.impact_score || eval["impact_score"],
      confidence: session.confidence_score || eval["confidence_score"],
      overall_summary: session.overall_summary || eval["overall_summary"],
      strengths: eval["strengths"] || [],
      improvements: eval["improvements"] || [],
      detailed_feedback: eval["detailed_feedback"] || %{},
      performance_label: performance_label(final_score),
      performance_color: performance_color(final_score)
    })
  end

  # ============================================================================
  # PSYCHOMETRIC
  # ============================================================================

  def load_psychometric_context(assessment_id, tenant_schema) do
    case Repo.get(StudentPsychometricAssessment, assessment_id, prefix: tenant_schema) do
      nil ->
        {:error, :assessment_not_found}

      assessment ->
        student = Students.get_student(assessment.student_id, tenant_schema)
        {:ok, build_psychometric_context(assessment, student)}
    end
  end

  defp build_psychometric_context(assessment, student) do
    composites = psychometric_composites(assessment)
    # Overall = Work Ethics ×0.8 + Teamwork ×0.1 + Initiative & Leadership ×0.1
    overall = round(composites.work_ethics * 0.8 + composites.collaboration * 0.1 + composites.leadership * 0.1)

    base_context(student, %{
      assessment: assessment,
      owner_id: assessment.student_id,
      overall_summary: assessment.overall_summary,
      overall_score: overall,
      composites: composites,
      factor_scores: assessment.factor_scores || %{},
      factor_reports: assessment.factor_reports || %{},
      strengths: assessment.strengths || [],
      development_areas: assessment.development_areas || [],
      suggestions: assessment.suggestions || [],
      performance_label: performance_label(overall),
      performance_color: performance_color(overall),
      scores: %{
        openness: assessment.openness_score,
        conscientiousness: assessment.conscientiousness_score,
        extraversion: assessment.extraversion_score,
        agreeableness: assessment.agreeableness_score,
        neuroticism: assessment.neuroticism_score
      }
    })
  end

  # Three AI8 composites (0-100) from the Big Five trait averages — the mapping
  # the DS team specified (Work Ethics, Teamwork, Initiative & Leadership).
  defp psychometric_composites(a) do
    %{
      work_ethics: trait_composite([a.conscientiousness_score, a.neuroticism_score]),
      collaboration: trait_composite([a.agreeableness_score, a.extraversion_score]),
      leadership: trait_composite([a.openness_score])
    }
  end

  defp trait_composite(traits) do
    vals = Enum.map(traits, fn v -> if(is_number(v), do: v, else: 3.0) end)
    avg = Enum.sum(vals) / length(vals)
    (avg / 5 * 100) |> round() |> min(100) |> max(0)
  end

  # ============================================================================
  # BEHAVIORAL
  # ============================================================================

  def load_behavioral_context(assessment_id, tenant_schema) do
    case Repo.get(StudentBehavioralAssessment, assessment_id, prefix: tenant_schema) do
      nil ->
        {:error, :assessment_not_found}

      assessment ->
        student = Students.get_student(assessment.student_id, tenant_schema)
        {:ok, build_behavioral_context(assessment, student)}
    end
  end

  defp build_behavioral_context(assessment, student) do
    profile = assessment.candidate_profile || %{}
    overall_score = assessment.overall_score || 0

    base_context(student, %{
      assessment: assessment,
      owner_id: assessment.student_id,
      candidate_name:
        profile["candidate_name"] || profile["name"] ||
          (student && "#{student.first_name} #{student.last_name}") || "Candidate",
      role: profile["role"] || profile["desired_role"],
      education: profile["education"],
      overall_score: overall_score,
      summary: assessment.summary,
      strengths: assessment.strengths || [],
      areas_for_development: assessment.areas_for_development || [],
      completed_scenarios: assessment.completed_scenarios || [],
      ratings: assessment.ratings || %{},
      reasoning: assessment.reasoning || %{},
      scores: %{
        work_ethics: assessment.work_ethics_score,
        teamwork: assessment.teamwork_score,
        adaptability: assessment.adaptability_score,
        leadership: assessment.leadership_score,
        communication: assessment.communication_score
      },
      performance_label: performance_label(overall_score),
      performance_color: performance_color(overall_score)
    })
  end

  # ============================================================================
  # INTERVIEW
  # ============================================================================

  def load_interview_context(session_id, tenant_schema) do
    case Interview.get_interview_session(session_id, tenant_schema) do
      nil ->
        {:error, :session_not_found}

      session ->
        student = Students.get_student(session.student_id, tenant_schema)
        {:ok, build_interview_context(session, student)}
    end
  end

  defp build_interview_context(session, student) do
    questions = get_in(session.questions_data || %{}, ["questions"]) || []
    overall_score = safe_decimal_to_float(session.overall_score)
    summary = session.session_summary || %{}

    base_context(student, %{
      session: session,
      owner_id: session.student_id,
      candidate_name:
        session.candidate_name || (student && "#{student.first_name} #{student.last_name}") ||
          "Candidate",
      overall_score: overall_score,
      final_report: session.final_report,
      session_summary: summary,
      competency: interview_competency(summary),
      summary_text: interview_summary_text(summary, session.final_report),
      strengths: session.strengths || [],
      improvements: session.improvements || [],
      questions: questions,
      questions_completed: session.questions_completed || length(questions),
      performance_label: performance_label(overall_score),
      performance_color: performance_color(overall_score)
    })
  end

  # Competency scores (0-100) + weights for the report, from session_summary.
  defp interview_competency(summary) do
    comp = summary["competency"] || %{}

    weights =
      comp["weights"] || %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}

    [
      {"Domain Knowledge & Technical Skills", num(comp["technical"]), pct_label(weights["technical"])},
      {"Communication & Interpersonal Skills", num(comp["communication"]), pct_label(weights["communication"])},
      {"Initiative & Leadership", num(comp["leadership"]), pct_label(weights["leadership"])},
      {"Cultural Fit & Emotional Intelligence", num(comp["cultural_fit"]), pct_label(weights["cultural_fit"])}
    ]
  end

  # Coerce a competency value to a number. The engine stores floats, but be
  # defensive: a Decimal or numeric string must not reach the template's
  # `round/1` as-is (that raises and crashes the whole PDF render → no email).
  defp num(v) when is_number(v), do: v
  defp num(%Decimal{} = d), do: Decimal.to_float(d)

  defp num(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0
    end
  end

  defp num(_), do: 0

  defp pct_label(w) when is_number(w), do: "#{round(w * 100)}%"
  defp pct_label(%Decimal{} = d), do: pct_label(Decimal.to_float(d))
  defp pct_label(w) when is_binary(w), do: pct_label(num(w))
  defp pct_label(_), do: ""

  # Overall summary text: prefer the stored value, else pull the "Overall
  # Summary" section out of the final-report markdown.
  defp interview_summary_text(summary, final_report) do
    case summary["summary"] do
      s when is_binary(s) and s != "" -> s
      _ -> extract_markdown_section(final_report, "Overall Summary")
    end
  end

  defp extract_markdown_section(nil, _), do: ""

  defp extract_markdown_section(md, heading) do
    md
    |> String.split("\n")
    |> Enum.drop_while(&(not String.contains?(&1, heading)))
    |> Enum.drop(1)
    |> Enum.take_while(&(not String.starts_with?(String.trim(&1), "#")))
    |> Enum.join(" ")
    |> String.trim()
  end

  # ============================================================================
  # CASE STUDY
  # ============================================================================

  def load_case_study_context(session_id, tenant_schema) do
    case Repo.get(CaseStudySession, session_id, prefix: tenant_schema) do
      nil ->
        {:error, :session_not_found}

      session ->
        student = Students.get_student(session.student_id, tenant_schema)
        {:ok, build_case_study_context(session, student)}
    end
  end

  defp build_case_study_context(session, student) do
    report = session.report || %{}
    total = session.total_score || 0

    base_context(student, %{
      session: session,
      owner_id: session.student_id,
      scenario_title: get_in(session.scenario || %{}, ["title"]) || "Case Study",
      specialization: session.specialization_sub || session.specialization_group,
      # Each sub-score is shown against its own max (domain /40, the others /30).
      scores: [
        {"Domain Expertise", session.domain_score || 0, 40, report["domain_feedback"]},
        {"Problem Solving", session.problem_solving_score || 0, 30, report["problem_solving_feedback"]},
        {"Initiative & Leadership", session.leadership_score || 0, 30, report["leadership_feedback"]}
      ],
      total_score: total,
      summary: report["summary"],
      strengths: report["strengths"] || [],
      improvements: report["improvements"] || [],
      verdict: report["overall_verdict"],
      performance_label: performance_label(total),
      performance_color: performance_color(total)
    })
  end

  # ============================================================================
  # MINI PROJECT
  # ============================================================================

  def load_mini_project_context(session_id, tenant_schema) do
    case Repo.get(StudentMiniProjectSession, session_id, prefix: tenant_schema) do
      nil ->
        {:error, :session_not_found}

      session ->
        student = Students.get_student(session.student_id, tenant_schema)
        {:ok, build_mini_project_context(session, student)}
    end
  end

  defp build_mini_project_context(session, student) do
    total = session.final_score || 0
    scenario = session.chosen_scenario || %{}

    base_context(student, %{
      session: session,
      owner_id: session.student_id,
      role_title: scenario["role_title"] || "Mini Project",
      specialization: session.specialization_name,
      total_score: total,
      grade_band: session.grade_band,
      # {label, score /100, AI8 weight %}
      indexes: [
        {"Domain Knowledge & Technical Skills", session.domain_index || 0, 56},
        {"Collaboration & Teamwork", session.collaboration_index || 0, 22},
        {"Initiative & Leadership", session.initiative_index || 0, 22}
      ],
      strengths: session.strengths || [],
      improvements: session.improvements || [],
      summary: session.report_markdown,
      performance_label: performance_label(total),
      performance_color: performance_color(total)
    })
  end

  # ============================================================================
  # AI8 PROFILE (aggregate across all assessments)
  # ============================================================================

  def load_ai8_context(student_id, tenant_schema) do
    student = Students.get_student(student_id, tenant_schema)
    profile = AI8.ai8_index(student_id, tenant_schema)
    {:ok, build_ai8_context(student_id, student, profile)}
  end

  defp build_ai8_context(student_id, student, profile) do
    dims =
      Enum.map(Dimensions.all(), fn {key, label} ->
        sk = Atom.to_string(key)
        %{key: sk, label: label, score: round(Map.get(profile.dimensions, sk, 0) || 0)}
      end)

    assessed = Enum.filter(dims, &(&1.score > 0))
    index = round(profile.index || profile.overall || 0)

    base_context(student, %{
      owner_id: student_id,
      dims: dims,
      index: index,
      completion: if(profile.completion, do: round(profile.completion), else: nil),
      strength: Enum.max_by(assessed, & &1.score, fn -> nil end),
      opportunity: Enum.min_by(assessed, & &1.score, fn -> nil end),
      performance_label: performance_label(index),
      performance_color: performance_color(index)
    })
  end

  # ============================================================================
  # EMPLOYABILITY CARD (2-page front/back mirror of the on-screen flip card)
  # ============================================================================

  def load_employability_card_context(student_id, tenant_schema) do
    student = Students.get_student(student_id, tenant_schema)
    ai8_profile = AI8.ai8_index(student_id, tenant_schema)
    score = round(ai8_profile.index)

    {:ok,
     base_context(student, %{
       owner_id: student_id,
       student_name: card_full_name(student),
       role: (student && student.degree) || "Student",
       initials: initials(card_full_name(student)),
       cert_id: cert_id(student_id),
       score: score,
       tier: tier_info(score),
       _qr_path: generate_qr_temp_file(share_profile_url(student_id, tenant_schema))
     })}
  end

  defp card_full_name(nil), do: "Student"
  defp card_full_name(student), do: String.trim("#{student.first_name} #{student.last_name}")

  # ============================================================================
  # CERTIFICATE (1-page mirror of the on-screen "View Certificate" tab)
  # ============================================================================

  def load_certificate_context(student_id, tenant_schema) do
    student = Students.get_student(student_id, tenant_schema)
    ai8_profile = AI8.ai8_index(student_id, tenant_schema)
    score = round(ai8_profile.index)
    today = Date.utc_today()

    {:ok,
     base_context(student, %{
       owner_id: student_id,
       student_name: card_full_name(student),
       cert_id: cert_id(student_id),
       issued_on: Calendar.strftime(today, "%d %B %Y"),
       valid_until: Calendar.strftime(Date.add(today, 365), "%d %B %Y"),
       score: score,
       _qr_path: generate_qr_temp_file(share_profile_url(student_id, tenant_schema))
     })}
  end

  @doc """
  Deterministic per-student certificate id, e.g. "VYA-2026-004821". Shared by
  the on-screen employability card/certificate and the emailed PDF so both
  always show the same id.
  """
  def cert_id(student_id) do
    year = Date.utc_today().year
    suffix = student_id |> :erlang.phash2(999_999) |> Integer.to_string() |> String.pad_leading(6, "0")
    "VYA-#{year}-#{suffix}"
  end

  @doc "Up to two initials from a full name, e.g. \"Ravi Kiran\" -> \"RK\"."
  def initials(name) when is_binary(name) and name != "" do
    name
    |> String.split(" ", trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  def initials(_), do: "S"

  @doc """
  Employability tier shown on the card back + certificate. Buckets are
  approximate (no live percentile-ranking query yet) — thresholds chosen so
  a representative 82 score reads as "Gold" / "Top 12%" / "High Potential" /
  "Placement Ready".
  """
  def tier_info(score) when score >= 90,
    do: %{level: "Platinum", percentile: "Top 5%", potential: "Exceptional Potential", readiness: "Placement Ready"}

  def tier_info(score) when score >= 75,
    do: %{level: "Gold", percentile: "Top 12%", potential: "High Potential", readiness: "Placement Ready"}

  def tier_info(score) when score >= 60,
    do: %{level: "Silver", percentile: "Top 35%", potential: "Growing Potential", readiness: "Almost Ready"}

  def tier_info(_score), do: %{level: "Bronze", percentile: "-", potential: "Early Stage", readiness: "Needs Practice"}

  @doc """
  QR points at the same no-auth shared-profile link used by the dashboard's
  "Share profile" action (same slug — `share_profile_url/2` is idempotent),
  so scanning it lands on the real public profile rather than a dead
  placeholder.
  """
  def share_profile_qr_url(student_id, tenant_schema) do
    png = student_id |> share_profile_url(tenant_schema) |> EQRCode.encode(:q) |> EQRCode.png(width: 400)
    "data:image/png;base64,#{Base.encode64(png)}"
  end

  @doc "The student's short, stable, no-auth shareable profile URL."
  def share_profile_url(student_id, tenant_schema) do
    slug = VyaasaCampus.Contexts.SharedProfileLinks.get_or_create_slug(student_id, tenant_schema)
    base_url = Application.get_env(:vyaasa_campus, :frontend_url, "http://localhost:4000")
    base_url <> "/profile/shared/#{slug}"
  end

  # Renders the QR locally (no network round trip) so Typst (which has no
  # network access) can embed it. TypstRenderer deletes this file after
  # compiling — returning "" (rather than raising) lets the PDF still render,
  # just without the QR, if encoding somehow fails.
  #
  # Error-correction level :q (~25% recoverable), not the default :l (~7%):
  # both card templates place the Vyaasa mark on top of the QR's center, and
  # :l's error budget isn't enough to survive that overlay once the PDF gets
  # rasterized/printed — it decoded fine as a raw PNG but failed after going
  # through Typst -> PDF -> real-world scan.
  defp generate_qr_temp_file(data) do
    png = data |> EQRCode.encode(:q) |> EQRCode.png(width: 400)
    path = Path.join(System.tmp_dir!(), "vyaasa_qr_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}.png")
    File.write!(path, png)
    path
  rescue
    e ->
      Logger.warning("EMPLOYABILITY_CARD | QR generation failed | #{inspect(e)}")
      ""
  end

  # ============================================================================
  # RESUME (ATS analysis)
  # ============================================================================

  def load_resume_context(phase_id, tenant_schema) do
    case Repo.get(StudentAtsPhase, phase_id, prefix: tenant_schema) do
      nil ->
        {:error, :phase_not_found}

      phase ->
        student = Students.get_student(phase.student_id, tenant_schema)
        {:ok, build_resume_context(phase, student)}
    end
  end

  defp build_resume_context(phase, student) do
    meta = phase.metadata || %{}
    score = round(safe_decimal_to_float(phase.ats_score))
    summary = phase.professional_summary || %{}

    improvements =
      (meta["completeness_feedback"] || []) ++
        (meta["relevance_feedback"] || []) ++
        (meta["sanity_feedback"] || [])

    base_context(student, %{
      phase: phase,
      owner_id: phase.student_id,
      score: score,
      subscores: [
        {"Completeness", safe_pct(meta["completeness_score"])},
        {"Relevance", safe_pct(meta["relevance_score"])},
        {"Sanity Check", safe_pct(meta["sanity_score"])}
      ],
      summary_text: summary["summary"] || summary["professional_summary"],
      total_experience: summary["total_experience"],
      technical_skills: resume_skills(phase.skills, "technical_skills"),
      non_technical_skills: resume_skills(phase.skills, "non_technical_skills"),
      experience_count: length(phase.work_experience || []),
      projects_count: length(phase.projects || []),
      education_count: length(phase.education || []),
      improvements: improvements,
      performance_label: performance_label(score),
      performance_color: performance_color(score)
    })
  end

  defp safe_pct(nil), do: 0
  defp safe_pct(n) when is_number(n), do: round(n)
  defp safe_pct(_), do: 0

  # Skills may be a list of strings or of maps ({"name"|"skill" => ...}); normalise
  # to a flat list of strings for the report.
  defp resume_skills(skills, key) when is_map(skills) do
    case skills[key] || skills[String.to_atom(key)] do
      list when is_list(list) ->
        Enum.map(list, fn
          s when is_binary(s) -> s
          m when is_map(m) -> m["name"] || m["skill"] || m["title"] || ""
          other -> to_string(other)
        end)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  defp resume_skills(_, _), do: []

  # ============================================================================
  # LEADERBOARD (admin)
  # ============================================================================

  @doc false
  def load_leaderboard_context(filters, tenant_schema) do
    filters = normalize_filters(filters)

    scored =
      VyaasaCampusWeb.TenantUser.DashboardLive.load_all_students_with_scores(tenant_schema)

    filtered = apply_leaderboard_filters(scored, filters)
    rankers = StudentRankings.get_top_rankers(filtered, 100)

    {:ok,
     %{
       generated_at: format_generated_at(DateTime.utc_now()),
       student: nil,
       filters: filters,
       subtitle: leaderboard_subtitle(filters),
       rankers: rankers,
       total: length(rankers)
     }}
  end

  # ============================================================================
  # SPECIALIZATION (admin)
  # ============================================================================

  @doc false
  def load_specialization_context(tenant_schema) do
    tenant = VyaasaCampus.Contexts.Tenants.get_tenant_by_schema_name(tenant_schema)
    tenant_name = (tenant && (tenant.full_name || tenant.alias)) || tenant_schema

    scored =
      VyaasaCampusWeb.TenantUser.DashboardLive.load_all_students_with_scores(tenant_schema)

    dept_stats = StudentRankings.get_department_stats(scored)

    departments =
      dept_stats
      |> Enum.with_index(1)
      |> Enum.map(fn {dept, rank} ->
        {status, color} = readiness_status(dept.avg_ai8_score)

        %{
          rank: rank,
          name: dept.department,
          count: dept.student_count,
          avg: round(dept.avg_ai8_score),
          status: status,
          color: color,
          topper: (dept.topper && dept.topper.name) || "—"
        }
      end)

    total_departments = length(departments)
    total_students = Enum.sum(Enum.map(dept_stats, & &1.student_count))

    overall_avg =
      if total_departments > 0,
        do: Float.round(Enum.sum(Enum.map(dept_stats, & &1.avg_ai8_score)) / total_departments, 1),
        else: 0.0

    top_dept = List.first(departments)

    summary_tiles = [
      %{label: "Specializations", value: to_string(total_departments), caption: "tracked departments"},
      %{label: "Students Scored", value: to_string(total_students), caption: "across all specializations"},
      %{label: "Average Score", value: to_string(overall_avg), caption: "across departments"}
    ]

    {:ok,
     %{
       generated_at: format_generated_at(DateTime.utc_now()),
       student: nil,
       tenant_name: tenant_name,
       subtitle: "#{total_departments} specializations · sorted by Vyaasa Score across #{tenant_name}",
       summary_tiles: summary_tiles,
       top_department: top_dept,
       departments: departments
     }}
  end

  # ============================================================================
  # ANALYTICS (admin) — mirrors the tenant-admin dashboard's Overview tab:
  # readiness/completion stats, alerts, and department breakdown.
  # ============================================================================

  @doc false
  def load_analytics_context(tenant_schema) do
    tenant = VyaasaCampus.Contexts.Tenants.get_tenant_by_schema_name(tenant_schema)
    tenant_name = (tenant && (tenant.full_name || tenant.alias)) || tenant_schema

    all_raw_students = Students.list_students(tenant_schema)
    scored_students = VyaasaCampusWeb.TenantUser.DashboardLive.load_all_students_with_scores(tenant_schema)

    overview = StudentRankings.get_full_overview_stats(all_raw_students, scored_students)
    department_stats = StudentRankings.get_department_stats(scored_students)
    alerts = StudentRankings.get_alerts(all_raw_students, scored_students)

    ready_count = Enum.count(scored_students, &((Map.get(&1, :ai8_score) || 0) >= 70))

    ready_pct =
      if overview.total_all_students > 0,
        do: round(ready_count / overview.total_all_students * 100),
        else: 0

    top_performer =
      case StudentRankings.get_top_rankers(scored_students, 1) do
        [%{name: name, ai8_score: score} | _] -> %{name: name, score: score}
        _ -> nil
      end

    {:ok,
     %{
       generated_at: format_generated_at(DateTime.utc_now()),
       student: nil,
       tenant_name: tenant_name,
       subtitle: "Readiness, potential and placement insight across #{tenant_name}",
       overview: overview,
       ready_count: ready_count,
       ready_pct: ready_pct,
       top_performer: top_performer,
       department_stats: department_stats,
       alerts: %{
         low_performers: alerts.low_performers.count,
         incomplete_profiles: alerts.incomplete_profiles.count,
         not_started: alerts.not_started.count,
         integrity_flags: alerts.integrity_flags.count
       }
     }}
  end

  # ============================================================================
  # PLACEMENT READINESS (admin) — a premium AI-dashboard-style read of the
  # tenant-admin Placement Readiness tab: funnel KPIs, department ranking,
  # attention alerts, and generated insight highlights.
  # ============================================================================

  @doc false
  def load_readiness_context(tenant_schema) do
    tenant = VyaasaCampus.Contexts.Tenants.get_tenant_by_schema_name(tenant_schema)
    tenant_name = (tenant && (tenant.full_name || tenant.alias)) || tenant_schema

    all_raw_students = Students.list_students(tenant_schema)
    scored_students = VyaasaCampusWeb.TenantUser.DashboardLive.load_all_students_with_scores(tenant_schema)

    overview = StudentRankings.get_full_overview_stats(all_raw_students, scored_students)
    alerts = StudentRankings.get_alerts(all_raw_students, scored_students)
    total_all = overview.total_all_students
    ready = Enum.count(scored_students, &(readiness_score(&1) >= 70))
    ready_pct = if total_all > 0, do: round(ready / total_all * 100), else: 0
    completion_rate = round(overview.avg_assessment_completion_rate)

    funnel = [
      %{label: "Registered", count: total_all, caption: "total onboarded"},
      %{label: "Profile Complete", count: overview.profile_completed, caption: pct_caption(overview.profile_completed, total_all)},
      %{label: "Assessment Completed", count: overview.all_assessments_completed, caption: pct_caption(overview.all_assessments_completed, total_all)},
      %{label: "Placement Ready", count: ready, caption: "#{ready_pct}% of cohort"}
    ]

    departments =
      StudentRankings.get_department_stats(scored_students)
      |> Enum.with_index(1)
      |> Enum.map(fn {dept, rank} ->
        {status, color} = readiness_status(dept.avg_ai8_score)

        %{
          rank: rank,
          name: dept.department,
          count: dept.student_count,
          avg: round(dept.avg_ai8_score),
          status: status,
          color: color
        }
      end)

    top_dept = List.first(departments)

    insights =
      [
        top_dept &&
          %{
            title: "Highest Performing Department",
            body: "#{top_dept.name} leads with an average score of #{top_dept.avg}.",
            color: "#22C55E"
          },
        %{
          title: "Students Needing Attention",
          body: "#{alerts.incomplete_profiles.count} student(s) still have incomplete profiles.",
          color: "#F59E0B"
        },
        %{
          title: "Placement Readiness",
          body: readiness_insight_text(ready_pct),
          color: "#2563EB"
        },
        %{
          title: "Completion Rate",
          body: "Only #{completion_rate}% of assessments have been completed so far.",
          color: "#8B5CF6"
        }
      ]
      |> Enum.reject(&is_nil/1)

    {:ok,
     %{
       generated_at: format_generated_at(DateTime.utc_now()),
       student: nil,
       tenant_name: tenant_name,
       subtitle: "AI-powered Student Performance Intelligence across #{tenant_name}",
       total_all: total_all,
       ready_count: ready,
       ready_pct: ready_pct,
       funnel: funnel,
       departments: departments,
       alerts: %{
         low_performers: alerts.low_performers.count,
         incomplete_profiles: alerts.incomplete_profiles.count,
         not_started: alerts.not_started.count,
         integrity_flags: alerts.integrity_flags.count
       },
       insights: insights
     }}
  end

  defp readiness_score(s), do: safe_to_float(Map.get(s, :ai8_score))

  defp pct_caption(_count, 0), do: "0% of cohort"
  defp pct_caption(count, total), do: "#{round(count / total * 100)}% of cohort"

  defp readiness_status(avg) when avg >= 90, do: {"Excellent", "#22C55E"}
  defp readiness_status(avg) when avg >= 75, do: {"Good", "#F59E0B"}
  defp readiness_status(avg) when avg >= 60, do: {"Average", "#F97316"}
  defp readiness_status(avg) when avg >= 40, do: {"Needs Attention", "#EF4444"}
  defp readiness_status(_avg), do: {"Critical", "#1E293B"}

  defp readiness_insight_text(pct) when pct < 20,
    do: "Placement readiness remains very low at #{pct}% — early intervention is recommended."

  defp readiness_insight_text(pct) when pct < 50,
    do: "Placement readiness is moderate at #{pct}%, with room to improve."

  defp readiness_insight_text(pct), do: "Placement readiness is strong at #{pct}%."

  defp normalize_filters(filters) when is_map(filters) do
    %{
      department: blank_to_all(Map.get(filters, "department") || Map.get(filters, :department)),
      specialization: blank_to_all(Map.get(filters, "specialization") || Map.get(filters, :specialization)),
      year: blank_to_all(Map.get(filters, "year") || Map.get(filters, :year))
    }
  end

  defp normalize_filters(_), do: normalize_filters(%{})

  defp blank_to_all(nil), do: "all"
  defp blank_to_all(""), do: "all"
  defp blank_to_all(v), do: to_string(v)

  defp apply_leaderboard_filters(students, %{department: dept, specialization: spec, year: year}) do
    students
    |> filter_field(:degree, dept)
    |> filter_field(:specialization, spec)
    |> filter_year(year)
  end

  defp filter_field(list, _field, "all"), do: list

  defp filter_field(list, field, value),
    do: Enum.filter(list, fn s -> Map.get(s, field) == value end)

  defp filter_year(list, "all"), do: list

  defp filter_year(list, value),
    do: Enum.filter(list, fn s -> to_string(Map.get(s, :year_of_passing)) == to_string(value) end)

  defp leaderboard_subtitle(%{department: dept, specialization: spec, year: year}) do
    parts =
      []
      |> add_if(dept != "all", "Dept: #{dept}")
      |> add_if(spec != "all", "Spec: #{spec}")
      |> add_if(year != "all", "Year: #{year}")

    case parts do
      [] -> "All departments · All specializations · All years"
      list -> Enum.join(list, " · ")
    end
  end

  defp add_if(list, true, value), do: list ++ [value]
  defp add_if(list, false, _), do: list

  # ============================================================================
  # SHARED
  # ============================================================================

  defp base_context(student, extra) do
    Map.merge(
      %{
        student: student,
        generated_at: format_generated_at(DateTime.utc_now())
      },
      extra
    )
  end

  defp format_generated_at(%DateTime{} = dt) do
    {:ok, ist} = DateTime.shift_zone(dt, "Asia/Kolkata")
    Calendar.strftime(ist, "%B %-d, %Y %-I:%M:%S %p IST")
  end

  defp student_slug(%{first_name: f, last_name: l}) do
    [f, l]
    |> Enum.reject(&(is_nil(&1) or String.trim(to_string(&1)) == ""))
    |> Enum.join("-")
    |> case do
      "" -> "Profile"
      name -> name
    end
  end

  defp student_slug(_), do: "Profile"

  defp build_filename(kind, label) do
    slug =
      label
      |> to_string()
      |> String.replace(~r/[^\w\-]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "Report"
        s -> s
      end

    "Vyaasa-#{kind}-#{slug}-#{Date.utc_today()}.pdf"
  end

  defp safe_decimal_to_float(nil), do: 0.0
  defp safe_decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp safe_decimal_to_float(val) when is_float(val), do: val
  defp safe_decimal_to_float(val) when is_integer(val), do: val / 1
  defp safe_decimal_to_float(_), do: 0.0

  defp safe_to_float(nil), do: 0.0
  defp safe_to_float(val) when is_float(val), do: val
  defp safe_to_float(val) when is_integer(val), do: val / 1

  defp safe_to_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp safe_to_float(_), do: 0.0

  defp performance_label(p) when is_number(p) and p >= 90, do: "Outstanding"
  defp performance_label(p) when is_number(p) and p >= 75, do: "Excellent"
  defp performance_label(p) when is_number(p) and p >= 60, do: "Good"
  defp performance_label(p) when is_number(p) and p >= 40, do: "Needs Improvement"
  defp performance_label(_), do: "Keep Trying"

  defp performance_color(p) when is_number(p) and p >= 75, do: :green
  defp performance_color(p) when is_number(p) and p >= 60, do: :amber
  defp performance_color(p) when is_number(p) and p >= 40, do: :orange
  defp performance_color(_), do: :red
end
