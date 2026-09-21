defmodule VyaasaCampus.AI.JamEngine do
  @moduledoc """
  Native Elixir JAM (Just A Minute) assessment engine.
  Replaces the Python JAM service for topic generation, evaluation, and transcription.

  Audio processing pipeline:
  - Raw audio → Groq Whisper API (transcription) — no Python preprocessing needed
  - Topic generation → Groq chat completion
  - Speech evaluation → Groq chat completion
  """

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.Contexts.AI8

  require Logger

  @min_word_count 30

  # Conservative filler list — avoids common words (so/like/well/right) that are
  # usually legitimate and would inflate the count with false positives.
  @filler_words ~w(um uh umm uhh er ah hmm erm basically literally)
  @filler_phrases ["you know", "i mean", "kind of", "sort of"]

  # Model used for speech evaluation / report generation. A larger model than the
  # fast default gives sharper, more consistent scoring + feedback.
  @eval_model "openai/gpt-oss-120b"

  # The five observable rubric dimensions the LLM scores from the transcript.
  @rubric_dimensions ["clarity", "structure", "relevance", "impact", "confidence"]

  # How those five dimensions roll up into the two AI8 indexes JAM feeds.
  # Weights within each index sum to 1.0. `structure` and `impact` are
  # cross-cutting (they evidence both how well the message landed AND how well
  # the candidate organised original substance on an unprepared topic).
  @communication_map %{"clarity" => 0.30, "structure" => 0.25, "confidence" => 0.25, "impact" => 0.20}
  @adaptability_map %{"relevance" => 0.45, "impact" => 0.30, "structure" => 0.25}

  # The two canonical AI8 dimensions JAM produces.
  @jam_indexes ["communication", "adaptability"]

  # Overall blend of the two indexes when the AI8 super-admin config has no
  # weights for the jam module. Production config sets communication 56 /
  # adaptability 44; this is only the fallback.
  @default_index_weights %{"communication" => 0.60, "adaptability" => 0.40}

  # ============================================================================
  # TOPIC GENERATION
  # ============================================================================

  @topic_generation_prompt """
  You are an expert HR recruitment assistant conducting a JAM (Just A Minute) session for fresh graduates. You give new and enthusiastic topics whenever asked, do not repeat or roam around the same category.

  Generate ONE JAM topic that:
  1. Is TIMELY and RELEVANT (refer to events from the last 3-6 months when possible)
  2. Does not spark debate or have multiple perspectives
  3. Tests communication, critical thinking, and awareness
  4. Connects to workplace skills or college culture or societal trends or real life experiences.

  TOPIC CATEGORIES (pick one):
  - Current Affairs & Technology (AI revolution, gig economy, remote work trends)
  - Contemporary College Challenges (Gen Z in workplace, work-life balance, skill gaps)
  - Modern Social Phenomena (influencer culture, digital detox, sustainability)
  - Recent Events & Trends (economic changes, policy shifts, cultural movements)
  - Future of Work & Education (automation, upskilling, entrepreneurship)
  - Exploration of Life (tours, trips, exploration)

  Good Topics are:
  - Debatable (not one-sided)
  - STRICTLY Relatable to fresh graduates
  - Contemporary (feel "2022-2025" not timeless)
  - Thought-provoking and engaging

  Avoid:
  - Generic motivational topics ("importance of hard work")
  - Overly technical jargon
  - Politically divisive or sensitive topics
  - Strictly do not revolve around the same topic categories always

  Output Format:
  <Topic> --- <One sentence explaining what this tests in the candidate>
  """

  # Categories one of which is selected at random per session so the model is
  # forced into a different region of topic space each call (a static prompt at
  # low temperature otherwise collapses onto the same most-probable topic).
  @topic_categories [
    "Current Affairs & Technology (AI revolution, gig economy, remote work trends)",
    "Contemporary College Challenges (Gen Z in workplace, work-life balance, skill gaps)",
    "Modern Social Phenomena (influencer culture, digital detox, sustainability)",
    "Recent Events & Trends (economic changes, policy shifts, cultural movements)",
    "Future of Work & Education (automation, upskilling, entrepreneurship)",
    "Exploration of Life (tours, trips, exploration)"
  ]

  # Pushes the model off its single most-probable completion. Paired with a
  # random category + per-call seed so topics actually vary between sessions.
  @topic_temperature 0.9

  # Builds a per-call prompt that pins a random category and a variation token,
  # plus any extra instruction (e.g. excluding a previous topic on re-roll).
  # "/no_think" suppresses gpt-oss-20b's (the default chat model) reasoning
  # preamble — this parser is a plain "<Topic> --- <explanation>" string
  # split that leaked <think> content would corrupt.
  defp topic_prompt(extra \\ "") do
    category = Enum.random(@topic_categories)
    nonce = :rand.uniform(1_000_000)

    @topic_generation_prompt <>
      """

      For THIS session, the topic MUST come from this category: #{category}
      Make it specific and fresh, not a generic example from the list above.#{extra}
      (variation token, ignore in output: #{nonce})
      /no_think
      """
  end

  defp topic_opts,
    do: [temperature: @topic_temperature, seed: :rand.uniform(2_000_000_000), reasoning_effort: "low"]

  @doc """
  Generate a JAM topic.
  Returns {:ok, %{topic_title, topic_explanation}} or {:error, reason}.
  """
  def generate_topic do
    case GroqClient.ask("You generate JAM session topics.", topic_prompt(), topic_opts()) do
      {:ok, response} ->
        response = GroqClient.strip_reasoning(response)

        {title, explanation} =
          case String.split(response, "---", parts: 2) do
            [t, e] ->
              {clean_topic_title(t), String.trim(e) |> String.trim("\"") |> String.trim("'")}

            _ ->
              {clean_topic_title(response), "Share your thoughts on this topic."}
          end

        tts_text = "Your topic is: #{title}. #{explanation}"
        audio_data = generate_tts_audio(tts_text)

        {:ok,
         %{
           topic_title: title,
           topic_explanation: explanation,
           guidance:
             "Consider different perspectives on this topic. Think about causes, effects, examples, and potential solutions or viewpoints.",
           audio_data: audio_data,
           audio_type: "wav"
         }}

      {:error, reason} ->
        Logger.error("JAM | Topic generation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Generate a different topic, excluding a previous one.
  """
  def change_topic(previous_topic) do
    modified_prompt =
      topic_prompt("""

      IMPORTANT: Do NOT generate anything similar to this previous topic: "#{previous_topic}"
      Generate a completely different topic from a different category.\
      """)

    case GroqClient.ask("You generate JAM session topics.", modified_prompt, topic_opts()) do
      {:ok, response} ->
        response = GroqClient.strip_reasoning(response)

        {title, explanation} =
          case String.split(response, "---", parts: 2) do
            [t, e] ->
              {clean_topic_title(t), String.trim(e) |> String.trim("\"") |> String.trim("'")}

            _ ->
              {clean_topic_title(response), "Share your thoughts on this topic."}
          end

        tts_text = "Your new topic is: #{title}. #{explanation}"
        audio_data = generate_tts_audio(tts_text)

        {:ok,
         %{
           topic_title: title,
           topic_explanation: explanation,
           guidance: "Consider different perspectives on this topic.",
           audio_data: audio_data,
           audio_type: "wav"
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Explain a topic in more detail.
  """
  def explain_topic(topic_title) do
    prompt = """
    You are an expert communication coach. A candidate has the topic: "#{topic_title}".
    Explain the purpose of this topic in 2-3 sentences. Focus on what skills it reveals and why it's relevant for fresh graduates.
    DO NOT give examples or hints on how to answer.
    /no_think
    """

    case GroqClient.ask("You are an expert communication coach.", prompt, reasoning_effort: "low") do
      {:ok, explanation} ->
        trimmed = explanation |> GroqClient.strip_reasoning() |> String.trim()
        audio_data = generate_tts_audio(trimmed)

        {:ok,
         %{
           explanation: trimmed,
           audio_data: audio_data,
           audio_type: "wav"
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # AUDIO TRANSCRIPTION (Groq Whisper — no Python preprocessing)
  # ============================================================================

  @doc """
  Transcribe audio using Groq Whisper API.
  Accepts a file path to an audio file.
  Returns {:ok, transcript} or {:error, reason}.
  """
  def transcribe_audio(audio_file_path) do
    Logger.info("JAM | Transcribing audio: #{audio_file_path}")
    GroqClient.transcribe_file(audio_file_path)
  end

  @doc """
  Transcribe audio from binary data.
  """
  def transcribe_audio_data(audio_binary, filename \\ "recording.webm") do
    Logger.info("JAM | Transcribing audio data: #{byte_size(audio_binary)} bytes")
    GroqClient.transcribe_audio(audio_binary, filename: filename)
  end

  # ============================================================================
  # SPEECH EVALUATION
  # ============================================================================

  @doc """
  Evaluate a JAM speech transcript.
  Returns {:ok, evaluation_data} or {:error, reason}.

  evaluation_data includes:
  - transcript, word_count, final_score
  - clarity_score, structure_score, relevance_score, impact_score, confidence_score
  - overall_summary, strengths, improvements, detailed_feedback
  """
  def evaluate_speech(transcript, topic_title, duration_seconds \\ nil, topic_explanation \\ nil) do
    word_count = transcript |> String.split() |> length()

    if word_count < @min_word_count do
      {:error, :too_short,
       %{
         word_count: word_count,
         min_required: @min_word_count,
         message: "Speech too short (#{word_count} words). Minimum required: #{@min_word_count} words."
       }}
    else
      do_evaluate(transcript, topic_title, word_count, duration_seconds, topic_explanation)
    end
  end

  defp do_evaluate(transcript, topic_title, word_count, duration_seconds, topic_explanation) do
    m = speech_metrics(transcript, word_count, duration_seconds)

    topic_intent =
      case topic_explanation do
        e when is_binary(e) and e != "" -> "WHAT THE TOPIC IS PROBING: #{e}\n\n"
        _ -> ""
      end

    eval_prompt = """
    You are an expert communication assessor scoring a 1-minute "Just A Minute" (JAM)
    speech by a FRESH GRADUATE speaking IMPROMPTU on a topic they did not prepare.
    Give calibrated, evidence-based, growth-oriented feedback.

    IMPORTANT: You are given the speech-to-text TRANSCRIPT plus objective delivery
    metrics. You CANNOT hear the audio — judge delivery ONLY from the transcript text
    and the metrics below. NEVER invent vocal qualities (tone, accent, volume, pronunciation).

    TOPIC: "#{topic_title}"
    #{topic_intent}OBJECTIVE METRICS (computed — treat as ground truth):
    - Words spoken: #{m.word_count}
    - Speaking duration: #{m.duration_label}
    - Speaking rate: #{m.wpm_label}  (conversational ideal ≈ 110–150 wpm; <90 = slow/hesitant, >170 = rushed)
    - Filler words (um, uh, you know, i mean, …): #{m.fillers} (#{m.filler_pct}% of words; >5% noticeably hurts fluency)

    TRANSCRIPT:
    "#{transcript}"

    SCORE EACH DIMENSION 0–100. Calibrate to a FRESH-GRADUATE IMPROMPTU bar — NOT a
    polished professional. A solid, on-topic, developed answer SHOULD land in 80–89;
    do not under-score genuinely good attempts.
      95–100 excellent — rare: fluent, vivid, tightly structured, original insight.
      80–94  good — clearly above the typical attempt: on-topic, developed, mostly fluent. TARGET for a solid answer.
      65–79  average — a normal fresh-grad attempt: on-topic but generic, loose structure, some fillers.
      45–64  below average — thin, drifting, or poorly organised.
      0–44   poor — off-topic, incoherent, OR mostly repeating the topic/instructions with no original idea.

    RANDOM / NON-SPEECH RULE (apply FIRST): if the transcript is gibberish, random
    words or tokens, keyboard-mashing, read-out IDs/hashes/numbers, or is not an
    actual spoken response to the topic, score EVERY dimension 0–5. Noise earns no
    marks no matter how many words there are.

    DEGENERATE-RESPONSE RULE (apply BEFORE scoring): if the transcript is mostly a
    restatement of the topic title/intent or the instructions, a list of keywords,
    or has NO original developed idea of the candidate's own, then score
    relevance ≤ 20, impact ≤ 15, structure ≤ 25, and cap clarity & confidence ≤ 40.

    DIMENSIONS:
    - clarity: clarity & coherence of expression (well-formed sentences, logical word choice). Factor in speaking rate and filler % from the metrics.
    - structure: a clear opening, a developed body, and a conclusion, with logical transitions.
    - relevance: engages the GIVEN topic with specific, on-point content of the candidate's own (penalise drifting, padding, or merely echoing the topic).
    - impact: brings a developed, memorable point or concrete example — said something that actually matters, not generic platitudes.
    - confidence: fluency & assertiveness evidenced by the TEXT + METRICS — few fillers, complete (non-trailing) sentences, decisive language, little hedging. Do NOT score vocal tone.

    Each "feedback" must reference something SPECIFIC from the transcript and give one concrete action.

    CALIBRATION ANCHORS (match this scale):
    A) "Online learning. Online learning is about online learning. The topic is online
       learning. Online education. So online." → relevance 12, impact 10, structure 18,
       clarity 30, confidence 22. (degenerate: echoes the topic, no original idea.)
    B) "I think social media is good and bad. It helps us connect with friends and learn
       new things. But sometimes people waste time on it. We should use it carefully and
       not too much. So social media has both sides." → relevance 72, impact 66,
       structure 68, clarity 72, confidence 68. (average: on-topic but generic, no example.)
    C) "Remote work reshaped how my generation views careers. In my final-year project our
       team was split across three cities, and we shipped on time only because we agreed on
       async stand-ups and a shared tracker. The lesson: flexibility works when paired with
       discipline. For fresh graduates, the real skill isn't avoiding the office — it's
       proving you can be trusted to deliver without one." → relevance 88, impact 86,
       structure 84, clarity 86, confidence 85. (good: on-topic, concrete example, clear arc.)

    INSTRUCTIONS:
    1. Response MUST be valid JSON only (no markdown, no extra text).
    2. Keys: "clarity", "structure", "relevance", "impact", "confidence", "overall_summary".
    3. Each of clarity/structure/relevance/impact/confidence: an object with "score" (integer 0-100) and "feedback" (a single plain string, 2-3 sentences).
    4. "overall_summary": a single plain string, 2-3 sentences — strengths + the top improvement.
    5. Do NOT output any other keys.

    Example output format:
    {
      "clarity": {"score": 82, "feedback": "Your point about async stand-ups was easy to follow; tighten one run-on sentence to keep the flow."},
      "structure": {"score": 80, "feedback": "Clear opening and a strong closing lesson — add one transition word before the conclusion."},
      "relevance": {"score": 86, "feedback": "You engaged the topic directly with a specific project example rather than generic claims."},
      "impact": {"score": 84, "feedback": "The 'trusted to deliver without an office' line lands well; a metric on what you shipped would make it sharper."},
      "confidence": {"score": 83, "feedback": "Decisive, low-filler delivery; only one hedging phrase weakened an otherwise assertive close."},
      "overall_summary": "A focused, example-driven answer with a clear arc. Add a concrete result to your anecdote to push from good to excellent."
    }
    """

    case GroqClient.ask("You are an HR communication evaluation expert.", eval_prompt,
           model: @eval_model,
           temperature: 0.1,
           response_format: %{type: "json_object"},
           reasoning_effort: "low"
         ) do
      {:ok, raw} ->
        case GroqClient.extract_json(raw) do
          {:ok, feedback} ->
            build_evaluation_result(feedback, transcript, topic_title, word_count, m)

          {:error, _reason} ->
            Logger.error("JAM | Evaluation JSON parse failed")
            {:error, "Failed to parse evaluation feedback"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Objective, deterministic delivery metrics fed to the evaluator as ground truth.
  defp speech_metrics(transcript, word_count, duration_seconds) do
    fillers = count_fillers(transcript)
    dur = if is_number(duration_seconds) and duration_seconds > 0, do: duration_seconds, else: nil
    wpm = if dur, do: round(word_count / (dur / 60)), else: nil

    %{
      word_count: word_count,
      wpm: wpm,
      fillers: fillers,
      filler_pct: if(word_count > 0, do: Float.round(fillers / word_count * 100, 1), else: 0.0),
      duration_label: if(dur, do: "#{dur} seconds", else: "unknown"),
      wpm_label: if(wpm, do: "#{wpm} words/min", else: "n/a (duration unknown)")
    }
  end

  defp count_fillers(transcript) do
    text = String.downcase(transcript)
    single = Enum.reduce(@filler_words, 0, fn w, acc -> acc + length(Regex.scan(~r/\b#{w}\b/, text)) end)
    multi = Enum.reduce(@filler_phrases, 0, fn p, acc -> acc + length(Regex.scan(~r/#{Regex.escape(p)}/, text)) end)
    single + multi
  end

  defp build_evaluation_result(feedback, transcript, _topic_title, word_count, m) do
    # The five observable rubric scores (0–100) the LLM returned.
    dim_scores =
      Map.new(@rubric_dimensions, fn dim ->
        score = (feedback[dim] || %{})["score"] |> normalize_score() |> min(100) |> max(0)
        {dim, score}
      end)

    # Derive the two AI8 indexes as weighted blends of the rubric dimensions.
    communication = weighted_index(dim_scores, @communication_map)
    adaptability = weighted_index(dim_scores, @adaptability_map)
    indexes = %{"communication" => communication, "adaptability" => adaptability}

    # Overall score = config-driven blend of the two indexes (super-admin jam
    # weights, normalized), falling back to 60/40. Restricted to whichever of
    # the two indexes the admin actually configured for the jam module.
    iw = index_weights()
    active = Map.take(indexes, Map.keys(iw))

    final_score =
      active
      |> Enum.reduce(0.0, fn {idx, score}, acc -> acc + score * Map.fetch!(iw, idx) end)
      |> round()

    # AI8 publishes only the configured indexes (both, in production).
    ai8_scores = Map.take(indexes, Map.keys(iw))

    # Strengths (>=70) vs improvements (<70), from the rubric feedback.
    {strengths, improvements} =
      Enum.reduce(@rubric_dimensions, {[], []}, fn dim, {str, imp} ->
        feedback_text = normalize_text((feedback[dim] || %{})["feedback"])

        cond do
          feedback_text == "" -> {str, imp}
          Map.fetch!(dim_scores, dim) >= 70 -> {str ++ [feedback_text], imp}
          true -> {str, imp ++ [feedback_text]}
        end
      end)

    detailed_feedback =
      Map.new(@rubric_dimensions, fn dim -> {dim, normalize_text((feedback[dim] || %{})["feedback"])} end)

    individual = Map.new(dim_scores, fn {dim, score} -> {"#{dim}_score", score} end)

    # Prefer the real recorded duration; fall back to a word-count estimate.
    speech_duration_seconds = duration_from_metrics(m) || max(1, div(word_count * 60, 130))

    result =
      %{
        "success" => true,
        "transcript" => transcript,
        "word_count" => word_count,
        "speech_duration_seconds" => speech_duration_seconds,
        "final_score" => final_score,
        "communication_index" => communication,
        "adaptability_index" => adaptability,
        "overall_summary" => normalize_summary(feedback["overall_summary"]),
        "strengths" => if(strengths == [], do: ["Good attempt! Keep practicing."], else: strengths),
        "improvements" => if(improvements == [], do: ["Try to elaborate more on your points."], else: improvements),
        "detailed_feedback" => detailed_feedback,
        "evaluation_data" => feedback,
        "ai8_scores" => ai8_scores
      }
      |> Map.merge(individual)

    {:ok, result}
  end

  # Weighted average of selected rubric dimensions → a single 0–100 index.
  defp weighted_index(dim_scores, weight_map) do
    weight_map
    |> Enum.reduce(0.0, fn {dim, w}, acc -> acc + Map.get(dim_scores, dim, 0) * w end)
    |> round()
  end

  # Overall blend weights for the two indexes, derived from the AI8 super-admin
  # config for the jam module (normalized to sum 1.0), falling back to 60/40.
  defp index_weights do
    case AI8.weight_map("jam") |> Map.take(@jam_indexes) do
      m when map_size(m) > 0 ->
        total = m |> Map.values() |> Enum.sum()
        if total > 0, do: Map.new(m, fn {k, v} -> {k, v / total} end), else: @default_index_weights

      _ ->
        @default_index_weights
    end
  end

  defp duration_from_metrics(%{duration_label: label}) do
    case Integer.parse(to_string(label)) do
      {secs, _} when secs > 0 -> secs
      _ -> nil
    end
  end

  # Groq sometimes returns varied shapes — normalize them.
  defp normalize_score(n) when is_integer(n), do: n
  defp normalize_score(n) when is_float(n), do: trunc(n)

  defp normalize_score(n) when is_binary(n) do
    case Integer.parse(n) do
      {int, _} -> int
      :error -> 5
    end
  end

  defp normalize_score(_), do: 50

  # Flattens list feedback into a single string; leaves strings as-is.
  defp normalize_text(nil), do: ""
  defp normalize_text(text) when is_binary(text), do: text

  defp normalize_text(list) when is_list(list) do
    list
    |> Enum.map(&to_string_safe/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp normalize_text(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.map(&to_string_safe/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp normalize_text(other), do: to_string_safe(other)

  defp to_string_safe(val) when is_binary(val), do: val
  defp to_string_safe(val) when is_number(val), do: to_string(val)
  defp to_string_safe(_), do: ""

  # overall_summary may be a string or a map like %{"summary" => "..."}
  defp normalize_summary(nil), do: ""
  defp normalize_summary(text) when is_binary(text), do: text
  defp normalize_summary(%{"summary" => text}) when is_binary(text), do: text
  defp normalize_summary(%{"text" => text}) when is_binary(text), do: text
  defp normalize_summary(map) when is_map(map), do: normalize_text(map)
  defp normalize_summary(other), do: normalize_text(other)

  # ============================================================================
  # FULL AUDIO PROCESSING PIPELINE
  # ============================================================================

  @doc """
  Complete audio processing: transcribe → evaluate.
  This is the main function called by the JAM context.
  Replaces Python's /jam/process-audio endpoint.
  """
  def process_audio(audio_file_path, topic_title, duration_seconds \\ nil, topic_explanation \\ nil) do
    VyaasaCampus.AI.Tracing.span("jam.process_audio", fn ->
      do_process_audio(audio_file_path, topic_title, duration_seconds, topic_explanation)
    end)
  end

  defp do_process_audio(audio_file_path, topic_title, duration_seconds, topic_explanation) do
    Logger.info("JAM | Processing audio pipeline | file=#{audio_file_path} | topic=#{topic_title}")

    with {:ok, transcript} <- transcribe_audio(audio_file_path),
         {:ok, transcript} <- validate_transcript(transcript) do
      case evaluate_speech(transcript, topic_title, duration_seconds, topic_explanation) do
        {:ok, result} -> {:ok, result}
        {:error, :too_short, info} -> {:error, info}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Process audio from binary data (for direct upload from LiveView).
  """
  def process_audio_data(
        audio_binary,
        topic_title,
        filename \\ "recording.webm",
        duration_seconds \\ nil,
        topic_explanation \\ nil
      ) do
    VyaasaCampus.AI.Tracing.span("jam.process_audio", fn ->
      do_process_audio_data(audio_binary, topic_title, filename, duration_seconds, topic_explanation)
    end)
  end

  defp do_process_audio_data(audio_binary, topic_title, filename, duration_seconds, topic_explanation) do
    Logger.info("JAM | Processing audio data pipeline | size=#{byte_size(audio_binary)} | topic=#{topic_title}")

    with {:ok, transcript} <- transcribe_audio_data(audio_binary, filename),
         {:ok, transcript} <- validate_transcript(transcript) do
      case evaluate_speech(transcript, topic_title, duration_seconds, topic_explanation) do
        {:ok, result} -> {:ok, result}
        {:error, :too_short, info} -> {:error, info}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp validate_transcript(transcript) do
    if String.trim(transcript) != "" do
      {:ok, String.trim(transcript)}
    else
      {:error, "No speech detected in audio"}
    end
  end

  # TTS: generate audio via Groq, return base64 or nil on failure
  defp generate_tts_audio(text) do
    case GroqClient.text_to_speech(text) do
      {:ok, base64_audio} ->
        base64_audio

      {:error, reason} ->
        Logger.warning("JAM | TTS generation failed, falling back to browser speech: #{inspect(reason)}")
        nil
    end
  end

  defp clean_topic_title(raw) do
    raw
    |> String.trim()
    |> String.replace(~r/^\*+|\*+$/, "")
    |> String.replace(~r/^#+\s*/, "")
    |> String.replace(~r/^Topic:\s*/i, "")
    |> String.trim("\"")
    |> String.trim("'")
    |> String.trim()
  end
end