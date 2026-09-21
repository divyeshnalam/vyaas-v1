defmodule VyaasaCampus.AI.Interview.Session do
  @moduledoc """
  State machine that drives the rebuilt interview: it sequences the dedicated
  agents — `Profile` → `Planner` → `Interviewer` (with `Github` ownership
  questions for project deep-dives) → `Evaluator` → final report.

  Replaces the monolithic `InterviewEngine` while preserving its public
  contract so the `Interview` context and the LiveView need no behavioural
  changes:

    * `new_session/4`   → `{:ok, state}` (raises nothing; `{:error, reason}` if
      the resume has no usable content)
    * `generate_greeting/1` → state with a warmer LLM greeting (silent fallback)
    * `greeting/1`      → `%{text, spoken}`
    * `proceed/1`       → `{:ok, state, %{stage: :interview, next_question, q_index: 0}}`
    * `submit_answer/2` → `{:ok, state, %{stage: :interview | :done, ...}}`

  State is a plain map carried through the LiveView socket. Per-answer scoring
  is silent (drives adaptive difficulty + follow-ups); only the final
  placement-readiness markdown report is surfaced.
  """

  alias VyaasaCampus.AI.GroqClient

  alias VyaasaCampus.AI.Interview.{
    Profile,
    Planner,
    Interviewer,
    Evaluator,
    Github,
    Consistency,
    Reporter,
    Specializations,
    ContentCheck
  }

  require Logger

  # Per-answer rollup weights for the LiveView per-answer score (the authoritative
  # competency overall uses domain weights at finish; this feeds adaptive difficulty).
  @w_tech 0.50
  @w_comm 0.30
  @w_lead 0.20

  # Follow-up budget (reference settings.py).
  @max_followups_total 2
  @max_followups_section 1

  # Strong/weak topic thresholds (reference settings.py).
  @strong_topic_threshold 70.0
  @weak_topic_threshold 50.0

  # ── Session bootstrap ─────────────────────────────────────────────────────
  @doc """
  Build a session from a parsed-resume map OR a `%Profile{}`. Returns
  `{:ok, state}` or `{:error, reason}` when there's nothing to anchor to.
  """
  def new_session(session_id, student_id, profile_or_resume, opts \\ []) do
    VyaasaCampus.AI.Tracing.span("interview.new_session", session_id, fn ->
      do_new_session(session_id, student_id, profile_or_resume, opts)
    end)
  end

  defp do_new_session(session_id, student_id, %Profile{} = profile, opts)
      when is_binary(session_id) do
    if empty_profile?(profile) do
      {:error, :no_resume_data}
    else
      plan = Planner.build_plan(profile)

      state = %{
        session_id: session_id,
        student_id: student_id,
        candidate_name: profile.name,
        profile: profile,
        plan: plan,
        stage: :greeting,
        q_index: 0,
        max_questions: Keyword.get(opts, :max_questions, plan.total_questions),
        current_question: nil,
        asked: [],
        evaluations: [],
        scores: [],
        chat_history: [],
        strong_topics: [],
        weak_topics: [],
        last_score: nil,
        github_questions: nil,
        warning_count: 0,
        greeting_text: build_greeting(profile.name)
      }

      {:ok, state}
    end
  end

  defp do_new_session(session_id, student_id, resume, opts) when is_map(resume) do
    do_new_session(session_id, student_id, Profile.from_ats_phase(resume), opts)
  end

  defp empty_profile?(%Profile{} = p) do
    p.projects == [] and p.work_history == [] and p.primary_skills == [] and
      p.name in [nil, ""]
  end

  # ── Greeting ──────────────────────────────────────────────────────────────
  def greeting(%{greeting_text: text}), do: %{text: text, spoken: strip_markdown(text)}

  @doc "Warmer, resume-aware LLM greeting; returns state unchanged on failure."
  def generate_greeting(state) do
    VyaasaCampus.AI.Tracing.span("interview.greeting", state[:session_id], fn -> do_generate_greeting(state) end)
  end

  defp do_generate_greeting(%{profile: profile} = state) do
    first = first_name(state.candidate_name)

    hook =
      cond do
        profile.projects != [] and profile.work_history != [] ->
          "They have both personal projects and work experience on their resume."

        profile.projects != [] ->
          "They have personal projects worth referencing."

        profile.work_history != [] ->
          "They have work experience worth referencing."

        true ->
          ""
      end

    system = """
    You are Vyaasa, a warm, encouraging AI interviewer for a placement-readiness assessment.
    Write a SHORT, friendly greeting (3-4 sentences, ~50-70 words) the candidate sees
    before the interview. Address them by first name, introduce yourself as Vyaasa, mention
    you'll ask about their projects and work experience, and invite them to click Proceed
    when ready. Warm and clear. No emojis, no markdown, no lists. You MAY gently reference
    their resume breadth WITHOUT naming specific projects, companies, or technologies.
    Return ONLY the greeting text.
    """

    user =
      "Candidate first name: #{first}\n#{if hook != "", do: "Resume context: #{hook}\n", else: ""}Now write the greeting."

    case GroqClient.ask(system, user,
           model: "openai/gpt-oss-120b",
           temperature: 0.6,
           max_tokens: 180,
           reasoning_effort: "low",
           timeout: 20_000
         ) do
      {:ok, text} when is_binary(text) ->
        cleaned = text |> GroqClient.strip_reasoning() |> String.trim() |> strip_wrapping_quotes()
        if cleaned == "", do: state, else: %{state | greeting_text: cleaned}

      {:error, reason} ->
        Logger.warning("INTERVIEW | greeting LLM failed, using template: #{inspect(reason)}")
        state
    end
  end

  # ── Greeting → first question ───────────────────────────────────────────────
  def proceed(state) do
    VyaasaCampus.AI.Tracing.span("interview.proceed", state[:session_id], fn -> do_proceed(state) end)
  end

  defp do_proceed(%{stage: :greeting} = state) do
    state = ensure_github_pool(state)

    case next_question_map(%{state | asked: []}) do
      {:ok, question} ->
        question = Map.put(question, :id, 1)
        new_state = %{state | stage: :interview, current_question: question, asked: [question]}
        {:ok, new_state, %{stage: :interview, next_question: question.text, q_index: 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_proceed(%{stage: stage}), do: {:error, "Cannot proceed from stage #{inspect(stage)}"}

  # ── Submit answer → evaluate → next / finish ────────────────────────────────
  def submit_answer(state, answer) do
    VyaasaCampus.AI.Tracing.span("interview.submit_answer", state[:session_id], fn -> do_submit_answer(state, answer) end)
  end

  defp do_submit_answer(%{stage: :interview} = state, answer) when is_binary(answer) do
    answer = String.trim(answer)

    cond do
      answer == "" ->
        {:error, :empty_answer}

      match?({true, _}, ContentCheck.check(answer)) ->
        moderate(state)

      true ->
        do_submit(state, answer)
    end
  end

  defp do_submit_answer(%{stage: stage}, _answer), do: {:error, "Cannot submit answer in stage #{inspect(stage)}"}

  # Content moderation: first violation warns (re-ask same question); a second
  # ends the interview unscored (port of the reference _apply_content_check).
  defp moderate(state) do
    count = state.warning_count + 1

    if count >= 2 do
      {:ok, %{state | warning_count: count, stage: :terminated, current_question: nil},
       %{
         stage: :terminated,
         q_index: state.q_index,
         message:
           "Your interview has been terminated due to repeated inappropriate language or unethical responses. This session will not be scored."
       }}
    else
      {:ok, %{state | warning_count: count},
       %{
         stage: :warning,
         q_index: state.q_index,
         warning_count: count,
         next_question: state.current_question.text,
         message:
           "Please keep your responses professional and relevant to the interview. A second violation will end the interview immediately."
       }}
    end
  end

  defp do_submit(state, answer) do
    state = ensure_github_pool(state)
    question = state.current_question
    raw_eval = Evaluator.evaluate(question, answer, state.profile, prior_qa(state.chat_history))
    lv_eval = to_lv_evaluation(raw_eval)
    score = score_entry(question, answer, raw_eval, state.profile.domain)

    state =
      %{
        state
        | evaluations: state.evaluations ++ [lv_eval],
          scores: state.scores ++ [score],
          chat_history: state.chat_history ++ [{"Assistant", question.text}, {"Candidate", answer}],
          last_score: raw_eval,
          q_index: state.q_index + 1
      }
      |> track_topic(question, score)

    if state.q_index >= state.max_questions do
      finish(state, lv_eval)
    else
      case next_question_map(state) do
        {:ok, next_q} ->
          next_q = Map.put(next_q, :id, length(state.asked) + 1)
          new_state = %{state | current_question: next_q, asked: state.asked ++ [next_q]}

          {:ok, new_state,
           %{stage: :interview, next_question: next_q.text, q_index: new_state.q_index, evaluation: lv_eval}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ── Next-question decision (CF → follow-up → GitHub ownership → section) ─────
  defp next_question_map(%{profile: profile, plan: plan, asked: asked, last_score: last_score} = state) do
    total = plan.total_questions
    asked_count = length(asked)

    cond do
      # Cultural fit is always last; let the interviewer build it.
      asked_count >= total - 1 ->
        Interviewer.next_question(profile, plan, asked, last_score)

      # One controlled follow-up when the last answer was shallow — bounded by
      # the total + per-topic follow-up budget.
      needs_followup?(last_score) and followup_budget?(asked) ->
        Interviewer.next_question(profile, plan, asked, last_score)

      true ->
        case next_github_question(state) do
          nil -> Interviewer.next_question(profile, plan, asked, last_score)
          q -> {:ok, q}
        end
    end
  end

  # Serve the next GitHub ownership question from the pre-fetched pool when the
  # current section is a project deep-dive (2/repo, max 3 total — bounded by the
  # pool size). Falls back to a generic interviewer project question otherwise.
  defp next_github_question(%{plan: plan, asked: asked, github_questions: pool}) when is_list(pool) do
    used = Enum.count(asked, &(&1[:type] == "ownership_verify"))

    if project_slot?(plan, asked) and used < length(pool) do
      Enum.at(pool, used)
    else
      nil
    end
  end

  defp next_github_question(_state), do: nil

  defp project_slot?(plan, asked) do
    case Interviewer.current_section(plan, asked) do
      %{name: name} -> name in ["project_deep_dive", "portfolio_deep_dive"]
      _ -> false
    end
  end

  # Fetch the GitHub ownership-question pool once, lazily (network + LLM). nil =
  # not yet fetched; a list (possibly empty) = fetched.
  defp ensure_github_pool(%{github_questions: nil, profile: profile} = state) do
    %{state | github_questions: Github.ownership_questions_pool(profile)}
  end

  defp ensure_github_pool(state), do: state

  # Last 3 Q&A pairs as plaintext for the evaluator's consistency check.
  defp prior_qa([]), do: "None — this is the first answer."

  defp prior_qa(chat_history) do
    pairs =
      chat_history
      |> Enum.chunk_every(2)
      |> Enum.filter(&match?([{"Assistant", _}, {"Candidate", _}], &1))
      |> Enum.take(-3)
      |> Enum.map_join("\n", fn [{"Assistant", q}, {"Candidate", a}] ->
        "  Q: #{q}\n  A: #{String.slice(a, 0, 300)}"
      end)

    if pairs == "", do: "None — this is the first answer.", else: pairs
  end

  defp needs_followup?(%{needs_followup: true}), do: true
  defp needs_followup?(_), do: false

  # Bounded follow-ups: never two in a row, ≤2 total, ≤1 per topic.
  defp followup_budget?(asked) do
    total = Enum.count(asked, &(&1[:type] == "followup"))

    last_topic =
      case List.last(asked),
        do: (
          %{topic: t} -> t
          _ -> nil
        )

    per_topic = Enum.count(asked, &(&1[:type] == "followup" and &1[:topic] == last_topic))

    last_not_followup? = match?(%{type: t} when t != "followup", List.last(asked)) or List.last(asked) == nil

    last_not_followup? and total < @max_followups_total and per_topic < @max_followups_section
  end

  # ── Per-answer score entry (feeds consistency, reporter, strong/weak topics) ─
  defp score_entry(question, answer, raw, domain) do
    cf? = raw[:is_cultural_fit] == true

    base = %{
      question_id: question[:id] || 0,
      section: question[:section] || "",
      topic: question[:topic] || "",
      difficulty: question[:difficulty] || 2,
      question_text: question.text,
      answer_text: answer,
      is_cultural_fit: cf?,
      technical: clamp(raw[:technical]),
      communication: clamp(raw[:communication]),
      leadership: clamp(raw[:leadership]),
      cultural_fit: clamp(raw[:cultural_fit]),
      strengths: raw[:strengths] || [],
      improvements: raw[:improvements] || [],
      feedback: raw[:feedback] || "",
      needs_followup: raw[:needs_followup] == true
    }

    Map.put(base, :overall, question_overall(base, domain))
  end

  # Single representative 0-100 score for one answer (domain-weighted).
  defp question_overall(%{is_cultural_fit: true} = s, _domain), do: Float.round(s.cultural_fit / 1, 1)

  defp question_overall(s, domain) do
    w = Specializations.competency_weights(domain)
    non_cf = w["technical"] + w["communication"] + w["leadership"]

    Float.round(
      (s.technical * w["technical"] + s.communication * w["communication"] + s.leadership * w["leadership"]) / non_cf,
      1
    )
  end

  # Auto-classify the question's topic as strong/weak from its overall score.
  defp track_topic(state, question, score) do
    topic = question[:topic]

    cond do
      is_nil(topic) or topic == "" ->
        state

      score.overall >= @strong_topic_threshold ->
        %{state | strong_topics: Enum.uniq(state.strong_topics ++ [topic])}

      score.overall < @weak_topic_threshold ->
        %{state | weak_topics: Enum.uniq(state.weak_topics ++ [topic])}

      true ->
        state
    end
  end

  # ── Evaluator map → LiveView-facing evaluation (string keys) ────────────────
  defp to_lv_evaluation(%{is_cultural_fit: true} = e) do
    cf = clamp(e[:cultural_fit])

    %{
      "score" => cf,
      "dimensions" => %{"cultural_fit" => cf},
      "weak_dimensions" => if(cf < 55, do: ["cultural_fit"], else: []),
      "strengths" => e[:strengths] || [],
      "weaknesses" => e[:improvements] || [],
      "evaluation" => e[:feedback] || "",
      "feedback" => e[:feedback] || "",
      "error" => false
    }
  end

  defp to_lv_evaluation(e) do
    tech = clamp(e[:technical])
    comm = clamp(e[:communication])
    lead = clamp(e[:leadership])
    score = round(tech * @w_tech + comm * @w_comm + lead * @w_lead)

    dims = %{"domain_expertise" => tech, "communication" => comm, "leadership" => lead}

    %{
      "score" => score,
      "dimensions" => dims,
      "weak_dimensions" => dims |> Enum.filter(fn {_k, v} -> v < 55 end) |> Enum.map(&elem(&1, 0)),
      "strengths" => e[:strengths] || [],
      "weaknesses" => e[:improvements] || [],
      "evaluation" => e[:feedback] || "",
      "feedback" => e[:feedback] || "",
      "error" => false
    }
  end

  defp clamp(v) when is_number(v), do: v |> round() |> max(0) |> min(100)
  defp clamp(_), do: 50

  # ── Finish — consistency → competency scores → reporter → final report ───────
  defp finish(state, last_eval) do
    comp = competency_scores(state)
    consistency = Consistency.analyze(state.profile, consistency_qa(state))

    report =
      Reporter.generate(%{
        profile: state.profile,
        target_role: state.plan[:target_role] || state.profile.target_role,
        comp: comp,
        scores: reporter_scores(state),
        qa: reporter_qa(state),
        consistency: consistency,
        strong_topics: state.strong_topics,
        weak_topics: state.weak_topics
      })

    readiness = readiness_level(comp["overall"])
    report_md = render_report(comp, report, consistency, readiness)
    metrics = build_metrics(state, comp, consistency, readiness)

    new_state = %{state | stage: :done, current_question: nil}

    {:ok, new_state,
     %{
       stage: :done,
       q_index: new_state.q_index,
       evaluation: last_eval,
       overall: report_md,
       metrics: metrics,
       thanks_text: build_thanks(state.candidate_name)
     }}
  end

  # Domain-weighted competency scores (port of state.get_competency_scores).
  defp competency_scores(state) do
    w = Specializations.competency_weights(state.profile.domain)
    main = Enum.reject(state.scores, & &1.is_cultural_fit)
    cf = Enum.filter(state.scores, & &1.is_cultural_fit)

    technical = avg(Enum.map(main, & &1.technical))
    communication = avg(Enum.map(main, & &1.communication))
    leadership = avg(Enum.map(main, & &1.leadership))
    cultural_fit = avg(Enum.map(cf, & &1.cultural_fit))

    # Overall score is always a whole number.
    overall =
      round(
        technical * w["technical"] + communication * w["communication"] +
          leadership * w["leadership"] + cultural_fit * w["cultural_fit"]
      )

    %{
      "technical" => technical,
      "communication" => communication,
      "leadership" => leadership,
      "cultural_fit" => cultural_fit,
      "overall" => overall,
      "weights" => w
    }
  end

  defp avg([]), do: 0.0
  defp avg(vals), do: Float.round(Enum.sum(vals) / length(vals), 1)

  defp consistency_qa(state) do
    Enum.map(state.scores, fn s ->
      %{
        id: s.question_id,
        section: s.section,
        topic: s.topic,
        difficulty: s.difficulty,
        question: s.question_text,
        answer: s.answer_text,
        overall: s.overall,
        needs_followup: s.needs_followup
      }
    end)
  end

  defp reporter_scores(state) do
    Enum.map(state.scores, fn s ->
      %{
        question_id: s.question_id,
        topic: s.topic,
        is_cultural_fit: s.is_cultural_fit,
        technical: s.technical,
        communication: s.communication,
        leadership: s.leadership,
        cultural_fit: s.cultural_fit,
        feedback: s.feedback,
        strengths: s.strengths,
        improvements: s.improvements
      }
    end)
  end

  defp reporter_qa(state) do
    Enum.map(state.scores, fn s ->
      %{question_id: s.question_id, section: s.section, text: s.question_text}
    end)
  end

  # ── Final markdown (keeps "What Went Well"/"Areas for Improvement" headers
  #    so the LiveView's strengths/improvements extraction keeps working) ───────
  defp render_report(comp, report, consistency, readiness) do
    overall = round(comp["overall"])

    sections = [
      "# 🎯 Placement Readiness Score: #{overall}/100 — #{readiness}",
      "## 📈 Overall Summary\n#{report.overall_summary}",
      "## 📊 Competency Scores\n" <>
        "- Technical: #{comp["technical"]}/100\n" <>
        "- Communication: #{comp["communication"]}/100\n" <>
        "- Leadership: #{comp["leadership"]}/100\n" <>
        "- Cultural Fit: #{comp["cultural_fit"]}/100",
      "## 🌟 What Went Well\n#{bullets(report.technical_strengths)}",
      "## 💡 Areas for Improvement\n#{bullets(report.technical_gaps)}",
      maybe_section("## ✅ Verified Skills", report.verified_skills),
      maybe_section("## ⚠️ Claims to Probe Further", report.suspicious_claims),
      "## 🗣️ Communication Assessment\n#{report.communication_assessment}",
      "## 🔎 Consistency\nOverall consistency: #{consistency[:overall_consistency]} · Contradictions: #{length(consistency[:contradictions] || [])}"
    ]

    sections |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
  end

  defp bullets([]), do: "- (none noted)"
  defp bullets(items), do: Enum.map_join(items, "\n", &"- #{&1}")

  defp maybe_section(_title, []), do: ""
  defp maybe_section(title, items), do: "#{title}\n#{bullets(items)}"

  # Metrics for the LiveView + AI8 publish. skill_scores uses the canonical AI8
  # interview keys (technical → domain_expertise).
  defp build_metrics(state, comp, consistency, readiness) do
    has_main = Enum.any?(state.scores, &(not &1.is_cultural_fit))
    has_cf = Enum.any?(state.scores, & &1.is_cultural_fit)

    skill_scores =
      %{}
      |> maybe_put(has_main, "domain_expertise", comp["technical"])
      |> maybe_put(has_main, "communication", comp["communication"])
      |> maybe_put(has_main, "leadership", comp["leadership"])
      |> maybe_put(has_cf, "cultural_fit", comp["cultural_fit"])

    %{
      "average_score" => comp["overall"],
      "total_questions" => length(state.scores),
      "valid_questions" => length(state.scores),
      "skill_scores" => skill_scores,
      "competency" => comp,
      "consistency" => %{
        "overall_consistency" => consistency[:overall_consistency],
        "contradictions" => length(consistency[:contradictions] || []),
        "verified_skills" => consistency[:verified_skills] || [],
        "suspicious_claims" => consistency[:suspicious_claims] || []
      },
      "readiness_level" => readiness
    }
  end

  defp maybe_put(map, true, key, val), do: Map.put(map, key, val)
  defp maybe_put(map, false, _key, _val), do: map

  defp readiness_level(avg) when avg >= 85, do: "🎯 Interview Ready"
  defp readiness_level(avg) when avg >= 70, do: "✅ Almost Ready"
  defp readiness_level(avg) when avg >= 55, do: "📚 Good Progress"
  defp readiness_level(avg) when avg >= 40, do: "🌱 Developing"
  defp readiness_level(_), do: "🎓 Needs Practice"

  # ── Small helpers ───────────────────────────────────────────────────────────
  defp build_greeting(name) do
    "Hi #{first_name(name)}, I'm Vyaasa — your AI interviewer. I'll ask you a few questions about your projects and work experience to understand your strengths. Take your time and answer naturally. Click Proceed when you're ready to begin."
  end

  defp build_thanks(name) do
    "Thanks for completing the interview, #{first_name(name)}. I'm putting together your placement-readiness report now."
  end

  defp first_name(nil), do: "there"

  defp first_name(full_name) do
    case full_name |> to_string() |> String.trim() |> String.split(" ", trim: true) do
      [first | _] -> first
      _ -> "there"
    end
  end

  defp strip_wrapping_quotes(text) do
    text
    |> String.replace_prefix("\"", "")
    |> String.replace_suffix("\"", "")
    |> String.replace_prefix("'", "")
    |> String.replace_suffix("'", "")
    |> String.trim()
  end

  defp strip_markdown(text) when is_binary(text) do
    text
    |> String.replace(~r/[#*_`>]/, "")
    |> String.replace(~r/\n{2,}/, "\n")
    |> String.trim()
  end

  defp strip_markdown(_), do: ""
end