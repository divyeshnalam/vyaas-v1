defmodule VyaasaCampus.AI.PsychometricEngine do
  @moduledoc """
  Adaptive Big Five (OCEAN) psychometric assessment engine.

  Native Elixir port of the reference `psychometric.py` adaptive flow:

  - Base questions are served from `QuestionBank` using a deterministic,
    theme-aware selector. No LLM call for base questions.
  - Follow-ups on ambiguous answers (keyed score 2 or 3) are generated
    dynamically by the LLM (qwen3-32b) on the SAME theme, with a graceful
    fallback to the next-depth bank item.
  - Up to 3 consecutive follow-ups, then the engine switches trait.
  - 6 questions per trait (30 total), balanced 3 positive / 3 negative.
  - A new chain prefers a theme not yet used for that trait.

  This module is **stateless / pure** — the caller (the context layer)
  owns persistence. All state is a plain map with STRING keys so it
  roundtrips through JSON in the DB `metadata` column without atom
  surprises.

  LLM calls happen in two places:
    - `_generate_llm_followup` — per-ambiguous-answer
    - `generate_report`        — once at the end, interprets the Q&A log
  """

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.Psychometric.QuestionBank
  require Logger

  # ============================================================================
  # CONSTANTS (identical to the reference module)
  # ============================================================================

  @model "openai/gpt-oss-120b"
  @followup_model "openai/gpt-oss-120b"
  @traits ["Extraversion", "Agreeableness", "Conscientiousness", "Emotional Stability", "Openness"]
  @max_questions_per_trait 6
  @total_questions 30
  @target_keyed_per_trait 3
  @max_consecutive_followups 3

  @likert_options [
    "Strongly Agree",
    "Agree",
    "Neutral",
    "Disagree",
    "Strongly Disagree"
  ]

  @likert_raw_scores %{
    "Strongly Agree" => 5,
    "Agree" => 4,
    "Neutral" => 3,
    "Disagree" => 2,
    "Strongly Disagree" => 1
  }

  def traits, do: @traits
  def total_questions, do: @total_questions
  def likert_options, do: @likert_options

  # ============================================================================
  # INTERPRETATION SYSTEM PROMPT (verbatim from the reference)
  # ============================================================================

  @interpretation_system """
  You are a psychometric assessment interpretation assistant.

  Rules:
  - Do not diagnose mental health conditions.
  - Interpret traits as behavioral tendencies in workplace contexts.
  - Be neutral, professional, and constructive.
  - Scores are averages on a 1–5 scale per trait (3.0 = neutral baseline).
  - Do not quote or reference individual assessment questions or answers.
  - Synthesize behavioural patterns across responses; do not discuss item-level evidence.

  Output sections (use markdown headers exactly as shown):

  ## Overall Summary
  3–4 sentences describing the overall profile and how the traits interact.

  ## Strengths
  Bullet list — specific and behaviourally grounded, not generic praise.

  ## Development Areas
  Bullet list — framed constructively, not as deficits.
  """

  # ============================================================================
  # STATE INIT
  # ============================================================================

  @doc """
  Build a fresh assessment state. All keys are strings so the state can be
  JSON-encoded into the DB `metadata` column and decoded back without
  atom-key surprises.
  """
  def init_state do
    %{
      "current_trait" => nil,
      "consecutive_followup_count" => 0,
      "trait_counts" => Map.new(@traits, &{&1, 0}),
      "trait_scores" => Map.new(@traits, &{&1, []}),
      "current_question_chain" => [],
      "all_questions" => [],
      "total_asked" => 0,
      "assessment_complete" => false,
      "trait_keyed_counts" => Map.new(@traits, &{&1, %{"positive" => 0, "negative" => 0}}),
      "used_question_ids" => [],
      "themes_used_per_trait" => Map.new(@traits, &{&1, []}),
      "current_theme" => nil,
      "_active_question_id" => nil,
      # Kept so submit_answer can read the question awaiting an answer
      # (the LiveView/context relies on this).
      "current_q" => nil
    }
  end

  # ============================================================================
  # PUBLIC ENTRY POINTS
  # ============================================================================

  @doc """
  Start an assessment: pick a random trait, serve the first base question.
  Returns `{:ok, %{state: new_state, question: %{...}}}` or `{:error, reason}`.
  """
  def start_assessment(state \\ nil) do
    state = state || init_state()
    first_trait = Enum.random(@traits)
    state = Map.put(state, "current_trait", first_trait)

    case pick_base_question(state, first_trait) do
      nil ->
        {:error, {:no_bank_question, first_trait}}

      q ->
        new_state =
          state
          |> commit_active_question(q)
          |> Map.put("current_q", %{"question" => q["text"], "keyed" => q["keyed"]})

        {:ok,
         %{
           state: new_state,
           question: %{
             "question" => q["text"],
             "trait" => first_trait,
             "keyed" => q["keyed"],
             "technique" => q["technique"] || "",
             "question_number" => 1,
             "total_questions" => @total_questions
           }
         }}
    end
  end

  @doc """
  Submit an answer for the current question and advance the engine.

  Returns one of:
    * `{:ok, %{state: new_state, status: :continue, question: %{...}}}`
    * `{:ok, %{state: new_state, status: :complete}}`
    * `{:error, reason}` — original state preserved (no half-applied mutation)
  """
  def submit_answer(state, answer) when is_binary(answer) do
    cond do
      state["assessment_complete"] ->
        {:error, :already_complete}

      state["current_q"] == nil ->
        {:error, :no_active_question}

      not Map.has_key?(@likert_raw_scores, answer) ->
        {:error, {:invalid_answer, answer}}

      true ->
        current_q = state["current_q"]

        try do
          process_answer(state, current_q["question"], current_q["keyed"], answer)
        rescue
          e ->
            Logger.error("PSYCH | process_answer raised: #{inspect(e)}")
            {:error, :process_failed}
        end
    end
  end

  # ============================================================================
  # ANSWER PROCESSING — adaptive routing (port of reference process_answer)
  # ============================================================================

  defp process_answer(state, question, keyed, answer) do
    raw_score = @likert_raw_scores[answer]
    keyed_score = compute_keyed_score(raw_score, keyed)
    ambiguous? = is_ambiguous(raw_score, keyed)
    current_trait = state["current_trait"]
    current_theme = state["current_theme"]

    # Record the answer.
    state =
      state
      |> update_in(["current_question_chain"], fn chain ->
        chain ++
          [
            %{
              "question" => question,
              "answer" => answer,
              "raw_score" => raw_score,
              "keyed_score" => keyed_score,
              "keyed" => keyed
            }
          ]
      end)
      |> update_in(["all_questions"], fn all ->
        all ++
          [
            %{
              "trait" => current_trait,
              "theme" => current_theme,
              "question" => question,
              "answer" => answer,
              "keyed" => keyed,
              "keyed_score" => keyed_score
            }
          ]
      end)
      |> update_in(["trait_counts", current_trait], &(&1 + 1))
      |> update_in(["trait_scores", current_trait], &(&1 ++ [keyed_score]))
      |> update_in(["trait_keyed_counts", current_trait, keyed], &(&1 + 1))
      |> update_in(["total_asked"], &(&1 + 1))
      |> Map.put("_active_question_id", nil)

    cond do
      # ── Global completion check ──────────────────────────────────────────
      all_complete?(state) ->
        {:ok, %{state: Map.put(state, "assessment_complete", true), status: :complete}}

      # ── FOLLOW-UP BRANCH ─────────────────────────────────────────────────
      ambiguous? and state["consecutive_followup_count"] < @max_consecutive_followups and
          not trait_quota_full?(state, current_trait) ->
        state = update_in(state, ["consecutive_followup_count"], &(&1 + 1))

        preferred_key = required_keying(state, current_trait, false)

        q =
          generate_llm_followup(
            current_trait,
            current_theme,
            question,
            answer,
            preferred_key
          ) || pick_followup_question(state, current_trait, current_theme)

        if q != nil do
          continue_with_question(state, q, current_trait, true)
        else
          # Neither LLM nor bank had a follow-up → clean trait switch.
          state = Map.put(state, "consecutive_followup_count", 0)
          switch_trait(state, current_trait, question, keyed, answer)
        end

      # ── SWITCH-TRAIT BRANCH ──────────────────────────────────────────────
      true ->
        switch_trait(state, current_trait, question, keyed, answer)
    end
  end

  defp switch_trait(state, current_trait, question, keyed, answer) do
    state =
      state
      |> Map.put("consecutive_followup_count", 0)
      |> Map.put("current_question_chain", [])
      |> Map.put("current_theme", nil)

    case get_next_trait(state, current_trait) do
      nil ->
        {:ok, %{state: Map.put(state, "assessment_complete", true), status: :complete}}

      next_trait ->
        state = Map.put(state, "current_trait", next_trait)

        case pick_base_question(state, next_trait) do
          nil ->
            # Bank exhausted for this trait — mark it full and recurse.
            state = put_in(state, ["trait_counts", next_trait], @max_questions_per_trait)
            switch_trait(state, current_trait, question, keyed, answer)

          q ->
            continue_with_question(state, q, next_trait, false)
        end
    end
  end

  # Commit the chosen question, build the continue response packet.
  defp continue_with_question(state, q, trait, is_followup?) do
    state =
      state
      |> commit_active_question(q)
      |> Map.put("current_q", %{"question" => q["text"], "keyed" => q["keyed"]})

    base_packet = %{
      "question" => q["text"],
      "trait" => trait,
      "keyed" => q["keyed"],
      "technique" => q["technique"] || "",
      "question_number" => state["total_asked"] + 1,
      "total_questions" => @total_questions,
      "is_followup" => is_followup?
    }

    packet =
      if is_followup? do
        Map.put(base_packet, "followup_number", state["consecutive_followup_count"])
      else
        base_packet
      end

    {:ok, %{state: state, status: :continue, question: packet}}
  end

  # ============================================================================
  # TRAIT ROUTING
  # ============================================================================

  # Trait with fewest questions asked that has not hit its quota and is not the
  # excluded trait. Random on ties. Falls back to including the excluded trait.
  defp get_next_trait(state, exclude) do
    eligible_excluding =
      Enum.filter(@traits, fn t -> t != exclude and not trait_quota_full?(state, t) end)

    eligible =
      if eligible_excluding == [] do
        Enum.filter(@traits, fn t -> not trait_quota_full?(state, t) end)
      else
        eligible_excluding
      end

    case eligible do
      [] ->
        nil

      _ ->
        min_count = eligible |> Enum.map(&state["trait_counts"][&1]) |> Enum.min()
        candidates = Enum.filter(eligible, &(state["trait_counts"][&1] == min_count))
        Enum.random(candidates)
    end
  end

  # ============================================================================
  # SCORING HELPERS
  # ============================================================================

  defp compute_keyed_score(raw, "negative"), do: 6 - raw
  defp compute_keyed_score(raw, _), do: raw

  defp is_ambiguous(raw_score, keyed), do: compute_keyed_score(raw_score, keyed) in [2, 3]

  defp trait_quota_full?(state, trait),
    do: state["trait_counts"][trait] >= @max_questions_per_trait

  defp all_complete?(state) do
    state["total_asked"] >= @total_questions or
      Enum.all?(@traits, &trait_quota_full?(state, &1))
  end

  # Decide which keying the next question for `trait` should be. Once one side
  # hits the target, the other is forced/preferred. nil = either is acceptable.
  # (Reference uses the same body for strict true/false.)
  defp required_keying(state, trait, _strict) do
    pos = state["trait_keyed_counts"][trait]["positive"]
    neg = state["trait_keyed_counts"][trait]["negative"]

    cond do
      pos >= @target_keyed_per_trait and neg < @target_keyed_per_trait -> "negative"
      neg >= @target_keyed_per_trait and pos < @target_keyed_per_trait -> "positive"
      true -> nil
    end
  end

  # ============================================================================
  # QUESTION SELECTION (bank-driven)
  # ============================================================================

  # Pull a fresh base-depth question. Theme cascade:
  #   1. fresh themes + required keying
  #   2. fresh themes + either
  #   3. all themes   + required keying
  #   4. all themes   + either
  defp pick_base_question(state, trait) do
    used = MapSet.new(state["used_question_ids"])
    needed_key = required_keying(state, trait, true)
    used_themes = MapSet.new(state["themes_used_per_trait"][trait])

    all_themes = QuestionBank.themes_for_trait(trait)
    fresh_themes = Enum.reject(all_themes, &MapSet.member?(used_themes, &1))

    attempts = [
      {fresh_themes, needed_key},
      {fresh_themes, nil},
      {all_themes, needed_key},
      {all_themes, nil}
    ]

    Enum.find_value(attempts, fn {theme_pool, keying} ->
      theme_pool
      |> Enum.shuffle()
      |> Enum.find_value(fn theme ->
        case QuestionBank.candidates(trait, "base", keyed: keying, theme: theme, exclude_ids: used) do
          [] -> nil
          cand -> Enum.random(cand)
        end
      end)
    end)
  end

  # Pull the next follow-up on the active chain — same trait, same theme, one
  # depth tier deeper. consecutive_followup_count has already been incremented
  # before this is called, so it indexes directly into depth_order.
  defp pick_followup_question(state, trait, theme) do
    used = MapSet.new(state["used_question_ids"])
    depth_idx = state["consecutive_followup_count"]
    depth_order = QuestionBank.depth_order()

    if depth_idx >= length(depth_order) do
      nil
    else
      target_depth = Enum.at(depth_order, depth_idx)
      preferred_key = required_keying(state, trait, false)

      Enum.find_value([preferred_key, nil], fn keying ->
        case QuestionBank.candidates(trait, target_depth,
               keyed: keying,
               theme: theme,
               exclude_ids: used
             ) do
          [] -> nil
          cand -> Enum.random(cand)
        end
      end)
    end
  end

  # Mark a freshly-picked question as the one awaiting an answer.
  defp commit_active_question(state, q) do
    trait = q["trait"]
    theme = q["theme"]

    state
    |> Map.put("_active_question_id", q["id"])
    |> Map.put("current_theme", theme)
    |> update_in(["themes_used_per_trait", trait], fn themes ->
      if theme in themes, do: themes, else: themes ++ [theme]
    end)
    |> update_in(["used_question_ids"], &(&1 ++ [q["id"]]))
  end

  # ============================================================================
  # DYNAMIC LLM FOLLOW-UP
  # ============================================================================

  # Generate a clarifying follow-up Likert statement via LLM. Returns a
  # question map shaped like a bank entry, or nil on any failure (caller falls
  # back to the bank).
  defp generate_llm_followup(trait, theme, prev_question, prev_answer, target_keying) do
    keying_instruction =
      if target_keying do
        "The refined statement MUST be #{target_keying}-keyed."
      else
        "Keep the same keying direction as the previous statement."
      end

    system_prompt =
      "You are an expert psychometrician designing a Big Five Likert assessment.\n\n" <>
        "A respondent has just given a soft or ambiguous answer to a statement. " <>
        "Your job is to produce a CLARIFYING follow-up that:\n" <>
        "  1. Targets the SAME underlying construct as the previous statement — do NOT switch topics.\n" <>
        "  2. Removes whatever ambiguity in the wording allowed the soft answer.\n\n" <>
        "Common sources of ambiguity to fix:\n" <>
        "- Vague qualifiers ('usually', 'tends to', 'more often than not')\n" <>
        "- Two-sided phrasing that lets the respondent agree with both halves\n" <>
        "- Lack of a concrete situation, time, or counterparty\n" <>
        "- Weak intensity that makes both sides easy to endorse\n\n" <>
        "Strategies (pick whichever fits the previous statement best):\n" <>
        "- Pin the behaviour to a recent, concrete situation.\n" <>
        "- Convert two-sided phrasing into a forced choice.\n" <>
        "- Replace fuzzy words with measurable behaviour or frequency.\n" <>
        "- Sharpen intensity so neutrality stops being a defensible answer.\n\n" <>
        "Example of refinement (NOT escalation):\n" <>
        "  Previous: \"Reaching out to start a conversation comes more easily to me than waiting for one to come to me.\"\n" <>
        "  Refined:  \"At the last gathering where I knew almost no one, I was the one who started most of the conversations I had.\"\n\n" <>
        "Keep the core idea of the previous statement intact. Do not invent a new scenario unrelated to it.\n" <>
        "Output: ONE plain-English sentence. No questions. No second-person address.\n" <>
        "Respond ONLY with valid JSON:\n" <>
        "{ \"text\": \"<the refined statement>\", \"keyed\": \"positive\" | \"negative\" }"

    user_prompt =
      "Trait: #{trait}\n" <>
        "Theme: #{theme}\n" <>
        "Previous statement: \"#{prev_question}\"\n" <>
        "Respondent answered: \"#{prev_answer}\" — a soft/ambiguous response that did not clearly commit either way.\n\n" <>
        "Refine the previous statement into a follow-up that targets the SAME construct " <>
        "but removes the ambiguity. Keep the core idea; sharpen the wording.\n" <>
        "#{keying_instruction}"

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: "/no-think\n" <> user_prompt}
    ]

    with {:ok, %{"content" => raw}} when is_binary(raw) <-
           GroqClient.chat(messages,
             model: @followup_model,
             temperature: 0.6,
             max_tokens: 1024,
             reasoning_effort: "low",
             timeout: 60_000
           ),
         content <- GroqClient.strip_reasoning(raw),
         [json_str] <- Regex.run(~r/\{.*\}/s, content),
         {:ok, data} <- Jason.decode(json_str) do
      text = (data["text"] || "") |> to_string() |> String.trim()
      keyed = (data["keyed"] || "") |> to_string() |> String.trim() |> String.downcase()

      if text != "" and keyed in ["positive", "negative"] do
        %{
          "id" => "dyn_" <> dynamic_id(),
          "trait" => trait,
          "theme" => theme,
          "depth" => "dynamic",
          "keyed" => keyed,
          "text" => text,
          "technique" => "llm_dynamic"
        }
      else
        Logger.warning("PSYCH | llm_followup invalid output, falling back to bank: #{inspect(data)}")
        nil
      end
    else
      other ->
        Logger.warning("PSYCH | llm_followup generation failed, falling back to bank: #{inspect(other)}")
        nil
    end
  end

  defp dynamic_id do
    Ecto.UUID.generate() |> String.replace("-", "") |> String.slice(0, 8)
  end

  # ============================================================================
  # GENERATE REPORT (the only LLM call left in the engine besides follow-ups)
  # ============================================================================

  @doc """
  One-shot LLM interpretation of the completed assessment.

  Builds per-trait deterministic behavioural signals (no question text
  exposed), calls the LLM with the interpretation system prompt, and returns
  the markdown content.

  Returns `{:ok, %{report: <markdown string>, trait_scores: %{trait => float}}}`.
  """
  def generate_report(state) do
    trait_summaries =
      Enum.reduce(@traits, %{}, fn trait, acc ->
        scores = state["trait_scores"][trait] || []

        if scores == [] do
          acc
        else
          avg = Float.round(Enum.sum(scores) / length(scores), 2)
          total = length(scores)
          high = Enum.count(scores, &(&1 >= 4))
          mid = Enum.count(scores, &(&1 == 3))
          low = Enum.count(scores, &(&1 <= 2))

          base_signal =
            cond do
              high / total >= 0.6 ->
                "Consistently strong responses (#{high}/#{total} high-keyed scores)"

              low / total >= 0.6 ->
                "Consistently low responses (#{low}/#{total} low-keyed scores)"

              true ->
                "Mixed responses (high: #{high}, neutral: #{mid}, low: #{low})"
            end

          theme_scores =
            state["all_questions"]
            |> Enum.filter(&(&1["trait"] == trait))
            |> Enum.reduce(%{order: [], map: %{}}, fn item, agg ->
              theme = item["theme"] || "unknown"
              ks = item["keyed_score"]

              if Map.has_key?(agg.map, theme) do
                %{agg | map: Map.update!(agg.map, theme, &(&1 ++ [ks]))}
              else
                %{order: agg.order ++ [theme], map: Map.put(agg.map, theme, [ks])}
              end
            end)

          theme_signals =
            Enum.map(theme_scores.order, fn theme ->
              t_scores = theme_scores.map[theme]
              t_avg = Float.round(Enum.sum(t_scores) / length(t_scores), 2)
              "#{titleize_theme(theme)}: avg #{t_avg}/5"
            end)

          Map.put(acc, trait, %{"score" => avg, "signals" => [base_signal | theme_signals]})
        end
      end)

    user_prompt = """
    Assessment complete.

    Trait behavioural summaries (scores on a 1.0–5.0 scale, 3.0 = neutral baseline):
    #{Jason.encode!(trait_summaries, pretty: true)}

    Generate the full psychometric interpretation report as specified.
    Ground interpretations in the recurring behavioural patterns reflected in the signals above.
    Do not quote, reference, or mention individual questions or answers.
    Focus on synthesized behavioural tendencies.
    """

    Logger.info("PSYCH | Generating final report | total_questions=#{state["total_asked"]}")

    trait_scores =
      Map.new(state["trait_scores"], fn
        {trait, []} -> {trait, "N/A"}
        {trait, scores} -> {trait, Float.round(Enum.sum(scores) / length(scores), 2)}
      end)

    messages = [
      %{role: "system", content: @interpretation_system},
      %{role: "user", content: user_prompt}
    ]

    case GroqClient.chat(messages,
           model: @model,
           temperature: 0.4,
           max_tokens: 3000,
           reasoning_effort: "low",
           timeout: 90_000
         ) do
      {:ok, %{"content" => content}} when is_binary(content) ->
        trimmed = content |> GroqClient.strip_reasoning() |> String.trim()

        report =
          if trimmed == "" do
            "Report generation failed — the model returned an empty response. Please retry."
          else
            trimmed
          end

        {:ok, %{report: report, trait_scores: trait_scores}}

      {:error, reason} ->
        Logger.error("PSYCH | Report LLM call failed: #{inspect(reason)}")

        {:ok,
         %{
           report:
             "Report generation failed — the interpretation service was unavailable. Please retry.",
           trait_scores: trait_scores
         }}
    end
  end

  defp titleize_theme(theme) do
    theme
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # ============================================================================
  # TRAIT SCORE → SCHEMA COLUMN MAPPING
  # ============================================================================

  @doc """
  Map adaptive trait names to existing `student_psychometric_assessments`
  schema columns. Used by the context to fill the float score columns
  without a DB migration.

  Note: `neuroticism_score` historically held the inverse (Emotional
  Stability is the opposite of Neuroticism), but for backwards
  compatibility we store the ES value directly.
  """
  def trait_to_schema_column("Extraversion"), do: :extraversion_score
  def trait_to_schema_column("Agreeableness"), do: :agreeableness_score
  def trait_to_schema_column("Conscientiousness"), do: :conscientiousness_score
  def trait_to_schema_column("Emotional Stability"), do: :neuroticism_score
  def trait_to_schema_column("Openness"), do: :openness_score
  def trait_to_schema_column(_), do: nil

  @doc "Average per-trait score from the state (1.0–5.0 scale)."
  def trait_averages(state) do
    Map.new(state["trait_scores"], fn
      {trait, []} -> {trait, nil}
      {trait, scores} -> {trait, Float.round(Enum.sum(scores) / length(scores), 2)}
    end)
  end
end
