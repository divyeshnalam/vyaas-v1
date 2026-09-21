defmodule VyaasaCampus.AI.Interview.Consistency do
  @moduledoc """
  Analyzes the full interview session for consistency and authenticity:
  contradictions across answers, unsubstantiated claims, skills claimed but
  never demonstrated, and skills genuinely verified through concrete answers.

  Port of the dev "AI Interviewer V1" consistency agent. Unlike the reference,
  this only RETURNS the report map — the caller is responsible for updating any
  session state.
  """

  require Logger

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.Interview.{Profile, Sanitize}

  @model "openai/gpt-oss-120b"
  @max_answer_chars 400
  @fallback_consistency_score 0.5

  @system_prompt """
  You are an expert interview analyst specializing in detecting
  inconsistencies, contradictions, and authenticity signals
  across a full interview session.

  Your job is to analyze the complete Q&A history and identify:
  - Contradictions between answers
  - Claims that were never substantiated
  - Skills claimed on resume but not demonstrated in answers
  - Suspiciously polished answers with no personal experience
  - Consistent patterns that verify genuine ownership

  Be precise and evidence-based. Every finding must cite
  specific questions and answers.

  Respond with valid JSON only. No markdown, no explanation.
  """

  @doc """
  Analyze the interview Q&A for consistency.

  `qa` is a list (in ask order) of maps with keys:
    `:id`, `:section`, `:topic`, `:difficulty`, `:question`, `:answer`,
    `:overall`, `:needs_followup`.

  Returns:
    %{contradictions: [%{question_id_a, question_id_b, description, severity}],
      suspicious_claims: [String.t()], verified_skills: [String.t()],
      overall_consistency: float}
  """
  def analyze(%Profile{} = profile, qa) when is_list(qa) do
    if length(qa) < 2 do
      %{overall_consistency: 1.0, contradictions: [], suspicious_claims: [], verified_skills: []}
    else
      do_analyze(profile, qa)
    end
  end

  defp do_analyze(profile, qa) do
    prompt = build_prompt(profile, qa)
    system = String.trim(@system_prompt) <> "\n\n" <> Sanitize.injection_defense()

    with {:ok, %{"content" => raw}} <-
           GroqClient.chat(
             [%{role: "system", content: system}, %{role: "user", content: prompt}],
             model: @model,
             temperature: 0.1,
             max_tokens: 2500,
             timeout: 180_000,
             response_format: %{"type" => "json_object"}
           ),
         {:ok, data} <- GroqClient.extract_json(raw) do
      parse(data)
    else
      error ->
        Logger.warning("[Consistency] analysis failed: #{inspect(error)}")
        fallback()
    end
  end

  # ── prompt ───────────────────────────────────────────────────────────────────
  defp build_prompt(profile, qa) do
    transcript_text = qa |> Enum.map(&transcript_block/1) |> Enum.join("\n\n")
    skills = profile.claimed_skills |> Enum.take(15) |> Enum.join(", ")
    projects = profile.projects |> Enum.map(& &1.name) |> Enum.join(", ")

    """
    Analyze this complete interview session for consistency and authenticity.

    --- CANDIDATE ---
    Name            : #{profile.name || "Candidate"}
    Domain          : #{profile.domain}
    Experience      : #{profile.experience_years} years (#{profile.experience_level})
    Claimed skills  : #{skills}
    Projects        : #{projects}

    --- FULL INTERVIEW TRANSCRIPT ---
    #{Sanitize.wrap_untrusted(transcript_text, "interview transcript")}

    --- ANALYSIS TASKS ---

    1. CONTRADICTIONS: Find answers that contradict each other.
       Example: Claims "I built the entire system" in Q1 but says
       "I only worked on the frontend" in Q4.

    2. SUSPICIOUS CLAIMS: Skills or projects claimed but never
       substantiated with real implementation details.
       Look for: generic answers, doc-recitation, no failures mentioned,
       no personal pronouns, no debugging stories.

    3. VERIFIED SKILLS: Skills that were confirmed through specific,
       concrete, implementation-level answers. Only include if the
       candidate gave evidence they actually used the skill.

    4. OVERALL CONSISTENCY: How consistent is the candidate's
       knowledge across the entire interview?
       1.0 = perfectly consistent, no red flags
       0.5 = some inconsistencies or unverified claims
       0.0 = major contradictions or clear fabrication

    Return ONLY this JSON:
    {
      "contradictions": [
        {
          "question_id_a": 1,
          "question_id_b": 3,
          "description": "what contradicts what — be specific",
          "severity": "minor | major"
        }
      ],
      "suspicious_claims": [
        "specific claim that was never substantiated with evidence"
      ],
      "verified_skills": [
        "skill confirmed through concrete implementation-level answers"
      ],
      "overall_consistency": 0.0
    }
    """
    |> String.trim()
  end

  defp transcript_block(q) do
    answer = to_string(q.answer || "")

    answer_text =
      if String.length(answer) > @max_answer_chars do
        String.slice(answer, 0, @max_answer_chars) <> "... [truncated]"
      else
        answer
      end

    followup = if q.needs_followup, do: " | NEEDS FOLLOWUP", else: ""

    "Q#{q.id} [#{q.section} | #{q.topic} | difficulty #{q.difficulty}]:\n" <>
      "  Question  : #{q.question}\n" <>
      "  Answer    : #{answer_text}\n" <>
      "  Score     : #{q.overall}/100#{followup}"
  end

  # ── parse ────────────────────────────────────────────────────────────────────
  defp parse(data) do
    contradictions =
      data
      |> Map.get("contradictions", [])
      |> List.wrap()
      |> Enum.map(fn c ->
        %{
          question_id_a: to_int(Map.get(c, "question_id_a", 0)),
          question_id_b: to_int(Map.get(c, "question_id_b", 0)),
          description: to_string(Map.get(c, "description", "")),
          severity: to_string(Map.get(c, "severity", "minor"))
        }
      end)

    %{
      contradictions: contradictions,
      suspicious_claims: string_list(Map.get(data, "suspicious_claims", [])),
      verified_skills: string_list(Map.get(data, "verified_skills", [])),
      overall_consistency: to_float(Map.get(data, "overall_consistency", 0.7))
    }
  end

  defp fallback do
    %{
      overall_consistency: @fallback_consistency_score,
      contradictions: [],
      suspicious_claims: [],
      verified_skills: []
    }
  end

  # ── helpers ──────────────────────────────────────────────────────────────────
  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_float(v), do: round(v)

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> 0
    end
  end

  defp to_int(_), do: 0

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v / 1

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {n, _} -> n
      _ -> 0.7
    end
  end

  defp to_float(_), do: 0.7

  defp string_list(l) when is_list(l), do: Enum.map(l, &to_string/1)
  defp string_list(_), do: []
end
