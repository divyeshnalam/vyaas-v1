defmodule VyaasaCampusWeb.Student.Assessment.ResultLive do
  @moduledoc """
  LiveView for Assessment Results/Score Screen.
  Shows instant score and performance breakdown.
  """

  use VyaasaCampusWeb, :live_view
  require Logger

  alias VyaasaCampus.Contexts.{Assessments, StudentAts}
  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(%{"tenant" => tenant_alias, "id" => assessment_id}, _session, socket) do
    require Logger

    tenant_schema = get_tenant_schema(tenant_alias)
    current_user = socket.assigns[:current_user]

    # Get assessment
    assessment = Assessments.get_assessment!(assessment_id, tenant_schema)

    # The latest attempt by SUBMISSION time (not start time) — otherwise a retake
    # submitted last but started earlier would show a stale older result.
    attempt =
      Assessments.get_latest_submitted_attempt(assessment.id, current_user.id, tenant_schema)

    cond do
      is_nil(attempt) ->
        {:ok, redirect(socket, to: "/student/#{tenant_alias}/dashboard")}

      # Authorization: attempt must belong to current user
      attempt.student_id != current_user.id ->
        Logger.warning("Unauthorized result access: attempt by user #{current_user.id}")
        {:ok, redirect(socket, to: "/student/#{tenant_alias}/dashboard")}

      true ->
        mount_result(socket, tenant_alias, tenant_schema, current_user, assessment, attempt)
    end
  end

  defp mount_result(socket, tenant_alias, tenant_schema, current_user, assessment, attempt) do
    # Calculate performance metrics from evaluation_data
    eval = attempt.evaluation_data || %{}
    percentage = safe_decimal_to_float(attempt.percentage)
    score = safe_decimal_to_float(attempt.score)

    correct = eval["correct"] || 0
    wrong = eval["wrong"] || 0
    unanswered = eval["unanswered"] || 0
    negative_marks = safe_to_float(eval["negative_marks"])
    total_questions = eval["total_questions"] || length(assessment.settings["questions"] || [])

    # Calculate time taken
    time_taken =
      if attempt.started_at && attempt.submitted_at do
        DateTime.diff(attempt.submitted_at, attempt.started_at, :second)
      else
        0
      end

    avg_time_per_question =
      if total_questions > 0, do: Float.round(time_taken / 60 / total_questions, 1), else: 0.0

    skill_breakdown =
      compute_skill_breakdown(assessment.settings["questions"] || [], attempt.answers || %{})

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
      |> assign(:score, score)
      |> assign(:total_marks, assessment.total_marks || 0)
      |> assign(:percentage, percentage)
      |> assign(:correct, correct)
      |> assign(:wrong, wrong)
      |> assign(:unanswered, unanswered)
      |> assign(:negative_marks, negative_marks)
      |> assign(:total_questions, total_questions)
      |> assign(:time_taken, time_taken)
      |> assign(:avg_time_per_question, avg_time_per_question)
      |> assign(:performance_label, get_performance_label(percentage))
      |> assign(:performance_color, get_performance_color(percentage))
      |> assign(:show_confetti, percentage >= 75)
      |> assign(:skill_breakdown, skill_breakdown)
      |> assign(:retry_error, nil)
      |> assign(:retry_error_title, "Something went wrong")

    {:ok, socket}
  end

  defp compute_skill_breakdown(questions, answers) do
    questions
    |> Enum.group_by(fn q -> q["subject"] || q["subject_name"] || "General" end)
    |> Enum.map(fn {subject, qs} ->
      total = length(qs)

      correct =
        Enum.count(qs, fn q ->
          qid = to_string(q["id"])
          ans = Map.get(answers, qid) || Map.get(answers, q["id"])
          ans && to_string(ans) == to_string(q["correct_answer"])
        end)

      %{subject: format_subject_label(subject), correct: correct, total: total}
    end)
    |> Enum.sort_by(& &1.subject)
  end

  defp format_subject_label(s) when is_binary(s) do
    s
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_subject_label(_), do: "General"

  @impl true
  def handle_event("back_to_dashboard", _params, socket) do
    {:noreply, redirect(socket, to: "/student/#{socket.assigns.tenant_alias}/dashboard")}
  end

  @impl true
  def handle_event("review_questions", _params, socket) do
    {:noreply,
     redirect(socket,
       to:
         ~p"/student/#{socket.assigns.tenant_alias}/assessment/#{socket.assigns.assessment.id}/review?attempt=#{socket.assigns.attempt.id}"
     )}
  end

  @impl true
  def handle_event("retry_assessment", _params, socket) do
    # Retake gets a FRESH, newly randomised question set — not the same
    # assessment's identical questions/order (Vya-001).
    case Assessments.retake_with_new_assessment(
           socket.assigns.current_user.id,
           socket.assigns.tenant_schema
         ) do
      {:ok, assessment, attempt} ->
        {:noreply,
         redirect(socket,
           to:
             ~p"/student/#{socket.assigns.tenant_alias}/assessment/#{assessment.id}/test?attempt=#{attempt.id}"
         )}

      {:error, :attempt_limit_reached, _details} ->
        {:noreply,
         socket
         |> assign(:retry_error_title, "Out of attempts")
         |> assign(
           :retry_error,
           "You've used all your available assessment attempts. Please contact your college admin to request more."
         )}

      {:error, :no_questions_available} ->
        {:noreply,
         socket
         |> assign(:retry_error_title, "Something went wrong")
         |> assign(
           :retry_error,
           "No questions are configured for your role yet. Please contact your administrator."
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:retry_error_title, "Something went wrong")
         |> assign(:retry_error, "Failed to start a new attempt. Please try again.")}
    end
  end

  @impl true
  def handle_event("resend_report", _params, socket) do
    schema = socket.assigns.tenant_schema
    tenant_alias = socket.assigns.tenant_alias

    case socket.assigns[:attempt] do
      %{id: id, status: "submitted"} ->
        case VyaasaCampus.Jobs.ReportGenerator.enqueue(:mcq, id, schema, tenant_alias) do
          {:ok, %Oban.Job{}} ->
            {:noreply, put_flash(socket, :info, "Your assessment report is queued and will be emailed shortly.")}

          {:ok, _} ->
            {:noreply, put_flash(socket, :info, "Your assessment report is queued and will be emailed shortly.")}

          {:error, reason} ->
            Logger.error("Failed to queue MCQ report email: #{inspect(reason)}")
            {:noreply, put_flash(socket, :error, "Could not queue the report email. Please try again.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "No completed assessment to email yet.")}
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

    accuracy =
      if assigns.correct + assigns.wrong > 0,
        do: round(assigns.correct / (assigns.correct + assigns.wrong) * 100),
        else: 0

    completion =
      if assigns.total_questions > 0,
        do: round((assigns.correct + assigns.wrong) / assigns.total_questions * 100),
        else: 0

    assigns =
      assigns
      |> assign(:user_info, user_info)
      |> assign(:accuracy, accuracy)
      |> assign(:completion, completion)

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-cream-50 flex">
        <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar
          current_section="mcq"
          tenant_alias={@tenant_alias}
          student_name={@user_info.name}
        />

        <div class="flex-1 flex flex-col min-w-0">
          <VyaasaCampusWeb.Components.Student.HeaderComponent.header user_info={@user_info} tenant_alias={@tenant_alias} />

          <main class="flex-1 overflow-auto">
            <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-300 mx-auto w-full">
            <div class="flex items-start gap-3 mb-6">
              <div
                class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
                style="background-color: #FFE9D2;"
              >
                <.icon name="hero-trophy" class="w-5 h-5" style="color: #B85F00;" />
              </div>
              <div>
                <p class="text-[11px] font-semibold tracking-[0.18em] uppercase" style="color: #FF8B00;">Objective Evaluation · Insights</p>
                <h1 class="text-2xl font-bold text-gray-900">Nice progress</h1>
                <p class="text-sm text-gray-500 mt-0.5">Calm, supportive view of how you did and exactly where to grow next.</p>
              </div>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
              <div class="rounded-2xl border border-cream-200 p-6" style="background-color: #FFF1DE;">
                <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">Score Overview</p>
                <div class="flex items-center gap-6">
                  <div class="relative w-32 h-32 shrink-0">
                    <svg class="w-32 h-32 transform -rotate-90" viewBox="0 0 100 100">
                      <circle cx="50" cy="50" r="42" fill="none" stroke="#F4ECDD" stroke-width="8"/>
                      <circle cx="50" cy="50" r="42" fill="none" stroke="#FF8B00" stroke-width="8"
                        stroke-dasharray="263.89"
                        stroke-dashoffset={263.89 * (1 - @percentage / 100)}
                        stroke-linecap="round" />
                    </svg>
                    <div class="absolute inset-0 flex flex-col items-center justify-center">
                      <div class="text-2xl font-bold text-gray-900">{@correct}/{@total_questions}</div>
                      <div class="text-[10px] text-gray-500">correct</div>
                    </div>
                  </div>
                  <div>
                    <div class="text-3xl font-bold" style="color: #FF8B00;">{round(@percentage)}%</div>
                    <div class="text-[10px] text-gray-500 mt-0.5">overall score · correct out of all {@total_questions} questions</div>
                    <%!-- <div class="text-xs text-green-600 mt-1">+{round(@score)} XP earned</div> --%>
                  </div>
                </div>
              </div>

              <div class="bg-white rounded-2xl border border-gray-100 p-6">
                <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">Score Breakdown</p>
                <div class="grid grid-cols-4 gap-2">
                  <.score_tile icon="hero-check" label="Correct" value={"#{@correct}"} color="green" />
                  <.score_tile icon="hero-academic-cap" label="To learn" value={"#{@wrong}"} color="brand" />
                  <.score_tile icon="hero-clock" label="Skipped" value={"#{@unanswered}"} color="gray" />
                  <.score_tile icon="hero-trophy" label="Accuracy" value={"#{@accuracy}%"} color="brand" />
                </div>

                <div class="mt-4 pt-4 border-t border-cream-200 space-y-2.5 text-xs">
                  <div>
                    <div class="flex items-center justify-between mb-1">
                      <span class="text-gray-500">Accuracy</span>
                      <span class="font-medium text-gray-700">{@correct}/{@correct + @wrong} correct ({@accuracy}%)</span>
                    </div>
                    <div class="h-1.5 bg-cream-200 rounded-full overflow-hidden">
                      <div class="h-full rounded-full" style={"width: #{@accuracy}%; background-color: #FF8B00;"}></div>
                    </div>
                  </div>
                  <div>
                    <div class="flex items-center justify-between mb-1">
                      <span class="text-gray-500">Completion</span>
                      <span class="font-medium text-gray-700">{@correct + @wrong}/{@total_questions} attempted ({@completion}%)</span>
                    </div>
                    <div class="h-1.5 bg-cream-200 rounded-full overflow-hidden">
                      <div class="h-full rounded-full" style={"width: #{@completion}%; background-color: #FF8B00;"}></div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <%= if @skill_breakdown != [] do %>
              <div class="bg-white rounded-2xl border border-gray-100 p-5 mb-6">
                <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-4">Skill Breakdown</p>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-4">
                  <%= for skill <- @skill_breakdown do %>
                    <div>
                      <div class="flex items-center justify-between text-sm mb-1">
                        <span class="text-gray-700">{skill.subject}</span>
                        <span class="text-gray-500">{skill.correct}/{skill.total}</span>
                      </div>
                      <div class="h-1.5 bg-cream-200 rounded-full overflow-hidden">
                        <div class="h-full rounded-full"
                          style={"width: #{if skill.total > 0, do: round(skill.correct / skill.total * 100), else: 0}%; background-color: #FF8B00;"}></div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
              <div class="rounded-2xl border p-5" style="background-color: #ECFDF5; border-color: #A7F3D0;">
                <div class="flex items-center gap-2 mb-2">
                  <.icon name="hero-arrow-trending-up" class="w-4 h-4 text-green-700" />
                  <p class="text-sm font-semibold text-green-800">Vyaasa strengths</p>
                </div>
                <ul class="text-xs text-green-800 space-y-1">
                  <li>· Solid grasp of foundational concepts</li>
                  <li>· Comfortable pacing — no rushed answers</li>
                </ul>
              </div>

              <div class="rounded-2xl border p-5" style="background-color: #FFF1DE; border-color: #F6D9AE;">
                <div class="flex items-center gap-2 mb-2">
                  <.icon name="hero-light-bulb" class="w-4 h-4" style="color: #B85F00;" />
                  <p class="text-sm font-semibold" style="color: #B85F00;">Vyaasa recommendations</p>
                </div>
                <ul class="text-xs space-y-1" style="color: #B85F00;">
                  <li>· Watch a 4-min refresher on weaker topics</li>
                  <li>· Retake in 24 hours — confidence locks in with spacing</li>
                </ul>
              </div>
            </div>

            <.error_card
              :if={@retry_error}
              title={@retry_error_title}
              error_message={@retry_error}
              retry_event="retry_assessment"
              class="mb-6"
            />

            <div class="flex flex-wrap items-center gap-3">
              <button type="button" phx-click="review_questions"
                class="inline-flex items-center gap-1.5 px-4 py-2.5 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition">
                <.icon name="hero-eye" class="w-4 h-4" /> Review Questions
              </button>
              <button type="button"
                phx-click="resend_report"
                class="inline-flex items-center gap-1.5 px-4 py-2.5 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition">
                <.icon name="hero-envelope" class="w-4 h-4" />
                Email me the report
              </button>
              <button :if={!@retry_error} type="button" phx-click="retry_assessment"
                class="inline-flex items-center gap-1.5 px-4 py-2.5 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition">
                <.icon name="hero-arrow-path" class="w-4 h-4" /> Retry Assessment
              </button>
              <button :if={!@retry_error} type="button" phx-click="back_to_dashboard"
                class="inline-flex items-center gap-1.5 px-4 py-2.5 rounded-lg border border-gray-200 text-sm text-white hover:bg-cream-50 transition"
                style="background-color: #FF8B00;">
                <.icon name="hero-home" class="w-4 h-4" /> Go to Dashboard
              </button>
            </div>
            </div>
          </main>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:color, :string, default: "brand")

  defp score_tile(assigns) do
    assigns = assign(assigns, :tile_style, tile_style(assigns.color))

    ~H"""
    <div class="rounded-xl border p-3 text-center" style={@tile_style}>
      <.icon name={@icon} class="w-4 h-4 mx-auto mb-1" />
      <div class="text-lg font-bold">{@value}</div>
      <div class="text-[10px] uppercase tracking-wider">{@label}</div>
    </div>
    """
  end

  defp tile_style("green"),
    do: "background-color: #ECFDF5; border-color: #A7F3D0; color: #047857;"

  defp tile_style("brand"),
    do: "background-color: #FFF1DE; border-color: #F6D9AE; color: #B85F00;"

  defp tile_style("gray"), do: "background-color: #F9FAFB; border-color: #E5E7EB; color: #6B7280;"
  defp tile_style(_), do: "background-color: #F9FAFB; border-color: #E5E7EB; color: #6B7280;"

  defp get_tenant_schema(tenant_alias) do
    alias VyaasaCampus.Contexts.Tenants
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    if tenant, do: tenant.schema_name, else: nil
  end

  defp safe_decimal_to_float(nil), do: 0.0
  defp safe_decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp safe_decimal_to_float(val) when is_float(val), do: val
  defp safe_decimal_to_float(val) when is_integer(val), do: val / 1
  defp safe_decimal_to_float(_), do: 0.0

  defp safe_to_float(nil), do: 0.0
  defp safe_to_float(val) when is_float(val), do: val
  defp safe_to_float(val) when is_integer(val), do: val / 1

  defp safe_to_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp safe_to_float(_), do: 0.0

  defp get_performance_label(percentage) when percentage >= 90, do: "🌟 Outstanding"
  defp get_performance_label(percentage) when percentage >= 75, do: "🎯 Excellent"
  defp get_performance_label(percentage) when percentage >= 60, do: "👍 Good"
  defp get_performance_label(percentage) when percentage >= 40, do: "📈 Needs Improvement"
  defp get_performance_label(_), do: "💪 Keep Trying"

  defp get_performance_color(percentage) when percentage >= 75, do: :green
  defp get_performance_color(percentage) when percentage >= 60, do: :amber
  defp get_performance_color(percentage) when percentage >= 40, do: :orange
  defp get_performance_color(_), do: :red

  defp text_color_class(:green), do: "text-green-600"
  defp text_color_class(:amber), do: "text-amber-600"
  defp text_color_class(:orange), do: "text-orange-600"
  defp text_color_class(:red), do: "text-red-600"

  defp circle_color(:green), do: "#22C55E"
  defp circle_color(:amber), do: "#F59E0B"
  defp circle_color(:orange), do: "#F97316"
  defp circle_color(:red), do: "#EF4444"

  defp badge_color_class(:green), do: "bg-green-100 text-green-700"
  defp badge_color_class(:amber), do: "bg-amber-100 text-amber-700"
  defp badge_color_class(:orange), do: "bg-orange-100 text-orange-700"
  defp badge_color_class(:red), do: "bg-red-100 text-red-700"
end
