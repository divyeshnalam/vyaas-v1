defmodule VyaasaCampusWeb.Student.BehavioralLive do
  @moduledoc """
  LiveView for the behavioral assessment.
  Uses the native Elixir behavioral engine — no Python service needed.

  Session state is held in socket assigns (:session_state).
  All AI calls run in background Tasks and results are sent back via messages.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.{Behavioral, StudentAts}

  import VyaasaCampusWeb.Components.UI, only: [icon: 1, error_card: 1]
  import VyaasaCampusWeb.Components.Student.MicGate
  import VyaasaCampusWeb.Components.Student.VoiceTranscript

  require Logger

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    current_user = socket.assigns[:current_user]

    case current_user do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Authentication required")
         |> redirect(to: "/auth/tenant/#{tenant_alias}/login")}

      user ->
        tenant_schema = get_tenant_schema(tenant_alias)

        # Opik filter labels for every trace this LiveView (and its Tasks) emits.
        if connected?(socket),
          do: VyaasaCampus.AI.Tracing.put_metadata(%{student_id: user.id, module: "behavioral", tenant: tenant_schema})

        ats_fields = StudentAts.get_student_ats_fields(user.id, tenant_schema)

        user_info = %{
          name: "#{user.first_name} #{user.last_name}",
          role: "Student",
          email: user.email,
          profile_picture_url: ats_fields[:profile_picture_url]
        }

        socket =
          socket
          |> assign(:tenant_alias, tenant_alias)
          |> assign(:tenant_schema, tenant_schema)
          |> assign(:current_scope, :student)
          |> assign(:user_info, user_info)
          |> assign(:page_title, "Behavioral Assessment")
          |> assign(:session_id, nil)
          |> assign(:session_state, nil)
          |> assign(:phase, :loading)
          |> assign(:messages, [])
          |> assign(:scenario_options, nil)
          |> assign(:chosen_scenario, nil)
          |> assign(:active_question, nil)
          |> assign(:pending_phase, nil)
          |> assign(:scenarios_completed, 0)
          |> assign(:report, nil)
          |> assign(:loading?, true)
          |> assign(:error_message, nil)
          |> assign(:error_title, "Something went wrong")
          |> assign(:show_star_dialog, false)
          |> assign(:response_mode, "text")
          |> assign(:is_recording, false)
          |> assign(:transcribing, false)
          |> assign(:is_followup, false)
          # Proctoring: warn twice, then auto-finalize on the 3rd violation
          # (scores completed rounds; terminates if none are complete).
          |> assign(:require_fullscreen, true)
          |> assign(:violation_count, 0)
          |> assign(:violation_limit, 3)
          |> assign(:mic_grace_until, now_ms())
          |> assign(:show_integrity_warning, false)
          |> assign(:integrity_message, nil)
          |> mount_mic_gate()

        if connected?(socket) do
          case Behavioral.get_latest_assessment(user.id, tenant_schema) do
            %{status: "completed", raw_response_json: raw} = _assessment
            when is_map(raw) and raw != %{} ->
              send(self(), {:load_previous_result, raw})

            _ ->
              send(self(), {:start_session, user.id})
          end
        end

        {:ok, socket}
    end
  end

  # ------------------------------------------------------------------
  # Info handlers (native engine — no Python/PubSub)
  # ------------------------------------------------------------------

  @impl true
  def handle_info({:load_previous_result, raw_response_json}, socket) do
    try do
      # The engine now persists reports in the native nested shape
      # (`raw_response_json["report"]["ratings"][k]["score"]`). Old records
      # from the Python service also lived under `"report"`. Anything else
      # is legacy and we wrap it.
      report =
        cond do
          is_map(raw_response_json) and is_map(raw_response_json["report"]) ->
            raw_response_json

          is_map(raw_response_json) ->
            %{"report" => raw_response_json}

          true ->
            %{"report" => %{}}
        end

      {:noreply,
       socket
       |> assign(:report, report)
       |> assign(:phase, :completed)
       |> assign(:scenarios_completed, 2)
       |> assign(:loading?, false)}
    rescue
      e ->
        Logger.error("Failed to load previous result: #{Exception.message(e)}")
        # Fall through to starting a new session
        send(self(), {:start_session, socket.assigns.current_user.id})
        {:noreply, socket}
    end
  end

  def handle_info({:start_session, student_id}, socket) do
    try do
      tenant_schema = socket.assigns.tenant_schema
      tenant_id = socket.assigns.current_user.tenant_id

      case VyaasaCampus.Contexts.AttemptGuard.check(student_id, :behavioral, tenant_id, tenant_schema) do
        {:error, :attempt_limit_reached, _details} ->
          {:noreply,
           show_retry_error(
             socket,
             "Out of attempts",
             "You've used all your available assessment attempts. Please contact your college admin to request more."
           )}

        :ok ->
          full_name = socket.assigns.user_info.name

          case Behavioral.start_session(student_id, full_name) do
            {:ok, %{session_id: session_id, session_state: session_state, response: response}} ->
              case Behavioral.create_assessment(student_id, tenant_id, session_id, tenant_schema) do
                {:ok, _record} ->
                  Logger.info("Behavioral assessment DB record created | session=#{session_id}")

                {:error, :attempt_limit_reached, details} ->
                  Logger.warning(
                    "Behavioral attempt limit reached between check and create: #{inspect(details)}"
                  )

                {:error, changeset} ->
                  Logger.warning("Failed to create behavioral DB record: #{inspect(changeset.errors)}")
              end

              {:noreply, apply_engine_response(socket, session_id, session_state, response)}

            {:error, reason} ->
              Logger.error("Behavioral start_session failed: #{inspect(reason)}")

              {:noreply,
               show_retry_error(
                 socket,
                 "Something went wrong",
                 "Failed to start the assessment. Please try again."
               )}
          end
      end
    rescue
      e ->
        Logger.error(
          "Behavioral start_session crashed: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
        )

        {:noreply,
         show_retry_error(socket, "Something went wrong", "Something went wrong. Please try again.")}
    catch
      kind, reason ->
        Logger.error(
          "Behavioral start_session caught #{kind}: #{inspect(reason)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
        )

        {:noreply,
         show_retry_error(socket, "Something went wrong", "Something went wrong. Please try again.")}
    end
  end

  # Async engine result from Task
  def handle_info({:engine_result, {:ok, new_state, response}}, socket) do
    {:noreply, apply_engine_response(socket, socket.assigns.session_id, new_state, response)}
  end

  def handle_info({:engine_result, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:loading?, false)
     |> assign(:error_message, "Assessment error: #{inspect(reason)}")}
  end

  # Proctoring auto-finalize with no completed rounds → terminate, no score.
  def handle_info({:engine_result, {:terminated, _state}}, socket) do
    Behavioral.update_assessment_status(
      socket.assigns.session_id,
      "terminated",
      socket.assigns.tenant_schema
    )

    {:noreply, socket |> assign(:phase, :terminated) |> assign(:loading?, false)}
  end

  # TTS audio ready — reveal the held scenario + play (drop if a newer prompt started).
  def handle_info({:tts_ready, gen, audio_base64}, socket) do
    if gen == socket.assigns[:tts_gen] do
      {:noreply,
       socket
       |> reveal_behavioral()
       |> push_event("play_audio", %{audio_data: audio_base64, audio_type: "wav", audio_key: "behavioral"})}
    else
      {:noreply, socket}
    end
  end

  # TTS failed — reveal + fall back to browser speech (drop if stale).
  def handle_info({:tts_fallback, gen, text}, socket) do
    if gen == socket.assigns[:tts_gen] do
      {:noreply,
       socket
       |> reveal_behavioral()
       |> push_event("speak_text", %{text: text, audio_key: "behavioral"})}
    else
      {:noreply, socket}
    end
  end

  # Safety net: reveal a held scenario even if its narration never arrives.
  def handle_info({:reveal_behavioral, gen}, socket) do
    if gen == socket.assigns[:tts_gen] do
      {:noreply, reveal_behavioral(socket)}
    else
      {:noreply, socket}
    end
  end

  # Voice answer transcribed — switch to text mode and drop the text into the
  # editable answer box for review before submitting.
  def handle_info({:transcription_ready, {:ok, text}}, socket) do
    text = String.trim(text || "")

    socket =
      socket
      |> assign(:transcribing, false)
      |> assign(:response_mode, "text")

    if text == "" do
      {:noreply, put_flash(socket, :error, "We couldn't hear anything — please try recording again.")}
    else
      {:noreply, push_event(socket, "set_input_text", %{text: text})}
    end
  end

  def handle_info({:transcription_ready, {:error, _reason}}, socket) do
    {:noreply,
     socket
     |> assign(:transcribing, false)
     |> put_flash(:error, "Transcription failed. Please try again or type your answer.")}
  end

  # Catch-all: prevent unhandled messages from crashing the LiveView
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ------------------------------------------------------------------
  # Event handlers
  # ------------------------------------------------------------------

  # The instructions screen's "Start Assessment". Same engine call as `proceed`,
  # but mic-gated: this is the last windowed screen, and every screen after it
  # runs in full screen where the browser refuses to show a permission prompt.
  @impl true
  def handle_event("start_assessment", _params, socket) do
    case require_mic(socket, "start_assessment") do
      {:gated, socket} -> {:noreply, socket}
      {:ok, socket} -> handle_event("proceed", %{}, socket)
    end
  end

  @impl true
  def handle_event("proceed", _params, socket) do
    socket =
      socket
      |> assign(:loading?, true)
      |> assign(:error_message, nil)

    run_engine_async(socket, fn state ->
      Behavioral.send_message(state, "Proceed")
    end)

    {:noreply, socket}
  end

  def handle_event("choose_scenario", %{"index" => index_str}, socket) do
    choice = String.to_integer(index_str)

    socket =
      socket
      |> assign(:chosen_scenario, choice)
      |> assign(:loading?, true)
      |> assign(:error_message, nil)

    run_engine_async(socket, fn state ->
      Behavioral.choose_scenario(state, choice)
    end)

    {:noreply, socket}
  end

  def handle_event("submit_scenario", %{"response" => response_text}, socket) do
    trimmed = String.trim(response_text)

    cond do
      trimmed == "" ->
        {:noreply, assign(socket, :error_message, "Please enter a response before submitting.")}

      true ->
        chosen = socket.assigns.chosen_scenario
        scenario_opts = socket.assigns.scenario_options || []
        question = Enum.at(scenario_opts, (chosen || 1) - 1, %{})["question"] || ""

        socket =
          socket
          |> assign(
            :messages,
            socket.assigns.messages ++
              [{:user, "**Scenario #{chosen}:** #{question}\n\nMy response: #{trimmed}"}]
          )
          |> assign(:phase, :fetching_report)
          |> assign(:loading?, true)
          |> assign(:error_message, nil)
          |> assign(:scenario_options, nil)

        run_engine_async(socket, fn state ->
          Behavioral.submit_answer(state, trimmed)
        end)

        {:noreply, socket}
    end
  end

  def handle_event("submit_scenario", _params, socket), do: {:noreply, socket}

  # Runs the engine off the LiveView process so long LLM calls don't block UI.
  defp run_engine_async(socket, fun) when is_function(fun, 1) do
    session_state = socket.assigns.session_state
    lv_pid = self()

    Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
      result = fun.(session_state)
      send(lv_pid, {:engine_result, result})
    end)

    :ok
  end

  def handle_event("back_to_dashboard", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/dashboard")}
  end

  def handle_event("resend_report", _params, socket) do
    schema = socket.assigns.tenant_schema

    case socket.assigns[:current_user] && Behavioral.get_latest_assessment(socket.assigns.current_user.id, schema) do
      %{id: id} ->
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:behavioral, id, schema)
        {:noreply, put_flash(socket, :info, "Your behavioral report is on its way to your email ✉️")}

      _ ->
        {:noreply, put_flash(socket, :error, "No completed assessment to email yet.")}
    end
  end

  def handle_event("show_coming_soon", _params, socket) do
    {:noreply, put_flash(socket, :info, "Settings coming soon!")}
  end

  def handle_event("show_star_dialog", _params, socket) do
    {:noreply, assign(socket, :show_star_dialog, true)}
  end

  def handle_event("close_star_dialog", _params, socket) do
    {:noreply, assign(socket, :show_star_dialog, false)}
  end

  def handle_event("set_response_mode", %{"mode" => "voice"}, socket) do
    # Always switch: the mic was checked when the page loaded, and voice mode
    # carries an inline notice that spells out a blocked mic. Re-probe in case
    # it was fixed since. `toggle_recording` is the hard gate.
    {:noreply, socket |> assign(:response_mode, "voice") |> probe_mic()}
  end

  def handle_event("set_response_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :response_mode, mode)}
  end

  def handle_event("mic_permission", params, socket) do
    case handle_mic_report(socket, params) do
      {:resume, event, socket} -> handle_event(event, %{}, socket)
      {:ok, socket} -> {:noreply, socket}
    end
  end

  def handle_event("mic_gate_retry", _params, socket), do: {:noreply, retry_mic(socket)}

  def handle_event("mic_gate_dismiss", _params, socket), do: {:noreply, close_mic_gate(socket)}

  # Proctoring: record the violation, warn twice, then auto-finalize on the 3rd.
  def handle_event("integrity_violation", %{"type" => type}, socket) do
    cond do
      # Ignore focus loss while the mic is engaging — the permission/OS audio
      # popup steals focus and would otherwise cost an innocent strike.
      socket.assigns.is_recording or now_ms() < socket.assigns.mic_grace_until ->
        {:noreply, socket}

      # Enforced only once the assessment has started (answering a scenario).
      socket.assigns.phase not in [:scenario_choice, :scenario_response] ->
        {:noreply, socket}

      true ->
        count = persist_violation(socket, type)
        limit = socket.assigns.violation_limit

        socket =
          socket
          |> assign(:violation_count, count)
          |> assign(:show_integrity_warning, true)

        if count >= limit do
          # 3rd strike → close the assessment (terminated, no score) and return
          # to the dashboard.
          if is_binary(socket.assigns[:session_id]) do
            Behavioral.update_assessment_status(socket.assigns.session_id, "terminated", socket.assigns.tenant_schema)
          end

          {:noreply,
           socket
           |> put_flash(:error, "Your assessment was closed after #{limit} full-screen exits / tab switches.")
           |> redirect(to: "/student/#{socket.assigns.tenant_alias}/dashboard")}
        else
          {:noreply, assign(socket, :integrity_message, behavioral_violation_message(type, limit - count))}
        end
    end
  end

  def handle_event("dismiss_integrity_warning", _params, socket) do
    {:noreply, assign(socket, :show_integrity_warning, false)}
  end

  # ── Voice answer recording (transcribed into the text box) ─────────────────
  def handle_event("toggle_recording", _params, socket) do
    cond do
      socket.assigns.is_recording ->
        {:noreply, push_event(socket, "stop_recording", %{})}

      not mic_granted?(socket) ->
        {_tag, socket} = require_mic(socket, "toggle_recording")
        {:noreply, socket}

      true ->
        # Grace window: the mic-permission / OS audio popup steals focus and
        # would otherwise cost an integrity strike. Ignore focus loss for ~8s.
        {:noreply,
         socket
         |> assign(:mic_grace_until, now_ms() + 8_000)
         # Stop the question TTS the instant the student starts answering.
         |> push_event("stop_audio", %{})
         |> push_event("start_recording", %{})}
    end
  end

  def handle_event("recording_started", _params, socket) do
    {:noreply, assign(socket, :is_recording, true)}
  end

  def handle_event("recording_error", %{"reason" => reason} = params, socket) do
    {:noreply,
     socket
     |> assign(:is_recording, false)
     |> mic_recording_failed(params["name"])
     |> put_flash(:error, "Microphone error: #{reason}")}
  end

  # Live waveform level from the hook — not visualised here; just acknowledge so
  # the event doesn't crash the LiveView.
  def handle_event("audio_level", _params, socket), do: {:noreply, socket}

  def handle_event("audio_recorded", %{"audio_data" => audio_data} = params, socket) do
    case Base.decode64(audio_data) do
      {:ok, binary} ->
        size = byte_size(binary)
        require Logger
        Logger.info("BEHAVIORAL | audio recorded | #{size} bytes (client reported #{params["size"]})")

        # An empty/near-silent recording makes Whisper hallucinate ("Thank you"),
        # so don't send it — tell the student to record again instead.
        if size < 2_000 do
          {:noreply,
           socket
           |> assign(:is_recording, false)
           |> assign(:transcribing, false)
           |> put_flash(:error, "We didn't catch any audio — check your mic, then hold Record while you speak for a couple of seconds.")}
        else
          mime = Map.get(params, "mime_type", "audio/webm")
          filename = if String.contains?(mime, "webm"), do: "answer.webm", else: "answer.ogg"
          lv_pid = self()
          # Opik: link the Whisper span to this session's thread (the Task has no thread id of its own).
          thread_id = socket.assigns[:session_id]

          Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
            result = VyaasaCampus.AI.GroqClient.transcribe_audio(binary, filename: filename, thread_id: thread_id)
            send(lv_pid, {:transcription_ready, result})
          end)

          # Releasing the mic (and the browser's recording indicator) can briefly
          # drop full screen / blur the window just after recording — extend the
          # grace so those don't count as integrity violations.
          {:noreply,
           socket
           |> assign(:is_recording, false)
           |> assign(:transcribing, true)
           |> assign(:mic_grace_until, now_ms() + 6_000)}
        end

      :error ->
        {:noreply,
         socket
         |> assign(:is_recording, false)
         |> put_flash(:error, "Could not read the recording. Please try again.")}
    end
  end

  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Logged out successfully")
     |> redirect(to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}
  end

  def handle_event("start_new_assessment", _params, socket) do
    socket =
      socket
      |> assign(:session_id, nil)
      |> assign(:session_state, nil)
      |> assign(:messages, [])
      |> assign(:scenario_options, nil)
      |> assign(:chosen_scenario, nil)
      |> assign(:scenarios_completed, 0)
      |> assign(:loading?, true)
      |> assign(:error_message, nil)
      |> assign(:error_title, "Something went wrong")

    send(self(), {:start_session, socket.assigns.current_user.id})
    {:noreply, socket}
  end

  # ------------------------------------------------------------------
  # Engine response handling
  # ------------------------------------------------------------------

  # Failure while (re)starting a session: if a previous result is still on
  # screen (:completed), keep it visible and layer the error on top — same
  # pattern as the MCQ retry flow. Only fall back to the standalone error
  # screen when there's nothing behind it to show (e.g. very first attempt).
  defp show_retry_error(socket, title, message) do
    socket =
      socket
      |> assign(:loading?, false)
      |> assign(:error_title, title)
      |> assign(:error_message, message)

    if socket.assigns.phase == :completed do
      socket
    else
      assign(socket, :phase, :error)
    end
  end

  defp apply_engine_response(socket, session_id, session_state, response) do
    ai_reply = response["reply"]
    spoken_reply = response["spoken_reply"]
    scenario_options = response["scenario_options"]
    scenarios_completed = response["scenarios_count"] || socket.assigns.scenarios_completed
    finished = response["interview_finished"] == true
    engine_phase = response["phase"]
    report_data = response["report"]

    messages =
      if ai_reply && ai_reply != "" do
        socket.assigns.messages ++ [{:ai, ai_reply}]
      else
        socket.assigns.messages
      end

    phase = map_engine_phase(engine_phase, finished)

    # Hold a spoken scenario on the loading skeleton until its narration is ready,
    # so the scenario and its audio appear together instead of the scenario
    # sitting silent for ~5s. A safety timer (see the TTS block) reveals it even
    # if TTS is slow or fails. Non-spoken phases display immediately.
    held? = phase == :scenario_response

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:session_state, session_state)
      |> assign(:messages, messages)
      |> assign(:phase, if(held?, do: :loading, else: phase))
      |> assign(:pending_phase, if(held?, do: :scenario_response, else: nil))
      |> assign(:scenarios_completed, scenarios_completed)
      |> assign(:is_followup, response["is_followup"] == true)
      |> assign(:loading?, false)
      |> assign(:error_message, nil)

    # Cheap retry for a mic that was plugged in (or unblocked) after the
    # page-load check; no-ops once verified, and never re-prompts when denied.
    socket = if phase == :scenario_choice, do: probe_mic(socket), else: socket

    socket =
      cond do
        scenario_options && phase == :scenario_choice ->
          assign(socket, :scenario_options, scenario_options)

        phase == :scenario_response ->
          socket

        true ->
          assign(socket, :scenario_options, nil)
      end

    socket =
      cond do
        phase == :scenario_response ->
          assign(socket, :active_question, response["scenario_question"])

        phase in [:scenario_choice, :chatting] ->
          assign(socket, :active_question, nil)

        true ->
          socket
      end

    socket =
      if finished and report_data do
        # Persist the report in the background — one save, new nested ratings shape.
        Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
          Behavioral.save_report(
            session_id,
            %{"report" => report_data, "raw_report" => report_data["raw_text"]},
            socket.assigns.tenant_schema
          )
        end)

        assign(socket, :report, %{"report" => report_data})
      else
        socket
      end

    # Speak the assistant reply via Groq TTS.
    tts_text =
      cond do
        # Picking between two scenario options — deliberately silent.
        phase == :scenario_choice ->
          nil

        # Read the scenario the student is answering. It lives in
        # `scenario_question` (also shown as @active_question), NOT in
        # reply/spoken_reply — so the old `spoken_reply || ai_reply` never
        # actually spoke the scenario (only the intro/greeting got read).
        phase == :scenario_response ->
          response["scenario_question"] || spoken_reply || ai_reply

        true ->
          spoken_reply || ai_reply
      end

    if tts_text && tts_text != "" && not finished do
      tts_pid = self()
      gen = (socket.assigns[:tts_gen] || 0) + 1

      Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
        # Opik: link the TTS span to this session's thread.
        case VyaasaCampus.AI.GroqClient.text_to_speech(tts_text, thread_id: session_id) do
          {:ok, audio_base64} -> send(tts_pid, {:tts_ready, gen, audio_base64})
          {:error, _} -> send(tts_pid, {:tts_fallback, gen, tts_text})
        end
      end)

      # Safety net: reveal a held scenario even if its narration is slow or fails.
      if socket.assigns[:pending_phase] && connected?(socket) do
        Process.send_after(self(), {:reveal_behavioral, gen}, 6_000)
      end

      # Stop any audio still reading, and bump the generation so a late TTS from
      # a previous prompt is dropped instead of played over the new one.
      socket |> assign(:tts_gen, gen) |> push_event("stop_audio", %{})
    else
      # Nothing to speak — never leave a held scenario stuck on the spinner.
      reveal_behavioral(socket)
    end
  end

  # Engine phase string → LiveView phase atom.
  defp behavioral_violation_message(type, remaining) do
    label =
      case type do
        "fullscreen_exit" -> "You left full-screen mode."
        "window_blur" -> "You switched away from the assessment window."
        _ -> "You switched tabs / left the assessment."
      end

    if remaining <= 1 do
      "#{label} Final warning — one more and your assessment ends automatically."
    else
      "#{label} This is recorded and shared with your evaluator. #{remaining} warnings left."
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp persist_violation(socket, type) do
    case socket.assigns[:session_id] do
      sid when is_binary(sid) ->
        case Behavioral.record_violation(sid, type, socket.assigns.tenant_schema) do
          {:ok, n} -> n
          _ -> socket.assigns.violation_count + 1
        end

      _ ->
        socket.assigns.violation_count + 1
    end
  end

  # Reveal a scenario that was held on the loading skeleton while its narration
  # was synthesised. No-op if nothing is pending.
  defp reveal_behavioral(socket) do
    case socket.assigns[:pending_phase] do
      nil -> socket
      target -> socket |> assign(:phase, target) |> assign(:pending_phase, nil)
    end
  end

  defp map_engine_phase(_phase, true), do: :completed
  defp map_engine_phase("greeting", _), do: :chatting
  defp map_engine_phase("presenting", _), do: :scenario_choice
  defp map_engine_phase("answering", _), do: :scenario_response
  defp map_engine_phase("probing", _), do: :scenario_response
  defp map_engine_phase("finished", _), do: :completed
  defp map_engine_phase(_, _), do: :chatting

  # Extract a 0–100 competency score from either the new nested
  # `%{"score" => int, "reasoning" => str}` shape or the legacy flat int.
  defp extract_rating_score(ratings, key) do
    case Map.get(ratings, key) do
      %{"score" => s} when is_integer(s) -> s
      %{"score" => s} when is_number(s) -> round(s)
      n when is_integer(n) -> n
      n when is_number(n) -> round(n)
      _ -> 0
    end
  end

  defp extract_reasoning_from_ratings(ratings) when is_map(ratings) do
    ratings
    |> Enum.map(fn {k, v} -> {k, normalize_reasoning_value(v)} end)
    |> Enum.into(%{})
  end

  defp extract_reasoning_from_ratings(_), do: %{}

  # Per-competency reasoning may arrive as a plain string, as the new nested
  # `%{"score" => _, "reasoning" => str}` shape, or as something unexpected.
  # Always coerce to a string so the template never tries to render a map.
  defp normalize_reasoning_value(v) when is_binary(v), do: v
  defp normalize_reasoning_value(%{"reasoning" => r}) when is_binary(r), do: r
  defp normalize_reasoning_value(%{reasoning: r}) when is_binary(r), do: r
  defp normalize_reasoning_value(_), do: ""

  # ------------------------------------------------------------------
  # Render
  # ------------------------------------------------------------------

  # Maps the internal phase + scenarios_completed to the visual 1-5 stepper
  # (2 rounds) that only moves forward, never backward.
  #
  # Step 1: Instructions
  # Step 2: Round 1
  # Step 3: Round 2
  # Step 4: Vyaasa Analyse
  # Step 5: Insights
  defp current_step(phase, scenarios_completed) do
    case phase do
      :loading -> 1
      :error -> 1
      :fetching_report -> 4
      :completed -> 5
      :chatting when scenarios_completed >= 2 -> 4
      :chatting when scenarios_completed > 0 -> scenarios_completed + 1
      :chatting -> 1
      p when p in [:scenario_choice, :scenario_response] -> scenarios_completed + 2
      _ -> 1
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :current_step, current_step(assigns.phase, assigns.scenarios_completed))
    # Full screen required only once the student is working on a scenario.
    assigns = assign(assigns, :require_fullscreen, assigns.phase in [:scenario_choice, :scenario_response, :fetching_report])

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-cream-50 flex" id="behavioral-container" phx-hook="AssessmentIntegrity"
        data-require-fullscreen={to_string(@require_fullscreen)}>
        <.mic_gate id="behavioral-mic-gate" state={@mic_permission} detail={@mic_detail} open={@mic_gate_open} checking={@mic_checking} />
        <!-- Full-screen gate: JS shows this until the student enters fullscreen -->
        <div :if={@require_fullscreen} id="fullscreen-gate" phx-update="ignore"
          class="fixed inset-0 z-100 bg-gray-900/95 flex items-center justify-center p-6 text-center">
          <div class="max-w-md">
            <.icon name="hero-lock-closed" class="w-12 h-12 text-orange-400 mx-auto mb-4" />
            <h2 class="text-xl font-bold text-white mb-2">Secure full-screen mode</h2>
            <p class="text-sm text-gray-300 mb-6">
              This is a proctored assessment that runs in full screen. Leaving full screen, switching
              tabs, or pasting text is recorded and shared with your evaluator.
            </p>
            <button id="enter-fullscreen-btn" type="button"
              class="px-6 py-3 rounded-xl bg-orange-500 hover:bg-orange-600 text-white font-semibold">
              Enter full screen &amp; begin
            </button>
            <div class="mt-4">
              <.link navigate={"/student/#{@tenant_alias}/dashboard"}
                data-confirm="Leave the assessment? Your progress won't be submitted."
                class="text-sm text-gray-400 hover:text-gray-200 underline">
                Exit assessment
              </.link>
            </div>
          </div>
        </div>

        <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar
          current_section="behavioral"
          tenant_alias={@tenant_alias}
          student_name={@user_info.name}
        />

        <div class="flex-1 flex flex-col min-w-0">
          <VyaasaCampusWeb.Components.Student.HeaderComponent.header user_info={@user_info} tenant_alias={@tenant_alias} exit_href={"/student/#{@tenant_alias}/dashboard"} />

          <div :if={@show_integrity_warning} class="bg-red-600 text-white px-6 py-3 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-exclamation-triangle" class="w-5 h-5 shrink-0" />
              <span class="text-sm font-medium">
                {@integrity_message} (Recorded {@violation_count} time{if @violation_count != 1, do: "s"}.)
              </span>
            </div>
            <button type="button" phx-click="dismiss_integrity_warning" class="text-white hover:text-red-100">
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <main class="flex-1 overflow-auto">
            <div id="audio-player" phx-hook="AudioPlayer"></div>

            <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-300 mx-auto w-full">
              <div class="flex items-start gap-3 mb-6">
                <div
                  class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
                  style="background-color: #FFE9D2;"
                >
                  <.icon name="hero-user-group" class="w-5 h-5" style="color: #B85F00;" />
                </div>
                <div>
                  <p class="text-[11px] font-semibold tracking-[0.18em] uppercase" style="color: #FF8B00;">2 Rounds · STAR Method · 5 Dimensions</p>
                  <h1 class="text-2xl font-bold text-gray-900">Situational & Behavioral Assessment</h1>
                  <p class="text-sm text-gray-500 mt-0.5">Vyaasa-generated workplace scenarios that evaluate leadership, teamwork, communication, adaptability and accountability judged on clarity & ownership, not perfection.</p>
                </div>
              </div>

              <%= if @phase != :error do %>
                <.render_progress_indicator
                  current_step={@current_step}
                  scenarios_completed={@scenarios_completed}
                  phase={@phase}
                />
              <% end %>

              <div id="page-content" phx-hook="PageTransition" class="mt-6">
                <%= case @phase do %>
                  <% :loading -> %>
                    <.render_loading_skeleton type="intro" />
                  <% :chatting -> %>
                    <.render_page_intro
                      messages={@messages}
                      loading?={@loading?}
                      error_message={@error_message}
                      scenarios_completed={@scenarios_completed}
                    />
                  <% :scenario_choice -> %>
                    <.render_page_scenario_selection
                      messages={@messages}
                      scenario_options={@scenario_options}
                      scenarios_completed={@scenarios_completed}
                    />
                  <% :scenario_response -> %>
                    <.render_page_star_response
                      chosen_scenario={@chosen_scenario}
                      scenario_options={@scenario_options}
                      active_question={@active_question}
                      error_message={@error_message}
                      scenarios_completed={@scenarios_completed}
                      response_mode={@response_mode}
                      is_recording={@is_recording}
                      transcribing={@transcribing}
                      is_followup={@is_followup}
                      mic_verified={@mic_verified}
                      mic_permission={@mic_permission}
                      mic_checking={@mic_checking}
                    />
                  <% :fetching_report -> %>
                    <.render_loading_skeleton type="report" />
                  <% :completed -> %>
                    <.render_page_results
                      report={@report}
                      tenant_alias={@tenant_alias}
                      user_info={@user_info}
                      scenarios_completed={@scenarios_completed}
                      error_message={@error_message}
                      error_title={@error_title}
                    />
                  <% :terminated -> %>
                    <div class="bg-white rounded-2xl border p-8 text-center" style="border-color: #FECACA;">
                      <div class="w-14 h-14 rounded-full bg-red-50 flex items-center justify-center mx-auto mb-4">
                        <.icon name="hero-shield-exclamation" class="w-7 h-7 text-red-500" />
                      </div>
                      <h2 class="text-xl font-bold text-gray-900 mb-2">Assessment ended</h2>
                      <p class="text-sm text-gray-500 max-w-md mx-auto mb-6">
                        Your assessment was ended after repeated integrity violations (leaving full
                        screen or switching away). No score was recorded, and this has been shared
                        with your evaluator.
                      </p>
                      <.link navigate={~p"/student/#{@tenant_alias}/dashboard"}
                        class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold"
                        style="background-color: #FF8B00;">
                        Back to dashboard
                      </.link>
                    </div>
                  <% :error -> %>
                    <.error_card
                      title={@error_title}
                      error_message={@error_message}
                      retry_event="start_new_assessment"
                      enter_fullscreen
                    />
                  <% _ -> %>
                    <.render_loading_skeleton type="intro" />
                <% end %>
              </div>
            </div>
          </main>
        </div>
      </div>

      <%= if @show_star_dialog do %>
        <.star_dialog />
      <% end %>
    </Layouts.app>
    """
  end

  defp render_progress_indicator(assigns) do
    steps = [
      %{num: 1, label: "Instructions"},
      %{num: 2, label: "Round 1"},
      %{num: 3, label: "Round 2"},
      %{num: 4, label: "Vyaasa Analyse"},
      %{num: 5, label: "Insights"}
    ]

    assigns = assign(assigns, :steps, steps)

    ~H"""
    <div class="flex items-center justify-center overflow-x-auto">
      <div class="flex items-center min-w-max">
        <%= for {step, idx} <- Enum.with_index(@steps) do %>
          <div class="flex flex-col items-center">
            <div
              class={[
                "w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold",
                cond do
                  step.num < @current_step -> "text-white"
                  step.num == @current_step -> "text-white"
                  true -> "text-gray-500 border border-gray-200 bg-cream-100"
                end
              ]}
              style={
                cond do
                  step.num < @current_step -> "background-color: #22C55E;"
                  step.num == @current_step -> "background-color: #FF8B00;"
                  true -> ""
                end
              }
            >
              <%= if step.num < @current_step, do: "✓", else: step.num %>
            </div>
            <span
              class={[
                "text-[10px] font-semibold tracking-[0.12em] uppercase mt-2 whitespace-nowrap",
                cond do
                  step.num < @current_step -> "text-gray-500"
                  step.num == @current_step -> ""
                  true -> "text-gray-400"
                end
              ]}
              style={if step.num == @current_step, do: "color: #FF8B00;", else: ""}
            >{step.label}</span>
          </div>
          <%= if idx < length(@steps) - 1 do %>
            <div class={[
              "h-0.5 w-12 sm:w-20 mx-1 -mt-5.5",
              if(step.num < @current_step, do: "bg-green-500", else: "bg-gray-200")
            ]}></div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :type, :string, default: "intro"

  defp render_loading_skeleton(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-10 text-center">
      <div class="animate-spin rounded-full h-12 w-12 border-2 border-cream-200 mx-auto mb-4" style="border-top-color: #FF8B00;"></div>
      <p class="text-sm font-medium text-gray-700">
        <%= if @type == "report", do: "Vyaasa is analysing your stories…", else: "Loading…" %>
      </p>
      <p class="text-xs text-gray-400 mt-1">Please don't refresh.</p>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :loading?, :boolean, required: true
  attr :error_message, :string, default: nil
  attr :scenarios_completed, :integer, required: true

  defp render_page_intro(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <div class="lg:col-span-2 bg-white rounded-2xl border border-gray-100 p-6">
        <span class="inline-block text-[11px] font-semibold px-2.5 py-1 rounded-full mb-3"
          style="background-color: #FFE9D2; color: #B85F00;">2 rounds · ~15 min</span>
        <h2 class="text-xl font-bold text-gray-900 mb-1">Tell two short stories. We'll listen for who you are at work.</h2>
        <p class="text-sm text-gray-500 mb-5">
          You'll complete <span class="font-semibold">2 rounds</span>. In each round you'll see <span class="font-semibold">2 workplace scenarios</span> — pick the one that feels most natural and respond using the <span class="font-semibold">STAR</span> format. After each answer we'll ask <span class="font-semibold">one quick follow-up</span>. Use voice or text.
        </p>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-2 mb-5">
          <.star_pillar letter="S" title="Situation" sub="Set the scene." />
          <.star_pillar letter="T" title="Task" sub="Your responsibility." />
          <.star_pillar letter="A" title="Action" sub="What YOU did." />
          <.star_pillar letter="R" title="Result" sub="Outcome + learning." />
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-2 mb-5">
          <.meta_card label="Time" value="5 min / response" />
          <.meta_card label="Text Limit" value="2,000 characters" />
          <.meta_card label="Voice" value="5 minutes max" />
          <.meta_card label="Format" value="STAR · voice or text" />
        </div>

        <%= if @error_message do %>
          <div class="mb-4 rounded-lg p-3 text-sm" style="background-color: #FEF2F2; color: #991B1B; border: 1px solid #FECACA;">
            {@error_message}
          </div>
        <% end %>

        <div class="flex items-center gap-3">
          <button
            type="button"
            phx-click="start_assessment"
            disabled={@loading?}
            class={[
              "inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold transition",
              if(@loading?, do: "cursor-not-allowed opacity-50", else: "")
            ]}
            style="background-color: #FF8B00;"
          >▶ Start Assessment <span class="ml-0.5">→</span></button>
          <button
            type="button"
            phx-click="show_star_dialog"
            class="inline-flex items-center gap-1.5 px-4 py-2.5 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition"
          >
            <.icon name="hero-book-open" class="w-4 h-4" /> Learn STAR Method
          </button>
        </div>
      </div>

      <div class="space-y-4">
        <div class="rounded-2xl border border-cream-200 p-4" style="background-color: #FFF1DE;">
          <div class="flex items-start gap-2 mb-1">
            <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5" style="color: #B85F00;" />
            <p class="text-sm font-semibold text-gray-800">Friendly reminder</p>
          </div>
          <p class="text-xs text-gray-600 leading-relaxed">
            Use "I" instead of "we" recruiters listen for personal ownership in your stories.
          </p>
        </div>

        <div class="bg-white rounded-2xl border border-gray-100 p-4">
          <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">Flow</p>
          <ul class="space-y-2 text-sm">
            <.flow_item number="1" label="Instructions" />
            <.flow_item number="2" label="STAR training" />
            <.flow_item number="3" label="Round 1" />
            <.flow_item number="4" label="Round 2" />
            <.flow_item number="5" label="Vyaasa evaluation" />
            <.flow_item number="6" label="Insights" />
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :letter, :string, required: true
  attr :title, :string, required: true
  attr :sub, :string, required: true

  defp star_pillar(assigns) do
    ~H"""
    <div class="bg-cream-50 rounded-xl p-3 border border-cream-200 text-center">
      <div class="w-9 h-9 rounded-full mx-auto mb-1 flex items-center justify-center text-white font-bold"
        style="background-color: #FF8B00;">{@letter}</div>
      <p class="text-xs font-semibold text-gray-900">{@title}</p>
      <p class="text-[10px] text-gray-500">{@sub}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp meta_card(assigns) do
    ~H"""
    <div class="bg-cream-50 rounded-xl p-3 border border-cream-200">
      <p class="text-[10px] uppercase tracking-wider text-gray-500 font-semibold">{@label}</p>
      <p class="text-sm font-bold text-gray-900 mt-0.5">{@value}</p>
    </div>
    """
  end

  attr :number, :string, required: true
  attr :label, :string, required: true

  defp flow_item(assigns) do
    ~H"""
    <li class="flex items-center gap-2 text-gray-700">
      <span class="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white" style="background-color: #FF8B00;">{@number}</span>
      <span>{@label}</span>
    </li>
    """
  end

  attr :messages, :list, required: true
  attr :scenario_options, :list, default: []
  attr :scenarios_completed, :integer, default: 0

  defp render_page_scenario_selection(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <div class="lg:col-span-2 bg-white rounded-2xl border border-gray-100 p-6">
        <div class="flex items-center justify-between mb-4">
          <span class="inline-block text-[11px] font-semibold px-2.5 py-1 rounded-full"
            style="background-color: #FFE9D2; color: #B85F00;">Round {@scenarios_completed + 1} of 2</span>
          <button
            phx-click="show_star_dialog"
            class="inline-flex items-center gap-1.5 text-xs text-gray-600 hover:text-gray-900 transition"
          >
            <.icon name="hero-book-open" class="w-3.5 h-3.5" /> STAR refresher
          </button>
        </div>

        <p class="text-sm text-gray-600 mb-4">Here are two scenarios. <span class="font-semibold">Choose the one</span> you would like to answer.</p>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <%= for {scenario, idx} <- Enum.with_index(@scenario_options || [], 1) do %>
            <button
              phx-click="choose_scenario"
              phx-value-index={idx}
              class="text-left bg-cream-50 rounded-xl border border-cream-200 p-4 hover:bg-[#FFF7ED] shadow-[0_2px_8px_rgba(16,24,40,0.06)] hover:shadow-[0_14px_28px_rgba(16,24,40,0.12)] hover:border-brand-300 transition-all duration-300"
              style="cursor: pointer;"
            >
              <span class="inline-block text-[10px] font-semibold px-2 py-0.5 rounded-full mb-2"
                style="background-color: #FFE9D2; color: #B85F00;">Scenario {idx}</span>
              <h3 class="text-sm font-bold text-gray-900 mb-2">{scenario_title(scenario, idx)}</h3>
              <p class="text-xs text-gray-600 leading-relaxed mb-2">{scenario["question"]}</p>
              <p class="text-[10px] font-semibold tracking-[0.12em] uppercase" style="color: #FF8B00;">
                {scenario_tags(scenario, idx)}
              </p>
            </button>
          <% end %>
        </div>
      </div>

      <div class="space-y-4">
        <div class="bg-white rounded-2xl border border-gray-100 p-4">
          <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">STAR helper</p>
          <ul class="space-y-3">
            <.star_helper_row letter="S" title="Situation" question="Where & when did this happen?" />
            <.star_helper_row letter="T" title="Task" question="What was your specific role?" />
            <.star_helper_row letter="A" title="Action" question="What did YOU choose to do?" />
            <.star_helper_row letter="R" title="Result" question="What changed because of it?" />
          </ul>
        </div>

        <div class="rounded-2xl border border-cream-200 p-4" style="background-color: #FFF1DE;">
          <div class="flex items-start gap-2 mb-1">
            <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5" style="color: #B85F00;" />
            <p class="text-sm font-semibold text-gray-800">Vyaasa tip</p>
          </div>
          <p class="text-xs text-gray-600 leading-relaxed">
            Recruiters score the <span class="font-semibold">Action</span> part most. Make YOUR specific decisions vivid.
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :letter, :string, required: true
  attr :title, :string, required: true
  attr :question, :string, required: true

  defp star_helper_row(assigns) do
    ~H"""
    <li class="flex items-start gap-3">
      <div class="w-7 h-7 rounded-full flex items-center justify-center text-white text-xs font-bold shrink-0"
        style="background-color: #FF8B00;">{@letter}</div>
      <div>
        <p class="text-xs font-semibold text-gray-900">{@title}</p>
        <p class="text-[11px] text-gray-500">{@question}</p>
      </div>
    </li>
    """
  end

  defp scenario_title(%{"title" => t}, _) when is_binary(t) and t != "", do: t

  defp scenario_title(scenario, _idx) do
    case scenario["question"] || "" do
      "" ->
        "Scenario"

      q ->
        q
        |> String.split(~r/[.?]/, parts: 2)
        |> List.first()
        |> String.trim()
        |> String.slice(0, 40)
    end
  end

  defp scenario_tags(scenario, _idx) do
    case scenario["tags"] do
      tags when is_list(tags) and tags != [] -> Enum.join(tags, " · ")
      _ -> "Behavioral · Workplace"
    end
  end

  attr :chosen_scenario, :integer, default: 1
  attr :scenario_options, :list, default: []
  attr :active_question, :string, default: nil
  attr :error_message, :string, default: nil
  attr :scenarios_completed, :integer, default: 0
  attr :response_mode, :string, default: "text"
  attr :is_recording, :boolean, default: false
  attr :transcribing, :boolean, default: false
  attr :is_followup, :boolean, default: false
  attr :mic_verified, :boolean, default: false
  attr :mic_permission, :string, default: nil
  attr :mic_checking, :boolean, default: false

  defp render_page_star_response(assigns) do
    chosen_idx = assigns.chosen_scenario || 1
    scenario_opts = assigns.scenario_options || []
    fallback = (Enum.at(scenario_opts, chosen_idx - 1) || %{})["question"] || ""
    chosen_question = assigns.active_question || fallback
    chosen_scenario_obj = Enum.at(scenario_opts, chosen_idx - 1) || %{}

    # "View Insights" only on the FINAL round's follow-up. Both rounds end in a
    # follow-up (is_followup), but only the last one leads to insights — during
    # the round-1 follow-up scenarios_completed is still 0, so it says "Continue".
    submit_label =
      if assigns.is_followup and (assigns.scenarios_completed || 0) >= 1 do
        "Submit & View Insights"
      else
        "Submit & Continue"
      end

    assigns =
      assigns
      |> assign(:chosen_question, chosen_question)
      |> assign(:chosen_title, scenario_title(chosen_scenario_obj, chosen_idx))
      |> assign(:submit_label, submit_label)

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <div class="lg:col-span-2 space-y-4">
        <div class="bg-white rounded-2xl border border-gray-100 p-6">
          <div class="flex items-center justify-between mb-4">
            <span class="inline-block text-[11px] font-semibold px-2.5 py-1 rounded-full"
              style="background-color: #FFE9D2; color: #B85F00;">
              {if @is_followup, do: "Follow-up · Round #{@scenarios_completed + 1} of 2", else: "Round #{@scenarios_completed + 1} of 2"}
            </span>
            <button
              phx-click="show_star_dialog"
              class="inline-flex items-center gap-1.5 text-xs text-gray-600 hover:text-gray-900 transition"
            >
              <.icon name="hero-book-open" class="w-3.5 h-3.5" /> STAR refresher
            </button>
          </div>

          <p :if={@is_followup} class="text-sm text-gray-600 mb-4"><span class="font-semibold">Quick follow-up</span> — answer in a sentence or two to add depth to your previous response.</p>

          <!-- Only the question being answered: the selected scenario, or the follow-up probe -->
          <div class="rounded-xl border-2 p-4" style="background-color: #FFF6EC; border-color: #FF8B00;">
            <div class="flex items-center gap-2 mb-2">
              <%= if @is_followup do %>
                <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4" style="color: #B85F00;" />
                <span class="inline-block text-[10px] font-semibold px-2 py-0.5 rounded-full" style="background-color: #FFE9D2; color: #B85F00;">Follow-up</span>
              <% else %>
                <span class="inline-block text-[10px] font-semibold px-2 py-0.5 rounded-full" style="background-color: #FFE9D2; color: #B85F00;">Scenario {@chosen_scenario}</span>
              <% end %>
            </div>
            <h3 :if={!@is_followup} class="text-sm font-bold text-gray-900 mb-1">{@chosen_title}</h3>
            <p class="text-sm font-semibold text-gray-900 leading-relaxed">{@chosen_question}</p>
          </div>
        </div>

        <form phx-submit="submit_scenario" class="bg-white rounded-2xl border border-gray-100 p-6">
          <div class="flex items-center justify-between mb-4">
            <div>
              <p class="text-[10px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-0.5">Your Response</p>
              <h3 class="text-base font-bold text-gray-900">{@chosen_title}</h3>
            </div>
            <div class="flex items-center gap-3">
              <div class="relative w-12 h-12">
                <svg class="w-12 h-12 transform -rotate-90" viewBox="0 0 40 40">
                  <circle cx="20" cy="20" r="16" fill="none" stroke="#F4ECDD" stroke-width="3" />
                  <circle cx="20" cy="20" r="16" fill="none" stroke="#FF8B00" stroke-width="3" stroke-dasharray="100" stroke-dashoffset="80" stroke-linecap="round" />
                </svg>
                <div class="absolute inset-0 flex flex-col items-center justify-center">
                  <span class="text-[11px] font-bold text-gray-900 leading-none">5</span>
                  <span class="text-[7px] uppercase tracking-wider text-gray-400 leading-none mt-0.5">MIN MAX</span>
                </div>
              </div>

              <div class="inline-flex rounded-lg p-0.5 bg-cream-100">
                <button
                  type="button"
                  phx-click="set_response_mode"
                  phx-value-mode="text"
                  class={[
                    "inline-flex items-center gap-1 px-3 py-1 rounded-md text-xs font-semibold transition",
                    if(@response_mode == "text", do: "bg-white text-gray-900 shadow", else: "text-gray-500")
                  ]}
                >
                  <.icon name="hero-document-text" class="w-3.5 h-3.5" /> Text
                </button>
                <button
                  type="button"
                  phx-click="set_response_mode"
                  phx-value-mode="voice"
                  class={[
                    "inline-flex items-center gap-1 px-3 py-1 rounded-md text-xs font-semibold transition",
                    if(@response_mode == "voice", do: "bg-white text-gray-900 shadow", else: "text-gray-500")
                  ]}
                >
                  <.icon name="hero-microphone" class="w-3.5 h-3.5" /> Voice
                </button>
              </div>
            </div>
          </div>

          <%= if @error_message do %>
            <div class="mb-3 rounded-lg p-2.5 text-xs" style="background-color: #FEF2F2; color: #991B1B; border: 1px solid #FECACA;">
              {@error_message}
            </div>
          <% end %>

          <div id="behavioral-recorder" phx-hook="AudioRecorder">
          <%= if @response_mode == "voice" do %>
            <.mic_status verified={@mic_verified} state={@mic_permission} checking={@mic_checking} />
          <% end %>
          <%= if @response_mode == "text" do %>
            <textarea
              name="response"
              rows="8"
              placeholder={"Situation — set the scene…\nTask — your role…\nAction — what YOU did…\nResult — outcome + lesson…"}
              maxlength="2000"
              class="w-full rounded-xl px-4 py-3 text-sm focus:outline-none resize-none"
              style="background-color: #FAF6EE; border: 1px solid #F4ECDD; color: #1F2937;"
              id="star-response"
              phx-hook="WordCounter"
            ></textarea>
            <p class="text-[10px] text-gray-400 mt-2" id="word-count-display">0 / 2,000 characters</p>
          <% else %>
            <div class="rounded-xl p-5" style="background-color: #FAF6EE; border: 1px solid #F4ECDD;">
              <p class="text-[10px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">Live Waveform</p>
              <div class="flex items-center justify-center gap-0.75 h-12 mb-3">
                <%= for h <- [20, 35, 50, 30, 40, 55, 35, 25, 45, 60, 40, 30, 50, 35, 45, 55, 30, 40, 50, 35, 45, 30, 55, 40, 50, 35, 45, 30, 40, 55, 35, 50, 40, 30, 45] do %>
                  <div class="w-1 rounded-full" style={"height: #{h}%; background-color: #FFB36B;"}></div>
                <% end %>
              </div>
              <div class="grid grid-cols-3 gap-3 mt-3 mb-4">
                <div class="bg-white rounded-lg px-3 py-2 text-center border border-cream-200">
                  <p class="text-[10px] uppercase tracking-wider text-gray-400">Pace</p>
                  <p class="text-sm font-semibold text-gray-900 mt-0.5">—</p>
                </div>
                <div class="bg-white rounded-lg px-3 py-2 text-center border border-cream-200">
                  <p class="text-[10px] uppercase tracking-wider text-gray-400">Clarity</p>
                  <p class="text-sm font-semibold text-gray-900 mt-0.5">—</p>
                </div>
                <div class="bg-white rounded-lg px-3 py-2 text-center border border-cream-200">
                  <p class="text-[10px] uppercase tracking-wider text-gray-400">Filler</p>
                  <p class="text-sm font-semibold text-gray-900 mt-0.5">—</p>
                </div>
              </div>
              <.live_transcript id="behavioral-live-transcript" recording?={@is_recording} class="mb-4" />

              <button
                type="button"
                phx-click="toggle_recording"
                disabled={@transcribing}
                class="w-full inline-flex items-center justify-center gap-1.5 px-4 py-2.5 rounded-lg text-white text-sm font-semibold transition disabled:opacity-60"
                style={if @is_recording, do: "background-color: #DC2626;", else: "background-color: #FF8B00;"}
              >
                <%= cond do %>
                  <% @transcribing -> %> ⏳ Transcribing…
                  <% @is_recording -> %> ⏹ Stop Recording
                  <% true -> %> ▶ Start Recording
                <% end %>
              </button>
              <p class="text-[10px] text-gray-400 text-center mt-2">We'll transcribe your answer into the text box so you can review and edit before submitting.</p>
            </div>
          <% end %>
          </div>

          <div class="flex items-center justify-between mt-5">
            <%!-- <button
              type="button"
              class="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg border border-gray-200 text-xs text-gray-700 hover:bg-cream-50 transition"
            >
              <.icon name="hero-document-text" class="w-3.5 h-3.5" /> Save Draft
            </button> --%>
            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="proceed"
                class="px-4 py-2 rounded-lg border border-gray-200 text-xs text-gray-700 hover:bg-cream-50 transition"
              >Skip</button>
              <button
                type="submit"
                class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold transition"
                style="background-color: #FF8B00;"
              >
                <.icon name="hero-paper-airplane" class="w-3.5 h-3.5" /> {@submit_label}
              </button>
            </div>
          </div>
        </form>
      </div>

      <div class="space-y-4">
        <div class="bg-white rounded-2xl border border-gray-100 p-4">
          <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">STAR helper</p>
          <ul class="space-y-3">
            <.star_helper_row letter="S" title="Situation" question="Where & when did this happen?" />
            <.star_helper_row letter="T" title="Task" question="What was your specific role?" />
            <.star_helper_row letter="A" title="Action" question="What did YOU choose to do?" />
            <.star_helper_row letter="R" title="Result" question="What changed because of it?" />
          </ul>
        </div>

        <div class="rounded-2xl border border-cream-200 p-4" style="background-color: #FFF1DE;">
          <div class="flex items-start gap-2 mb-1">
            <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5" style="color: #B85F00;" />
            <p class="text-sm font-semibold text-gray-800">Vyaasa tip</p>
          </div>
          <p class="text-xs text-gray-600 leading-relaxed">
            Recruiters score the <span class="font-semibold">Action</span> part most. Make YOUR specific decisions vivid.
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :report, :map, required: true
  attr :tenant_alias, :string, required: true
  attr :user_info, :map, required: true
  attr :scenarios_completed, :integer, default: 0
  attr :error_message, :string, default: nil
  attr :error_title, :string, default: nil

  defp render_page_results(assigns) do
    report = assigns.report || %{}
    parsed = report["report"] || %{}
    ratings = parsed["ratings"] || %{}

    reasoning =
      case parsed["reasoning"] do
        %{} = r when map_size(r) > 0 ->
          Map.merge(
            extract_reasoning_from_ratings(ratings),
            extract_reasoning_from_ratings(r),
            fn _k, from_ratings, from_reasoning ->
              if from_reasoning == "", do: from_ratings, else: from_reasoning
            end
          )

        _ ->
          extract_reasoning_from_ratings(ratings)
      end

    user_name = assigns[:user_info][:name]

    leadership = extract_rating_score(ratings, "leadership_potential")
    communication = extract_rating_score(ratings, "communication_skills")
    accountability = extract_rating_score(ratings, "work_ethics_and_reliability")
    problem_solving = extract_rating_score(ratings, "teamwork_and_collaboration")
    adaptability = extract_rating_score(ratings, "adaptability_and_learning")

    radar_points = behavioral_radar_points([leadership, communication, accountability, problem_solving, adaptability])

    radar_labels =
      behavioral_radar_labels(["Leadership", "Communication", "Accountability", "Problem Solving", "Adaptability"])

    assigns =
      assigns
      |> assign(:candidate_name, user_name || parsed["candidate_name"] || "Candidate")
      |> assign(:overall_score, parsed["overall_score"] || 0)
      |> assign(:summary, parsed["summary"] || "")
      |> assign(:strengths, parsed["strengths"] || [])
      |> assign(:areas_for_development, parsed["areas_for_development"] || [])
      |> assign(:reasoning, reasoning)
      |> assign(:leadership, leadership)
      |> assign(:communication, communication)
      |> assign(:accountability, accountability)
      |> assign(:problem_solving, problem_solving)
      |> assign(:adaptability, adaptability)
      |> assign(:radar_points, radar_points)
      |> assign(:radar_labels, radar_labels)

    ~H"""
    <div id="behavioral-report-source" class="space-y-4">
      <div class="rounded-2xl p-6 relative overflow-hidden"
        style="background: linear-gradient(135deg, #FFF6EC 0%, #ECFDF5 100%); border: 1px solid #F4ECDD;"
      >
        <span class="inline-block text-[10px] font-semibold px-2 py-0.5 rounded-full mb-3"
          style="background-color: #22C55E; color: white;">Behavioral assessment complete</span>

        <div class="flex items-start justify-between gap-4">
          <div class="flex-1">
            <h2 class="text-2xl font-bold text-gray-900 mb-2">Your stories are taking shape</h2>
            <p class="text-sm text-gray-700">
              We evaluated your {@scenarios_completed * 2} responses across 5 behavioral dimensions. Here's what stood out — and where to grow next.
            </p>
          </div>
          <div class="text-center shrink-0">
            <div class="w-20 h-20 rounded-full flex items-center justify-center" style="background-color: #FF8B00;">
              <span class="text-2xl font-bold text-white">{@overall_score}</span>
            </div>
            <p class="text-[10px] mt-1 uppercase tracking-wider text-gray-500">Overall Score / 100</p>
          </div>
        </div>
      </div>

      <div class="bg-white rounded-2xl border border-gray-100 p-6 grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div>
          <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">Dimension Radar</p>
          <div class="flex items-center justify-center">
            <div class="relative w-64 h-64">
              <svg viewBox="0 0 200 200" class="w-full h-full" style="overflow: visible">
                <polygon points="100,20 175,65 155,155 45,155 25,65" fill="none" stroke="#F4ECDD" stroke-width="1"/>
                <polygon points="100,40 155,75 140,140 60,140 45,75" fill="none" stroke="#F4ECDD" stroke-width="1"/>
                <polygon points="100,60 135,85 125,125 75,125 65,85" fill="none" stroke="#F4ECDD" stroke-width="1"/>
                <polygon points="100,80 115,95 110,110 90,110 85,95" fill="none" stroke="#F4ECDD" stroke-width="1"/>
                <line x1="100" y1="100" x2="100" y2="20" stroke="#F4ECDD" stroke-width="1"/>
                <line x1="100" y1="100" x2="175" y2="65" stroke="#F4ECDD" stroke-width="1"/>
                <line x1="100" y1="100" x2="155" y2="155" stroke="#F4ECDD" stroke-width="1"/>
                <line x1="100" y1="100" x2="45" y2="155" stroke="#F4ECDD" stroke-width="1"/>
                <line x1="100" y1="100" x2="25" y2="65" stroke="#F4ECDD" stroke-width="1"/>
                <polygon points={@radar_points} fill="rgba(255,139,0,0.25)" stroke="#FF8B00" stroke-width="2"/>
                <text
                  :for={{x, y, anchor, lbl} <- @radar_labels}
                  x={x}
                  y={y}
                  text-anchor={anchor}
                  dominant-baseline="central"
                  class="fill-gray-500"
                  style="font-size:10px"
                >{lbl}</text>
              </svg>
            </div>
          </div>
        </div>

        <div>
          <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">Dimension Scores</p>
          <div class="space-y-3">
            <.dimension_row label="Leadership" score={@leadership} />
            <.dimension_row label="Communication" score={@communication} />
            <.dimension_row label="Accountability" score={@accountability} />
            <.dimension_row label="Problem Solving" score={@problem_solving} />
            <.dimension_row label="Adaptability" score={@adaptability} />
          </div>
        </div>
      </div>

      <div class="bg-white rounded-2xl border border-gray-100 p-5">
        <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-2">Vyaasa Behavioral Summary</p>
        <p class="text-sm text-gray-700 leading-relaxed mb-4">
          <%= if @summary != "", do: @summary, else: "Your stories were brief. To unlock a fuller behavioral picture, retake any round and aim for 150-250 words per response using the full STAR structure." %>
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div class="rounded-xl border border-cream-200 p-3" style="background-color: #FAF6EE;">
            <p class="text-[10px] uppercase tracking-wider text-gray-500 font-semibold">Leadership Potential</p>
            <p class="text-base font-bold text-gray-900 mt-0.5">{leadership_label(@leadership)}</p>
          </div>
          <div class="rounded-xl border border-cream-200 p-3" style="background-color: #FAF6EE;">
            <p class="text-[10px] uppercase tracking-wider text-gray-500 font-semibold">Hiring Recommendation</p>
            <p class="text-base font-bold text-gray-900 mt-0.5">{hiring_recommendation(@overall_score)}</p>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="rounded-2xl border p-5" style="background-color: #ECFDF5; border-color: #A7F3D0;">
          <div class="flex items-center gap-2 mb-3">
            <.icon name="hero-check-circle" class="w-4 h-4 text-green-700" />
            <p class="text-sm font-semibold text-green-800">Key strengths</p>
          </div>
          <ul class="space-y-1.5 text-xs text-green-800">
            <%= if @strengths == [] do %>
              <li>· Clear, structured story arcs</li>
              <li>· Honest reflections on successes</li>
              <li>· Empathy toward teammates</li>
            <% else %>
              <%= for s <- @strengths do %><li>· {s}</li><% end %>
            <% end %>
          </ul>
        </div>

        <div class="rounded-2xl border p-5" style="background-color: #FFF1DE; border-color: #F6D9AE;">
          <div class="flex items-center gap-2 mb-3">
            <.icon name="hero-light-bulb" class="w-4 h-4" style="color: #B85F00;" />
            <p class="text-sm font-semibold" style="color: #B85F00;">Development areas</p>
          </div>
          <ul class="space-y-1.5 text-xs" style="color: #B85F00;">
            <%= if @areas_for_development == [] do %>
              <li>· Use "I" instead of "we" more often</li>
              <li>· Quantify outcomes (e.g. "saved 5 hours")</li>
              <li>· Add one leadership story with a tough call</li>
            <% else %>
              <%= for a <- @areas_for_development do %><li>· {a}</li><% end %>
            <% end %>
          </ul>
        </div>
      </div>

      <div class="bg-white rounded-2xl border border-gray-100 p-5">
        <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">Suggested Learning Path</p>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <.learning_card title="Leadership Storytelling" description="A 5-day course on owning your decisions and outcomes." />
          <.learning_card title="Quantifying Impact" description="Practice scoring soft outcomes that recruiters value." />
          <.learning_card title="Difficult Conversations" description="Workplace dialogue scenarios with the Vyaasa coach." />
        </div>
      </div>

      <.error_card
        :if={@error_message}
        title={@error_title}
        error_message={@error_message}
        retry_event="start_new_assessment"
        class="mb-6"
      />

      <div data-print-hide>
        <VyaasaCampusWeb.Components.Student.AssessmentFooter.assessment_footer
          next_event="back_to_dashboard"
          restart_event="start_new_assessment"
          restart_label="Retake Assessment"
          dashboard_event="back_to_dashboard"
        />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :score, :integer, required: true

  defp dimension_row(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between text-sm mb-1">
        <span class="font-medium text-gray-800">{@label}</span>
        <span class="text-gray-500">{@score}/100</span>
      </div>
      <div class="h-1.5 bg-cream-200 rounded-full overflow-hidden">
        <div class="h-full rounded-full" style={"width: #{@score}%; background-color: #FF8B00;"}></div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true

  defp learning_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-cream-200 p-3 bg-cream-50">
      <p class="text-sm font-semibold text-gray-900 mb-1">{@title}</p>
      <p class="text-xs text-gray-500 leading-relaxed">{@description}</p>
    </div>
    """
  end

  defp behavioral_radar_points(scores) do
    angles = [-90, -18, 54, 126, 198]
    r = 80

    scores
    |> Enum.zip(angles)
    |> Enum.map(fn {score, angle} ->
      val = (score || 0) / 100
      rad = angle * :math.pi() / 180
      x = 100 + r * val * :math.cos(rad)
      y = 100 + r * val * :math.sin(rad)
      "#{Float.round(x, 1)},#{Float.round(y, 1)}"
    end)
    |> Enum.join(" ")
  end

  # Labels placed clear of the outer ring, anchored away from the grid
  # (start/end for side labels, middle for top/bottom) using the same
  # [-90, -18, 54, 126, 198] angles as behavioral_radar_points/1 so each
  # label always lines up with the dimension it names.
  defp behavioral_radar_labels(labels) do
    angles = [-90, -18, 54, 126, 198]
    r = 80

    labels
    |> Enum.zip(angles)
    |> Enum.map(fn {lbl, angle} ->
      rad = angle * :math.pi() / 180
      cos_a = :math.cos(rad)
      sin_a = :math.sin(rad)
      x = Float.round(100 + (r + 16) * cos_a, 1)
      y = Float.round(100 + (r + 16) * sin_a, 1)

      anchor =
        cond do
          cos_a > 0.3 -> "start"
          cos_a < -0.3 -> "end"
          true -> "middle"
        end

      {x, y, anchor, lbl}
    end)
  end

  defp leadership_label(score) when score >= 80, do: "High"
  defp leadership_label(score) when score >= 60, do: "Emerging"
  defp leadership_label(_), do: "Developing"

  defp hiring_recommendation(score) when score >= 80, do: "Strong proceed"
  defp hiring_recommendation(score) when score >= 60, do: "Proceed with notes"
  defp hiring_recommendation(_), do: "Build skills further"

  defp star_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" phx-click="close_star_dialog">
      <div class="rounded-2xl shadow-2xl max-w-2xl w-full p-6" phx-click-away="close_star_dialog" style="background-color: #FAF6EE;">
        <div class="flex items-start justify-between mb-1">
          <div>
            <h3 class="text-xl font-bold text-gray-900">What is STAR?</h3>
            <p class="text-sm text-gray-500">A simple 4-beat structure to make every workplace story land clearly.</p>
          </div>
          <button phx-click="close_star_dialog" class="text-gray-400 hover:text-gray-600">
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 my-5">
          <.star_dialog_tile letter="S" title="Situation" description="Describe the context." />
          <.star_dialog_tile letter="T" title="Task" description="Explain your responsibility." />
          <.star_dialog_tile letter="A" title="Action" description="Describe what you did." />
          <.star_dialog_tile letter="R" title="Result" description="Explain the outcome." />
        </div>

        <div class="rounded-xl border border-cream-200 p-4 mb-5" style="background-color: #FFF1DE;">
          <div class="flex items-center gap-2 mb-2">
            <.icon name="hero-sparkles" class="w-4 h-4" style="color: #B85F00;" />
            <p class="text-[10px] font-semibold tracking-[0.18em] uppercase" style="color: #B85F00;">Example Response</p>
          </div>
          <div class="space-y-1.5 text-xs text-gray-700">
            <p><span class="font-semibold">Situation:</span> Our project deadline was moved forward unexpectedly.</p>
            <p><span class="font-semibold">Task:</span> I was responsible for coordinating developers and designers.</p>
            <p><span class="font-semibold">Action:</span> I reorganized priorities and scheduled daily checkpoints.</p>
            <p><span class="font-semibold">Result:</span> We delivered the project two days before the revised deadline.</p>
          </div>
        </div>

        <div class="flex justify-end">
          <button
            phx-click="close_star_dialog"
            class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold transition"
            style="background-color: #FF8B00;"
          >Continue →</button>
        </div>
      </div>
    </div>
    """
  end

  attr :letter, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp star_dialog_tile(assigns) do
    ~H"""
    <div class="bg-white rounded-xl border border-cream-200 p-4">
      <div class="flex items-center gap-2 mb-1">
        <div class="w-7 h-7 rounded-full flex items-center justify-center text-white text-xs font-bold" style="background-color: #FF8B00;">{@letter}</div>
        <p class="text-sm font-bold text-gray-900">{@title}</p>
      </div>
      <p class="text-xs text-gray-500 ml-9">{@description}</p>
    </div>
    """
  end

  defp competency_bar(assigns) do
    color =
      cond do
        assigns.score >= 85 -> "bg-green-500"
        assigns.score >= 70 -> "bg-yellow-500"
        assigns.score >= 50 -> "bg-orange-500"
        true -> "bg-red-500"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <div>
      <div class="flex justify-between text-sm mb-1">
        <span class="text-gray-700 font-medium">{@label}</span>
        <span class="text-gray-500">{@score}/100</span>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-2.5">
        <div class={[@color, "h-2.5 rounded-full transition-all duration-500"]} style={"width: #{@score}%"}>
        </div>
      </div>
    </div>
    """
  end

  defp competency_accordion(assigns) do
    color =
      cond do
        assigns.score >= 85 -> "text-green-600"
        assigns.score >= 70 -> "text-yellow-600"
        assigns.score >= 50 -> "text-orange-600"
        true -> "text-red-600"
      end

    bar_color =
      cond do
        assigns.score >= 85 -> "bg-green-500"
        assigns.score >= 70 -> "bg-yellow-500"
        assigns.score >= 50 -> "bg-orange-500"
        true -> "bg-red-500"
      end

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:bar_color, bar_color)

    ~H"""
    <div>
      <button
        phx-hook="AccordionToggle"
        id={@id}
        class="w-full flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition text-left"
      >
        <div class="flex items-center gap-3 flex-1">
          <span class="text-sm font-medium text-gray-800">{@label}</span>
          <span class={["text-sm font-bold", @color]}>{@score}/100</span>
        </div>
        <svg data-accordion-icon class="w-4 h-4 text-gray-400 transition-transform duration-200" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      <div class="hidden px-3 pb-4 space-y-2">
        <div class="w-full bg-gray-200 rounded-full h-2">
          <div class={[@bar_color, "h-2 rounded-full transition-all duration-500"]} style={"width: #{@score}%"}></div>
        </div>
        <p class="text-sm text-gray-600 leading-relaxed">{@reasoning}</p>
      </div>
    </div>
    """
  end

  # ------------------------------------------------------------------
  # Private helpers
  # ------------------------------------------------------------------

  defp get_tenant_schema(tenant_alias) do
    alias VyaasaCampus.Contexts.Tenants
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    if tenant, do: tenant.schema_name, else: nil
  end

  # Closing the tab / navigating away mid-conversation must not leave the
  # assessment stuck non-terminal forever — the investigation found this type
  # explicitly abandons (never resumes) a stale "started"/"interviewing" row
  # on the student's next visit, so without this a closed tab meant that row
  # sat there permanently. Enqueues the same finalize job the abandonment
  # sweep uses, so both share one completion path
  # (Behavioral.force_complete/2). Guarded on connected?/1 — the disconnected
  # static-render pass would otherwise fire this on every page load.
  @impl true
  def terminate(_reason, socket) do
    with true <- connected?(socket),
         session_id when is_binary(session_id) <- socket.assigns[:session_id],
         tenant_schema when is_binary(tenant_schema) <- socket.assigns[:tenant_schema] do
      VyaasaCampus.Jobs.AssessmentFinalizer.enqueue("behavioral", session_id, tenant_schema)
    end

    :ok
  end
end
