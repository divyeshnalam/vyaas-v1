defmodule VyaasaCampusWeb.Student.Psychometric.PsychometricLive do
  @moduledoc """
  LiveView for the adaptive Big Five psychometric assessment.

  Phases:
    :loading       — initial mount
    :instructions  — landing screen, "Start" button
    :test          — current question shown, Likert buttons
    :thinking      — LLM is generating the next question (~5-15s)
    :processing    — assessment finished, generating final report
    :report        — final report displayed

  Flow:
    Start → engine generates Q1 → :test
    Answer click → :thinking → engine returns next Q → :test
    (repeat 30 times)
    Last answer → :processing → report ready → :report
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.{Psychometric, StudentAts}
  alias VyaasaCampus.AI.PsychometricEngine

  import VyaasaCampusWeb.Components.UI, only: [icon: 1, error_card: 1]

  require Logger

  @selected_answer_min_ms 2_00

  # ============================================================================
  # MOUNT
  # ============================================================================

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    tenant_schema = get_tenant_schema(tenant_alias)
    current_user = socket.assigns[:current_user]

    # Opik filter labels for every trace this LiveView (and its Tasks) emits.
    if connected?(socket),
      do: VyaasaCampus.AI.Tracing.put_metadata(%{student_id: current_user.id, module: "psychometric", tenant: tenant_schema})

    existing = Psychometric.get_latest_assessment(current_user.id, tenant_schema)

    socket =
      socket
      |> assign(:tenant_alias, tenant_alias)
      |> assign(:tenant_schema, tenant_schema)
      |> assign(:current_user, current_user)
      |> assign(
        :profile_picture_url,
        StudentAts.get_student_ats_fields(current_user.id, tenant_schema)[:profile_picture_url]
      )
      |> assign(:assessment, existing)
      |> assign(:session_id, existing && existing.session_id)
      |> assign(:current_question, nil)
      |> assign(:current_answer, nil)
      |> assign(:selected_answer_at, nil)
      |> assign(:pending_answer_result, nil)
      |> assign(:question_number, 0)
      |> assign(:total_questions, PsychometricEngine.total_questions())
      |> assign(:is_followup, false)
      |> assign(:followup_number, 0)
      |> assign(:report, nil)
      |> assign(:factor_scores, nil)
      |> assign(:error, nil)
      |> assign(:error_title, "Something went wrong")
      |> assign(:likert_options, PsychometricEngine.likert_options())
      # Proctoring (fullscreen for consistency; violations are log-only) + the
      # real integrity signal for a personality test: response validity.
      # No gate when only viewing an already-completed report.
      |> assign(:require_fullscreen, existing == nil or existing.status != "completed")
      |> assign(:violation_count, 0)
      |> assign(:show_integrity_warning, false)
      |> assign(:integrity_message, nil)
      |> assign(:answer_log, [])
      |> assign(:answer_times, [])
      |> assign(:question_shown_at, nil)

    socket =
      cond do
        existing && existing.status == "completed" ->
          socket
          |> assign(:phase, :report)
          |> assign(:report, existing.factor_reports)
          |> assign(:factor_scores, existing.factor_scores)

        existing && existing.status == "processing" ->
          assign(socket, :phase, :processing)

        true ->
          # Any non-completed, non-processing state (incl. an abandoned
          # "started" or a "failed" session) is treated as a fresh start.
          # We deliberately do NOT resume an incomplete "started" session —
          # the student begins over cleanly. The stale row is replaced when
          # they hit "Start Assessment" (see the start_assessment handler,
          # which resets any non-completed record before inserting a new one).
          assign(socket, :phase, :instructions)
      end

    {:ok, socket}
  end

  # ============================================================================
  # EVENTS
  # ============================================================================

  @impl true
  def handle_event("start_assessment", _params, socket) do
    socket = assign(socket, :phase, :thinking)
    user = socket.assigns.current_user
    tenant_id = user.tenant_id || socket.assigns.tenant_alias
    tenant_schema = socket.assigns.tenant_schema

    # If a stale "started" record exists, delete it first so we never trip
    # the unique (student_id, attempt_number) constraint.
    if existing = socket.assigns.assessment do
      if existing.status not in ["completed"] do
        Psychometric.reset_assessment(user.id, tenant_schema)
      end
    end

    lv_pid = self()

    Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
      result = Psychometric.start_adaptive(user.id, to_string(tenant_id), tenant_schema)
      send(lv_pid, {:start_result, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_answer", %{"answer" => answer}, socket) do
    if socket.assigns.phase != :test do
      {:noreply, socket}
    else
      # Response validity: log the answer + how long it took to read+answer.
      rt =
        case socket.assigns.question_shown_at do
          nil -> nil
          shown -> System.monotonic_time(:millisecond) - shown
        end

      socket =
        socket
        |> assign(:phase, :thinking)
        |> assign(:current_answer, answer)
        |> assign(:selected_answer_at, System.monotonic_time(:millisecond))
        |> assign(:pending_answer_result, nil)
        |> assign(:answer_log, [answer | socket.assigns.answer_log])
        |> assign(:answer_times, if(rt, do: [rt | socket.assigns.answer_times], else: socket.assigns.answer_times))

      session_id = socket.assigns.session_id
      tenant_schema = socket.assigns.tenant_schema
      lv_pid = self()

      Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
        result = Psychometric.submit_answer(session_id, answer, tenant_schema)
        send(lv_pid, {:answer_result, result})
      end)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("resend_report", _params, socket) do
    case socket.assigns[:assessment] do
      %{id: id} ->
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:psychometric, id, socket.assigns.tenant_schema)
        {:noreply, put_flash(socket, :info, "Your personality report is on its way to your email ✉️")}

      _ ->
        {:noreply, put_flash(socket, :error, "No completed assessment to email yet.")}
    end
  end

  @impl true
  def handle_event("back_to_dashboard", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/dashboard")}
  end

  @impl true
  def handle_event("retake_assessment", _params, socket) do
    user = socket.assigns.current_user
    tenant_id = user.tenant_id || socket.assigns.tenant_alias
    tenant_schema = socket.assigns.tenant_schema
    Psychometric.reset_assessment(user.id, tenant_schema)

    socket = assign(socket, :error, nil)
    lv_pid = self()

    Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
      result = Psychometric.start_adaptive(user.id, to_string(tenant_id), tenant_schema)
      send(lv_pid, {:start_result, result})
    end)

    {:noreply, socket}
  end

  # ============================================================================
  # ASYNC TASK RESULTS
  # ============================================================================

  @impl true
  def handle_info({:start_result, {:ok, %{assessment: assessment, question: question}}}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :test)
     |> assign(:assessment, assessment)
     |> assign(:session_id, assessment.session_id)
     |> assign(:current_question, question)
     |> assign(:current_answer, nil)
     |> assign(:selected_answer_at, nil)
     |> assign(:pending_answer_result, nil)
     |> assign(:question_number, question["question_number"])
     |> assign(:is_followup, false)
     |> assign(:followup_number, 0)
     |> assign(:question_shown_at, System.monotonic_time(:millisecond))
     |> assign(:error, nil)}
  end

  def handle_info({:start_result, {:error, :attempt_limit_reached, _details}}, socket) do
    message =
      "You've used all your available psychometric attempts. Please contact your college admin to request more."

    {:noreply, show_start_error(socket, "Out of attempts", message)}
  end

  def handle_info({:start_result, {:error, reason}}, socket) do
    Logger.error("PSYCH_LIVE | start failed: #{inspect(reason)}")

    {:noreply,
     show_start_error(socket, "Something went wrong", "Failed to start assessment. Please try again.")}
  end

  def handle_info({:answer_result, result}, socket) do
    case selected_answer_wait_ms(socket) do
      0 ->
        apply_answer_result(result, socket)

      wait_ms ->
        Process.send_after(self(), :apply_pending_answer_result, wait_ms)

        {:noreply, assign(socket, :pending_answer_result, result)}
    end
  end

  def handle_info(:apply_pending_answer_result, socket) do
    case socket.assigns.pending_answer_result do
      nil -> {:noreply, socket}
      result -> apply_answer_result(result, assign(socket, :pending_answer_result, nil))
    end
  end

  def handle_info({:report_result, {:ok, assessment}}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :report)
     |> assign(:assessment, assessment)
     |> assign(:report, assessment.factor_reports)
     |> assign(:factor_scores, assessment.factor_scores)}
  end

  def handle_info({:report_result, {:error, reason}}, socket) do
    Logger.error("PSYCH_LIVE | report generation failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:phase, :instructions)
     |> assign(:error_title, "Something went wrong")
     |> assign(:error, "Report generation failed. Please retake the assessment.")
     |> put_flash(:error, "Report generation failed. Please retake.")}
  end

  @impl true
  def handle_event("show_coming_soon", _params, socket) do
    {:noreply, put_flash(socket, :info, "Coming soon!")}
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply, redirect(socket, to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}
  end

  @impl true
  def handle_event("integrity_violation", %{"type" => type}, socket) do
    # Enforced only once the test has started; close at the 3rd strike.
    if socket.assigns.phase in [:thinking, :test, :processing] do
      count =
        case socket.assigns[:session_id] do
          sid when is_binary(sid) ->
            case Psychometric.record_violation(sid, type, socket.assigns.tenant_schema) do
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
         |> redirect(to: "/student/#{socket.assigns.tenant_alias}/dashboard")}
      else
        {:noreply, assign(socket, :integrity_message, integrity_message(type))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dismiss_integrity_warning", _params, socket) do
    {:noreply, assign(socket, :show_integrity_warning, false)}
  end

  # Compute straight-lining % + median answer time and persist for admin review.
  # Failure while (re)starting an assessment: if a completed report is still
  # on screen (retry triggered from :report), keep it visible and layer the
  # error on top — same pattern as the MCQ retry flow. Only fall back to the
  # instructions screen when there's no report to show behind it.
  defp show_start_error(socket, title, message) do
    socket =
      socket
      |> assign(:error_title, title)
      |> assign(:error, message)
      |> put_flash(:error, message)

    if socket.assigns.phase == :report do
      socket
    else
      assign(socket, :phase, :instructions)
    end
  end

  defp persist_validity(socket, session_id) do
    answers = socket.assigns.answer_log
    times = socket.assigns.answer_times
    n = length(answers)

    if is_binary(session_id) and n >= 5 do
      most = answers |> Enum.frequencies() |> Map.values() |> Enum.max(fn -> 0 end)
      straight_lining = most / n

      validity = %{
        "n" => n,
        "straight_lining_pct" => Float.round(straight_lining, 3),
        "median_ms" => median(times)
      }

      Psychometric.record_validity(session_id, validity, socket.assigns.tenant_schema)
    end
  end

  defp median([]), do: 0

  defp median(list) do
    sorted = Enum.sort(list)
    len = length(sorted)
    mid = div(len, 2)

    if rem(len, 2) == 1 do
      Enum.at(sorted, mid)
    else
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end

  defp integrity_message("fullscreen_exit"), do: "You left full-screen mode. This is recorded."
  defp integrity_message("window_blur"), do: "You switched away from the assessment. This is recorded."
  defp integrity_message(_), do: "You switched tabs / left the assessment. This is recorded."

  defp selected_answer_wait_ms(socket) do
    case socket.assigns.selected_answer_at do
      nil ->
        0

      selected_at ->
        elapsed = System.monotonic_time(:millisecond) - selected_at
        max(@selected_answer_min_ms - elapsed, 0)
    end
  end

  defp apply_answer_result({:ok, %{assessment: assessment, complete: true}}, socket) do
    # Response-validity check (straight-lining + rapid answering) — the actual
    # integrity risk for a personality test. Persist for the admin panel.
    persist_validity(socket, assessment.session_id)

    socket =
      socket
      |> assign(:phase, :processing)
      |> assign(:assessment, assessment)
      |> assign(:selected_answer_at, nil)

    # Kick off final report generation in another Task
    session_id = assessment.session_id
    tenant_schema = socket.assigns.tenant_schema
    lv_pid = self()

    Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn ->
      result = Psychometric.finalize_report(session_id, tenant_schema)
      send(lv_pid, {:report_result, result})
    end)

    {:noreply, socket}
  end

  defp apply_answer_result({:ok, %{assessment: assessment, question: question}}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :test)
     |> assign(:assessment, assessment)
     |> assign(:current_question, question)
     |> assign(:current_answer, nil)
     |> assign(:selected_answer_at, nil)
     |> assign(:question_number, question["question_number"])
     |> assign(:is_followup, question["is_followup"] || false)
     |> assign(:followup_number, question["followup_number"] || 0)
     |> assign(:question_shown_at, System.monotonic_time(:millisecond))}
  end

  defp apply_answer_result({:error, reason}, socket) do
    Logger.error("PSYCH_LIVE | submit_answer failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:phase, :test)
     |> assign(:current_answer, nil)
     |> assign(:selected_answer_at, nil)
     |> put_flash(:error, "Could not submit answer. Please try again.")}
  end

  # ============================================================================
  # RENDER
  # ============================================================================

  @impl true
  def render(assigns) do
    user_info = %{
      name: "#{assigns.current_user.first_name} #{assigns.current_user.last_name}",
      profile_picture_url: assigns[:profile_picture_url]
    }

    assigns = assign(assigns, :user_info, user_info)
    # Full screen required only once the test is underway (after Start).
    assigns = assign(assigns, :require_fullscreen, assigns.phase in [:thinking, :test, :processing])

    ~H"""
    <div class="min-h-screen bg-cream-50 flex" id="psychometric-container" phx-hook="AssessmentIntegrity"
      data-require-fullscreen={to_string(@require_fullscreen)}>
      <div :if={@require_fullscreen} id="fullscreen-gate" phx-update="ignore"
        class="fixed inset-0 z-100 bg-gray-900/95 flex items-center justify-center p-6 text-center">
        <div class="max-w-md">
          <.icon name="hero-lock-closed" class="w-12 h-12 text-orange-400 mx-auto mb-4" />
          <h2 class="text-xl font-bold text-white mb-2">Secure full-screen mode</h2>
          <p class="text-sm text-gray-300 mb-6">
            This assessment runs in full screen. Answer honestly — there are no right or wrong
            answers. Leaving full screen or switching away is recorded.
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
        current_section="psychometric"
        tenant_alias={@tenant_alias}
        student_name={@user_info.name}
      />

      <div class="flex-1 flex flex-col min-w-0">
        <VyaasaCampusWeb.Components.Student.HeaderComponent.header user_info={@user_info} tenant_alias={@tenant_alias} exit_href={"/student/#{@tenant_alias}/dashboard"} />

        <div :if={@show_integrity_warning} class="bg-red-600 text-white px-6 py-3 flex items-center justify-between">
          <div class="flex items-center gap-3">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5 shrink-0" />
            <span class="text-sm font-medium">{@integrity_message}</span>
          </div>
          <button type="button" phx-click="dismiss_integrity_warning" class="text-white hover:text-red-100">
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <main class="flex-1 overflow-auto">
          <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-300 mx-auto w-full">
            <div class="flex items-start gap-3 mb-6">
              <div
                class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
                style="background-color: #FFE9D2;"
              >
                <.icon name="hero-light-bulb" class="w-5 h-5 text-[#B85F00]" />
              </div>
              <div>
                <p class="text-[11px] font-semibold tracking-[0.18em] uppercase" style="color: #FF8B00;">Ethics · EQ · Adaptability</p>
                <h1 class="text-2xl font-bold text-gray-900">Psychometric</h1>
                <p class="text-sm text-gray-500 mt-0.5">There are no right answers. Just be honest — your Vyaasa Coach uses this to personalise your growth.</p>
              </div>
            </div>

            <%= case @phase do %>
              <% :loading -> %><.loader_phase message="Loading assessment…" />
              <% :instructions -> %><.instructions_phase {assigns} />
              <% :thinking -> %>
                <%= if @current_question do %>
                  <.test_phase {assigns} />
                <% else %>
                  <.loader_phase message="Preparing the next question — this takes a few seconds." />
                <% end %>
              <% :test -> %><.test_phase {assigns} />
              <% :processing -> %><.processing_phase {assigns} />
              <% :report -> %><.report_phase {assigns} />
              <% _ -> %><.loader_phase message="Loading…" />
            <% end %>
          </div>
        </main>
      </div>

      <VyaasaCampusWeb.Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  attr :message, :string, default: "Loading…"

  defp loader_phase(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-10 text-center">
      <div class="animate-spin rounded-full h-12 w-12 border-2 border-cream-200 mx-auto mb-4" style="border-top-color: #FF8B00;"></div>
      <p class="text-sm font-medium text-gray-700">{@message}</p>
      <p class="text-xs text-gray-400 mt-1">Please don't refresh.</p>
    </div>
    """
  end

  defp instructions_phase(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_330px] gap-6 items-stretch">
      <div class="bg-white rounded-2xl border border-gray-100 p-8">
        <span class="inline-block text-[10px] font-semibold px-2.5 py-1 rounded-full mb-6"
          style="background-color: #FFE9D2; color: #B85F00;">Big Five · Friendly version</span>
        <h2 class="text-2xl font-bold text-gray-900 mb-3">Discover how you naturally show up.</h2>
        <p class="text-base text-gray-500 mb-8">Your responses build a private personality map. We use it only to suggest practice paths that fit you.</p>

        <.error_card
          :if={@error}
          title={@error_title}
          error_message={@error}
          retry_event="start_assessment"
          class="mb-5"
        />

        <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mb-8">
          <%= for trait <- ["Extraversion", "Agreeableness", "Conscientiousness", "Emotional Stability", "Openness"] do %>
            <div class="flex items-center gap-3 px-4 py-3 rounded-xl border" style="border-color: #FF8B00; background-color: #FFFFFF;">
              <span class="w-2.5 h-2.5 rounded-full" style="background-color: #FF8B00;"></span>
              <span class="text-sm font-medium text-gray-700">{trait}</span>
            </div>
          <% end %>
        </div>

        <button
          :if={!@error}
          type="button"
          phx-click="start_assessment"
          data-enter-fullscreen
          class="inline-flex items-center gap-2 px-6 py-3 rounded-lg text-white text-base font-semibold transition"
          style="background-color: #FF8B00;"
        >
          <.icon name="hero-play" class="w-4 h-4" /> Start Assessment
        </button>
      </div>

      <div class="rounded-2xl border p-6 min-h-70" style="background-color: #FFF1DE; border-color: #FF8B00;">
        <div class="flex items-start gap-2 mb-3">
          <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5 text-[#B85F00]" />
          <p class="text-lg font-bold text-gray-800">Honest &gt; Ideal</p>
        </div>
        <p class="text-sm text-gray-600 leading-relaxed">
          Pick what's real for you today, not what sounds best. Your private map will be more useful that way.
        </p>
      </div>
    </div>
    """
  end

  defp test_phase(assigns) do
    progress_pct =
      if assigns.total_questions > 0,
        do: round(assigns.question_number / assigns.total_questions * 100),
        else: 0

    assigns = assign(assigns, :progress_pct, progress_pct)

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <div class="lg:col-span-2 bg-white rounded-2xl border border-gray-100 p-6">
        <%= if @current_question do %>
          <div class="flex items-center gap-2 mb-1">
            <span class="text-[10px] font-semibold px-2.5 py-1 rounded-full"
              style="background-color: #FFE9D2; color: #B85F00;">Question {@question_number} of {@total_questions}</span>
            <%= if @is_followup do %>
              <span class="text-[10px] font-medium px-2 py-0.5 rounded-full bg-cream-100 text-gray-600 border border-cream-200">Follow-up {@followup_number}/3</span>
            <% end %>
          </div>

          <div class="h-1 bg-cream-200 rounded-full overflow-hidden my-4">
            <div class="h-full rounded-full transition-all"
              style={"width: #{@progress_pct}%; background-color: #FF8B00;"}></div>
          </div>

          <h2 class="text-lg font-bold text-gray-900 leading-relaxed mb-6">
            "{@current_question["question"]}"
          </h2>

          <div class="space-y-2.5 mb-4">
            <%= for {label, idx} <- Enum.with_index(@likert_options) do %>
              <% selected = @current_answer == label %>
              <button
                type="button"
                phx-click="select_answer"
                phx-value-answer={label}
                disabled={@current_answer != nil}
                class={[
                  "w-full text-left flex items-center gap-3 p-3.5 rounded-xl border-2 transition",
                  selected && "border-[#FF8B00] bg-[#FFF7ED]",
                  not selected && "bg-white border-gray-100 hover:border-cream-200 hover:bg-cream-50",
                  @current_answer != nil && "cursor-default"
                ]}
              >
                <div class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold shrink-0"
                  style={
                    if selected,
                      do: "background-color: #FF8B00; color: #FFFFFF;",
                      else: "background-color: #F4ECDD; color: #6B7280;"
                  }>
                  {Enum.at(["A", "B", "C", "D", "E"], idx, "?")}
                </div>
                <span class={[
                  "text-sm flex-1",
                  selected && "font-semibold text-gray-900",
                  not selected && "text-gray-700"
                ]}>{label}</span>
              </button>
            <% end %>
          </div>

          <p class="text-[11px] text-gray-400 text-center">
            Selecting an option auto-advances — there's a brief pause while the next is prepared.
          </p>
        <% else %>
          <p class="text-sm text-gray-500 text-center py-8">No question loaded.</p>
        <% end %>
      </div>

      <div class="space-y-4">
        <div class="rounded-2xl border border-cream-200 p-4" style="background-color: #FFF1DE;">
          <div class="flex items-start gap-2 mb-1">
            <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5 text-[#B85F00]" />
            <p class="text-sm font-semibold text-gray-800">Honest > Ideal</p>
          </div>
          <p class="text-xs text-gray-600 leading-relaxed">
            Pick what's real for you today, not what sounds best. Your private map will be more useful that way.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp processing_phase(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-10 text-center">
      <div class="animate-spin rounded-full h-12 w-12 border-2 border-cream-200 mx-auto mb-4" style="border-top-color: #FF8B00;"></div>
      <h2 class="text-lg font-bold text-gray-900 mb-1">Generating your report</h2>
      <p class="text-sm text-gray-500">Analyzing your responses to produce a calm, friendly personality snapshot.</p>
      <p class="text-xs text-gray-400 mt-3">Please don't refresh.</p>
    </div>
    """
  end

  defp report_phase(assigns) do
    factor_reports = (assigns.report && assigns.report["factor_reports"]) || []

    assigns =
      assigns
      |> assign(:factor_reports_list, factor_reports)
      |> assign(:overall_score, psychometric_overall(assigns.factor_scores))

    ~H"""
    <div id="psychometric-report-source" class="space-y-4">
      <div
        class="rounded-2xl p-6 relative overflow-hidden"
        style="background: linear-gradient(135deg, #ECFDF5 0%, #FFF1DE 72%); border: 1px solid #F6D9AE;"
      >
        <span class="inline-block text-[10px] font-semibold px-2.5 py-1 rounded-full mb-3"
          style="background-color: #22C55E; color: white;">Personality snapshot</span>

        <div class="flex items-start justify-between gap-4">
          <div class="max-w-3xl">
            <h2 class="text-2xl font-bold text-gray-900 mb-2">Here's how you naturally show up ✨</h2>
            <p class="text-sm text-gray-700 leading-relaxed">
              <%= if @report && @report["overall_summary"] do %>
                {@report["overall_summary"]}
              <% else %>
                Your profile shows a balanced personality pattern. Use this as a private reflection map, not a label.
              <% end %>
            </p>
          </div>
          <div class="hidden sm:flex flex-col w-20 h-20 rounded-full items-center justify-center shrink-0 text-white" style="background-color: #FF8B00;">
            <span class="text-2xl font-bold leading-none">{@overall_score}</span>
            <span class="text-[8px] uppercase tracking-wider mt-0.5" style="color: rgba(255,255,255,0.9);">/ 100</span>
          </div>
        </div>
      </div>

      <%= if @factor_scores do %>
        <div class="bg-white rounded-2xl border border-gray-100 p-5">
          <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-4">Factor Scores</p>
          <div class="space-y-4">
            <%= for {factor, score} <- @factor_scores do %>
              <div>
                <div class="flex items-start justify-between gap-4 mb-1.5">
                  <div>
                    <p class="text-sm font-semibold text-gray-900">{factor}</p>
                    <p class="text-[11px] text-gray-500 leading-relaxed">{factor_score_hint(factor)}</p>
                  </div>
                  <span class="text-[10px] font-semibold px-2.5 py-1 rounded-full whitespace-nowrap" style="background-color: #FFE9D2; color: #B85F00;">
                    {format_factor_score(score)} / 5.0
                  </span>
                </div>
                <div class="h-2 bg-cream-200 rounded-full overflow-hidden">
                  <div class="h-full rounded-full" style={"width: #{score_to_pct(score)}%; background-color: #FF8B00;"}></div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @factor_reports_list != [] do %>
        <%= for fr <- @factor_reports_list do %>
          <div class="bg-white rounded-2xl border border-gray-100 p-5">
            <div class="flex items-center justify-between gap-3 mb-3">
              <h3 class="font-bold text-gray-900">{fr["factor"]}</h3>
              <span class="text-[10px] font-semibold px-2.5 py-1 rounded-full border border-gray-200 text-gray-600">Deep dive</span>
            </div>
            <p class="text-sm text-gray-600 leading-relaxed mb-4">{fr["interpretation"]}</p>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
              <.insight_box title="Strengths" items={fr["strengths"] || []} tone="green" />
              <.insight_box title="Risks" items={fr["risks"] || []} tone="red" />
              <.insight_box title="Suggestions" items={fr["suggestions"] || []} tone="amber" />
            </div>
          </div>
        <% end %>
      <% end %>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="rounded-2xl border p-5" style="background-color: #ECFDF5; border-color: #A7F3D0;">
          <div class="flex items-center gap-2 mb-3">
            <.icon name="hero-arrow-trending-up" class="w-4 h-4 text-green-700" />
            <p class="text-sm font-semibold text-green-800">Key strengths</p>
          </div>
          <ul class="space-y-1.5 text-xs text-green-800">
            <%= for item <- (@report && @report["strengths"]) || [] do %>
              <li>· {item}</li>
            <% end %>
            <%= if (@report && @report["strengths"]) in [nil, []] do %>
              <li>· Your responses show a balanced, steady profile.</li>
            <% end %>
          </ul>
        </div>

        <div class="rounded-2xl border p-5" style="background-color: #FFF1DE; border-color: #F6D9AE;">
          <div class="flex items-center gap-2 mb-3">
            <.icon name="hero-light-bulb" class="w-4 h-4 text-[#B85F00]" />
            <p class="text-sm font-semibold" style="color: #B85F00;">Development areas</p>
          </div>
          <ul class="space-y-1.5 text-xs" style="color: #B85F00;">
            <%= for item <- (@report && @report["development_areas"]) || [] do %>
              <li>· {item}</li>
            <% end %>
            <%= if (@report && @report["development_areas"]) in [nil, []] do %>
              <li>· Keep reflecting on areas you'd like to stretch in.</li>
            <% end %>
          </ul>
        </div>
      </div>

      <div class="bg-white rounded-2xl border border-gray-100 p-5">
        <div class="flex items-center gap-2 mb-2">
          <.icon name="hero-map-pin" class="w-4 h-4 text-[#B85F00]" />
          <p class="text-sm font-semibold" style="color: #B85F00;">Career environment fit</p>
        </div>
        <p class="text-xs text-gray-700 leading-relaxed">
          You'll thrive in roles that value <span class="font-semibold">quality and ownership</span>, with a steady cadence and time for deep work. Best growth comes from teams that gently push you into new methods and visible communication moments.
        </p>
      </div>

      <.error_card
        :if={@error}
        title={@error_title}
        error_message={@error}
        retry_event="retake_assessment"
      />

      <div data-print-hide>
        <VyaasaCampusWeb.Components.Student.AssessmentFooter.assessment_footer
          next_event="back_to_dashboard"
          restart_event="retake_assessment"
          restart_label="Retake Assessment"
          dashboard_event="back_to_dashboard"
        />
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, default: []
  attr :tone, :string, default: "green"

  defp insight_box(assigns) do
    assigns = assign(assigns, :style, insight_box_style(assigns.tone))

    ~H"""
    <div class="rounded-xl p-3 min-h-28" style={@style}>
      <p class="text-[10px] uppercase tracking-wider font-semibold mb-2">{@title}</p>
      <ul class="space-y-1 text-xs leading-relaxed">
        <%= if @items == [] do %>
          <li>· Keep reflecting on this area as you grow.</li>
        <% else %>
          <%= for item <- @items do %>
            <li>· {item}</li>
          <% end %>
        <% end %>
      </ul>
    </div>
    """
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp get_tenant_schema(tenant_alias) do
    alias VyaasaCampus.Contexts.Tenants
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    if tenant, do: tenant.schema_name, else: nil
  end

  # Composite-weighted overall (0-100): Work Ethics ×0.8 + Teamwork ×0.1 +
  # Initiative & Leadership ×0.1, from the Big Five trait averages.
  defp psychometric_overall(scores) when is_map(scores) do
    work = comp_score([trait_val(scores, "Conscientiousness"), trait_val(scores, "Emotional Stability")])
    collab = comp_score([trait_val(scores, "Agreeableness"), trait_val(scores, "Extraversion")])
    lead = comp_score([trait_val(scores, "Openness")])
    round(work * 0.8 + collab * 0.1 + lead * 0.1)
  end

  defp psychometric_overall(_), do: 0

  defp trait_val(scores, key) do
    case Map.get(scores, key) do
      v when is_number(v) -> v
      _ -> 3.0
    end
  end

  defp comp_score(traits) do
    vals = Enum.map(traits, fn v -> if(is_number(v), do: v, else: 3.0) end)
    (Enum.sum(vals) / length(vals) / 5 * 100) |> round() |> min(100) |> max(0)
  end

  defp format_factor_score(score) when is_float(score), do: :erlang.float_to_binary(score, decimals: 2)
  defp format_factor_score(score) when is_integer(score), do: "#{score}.00"
  defp format_factor_score(score), do: to_string(score || "0.00")

  defp factor_score_hint("Conscientiousness"),
    do: "A bright focus on accuracy and thoroughness — you double-check work and protect quality."

  defp factor_score_hint("Emotional Stability"),
    do: "Generally resilient: you absorb stress and recover quickly with helpful mental habits."

  defp factor_score_hint("Extraversion"),
    do: "Comfortable in social settings; you contribute warmly but let others lead at first."

  defp factor_score_hint("Agreeableness"), do: "You set healthy boundaries while staying supportive when it matters."

  defp factor_score_hint("Openness"),
    do: "You prefer proven methods; openness to new ideas grows when you see clear value."

  defp factor_score_hint(_), do: "A useful signal for how you naturally respond in work and learning situations."

  defp insight_box_style("green"), do: "background-color: #ECFDF5; border: 1px solid #A7F3D0; color: #047857;"
  defp insight_box_style("red"), do: "background-color: #FEF2F2; border: 1px solid #FECACA; color: #DC2626;"
  defp insight_box_style("amber"), do: "background-color: #FFF1DE; border: 1px solid #F6D9AE; color: #B85F00;"
  defp insight_box_style(_), do: "background-color: #F9FAFB; border: 1px solid #E5E7EB; color: #4B5563;"

  defp score_to_pct(score) when is_number(score), do: max(0, min(100, score / 5 * 100))
  defp score_to_pct(_), do: 0

  # Closing the tab / navigating away mid-session must not leave the
  # assessment stuck non-terminal forever. This reverses the "deliberately
  # do NOT resume" decision documented in mount/3 above — that decision was
  # about resuming the student's OWN next visit (still true, unchanged), not
  # about whether an abandoned attempt ever gets scored at all. It now does,
  # via Psychometric.force_complete/2, same as every other assessment type.
  # Enqueues the same finalize job the abandonment sweep uses, so both share
  # one completion path. Guarded on connected?/1 — the disconnected
  # static-render pass would otherwise fire this on every page load.
  @impl true
  def terminate(_reason, socket) do
    with true <- connected?(socket),
         session_id when is_binary(session_id) <- socket.assigns[:session_id],
         tenant_schema when is_binary(tenant_schema) <- socket.assigns[:tenant_schema] do
      VyaasaCampus.Jobs.AssessmentFinalizer.enqueue("psychometric", session_id, tenant_schema)
    end

    :ok
  end
end
