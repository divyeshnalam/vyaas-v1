defmodule VyaasaCampusWeb.Student.Jam.JamSessionLive do
  @moduledoc """
  LiveView for the JAM (Just A Minute) session flow.
  4-step wizard: Instructions → Topic → Speak → Feedback.
  Integrates with Python JAM service for AI-powered topic generation,
  audio processing, and speech evaluation.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Contexts.Jam
  alias VyaasaCampus.Contexts.StudentRankings
  alias VyaasaCampus.Contexts.StudentAts
  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Student.MicGate
  import VyaasaCampusWeb.Components.Student.VoiceTranscript
  import VyaasaCampusWeb.Student.Jam.Components

  require Logger

  # ── Mount ──────────────────────────────────────────────────────────────

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    tenant_schema = if tenant, do: tenant.schema_name, else: nil
    current_user = socket.assigns[:current_user]

    case current_user do
      nil ->
        {:ok, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}

      _user ->
        # Opik filter labels for every trace this LiveView (and its Tasks) emits.
        if connected?(socket),
          do: VyaasaCampus.AI.Tracing.put_metadata(%{student_id: current_user.id, module: "jam", tenant: tenant_schema})

        ats_fields = StudentAts.get_student_ats_fields(current_user.id, tenant_schema)

        user_info = %{
          name: "#{current_user.first_name} #{current_user.last_name}",
          role: "Student",
          email: current_user.email,
          profile_picture_url: ats_fields[:profile_picture_url]
        }

        # Load rankings for sidebar
        rankings =
          try do
            StudentRankings.get_student_scores_and_ranks(current_user.id, tenant_schema)
          rescue
            _ -> %{}
          end

        socket =
          socket
          |> assign(:tenant_alias, tenant_alias)
          |> assign(:tenant_schema, tenant_schema)
          |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: tenant_alias))
          |> assign(:current_scope, :student)
          |> assign(:user_info, user_info)
          |> assign(:rankings, rankings)
          |> assign(:page_title, "JAM Session")
          |> assign_initial_state()
          |> mount_mic_gate()
          |> maybe_restore_completed_session(current_user.id, tenant_schema)

        # Proctoring: fullscreen unless landing straight on a completed result.
        socket = assign(socket, :require_fullscreen, socket.assigns.current_step not in [:feedback, :completed])

        {:ok, socket}
    end
  end

  defp jam_violation_message("fullscreen_exit"), do: "You left full-screen mode. This is recorded and shared with your evaluator."
  defp jam_violation_message("window_blur"), do: "You switched away from the assessment. This is recorded and shared with your evaluator."
  defp jam_violation_message(_), do: "You switched tabs / left the assessment. This is recorded and shared with your evaluator."

  defp assign_initial_state(socket) do
    socket
    |> assign(:current_step, :instructions)
    |> assign(:show_full_instructions, false)
    |> assign(:topic, nil)
    |> assign(:topic_changed, false)
    |> assign(:decision_countdown, 15)
    |> assign(:decision_timer_active, false)
    |> assign(:prep_countdown, 60)
    |> assign(:prep_timer_active, false)
    |> assign(:speak_countdown, 60)
    |> assign(:speak_timer_active, false)
    |> assign(:is_recording, false)
    |> assign(:show_detailed_feedback, false)
    |> assign(:feedback, nil)
    |> assign(:jam_session, nil)
    |> assign(:loading, nil)
    |> assign(:error, nil)
    |> assign(:error_title, "Something went wrong")
    |> assign(:error_retry_event, "start_session")
    |> assign(:async_ref, nil)
    |> assign(:audio_level, 0)
    |> assign(:audio_muted, false)
    |> assign(:notes, "")
    # Proctoring (log-only for JAM — a short spoken assessment)
    |> assign(:require_fullscreen, true)
    |> assign(:violation_count, 0)
    |> assign(:show_integrity_warning, false)
    |> assign(:integrity_message, nil)
    |> assign(:mic_grace_until, System.monotonic_time(:millisecond))
  end

  defp maybe_restore_completed_session(socket, student_id, tenant_schema) do
    case Jam.get_completed_jam_sessions(student_id, tenant_schema) do
      [latest | _] when latest.evaluation_data != nil and latest.evaluation_data != %{} ->
        eval_data = latest.evaluation_data

        speaking_duration = eval_data["speech_duration_seconds"] || latest.actual_speech_time_used || 0
        mins = div(speaking_duration, 60)
        secs = rem(speaking_duration, 60)
        duration_str = "#{String.pad_leading(Integer.to_string(mins), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}s"

        feedback = %{
          overall_score: eval_data["final_score"] || latest.final_score || 0,
          speaking_duration: duration_str,
          scores: %{
            clarity: eval_data["clarity_score"] || latest.clarity_score || 0,
            fluency: eval_data["confidence_score"] || latest.confidence_score || 0,
            structure: eval_data["structure_score"] || latest.structure_score || 0,
            relevance: eval_data["relevance_score"] || latest.relevance_score || 0
          },
          strengths: parse_list(eval_data["strengths"]),
          improvements: parse_list(eval_data["improvements"]),
          summary: eval_data["overall_summary"] || latest.overall_summary || "No summary available.",
          transcript: eval_data["transcript"] || latest.transcript || "No transcript available.",
          detailed_feedback: %{
            clarity: non_empty(get_in(eval_data, ["detailed_feedback", "clarity"]), "No detailed feedback available for clarity."),
            structure: non_empty(get_in(eval_data, ["detailed_feedback", "structure"]), "No detailed feedback available for structure."),
            relevance: non_empty(get_in(eval_data, ["detailed_feedback", "relevance"]), "No detailed feedback available for relevance."),
            impact: non_empty(get_in(eval_data, ["detailed_feedback", "impact"]), "No detailed feedback available for impact.")
          }
        }

        topic = %{
          title: latest.topic_title,
          guidance: "Consider different perspectives on this topic.",
          explanation: latest.topic_explanation
        }

        socket
        |> assign(:jam_session, latest)
        |> assign(:current_step, :feedback)
        |> assign(:feedback, feedback)
        |> assign(:topic, topic)

      _ ->
        socket
    end
  end

  # ── Events ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_instructions", _params, socket) do
    {:noreply, assign(socket, :show_full_instructions, !socket.assigns.show_full_instructions)}
  end

  @impl true
  def handle_event("toggle_mute", _params, socket) do
    new_muted = !socket.assigns.audio_muted

    socket =
      socket
      |> assign(:audio_muted, new_muted)
      |> push_event(if(new_muted, do: "mute_audio", else: "unmute_audio"), %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_session", _params, socket) do
    # JAM is spoken end to end — make sure the mic is usable before we create a
    # session row the student can't actually complete.
    with {:ok, socket} <- require_mic(socket, "start_session") do
      do_start_session(socket)
    else
      {:gated, socket} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("mic_permission", params, socket) do
    case handle_mic_report(socket, params) do
      {:resume, event, socket} -> handle_event(event, %{}, socket)
      {:ok, socket} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("mic_gate_retry", _params, socket), do: {:noreply, retry_mic(socket)}

  @impl true
  def handle_event("mic_gate_dismiss", _params, socket), do: {:noreply, close_mic_gate(socket)}

  @impl true
  def handle_event("explain_further", _params, socket) do
    topic_title = socket.assigns.topic && socket.assigns.topic.title

    if topic_title do
      # Opik: explain_topic/1 takes no session, so scope this JAM session's
      # thread id around it here (same thread as the other JAM calls).
      thread_id = socket.assigns[:jam_session] && socket.assigns.jam_session.id

      task =
        Task.Supervisor.async_nolink(VyaasaCampus.TaskSupervisor, fn ->
          VyaasaCampus.AI.Tracing.with_thread_id(thread_id, fn -> Jam.explain_topic(topic_title) end)
        end)

      socket =
        socket
        |> assign(:loading, :explain)
        |> assign(:error, nil)
        |> assign(:async_ref, task.ref)
        |> assign(:current_step, :topic_explanation)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("back_to_topic", _params, socket) do
    socket =
      socket
      |> push_event("stop_audio", %{})
      |> assign(:current_step, :topic)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_topic", _params, socket) do
    if socket.assigns.topic_changed do
      {:noreply, put_flash(socket, :warning, "You can only change the topic once.")}
    else
      jam_session = socket.assigns.jam_session
      previous_topic = socket.assigns.topic && socket.assigns.topic.title

      task =
        Task.Supervisor.async_nolink(VyaasaCampus.TaskSupervisor, fn ->
          Jam.change_topic(jam_session, previous_topic)
        end)

      socket =
        socket
        |> assign(:loading, :change_topic)
        |> assign(:error, nil)
        |> assign(:async_ref, task.ref)
        |> assign(:topic_changed, true)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_prep", _params, socket) do
    prefix = socket.assigns.tenant_schema
    jam_session = socket.assigns.jam_session

    # Stop any TTS audio playing when entering prep
    socket = push_event(socket, "stop_audio", %{})

    # Update DB status
    case Jam.start_preparation(jam_session, prefix) do
      {:ok, updated_session} ->
        socket =
          socket
          |> assign(:jam_session, updated_session)
          |> assign(:decision_timer_active, false)
          |> assign(:prep_countdown, 60)
          |> assign(:prep_timer_active, true)
          |> assign(:current_step, :preparation)
          |> push_event("countdown_start", %{id: "prep-countdown-timer", seconds: 60, total: 60})
          |> push_event("countdown_stop", %{id: "decision-countdown-timer"})

        if connected?(socket), do: schedule_tick(:prep)
        {:noreply, socket}

      {:error, _} ->
        # Still allow prep even if DB update fails
        socket =
          socket
          |> assign(:decision_timer_active, false)
          |> assign(:prep_countdown, 60)
          |> assign(:prep_timer_active, true)
          |> assign(:current_step, :preparation)
          |> push_event("countdown_start", %{id: "prep-countdown-timer", seconds: 60, total: 60})
          |> push_event("countdown_stop", %{id: "decision-countdown-timer"})

        if connected?(socket), do: schedule_tick(:prep)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_notes", %{"value" => value}, socket) do
    {:noreply, assign(socket, :notes, value)}
  end

  @impl true
  def handle_event("finish_prep", _params, socket) do
    # No mic re-check here: the student is already in full screen, where the
    # browser suppresses permission prompts — the mic was verified before the
    # session started, and `recording_error` covers a mic lost since then.
    do_finish_prep(socket)
  end

  @impl true
  def handle_event("integrity_violation", %{"type" => type}, socket) do
    cond do
      # Suppress the mic-popup focus-loss window.
      System.monotonic_time(:millisecond) < socket.assigns.mic_grace_until ->
        {:noreply, socket}

      # Enforced only once the session is underway (after Start).
      socket.assigns.current_step not in [:topic, :topic_explanation, :preparation, :speak] ->
        {:noreply, socket}

      true ->
        count =
          case socket.assigns.jam_session do
            %{session_token: token} when is_binary(token) ->
              case Jam.record_violation(token, type, socket.assigns.tenant_schema) do
                {:ok, n} -> n
                _ -> socket.assigns.violation_count + 1
              end

            _ ->
              socket.assigns.violation_count + 1
          end

        socket = socket |> assign(:violation_count, count) |> assign(:show_integrity_warning, true)

        if count >= 3 do
          {:noreply,
           socket
           |> put_flash(:error, "Your assessment was closed after 3 full-screen exits / tab switches.")
           |> redirect(to: ~p"/student/#{socket.assigns.tenant_alias}/dashboard")}
        else
          {:noreply, assign(socket, :integrity_message, jam_violation_message(type))}
        end
    end
  end

  @impl true
  def handle_event("dismiss_integrity_warning", _params, socket) do
    {:noreply, assign(socket, :show_integrity_warning, false)}
  end

  @impl true
  def handle_event("retry_recording", _params, socket) do
    socket =
      socket
      |> assign(:current_step, :preparation)
      |> assign(:error, nil)
      |> assign(:feedback, nil)
      |> assign(:speak_countdown, 60)

    {:noreply, socket}
  end

  @impl true
  def handle_event("back_to_dashboard", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/dashboard")}
  end

  @impl true
  def handle_event("toggle_recording", _params, socket) do
    if socket.assigns.is_recording do
      # Stop recording — push event to JS hook
      {:noreply, push_event(socket, "stop_recording", %{})}
    else
      # Stop the question/prompt TTS, then start recording.
      {:noreply,
       socket
       |> push_event("stop_audio", %{})
       |> push_event("start_recording", %{})}
    end
  end

  @impl true
  def handle_event("recording_started", _params, socket) do
    prefix = socket.assigns.tenant_schema
    jam_session = socket.assigns.jam_session
    prep_time_used = 60 - socket.assigns.prep_countdown

    # Update DB status to speaking
    case Jam.start_speaking(jam_session, prep_time_used, prefix) do
      {:ok, updated_session} ->
        socket =
          socket
          |> assign(:jam_session, updated_session)
          |> assign(:is_recording, true)
          |> assign(:prep_timer_active, false)
          |> assign(:speak_timer_active, true)
          |> push_event("countdown_start", %{id: "speak-countdown-timer", seconds: 60, total: 60})

        if connected?(socket), do: schedule_tick(:speak)
        {:noreply, socket}

      {:error, _} ->
        # Still proceed even if DB update fails
        socket =
          socket
          |> assign(:is_recording, true)
          |> assign(:prep_timer_active, false)
          |> assign(:speak_timer_active, true)
          |> push_event("countdown_start", %{id: "speak-countdown-timer", seconds: 60, total: 60})

        if connected?(socket), do: schedule_tick(:speak)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("recording_error", %{"reason" => reason} = params, socket) do
    # The recorder lost the mic — invalidate the pre-flight check and put the
    # actionable dialog back up instead of a bare toast.
    {:noreply,
     socket
     |> mic_recording_failed(params["name"])
     |> put_flash(:error, "Microphone error: #{reason}")}
  end

  @impl true
  def handle_event("audio_level", %{"level" => level}, socket) do
    {:noreply, assign(socket, :audio_level, level)}
  end

  @impl true
  def handle_event("audio_recorded", %{"audio_data" => audio_data, "mime_type" => mime_type} = _params, socket) do
    jam_session = socket.assigns.jam_session

    if is_nil(jam_session) do
      Logger.warning("audio_recorded event received but jam_session is nil — ignoring")
      {:noreply, put_flash(socket, :error, "Session expired. Please start a new session.")}
    else
      handle_audio_recorded(socket, jam_session, audio_data, mime_type)
    end
  end

  @impl true
  def handle_event("finish_recording", _params, socket) do
    # Push stop to JS hook — the audio_recorded event will handle the rest
    {:noreply, push_event(socket, "stop_recording", %{})}
  end

  @impl true
  def handle_event("toggle_detailed_feedback", _params, socket) do
    {:noreply, assign(socket, :show_detailed_feedback, !socket.assigns.show_detailed_feedback)}
  end

  # "Retake Assessment" on the feedback step: attempt the new session right
  # away and stay on :feedback (with the completed report still visible)
  # until we know whether it worked — same pattern as the MCQ retry flow.
  # Only wipe the old feedback and advance to :topic once the new session
  # actually starts; on failure, layer the error card over the still-visible
  # feedback instead of bouncing to the instructions screen first.
  @impl true
  def handle_event("start_another", _params, socket) do
    case require_mic(socket, "start_another", dialog: false) do
      {:gated, socket} -> {:noreply, socket}
      {:ok, socket} -> do_start_another(socket)
    end
  end

  @impl true
  def handle_event("resend_report", _params, socket) do
    case socket.assigns[:jam_session] do
      %{id: id} ->
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:jam, id, socket.assigns.tenant_schema)
        {:noreply, put_flash(socket, :info, "Your JAM report is on its way to your email ✉️")}

      _ ->
        {:noreply, put_flash(socket, :error, "No completed session to email yet.")}
    end
  end

  @impl true
  def handle_event("retry", _params, socket) do
    jam_session = socket.assigns[:jam_session]
    recording_path = jam_session && jam_session.recording_file_path

    # If a recording was already captured, re-run the transcribe/evaluate
    # pipeline on the saved file rather than forcing the student to re-record
    # (transient Groq failures must not cost them their attempt).
    if is_binary(recording_path) and File.exists?(recording_path) do
      task =
        Task.Supervisor.async_nolink(VyaasaCampus.TaskSupervisor, fn ->
          Jam.process_audio(jam_session, recording_path)
        end)

      socket =
        socket
        |> assign(:error, nil)
        |> assign(:current_step, :feedback)
        |> assign(:loading, :processing)
        |> assign(:async_ref, task.ref)

      {:noreply, socket}
    else
      socket =
        socket
        |> assign(:error, nil)
        |> assign(:loading, nil)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("logout", _params, socket) do
    socket =
      socket
      |> put_flash(:info, "Logged out successfully")
      |> redirect(to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_coming_soon", _params, socket) do
    {:noreply, put_flash(socket, :info, "Settings coming soon!")}
  end

  @impl true
  def handle_event("replay_audio", %{"key" => key}, socket) do
    {:noreply, push_event(socket, "replay_audio", %{audio_key: key})}
  end

  # ── Async Task Results ──────────────────────────────────────────────────

  @impl true
  def handle_info({ref, result}, socket) when socket.assigns.async_ref == ref do
    # Flush the DOWN message
    Process.demonitor(ref, [:flush])

    case {socket.assigns.loading, result} do
      {:topic, {:ok, topic_data}} ->
        handle_topic_result(socket, topic_data)

      {:change_topic, {:ok, topic_data}} ->
        handle_topic_result(socket, topic_data)

      {:explain, {:ok, explanation_data}} ->
        handle_explain_result(socket, explanation_data)

      {:processing, {:ok, eval_data}} ->
        handle_processing_result(socket, eval_data)

      {:processing, {:error, reason}} ->
        Logger.error("JAM audio processing failed: #{inspect(reason)}")
        # Stay on :feedback — reverting to :speak would re-mount the AudioRecorder
        # hook with data-autostart="true", causing an infinite record → fail loop
        # when the student is silent or speaks fewer than the minimum word count.
        socket =
          socket
          |> assign(:loading, nil)
          |> assign(:async_ref, nil)
          |> assign(:is_recording, false)
          |> assign(:error_title, "Something went wrong")
          |> assign(:error, format_error(reason))
          |> assign(:error_retry_event, "retry")

        {:noreply, socket}

      {_loading, {:error, reason}} ->
        Logger.error("JAM async task failed: #{inspect(reason)}")
        socket =
          socket
          |> assign(:loading, nil)
          |> assign(:async_ref, nil)
          |> assign(:error_title, "Something went wrong")
          |> assign(:error, format_error(reason))
          |> assign(:error_retry_event, "retry")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) when socket.assigns.async_ref == ref do
    Logger.error("JAM async task crashed: #{inspect(reason)}")
    socket =
      socket
      |> assign(:loading, nil)
      |> assign(:async_ref, nil)
      |> assign(:error_title, "Something went wrong")
      |> assign(:error, "Something went wrong. Please try again.")
      |> assign(:error_retry_event, "retry")

    {:noreply, socket}
  end

  # ── Timer Ticks ────────────────────────────────────────────────────────

  @impl true
  def handle_info(:decision_tick, socket) do
    if socket.assigns.decision_timer_active do
      new_countdown = socket.assigns.decision_countdown - 1

      if new_countdown <= 0 do
        # Auto-start preparation — stop any TTS audio
        socket =
          socket
          |> push_event("stop_audio", %{})
          |> assign(:decision_timer_active, false)
          |> assign(:decision_countdown, 0)
          |> assign(:prep_countdown, 60)
          |> assign(:prep_timer_active, true)
          |> assign(:current_step, :preparation)
          |> push_event("countdown_stop", %{id: "decision-countdown-timer"})
          |> push_event("countdown_start", %{id: "prep-countdown-timer", seconds: 60, total: 60})

        schedule_tick(:prep)
        {:noreply, socket}
      else
        schedule_tick(:decision)
        {:noreply, assign(socket, :decision_countdown, new_countdown)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:prep_tick, socket) do
    if socket.assigns.prep_timer_active do
      new_countdown = socket.assigns.prep_countdown - 1

      if new_countdown <= 0 do
        # Auto-advance to speak — stop any TTS audio
        socket =
          socket
          |> push_event("stop_audio", %{})
          |> assign(:prep_timer_active, false)
          |> assign(:prep_countdown, 0)
          |> assign(:current_step, :speak)
          |> assign(:speak_countdown, 60)

        {:noreply, socket}
      else
        schedule_tick(:prep)
        {:noreply, assign(socket, :prep_countdown, new_countdown)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:speak_tick, socket) do
    if socket.assigns.speak_timer_active do
      new_countdown = socket.assigns.speak_countdown - 1

      if new_countdown <= 0 do
        # Auto-stop recording
        socket =
          socket
          |> assign(:speak_countdown, 0)

        {:noreply, push_event(socket, "stop_recording", %{})}
      else
        schedule_tick(:speak)
        {:noreply, assign(socket, :speak_countdown, new_countdown)}
      end
    else
      {:noreply, socket}
    end
  end

  # Catch-all for any other messages (prevents crashes)
  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ── Audio recorded handler ──

  defp handle_audio_recorded(socket, jam_session, audio_data, mime_type) do
    prefix = socket.assigns.tenant_schema
    speech_time_used = 60 - socket.assigns.speak_countdown

    case Base.decode64(audio_data) do
      {:ok, binary_data} ->
        extension = if String.contains?(mime_type, "webm"), do: ".webm", else: ".ogg"
        tmp_path = Path.join(System.tmp_dir!(), "jam_#{jam_session.session_token}#{extension}")
        File.write!(tmp_path, binary_data)

        audio_attrs = %{recording_file_path: tmp_path, recording_duration_seconds: speech_time_used}

        case Jam.complete_speaking(jam_session, speech_time_used, audio_attrs, prefix) do
          {:ok, updated_session} ->
            task =
              Task.Supervisor.async_nolink(VyaasaCampus.TaskSupervisor, fn ->
                Jam.process_audio(updated_session, tmp_path)
              end)

            socket =
              socket
              |> assign(:jam_session, updated_session)
              |> assign(:is_recording, false)
              |> assign(:speak_timer_active, false)
              |> assign(:current_step, :feedback)
              |> assign(:loading, :processing)
              |> assign(:error, nil)
              |> assign(:async_ref, task.ref)

            {:noreply, socket}

          {:error, _} ->
            task =
              Task.Supervisor.async_nolink(VyaasaCampus.TaskSupervisor, fn ->
                Jam.process_audio(jam_session, tmp_path)
              end)

            socket =
              socket
              |> assign(:is_recording, false)
              |> assign(:speak_timer_active, false)
              |> assign(:current_step, :feedback)
              |> assign(:loading, :processing)
              |> assign(:error, nil)
              |> assign(:async_ref, task.ref)

            {:noreply, socket}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Failed to process audio recording.")}
    end
  end

  # ── Topic result handler ──

  defp handle_topic_result(socket, topic_data) do
    prefix = socket.assigns.tenant_schema
    jam_session = socket.assigns.jam_session

    topic_title = topic_data["topic_title"] || topic_data[:topic_title]
    topic_explanation = topic_data["topic_explanation"] || topic_data[:topic_explanation]
    guidance = topic_data["guidance"] || topic_data[:guidance]
    audio_data = topic_data["audio_data"] || topic_data[:audio_data]
    audio_type = topic_data["audio_type"] || topic_data[:audio_type] || "mp3"

    # Update DB with topic
    topic_attrs = %{
      topic_title: topic_title,
      topic_explanation: topic_explanation
    }

    topic = %{
      title: topic_title,
      guidance: guidance || "Consider different perspectives on this topic.",
      explanation: topic_explanation
    }

    socket =
      case Jam.update_jam_session_topic(jam_session, topic_attrs, prefix) do
        {:ok, updated_session} -> assign(socket, :jam_session, updated_session)
        {:error, _} -> socket
      end

    socket =
      socket
      |> assign(:topic, topic)
      |> assign(:loading, nil)
      |> assign(:async_ref, nil)
      |> assign(:decision_countdown, 15)
      |> assign(:decision_timer_active, true)
      |> push_event("countdown_start", %{id: "decision-countdown-timer", seconds: 15, total: 15})

    # TTS: speak the topic aloud using browser Web Speech API
    socket =
      if audio_data do
        push_event(socket, "play_audio", %{audio_data: audio_data, audio_type: audio_type, audio_key: "topic"})
      else
        tts_text = "Your topic is: #{topic_title}. #{topic_explanation}"
        push_event(socket, "speak_text", %{text: tts_text, audio_key: "topic"})
      end

    if connected?(socket), do: schedule_tick(:decision)
    {:noreply, socket}
  end

  # ── Explain result handler ──

  defp handle_explain_result(socket, explanation_data) do
    explanation = explanation_data["explanation"] || explanation_data[:explanation]
    audio_data = explanation_data["audio_data"] || explanation_data[:audio_data]
    audio_type = explanation_data["audio_type"] || explanation_data[:audio_type] || "mp3"

    topic = socket.assigns.topic
    updated_topic = %{topic | explanation: explanation || topic.explanation}

    socket =
      socket
      |> assign(:topic, updated_topic)
      |> assign(:loading, nil)
      |> assign(:async_ref, nil)

    # TTS: speak the explanation using browser Web Speech API
    socket =
      if audio_data do
        push_event(socket, "play_audio", %{audio_data: audio_data, audio_type: audio_type, audio_key: "explanation"})
      else
        push_event(socket, "speak_text", %{text: explanation || "", audio_key: "explanation"})
      end

    {:noreply, socket}
  end

  # ── Processing result handler ──

  defp handle_processing_result(socket, eval_data) do
    prefix = socket.assigns.tenant_schema
    jam_session = socket.assigns.jam_session

    db_attrs = Jam.evaluation_to_completion_attrs(eval_data)

    # Update DB with evaluation
    case Jam.complete_processing(jam_session, db_attrs, prefix) do
      {:ok, updated_session} ->
        socket = assign(socket, :jam_session, updated_session)
        build_feedback_assigns(socket, eval_data)

      {:error, _} ->
        # Still show feedback even if DB update fails
        build_feedback_assigns(socket, eval_data)
    end
  end

  defp build_feedback_assigns(socket, eval_data) do
    # Build the feedback map matching the UI expectations
    speaking_duration = eval_data["speech_duration_seconds"] || (60 - socket.assigns.speak_countdown)
    mins = div(speaking_duration, 60)
    secs = rem(speaking_duration, 60)
    duration_str = "#{String.pad_leading(Integer.to_string(mins), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}s"

    feedback = %{
      overall_score: eval_data["final_score"] || 0,
      speaking_duration: duration_str,
      scores: %{
        clarity: eval_data["clarity_score"] || 0,
        fluency: eval_data["confidence_score"] || 0,
        structure: eval_data["structure_score"] || 0,
        relevance: eval_data["relevance_score"] || 0
      },
      strengths: parse_list(eval_data["strengths"]),
      improvements: parse_list(eval_data["improvements"]),
      summary: eval_data["overall_summary"] || "No summary available.",
      transcript: eval_data["transcript"] || "No transcript available.",
      detailed_feedback: %{
        clarity: non_empty(get_in(eval_data, ["detailed_feedback", "clarity"]), "No detailed feedback available for clarity."),
        structure: non_empty(get_in(eval_data, ["detailed_feedback", "structure"]), "No detailed feedback available for structure."),
        relevance: non_empty(get_in(eval_data, ["detailed_feedback", "relevance"]), "No detailed feedback available for relevance."),
        impact: non_empty(get_in(eval_data, ["detailed_feedback", "impact"]), "No detailed feedback available for impact.")
      }
    }

    socket =
      socket
      |> assign(:feedback, feedback)
      |> assign(:loading, nil)
      |> assign(:async_ref, nil)

    {:noreply, socket}
  end

  defp parse_list(nil), do: []
  defp parse_list(list) when is_list(list), do: list
  defp parse_list(str) when is_binary(str), do: [str]
  defp parse_list(_), do: []

  defp non_empty(nil, fallback), do: fallback
  defp non_empty("", fallback), do: fallback
  defp non_empty(value, _fallback) when is_binary(value), do: value
  defp non_empty(_, fallback), do: fallback

  defp format_error({:validation_error, %{message: message}}), do: message
  defp format_error({:validation_error, %{"message" => message}}), do: message
  defp format_error({:http_error, _status, %{"error" => message}}) when is_binary(message), do: message
  defp format_error({:http_error, status, _body}), do: "Service returned error (HTTP #{status}). Please try again."
  defp format_error({:service_error, _reason}), do: "Could not connect to AI service. Please try again."
  defp format_error(:groq_overloaded), do: "AI service is experiencing high demand. Please wait a moment and try again."
  defp format_error(msg) when is_binary(msg), do: msg
  # too_short info comes back as a keyword list: [word_count: N, min_required: 30, message: "..."]
  defp format_error(info) when is_list(info), do: Keyword.get(info, :message) || "Speech too short. Please try again."
  defp format_error(_), do: "Something went wrong. Please try again."

  defp do_finish_prep(socket) do
    # Move to the speak step, stop the prep timer, and let the AudioRecorder
    # hook auto-start (via data-autostart="true"). The `recording_started`
    # event handler will update the DB and start the speak timer once the
    # browser confirms the mic stream is live.
    socket =
      socket
      |> assign(:prep_timer_active, false)
      |> assign(:speak_countdown, 60)
      |> assign(:current_step, :speak)
      # Mic grace: the permission/OS audio popup steals focus as recording
      # auto-starts; ignore focus loss for ~8s so it doesn't log a false strike.
      |> assign(:mic_grace_until, System.monotonic_time(:millisecond) + 8_000)
      |> push_event("countdown_stop", %{id: "prep-countdown-timer"})

    {:noreply, socket}
  end

  defp do_start_another(socket) do
    current_user = socket.assigns.current_user
    prefix = socket.assigns.tenant_schema

    attrs = %{student_id: current_user.id, tenant_id: current_user.tenant_id}

    case Jam.create_jam_session(attrs, prefix) do
      {:ok, jam_session} ->
        task =
          Task.Supervisor.async_nolink(VyaasaCampus.TaskSupervisor, fn ->
            Jam.generate_topic(jam_session)
          end)

        socket =
          socket
          |> assign_initial_state()
          |> assign(:jam_session, jam_session)
          |> assign(:loading, :topic)
          |> assign(:error, nil)
          |> assign(:async_ref, task.ref)
          |> assign(:current_step, :topic)

        {:noreply, socket}

      {:error, :attempt_limit_reached, _details} ->
        {:noreply,
         socket
         |> assign(:error_title, "Out of attempts")
         |> assign(
           :error,
           "You've used all your available JAM attempts. Please contact your college admin to request more."
         )
         |> assign(:error_retry_event, "start_another")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:error_title, "Something went wrong")
         |> assign(:error, "Failed to create JAM session. Please try again.")
         |> assign(:error_retry_event, "start_another")}
    end
  end

  defp do_start_session(socket) do
    current_user = socket.assigns.current_user
    prefix = socket.assigns.tenant_schema

    # Create DB session
    attrs = %{
      student_id: current_user.id,
      tenant_id: current_user.tenant_id
    }

    case Jam.create_jam_session(attrs, prefix) do
      {:ok, jam_session} ->
        # Async generate topic
        task =
          Task.Supervisor.async_nolink(VyaasaCampus.TaskSupervisor, fn ->
            Jam.generate_topic(jam_session)
          end)

        socket =
          socket
          |> assign(:jam_session, jam_session)
          |> assign(:loading, :topic)
          |> assign(:error, nil)
          |> assign(:async_ref, task.ref)
          |> assign(:current_step, :topic)

        {:noreply, socket}

      {:error, :attempt_limit_reached, _details} ->
        {:noreply,
         socket
         |> assign(:error_title, "Out of attempts")
         |> assign(
           :error,
           "You've used all your available JAM attempts. Please contact your college admin to request more."
         )
         |> assign(:error_retry_event, "start_session")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create JAM session. Please try again.")}
    end
  end

  defp schedule_tick(:decision), do: Process.send_after(self(), :decision_tick, 1000)
  defp schedule_tick(:prep), do: Process.send_after(self(), :prep_tick, 1000)
  defp schedule_tick(:speak), do: Process.send_after(self(), :speak_tick, 1000)

  # ── Render ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    # Full screen required only once the JAM session is underway (after Start).
    assigns = assign(assigns, :require_fullscreen, assigns.current_step in [:topic, :topic_explanation, :preparation, :speak])

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="toast-container" phx-hook="ToastContainer" class="fixed top-4 right-4 z-50 space-y-2"></div>

      <.mic_gate id="jam-mic-gate" state={@mic_permission} detail={@mic_detail} open={@mic_gate_open} checking={@mic_checking} />

      <div class="min-h-screen bg-cream-50 flex" id="jam-container" phx-hook="AssessmentIntegrity"
        data-require-fullscreen={to_string(@require_fullscreen)}>
        <div :if={@require_fullscreen} id="fullscreen-gate" phx-update="ignore"
          class="fixed inset-0 z-100 bg-gray-900/95 flex items-center justify-center p-6 text-center">
          <div class="max-w-md">
            <.icon name="hero-lock-closed" class="w-12 h-12 text-orange-400 mx-auto mb-4" />
            <h2 class="text-xl font-bold text-white mb-2">Secure full-screen mode</h2>
            <p class="text-sm text-gray-300 mb-6">
              This is a proctored speaking assessment that runs in full screen. Leaving full screen
              or switching windows while you speak is recorded and shared with your evaluator.
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
          :if={@current_step not in [:topic, :topic_explanation, :preparation, :speak]}
          current_section="jam"
          tenant_alias={@tenant_alias}
          student_name={@user_info.name}
          rankings={@rankings}
        />

        <div class="flex-1 flex flex-col min-w-0 h-screen overflow-hidden">
          <VyaasaCampusWeb.Components.Student.HeaderComponent.header
            user_info={@user_info}
            tenant_alias={@tenant_alias}
            page_title="JAM Session"
            exit_href={"/student/#{@tenant_alias}/dashboard"}
            focus?={@current_step in [:topic, :topic_explanation, :preparation, :speak]}
          />

          <div :if={@show_integrity_warning} class="bg-red-600 text-white px-6 py-3 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-exclamation-triangle" class="w-5 h-5 shrink-0" />
              <span class="text-sm font-medium">{@integrity_message} (Recorded {@violation_count} time{if @violation_count != 1, do: "s"}.)</span>
            </div>
            <button type="button" phx-click="dismiss_integrity_warning" class="text-white hover:text-red-100">
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <main class="flex-1 overflow-y-auto">
            <div class="px-4 lg:px-8 py-8 max-w-6xl mx-auto w-full">
              <!-- Page header -->
              <div class="flex items-start justify-between mb-6">
                <div class="flex items-start gap-3">
                  <div
                    class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
                    style="background-color: #FFE9D2;"
                  >
                    <.icon name="hero-chat-bubble-left-right" class="w-5 h-5" style="color: #B85F00;" />
                  </div>
                  <div>
                    <p class="text-[11px] font-semibold tracking-[0.18em] uppercase" style="color: #FF8B00;">Communication · Adaptability</p>
                    <h1 class="text-2xl font-bold text-gray-900">JAM Session</h1>
                    <p class="text-sm text-gray-500 mt-0.5">One minute. One topic. Endless growth.</p>
                  </div>
                </div>
                <%= if @current_step in [:topic, :preparation, :topic_explanation, :speak, :feedback] do %>
                  <button
                    phx-click="back_to_dashboard"
                    class="inline-flex items-center gap-1.5 text-sm text-gray-600 hover:text-gray-900 transition"
                  >
                    <%!-- <.icon name="hero-arrow-left" class="w-4 h-4" /> Previous --%>
                  </button>
                <% end %>
              </div>

              <!-- Stepper -->
              <.stepper current_step={@current_step} />

              <!-- Audio Player (persistent, invisible — caches TTS audio across steps) -->
              <div id="audio-player" phx-hook="AudioPlayer"></div>

              <!-- Step Content -->
              <div class="grid grid-cols-1 lg:grid-cols-12 gap-8">
                <div class="lg:col-span-8">
                  <%= if @error && @current_step != :feedback do %>
                    <.error_card
                      title={@error_title}
                      error_message={@error}
                      retry_event={@error_retry_event}
                      class="mb-4"
                    />
                  <% end %>

                  <%= case @current_step do %>
                    <% :instructions -> %>
                      <.instructions_step
                        error={@error}
                        mic_verified={@mic_verified}
                        mic_permission={@mic_permission}
                        mic_checking={@mic_checking}
                      />
                    <% :topic -> %>
                      <.topic_step
                        topic={@topic}
                        topic_changed={@topic_changed}
                        decision_countdown={@decision_countdown}
                        decision_timer_active={@decision_timer_active}
                        loading={@loading}
                      />
                    <% :preparation -> %>
                      <.preparation_step
                        topic={@topic}
                        prep_countdown={@prep_countdown}
                        prep_timer_active={@prep_timer_active}
                        notes={@notes}
                      />
                    <% :topic_explanation -> %>
                      <.topic_explanation_step topic={@topic} loading={@loading} />
                    <% :speak -> %>
                      <.speak_step
                        topic={@topic}
                        speak_countdown={@speak_countdown}
                        speak_timer_active={@speak_timer_active}
                        is_recording={@is_recording}
                        audio_level={@audio_level}
                      />
                    <% :feedback -> %>
                      <.feedback_step
                        topic={@topic}
                        feedback={@feedback}
                        loading={@loading}
                        error={@error}
                        error_title={@error_title}
                        error_retry_event={@error_retry_event}
                        tenant_alias={@tenant_alias}
                        jam_session={@jam_session}
                        mic_verified={@mic_verified}
                        mic_permission={@mic_permission}
                        mic_checking={@mic_checking}
                      />
                  <% end %>
                </div>

                <!-- Right Sidebar (Cards) -->
                <div class="lg:col-span-4 space-y-6">
                  <%= case @current_step do %>
                    <% :instructions -> %>
                      <.right_card_calm_reminder />
                      <.right_card_dimensions />
                    <% step when step in [:topic, :topic_explanation, :preparation] -> %>
                      <.right_card_key_points />
                      <.right_card_speaking_tip />
                    <% :speak -> %>
                      <.right_card_speaking_tip />
                    <% :feedback -> %>
                      <.right_card_insights feedback={@feedback} />
                      <.right_card_improve_next feedback={@feedback} />
                  <% end %>
                </div>
              </div>
            </div>
          </main>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Step Components ────────────────────────────────────────────────────

  attr :show_full_instructions, :boolean, default: false
  attr :error, :string, default: nil
  attr :mic_verified, :boolean, default: false
  attr :mic_permission, :string, default: nil
  attr :mic_checking, :boolean, default: false

  defp instructions_step(assigns) do
    ~H"""
    <div class="bg-white rounded-3xl p-8 border border-gray-100 shadow-sm">
      <div class="flex items-start gap-4 mb-6">
        <div class="w-12 h-12 bg-orange-50 rounded-2xl flex items-center justify-center shrink-0">
          <.icon name="hero-chat-bubble-left-right" class="w-6 h-6 text-orange-500" />
        </div>
        <div>
          <div class="flex items-center gap-2 mb-1">
            <span class="text-[10px] font-bold tracking-wider text-orange-500 uppercase">COMMUNICATION · ADAPTABILITY</span>
          </div>
          <h2 class="text-3xl font-bold text-gray-900 mb-1">JAM Session</h2>
          <p class="text-gray-500">One minute. One topic. Endless growth.</p>
        </div>
      </div>

      <div class="bg-orange-50/50 rounded-3xl p-8 mb-8 border border-orange-100/50">
        <div class="flex items-start justify-between mb-8">
          <div>
            <span class="inline-block px-3 py-1 bg-orange-500 text-white text-[10px] font-bold rounded-full mb-4">A friendly intro</span>
            <h3 class="text-3xl font-bold text-gray-900 leading-tight">
              Speak for 60 seconds your<br />Vyaasa coach is in your corner.
            </h3>
            <p class="text-gray-500 mt-4">No pass. No fail. Just five gentle dimensions of feedback so you can hear yourself grow.</p>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
          <.instruction_feature icon="hero-microphone" label="30s prep + 60s speak" />
          <.instruction_feature icon="hero-sparkles" label="Vyaasa listening" />
          <.instruction_feature icon="hero-hand-raised" label="Distraction-free" />
          <.instruction_feature icon="hero-chart-bar" label="5 dimensions tracked" />
          <.instruction_feature icon="hero-light-bulb" label="Vyaasa speech tips" />
          <.instruction_feature icon="hero-trophy" label="Earn streak badges" />
        </div>

        <%!-- Driven by the passive Permissions API read, so a student with a
        blocked mic is told here — no prompt, no click needed. --%>
        <.mic_status verified={@mic_verified} state={@mic_permission} checking={@mic_checking} />

        <%!-- Deliberately no `data-enter-fullscreen`: full screen must not
        engage until the mic is verified, because browsers suppress the
        permission prompt while a page is full screen. The full-screen gate on
        the next step takes over. --%>
        <button
          :if={!@error}
          phx-click="start_session"
          class="inline-flex items-center justify-center px-8 py-4 bg-orange-500 hover:bg-orange-600 text-white font-bold rounded-2xl transition-all shadow-lg shadow-orange-200 gap-2"
        >
          Start Session
          <.icon name="hero-arrow-right" class="w-5 h-5" />
        </button>
      </div>
    </div>
    """
  end

  defp instruction_feature(assigns) do
    ~H"""
    <div class="flex items-center gap-3 bg-white/80 border border-gray-100 p-4 rounded-2xl">
      <div class="w-8 h-8 rounded-full bg-orange-50 flex items-center justify-center shrink-0">
        <.icon name={@icon} class="w-4 h-4 text-orange-500" />
      </div>
      <span class="text-sm font-semibold text-gray-700">{@label}</span>
    </div>
    """
  end

  defp right_card_calm_reminder(assigns) do
    ~H"""
    <div class="bg-orange-50/50 border border-orange-100 rounded-3xl p-6">
      <div class="flex items-start gap-3">
        <div class="w-10 h-10 bg-white rounded-2xl flex items-center justify-center shrink-0 shadow-sm">
          <.icon name="hero-sparkles" class="w-5 h-5 text-orange-500" />
        </div>
        <div>
          <h4 class="font-bold text-gray-900 mb-1">Calm reminder</h4>
          <p class="text-sm text-gray-600 leading-relaxed">Pauses are powerful. Confident speakers breathe between ideas.</p>
        </div>
      </div>
    </div>
    """
  end

  defp right_card_dimensions(assigns) do
    ~H"""
    <div class="bg-white border border-gray-100 rounded-3xl p-6 shadow-sm">
      <h4 class="text-[11px] font-bold tracking-wider text-gray-400 uppercase mb-4">5 EVALUATION DIMENSIONS</h4>
      <ul class="space-y-3">
        <%= for dimension <- ["Clarity", "Fluency", "Structure", "Relevance", "Impact"] do %>
          <li class="flex items-center gap-2">
            <span class="w-1.5 h-1.5 rounded-full bg-orange-500"></span>
            <span class="text-sm font-semibold text-gray-700">{dimension}</span>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  attr :topic, :map
  attr :topic_changed, :boolean, default: false
  attr :decision_countdown, :integer, default: 15
  attr :decision_timer_active, :boolean, default: false
  attr :prep_countdown, :integer, default: 60
  attr :prep_timer_active, :boolean, default: false
  attr :loading, :atom, default: nil
  attr :audio_muted, :boolean, default: false

  defp topic_step(assigns) do
    ~H"""
    <div class="bg-white rounded-3xl p-8 border border-gray-100 shadow-sm relative overflow-hidden">
      <!-- Background Gradient Blob -->
      <div class="absolute -top-24 -right-24 w-64 h-64 bg-orange-100/50 rounded-full blur-3xl -z-10"></div>

      <%= if @loading in [:topic, :change_topic] do %>
        <div class="flex flex-col items-center justify-center py-24">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-orange-500 mb-4"></div>
          <p class="text-gray-600 font-medium">
            <%= if @loading == :topic, do: "Generating your topic...", else: "Finding a new topic..." %>
          </p>
        </div>
      <% else %>
        <div class="mb-6">
          <span class="inline-block px-3 py-1 bg-orange-50 text-orange-600 text-[10px] font-bold rounded-full mb-4">Today's topic</span>
          <h2 class="text-4xl font-bold text-gray-900 leading-tight mb-4">
            "{@topic && @topic.title}"
          </h2>
          <p class="text-gray-500 text-lg">
            A timely topic speak about what's changing, why it matters, and your take.
          </p>
        </div>

        <div class="bg-orange-50/50 border border-orange-100 rounded-2xl p-6 mb-8">
          <div class="flex items-center gap-2 mb-3">
            <span class="text-[10px] font-bold tracking-wider text-orange-600 uppercase">VYAASA EXPLANATION</span>
          </div>
          <p class="text-gray-700 leading-relaxed">
            Think about <span class="font-bold">1) what is changing right now</span>, <span class="font-bold">2) why students should care</span>, and <span class="font-bold">3) a personal angle</span> — your own experience, observation, or hope for the future.
          </p>
        </div>

        <div class="flex items-center gap-4 mb-10">
          <button
            phx-click="change_topic"
            disabled={@topic_changed}
            class={["flex items-center gap-2 px-6 py-3 border-2 border-gray-100 rounded-2xl font-bold text-gray-600 hover:bg-gray-50 transition-all", @topic_changed && "opacity-50 cursor-not-allowed"]}
          >
            <.icon name="hero-arrow-path" class="w-5 h-5" />
            Change Topic
          </button>
          <button
            phx-click="explain_further"
            class="flex items-center gap-2 px-6 py-3 border-2 border-gray-100 rounded-2xl font-bold text-gray-600 hover:bg-gray-50 transition-all"
          >
            <.icon name="hero-sparkles" class="w-5 h-5 text-orange-500" />
            Explain Further
          </button>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          <.topic_hint_card time="1-20S" title="Introduction" desc="Hook with a surprising stat or personal angle." />
          <.topic_hint_card time="2-20S" title="Key points" desc="Cover 2 trends + 1 challenge." />
          <.topic_hint_card time="3-20S" title="Conclusion" desc="End with a forward-looking takeaway." />
        </div>

        <button
          phx-click="start_prep"
          class="w-full flex items-center justify-center gap-2 py-4 bg-orange-500 hover:bg-orange-600 text-white font-bold rounded-2xl transition-all shadow-lg shadow-orange-200"
        >
          <%= if @decision_timer_active do %>
            Starting in {@decision_countdown}s...
          <% else %>
            Continue to Preparation
            <.icon name="hero-arrow-right" class="w-5 h-5" />
          <% end %>
        </button>
      <% end %>
    </div>
    """
  end

  defp topic_hint_card(assigns) do
    ~H"""
    <div class="bg-white border border-gray-100 p-5 rounded-2xl shadow-sm">
      <span class="text-[10px] font-bold text-orange-500">{@time}</span>
      <h4 class="font-bold text-gray-900 mt-1 mb-2">{@title}</h4>
      <p class="text-xs text-gray-500 leading-relaxed">{@desc}</p>
    </div>
    """
  end

  attr :topic, :map
  attr :prep_countdown, :integer, default: 60
  attr :prep_timer_active, :boolean, default: false
  attr :notes, :string, default: ""

  defp preparation_step(assigns) do
    ~H"""
    <div class="bg-white rounded-3xl p-8 border border-gray-100 shadow-sm">
      <!-- Assigned topic (visible during prep) -->
      <div class="bg-orange-50/50 border border-orange-100 rounded-2xl p-6 mb-8">
        <span class="text-[10px] font-bold tracking-wider text-orange-600 uppercase">Your topic</span>
        <h3 class="text-2xl font-bold text-gray-900 leading-tight mt-2">
          "{@topic && @topic.title}"
        </h3>
        <%= if @topic && @topic.explanation do %>
          <p class="text-gray-700 leading-relaxed mt-3">{@topic.explanation}</p>
        <% end %>
      </div>

      <div class="flex items-center justify-between mb-8">
        <div>
          <span class="inline-block px-3 py-1 bg-orange-50 text-orange-600 text-[10px] font-bold rounded-full mb-4">Prep time</span>
          <h2 class="text-3xl font-bold text-gray-900 mb-2">Take a breath. Outline your three beats.</h2>
          <p class="text-gray-500">Don't Memorize Jot Keywords You Can Speak From.</p>
        </div>

        <div class="flex flex-col items-center gap-2">
          <div class="w-20 h-20 flex items-center justify-center relative">
            <svg class="absolute inset-0 w-full h-full -rotate-90" viewBox="0 0 80 80">
              <!-- Background circle -->
              <circle cx="40" cy="40" r="36" fill="none" stroke="#f3f4f6" stroke-width="4" />
              <!-- Progress circle -->
              <circle
                cx="40" cy="40" r="36"
                fill="none" stroke="#F97316" stroke-width="4"
                stroke-linecap="round"
                stroke-dasharray="226.19"
                stroke-dashoffset={226.19 * (1 - @prep_countdown / 60)}
                class="transition-all duration-1000"
              />
            </svg>
            <span class="text-xl font-bold text-gray-900 relative z-10">{@prep_countdown}</span>
          </div>
          <button class="text-[10px] font-bold text-gray-500 hover:text-gray-900 flex items-center gap-1">
            <.icon name="hero-plus" class="w-3 h-3" /> EXTEND
          </button>
        </div>
      </div>

      <!-- No text answer/return input during preparation. Mentally outline your beats. -->
      <div class="bg-gray-50 border border-gray-100 rounded-3xl p-6 mb-8 flex items-start gap-3">
        <.icon name="hero-light-bulb" class="w-5 h-5 text-orange-500 shrink-0 mt-0.5" />
        <p class="text-sm text-gray-600 leading-relaxed">
          Use this minute to plan your three beats in your head — a hook, two key points, and a closing line.
          You'll speak your answer once preparation ends. There's nothing to type here.
        </p>
      </div>

      <button
        phx-click="finish_prep"
        class="w-full flex items-center justify-center gap-2 py-4 bg-orange-500 hover:bg-orange-600 text-white font-bold rounded-2xl transition-all shadow-lg shadow-orange-200"
      >
        <.icon name="hero-play" class="w-5 h-5 fill-current" />
        Start Speaking
      </button>
    </div>
    """
  end

  defp right_card_key_points(assigns) do
    ~H"""
    <div class="bg-white border border-gray-100 rounded-3xl p-6 shadow-sm">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-list-bullet" class="w-4 h-4 text-orange-500" />
        <h4 class="text-[11px] font-bold tracking-wider text-gray-400 uppercase">KEY POINTS HELPER</h4>
      </div>
      <ul class="space-y-2">
        <%= for point <- ["Rise of AI-led mentorship", "Global access for tier-2/3 cities", "Skill-based hiring shift"] do %>
          <li class="p-3 bg-gray-50 rounded-xl text-sm font-semibold text-gray-700">
            {point}
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp right_card_speaking_tip(assigns) do
    ~H"""
    <div class="bg-orange-50/50 border border-orange-100 rounded-3xl p-6">
      <div class="flex items-start gap-3">
        <div class="w-10 h-10 bg-white rounded-2xl flex items-center justify-center shrink-0 shadow-sm">
          <.icon name="hero-sparkles" class="w-5 h-5 text-orange-500" />
        </div>
        <div>
          <h4 class="font-bold text-gray-900 mb-1">Speaking tip</h4>
          <p class="text-sm text-gray-600 leading-relaxed">
            Open with <span class="italic text-gray-400">"Imagine a college student in 2025..."</span> story openings boost engagement.
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :topic, :map
  attr :loading, :atom, default: nil
  attr :audio_muted, :boolean, default: false

  defp topic_explanation_step(assigns) do
    ~H"""
    <div class="bg-white rounded-3xl p-8 border border-gray-100 shadow-sm relative overflow-hidden">
      <!-- Background Gradient Blob -->
      <div class="absolute -top-24 -right-24 w-64 h-64 bg-orange-100/50 rounded-full blur-3xl -z-10"></div>

      <div class="mb-6">
        <span class="inline-block px-3 py-1 bg-orange-50 text-orange-600 text-[10px] font-bold rounded-full mb-4">Deep dive</span>
        <h2 class="text-3xl font-bold text-gray-900 mb-2">Explaining the Topic</h2>
        <p class="text-gray-500">"{@topic && @topic.title}"</p>
      </div>

      <div class="bg-orange-50/50 border border-orange-100 rounded-2xl p-8 mb-10 min-h-50 flex items-center justify-center">
        <%= if @loading == :explain do %>
          <div class="flex flex-col items-center gap-3">
            <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-orange-500"></div>
            <p class="text-gray-500 font-medium">Generating explanation...</p>
          </div>
        <% else %>
          <p class="text-gray-700 text-lg leading-relaxed text-center">
            {@topic && @topic.explanation}
          </p>
        <% end %>
      </div>

      <button
        phx-click="back_to_topic"
        class="w-full flex items-center justify-center gap-2 py-4 border-2 border-gray-100 rounded-2xl font-bold text-gray-600 hover:bg-gray-50 transition-all"
      >
        <.icon name="hero-arrow-left" class="w-5 h-5" />
        Got it! back to the topic
      </button>
    </div>
    """
  end

  attr :topic, :map
  attr :speak_countdown, :integer, default: 60
  attr :speak_timer_active, :boolean, default: false
  attr :is_recording, :boolean, default: false
  attr :audio_level, :integer, default: 0

  defp speak_step(assigns) do
    topic_title =
      cond do
        is_map(assigns.topic) and is_binary(assigns.topic[:title]) and assigns.topic[:title] != "" ->
          assigns.topic[:title]
        is_map(assigns.topic) and is_binary(assigns.topic["title"]) and assigns.topic["title"] != "" ->
          assigns.topic["title"]
        true ->
          "If you could mentor your past self for one day..."
      end

    topic_explanation =
      cond do
        is_map(assigns.topic) and is_binary(assigns.topic[:explanation]) -> assigns.topic[:explanation]
        is_map(assigns.topic) and is_binary(assigns.topic["explanation"]) -> assigns.topic["explanation"]
        true -> nil
      end

    assigns =
      assigns
      |> assign(:topic_question, topic_title)
      |> assign(:topic_explanation, topic_explanation)

    ~H"""
    <div
      id="audio-recorder"
      phx-hook="AudioRecorder"
      data-autostart="true"
      class="bg-white rounded-2xl p-6 border border-gray-100"
    >
      <h2 class="text-lg font-bold text-gray-900 text-center mb-2">"{@topic_question}"</h2>
      <%= if @topic_explanation && @topic_explanation != "" do %>
        <p class="text-sm text-gray-500 text-center mb-5 max-w-xl mx-auto">{@topic_explanation}</p>
      <% end %>

      <!-- Nested cream content block -->
      <div class="rounded-2xl p-6" style="background-color: #FAF6EE;">
        <div class="flex flex-col items-center mb-5">
          <div class="relative w-24 h-24 mb-1">
            <svg class="absolute inset-0 w-full h-full -rotate-90" viewBox="0 0 96 96">
              <circle cx="48" cy="48" r="42" fill="none" stroke="#F4ECDD" stroke-width="6" />
              <circle
                cx="48" cy="48" r="42"
                fill="none" stroke="#FF8B00" stroke-width="6"
                stroke-linecap="round"
                stroke-dasharray="263.89"
                stroke-dashoffset={263.89 * (1 - @speak_countdown / 60)}
                class="transition-all duration-1000"
              />
            </svg>
            <div class="absolute inset-0 flex flex-col items-center justify-center">
              <span class="text-2xl font-bold text-gray-900 leading-none">{@speak_countdown}</span>
              <span class="text-[9px] font-semibold tracking-wider text-gray-400 uppercase mt-1">Left</span>
            </div>
          </div>
          <span class="text-[10px] font-semibold tracking-[0.18em] text-gray-500 uppercase">Speaking now · Don't stop</span>
        </div>

        <!-- Waveform -->
        <div class="flex items-center justify-center gap-0.75 h-12 mb-5">
          <%= for {h, _i} <- Enum.with_index(jam_speak_bars(@is_recording, @audio_level)) do %>
            <div class="w-1 rounded-full" style={"height: #{h}%; background-color: #{if @is_recording, do: "#FF8B00", else: "#FFB36B"};"}></div>
          <% end %>
        </div>

        <!-- Metrics -->
        <div class="grid grid-cols-3 gap-3 mb-5">
          <.live_metric label="Pace" value="Natural" />
          <.live_metric label="Clarity" value="Strong" />
          <.live_metric label="Filler" value="1 um" />
        </div>

        <!-- Live transcript (browser preview; scoring uses the recording) -->
        <.live_transcript id="jam-live-transcript" recording?={@is_recording} class="mb-5" />

        <!-- Action buttons -->
        <div class="flex items-center justify-center gap-3">
          <%!-- <button
            phx-click="toggle_recording"
            class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg bg-white border border-gray-200 text-sm font-semibold text-gray-700 hover:bg-cream-50 transition"
          >
            <.icon name="hero-play" class="w-4 h-4" /> Resume
          </button> --%>
          <button
            phx-click="retry_recording"
            class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg bg-white border border-gray-200 text-sm font-semibold text-gray-700 hover:bg-cream-50 transition"
          >
            <.icon name="hero-arrow-path" class="w-4 h-4" /> Retry
          </button>
          <button
            phx-click="finish_recording"
            class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold transition"
            style="background-color: #DC2626;"
          >
            <span class="w-2.5 h-2.5 bg-white rounded-sm inline-block"></span> Submit Recording
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp jam_speak_bars(true, level) when is_integer(level) and level > 0 do
    base = level
    for i <- 0..52 do
      variation = :erlang.phash2({i, base}, 30) - 15
      min(95, max(15, base + variation))
    end
  end

  defp jam_speak_bars(true, _) do
    [35, 55, 40, 65, 45, 70, 50, 60, 38, 68, 42, 58, 48, 62, 36, 55, 44, 66, 40, 52, 46, 64, 38, 56, 50, 42, 60, 38, 52, 46, 40, 58, 44, 36, 50, 42, 48, 38, 56, 44, 60, 38, 52, 46, 64, 40, 58, 50, 36, 54, 42, 46, 38]
  end

  defp jam_speak_bars(false, _),
    do: [10, 14, 18, 12, 16, 20, 14, 10, 18, 22, 14, 12, 18, 14, 16, 22, 12, 16, 18, 14, 16, 12, 22, 16, 18, 14, 16, 12, 14, 22, 14, 18, 16, 12, 16, 14, 18, 16, 12, 16, 18, 14, 12, 20, 14, 18, 16, 12, 18, 14, 16, 18, 14]

  defp live_metric(assigns) do
    ~H"""
    <div class="text-center p-4 bg-gray-50 rounded-2xl border border-gray-100/50">
      <span class="text-[10px] font-bold text-gray-400 uppercase block mb-1">{@label}</span>
      <span class="text-sm font-bold text-gray-900 uppercase">{@value}</span>
    </div>
    """
  end

  attr :topic, :map
  attr :feedback, :map
  attr :show_detailed_feedback, :boolean, default: false
  attr :loading, :atom, default: nil
  attr :error, :string, default: nil
  attr :error_title, :string, default: nil
  attr :error_retry_event, :string, default: nil
  attr :tenant_alias, :string, default: nil
  attr :jam_session, :map, default: nil
  attr :mic_verified, :boolean, default: false
  attr :mic_permission, :string, default: nil
  attr :mic_checking, :boolean, default: false

  defp feedback_step(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @loading == :processing do %>
        <!-- Processing/Loading state -->
        <div class="bg-white rounded-3xl border border-gray-100 p-12 shadow-sm text-center">
          <div class="animate-spin rounded-full h-16 w-16 border-b-2 border-orange-500 mx-auto mb-6"></div>
          <h3 class="text-2xl font-bold text-gray-900 mb-2">Analyzing your speech...</h3>
          <p class="text-gray-500">Transcribing audio and generating AI feedback</p>
        </div>
      <% else %>
        <%= if @feedback == nil and @error not in [nil, ""] do %>
          <!-- No speech detected / word count too low — show error and let the student retry -->
          <div class="bg-white rounded-3xl border border-red-100 p-10 shadow-sm text-center space-y-4">
            <div class="w-16 h-16 rounded-full bg-red-50 flex items-center justify-center mx-auto">
              <.icon name="hero-microphone-slash" class="w-8 h-8 text-red-400" />
            </div>
            <h3 class="text-xl font-bold text-gray-900">We didn't catch your speech</h3>
            <p class="text-gray-500 max-w-sm mx-auto">{@error}</p>
            <button
              phx-click="retry_recording"
              class="inline-flex items-center gap-2 px-6 py-3 bg-orange-500 hover:bg-orange-600 text-white font-bold rounded-2xl transition-all shadow-lg shadow-orange-200"
            >
              <.icon name="hero-arrow-path" class="w-5 h-5" />
              Try Again
            </button>
          </div>
        <% else %>
        <div id="jam-report-source" class="space-y-6">
          <!-- Header Card -->
          <div class="bg-linear-to-r from-teal-50 to-orange-50 rounded-3xl p-8 border border-gray-100 flex items-center justify-between relative overflow-hidden">
             <!-- XP Badge -->
             <div class="absolute top-6 left-8">
               <span class="px-3 py-1 bg-teal-500 text-white text-[10px] font-bold rounded-full">JAM complete +80 XP</span>
             </div>

             <div class="mt-8">
               <h3 class="text-3xl font-bold text-gray-900 mb-2">
                 <%= if (@feedback && @feedback.overall_score || 0) >= 80, do: "You spoke with real presence", else: "Good effort! Keep practicing" %>
               </h3>
               <p class="text-gray-500 max-w-md">{@feedback && @feedback.summary}</p>
             </div>

             <div class="relative w-32 h-32 flex flex-col items-center justify-center bg-white rounded-full shadow-lg border-8 border-orange-100">
               <span class="text-4xl font-black text-gray-900 leading-none">{(@feedback && @feedback.overall_score) || 0}</span>
               <span class="text-[10px] font-bold text-gray-400 uppercase tracking-tighter">Overall score / 100</span>
             </div>
          </div>

          <!-- What the AI actually scored -->
          <.heard_transcript
            id="jam-heard-transcript"
            transcript={@feedback && @feedback[:transcript]}
            note="Transcribed from your recording — this is the text your JAM was scored from."
          />

          <!-- Dimension Breakdown -->
          <div class="bg-white rounded-3xl p-8 border border-gray-100 shadow-sm">
            <h4 class="text-[11px] font-bold tracking-wider text-gray-400 uppercase mb-8">5-DIMENSION BREAKDOWN</h4>
            <div class="space-y-6">
              <.dimension_bar label="Fluency" score={(@feedback && @feedback.scores.fluency) || 0} />
              <.dimension_bar label="Clarity" score={(@feedback && @feedback.scores.clarity) || 0} />
              <.dimension_bar label="Confidence" score={(@feedback && @feedback.scores.fluency) || 0} />
              <.dimension_bar label="Structure" score={(@feedback && @feedback.scores.structure) || 0} />
              <.dimension_bar label="Impact" score={(@feedback && @feedback.scores.relevance) || 0} />
            </div>
          </div>
        </div>

        <.error_card
          :if={@error}
          title={@error_title}
          error_message={@error}
          retry_event={@error_retry_event}
          class="mb-4"
        />

        <%!-- Retake needs the mic too, so the state is spelled out here rather
        than as a modal over the student's results. --%>
        <.mic_status verified={@mic_verified} state={@mic_permission} checking={@mic_checking} />

        <!-- Bottom Action Buttons -->
        <VyaasaCampusWeb.Components.Student.AssessmentFooter.assessment_footer
          next_event="back_to_dashboard"
          restart_event="start_another"
          restart_label="Retake Assessment"
          dashboard_event="back_to_dashboard"
          class="pt-6"
        />
        <% end %>
      <% end %>
    </div>
    """
  end

  defp dimension_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-6">
      <span class="text-sm font-semibold text-gray-600 w-24">{@label}</span>
      <div class="flex-1 h-3 bg-gray-50 rounded-full overflow-hidden border border-gray-100">
        <div class="h-full bg-orange-500 rounded-full" style={"width: #{@score}%"}></div>
      </div>
      <span class="text-xs font-bold text-gray-400 w-12 text-right">{@score} / 100</span>
    </div>
    """
  end

  defp right_card_insights(assigns) do
    ~H"""
    <div class="bg-teal-50/30 border border-teal-100 rounded-3xl p-6">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-arrow-trending-up" class="w-4 h-4 text-teal-600" />
        <h4 class="text-[11px] font-bold tracking-wider text-teal-600 uppercase">VYAASA INSIGHTS</h4>
      </div>
      <ul class="space-y-3">
        <%= for point <- (@feedback && @feedback.strengths) || ["Strong story-led opener", "Nice rhythm with pauses", "Confident, varied tone"] do %>
          <li class="flex items-center gap-2">
            <span class="w-1.5 h-1.5 rounded-full bg-teal-500"></span>
            <span class="text-sm font-semibold text-gray-700">{point}</span>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp right_card_improve_next(assigns) do
    ~H"""
    <div class="bg-orange-50/50 border border-orange-100 rounded-3xl p-6">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-sparkles" class="w-4 h-4 text-orange-500" />
        <h4 class="text-[11px] font-bold tracking-wider text-orange-600 uppercase">IMPROVE NEXT TIME</h4>
      </div>
      <ul class="space-y-3">
        <%= for point <- (@feedback && @feedback.improvements) || ["End with a stronger one-liner", "Reduce 2 filler \"you knows\"", "Slow first 5 seconds for hook"] do %>
          <li class="flex items-center gap-2">
            <span class="w-1.5 h-1.5 rounded-full bg-orange-500"></span>
            <span class="text-sm font-semibold text-gray-700">{point}</span>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp format_countdown(seconds) when seconds >= 0 do
    mins = div(seconds, 60)
    secs = rem(seconds, 60)

    "#{String.pad_leading(Integer.to_string(mins), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_countdown(_), do: "00:00"

  # Closing the tab / navigating away mid-session must not leave the JAM
  # session stuck non-terminal forever — enqueue the same finalize job the
  # abandonment sweep would eventually use, so this and the sweep share one
  # completion path (Jam.force_complete/2) regardless of which one gets there
  # first. Guarded on connected?/1 (LiveView's disconnected static-render pass
  # would otherwise fire this on every page load, before the student even
  # starts) — evaluation itself never runs inline here (LLM-backed, no place
  # blocking process shutdown), only a lightweight job enqueue.
  @impl true
  def terminate(_reason, socket) do
    with true <- connected?(socket),
         %{id: session_id} <- socket.assigns[:jam_session],
         tenant_schema when is_binary(tenant_schema) <- socket.assigns[:tenant_schema] do
      VyaasaCampus.Jobs.AssessmentFinalizer.enqueue("jam", session_id, tenant_schema)
    end

    :ok
  end
end
