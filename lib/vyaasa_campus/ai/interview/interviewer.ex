defmodule VyaasaCampus.AI.Interview.Interviewer do
  @moduledoc """
  Generates the next interview question — project/experience-anchored, adaptive
  difficulty, one controlled follow-up when an answer is shallow, cultural-fit
  always last. Stateless: the engine passes the profile, plan, and the questions
  asked so far (+ the last answer's score) and gets the next question back.

  Port of the dev "AI Interviewer V1" interviewer agent.
  """

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.Interview.Profile
  alias VyaasaCampus.AI.Interview.Specializations

  @model "openai/gpt-oss-120b"

  # One angle per session (stable for a candidate, varies across candidates) —
  # port of the reference _QUESTION_ANGLES.
  @question_angles [
    "Focus on challenges — ask what was hard, what broke, and how they solved it.",
    "Focus on decisions — ask why they chose this approach over alternatives.",
    "Focus on ownership — ask what they personally built versus what already existed.",
    "Focus on learnings — ask what they learned and what they would do differently now.",
    "Focus on specifics — ask for exact implementation details, not high-level overviews."
  ]

  @system """
          You are an expert interviewer conducting a real job interview.
          Your goal is to accurately assess the candidate's true ability —
          not to trick them, but to understand their genuine depth.

          Rules:
          - Ask ONE question at a time
          - Never repeat a topic already covered
          - If an answer is shallow, probe deeper with a follow-up
          - If an answer mentions something interesting, explore it
          - Adapt difficulty based on how the candidate performs
          - For project questions, always ask about specifics — not generic concepts
          - Be direct and professional — no filler phrases

          Respond with valid JSON only. No markdown, no explanation.
          Output JSON shape: {"question": "...", "expected_signals": ["..."]}
          """ <>
            "\n\n" <> VyaasaCampus.AI.Interview.Sanitize.injection_defense()

  @doc """
  Returns `{:ok, question_map}` where question_map has:
  `text, type, section, topic, project_name, experience_name, github_url,
   difficulty, follow_up_of, expected_signals`.

  `asked` is the list of previously-asked question maps; `last_score` is the
  score map of the most recent answer (or nil).
  """
  def next_question(%Profile{} = profile, plan, asked, last_score \\ nil) do
    asked_count = length(asked)
    total_q = plan.total_questions

    result =
      cond do
        # Cultural fit is always the final question.
        asked_count >= total_q - 1 ->
          cultural_fit_question(profile)

        # One controlled follow-up when the last answer was shallow.
        followup?(last_score) and followup_budget?(asked) ->
          followup_question(profile, List.last(asked))

        true ->
          section_question(profile, plan, asked)
      end

    # Never serve a question already asked. When the Groq call fails or returns
    # unparseable JSON, `generate` falls back to a deterministic constant — with
    # no dedup that produced the "same question 3 times" repeat. Substitute a
    # distinct question when the generator (or its fallback) repeats.
    case result do
      {:ok, q} -> {:ok, ensure_unique(q, asked)}
      other -> other
    end
  end

  @fallback_pool [
    "Tell me about a recent project or task you worked on and what your specific role was.",
    "What technical decision are you most proud of, and what made it the right call?",
    "Describe a bug or blocker that took you a while to crack — how did you approach it?",
    "If you could rebuild one part of your project, what would you change and why?",
    "Walk me through how you tested or validated your work.",
    "What trade-off did you have to make, and how did you decide?"
  ]

  defp ensure_unique(%{text: text} = q, asked) do
    asked_norm = asked |> Enum.map(&norm(&1[:text])) |> Enum.reject(&(&1 == ""))

    if norm(text) in asked_norm do
      replacement = Enum.find(@fallback_pool, &(norm(&1) not in asked_norm))
      Map.put(q, :text, replacement || text)
    else
      q
    end
  end

  defp norm(nil), do: ""
  defp norm(s), do: s |> to_string() |> String.downcase() |> String.trim()

  # ── Section (project/experience/skill) question ─────────────────────────────
  defp section_question(profile, plan, asked) do
    section = current_section(plan, asked)
    difficulty = difficulty_for(length(asked), plan.total_questions)

    # Rotate across the section's topics (projects/roles), least-covered first.
    rotated = pick_topic(section, asked)
    {project, experience} = anchor_for(profile, section, rotated)
    topic = rotated || project_or_role(project, experience) || "their background"

    prompt = """
    CANDIDATE: #{profile.name || "the candidate"} — target role: #{profile.target_role} (#{profile.domain}).
    SECTION: #{section.name} — #{section.purpose}
    TOPIC TO PROBE: #{topic}
    #{anchor_block(project, experience)}
    #{jd_context(profile, plan, section, asked)}#{domain_hints(profile.domain)}ANGLE: #{session_angle(profile)}
    DIFFICULTY: #{difficulty}/3 (1=easy/tools, 2=design/why, 3=trade-offs/edge cases).

    Already asked (avoid repeating):
    #{recent_asked(asked)}

    Generate ONE #{difficulty_word(difficulty)} question for this topic.
    """

    generate(prompt, %{
      type: List.first(section.question_types) || "technical",
      section: section.name,
      topic: topic,
      project_name: project && project.name,
      experience_name: experience && experience_label(experience),
      github_url: project && project.github_url,
      difficulty: difficulty,
      follow_up_of: nil
    })
  end

  # ── Follow-up on the previous answer ────────────────────────────────────────
  defp followup_question(profile, last_q) do
    prompt = """
    CANDIDATE: #{profile.name || "the candidate"}.
    The previous question was: "#{last_q.text}"
    Their answer was shallow or missing specifics. Ask ONE short, warm follow-up
    that digs into the concrete details (what THEY did, decisions, outcome).
    """

    generate(prompt, %{
      type: "followup",
      section: last_q.section,
      topic: last_q.topic,
      project_name: last_q[:project_name],
      experience_name: last_q[:experience_name],
      github_url: nil,
      difficulty: last_q[:difficulty] || 2,
      follow_up_of: last_q[:id]
    })
  end

  # ── Cultural fit (final) ────────────────────────────────────────────────────
  defp cultural_fit_question(profile) do
    prompt = """
    CANDIDATE: #{profile.name || "the candidate"}, target role #{profile.target_role}.
    Ask ONE cultural-fit question about their work values, how they handle
    disagreement, or what kind of team they thrive in. Warm and open-ended.
    """

    generate(prompt, %{
      type: "cultural_fit",
      section: "cultural_fit",
      topic: "work values",
      project_name: nil,
      experience_name: nil,
      github_url: nil,
      difficulty: 1,
      follow_up_of: nil
    })
  end

  # ── LLM call + parse ────────────────────────────────────────────────────────
  defp generate(prompt, meta) do
    # gpt-oss reasons by default — /no_think keeps output clean, and we strip
    # any residual <think> block before parsing.
    case GroqClient.chat([%{role: "system", content: @system}, %{role: "user", content: prompt <> "\n/no_think"}],
           model: @model,
           temperature: 0.5,
           max_tokens: 1000,
           timeout: 60_000
         ) do
      {:ok, %{"content" => raw}} ->
        case GroqClient.extract_json(GroqClient.strip_reasoning(raw)) do
          {:ok, %{"question" => q} = data} when is_binary(q) and q != "" ->
            {:ok, Map.merge(meta, %{text: String.trim(q), expected_signals: data["expected_signals"] || []})}

          _ ->
            {:ok, Map.merge(meta, %{text: fallback_text(meta), expected_signals: []})}
        end

      _ ->
        {:ok, Map.merge(meta, %{text: fallback_text(meta), expected_signals: []})}
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────
  # First plan section (excluding cultural_fit) whose questions aren't yet filled.
  @doc false
  def current_section(plan, asked) do
    plan.sections
    |> Enum.reject(&(&1.name == "cultural_fit"))
    |> Enum.find(fn s ->
      asked_in_section = Enum.count(asked, &(&1[:section] == s.name and &1[:type] != "followup"))
      asked_in_section < s.question_count
    end)
    |> case do
      nil ->
        List.first(plan.sections) ||
          %{name: "core_concepts", purpose: "", topics: [], question_count: 1, question_types: ["technical"]}

      s ->
        s
    end
  end

  # Pick the least-covered topic in this section (rotation across projects/roles).
  defp pick_topic(%{topics: []}, _asked), do: nil

  defp pick_topic(%{topics: topics, name: name}, asked) do
    Enum.min_by(topics, fn t -> Enum.count(asked, &(&1[:section] == name and &1[:topic] == t)) end)
  end

  # Resolve the concrete project/experience the rotated topic refers to.
  defp anchor_for(profile, %{name: section}, topic)
       when section in ["project_deep_dive", "portfolio_deep_dive"] and is_binary(topic) do
    {Enum.find(profile.projects, &(&1.name == topic)), nil}
  end

  defp anchor_for(profile, %{name: "experience_deep_dive"}, topic) when is_binary(topic) do
    {nil, Enum.find(profile.work_history, &(experience_label(&1) == topic))}
  end

  defp anchor_for(_profile, _section, _topic), do: {nil, nil}

  defp anchor_block(nil, nil), do: ""

  defp anchor_block(%{} = p, nil),
    do: "PROJECT (anchor strictly to this): #{p.name} — tech: #{Enum.join(p.technologies, ", ")}. #{p.description}"

  defp anchor_block(nil, %{} = e),
    do: "EXPERIENCE (anchor to this role): #{experience_label(e)} — #{Enum.join(e.responsibilities, "; ")}"

  defp anchor_block(_, _), do: ""

  defp project_or_role(%{name: n}, _), do: n
  defp project_or_role(_, %{} = e), do: experience_label(e)
  defp project_or_role(_, _), do: nil

  defp experience_label(%{role: r, company: c}), do: String.trim("#{r} #{c}")
  defp experience_label(_), do: ""

  defp recent_asked([]), do: "  None yet"
  defp recent_asked(asked), do: asked |> Enum.take(-6) |> Enum.map_join("\n", &"  - #{&1.text}")

  # Stable per-candidate angle (no Math.random — deterministic from the profile).
  defp session_angle(profile) do
    seed = :erlang.phash2({profile.name, profile.target_role, profile.domain})
    Enum.at(@question_angles, rem(seed, length(@question_angles)))
  end

  # Role/JD context from the super-admin's job role: a short role-requirements
  # line for every section, plus (for skill-focused sections) the role-required
  # skills the candidate claims but hasn't been asked about yet.
  defp jd_context(profile, plan, section, asked) do
    role_line =
      case String.trim(profile.jd_text || "") do
        "" -> ""
        text -> "ROLE REQUIREMENTS (target job): #{String.slice(text, 0, 600)}\n"
      end

    skills_line =
      if section.name in ["core_concepts", "experience_deep_dive"] do
        case uncovered_jd_skills(plan, asked) do
          [] -> ""
          skills -> "ROLE-REQUIRED SKILLS STILL TO VERIFY (favour these): #{Enum.join(skills, ", ")}\n"
        end
      else
        ""
      end

    role_line <> skills_line
  end

  # Domain specialization hints — red flags to watch for + topics that warrant
  # deeper probing (from the reference specializations config).
  defp domain_hints(domain) do
    triggers = Specializations.depth_triggers(domain) |> Enum.take(6)
    flags = Specializations.red_flags(domain) |> Enum.take(4)

    trigger_line =
      if triggers == [], do: "", else: "DEEPEN IF THEY MENTION: #{Enum.join(triggers, ", ")}\n"

    flag_line =
      if flags == [], do: "", else: "RED FLAGS TO PROBE FOR (don't name them): #{Enum.join(flags, "; ")}\n"

    trigger_line <> flag_line
  end

  defp uncovered_jd_skills(plan, asked) do
    asked_blob = asked |> Enum.map_join(" ", & &1.text) |> String.downcase()

    (plan[:jd_matched_skills] || [])
    |> Enum.reject(&String.contains?(asked_blob, String.downcase(&1)))
    |> Enum.take(6)
  end

  defp difficulty_for(q_count, total) do
    cond do
      q_count < div(total, 3) -> 1
      q_count < div(2 * total, 3) -> 2
      true -> 3
    end
  end

  defp difficulty_word(1), do: "easy, warm-up"
  defp difficulty_word(2), do: "moderate, design/reasoning"
  defp difficulty_word(_), do: "challenging, trade-off / edge-case"

  defp followup?(%{needs_followup: true}), do: true
  defp followup?(_), do: false

  # Don't follow up if the last question was itself a follow-up (cap consecutive).
  defp followup_budget?(asked) do
    case List.last(asked) do
      %{type: "followup"} -> false
      _ -> true
    end
  end

  defp fallback_text(%{project_name: name}) when is_binary(name),
    do: "Walk me through the #{name} project — what part did you build yourself, and what was the hardest decision?"

  defp fallback_text(%{section: "cultural_fit"}),
    do: "Tell me about a time you disagreed with a teammate — how did you handle it?"

  defp fallback_text(_),
    do: "Tell me about a recent project or task you worked on and what your specific role was."
end
