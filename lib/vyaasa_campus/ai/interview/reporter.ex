defmodule VyaasaCampus.AI.Interview.Reporter do
  @moduledoc """
  Generates the final hiring assessment report from a completed interview
  session. Port of the dev "AI Interviewer V1" reporter agent.

  Unlike the reference (which computes scores deterministically from
  `InterviewState`), this port expects the CALLER to compute all scores and
  pass them in. This module only builds the prompt, calls the LLM, and returns
  the six narrative report fields. On failure it returns a deterministic
  fallback built from the supplied topics/consistency data.
  """

  require Logger

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.Interview.{Profile, Sanitize}

  @model "openai/gpt-oss-120b"

  @system_prompt """
  You are a senior hiring manager writing a final assessment report.

  Your report must be:
  - Evidence-based: every claim backed by interview data
  - Fair: do not penalise communication style or imperfect English
  - Precise: specific strengths and gaps, not generic statements
  - Actionable: useful for a recruiter making a real hiring decision

  Respond with valid JSON only. No markdown, no explanation.
  """

  @doc """
  Generate the final report. `args` is a map (see module-level contract):

    %{profile: %Profile{}, target_role: String.t(), comp: map(), scores: [map()],
      qa: [map()], consistency: map() | nil, strong_topics: [String.t()],
      weak_topics: [String.t()]}

  Returns a map with the six narrative fields:
    %{technical_strengths, technical_gaps, verified_skills, suspicious_claims,
      communication_assessment, overall_summary}
  """
  def generate(args) when is_map(args) do
    prompt = build_prompt(args)
    system = String.trim(@system_prompt) <> "\n\n" <> Sanitize.injection_defense()

    with {:ok, %{"content" => raw}} <-
           GroqClient.chat(
             [%{role: "system", content: system}, %{role: "user", content: prompt}],
             model: @model,
             temperature: 0.3,
             max_tokens: 2500,
             timeout: 180_000,
             response_format: %{"type" => "json_object"},
             reasoning_effort: "low"
           ),
         {:ok, data} <- raw |> GroqClient.strip_reasoning() |> GroqClient.extract_json() do
      %{
        technical_strengths: string_list(Map.get(data, "technical_strengths", [])),
        technical_gaps: string_list(Map.get(data, "technical_gaps", [])),
        verified_skills: string_list(Map.get(data, "verified_skills", [])),
        suspicious_claims: string_list(Map.get(data, "suspicious_claims", [])),
        communication_assessment: to_string(Map.get(data, "communication_assessment", "")),
        overall_summary: to_string(Map.get(data, "overall_summary", ""))
      }
    else
      error ->
        Logger.warning("[Reporter] report generation failed: #{inspect(error)}")
        fallback(args)
    end
  end

  # ── prompt ───────────────────────────────────────────────────────────────────
  defp build_prompt(args) do
    %Profile{} = profile = args.profile
    comp = args.comp
    scores = args.scores || []
    qa = args.qa || []
    consistency = args.consistency
    strong_topics = args.strong_topics || []
    weak_topics = args.weak_topics || []

    score_lines = scores |> Enum.map(&score_line/1) |> Enum.join("\n")

    score_by_qid = Map.new(scores, fn s -> {s.question_id, s} end)

    qa_summary =
      qa
      |> Enum.map(fn q -> {q, Map.get(score_by_qid, q.question_id)} end)
      |> Enum.reject(fn {_q, s} -> is_nil(s) end)
      |> Enum.map(fn {q, s} -> qa_block(q, s) end)
      |> Enum.join("\n")

    consistency_text = consistency_text(consistency)

    work_exp_line =
      case profile.work_history do
        [] ->
          "None"

        history ->
          history
          |> Enum.map(fn w -> "#{w.role} at #{w.company}" end)
          |> Enum.join(", ")
      end

    primary_skills = profile.primary_skills |> Enum.take(10) |> Enum.join(", ")
    project_names = profile.projects |> Enum.map(& &1.name) |> Enum.join(", ")

    """
    Generate a final hiring assessment report for this candidate.

    --- CANDIDATE ---
    Name           : #{profile.name || "Unknown"}
    Email          : #{profile.email || "Not provided"}
    Target Role    : #{blank_to(args.target_role, "Unknown")}
    Domain         : #{profile.domain}
    Experience     : #{profile.experience_years} years (#{profile.experience_level})
    Primary Skills : #{primary_skills}
    Projects       : #{blank_to(project_names, "None")}
    Work Experience: #{work_exp_line}

    --- COMPETENCY SCORES (out of 100) ---
    Technical (50%)          : #{comp["technical"]}
    Communication (30%)      : #{comp["communication"]}
    Leadership (10%)         : #{comp["leadership"]}
    Cultural Fit (10%)       : #{comp["cultural_fit"]}
    Overall weighted score   : #{comp["overall"]}

    --- PER-QUESTION BREAKDOWN ---
    #{score_lines}

    --- CONSISTENCY ANALYSIS ---
    #{consistency_text}

    --- INTERVIEW Q&A SUMMARY ---
    #{qa_summary}

    --- STRONG TOPICS ---
    #{blank_to(Enum.join(strong_topics, ", "), "None identified")}

    --- WEAK TOPICS ---
    #{blank_to(Enum.join(weak_topics, ", "), "None identified")}

    Return ONLY this JSON:
    {
      "technical_strengths": ["specific verified technical strengths from the interview"],
      "technical_gaps": ["specific gaps relevant to the role"],
      "verified_skills": ["skills confirmed during the interview"],
      "suspicious_claims": ["claims that were not substantiated"],
      "communication_assessment": "2-3 sentences on communication clarity and structure",
      "overall_summary": "3-4 sentence narrative summary of this candidate",
    }
    """
    |> String.trim()
  end

  defp score_line(%{is_cultural_fit: true} = s) do
    "  Q#{s.question_id} [#{s.topic}] cultural_fit=#{round_int(s.cultural_fit)}"
  end

  defp score_line(s) do
    "  Q#{s.question_id} [#{s.topic}] " <>
      "tech=#{round_int(s.technical)}  comm=#{round_int(s.communication)}  lead=#{round_int(s.leadership)}"
  end

  defp qa_block(q, s) do
    "  [#{q.section}] #{String.slice(to_string(q.text), 0, 100)}\n" <>
      "  → Feedback: #{s.feedback}\n" <>
      "  → Strengths: #{join_first(s.strengths, 2)}\n" <>
      "  → Improvements: #{join_first(s.improvements, 2)}"
  end

  defp consistency_text(nil), do: "Not analyzed."

  defp consistency_text(consistency) do
    contradictions = consistency.contradictions || []
    verified = (consistency.verified_skills || []) |> Enum.take(8) |> Enum.join(", ")
    suspicious = (consistency.suspicious_claims || []) |> Enum.take(4) |> Enum.join(", ")

    "Overall consistency: #{consistency.overall_consistency} | " <>
      "Contradictions: #{length(contradictions)} | " <>
      "Verified skills: #{blank_to(verified, "None")} | " <>
      "Suspicious: #{blank_to(suspicious, "None")}"
  end

  # ── fallback ─────────────────────────────────────────────────────────────────
  defp fallback(args) do
    consistency = args.consistency

    %{
      technical_strengths: args.strong_topics || [],
      technical_gaps: args.weak_topics || [],
      verified_skills: (consistency && consistency.verified_skills) || [],
      suspicious_claims: (consistency && consistency.suspicious_claims) || [],
      communication_assessment: "Automated assessment unavailable — see scores above.",
      overall_summary: "Report generation failed. Overall score: #{args.comp["overall"]}/100. Manual review required."
    }
  end

  # ── helpers ──────────────────────────────────────────────────────────────────
  defp round_int(n) when is_number(n), do: round(n)
  defp round_int(_), do: 0

  defp join_first(list, n) when is_list(list), do: list |> Enum.take(n) |> Enum.join("; ")
  defp join_first(_, _), do: ""

  defp blank_to(value, default) do
    str = to_string(value || "")
    if String.trim(str) == "", do: default, else: str
  end

  defp string_list(l) when is_list(l), do: Enum.map(l, &to_string/1)
  defp string_list(_), do: []
end
