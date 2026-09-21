defmodule VyaasaCampus.AI.GroqClient do
  @moduledoc """
  HTTP client for the Groq API (OpenAI-compatible).
  Supports chat completions and audio transcription (Whisper).

  Production features:
  - Rate limiting via GroqRateLimiter (token bucket + queue)
  - Connection pooling via named Finch pool
  - Automatic retry with exponential backoff on 429/503
  - Graceful degradation when overloaded
  """

  alias VyaasaCampus.AI.GroqRateLimiter

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @base_url "https://api.groq.com/openai/v1"
  # llama-3.3-70b-versatile and llama-3.1-8b-instant were both removed from
  # Groq's catalog (shutdown 2026-08-16); Groq's own migration table maps
  # them to openai/gpt-oss-120b and openai/gpt-oss-20b respectively. Both
  # replacements are reasoning models — callers relying on these defaults
  # for free-text (non-JSON-mode) output must append "/no_think" to the
  # prompt and run the response through strip_reasoning/1 before parsing,
  # the same way lib/vyaasa_campus/ai/interview/interviewer.ex already does
  # for its own explicit gpt-oss-120b call. JAM's topic generation
  # (generate_topic/change_topic/explain_topic) is the one caller of the
  # chat default and has this handling; see jam_engine.ex.
  @default_chat_model "openai/gpt-oss-20b"
  @default_fast_model "openai/gpt-oss-20b"
  @default_whisper_model "whisper-large-v3-turbo"

  defp api_key do
    Application.get_env(:vyaasa_campus, :groq_api_key) ||
      raise "GROQ_API_KEY not configured. Set it in your environment."
  end

  defp headers do
    [
      {"authorization", "Bearer #{api_key()}"},
      {"content-type", "application/json"}
    ]
  end

  defp req_opts(extra) do
    Keyword.merge([finch: VyaasaCampus.Finch], extra)
  end

  # ============================================================================
  # CHAT COMPLETIONS
  # ============================================================================

  @doc """
  Send a chat completion request to Groq.

  ## Options
    * `:model` - Model name (default: "openai/gpt-oss-20b")
    * `:temperature` - Sampling temperature (default: 0.5)
    * `:max_tokens` - Max tokens in response
    * `:response_format` - e.g. %{"type" => "json_object"}
    * `:reasoning_effort` - gpt-oss models only: "low" | "medium" | "high"
      (Groq default is "medium", which burns real latency on chain-of-thought
      tokens before the answer even lands — pass "low" for anything where
      that reasoning isn't earning its cost)
    * `:timeout` - Request timeout in ms (default: 60_000)
    * `:max_retries` - Number of retries on failure (default: 3)
  """
  def chat(messages, opts \\ []) when is_list(messages) do
    model = Keyword.get(opts, :model, @default_chat_model)
    temperature = Keyword.get(opts, :temperature, 0.5)
    timeout = Keyword.get(opts, :timeout, 60_000)
    max_retries = Keyword.get(opts, :max_retries, 3)

    body = %{model: model, messages: messages, temperature: temperature}
    body = if opts[:max_tokens], do: Map.put(body, :max_tokens, opts[:max_tokens]), else: body
    body = if opts[:response_format], do: Map.put(body, :response_format, opts[:response_format]), else: body
    body = if opts[:top_p], do: Map.put(body, :top_p, opts[:top_p]), else: body
    body = if opts[:seed], do: Map.put(body, :seed, opts[:seed]), else: body
    body = if opts[:reasoning_effort], do: Map.put(body, :reasoning_effort, opts[:reasoning_effort]), else: body

    span_attrs = %{
      "gen_ai.operation.name" => "chat",
      "gen_ai.request.model" => model,
      "gen_ai.request.temperature" => temperature,
      "gen_ai.request.max_tokens" => opts[:max_tokens],
      "gen_ai.prompt" => Jason.encode!(messages)
    }

    traced("groq.chat", span_attrs, fn ->
      with_rate_limit(timeout, fn ->
        do_chat_with_retry(body, timeout, max_retries, 0)
      end)
    end)
  end

  @doc "Single-turn chat. Returns {:ok, text} or {:error, reason}."
  def ask(system_prompt, user_message, opts \\ []) do
    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_message}
    ]

    case chat(messages, opts) do
      {:ok, %{"content" => content}} -> {:ok, content}
      {:ok, result} -> {:ok, result}
      error -> error
    end
  end

  @doc "Quick chat using the fast model (openai/gpt-oss-20b)."
  def ask_fast(system_prompt, user_message, opts \\ []) do
    ask(system_prompt, user_message, Keyword.put(opts, :model, @default_fast_model))
  end

  # ============================================================================
  # AUDIO TRANSCRIPTION (Whisper)
  # ============================================================================

  @doc """
  Transcribe audio using Groq's Whisper API.
  Returns {:ok, transcript_text} or {:error, reason}.

  Pass `:thread_id` (the assessment session id) so the span joins that
  session's Opik thread even when called from a process other than the one
  that ran the session's `Tracing.span/3` (e.g. a LiveView Task).
  """
  def transcribe_audio(audio_data, opts \\ []) when is_binary(audio_data) do
    model = Keyword.get(opts, :model, @default_whisper_model)
    language = Keyword.get(opts, :language, "en")
    temperature = Keyword.get(opts, :temperature, 0.0)
    timeout = Keyword.get(opts, :timeout, 60_000)
    max_retries = Keyword.get(opts, :max_retries, 3)
    filename = Keyword.get(opts, :filename, "audio.wav")

    form_data = [
      {:file, {audio_data, filename: filename, content_type: audio_content_type(filename)}},
      {:model, model},
      {:language, language},
      {:temperature, to_string(temperature)},
      {:response_format, "json"}
    ]

    Logger.info("GROQ | Transcribing audio | model=#{model} | size=#{byte_size(audio_data)} bytes")

    span_attrs = %{
      "gen_ai.operation.name" => "transcription",
      "gen_ai.request.model" => model,
      "groq.audio.bytes" => byte_size(audio_data),
      "groq.audio.language" => language,
      "thread_id" => opts[:thread_id]
    }

    traced("groq.transcribe", span_attrs, fn ->
      with_rate_limit(timeout, fn ->
        do_transcribe_with_retry(form_data, timeout, max_retries, 0)
      end)
    end)
  end

  # Transcription retries transient failures (429/503/timeout) just like chat —
  # a single Whisper hiccup must not abort the whole assessment.
  defp do_transcribe_with_retry(_form, _timeout, max_retries, attempt) when attempt >= max_retries do
    {:error, "Transcription failed: max retries (#{max_retries}) exceeded"}
  end

  defp do_transcribe_with_retry(form_data, timeout, max_retries, attempt) do
    url = "#{@base_url}/audio/transcriptions"

    case Req.post(url,
           req_opts(
             headers: [{"authorization", "Bearer #{api_key()}"}],
             form_multipart: form_data,
             receive_timeout: timeout
           )
         ) do
      {:ok, %Req.Response{status: 200, body: %{"text" => text}}} ->
        Logger.info("GROQ | Transcription complete | length=#{String.length(text)}")
        set_span_attrs(%{"gen_ai.completion" => String.trim(text), "groq.attempts" => attempt + 1})
        {:ok, String.trim(text)}

      {:ok, %Req.Response{status: 429, headers: resp_headers}} ->
        retry_after = parse_retry_after(resp_headers)
        GroqRateLimiter.pause(retry_after)
        wait_ms = retry_delay(attempt)
        Logger.warning("GROQ | Transcription rate limited | pausing #{retry_after}ms, retrying in #{wait_ms}ms")
        Process.sleep(wait_ms)
        do_transcribe_with_retry(form_data, timeout, max_retries, attempt + 1)

      {:ok, %Req.Response{status: 503}} ->
        wait_ms = retry_delay(attempt)
        Logger.warning("GROQ | Transcription service unavailable | retrying in #{wait_ms}ms")
        Process.sleep(wait_ms)
        do_transcribe_with_retry(form_data, timeout, max_retries, attempt + 1)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("GROQ | Transcription failed | status=#{status}")
        {:error, "Groq API returned #{status}: #{inspect(body)}"}

      # Transient transport errors — including :closed, where Groq (or the pool)
      # dropped a keep-alive connection mid-upload. A retry gets a fresh
      # connection and almost always succeeds, so don't fail the answer on it.
      {:error, %Req.TransportError{reason: reason}}
      when reason in [:timeout, :closed, :econnreset, :econnrefused] ->
        if attempt + 1 < max_retries do
          wait_ms = retry_delay(attempt)
          Logger.warning(
            "GROQ | Transcription transport error #{inspect(reason)} | retrying in #{wait_ms}ms | attempt=#{attempt + 1}"
          )

          Process.sleep(wait_ms)
          do_transcribe_with_retry(form_data, timeout, max_retries, attempt + 1)
        else
          {:error, reason}
        end

      {:error, reason} ->
        Logger.error("GROQ | Transcription request failed | reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Transcribe audio from a file path."
  def transcribe_file(file_path, opts \\ []) do
    case File.read(file_path) do
      {:ok, data} ->
        transcribe_audio(data, Keyword.put(opts, :filename, Path.basename(file_path)))

      {:error, reason} ->
        {:error, "Failed to read file: #{reason}"}
    end
  end

  # ============================================================================
  # TEXT-TO-SPEECH (Groq Orpheus TTS)
  # ============================================================================

  @default_tts_model "canopylabs/orpheus-v1-english"
  @default_tts_voice "autumn"

  @doc """
  Generate speech audio from text using Groq TTS API.
  Returns {:ok, base64_wav_string} or {:error, reason}.

  ## Options
    * `:model` - TTS model (default: "playai/tts-arabic-v2.0")
    * `:voice` - Voice name (default: "Fritz-PlayAI")
    * `:response_format` - Audio format (default: "wav")
    * `:timeout` - Request timeout in ms (default: 30_000)
    * `:thread_id` - Assessment session id; links this span to the session's
      Opik thread when called outside the session's own process
  """
  def text_to_speech(text, opts \\ []) when is_binary(text) do
    model = Keyword.get(opts, :model, @default_tts_model)
    voice = Keyword.get(opts, :voice, @default_tts_voice)
    response_format = Keyword.get(opts, :response_format, "wav")
    timeout = Keyword.get(opts, :timeout, 30_000)

    url = "#{@base_url}/audio/speech"

    body = %{
      model: model,
      voice: voice,
      input: text,
      response_format: response_format
    }

    Logger.info("GROQ | TTS request | model=#{model} | voice=#{voice} | text_length=#{String.length(text)}")

    span_attrs = %{
      "gen_ai.operation.name" => "text_to_speech",
      "gen_ai.request.model" => model,
      "gen_ai.prompt" => text,
      "groq.tts.voice" => voice,
      "thread_id" => opts[:thread_id]
    }

    traced("groq.text_to_speech", span_attrs, fn ->
      with_rate_limit(timeout, fn ->
        case Req.post(url,
               req_opts(
                 headers: headers(),
                 json: body,
                 receive_timeout: timeout
               )
             ) do
          {:ok, %Req.Response{status: 200, body: audio_bytes}} when is_binary(audio_bytes) and byte_size(audio_bytes) > 0 ->
            encoded = Base.encode64(audio_bytes)
            Logger.info("GROQ | TTS complete | audio_size=#{byte_size(audio_bytes)} bytes")
            set_span_attrs(%{"groq.audio.bytes" => byte_size(audio_bytes)})
            {:ok, encoded}

          {:ok, %Req.Response{status: 200, body: body}} ->
            Logger.error("GROQ | TTS returned empty audio")
            {:error, "Empty audio returned from TTS"}

          {:ok, %Req.Response{status: 429, headers: resp_headers}} ->
            retry_after = parse_retry_after(resp_headers)
            GroqRateLimiter.pause(retry_after)
            {:error, :rate_limited}

          {:ok, %Req.Response{status: status, body: body}} ->
            Logger.error(
              "GROQ | TTS failed | status=#{status} | body=#{inspect(tts_error_body(body), printable_limit: 500)}"
            )

            {:error, "Groq TTS returned #{status}"}

          {:error, reason} ->
            Logger.error("GROQ | TTS request failed | reason=#{inspect(reason)}")
            {:error, reason}
        end
      end)
    end)
  end

  # When `into: :binary` is used, non-200 error bodies arrive as raw bytes
  # instead of decoded JSON. Try to decode so the log shows Groq's error message.
  defp tts_error_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> body
    end
  end

  defp tts_error_body(body), do: body

  # ============================================================================
  # JSON EXTRACTION HELPER
  # ============================================================================

  @doc "Extract and parse JSON from LLM response text."
  @doc """
  Strip a reasoning model's `<think>…</think>` block (qwen3 et al.).

  Port of the reference `_strip_thinking`: if real content follows `</think>`,
  that is the answer; otherwise strip the block; if nothing remains (the whole
  answer was inside the block), return the raw text so parsers still have input.
  """
  def strip_reasoning(text) when is_binary(text) do
    if String.contains?(text, "</think>") do
      after_think = text |> String.split("</think>") |> List.last() |> String.trim()
      if after_think != "", do: after_think, else: do_strip_think(text)
    else
      do_strip_think(text)
    end
  end

  def strip_reasoning(other), do: other

  defp do_strip_think(text) do
    cleaned = Regex.replace(~r/<think>.*?<\/think>/s, text, "") |> String.trim()
    if cleaned != "", do: cleaned, else: String.trim(text)
  end

  def extract_json(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, _} ->
        json_str =
          case Regex.run(~r/```(?:json)?\s*\n?(.*?)\n?\s*```/s, text) do
            [_, captured] -> captured
            nil ->
              case Regex.run(~r/\{.*\}/s, text) do
                [captured] -> captured
                nil -> nil
              end
          end

        if json_str do
          case Jason.decode(json_str) do
            {:ok, parsed} -> {:ok, parsed}
            {:error, reason} -> {:error, "JSON parse error: #{inspect(reason)}"}
          end
        else
          {:error, "No JSON found in response"}
        end
    end
  end

  # ============================================================================
  # RATE LIMITING WRAPPER
  # ============================================================================

  defp with_rate_limit(timeout, fun) do
    case GroqRateLimiter.acquire(timeout) do
      :ok ->
        try do
          fun.()
        after
          GroqRateLimiter.release()
        end

      {:error, :queue_timeout} ->
        Logger.warning("GROQ | Request queued too long — dropped")
        {:error, :groq_overloaded}

      {:error, :queue_full} ->
        Logger.warning("GROQ | Request queue full — rejected")
        {:error, :groq_overloaded}
    end
  end

  # ============================================================================
  # TRACING (OpenTelemetry → Opik)
  # ============================================================================

  # Runs `fun` inside a client span tagged with GenAI semantic-convention
  # attributes, which Opik maps onto the span's model, usage, input and output.
  # The span covers rate-limit queueing and all retries; it is marked errored on
  # an {:error, _} result or a raise.
  defp traced(name, attrs, fun) do
    Tracer.with_span name, %{kind: :client} do
      # An explicit thread_id (from opts) wins over the process-local one, so
      # calls made from a different process still land in the session's thread.
      thread_id =
        case attrs["thread_id"] || VyaasaCampus.AI.Tracing.thread_id() do
          nil -> nil
          id -> to_string(id)
        end

      set_span_attrs(Map.merge(attrs, %{"gen_ai.system" => "groq", "thread_id" => thread_id}))
      # Filter labels (student_id / module / tenant) — see Tracing.put_metadata/1.
      set_span_attrs(VyaasaCampus.AI.Tracing.metadata_attributes())

      try do
        result = fun.()

        with {:error, reason} <- result do
          Tracer.set_status(OpenTelemetry.status(:error, inspect(reason)))
        end

        result
      rescue
        e ->
          OpenTelemetry.Span.record_exception(Tracer.current_span_ctx(), e, __STACKTRACE__, [])
          Tracer.set_status(OpenTelemetry.status(:error, Exception.message(e)))
          reraise e, __STACKTRACE__
      end
    end
  end

  # nil is not a valid OTel attribute value, so optional fields are dropped.
  defp set_span_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> Tracer.set_attributes()
  end

  # ============================================================================
  # CHAT WITH RETRY
  # ============================================================================

  defp do_chat_with_retry(_body, _timeout, max_retries, attempt) when attempt >= max_retries do
    {:error, "Max retries (#{max_retries}) exceeded"}
  end

  defp do_chat_with_retry(body, timeout, max_retries, attempt) do
    url = "#{@base_url}/chat/completions"

    Logger.info("GROQ | Chat request | model=#{body.model} | attempt=#{attempt + 1}/#{max_retries}")

    case Req.post(url,
           req_opts(
             headers: headers(),
             json: body,
             receive_timeout: timeout
           )
         ) do
      {:ok, %Req.Response{status: 200, body: %{"choices" => [%{"message" => message} | _]} = resp_body}} ->
        Logger.info("GROQ | Chat complete | model=#{body.model}")
        usage = resp_body["usage"] || %{}

        set_span_attrs(%{
          "gen_ai.completion" => Jason.encode!([message]),
          "gen_ai.response.model" => resp_body["model"],
          "gen_ai.response.id" => resp_body["id"],
          "gen_ai.usage.input_tokens" => usage["prompt_tokens"],
          "gen_ai.usage.output_tokens" => usage["completion_tokens"],
          "gen_ai.usage.total_tokens" => usage["total_tokens"],
          "groq.attempts" => attempt + 1
        })

        {:ok, message}

      {:ok, %Req.Response{status: 429, headers: resp_headers}} ->
        retry_after = parse_retry_after(resp_headers)
        GroqRateLimiter.pause(retry_after)
        wait_ms = retry_delay(attempt)
        Logger.warning("GROQ | Rate limited | pausing #{retry_after}ms, retrying in #{wait_ms}ms")
        Process.sleep(wait_ms)
        do_chat_with_retry(body, timeout, max_retries, attempt + 1)

      {:ok, %Req.Response{status: 503}} ->
        wait_ms = retry_delay(attempt)
        Logger.warning("GROQ | Service unavailable | retrying in #{wait_ms}ms")
        Process.sleep(wait_ms)
        do_chat_with_retry(body, timeout, max_retries, attempt + 1)

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.error("GROQ | Chat failed | status=#{status} | body=#{inspect(resp_body)}")
        {:error, "Groq API returned #{status}"}

      {:error, %Req.TransportError{reason: :timeout}} ->
        if attempt + 1 < max_retries do
          Logger.warning("GROQ | Timeout | retrying | attempt=#{attempt + 1}")
          do_chat_with_retry(body, timeout, max_retries, attempt + 1)
        else
          {:error, :timeout}
        end

      {:error, reason} ->
        Logger.error("GROQ | Request failed | reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  defp retry_delay(attempt), do: trunc(:math.pow(2, attempt) * 1000)

  # Req returns headers as a map (with list values per RFC) on recent versions
  # and as a list of tuples on older ones. Handle both shapes.
  defp parse_retry_after(headers) do
    raw =
      cond do
        is_map(headers) ->
          case Map.get(headers, "retry-after") do
            [v | _] -> v
            v when is_binary(v) -> v
            _ -> nil
          end

        is_list(headers) ->
          case List.keyfind(headers, "retry-after", 0) do
            {_, v} when is_binary(v) -> v
            {_, [v | _]} -> v
            _ -> nil
          end

        true ->
          nil
      end

    case raw && Integer.parse(raw) do
      {seconds, _} -> seconds * 1000
      _ -> 5_000
    end
  end

  defp audio_content_type(filename) do
    case Path.extname(filename) do
      ".wav" -> "audio/wav"
      ".mp3" -> "audio/mpeg"
      ".webm" -> "audio/webm"
      ".ogg" -> "audio/ogg"
      ".m4a" -> "audio/m4a"
      _ -> "audio/wav"
    end
  end
end