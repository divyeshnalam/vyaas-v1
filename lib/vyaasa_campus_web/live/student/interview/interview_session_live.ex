defmodule VyaasaCampusWeb.Student.Interview.InterviewSessionLive do
  @moduledoc """
  LiveView for the AI-Led Resume Interview session flow.
  Native Elixir engine — no Python service, no WebSocket.

  Two-step wizard: Initialize Interview → Interview → Results.
  Engine state (`socket.assigns.session_state`) is carried turn-to-turn;
  LLM calls run inside `Task.Supervisor` children so the LiveView process
  stays responsive.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.Contexts.{Interview, Tenants, StudentAts}
  alias VyaasaCampus.Contexts.AtsUpload
  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Student.MicGate
  import VyaasaCampusWeb.Student.Interview.Components

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
          do: VyaasaCampus.AI.Tracing.put_metadata(%{student_id: current_user.id, module: "interview", tenant: tenant_schema})

        ats_data = StudentAts.get_by_student_id(current_user.id, tenant_schema)
        resume_info = build_resume_info(ats_data)

        user_info = %{
          name: "#{current_user.first_name} #{current_user.last_name}",
          role: "Student",
          email: current_user.email,
          profile_picture_url: ats_data && ats_data.profile_picture_url
        }

        socket =
          socket
          |> assign(:tenant_alias, tenant_alias)
          |> assign(:tenant_schema, tenant_schema)
          |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: tenant_alias))
          |> assign(:current_scope, :student)
          |> assign(:user_info, user_info)
          |> assign(:page_title, "Interactive Session")
          |> assign(:resume_info, resume_info)
          |> assign(:ats_data, ats_data)
          |> assign_initial_state()
          |> mount_mic_gate()
          |> maybe_restore_completed_session(current_user.id, tenant_schema)

        # No fullscreen gate when landing straight on a completed result.
        socket = assign(socket, :require_fullscreen, socket.assigns.current_step != :results)

        {:ok, socket}
    end
  end

  defp interview_violation_message("fullscreen_exit"),
    do: "You left full-screen mode. This is recorded and shared with your evaluator."

  defp interview_violation_message("window_blur"),
    do: "You switched away from the session. This is recorded and shared with your evaluator."

  defp interview_violation_message(_),
    do: "You switched tabs / left the session. This is recorded and shared with your evaluator."

  defp assign_initial_state(socket) do
    socket
    |> assign(:current_step, :initialize)
    |> assign(:interview_phase, :welcome)
    |> assign(:interview_session, nil)
    |> assign(:session_state, nil)
    |> assign(:session_id, nil)
    # Question state
    |> assign(:current_question, nil)
    |> assign(:current_question_number, 0)
    |> assign(:total_questions, 5)
    |> assign(:questions_answered, [])
    |> assign(:current_transcript, nil)
    |> assign(:pending_question_key, nil)
    |> assign(:greeting_text, nil)
    # Recording
    |> assign(:is_recording, false)
    |> assign(:audio_level, 0)
    # Results
    |> assign(:overall_score, nil)
    |> assign(:final_report, nil)
    |> assign(:strengths, [])
    |> assign(:improvements, [])
    |> assign(:expanded_question, nil)
    # Loading / error
    |> assign(:loading, nil)
    |> assign(:error, nil)
    |> assign(:error_title, "Something went wrong")
    |> assign(:async_ref, nil)
    # Timer
    |> assign(:remaining_time, 600)
    |> assign(:timer_active, false)
    # Proctoring (log-only for a live voice conversation)
    |> assign(:require_fullscreen, true)
    |> assign(:violation_count, 0)
    |> assign(:show_integrity_warning, false)
    |> assign(:integrity_message, nil)
    |> assign(:mic_grace_until, System.monotonic_time(:millisecond))
  end

  defp maybe_restore_completed_session(socket, student_id, tenant_schema) do
    case Interview.get_completed_interviews(student_id, tenant_schema) do
      [latest | _] ->
        questions = get_in(latest.questions_data, ["questions"]) || []

        strengths =
          if latest.strengths == [] and latest.final_report do
            extract_list_from_report(latest.final_report, "What Went Well")
          else
            latest.strengths || []
          end

        improvements =
          if latest.improvements == [] and latest.final_report do
            extract_list_from_report(latest.final_report, "Areas for Improvement")
          else
            latest.improvements || []
          end

        socket
        |> assign(:interview_session, latest)
        |> assign(:current_step, :results)
        |> assign(:interview_phase, :results)
        |> assign(:overall_score, latest.overall_score)
        |> assign(:final_report, latest.final_report)
        |> assign(:strengths, strengths)
        |> assign(:improvements, improvements)
        |> assign(:questions_answered, questions)

      _ ->
        socket
    end
  end

  defp build_resume_info(nil), do: %{filename: nil, size: nil}

  defp build_resume_info(ats_data) do
    resume_url = ats_data.resume_url

    if resume_url do
      filename = Path.basename(resume_url)
      file_path = AtsUpload.get_resume_file_path(resume_url)

      size =
        if file_path do
          case File.stat(file_path) do
            {:ok, %{size: bytes}} -> format_file_size(bytes)
            _ -> ""
          end
        else
          ""
        end

      %{filename: filename, size: size, path: file_path}
    else
      %{filename: nil, size: nil, path: nil}
    end
  end

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  # Failure while (re)starting an interview: if a completed report is still
  # on screen (retry triggered from :results), keep it visible and layer the
  # error on top — same pattern as the MCQ retry flow. Only fall back to the
  # :initialize step's :welcome phase when there's no report to show behind it.
  defp show_new_interview_error(socket, message), do: show_new_interview_error(socket, "Something went wrong", message)

  defp show_new_interview_error(socket, title, message) do
    socket =
      socket
      |> assign(:loading, nil)
      |> assign(:error_title, title)
      |> assign(:error, message)

    if socket.assigns.current_step == :results do
      socket
    else
      assign(socket, :interview_phase, :welcome)
    end
  end

  # ── Events ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("start_interview", _params, socket) do
    # The interview is a spoken conversation — confirm the mic works before we
    # spend time indexing the resume and open a session.
    case require_mic(socket, "start_interview") do
      {:gated, socket} -> {:noreply, socket}
      {:ok, socket} -> do_start_interview(socket)
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
  def handle_event("begin_interview", _params, socket) do
    case require_mic(socket, "begin_interview") do
      {:gated, socket} -> {:noreply, socket}
      {:ok, socket} -> do_begin_interview(socket)
    end
  end

  @impl true
  def handle_event("toggle_recording", _params, socket) do
    if socket.assigns.is_recording do
      {:noreply, push_event(socket, "stop_recording", %{})}
    else
      # Mic grace: the permission/OS popup steals focus on the first record —
      # ignore focus loss for ~8s so it doesn't log a false strike.
      {:noreply,
       socket
       |> assign(:mic_grace_until, System.monotonic_time(:millisecond) + 8_000)
       # Stop the question TTS the instant the student starts answering.
       |> push_event("stop_audio", %{})
       |> push_event("start_recording", %{})}
    end
  end

  @impl true
  def handle_event("integrity_violation", %{"type" => type}, socket) do
    cond do
      # Suppress the mic-popup focus-loss window.
      System.monotonic_time(:millisecond) < socket.assigns.mic_grace_until ->
        {:noreply, socket}

      # Enforced only once the interview is underway (after Start/Begin).
      socket.assigns.current_step != :interview ->
        {:noreply, socket}

      true ->
        count =
          case socket.assigns.interview_session do
            %{session_token: token} when is_binary(token) ->
              case Interview.record_violation(token, type, socket.assigns.tenant_schema) do
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
          {:noreply, assign(socket, :integrity_message, interview_violation_message(type))}
        end
    end
  end

  @impl true
  def handle_event("dismiss_integrity_warning", _params, socket) do
    {:noreply, assign(socket, :show_integrity_warning, false)}
  end

  @impl true
  # "Retry" — throw away the in-progress recording and let the student record
  # again, instead of stopping+submitting the answer (Vya-028).
  def handle_event("discard_recording", _params, socket) do
    {:noreply,
     socket
     |> assign(:is_recording, false)
     |> push_event("discard_recording", %{})}
  end

  @impl true
  def handle_event("recording_started", _params, socket) do
    {:noreply, assign(socket, :is_recording, true)}
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
  def handle_event("audio_recorded", %{"audio_data" => audio_base64}, socket) do
    socket =
      socket
      |> assign(:is_recording, false)
      |> assign(:interview_phase, :processing)

    run_transcription_async(audio_base64, socket.assigns.session_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_question_detail", %{"question_number" => q_num_str}, socket) do
    q_num = String.to_integer(q_num_str)
    current = socket.assigns.expanded_question
    new_expanded = if current == q_num, do: nil, else: q_num
    {:noreply, assign(socket, :expanded_question, new_expanded)}
  end

  @impl true
  def handle_event("resend_report", _params, socket) do
    case socket.assigns[:interview_session] do
      %{id: id} ->
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:interview, id, socket.assigns.tenant_schema)
        {:noreply, put_flash(socket, :info, "Your interview feedback report is on its way to your email ✉️")}

      _ ->
        {:noreply, put_flash(socket, :error, "No completed interview to email yet.")}
    end
  end

  # Lets a student who has a completed interview start a genuinely NEW
  # attempt — distinct from "retry_interview" below, which wipes and reuses
  # the SAME session row (meant for recovering a technically-failed
  # attempt, not for taking another attempt after a real completion).
  # Bound to both the results page's "Retake" button and the :initialize
  # screen's error card. When fired from :results, the new session is
  # attempted right away and the completed report stays visible (with any
  # error layered on top) until we know whether it worked — same pattern as
  # the MCQ retry flow — instead of bouncing to the start screen first. The
  # old report is only cleared, and the view only hops to :initialize, once
  # a new session actually comes back (see handle_info({:session_ready, ...})).
  @impl true
  def handle_event("start_new_interview", _params, socket) do
    ats_data = socket.assigns.ats_data

    cond do
      is_nil(ats_data) or is_nil(ats_data.resume_url) ->
        {:noreply, show_new_interview_error(socket, "No resume found. Please upload a resume first.")}

      ats_data.status != "completed" ->
        {:noreply,
         show_new_interview_error(socket, "Your resume is still being analysed. Please try again in a moment.")}

      true ->
        prefix = socket.assigns.tenant_schema
        current_user = socket.assigns.current_user
        resume_file_path = AtsUpload.get_resume_file_path(ats_data.resume_url)

        socket = assign(socket, :error, nil)

        run_start_session_async(prefix, %{
          student_id: current_user.id,
          tenant_id: current_user.tenant_id,
          resume_url: ats_data.resume_url,
          resume_file_path: resume_file_path
        })

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("retry_interview", _params, socket) do
    prefix = socket.assigns.tenant_schema
    session = socket.assigns.interview_session

    if session, do: Interview.retry_interview(session, prefix)

    socket =
      socket
      |> assign_initial_state()
      |> assign(:resume_info, build_resume_info(socket.assigns.ats_data))
      |> assign(:ats_data, socket.assigns.ats_data)

    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_different_resume", _params, socket) do
    {:noreply, put_flash(socket, :info, "Please update your resume in the profile completion section.")}
  end

  @impl true
  def handle_event("back_to_dashboard", _params, socket) do
    {:noreply, redirect(socket, to: "/student/#{socket.assigns.tenant_alias}/dashboard")}
  end

  @impl true
  def handle_event("go_to_dashboard", _params, socket) do
    {:noreply, redirect(socket, to: "/student/#{socket.assigns.tenant_alias}/dashboard")}
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Logged out successfully")
     |> redirect(to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}
  end

  @impl true
  def handle_event("show_coming_soon", _params, socket) do
    {:noreply, put_flash(socket, :info, "Settings coming soon!")}
  end

  @impl true
  def handle_event("retry", _params, socket) do
    {:noreply, assign(socket, :error, nil)}
  end

  # ── Async engine/transcription helpers ─────────────────────────────

  defp run_start_session_async(prefix, attrs) do
    lv_pid = self()

    Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
      # start_session/2 (attempt-guard gated, purely in-memory — no DB write)
      # must run BEFORE create_interview_session/2 (the DB insert). Reversed,
      # a rejected attempt still left an orphaned interview_sessions row
      # behind — which is exactly the row AttemptGuard counts to decide the
      # NEXT check, so every click (rejected or not) silently inflated the
      # count the limit is supposed to be checked against.
      result =
        with {:ok, session} <- Interview.start_session(attrs.student_id, prefix),
             {:ok, db_session} <- Interview.create_interview_session(attrs, prefix),
             {:ok, db_session} <-
               Interview.mark_initialized(
                 db_session,
                 %{python_session_id: session.session_id, candidate_name: session.candidate_name},
                 prefix
               ) do
          {:ok, db_session, session}
        end

      send(lv_pid, {:session_ready, result})
    end)

    :ok
  end

  defp run_engine_async(socket, fun) when is_function(fun, 1) do
    state = socket.assigns.session_state
    lv_pid = self()

    Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
      result = fun.(state)
      send(lv_pid, {:engine_result, result})
    end)

    :ok
  end

  # `session_id` is passed explicitly so the Whisper span joins this session's
  # Opik thread — the Task is a fresh process with no thread id of its own.
  defp run_transcription_async(audio_base64, session_id) do
    lv_pid = self()

    Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
      case Interview.transcribe_audio(audio_base64, thread_id: session_id) do
        {:ok, text} -> send(lv_pid, {:transcribed, text})
        {:error, reason} -> send(lv_pid, {:transcription_failed, reason})
      end
    end)

    :ok
  end

  # ── Async results ──────────────────────────────────────────────────

  @impl true
  def handle_info({:session_ready, {:ok, db_session, session}}, socket) do
    greeting = session.greeting

    # Only now — once the new session is confirmed — do we drop the old
    # completed report and move off the :results step (see
    # start_new_interview/3 above).
    socket =
      if socket.assigns.current_step == :results do
        socket
        |> assign_initial_state()
        |> assign(:resume_info, build_resume_info(socket.assigns.ats_data))
        |> assign(:ats_data, socket.assigns.ats_data)
      else
        socket
      end

    socket =
      socket
      |> assign(:interview_session, db_session)
      |> assign(:session_id, session.session_id)
      |> assign(:session_state, session.session_state)
      |> assign(:total_questions, session.max_questions)
      |> assign(:remaining_time, (db_session.max_duration_minutes || 10) * 60)
      |> assign(:interview_phase, :ready)
      |> assign(:greeting_text, greeting[:text])
      |> assign(:loading, nil)
      |> assign(:error, nil)
      # Re-check the mic on the "Ready to begin" screen — still windowed, so the
      # browser can prompt, and the student learns about a blocked mic here
      # rather than through a failed recording (and a strike) mid-interview.
      |> probe_mic()

    socket = maybe_push_tts(socket, greeting[:spoken], "greeting")
    {:noreply, socket}
  end

  # AttemptGuard.check returns a 3-tuple ({:error, :attempt_limit_reached,
  # %{used:, limit:, granted:}}) on rejection — the 2-tuple clause below
  # never matched it, so this fell through to the catch-all handle_info and
  # was silently dropped: the student just saw the loading spinner hang
  # forever with no explanation, even once they'd genuinely hit the limit.
  def handle_info({:session_ready, {:error, :attempt_limit_reached, _details}}, socket) do
    {:noreply,
     show_new_interview_error(
       socket,
       "Out of attempts",
       "You've used all your available interview attempts. Please contact your college admin to request more."
     )}
  end

  def handle_info({:session_ready, {:error, reason}}, socket) do
    Logger.error("Interview start failed: #{inspect(reason)}")

    {:noreply, show_new_interview_error(socket, "Something went wrong", format_error(reason))}
  end

  def handle_info({:transcribed, text}, socket) do
    trimmed = String.trim(text || "")

    cond do
      trimmed == "" ->
        {:noreply,
         socket
         |> assign(:interview_phase, :question)
         |> assign(:error, "We couldn't hear anything — please try recording again.")}

      true ->
        socket =
          socket
          |> assign(:current_transcript, trimmed)
          |> assign(:interview_phase, :evaluating)

        run_engine_async(socket, fn state -> Interview.submit_answer(state, trimmed) end)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:transcription_failed, reason}, socket) do
    Logger.error("Interview transcription failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:interview_phase, :question)
     |> assign(:error, "Couldn't transcribe your response. Please try again.")}
  end

  @impl true
  def handle_info({:engine_result, {:ok, new_state, response}}, socket) do
    {:noreply, apply_engine_response(socket, new_state, response)}
  end

  @impl true
  def handle_info({:engine_result, {:error, reason}}, socket) do
    Logger.error("Interview engine error: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:loading, nil)
     |> assign(:interview_phase, :question)
     |> assign(:error, format_error(reason))}
  end

  # TTS results from the async worker (optional audio). Drop stale audio: if the
  # student already moved on, the key no longer matches the current question.
  @impl true
  def handle_info({:tts_ready, audio_key, audio_base64}, socket) do
    if audio_key == socket.assigns[:current_audio_key] do
      {:noreply,
       socket
       |> reveal_if_pending(audio_key)
       |> push_event("play_audio", %{
         audio_data: audio_base64,
         audio_type: "wav",
         audio_key: audio_key
       })}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:tts_fallback, audio_key, text}, socket) do
    if audio_key == socket.assigns[:current_audio_key] do
      {:noreply,
       socket
       |> reveal_if_pending(audio_key)
       |> push_event("speak_text", %{text: text, audio_key: audio_key})}
    else
      {:noreply, socket}
    end
  end

  # Safety net: reveal the question even if its narration is slow or never arrives.
  @impl true
  def handle_info({:reveal_question, key}, socket) do
    {:noreply, reveal_if_pending(socket, key)}
  end

  # Reveal a question that's been held on the spinner waiting for its audio.
  defp reveal_if_pending(socket, key) do
    if socket.assigns[:pending_question_key] == key do
      socket
      |> assign(:interview_phase, :question)
      |> assign(:pending_question_key, nil)
    else
      socket
    end
  end

  @impl true
  def handle_info(:interview_tick, socket) do
    if socket.assigns.timer_active do
      remaining = socket.assigns.remaining_time - 1

      if remaining <= 0 do
        {:noreply, assign(socket, :remaining_time, 0) |> assign(:timer_active, false)}
      else
        schedule_tick()
        {:noreply, assign(socket, :remaining_time, remaining)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Engine response → socket ───────────────────────────────────────

  defp apply_engine_response(
         socket,
         new_state,
         %{stage: :interview, next_question: question, q_index: q_idx} = response
       ) do
    prefix = socket.assigns.tenant_schema
    session = socket.assigns.interview_session
    q_num = q_idx + 1

    # Persist the question and any completed answer from the previous turn.
    # In an :interview response, `q_idx` is the index of the UPCOMING question,
    # while `evaluation` belongs to the question asked on the PREVIOUS turn
    # (index `q_idx - 1`). Record the answer against that previous question so
    # the stored question numbers stay 1..N with no gaps or duplicates.
    {socket, session} =
      if evaluation = response[:evaluation] do
        record_answered_question(socket, session, prefix, q_idx - 1, evaluation, new_state)
      else
        # First question: mark interview as "interviewing" and start the timer.
        case Interview.start_interview(session, prefix) do
          {:ok, updated} ->
            if connected?(socket), do: schedule_tick()
            {assign(socket, :timer_active, true), updated}

          _ ->
            {socket, session}
        end
      end

    question_data = %{"question_number" => q_num, "question_text" => question}

    session =
      case Interview.add_question(session, question_data, prefix) do
        {:ok, updated} -> updated
        _ -> session
      end

    key = "question_#{q_num}"

    socket =
      socket
      |> assign(:interview_session, session)
      |> assign(:session_state, new_state)
      |> assign(:current_question, %{number: q_num, text: question})
      |> assign(:current_question_number, q_num)
      # Hold on the "reflecting" spinner (don't reveal the question yet) while its
      # narration is synthesised, so the question appears TOGETHER with its audio
      # instead of sitting silent for ~5s. A safety timer reveals it regardless if
      # TTS is slow or fails, so the student is never stuck on the spinner.
      |> assign(:interview_phase, :evaluating)
      |> assign(:pending_question_key, key)
      |> assign(:loading, nil)
      |> assign(:current_transcript, nil)

    if connected?(socket), do: Process.send_after(self(), {:reveal_question, key}, 6_000)

    maybe_push_tts(socket, question, key)
  end

  defp apply_engine_response(socket, new_state, %{stage: :done} = response) do
    prefix = socket.assigns.tenant_schema
    session = socket.assigns.interview_session
    q_idx = response[:q_index] - 1
    evaluation = response[:evaluation]

    {socket, session} =
      if evaluation do
        record_answered_question(socket, session, prefix, q_idx, evaluation, new_state)
      else
        {socket, session}
      end

    metrics = response[:metrics] || %{}
    report_md = response[:overall] || ""
    avg_score = metrics["average_score"] || Interview.average_question_score(socket.assigns.questions_answered)
    strengths = extract_list_from_report(report_md, "What Went Well")
    improvements = extract_list_from_report(report_md, "Areas for Improvement")

    # overall_score here is the plain-average fallback; complete_interview/3
    # publishes to AI8 and overrides it with the super-admin-weighted module
    # score when available (same for this live path and force_complete/2).
    attrs = %{
      overall_score: round_score(avg_score),
      final_report: report_md,
      session_summary: metrics,
      strengths: strengths,
      improvements: improvements
    }

    session =
      case Interview.complete_interview(session, attrs, prefix) do
        {:ok, updated} -> updated
        _ -> session
      end

    socket =
      socket
      |> assign(:interview_session, session)
      |> assign(:session_state, new_state)
      |> assign(:overall_score, session.overall_score)
      |> assign(:final_report, report_md)
      |> assign(:strengths, strengths)
      |> assign(:improvements, improvements)
      |> assign(:interview_phase, :results)
      |> assign(:current_step, :results)
      |> assign(:timer_active, false)
      |> assign(:loading, nil)

    if thanks = response[:thanks_text] do
      maybe_push_tts(socket, thanks, "thanks")
    else
      socket
    end
  end

  # Content moderation: first violation warns and re-asks the same question.
  # Record it as an integrity flag too (audited even if they don't re-offend).
  defp apply_engine_response(socket, new_state, %{stage: :warning, message: message} = response) do
    count = response[:warning_count] || 1

    session =
      case socket.assigns[:interview_session] do
        %{} = s ->
          case Interview.add_integrity_flag(
                 s,
                 "Content warning ##{count} — inappropriate language (interview)",
                 socket.assigns.tenant_schema
               ) do
            {:ok, updated} -> updated
            _ -> s
          end

        _ ->
          socket.assigns[:interview_session]
      end

    socket
    |> assign(:interview_session, session)
    |> assign(:session_state, new_state)
    |> assign(:interview_phase, :question)
    |> assign(:loading, nil)
    |> assign(:current_transcript, nil)
    |> put_flash(:error, message)
  end

  # Second violation terminates the session unscored — persist an integrity flag
  # so the tenant-admin dashboard surfaces it.
  defp apply_engine_response(socket, _new_state, %{stage: :terminated, message: message}) do
    case socket.assigns[:interview_session] do
      %{} = session ->
        Interview.mark_terminated(
          session,
          ["Interview terminated — repeated inappropriate or unethical responses (content moderation)"],
          socket.assigns.tenant_schema
        )

      _ ->
        :ok
    end

    socket
    |> assign(:timer_active, false)
    |> assign(:loading, nil)
    |> put_flash(:error, message)
    |> redirect(to: "/student/#{socket.assigns.tenant_alias}/dashboard")
  end

  defp apply_engine_response(socket, new_state, _response) do
    assign(socket, :session_state, new_state) |> assign(:loading, nil)
  end

  defp record_answered_question(socket, session, prefix, q_idx, evaluation, _new_state) do
    q_num = q_idx + 1
    current_q = socket.assigns.current_question
    q_text = if current_q, do: current_q.text, else: ""
    transcript = socket.assigns.current_transcript || ""

    answer_data = %{
      "transcript" => transcript,
      "score" => evaluation["score"] || 0,
      "evaluation" => evaluation["evaluation"] || "",
      "feedback" => evaluation["feedback"] || "",
      "dimensions" => evaluation["dimensions"] || %{},
      "strengths" => evaluation["strengths"] || [],
      "weaknesses" => evaluation["weaknesses"] || []
    }

    session =
      case Interview.update_question_answer(session, q_num, answer_data, prefix) do
        {:ok, updated} -> updated
        _ -> session
      end

    entry = Map.merge(answer_data, %{"question_number" => q_num, "question_text" => q_text})
    answered = socket.assigns.questions_answered ++ [entry]

    {assign(socket, :questions_answered, answered), session}
  end

  # ── TTS (async; silent on failure) ─────────────────────────────────

  defp maybe_push_tts(socket, text, audio_key) do
    cleaned = (text || "") |> String.trim()

    if cleaned == "" do
      socket
    else
      lv_pid = self()
      # Link the TTS span to this session's Opik thread (see run_transcription_async/2).
      session_id = socket.assigns[:session_id]

      Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
        case GroqClient.text_to_speech(cleaned, thread_id: session_id) do
          {:ok, audio_b64} -> send(lv_pid, {:tts_ready, audio_key, audio_b64})
          {:error, _} -> send(lv_pid, {:tts_fallback, audio_key, cleaned})
        end
      end)

      # Stop whatever is currently reading immediately (the previous question's
      # audio may still be playing), and record which key is now current so a
      # late-arriving TTS for an old question is dropped instead of played.
      socket
      |> assign(:current_audio_key, audio_key)
      |> push_event("stop_audio", %{})
    end
  end

  # ── Render ─────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    # Full screen required only once the interview is underway (after Start).
    assigns = assign(assigns, :require_fullscreen, assigns.current_step == :interview)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="toast-container" phx-hook="ToastContainer" class="fixed top-4 right-4 z-50 space-y-2"></div>

      <div class="min-h-screen bg-cream-50 flex" id="interview-container" phx-hook="AssessmentIntegrity"
        data-require-fullscreen={to_string(@require_fullscreen)}>
        <div :if={@require_fullscreen} id="fullscreen-gate" phx-update="ignore"
          class="fixed inset-0 z-100 bg-gray-900/95 flex items-center justify-center p-6 text-center">
          <div class="max-w-md">
            <.icon name="hero-lock-closed" class="w-12 h-12 text-orange-400 mx-auto mb-4" />
            <h2 class="text-xl font-bold text-white mb-2">Secure full-screen mode</h2>
            <p class="text-sm text-gray-300 mb-6">
              This is a proctored session that runs in full screen. Leaving full screen or switching
              windows while you speak is recorded and shared with your evaluator.
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

        <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar :if={@current_step != :interview} current_section="interview" tenant_alias={@tenant_alias} student_name={@user_info.name} />

        <div class="flex-1 flex flex-col">
          <VyaasaCampusWeb.Components.Student.HeaderComponent.header
            user_info={@user_info}
            tenant_alias={@tenant_alias}
            page_title=""
            exit_href={"/student/#{@tenant_alias}/dashboard"}
            focus?={@current_step == :interview}
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

          <main class="flex-1 bg-cream-50 overflow-auto">
            <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-300 mx-auto w-full">
              <!-- Page header -->
              <div class="flex items-start gap-3 mb-6">
                <div
                  class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
                  style="background-color: #FFE9D2;"
                >
                  <.icon name="hero-microphone" class="w-5 h-5" style="color: #B85F00;" />
                </div>
                <div>
                  <p class="text-[11px] font-semibold tracking-[0.18em] uppercase" style="color: #FF8B00;">Communication · EQ · Leadership</p>
                  <h1 class="text-2xl font-bold text-gray-900">Vyaasa Introduction Session</h1>
                  <p class="text-sm text-gray-500 mt-0.5">Speak naturally. Vyaasa is listening with empathy, with out judgment.</p>
                </div>
              </div>

              <%= if @error && @current_step == :initialize do %>
                <.error_card
                  title={@error_title}
                  error_message={@error}
                  retry_event="start_interview"
                  class="mb-4"
                />
              <% end %>

              <%= if @error && @current_step not in [:initialize, :results] do %>
                <div class="mb-4 rounded-lg p-3 flex items-center justify-between" style="background-color: #FEF2F2; border: 1px solid #FECACA;">
                  <div class="flex items-center gap-2">
                    <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-red-500" />
                    <span class="text-red-700 text-sm">{@error}</span>
                  </div>
                  <button phx-click="retry" class="text-red-600 hover:text-red-800 text-xs font-medium">Dismiss</button>
                </div>
              <% end %>

              <%= if @current_step == :interview do %>
                <div class="flex justify-end mb-3">
                  <button
                    phx-click="back_to_dashboard"
                    data-confirm="Leave the interview and return to your dashboard? Progress in this session won't be saved."
                    class="inline-flex items-center gap-1.5 text-xs font-medium text-gray-500 hover:text-gray-800 transition"
                  >
                    <%!-- <.icon name="hero-arrow-left-on-rectangle" class="w-4 h-4" /> Exit to Dashboard --%>
                  </button>
                </div>
              <% end %>

              <.interview_stepper
                current_step={@current_step}
                current_question_number={@current_question_number}
                total_questions={@total_questions}
                interview_phase={@interview_phase}
              />

              <div id="audio-player" phx-hook="AudioPlayer"></div>

              <.mic_gate id="interview-mic-gate" state={@mic_permission} detail={@mic_detail} open={@mic_gate_open} checking={@mic_checking} />

              <%= case @current_step do %>
                <% :initialize -> %>
                  <.initialize_step
                    :if={!@error}
                    resume_info={@resume_info}
                    interview_phase={@interview_phase}
                    loading={@loading}
                    error={@error}
                    greeting_text={@greeting_text}
                    mic_verified={@mic_verified}
                    mic_permission={@mic_permission}
                    mic_checking={@mic_checking}
                  />
                <% :interview -> %>
                  <.interview_step
                    interview_phase={@interview_phase}
                    current_question={@current_question}
                    current_question_number={@current_question_number}
                    total_questions={@total_questions}
                    is_recording={@is_recording}
                    audio_level={@audio_level}
                    remaining_time={@remaining_time}
                    loading={@loading}
                    current_transcript={@current_transcript}
                  />
                <% :results -> %>
                  <div id="interview-report-source">
                    <.results_step
                      tenant_alias={@tenant_alias}
                      interview_session={@interview_session}
                      overall_score={@overall_score}
                      strengths={@strengths}
                      improvements={@improvements}
                      questions_answered={@questions_answered}
                      expanded_question={@expanded_question}
                      student_name={@user_info.name}
                      error={@error}
                      error_title={@error_title}
                    />
                  </div>
              <% end %>
            </div>
          </main>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Private Helpers ────────────────────────────────────────────────

  defp do_begin_interview(socket) do
    session_state = socket.assigns.session_state

    if is_nil(session_state) do
      {:noreply, assign(socket, :error, "Session not initialized. Please start over.")}
    else
      socket =
        socket
        |> assign(:loading, :starting_ws)
        |> assign(:current_step, :interview)
        |> assign(:interview_phase, :connecting)

      run_engine_async(socket, fn state -> Interview.proceed(state) end)

      {:noreply, socket}
    end
  end

  defp do_start_interview(socket) do
    current_user = socket.assigns.current_user
    prefix = socket.assigns.tenant_schema
    ats_data = socket.assigns.ats_data

    cond do
      is_nil(ats_data) or is_nil(ats_data.resume_url) ->
        {:noreply, assign(socket, :error, "No resume found. Please upload a resume first.")}

      ats_data.status != "completed" ->
        {:noreply, assign(socket, :error, "Your resume is still being analysed. Please try again in a moment.")}

      true ->
        resume_file_path = AtsUpload.get_resume_file_path(ats_data.resume_url)
        student_id = current_user.id
        tenant_id = current_user.tenant_id
        resume_url = ats_data.resume_url

        socket =
          socket
          |> assign(:loading, :indexing)
          |> assign(:interview_phase, :indexing)
          |> assign(:error, nil)

        run_start_session_async(prefix, %{
          student_id: student_id,
          tenant_id: tenant_id,
          resume_url: resume_url,
          resume_file_path: resume_file_path
        })

        {:noreply, socket}
    end
  end

  defp schedule_tick, do: Process.send_after(self(), :interview_tick, 1000)

  defp format_error(:no_resume), do: "No resume on file. Please upload one first."
  defp format_error(:resume_not_ready), do: "Your resume is still being analysed. Please try again shortly."
  defp format_error(:empty_answer), do: "Your response was empty — please try again."
  defp format_error(message) when is_binary(message), do: message
  defp format_error(reason), do: "Something went wrong (#{inspect(reason)}). Please try again."

  # Overall score is always a whole number.
  defp round_score(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_integer()
  defp round_score(n) when is_number(n), do: round(n)
  defp round_score(_), do: 0

  defp extract_list_from_report(nil, _section), do: []

  defp extract_list_from_report(report, section) do
    lines = String.split(report, "\n")

    section_idx =
      Enum.find_index(lines, fn line -> String.contains?(line, section) end)

    case section_idx do
      nil ->
        []

      idx ->
        lines
        |> Enum.drop(idx + 1)
        |> Enum.take_while(fn line ->
          trimmed = String.trim(line)
          trimmed != "" and not String.starts_with?(trimmed, "##")
        end)
        |> Enum.map(fn line ->
          line
          |> String.trim()
          |> String.replace(~r/^•\s*/, "")
          |> String.replace(~r/^[-*]\s+/, "")
          |> String.trim()
        end)
        |> Enum.map(&extract_bullet_title/1)
        |> Enum.filter(&(&1 != ""))
        |> Enum.take(5)
    end
  end

  defp extract_bullet_title(text) do
    case Regex.run(~r/^\*\*(.+?)\*\*/, text) do
      [_, title] -> title
      nil -> text
    end
  end

  # Closing the tab / navigating away mid-interview must not leave the
  # session stuck non-terminal forever — this is the first time this type has
  # had ANY force-completion path (previously not even the countdown timer
  # reaching zero for a connected student did anything). Enqueues the same
  # finalize job the abandonment sweep uses, so both share one completion
  # path (Interview.force_complete/2). Guarded on connected?/1 — the
  # disconnected static-render pass would otherwise fire this on every page
  # load. Evaluation never runs inline here (LLM-backed via the engine's
  # report generation), only a lightweight job enqueue.
  @impl true
  def terminate(_reason, socket) do
    with true <- connected?(socket),
         %{id: session_id} <- socket.assigns[:interview_session],
         tenant_schema when is_binary(tenant_schema) <- socket.assigns[:tenant_schema] do
      VyaasaCampus.Jobs.AssessmentFinalizer.enqueue("interview", session_id, tenant_schema)
    end

    :ok
  end
end
