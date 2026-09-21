defmodule VyaasaCampusWeb.Student.Assessment.ReviewLive do
  @moduledoc """
  LiveView for Assessment Review Summary Screen.
  Shows answer summary before final submission.
  """

  use VyaasaCampusWeb, :live_view
  alias VyaasaCampus.Contexts.{Assessments, StudentAts}
  alias VyaasaCampusWeb.DateTimeFormatter
  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(%{"tenant" => tenant_alias, "id" => assessment_id} = params, _session, socket) do
    require Logger

    tenant_schema = get_tenant_schema(tenant_alias)
    current_user = socket.assigns[:current_user]

    # Get assessment and attempt
    assessment = Assessments.get_assessment!(assessment_id, tenant_schema)
    attempt_id = params["attempt"]
    attempt = if attempt_id, do: Assessments.get_attempt(attempt_id, tenant_schema), else: nil

    cond do
      # No attempt — redirect to instructions
      is_nil(attempt) ->
        {:ok, redirect(socket, to: ~p"/student/#{tenant_alias}/assessment/instructions")}

      # Authorization: attempt must belong to current user
      attempt.student_id != current_user.id ->
        Logger.warning("Unauthorized review access: attempt #{attempt_id} by user #{current_user.id}")
        {:ok, redirect(socket, to: "/student/#{tenant_alias}/dashboard")}

      attempt.status == "submitted" ->
        # Post-submit "walk through each one" mode
        questions = Assessments.load_assessment_questions(assessment_id, tenant_schema)
        answers = attempt.answers || %{}

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
          |> assign(:answers, answers)
          |> assign(:mode, :post_submit)
          |> assign(:show_submit_modal, false)
          |> assign(:submitting, false)
          |> assign(:time_remaining, 0)

        {:ok, socket}

      true ->
        # Pre-submit summary mode
        questions = Assessments.load_assessment_questions(assessment_id, tenant_schema)
        answers = attempt.answers || %{}
        time_remaining = calculate_time_remaining(attempt, assessment)

        if time_remaining <= 0 do
          Assessments.force_submit_assessment(attempt.id, answers, tenant_schema)
          {:ok, redirect(socket, to: ~p"/student/#{tenant_alias}/assessment/#{assessment_id}/result")}
        else
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
            |> assign(:answers, answers)
            |> assign(:mode, :pre_submit)
            |> assign(:show_submit_modal, false)
            |> assign(:submitting, false)
            |> assign(:time_remaining, time_remaining)

          {:ok, socket}
        end
    end
  end

  @impl true
  def handle_event("back_to_results", _params, socket) do
    {:noreply,
     redirect(socket,
       to: ~p"/student/#{socket.assigns.tenant_alias}/assessment/#{socket.assigns.assessment.id}/result"
     )}
  end

  @impl true
  def handle_event("back_to_test", _params, socket) do
    {:noreply,
     redirect(socket,
       to:
         ~p"/student/#{socket.assigns.tenant_alias}/assessment/#{socket.assigns.assessment.id}/test?attempt=#{socket.assigns.attempt.id}"
     )}
  end

  @impl true
  def handle_event("show_submit_modal", _params, socket) do
    {:noreply, assign(socket, :show_submit_modal, true)}
  end

  @impl true
  def handle_event("close_submit_modal", _params, socket) do
    {:noreply, assign(socket, :show_submit_modal, false)}
  end

  @impl true
  def handle_event("confirm_submit", _params, socket) do
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
           |> assign(:show_submit_modal, false)
           |> put_flash(:error, "Submission was too quick. Please take more time to review your answers.")}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(:submitting, false)
           |> assign(:show_submit_modal, false)
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
    user_info = %{
      name: "#{assigns.current_user.first_name} #{assigns.current_user.last_name}",
      profile_picture_url: assigns[:profile_picture_url]
    }

    assigns =
      assigns
      |> assign(:user_info, user_info)
      |> assign(:total_questions, length(assigns.questions))
      |> assign(:answered_count, count_answered(assigns.answers, assigns.questions))
      |> assign(:unanswered_count, count_unanswered(assigns.answers, assigns.questions))

    ~H"""
    <div class="min-h-screen bg-cream-50 flex">
      <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar
        current_section="mcq"
        tenant_alias={@tenant_alias}
        student_name={@user_info.name}
      />

      <div class="flex-1 flex flex-col min-w-0">
        <VyaasaCampusWeb.Components.Student.HeaderComponent.header user_info={@user_info} tenant_alias={@tenant_alias} />

        <main class="flex-1 overflow-auto">
          <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-[1200px] mx-auto w-full">
            <div class="flex items-start justify-between mb-6">
              <div class="flex items-start gap-3">
                <div
                  class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
                  style="background-color: #FFE9D2;"
                >
                  <.icon name="hero-eye" class="w-5 h-5" style="color: #B85F00;" />
                </div>
                <div>
                  <p class="text-[11px] font-semibold tracking-[0.18em] uppercase" style="color: #FF8B00;">Question Review · Learn At Your Pace</p>
                  <h1 class="text-2xl font-bold text-gray-900">Let's go through each one</h1>
                  <p class="text-sm text-gray-500 mt-0.5">Calm, no-pressure walkthrough with the why behind each answer.</p>
                </div>
              </div>

              <%= if @mode == :post_submit do %>
                <button
                  type="button"
                  phx-click="back_to_results"
                  class="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition"
                >
                  ← Back to results
                </button>
              <% else %>
                <button
                  type="button"
                  phx-click="back_to_test"
                  class="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition"
                >
                  ← Back to test
                </button>
              <% end %>
            </div>

            <%= if @mode == :pre_submit do %>
              <div class="bg-white rounded-2xl border border-gray-100 p-5 mb-4 grid grid-cols-3 gap-4">
                <div>
                  <p class="text-[10px] uppercase tracking-wider text-gray-500 font-semibold">Total</p>
                  <p class="text-2xl font-bold text-gray-900">{@total_questions}</p>
                </div>
                <div>
                  <p class="text-[10px] uppercase tracking-wider text-gray-500 font-semibold">Answered</p>
                  <p class="text-2xl font-bold text-green-600">{@answered_count}</p>
                </div>
                <div>
                  <p class="text-[10px] uppercase tracking-wider text-gray-500 font-semibold">Unanswered</p>
                  <p class="text-2xl font-bold text-amber-600">{@unanswered_count}</p>
                </div>
              </div>
            <% end %>

            <div class="space-y-3 mb-6">
              <%= for {question, idx} <- Enum.with_index(@questions) do %>
                <% answer = Map.get(@answers, to_string(question.id)) %>
                <% correct_answer = Map.get(question, :answer) || Map.get(question, :correct_answer) %>
                <% answered? = answer != nil %>
                <% is_correct? = answered? and answer && correct_answer && to_string(answer) == to_string(correct_answer) %>
                <div class="bg-white rounded-2xl border border-gray-100 p-5">
                  <div class="flex items-center justify-between mb-2">
                    <span
                      class="text-[10px] font-semibold px-2.5 py-1 rounded-full"
                      style="background-color: #FFE9D2; color: #B85F00;"
                    >Q{idx + 1} · {question.subject_name || "General"}</span>
                    <%= if @mode == :post_submit do %>
                      <%= cond do %>
                        <% not answered? -> %>
                          <span class="text-[10px] font-semibold" style="color: #B85F00;">Skipped</span>
                        <% is_correct? -> %>
                          <span class="text-[10px] font-semibold text-green-600">Nice one</span>
                        <% true -> %>
                          <span class="text-[10px] font-semibold" style="color: #FF8B00;">Let's revisit</span>
                      <% end %>
                    <% else %>
                      <%= if answered? do %>
                        <span class="text-[10px] font-medium text-green-600">Answered</span>
                      <% else %>
                        <span class="text-[10px] font-medium text-amber-600">Skipped</span>
                      <% end %>
                    <% end %>
                  </div>

                  <div class="h-1 bg-cream-200 rounded-full overflow-hidden mb-3">
                    <div class="h-full rounded-full"
                      style="width: 100%; background-color: #FF8B00;"></div>
                  </div>

                  <p class="text-sm font-semibold text-gray-900 mb-3">{question.question}</p>

                  <div class="space-y-1.5">
                    <%= for {key, text} <- get_question_options(question) do %>
                      <% picked? = answer == key %>
                      <% correct? = @mode == :post_submit and correct_answer && to_string(key) == to_string(correct_answer) %>
                      <% your_wrong_pick? = @mode == :post_submit and picked? and not correct? %>
                      <div
                        class="flex items-center gap-2 p-2.5 rounded-lg border"
                        style={review_option_style(@mode, picked?, correct?, your_wrong_pick?)}
                      >
                        <div
                          class="w-7 h-7 rounded-full flex items-center justify-center text-[11px] font-bold shrink-0"
                          style={review_letter_style(@mode, picked?, correct?, your_wrong_pick?)}
                        >
                          {String.upcase(key)}
                        </div>
                        <span class="text-xs text-gray-700 flex-1">{text}</span>
                        <%= cond do %>
                          <% correct? -> %>
                            <span class="text-[10px] font-semibold text-green-600">Correct</span>
                          <% your_wrong_pick? -> %>
                            <span class="text-[10px] font-semibold" style="color: #DC2626;">Your pick</span>
                          <% picked? and @mode == :pre_submit -> %>
                            <span class="text-[10px] font-semibold" style="color: #FF8B00;">Your pick</span>
                          <% true -> %>
                        <% end %>
                      </div>
                    <% end %>
                  </div>

                  <%= if @mode == :post_submit do %>
                    <% why = Map.get(question, :explanation) || Map.get(question, :why) || nil %>
                    <%= if why && why != "" do %>
                      <div class="mt-3 rounded-xl border p-3" style="background-color: #FFF1DE; border-color: #F6D9AE;">
                        <p class="text-[10px] font-semibold tracking-[0.18em] uppercase mb-1" style="color: #B85F00;">Why</p>
                        <p class="text-xs leading-relaxed" style="color: #78350F;">{why}</p>
                      </div>
                    <% else %>
                      <% inferred = build_why_fallback(question, correct_answer) %>
                      <%= if inferred do %>
                        <div class="mt-3 rounded-xl border p-3" style="background-color: #FFF1DE; border-color: #F6D9AE;">
                          <p class="text-[10px] font-semibold tracking-[0.18em] uppercase mb-1" style="color: #B85F00;">Why</p>
                          <p class="text-xs leading-relaxed" style="color: #78350F;">{inferred}</p>
                        </div>
                      <% end %>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%= if @mode == :pre_submit do %>
              <div class="flex items-center justify-end gap-3">
                <button type="button" phx-click="back_to_test"
                  class="px-4 py-2.5 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition">
                  Back to test
                </button>
                <button type="button" phx-click="show_submit_modal"
                  class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold transition"
                  style="background-color: #FF8B00;">
                  Submit Test →
                </button>
              </div>
            <% else %>
              <div class="flex items-center justify-end">
                <button type="button" phx-click="back_to_results"
                  class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold transition"
                  style="background-color: #FF8B00;">
                  Back to results →
                </button>
              </div>
            <% end %>
          </div>
        </main>
      </div>

      <%= if @show_submit_modal do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
          <div class="bg-white rounded-2xl shadow-2xl max-w-md w-full mx-4 p-6">
            <h3 class="text-lg font-bold text-gray-900 mb-2">Submit your assessment?</h3>
            <p class="text-sm text-gray-600 mb-4">
              You've answered {@answered_count} of {@total_questions}. Once submitted, you can't change your answers.
            </p>
            <div class="flex items-center justify-end gap-2">
              <button type="button" phx-click="close_submit_modal"
                class="px-4 py-2 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition">
                Cancel
              </button>
              <button type="button" phx-click="confirm_submit" disabled={@submitting}
                class={[
                  "inline-flex items-center gap-1.5 px-5 py-2 rounded-lg text-white text-sm font-semibold transition",
                  if(@submitting, do: "cursor-not-allowed opacity-50", else: "")
                ]}
                style="background-color: #FF8B00;">
                {if @submitting, do: "Submitting…", else: "Submit"}
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private functions

  defp get_tenant_schema(tenant_alias) do
    alias VyaasaCampus.Contexts.Tenants
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    if tenant, do: tenant.schema_name, else: nil
  end

  defp calculate_time_remaining(attempt, assessment) do
    if attempt && attempt.started_at do
      elapsed = DateTime.diff(DateTime.utc_now(), attempt.started_at, :second)
      max(0, assessment.duration_minutes * 60 - elapsed)
    else
      0
    end
  end

  defp get_question_options(question) do
    Map.get(question, :options, %{})
    |> Enum.sort_by(fn {key, _} -> key end)
  end

  defp review_option_style(:post_submit, _picked, true = _correct, _your_wrong) do
    "background-color: #ECFDF5; border-color: #22C55E;"
  end

  defp review_option_style(:post_submit, _picked, _correct, true = _your_wrong) do
    "background-color: #FEF2F2; border-color: #DC2626;"
  end

  defp review_option_style(:pre_submit, true = _picked, _correct, _your_wrong) do
    "background-color: #FFF6EC; border-color: #FF8B00;"
  end

  defp review_option_style(_, _, _, _),
    do: "background-color: #F9FAFB; border-color: #E5E7EB;"

  defp review_letter_style(:post_submit, _picked, true, _your_wrong),
    do: "background-color: #22C55E; color: white;"

  defp review_letter_style(:post_submit, _picked, _correct, true),
    do: "background-color: #DC2626; color: white;"

  defp review_letter_style(:pre_submit, true, _correct, _your_wrong),
    do: "background-color: #FF8B00; color: white;"

  defp review_letter_style(_, _, _, _),
    do: "background-color: #F4ECDD; color: #6B7280;"

  defp build_why_fallback(_question, nil), do: nil

  defp build_why_fallback(question, correct_answer) do
    options = Map.get(question, :options, %{})
    correct_text = Map.get(options, to_string(correct_answer)) || Map.get(options, correct_answer)

    if is_binary(correct_text) and correct_text != "" do
      "The correct answer is #{String.upcase(to_string(correct_answer))}: #{correct_text}"
    else
      nil
    end
  end

  defp count_answered(answers, questions) do
    question_ids = Enum.map(questions, &to_string(&1.id)) |> MapSet.new()
    Map.keys(answers) |> Enum.filter(&MapSet.member?(question_ids, to_string(&1))) |> length()
  end

  defp count_unanswered(answers, questions) do
    total = length(questions)
    answered = count_answered(answers, questions)
    total - answered
  end
end
