defmodule VyaasaCampus.AI.Interview.Evaluator do
  @moduledoc """
  Scores a single interview answer (port of the reference `agents/evaluator.py`).

  Q1–9 (technical/project/behavioural) → technical, communication, leadership
  (0–100 each) + whether a follow-up is needed. The cultural-fit question →
  cultural_fit (0–100). Scoring is silent — it drives adaptive difficulty,
  bounded follow-ups, and the final report.

  Follow-ups fire only in the mid-range (40–60): below that they don't know it,
  above it they answered well enough to move on. A parse/LLM failure scores 0 and
  flags for manual review — a failure must never hand out a passing score.
  """

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.Interview.{Profile, Sanitize, Specializations}

  @model "openai/gpt-oss-120b"
  @followup_min 40
  @followup_max 60

  @system """
  You are an expert interviewer evaluating a candidate's response.

  Score each dimension independently and precisely on a 0–100 scale.
  Base every score strictly on evidence from the answer — not on assumptions.

  Scoring guide — calibrate generously to a FRESHER bar; a solid, correct answer
  SHOULD land in 80–89. Do not under-score genuine competence:
    95–100: Excellent. Expert-level detail or insight only a genuine practitioner gives.
    80–94 : Good. Clear, accurate, specific, real ownership shown. TARGET for a solid answer.
    65–79 : Average. Correct but generic or somewhat shallow.
    45–64 : Below average. Partial understanding, notable gaps.
    25–44 : Weak. Mostly incorrect or very thin.
    0–24  : Poor. Wrong, off-topic, or no real answer.

  RANDOM / NON-ANSWER RULE (apply FIRST): if the answer is empty, gibberish,
  a single word/letter, random or filler text, UUIDs / hashes / IDs / numbers,
  or does not actually address the question, score EVERY dimension 0 (at most 5)
  regardless of length. Do not award marks for words that don't answer the question.

  Never penalise for nervousness, accent, or imperfect English grammar.
  Never reward buzzwords without substance.

  Respond with valid JSON only. No markdown, no explanation.
  """

  @doc """
  Returns a score map:
    %{is_cultural_fit: false, technical, communication, leadership, needs_followup,
      followup_reason, strengths, improvements, feedback, flagged_for_review}
    %{is_cultural_fit: true, cultural_fit, strengths, improvements, feedback}

  `prior_qa` is a plaintext rendering of the last few Q&A pairs (for a
  consistency check); pass "None — this is the first answer." when unavailable.
  """
  def evaluate(question, answer, profile, prior_qa \\ "None — this is the first answer.")

  def evaluate(question, answer, %Profile{} = profile, prior_qa) do
    cf? = Map.get(question, :section) == "cultural_fit"
    system = @system <> "\n\n" <> Sanitize.injection_defense()

    prompt =
      if cf?,
        do: cf_prompt(question, answer, profile),
        else: eval_prompt(question, answer, profile, prior_qa)

    case GroqClient.chat([%{role: "system", content: system}, %{role: "user", content: prompt}],
           model: @model,
           temperature: 0.1,
           max_tokens: 1500,
           response_format: %{"type" => "json_object"},
           timeout: 60_000
         ) do
      {:ok, %{"content" => raw}} ->
        case GroqClient.extract_json(raw) do
          {:ok, data} -> parse(data, cf?)
          _ -> fallback(cf?)
        end

      _ ->
        fallback(cf?)
    end
  end

  # ── prompts ─────────────────────────────────────────────────────────────────
  defp eval_prompt(question, answer, profile, prior_qa) do
    technical_desc =
      if Specializations.it_domain?(profile.domain) do
        """
        Does the answer show correct technical understanding?
           Does it go beyond surface definitions into how/why?
           Does it reflect real hands-on experience with the topic?\
        """
      else
        """
        Does the answer show correct domain/professional knowledge?
           Does it demonstrate understanding of relevant processes, best practices, or concepts?
           Does it reflect real-world judgment and experience relevant to this role?\
        """
      end

    """
    Evaluate this interview answer across three competency dimensions.

    --- CANDIDATE ---
    Name   : #{profile.name || "Candidate"}
    Domain : #{profile.domain}
    Level  : #{profile.experience_level}
    Skills : #{Enum.join(Enum.take(profile.primary_skills, 6), ", ")}

    --- QUESTION ---
    Question  : #{question.text}
    Section   : #{question[:section]}
    Topic     : #{question[:topic]}
    Expected  : #{Enum.join(Enum.take(question[:expected_signals] || [], 4), ", ") |> blank_to("N/A")}

    --- CANDIDATE'S ANSWER ---
    #{Sanitize.wrap_untrusted(answer, "candidate answer")}

    --- PRIOR CONVERSATION (for consistency check) ---
    #{Sanitize.wrap_untrusted(prior_qa, "prior conversation")}

    --- WHAT TO SCORE ---

    1. TECHNICAL (0–100) — Domain knowledge & professional skills
       #{technical_desc}

    2. COMMUNICATION (0–100) — Communication & interpersonal skills
       Was the answer clear, structured, and easy to follow?
       Did the candidate explain ideas logically and concisely?
       Could a non-expert follow their explanation?

    3. LEADERSHIP (0–100) — Initiative & leadership
       Did the candidate show initiative, ownership, or proactive thinking?
       Did they describe decisions THEY made, problems THEY solved?
       Did they show drive, accountability, or a problem-solving mindset?

    --- FOLLOW-UP NEEDED ---
    Set needs_followup=true ONLY if technical is between #{@followup_min} and #{@followup_max} (mid-range):
      - candidate showed partial understanding but left clear gaps
      - answer was on the right track but missed key signals
      - a targeted follow-up could surface what they actually know

    Do NOT set needs_followup=true if:
      - technical < #{@followup_min} (they clearly don't know — follow-up won't help)
      - technical > #{@followup_max} (they answered well — move on)
      - answer contradicts a prior answer (flag in improvements instead)

    followup_reason must name the SPECIFIC GAP to probe — not a repeat of the same question.

    Return ONLY this JSON:
    {
      "technical":       0,
      "communication":   0,
      "leadership":      0,
      "strengths":       ["specific strength from this answer"],
      "improvements":    ["specific gap or weakness in this answer"],
      "feedback":        "one sentence summary of this answer's quality",
      "needs_followup":  false,
      "followup_reason": "what gap a follow-up should address, or empty string"
    }
    """
  end

  defp cf_prompt(question, answer, profile) do
    """
    Evaluate this cultural fit and emotional intelligence answer.

    --- CANDIDATE ---
    Name   : #{profile.name || "Candidate"}
    Domain : #{profile.domain}
    Level  : #{profile.experience_level}

    --- QUESTION ---
    #{question.text}

    --- CANDIDATE'S ANSWER ---
    #{Sanitize.wrap_untrusted(answer, "candidate answer")}

    --- WHAT TO SCORE ---

    CULTURAL FIT (0–100) — Cultural fit & emotional intelligence
      Does the answer show genuine self-awareness?
      Does it reveal values, work ethic, and collaboration style authentically?
      Does it show emotional maturity — handling setbacks, conflict, or feedback?
      Does it feel honest and personal, not rehearsed or generic?

    Return ONLY this JSON:
    {
      "cultural_fit":  0,
      "strengths":     ["specific strength from this answer"],
      "improvements":  ["specific gap or weakness in this answer"],
      "feedback":      "one sentence summary of this answer's quality"
    }
    """
  end

  # ── parse ─────────────────────────────────────────────────────────────────
  defp parse(data, true) do
    %{
      is_cultural_fit: true,
      cultural_fit: clamp(data["cultural_fit"]),
      needs_followup: false,
      strengths: list(data["strengths"]),
      improvements: list(data["improvements"]),
      feedback: to_string(data["feedback"] || ""),
      flagged_for_review: false
    }
  end

  defp parse(data, false) do
    technical = clamp(data["technical"])
    needs_fu = data["needs_followup"] == true
    # Hard override: follow up only in the mid-range.
    in_range? = technical >= @followup_min and technical <= @followup_max

    %{
      is_cultural_fit: false,
      technical: technical,
      communication: clamp(data["communication"]),
      leadership: clamp(data["leadership"]),
      needs_followup: needs_fu and in_range?,
      followup_reason: if(needs_fu and in_range?, do: to_string(data["followup_reason"] || ""), else: ""),
      strengths: list(data["strengths"]),
      improvements: list(data["improvements"]),
      feedback: to_string(data["feedback"] || ""),
      flagged_for_review: false
    }
  end

  # Evaluation failed even after retries — score 0 and flag for manual review so a
  # parse failure can never hand out a passing score.
  defp fallback(true),
    do: %{
      is_cultural_fit: true,
      cultural_fit: 0,
      needs_followup: false,
      strengths: [],
      improvements: ["Automated evaluation failed — this answer needs manual review."],
      feedback: "Evaluation failed — flagged for manual review (not auto-scored).",
      flagged_for_review: true
    }

  defp fallback(false),
    do: %{
      is_cultural_fit: false,
      technical: 0,
      communication: 0,
      leadership: 0,
      needs_followup: false,
      followup_reason: "",
      strengths: [],
      improvements: ["Automated evaluation failed — this answer needs manual review."],
      feedback: "Evaluation failed — flagged for manual review (not auto-scored).",
      flagged_for_review: true
    }

  defp clamp(v) when is_number(v), do: v |> round() |> max(0) |> min(100)

  defp clamp(v) when is_binary(v),
    do:
      (case Integer.parse(v) do
         {n, _} -> clamp(n)
         _ -> 50
       end)

  defp clamp(_), do: 50

  defp list(l) when is_list(l), do: Enum.map(l, &to_string/1)
  defp list(_), do: []

  defp blank_to("", default), do: default
  defp blank_to(s, _default), do: s
end
