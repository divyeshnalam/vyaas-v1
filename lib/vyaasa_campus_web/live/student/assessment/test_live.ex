defmodule VyaasaCampusWeb.Student.Assessment.TestLive do
  @moduledoc """
  LiveView for MCQ Test Taking Screen.
  Main screen with timer, questions, and navigation panel.
  """

  use VyaasaCampusWeb, :live_view
  alias VyaasaCampus.Contexts.{Assessments, StudentAts}
  alias VyaasaCampus.Schema.Assessments.AssessmentAttempt
  alias VyaasaCampusWeb.DateTimeFormatter
  import VyaasaCampusWeb.Components.UI

  # Auto-submit the test once a student accumulates this many integrity
  # violations (tab switches, window-blur / alt-tab, fullscreen exits).
  @violation_limit 3

  @impl true
  def mount(%{"tenant" => tenant_alias, "id" => assessment_id} = params, _session, socket) do
    require Logger

    tenant_schema = get_tenant_schema(tenant_alias)
    current_user = socket.assigns[:current_user]

    # Get assessment
    assessment = Assessments.get_assessment!(assessment_id, tenant_schema)

    # Get attempt — redirect if missing
    attempt_id = params["attempt"]
    attempt = if attempt_id, do: Assessments.get_attempt(attempt_id, tenant_schema), else: nil

    cond do
      # No attempt provided or not found — redirect to instructions
      is_nil(attempt) ->
        {:ok, redirect(socket, to: ~p"/student/#{tenant_alias}/assessment/instructions")}

      # Attempt already submitted — redirect to results
      attempt.status == "submitted" ->
        {:ok, redirect(socket, to: ~p"/student/#{tenant_alias}/assessment/#{assessment_id}/result")}

      # Authorization: attempt must belong to current user
      attempt.student_id != current_user.id ->
        Logger.warning("Unauthorized access to attempt #{attempt_id} by user #{current_user.id}")
        {:ok, redirect(socket, to: "/student/#{tenant_alias}/dashboard")}

      true ->
        mount_test(socket, tenant_alias, tenant_schema, current_user, assessment, attempt)
    end
  end

  defp mount_test(socket, tenant_alias, tenant_schema, current_user, assessment, attempt) do
    # Get questions for this assessment from the database
    questions = Assessments.load_assessment_questions(assessment.id, tenant_schema)

    # Guard: no questions available
    if Enum.empty?(questions) do
      {:ok,
       socket
       |> put_flash(:error, "No questions available for this assessment.")
       |> redirect(to: "/student/#{tenant_alias}/dashboard")}
    else
      # Restore answers from attempt (handles page reload)
      saved_answers = attempt.answers || %{}

      # Restore current question index from attempt metadata
      saved_index = get_in(attempt.metadata, ["current_question_index"]) || 0
      saved_index = min(saved_index, length(questions) - 1)

      # Calculate remaining time from attempt start time
      time_remaining =
        if attempt.started_at do
          elapsed = DateTime.diff(DateTime.utc_now(), attempt.started_at, :second)
          max(0, assessment.duration_minutes * 60 - elapsed)
        else
          assessment.duration_minutes * 60
        end

      # If time is already up, force-submit (bypasses min-time guard)
      if time_remaining <= 0 do
        Assessments.force_submit_assessment(attempt.id, saved_answers, tenant_schema)
        {:ok, redirect(socket, to: ~p"/student/#{tenant_alias}/assessment/#{assessment.id}/result")}
      else
        # Determine current section from current question
        current_question = Enum.at(questions, saved_index)
        current_section = if current_question, do: current_question.subject_name || "aptitude", else: "aptitude"

        tab_switch_count = get_in(attempt.metadata, ["tab_switch_count"]) || 0

        # Restore integrity tracking state from attempt metadata
        answer_timestamps   = get_in(attempt.metadata, ["answer_timestamps"])   || %{}
        answer_change_counts = get_in(attempt.metadata, ["answer_change_counts"]) || %{}

        socket =
          socket
          |> assign(:tenant_alias, tenant_alias)
          |> assign(:tenant_schema, tenant_schema)
          |> assign(:current_user, current_user)
          |> assign(
            :profile_picture_url,
            StudentAts.get_student_ats_fields(current_user.id, tenant_schema)[:profile_picture_url]
          )
          |> assign(:assessment, assessment)
          |> assign(:attempt, attempt)
          |> assign(:questions, questions)
          |> assign(:current_question_index, saved_index)
          |> assign(:current_section, current_section)
          |> assign(:answers, saved_answers)
          |> assign(:marked_for_review, MapSet.new())
          |> assign(:visited_questions, MapSet.new([saved_index]))
          |> assign(:time_remaining, time_remaining)
          |> assign(:timer_warning_level, get_timer_warning_level(time_remaining))
          |> assign(:submitting, false)
          |> assign(:tab_switch_count, tab_switch_count)
          |> assign(:show_tab_warning, false)
          # Proctoring / integrity (auto-submit after @violation_limit strikes)
          |> assign(:violation_count, get_in(attempt.metadata, ["violation_count"]) || 0)
          |> assign(:violation_limit, @violation_limit)
          |> assign(:require_fullscreen, true)
          |> assign(:show_integrity_warning, false)
          |> assign(:integrity_message, nil)
          |> assign(:answer_timestamps, answer_timestamps)
          |> assign(:answer_change_counts, answer_change_counts)

        # Start timer tick
        if connected?(socket) do
          schedule_timer_tick()
        end

        {:ok, socket}
      end
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    # Don't tick if already submitting
    if socket.assigns.submitting do
      {:noreply, socket}
    else
      time_remaining = max(0, socket.assigns.time_remaining - 1)

      socket =
        socket
        |> assign(:time_remaining, time_remaining)
        |> assign(:timer_warning_level, get_timer_warning_level(time_remaining))

      if time_remaining <= 0 do
        # Auto-submit when timer expires — set submitting flag to prevent double submit
        {:noreply, socket |> assign(:submitting, true) |> auto_submit_assessment()}
      else
        schedule_timer_tick()
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("select_option", %{"option" => option}, socket) do
    current_idx = socket.assigns.current_question_index
    question = Enum.at(socket.assigns.questions, current_idx)

    if question do
      question_id = to_string(question.id)
      now_unix = System.os_time(:second)

      # Track timestamp of this answer
      answer_timestamps = Map.put(socket.assigns.answer_timestamps, question_id, now_unix)

      # Track how many times this question's answer has been changed
      prev_answer = Map.get(socket.assigns.answers, question_id)
      answer_change_counts =
        if prev_answer != nil and prev_answer != option do
          Map.update(socket.assigns.answer_change_counts, question_id, 1, &(&1 + 1))
        else
          socket.assigns.answer_change_counts
        end

      answers = Map.put(socket.assigns.answers, question_id, option)

      save_answers_to_attempt(
        socket.assigns.attempt,
        answers,
        answer_timestamps,
        answer_change_counts,
        socket.assigns.tenant_schema
      )

      {:noreply,
       socket
       |> assign(:answers, answers)
       |> assign(:answer_timestamps, answer_timestamps)
       |> assign(:answer_change_counts, answer_change_counts)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_response", _params, socket) do
    current_idx = socket.assigns.current_question_index
    question = Enum.at(socket.assigns.questions, current_idx)

    if question do
      question_id = to_string(question.id)
      answers = Map.delete(socket.assigns.answers, question_id)

      save_answers_to_attempt(
        socket.assigns.attempt,
        answers,
        socket.assigns.answer_timestamps,
        socket.assigns.answer_change_counts,
        socket.assigns.tenant_schema
      )

      {:noreply, assign(socket, :answers, answers)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_mark_review", _params, socket) do
    current_idx = socket.assigns.current_question_index
    marked = socket.assigns.marked_for_review

    new_marked =
      if MapSet.member?(marked, current_idx),
        do: MapSet.delete(marked, current_idx),
        else: MapSet.put(marked, current_idx)

    {:noreply, assign(socket, :marked_for_review, new_marked)}
  end

  @impl true
  def handle_event("navigate_question", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    questions_count = length(socket.assigns.questions)

    if index >= 0 and index < questions_count do
      current_question = Enum.at(socket.assigns.questions, index)

      section =
        if current_question, do: current_question.subject_name || "aptitude", else: socket.assigns.current_section

      socket =
        socket
        |> assign(:current_question_index, index)
        |> assign(:current_section, section)
        |> update(:visited_questions, &MapSet.put(&1, index))

      save_question_index(socket.assigns.attempt, index, socket.assigns.tenant_schema)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("previous_question", _params, socket) do
    current_idx = socket.assigns.current_question_index

    if current_idx > 0 do
      new_idx = current_idx - 1
      current_question = Enum.at(socket.assigns.questions, new_idx)

      section =
        if current_question, do: current_question.subject_name || "aptitude", else: socket.assigns.current_section

      socket =
        socket
        |> assign(:current_question_index, new_idx)
        |> assign(:current_section, section)
        |> update(:visited_questions, &MapSet.put(&1, new_idx))

      save_question_index(socket.assigns.attempt, new_idx, socket.assigns.tenant_schema)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_question", _params, socket) do
    current_idx = socket.assigns.current_question_index
    questions_count = length(socket.assigns.questions)

    if current_idx < questions_count - 1 do
      new_idx = current_idx + 1
      current_question = Enum.at(socket.assigns.questions, new_idx)

      section =
        if current_question, do: current_question.subject_name || "aptitude", else: socket.assigns.current_section

      socket =
        socket
        |> assign(:current_question_index, new_idx)
        |> assign(:current_section, section)
        |> update(:visited_questions, &MapSet.put(&1, new_idx))

      save_question_index(socket.assigns.attempt, new_idx, socket.assigns.tenant_schema)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("review_and_submit", _params, socket) do
    {:noreply,
     redirect(socket,
       to:
         ~p"/student/#{socket.assigns.tenant_alias}/assessment/#{socket.assigns.assessment.id}/review?attempt=#{socket.assigns.attempt.id}"
     )}
  end

  @impl true
  def handle_event("integrity_violation", %{"type" => type}, socket) do
    case Assessments.record_violation(
           socket.assigns.attempt.id,
           type,
           socket.assigns.tenant_schema
         ) do
      {:ok, count} ->
        limit = socket.assigns.violation_limit
        remaining = max(0, limit - count)

        socket =
          socket
          |> assign(:violation_count, count)
          |> assign(:tab_switch_count, count)
          |> assign(:show_integrity_warning, true)
          |> assign(:integrity_message, violation_message(type, remaining))

        if count >= limit and not socket.assigns.submitting do
          # Too many strikes → close the assessment and return to the dashboard.
          Assessments.force_submit_assessment(
            socket.assigns.attempt.id,
            socket.assigns.answers,
            socket.assigns.tenant_schema
          )

          {:noreply,
           socket
           |> assign(:submitting, true)
           |> push_event("exit_fullscreen", %{})
           |> put_flash(:error, "Your assessment was closed after #{limit} full-screen exits / tab switches.")
           |> redirect(to: "/student/#{socket.assigns.tenant_alias}/dashboard")}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dismiss_tab_warning", _params, socket) do
    {:noreply, assign(socket, :show_integrity_warning, false)}
  end

  @impl true
  def handle_event("submit_test", _params, socket) do
    # Prevent double submission
    if socket.assigns.submitting do
      {:noreply, socket}
    else
      socket = assign(socket, :submitting, true)

      case Assessments.submit_assessment(
             socket.assigns.attempt.id,
             socket.assigns.answers,
             socket.assigns.tenant_schema
           ) do
        {:ok, _attempt} ->
          {:noreply,
           redirect(socket,
             to: ~p"/student/#{socket.assigns.tenant_alias}/assessment/#{socket.assigns.assessment.id}/result"
           )}

        {:error, :submitted_too_fast} ->
          {:noreply,
           socket
           |> assign(:submitting, false)
           |> put_flash(:error, "Submission was too quick. Please take more time to review your answers.")}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(:submitting, false)
           |> put_flash(:error, "Failed to submit assessment. Please try again.")}
      end
    end
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
  def render(assigns) do
    assigns = assign(assigns, :current_question, Enum.at(assigns.questions, assigns.current_question_index))
    user_info = %{
      name: "#{assigns.current_user.first_name} #{assigns.current_user.last_name}",
      profile_picture_url: assigns[:profile_picture_url]
    }

    assigns = assign(assigns, :user_info, user_info)

    ~H"""
    <div class="min-h-screen bg-cream-50 flex" id="assessment-container" phx-hook="AssessmentIntegrity"
      data-require-fullscreen={to_string(@require_fullscreen)}>
      <!-- Full-screen gate: JS shows this until the student enters fullscreen -->
      <div :if={@require_fullscreen} id="fullscreen-gate" phx-update="ignore"
        class="fixed inset-0 z-[100] bg-gray-900/95 flex items-center justify-center p-6 text-center">
        <div class="max-w-md">
          <.icon name="hero-lock-closed" class="w-12 h-12 text-orange-400 mx-auto mb-4" />
          <h2 class="text-xl font-bold text-white mb-2">Secure full-screen mode</h2>
          <p class="text-sm text-gray-300 mb-6">
            This is a proctored test that runs in full screen. Leaving full screen, switching tabs,
            or switching windows is recorded — after {@violation_limit} warnings your test is
            submitted automatically.
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
        current_section="mcq"
        tenant_alias={@tenant_alias}
        student_name={@user_info.name}
      />

      <div class="flex-1 flex flex-col min-w-0">
        <VyaasaCampusWeb.Components.Student.HeaderComponent.header user_info={@user_info} tenant_alias={@tenant_alias} exit_href={"/student/#{@tenant_alias}/dashboard"} />

        <%= if @show_integrity_warning do %>
          <div class="bg-red-600 text-white px-6 py-3 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-exclamation-triangle" class="w-5 h-5 shrink-0" />
              <span class="text-sm font-medium">
                {@integrity_message} (Strike {@violation_count} of {@violation_limit}.)
              </span>
            </div>
            <button type="button" phx-click="dismiss_tab_warning" class="text-white hover:text-red-100">
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>
        <% end %>

        <main class="flex-1 overflow-auto">
          <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-[1200px] mx-auto w-full">
            <div class="flex items-start gap-3 mb-6">
              <div
                class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
                style="background-color: #FFE9D2;"
              >
                <.icon name="hero-puzzle-piece" class="w-5 h-5" style="color: #B85F00;" />
              </div>
              <div>
                <p class="text-[11px] font-semibold tracking-[0.18em] uppercase" style="color: #FF8B00;">Domain · Problem-Solving</p>
                <h1 class="text-2xl font-bold text-gray-900">Objective Evaluation</h1>
                <p class="text-sm text-gray-500 mt-0.5">Take it at your own pace we'll guide you, not grade you.</p>
              </div>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <div class="lg:col-span-2 bg-white rounded-2xl border border-gray-100 p-6">
                <!-- Top row: Question pill + section + timer + bookmark -->
                <div class="flex items-center justify-between mb-2">
                  <div class="flex items-center gap-2">
                    <span
                      class="text-[10px] font-semibold px-2.5 py-1 rounded-full"
                      style="background-color: #FFE9D2; color: #B85F00;"
                    >
                      Question {@current_question_index + 1} of {length(@questions)}
                    </span>
                    <span class="text-xs text-gray-500">{format_section(@current_section)}</span>
                  </div>
                  <div class="flex items-center gap-3">
                    <span class={"inline-flex items-center gap-1 text-xs font-mono #{timer_text_class(@timer_warning_level)}"}>
                      <.icon name="hero-clock" class="w-3.5 h-3.5" />
                      {DateTimeFormatter.format_duration(@time_remaining)}
                    </span>
                    <% marked = MapSet.member?(@marked_for_review, @current_question_index) %>
                    <button
                      type="button"
                      phx-click="toggle_mark_review"
                      class="text-gray-400 hover:text-amber-600 transition"
                      style={if marked, do: "color: #F59E0B;", else: ""}
                      aria-label="Mark for review"
                    >
                      <.icon name="hero-bookmark" class="w-4 h-4" />
                    </button>
                  </div>
                </div>

                <div class="h-1 bg-cream-200 rounded-full overflow-hidden mb-5">
                  <div
                    class="h-full rounded-full transition-all"
                    style={"width: #{(@current_question_index + 1) / max(length(@questions), 1) * 100}%; background-color: #FF8B00;"}
                  ></div>
                </div>

                <h2 class="text-base font-bold text-gray-900 leading-relaxed mb-5">
                  {@current_question.question}
                </h2>

                <div class="space-y-2.5 mb-6">
                  <%= for {option_key, option_text} <- get_question_options(@current_question) do %>
                    <% selected = Map.get(@answers, to_string(@current_question.id)) == option_key %>
                    <button
                      type="button"
                      phx-click="select_option"
                      phx-value-option={option_key}
                      class={[
                        "w-full text-left flex items-center gap-3 px-4 py-3 rounded-xl border transition-all",
                        if(selected, do: "border-transparent", else: "bg-white border-gray-100 hover:border-cream-300")
                      ]}
                      style={if selected, do: "background-color: #FFF6EC; border-color: #FF8B00; border-width: 2px;", else: ""}
                    >
                      <div
                        class="shrink-0 w-7 h-7 rounded-full flex items-center justify-center text-[11px] font-bold"
                        style={if selected, do: "background-color: #FF8B00; color: white;", else: "background-color: #F4ECDD; color: #6B7280;"}
                      >
                        {String.upcase(option_key)}
                      </div>
                      <span class="text-sm text-gray-700 flex-1">{option_text}</span>
                    </button>
                  <% end %>
                </div>

                <!-- Bottom: Previous + Next -->
                <div class="flex items-center justify-between pt-3">
                  <button
                    type="button"
                    phx-click="previous_question"
                    disabled={@current_question_index == 0}
                    class={[
                      "inline-flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium transition",
                      if(@current_question_index == 0, do: "text-gray-300 cursor-not-allowed", else: "text-gray-600 hover:bg-cream-50")
                    ]}
                  >
                    ← Previous
                  </button>

                  <%= if @current_question_index == length(@questions) - 1 do %>
                    <button
                      type="button"
                      phx-click="review_and_submit"
                      class="inline-flex items-center gap-1.5 px-5 py-2 rounded-lg text-white text-xs font-semibold transition"
                      style="background-color: #FF8B00;"
                    >
                      Review & Submit →
                    </button>
                  <% else %>
                    <button
                      type="button"
                      phx-click="next_question"
                      class="inline-flex items-center gap-1.5 px-5 py-2 rounded-lg text-white text-xs font-semibold transition"
                      style="background-color: #FF8B00;"
                    >
                      Next →
                    </button>
                  <% end %>
                </div>
              </div>

              <div class="space-y-4">
                <div class="bg-white rounded-2xl border border-gray-100 p-4">
                  <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">Question Map</p>
                  <div class="grid grid-cols-5 gap-1.5 mb-3">
                    <%= for {_question, idx} <- Enum.with_index(@questions) do %>
                      <% question_status = get_question_status(idx, @current_question_index, @answers, @questions, @marked_for_review, @visited_questions) %>
                      <button
                        type="button"
                        phx-click="navigate_question"
                        phx-value-index={idx}
                        class={[
                          "w-9 h-9 rounded-full text-xs font-semibold transition flex items-center justify-center",
                          q_map_class(question_status, idx == @current_question_index)
                        ]}
                        style={if idx == @current_question_index, do: "background-color: #FF8B00;", else: ""}
                      >
                        {idx + 1}
                      </button>
                    <% end %>
                  </div>

                  <div class="text-[10px] text-gray-500 border-t border-gray-100 pt-2">
                    {count_answered(@answers, @questions)}/{length(@questions)} answered · auto-saved
                  </div>
                </div>

                <div class="rounded-2xl border border-cream-200 p-4" style="background-color: #FFF1DE;">
                  <div class="flex items-start gap-2 mb-1">
                    <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5" style="color: #B85F00;" />
                    <p class="text-sm font-semibold text-gray-800">Calm reminder</p>
                  </div>
                  <p class="text-xs text-gray-600 leading-relaxed">
                    There's no penalty for thinking. Skip and return your answers stay saved.
                  </p>
                </div>

                <!-- Subtle submit + clear at bottom of sidebar -->
                <div class="flex items-center justify-between text-xs text-gray-500">
                  <button
                    type="button"
                    phx-click="clear_response"
                    class="hover:text-gray-700 transition"
                  >
                    Clear response
                  </button>
                  <button
                    type="button"
                    phx-click="submit_test"
                    data-confirm="Submit your test?"
                    class="text-red-600 hover:text-red-700 font-medium transition"
                  >
                    Submit test
                  </button>
                </div>
              </div>
            </div>
          </div>
        </main>
      </div>
    </div>
    """
  end

  defp q_map_class(_status, true), do: "text-white"
  defp q_map_class(:answered_and_marked, false), do: "bg-green-500 text-white ring-2 ring-amber-400"
  defp q_map_class(:answered, false), do: "bg-green-500 text-white"
  defp q_map_class(:marked, false), do: "bg-amber-500 text-white"
  defp q_map_class(:skipped, false), do: "bg-red-100 text-red-600"
  defp q_map_class(_, false), do: "bg-cream-100 text-gray-500 hover:bg-cream-200"

  defp format_section(nil), do: ""
  defp format_section(section) when is_binary(section) do
    section
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
  defp format_section(_), do: ""

  # Private functions

  defp save_answers_to_attempt(nil, _answers, _timestamps, _change_counts, _prefix), do: :ok

  defp save_answers_to_attempt(attempt, answers, answer_timestamps, answer_change_counts, prefix) do
    case Assessments.save_answers(attempt.id, answers, answer_timestamps, answer_change_counts, prefix) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to save answers for attempt #{attempt.id}: #{inspect(reason)}")
        :error
    end
  end

  defp save_question_index(nil, _index, _prefix), do: :ok

  defp save_question_index(attempt, index, prefix) do
    metadata = Map.put(attempt.metadata || %{}, "current_question_index", index)

    attempt
    |> AssessmentAttempt.changeset(%{metadata: metadata})
    |> VyaasaCampus.Repo.update(prefix: prefix)
  end

  defp get_tenant_schema(tenant_alias) do
    alias VyaasaCampus.Contexts.Tenants
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    if tenant, do: tenant.schema_name, else: nil
  end

  defp schedule_timer_tick do
    Process.send_after(self(), :tick, 1000)
  end

  defp get_timer_warning_level(seconds) when seconds <= 60, do: :critical
  defp get_timer_warning_level(seconds) when seconds <= 300, do: :warning
  defp get_timer_warning_level(seconds) when seconds <= 600, do: :caution
  defp get_timer_warning_level(_), do: :normal

  defp timer_text_class(:critical), do: "text-red-600 animate-pulse"
  defp timer_text_class(:warning), do: "text-red-500"
  defp timer_text_class(:caution), do: "text-orange-500"
  defp timer_text_class(:normal), do: "text-gray-900"

  defp violation_message(type, remaining) do
    label =
      case type do
        "fullscreen_exit" -> "You left full-screen mode."
        "window_blur" -> "You switched away from the test window."
        _ -> "You switched tabs / left the test."
      end

    cond do
      remaining <= 0 -> "#{label} Submitting your test now."
      remaining == 1 -> "#{label} Final warning — one more and your test is submitted automatically."
      true -> "#{label} This is recorded. #{remaining} warnings left before auto-submit."
    end
  end

  defp auto_submit_assessment(socket) do
    # Auto-submit bypasses the minimum-time guard since the timer forced the submission
    case Assessments.force_submit_assessment(
           socket.assigns.attempt.id,
           socket.assigns.answers,
           socket.assigns.tenant_schema
         ) do
      {:ok, _attempt} ->
        redirect(socket,
          to: ~p"/student/#{socket.assigns.tenant_alias}/assessment/#{socket.assigns.assessment.id}/result"
        )

      {:error, _changeset} ->
        put_flash(socket, :error, "Failed to auto-submit assessment.")
    end
  end

  defp get_question_options(question) do
    Map.get(question, :options, %{})
    |> Enum.sort_by(fn {key, _} -> key end)
  end

  defp get_question_status(idx, current_idx, answers, questions, marked, visited) do
    question = Enum.at(questions, idx)
    answered = question && Map.has_key?(answers, to_string(question.id))
    is_marked = MapSet.member?(marked, idx)
    is_visited = MapSet.member?(visited, idx)

    cond do
      idx == current_idx -> :current
      answered and is_marked -> :answered_and_marked
      answered -> :answered
      is_marked -> :marked
      is_visited -> :skipped
      true -> :not_visited
    end
  end

  defp question_status_class(:current), do: "bg-blue-500 text-white ring-2 ring-blue-400"

  defp question_status_class(:answered_and_marked),
    do:
      "bg-green-500 text-white relative after:absolute after:top-0 after:right-0 after:w-0 after:h-0 after:border-t-8 after:border-r-8 after:border-t-amber-500 after:border-r-transparent"

  defp question_status_class(:answered), do: "bg-green-500 text-white"
  defp question_status_class(:marked), do: "bg-amber-500 text-white"
  defp question_status_class(:skipped), do: "bg-red-300 text-gray-900"
  defp question_status_class(:not_visited), do: "bg-gray-200 text-gray-700"

  defp count_answered(answers, questions) do
    question_ids = Enum.map(questions, &to_string(&1.id)) |> MapSet.new()
    Map.keys(answers) |> Enum.filter(&MapSet.member?(question_ids, to_string(&1))) |> length()
  end

  defp count_not_visited(visited, questions) do
    total = length(questions)
    visited_count = MapSet.size(visited)
    total - visited_count
  end

  # Closing the tab / navigating away mid-test must not leave the attempt
  # stuck "in_progress" forever. Guarded on connected?/1 — LiveView mounts
  # twice (a disconnected static render, then the real connected one over the
  # websocket); without this guard terminate/2 would fire on every page load,
  # before the student even starts. force_submit_assessment/3 re-checks status
  # from the DB itself and no-ops if already terminal, so this is safe even if
  # it races a normal, just-completed submit's own navigation/unmount.
  #
  # MCQ scoring is objective (correct-answer matching, no LLM), so this runs
  # inline rather than handing off to a job — unlike every other assessment
  # type, there's nothing here slow enough to justify decoupling.
  @impl true
  def terminate(_reason, socket) do
    with true <- connected?(socket),
         %{id: attempt_id} <- socket.assigns[:attempt],
         tenant_schema when is_binary(tenant_schema) <- socket.assigns[:tenant_schema] do
      answers = socket.assigns[:answers] || %{}
      Assessments.force_submit_assessment(attempt_id, answers, tenant_schema)
    end

    :ok
  end
end
