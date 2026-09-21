defmodule VyaasaCampusWeb.Student.DashboardLive do
  @moduledoc """
  LiveView for student dashboard.
  Shows student profile information from both student and student_ats tables.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.{
    AI8,
    Assessments,
    AttemptGuard,
    Behavioral,
    CaseStudy,
    Entitlements,
    Interview,
    Jam,
    MiniProject,
    Psychometric,
    StudentAts,
    StudentRankings,
    Students,
    Tenants
  }

  alias VyaasaCampus.AI8.Dimensions, as: AI8Dimensions
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampusWeb.Components.Student.Dashboard.Helpers, as: DH
  alias VyaasaCampusWeb.DateTimeFormatter
  import VyaasaCampusWeb.Components.UI
  import Phoenix.LiveView

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    require Logger

    # Get tenant information
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    tenant_schema = if tenant, do: tenant.schema_name, else: nil

    # Get current user from socket assigns (set by AuthPlug)
    current_user = socket.assigns[:current_user]

    Logger.info("Student dashboard mount - tenant: #{tenant_alias}, current_user: #{inspect(current_user)}")

    case current_user do
      nil ->
        Logger.warning("No current user found in socket assigns")
        {:ok, setup_error_socket(socket, "Authentication required")}

      _user ->
        handle_authenticated_mount(socket, current_user, tenant, tenant_alias, tenant_schema)
    end
  end

  @impl true
  def mount(%{"profile_token" => profile_token}, _session, socket) do
    require Logger

    Logger.info("Student dashboard mount - profile_token: #{profile_token}")

    case find_student_by_token(profile_token) do
      {:ok, {student, ats_data, tenant_schema}} ->
        {:ok, setup_successful_socket(socket, student, ats_data, tenant_schema)}

      {:error, reason} ->
        {:ok, setup_error_socket(socket, reason)}
    end
  end

  @impl true
  def handle_event("logout", _params, socket) do
    # Handle logout - redirect to login page
    socket =
      socket
      |> put_flash(:info, "Logged out successfully")
      |> redirect(to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")

    {:noreply, socket}
  end

  @impl true
  def handle_event("reanalyze_resume", _params, socket) do
    # Authenticated route — no profile_token needed. Each re-analysis is
    # stored as a new ATS phase so students can track score improvements.
    {:noreply,
     redirect(socket,
       to: ~p"/student/#{socket.assigns.tenant_alias}/resume/reanalyze"
     )}
  end

  @impl true
  def handle_event("start_instruction", %{"instruction" => instruction_id}, socket) do
    require Logger
    Logger.info("Starting instruction: #{instruction_id}")

    case instruction_id do
      "objective_evaluation" ->
        {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/assessment/instructions")}

      "behavioral_questions" ->
        {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/assessment/behavioral")}

      "jam_session" ->
        # Navigate to JAM session
        {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/jam/session")}

      "ai_introduction" ->
        # Navigate to AI Interview session
        {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/interview/session")}

      "psychometric" ->
        # Navigate to Psychometric Assessment
        {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/assessment/psychometric")}

      "case_study" ->
        {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/case-study")}

      "mini_project" ->
        {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/mini-project")}

      _ ->
        # For other instructions, show a flash message
        socket = put_flash(socket, :info, "Starting #{instruction_id} instruction...")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("view_results", _params, socket) do
    attempt = socket.assigns[:submitted_attempt]
    tenant_alias = socket.assigns.tenant_alias

    if attempt do
      {:noreply, redirect(socket, to: ~p"/student/#{tenant_alias}/assessment/#{attempt.assessment_id}/result")}
    else
      {:noreply, put_flash(socket, :error, "No completed assessment found.")}
    end
  end

  # view_behavioral_results and view_psychometric_results are handled by start_instruction

  @impl true
  def handle_event("view_resume_insights", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/resume/insights")}
  end

  @impl true
  def handle_event("show_coming_soon", _params, socket) do
    socket = put_flash(socket, :info, "Settings coming soon!")
    {:noreply, socket}
  end

  @impl true
  def handle_event("download_resume", _params, socket) do
    ats_data = socket.assigns.ats_data

    if ats_data && ats_data[:resume_url] do
      filename = Path.basename(ats_data.resume_url)
      student_id = socket.assigns.student.id
      tenant_alias = socket.assigns.tenant_alias
      download_url = "/api/tenant/students/#{student_id}/resume/#{filename}?tenant=#{tenant_alias}"

      {:noreply, redirect(socket, external: download_url)}
    else
      {:noreply, put_flash(socket, :error, "No resume available for download.")}
    end
  end

  @impl true
  def handle_event("share_profile", _params, socket) do
    student_id = socket.assigns.student.id
    tenant_schema = socket.assigns.tenant_schema

    share_url = VyaasaCampus.Reports.share_profile_url(student_id, tenant_schema)

    {:noreply,
     socket
     |> assign(:share_url, share_url)
     |> assign(:show_share_modal, true)}
  end

  @impl true
  def handle_event("close_share_modal", _params, socket) do
    {:noreply, assign(socket, :show_share_modal, false)}
  end

  @impl true
  def handle_event("copy_share_link", _params, socket) do
    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: socket.assigns.share_url})
     |> put_flash(:info, "Link copied to clipboard!")}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("switch_section", %{"section" => section}, socket) do
    {:noreply, assign(socket, :active_section, section)}
  end

  # Real-time student dashboard: any change to this student's profile,
  # assessments, ATS or session results triggers a debounced reload so the
  # cards on screen stay current without a page refresh.
  @impl true
  def handle_info({:dashboard_event, _payload}, socket) do
    {:noreply, schedule_student_reload(socket)}
  end

  @impl true
  def handle_info(:reload_student_dashboard, socket) do
    {:noreply,
     socket
     |> assign(:reload_pending?, false)
     |> reload_student_dashboard_data()}
  end

  defp schedule_student_reload(socket) do
    if Map.get(socket.assigns, :reload_pending?, false) do
      socket
    else
      Process.send_after(self(), :reload_student_dashboard, 300)
      assign(socket, :reload_pending?, true)
    end
  end

  defp reload_student_dashboard_data(socket) do
    require Logger

    student = socket.assigns[:student]
    tenant_schema = socket.assigns[:tenant_schema]

    if is_nil(student) or is_nil(tenant_schema) do
      socket
    else
      try do
        student_id = student.id

        refreshed_student =
          case Students.get_student(student_id, tenant_schema) do
            nil -> student
            s -> convert_student_to_simple_map(s)
          end

        ats_data =
          StudentAts.get_by_student_id(student_id, tenant_schema)
          |> convert_ats_data_to_simple_map()

        submitted_attempt =
          try do
            Assessments.get_student_latest_submitted_attempt(student_id, tenant_schema)
          rescue
            _ -> nil
          end

        has_completed_interview =
          try do
            case Interview.get_completed_interviews(student_id, tenant_schema) do
              [_ | _] -> true
              _ -> false
            end
          rescue
            _ -> false
          end

        has_completed_jam =
          try do
            case Jam.get_completed_jam_sessions(student_id, tenant_schema) do
              [_ | _] -> true
              _ -> false
            end
          rescue
            _ -> false
          end

        behavioral_completed =
          try do
            Behavioral.assessment_completed?(student_id, tenant_schema)
          rescue
            _ -> false
          end

        psychometric_completed =
          try do
            Psychometric.assessment_completed?(student_id, tenant_schema)
          rescue
            _ -> false
          end

        module_statuses = load_module_statuses(student_id, tenant_schema)
        {rankings, ai8_data} = load_rankings(student_id, tenant_schema)

        socket
        |> assign(:student, refreshed_student)
        |> assign(:ats_data, ats_data)
        |> assign(:submitted_attempt, submitted_attempt)
        |> assign(:has_completed_interview, has_completed_interview)
        |> assign(:has_completed_jam, has_completed_jam)
        |> assign(:behavioral_completed, behavioral_completed)
        |> assign(:psychometric_completed, psychometric_completed)
        |> assign(module_statuses)
        |> assign(:rankings, rankings)
        |> assign(:ai8_data, ai8_data)
        |> assign(:attempt_history, load_attempt_history(student_id, tenant_schema))
        |> assign(:attempt_counts, load_attempt_counts(student_id, tenant_schema))
        |> assign(:attempt_limits, load_attempt_limits(student_id, socket.assigns[:tenant], tenant_schema))
      rescue
        e ->
          Logger.error("Student dashboard live reload failed: #{Exception.message(e)}")
          socket
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="toast-container" phx-hook="ToastContainer" class="fixed top-4 right-4 z-50 space-y-2"></div>

      <%= if @student do %>
        <div class="min-h-screen bg-cream-50 flex">
          <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar
            current_section="dashboard"
            tenant_alias={@tenant_alias}
            student_name={@user_info.name}
            rankings={@rankings}
          />

          <div class="flex-1 flex flex-col min-w-0">
            <VyaasaCampusWeb.Components.Student.HeaderComponent.header
              user_info={@user_info}
              tenant_alias={@tenant_alias}
              page_title="Dashboard"
            />

            <main class="flex-1 overflow-auto">
              <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-7xl mx-auto w-full">
                <!-- Page header -->
                <div class="flex items-start gap-3 mb-6 bg-white rounded-2xl border border-gray-100 shadow-card-soft px-6 py-5">
                  <div class="w-10 h-10 rounded-xl bg-brand-100 flex items-center justify-center shrink-0">
                    <.icon name="hero-squares-2x2" class="w-5 h-5 text-brand-600" />
                  </div>
                  <div>
                    <h1 class="text-2xl font-bold text-gray-900">Assessments</h1>
                    <p class="text-sm text-gray-500 mt-0.5">Choose any module. Practice freely.</p>
                  </div>
                </div>

                <!-- Assessment grid -->
                <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
                  <.module_card
                    icon="hero-document-text"
                    tags={Map.get(@ai8_tags, "resume", [])}
                    status={if @ats_data, do: "Completed", else: "Not started"}
                    title="Resume Insights"
                    description="Vyaasa parses, scores and improves your resume for ATS readiness."
                    progress={if @ats_data && @ats_data[:ats_score], do: round(@ats_data.ats_score), else: 0}
                    time="8 min"
                    difficulty="Beginner"
                    insight={resume_insight(@ats_data)}
                    completed={@ats_data != nil}
                    primary_event="reanalyze_resume"
                    secondary_event={if @ats_data, do: "view_resume_insights", else: "reanalyze_resume"}
                  />

                  <.module_card
                    icon="hero-microphone"
                    tags={Map.get(@ai8_tags, "interview", [])}
                    status={module_status(@has_completed_interview, @attempt_counts.interview)}
                    title="Interactive Session"
                    description="A friendly intro session with Vyaasa listening & encouraging tips."
                    progress={progress_for(@rankings.interview)}
                    attempts={@attempt_counts.interview}
                    attempt_limit={Map.get(@attempt_limits, :interview)}
                    completed={@has_completed_interview}
                    started={@attempt_counts.interview > 0}
                    time="12 min"
                    difficulty="Intermediate"
                    primary_event="start_instruction"
                    primary_value={%{"instruction" => "ai_introduction"}}
                    secondary_event="start_instruction"
                    secondary_value={%{"instruction" => "ai_introduction"}}
                  />

                  <.module_card
                    icon="hero-puzzle-piece"
                    tags={Map.get(@ai8_tags, "mcq", [])}
                    status={module_status(@submitted_attempt != nil, @attempt_counts.mcq)}
                    title="Objective / MCQs"
                    description="Calm, focused questions to test domain & problem-solving."
                    progress={progress_for(@rankings.mcq, :percentage)}
                    attempts={@attempt_counts.mcq}
                    attempt_limit={Map.get(@attempt_limits, :mcq)}
                    completed={@submitted_attempt != nil}
                    started={@attempt_counts.mcq > 0}
                    time="15 min"
                    difficulty="Intermediate"
                    primary_event="start_instruction"
                    primary_value={%{"instruction" => "objective_evaluation"}}
                    secondary_event={if @submitted_attempt, do: "view_results", else: "start_instruction"}
                    secondary_value={%{"instruction" => "objective_evaluation"}}
                  />

                  <.module_card
                    icon="hero-chat-bubble-left-right"
                    tags={Map.get(@ai8_tags, "jam", [])}
                    status={module_status(@has_completed_jam, @attempt_counts.jam)}
                    title="JAM Session"
                    description="Just-a-minute speaking with live coaching and feedback."
                    progress={progress_for(@rankings.jam)}
                    attempts={@attempt_counts.jam}
                    attempt_limit={Map.get(@attempt_limits, :jam)}
                    completed={@has_completed_jam}
                    started={@attempt_counts.jam > 0}
                    time="5 min"
                    difficulty="Beginner"
                    primary_event="start_instruction"
                    primary_value={%{"instruction" => "jam_session"}}
                    secondary_event="start_instruction"
                    secondary_value={%{"instruction" => "jam_session"}}
                  />

                  <.module_card
                    icon="hero-user-group"
                    tags={Map.get(@ai8_tags, "behavioral", [])}
                    status={module_status(@behavioral_completed, @attempt_counts.behavioral)}
                    title="Situational & Behavioral"
                    description="STAR-method scenarios with Vyaasa guidance for each step."
                    progress={progress_for(@rankings.behavioral)}
                    attempts={@attempt_counts.behavioral}
                    attempt_limit={Map.get(@attempt_limits, :behavioral)}
                    completed={@behavioral_completed}
                    started={@attempt_counts.behavioral > 0}
                    time="10 min"
                    difficulty="Intermediate"
                    primary_event="start_instruction"
                    primary_value={%{"instruction" => "behavioral_questions"}}
                    secondary_event="start_instruction"
                    secondary_value={%{"instruction" => "behavioral_questions"}}
                  />

                  <.module_card
                    icon="hero-light-bulb"
                    tags={Map.get(@ai8_tags, "psychometric", [])}
                    status={module_status(@psychometric_completed, @attempt_counts.psychometric)}
                    title="Psychometric Assessment"
                    description="Big Five personality with adaptive friendly questions."
                    progress={progress_for(@rankings.psychometric)}
                    attempts={@attempt_counts.psychometric}
                    attempt_limit={Map.get(@attempt_limits, :psychometric)}
                    completed={@psychometric_completed}
                    started={@attempt_counts.psychometric > 0}
                    time="12 min"
                    difficulty="Beginner"
                    primary_event="start_instruction"
                    primary_value={%{"instruction" => "psychometric"}}
                    secondary_event="start_instruction"
                    secondary_value={%{"instruction" => "psychometric"}}
                  />

                  <.module_card
                    icon="hero-academic-cap"
                    tags={Map.get(@ai8_tags, "case_study", [])}
                    status={if @case_study_started, do: "Attempted", else: "Not started"}
                    title="Case Studies"
                    description="Solve a realistic problem with structured thinking canvas."
                    progress={@case_study_progress}
                    attempts={@attempt_counts.case_study}
                    attempt_limit={Map.get(@attempt_limits, :case_study)}
                    started={@case_study_started}
                    completed={@case_study_completed}
                    time="20 min"
                    difficulty="Advanced"
                    primary_event="start_instruction"
                    primary_value={%{"instruction" => "case_study"}}
                    secondary_event="start_instruction"
                    secondary_value={%{"instruction" => "case_study"}}
                  />

                  <.module_card
                    icon="hero-wrench-screwdriver"
                    tags={Map.get(@ai8_tags, "mini_project", [])}
                    status={if @mini_project_started, do: "Attempted", else: "Not started"}
                    title="Mini Project"
                    description="Build & submit a domain mini project. Vyaasa evaluates approach."
                    progress={@mini_project_progress}
                    attempts={@attempt_counts.mini_project}
                    attempt_limit={Map.get(@attempt_limits, :mini_project)}
                    started={@mini_project_started}
                    completed={@mini_project_completed}
                    time="2 days"
                    difficulty="Advanced"
                    primary_event="start_instruction"
                    primary_value={%{"instruction" => "mini_project"}}
                    secondary_event="start_instruction"
                    secondary_value={%{"instruction" => "mini_project"}}
                  />
                </div>

                <!-- Bottom: Next steps + Achievements -->
                <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  <.next_steps_card rankings={@rankings} has_completed_interview={@has_completed_interview} has_completed_jam={@has_completed_jam} behavioral_completed={@behavioral_completed} psychometric_completed={@psychometric_completed} submitted_attempt={@submitted_attempt} ats_data={@ats_data} />
                  <.recent_achievements_card rankings={@rankings} ai8_data={@ai8_data} />
                </div>
              </div>
            </main>
          </div>
        </div>

        <!-- Share Profile Modal (preserved) -->
        <%= if @show_share_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" phx-click="close_share_modal">
            <div class="bg-white rounded-2xl shadow-2xl max-w-lg w-full mx-4 p-6" phx-click-away="close_share_modal">
              <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-bold text-gray-900">Share Your Profile</h3>
                <button phx-click="close_share_modal" class="text-gray-400 hover:text-gray-600">
                  <.icon name="hero-x-mark" class="w-5 h-5" />
                </button>
              </div>
              <p class="text-sm text-gray-600 mb-4">
                Anyone with this link can view your profile and assessment scores.
              </p>
              <div class="flex items-center gap-2 mb-4">
                <input
                  type="text"
                  value={@share_url}
                  readonly
                  class="flex-1 px-3 py-2 border border-gray-200 rounded-lg text-sm text-gray-700 bg-gray-50 focus:outline-none"
                  id="share-url-input"
                />
                <button
                  phx-click="copy_share_link"
                  class="px-4 py-2 bg-brand-500 text-white rounded-lg text-sm font-medium hover:bg-brand-600 transition flex items-center gap-1.5"
                >
                  <.icon name="hero-clipboard-document" class="w-4 h-4" />
                  Copy
                </button>
              </div>
            </div>
          </div>
        <% end %>

      <% else %>
        <!-- Invalid Token -->
        <div class="min-h-screen flex items-center justify-center bg-cream-50">
          <div class="max-w-md w-full space-y-8">
            <div class="text-center">
              <div class="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-red-600" />
              </div>
              <h1 class="text-2xl font-bold text-gray-900 mb-2">Invalid Access</h1>
              <p class="text-gray-600">
                The profile token is invalid or has expired. Please contact your administrator to get a new access link.
              </p>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  # ============================================================================
  # NEW UI COMPONENTS
  # ============================================================================

  attr :icon, :string, required: true
  attr :tags, :list, default: []
  attr :status, :string, default: "Not started"
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :progress, :integer, default: 0
  attr :started, :boolean, default: false
  attr :completed, :boolean, default: false
  attr :time, :string, default: ""
  attr :difficulty, :string, default: ""
  attr :insight, :map, default: nil
  attr :attempts, :integer, default: nil
  attr :attempt_limit, :integer, default: nil
  attr :primary_event, :string, required: true
  attr :primary_value, :map, default: %{}
  attr :secondary_event, :string, default: nil
  attr :secondary_value, :map, default: %{}
  attr :disabled, :boolean, default: false

  defp module_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-200/80 p-6 flex flex-col shadow-[0_2px_8px_rgba(16,24,40,0.06)] hover:shadow-[0_14px_28px_rgba(16,24,40,0.12)] hover:border-brand-200 hover:-translate-y-1 transition duration-200">
      <!-- Click anywhere here to open details (button below is separate) -->
      <div
        phx-click={@secondary_event || @primary_event}
        phx-value-instruction={Map.get(@secondary_value || @primary_value, "instruction")}
        class="flex-1 flex flex-col cursor-pointer"
      >
        <!-- Header: icon + previous score pill -->
        <div class="flex items-start justify-between mb-5">
          <div
            class="w-12 h-12 rounded-xl flex items-center justify-center"
            style="background-color: #FFE9D2;"
          >
            <.icon name={@icon} class="w-6 h-6" style="color: #B85F00;" />
          </div>
          <%= if @completed do %>
            <span class="text-xs font-bold px-3 py-1 rounded-full bg-brand-50 text-brand-600 border border-brand-200">
              {@progress}%
            </span>
          <% else %>
            <span class="text-xs font-semibold px-3 py-1 rounded-full bg-gray-50 text-gray-500 border border-gray-200">
              {@status}
            </span>
          <% end %>
        </div>

        <!-- Title + description -->
        <h3 class="font-bold text-gray-900 text-lg leading-snug mb-2">{@title}</h3>
        <p class="text-sm text-gray-500 leading-relaxed mb-3 line-clamp-2 min-h-10">{@description}</p>

        <!-- Attempts count (per module) -->
        <%= if @attempts != nil do %>
          <p class="flex items-center gap-1.5 text-xs text-gray-400 mb-5">
            <.icon name="hero-arrow-path" class="w-3.5 h-3.5" />
            <span>{attempts_display(@attempts, @attempt_limit)}</span>
          </p>
        <% end %>

        <!-- Tags -->
        <%= if @tags != [] do %>
          <div class="flex flex-wrap gap-2 mb-5">
            <%= for tag <- @tags do %>
              <span class="text-[11px] font-medium px-2.5 py-1 rounded-full bg-cream-100 text-gray-600 border border-cream-200">{tag}</span>
            <% end %>
          </div>
        <% end %>

        <!-- Optional insight callout -->
        <%= if @insight do %>
          <div class={[
            "rounded-lg px-3 py-2 text-[11px] flex items-start gap-1.5",
            insight_class(@insight[:type])
          ]}>
            <.icon name="hero-sparkles" class="w-3.5 h-3.5 shrink-0 mt-0.5" />
            <span>{@insight[:message]}</span>
          </div>
        <% end %>
      </div>

      <!-- Start / Retake — goes straight to the assessment (separate from details click) -->
      <button
        type="button"
        phx-click={@primary_event}
        phx-value-instruction={Map.get(@primary_value, "instruction")}
        disabled={@disabled}
        class={[
          "w-full inline-flex items-center justify-center gap-1.5 px-4 py-3 rounded-xl text-white text-sm font-semibold transition mt-6",
          if(@disabled, do: "cursor-not-allowed opacity-50", else: "cursor-pointer hover:brightness-95")
        ]}
        style="background-color: #FF8B00;"
      >
        <%= if @completed or @started do %>↻ Retake<% else %>▶ Start<% end %>
      </button>
    </div>
    """
  end

  defp insight_class(:improvement), do: "bg-brand-50 text-brand-700 border border-brand-200"
  defp insight_class(:retry), do: "bg-amber-50 text-amber-700 border border-amber-200"
  defp insight_class(:review), do: "bg-green-50 text-green-700 border border-green-200"
  defp insight_class(_), do: "bg-cream-100 text-gray-600 border border-cream-200"

  defp resume_insight(nil), do: nil

  defp resume_insight(%{ats_score: score}) when is_number(score) and score > 0 do
    %{type: :improvement, message: "Score #{round(score)} → try our improvement checklist."}
  end

  defp resume_insight(_), do: nil

  # Status badge consistent with attempt data (Vya-020): an unsubmitted attempt
  # reads "In progress", not "Not started".
  defp module_status(true, _attempts), do: "Completed"
  defp module_status(false, attempts) when is_integer(attempts) and attempts > 0, do: "In progress"
  defp module_status(false, _attempts), do: "Not started"

  defp progress_for(%{completed: true, percentage: pct}) when not is_nil(pct), do: round(safe_to_float(pct))
  defp progress_for(%{completed: true, score: score}) when not is_nil(score), do: round(score)
  defp progress_for(_), do: 0

  defp progress_for(%{completed: true, percentage: pct}, :percentage) when not is_nil(pct),
    do: round(safe_to_float(pct))

  defp progress_for(%{completed: true, score: score}, :percentage) when not is_nil(score), do: round(score)
  defp progress_for(_, :percentage), do: 0

  defp safe_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp safe_to_float(n) when is_number(n), do: n
  defp safe_to_float(_), do: 0

  # Dashboard pills per module, dynamically from the AI8 config: only dimensions
  # the super admin has given a percentage weight → compact labels.
  # Returns %{module_string => [label, ...]}.
  defp ai8_pills do
    AI8.weighted_dimensions_by_module()
    |> Map.new(fn {module, dims} -> {module, Enum.map(dims, &AI8Dimensions.short_label/1)} end)
  end

  attr :rankings, :map, required: true
  attr :has_completed_interview, :boolean, required: true
  attr :has_completed_jam, :boolean, required: true
  attr :behavioral_completed, :boolean, required: true
  attr :psychometric_completed, :boolean, required: true
  attr :submitted_attempt, :any, required: true
  attr :ats_data, :any, required: true

  defp next_steps_card(assigns) do
    steps = build_next_steps(assigns)
    assigns = assign(assigns, :steps, steps)

    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-5 shadow-card-soft">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-arrow-trending-up" class="w-5 h-5 text-brand-500" />
        <h3 class="font-bold text-gray-900">Recommended next steps</h3>
      </div>
      <%= if @steps == [] do %>
        <p class="text-sm text-gray-500">You're all caught up — explore any module to refine your scores.</p>
      <% else %>
        <ul class="space-y-3">
          <%= for {step, idx} <- Enum.with_index(@steps, 1) do %>
            <li class="flex items-start gap-3 p-3 rounded-xl hover:bg-cream-50 transition">
              <div class="w-6 h-6 rounded-full bg-brand-100 text-brand-600 text-xs font-bold flex items-center justify-center shrink-0">{idx}</div>
              <div class="flex-1">
                <p class="text-sm font-semibold text-gray-800">{step.title}</p>
                <p class="text-xs text-gray-500 mt-0.5">{step.description}</p>
              </div>
              <span class="text-[11px] text-gray-400 whitespace-nowrap mt-1">{step.hint}</span>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end

  defp build_next_steps(assigns) do
    candidates = [
      {!assigns.ats_data,
       %{title: "Upload your resume", description: "Get an AI-led ATS readiness snapshot.", hint: "5 min"}},
      {!assigns.has_completed_interview,
       %{
         title: "Start your introduction session",
         description: "A friendly mini Vyaasa session with empathy.",
         hint: "20-30 min"
       }},
      {!assigns.submitted_attempt,
       %{title: "Take the Objective MCQs", description: "Test conceptual understanding & accuracy.", hint: "60-90 min"}},
      {!assigns.has_completed_jam,
       %{title: "Try a JAM Session", description: "Speak for a minute with friendly feedback.", hint: "60 sec"}},
      {!assigns.behavioral_completed,
       %{title: "Share three short stories", description: "Behavioral STAR-led assessment.", hint: "15 min"}},
      {!assigns.psychometric_completed,
       %{title: "Discover your Big Five", description: "Adaptive personality friendly questions.", hint: "8 min"}}
    ]

    candidates
    |> Enum.filter(fn {pending, _} -> pending end)
    |> Enum.take(3)
    |> Enum.map(fn {_, step} -> step end)
  end

  attr :rankings, :map, required: true
  attr :ai8_data, :map, required: true

  defp recent_achievements_card(assigns) do
    achievements = build_achievements(assigns)
    assigns = assign(assigns, :achievements, achievements)

    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-5 shadow-card-soft">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-trophy" class="w-5 h-5 text-brand-500" />
        <h3 class="font-bold text-gray-900">Recent achievements</h3>
      </div>
      <%= if @achievements == [] do %>
        <p class="text-sm text-gray-500">Complete an assessment to earn your first achievement.</p>
      <% else %>
        <ul class="space-y-3">
          <%= for ach <- @achievements do %>
            <li class="flex items-center gap-3 p-3 rounded-xl bg-cream-50">
              <div class="w-9 h-9 rounded-full bg-brand-100 flex items-center justify-center shrink-0">
                <.icon name={ach.icon} class="w-4 h-4 text-brand-600" />
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-sm font-semibold text-gray-800 truncate">{ach.title}</p>
                <p class="text-xs text-gray-500">{ach.description}</p>
              </div>
              <span class="text-xs font-semibold text-brand-600 whitespace-nowrap">{ach.score}</span>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end

  defp build_achievements(assigns) do
    [
      {:mcq, "hero-puzzle-piece", "Objective MCQs", "Conceptual understanding"},
      {:interview, "hero-microphone", "Interactive Session", "Communication & EQ"},
      {:jam, "hero-chat-bubble-left-right", "JAM Session", "Speaking with presence"},
      {:behavioral, "hero-user-group", "Behavioral", "STAR storytelling"},
      {:psychometric, "hero-light-bulb", "Psychometric", "Big Five profile"}
    ]
    |> Enum.filter(fn {key, _, _, _} ->
      case Map.get(assigns.rankings, key) do
        %{completed: true} -> true
        _ -> false
      end
    end)
    |> Enum.take(3)
    |> Enum.map(fn {key, icon, title, description} ->
      data = Map.get(assigns.rankings, key, %{})

      score =
        case key do
          :mcq -> progress_for(data, :percentage)
          _ -> progress_for(data)
        end

      %{icon: icon, title: title, description: description, score: "#{score}%"}
    end)
  end

  # ============================================================================
  # COMPONENT FUNCTIONS
  # ============================================================================

  defp profile_header_card(assigns) do
    initials = get_initials(assigns.user_info.name)
    summary = if assigns.ats_data, do: assigns.ats_data[:professional_summary] || %{}, else: %{}
    preferred_role = if assigns.ats_data, do: assigns.ats_data[:preferred_role], else: nil
    personal_info = if assigns.ats_data, do: assigns.ats_data[:personal_information] || %{}, else: %{}

    photo_url =
      case assigns.ats_data && assigns.ats_data[:profile_picture_url] do
        url when is_binary(url) and url != "" -> url
        _ -> nil
      end

    assigns =
      assigns
      |> assign(:initials, initials)
      |> assign(:photo_url, photo_url)
      |> assign(:preferred_role, preferred_role)
      |> assign(:location, personal_info["location"] || personal_info["city"])
      |> assign(:total_experience, summary["total_experience"])

    ~H"""
    <div class="bg-white border border-gray-100 rounded-xl p-5 sm:p-6 mb-6 hover:shadow-md transition-shadow">
      <div class="flex flex-col sm:flex-row sm:items-start gap-4">
        <!-- Avatar -->
        <div :if={@photo_url} class="w-16 h-16 rounded-xl shrink-0 overflow-hidden">
          <img src={@photo_url} alt={@user_info.name} class="w-full h-full object-cover" />
        </div>
        <div :if={!@photo_url} class="w-16 h-16 bg-linear-to-br from-orange-400 to-orange-600 rounded-xl flex items-center justify-center text-white font-bold text-xl shrink-0">
          {@initials}
        </div>
        <!-- Info -->
        <div class="flex-1 min-w-0">
          <div class="flex flex-wrap items-center gap-2 mb-1">
            <h2 class="text-xl font-bold text-gray-900">{@user_info.name}</h2>
            <%= if @student.status == "verified" do %>
              <span class="inline-flex items-center gap-1 px-2 py-0.5 bg-green-100 text-green-700 text-xs font-medium rounded-full">
                <.icon name="hero-check" class="w-3 h-3" />
                Verified Candidate
              </span>
            <% end %>
          </div>
          <%= if @preferred_role do %>
            <p class="text-gray-600 font-medium mb-2">{@preferred_role}</p>
          <% end %>
          <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-gray-500">
            <%= if @location do %>
              <span class="flex items-center gap-1">
                <.icon name="hero-map-pin" class="w-4 h-4" />
                {@location}
              </span>
            <% end %>
            <%= if @total_experience do %>
              <span class="flex items-center gap-1">
                <.icon name="hero-briefcase" class="w-4 h-4" />
                {@total_experience}
              </span>
            <% end %>
            <%= if @student.degree do %>
              <span class="flex items-center gap-1">
                <.icon name="hero-academic-cap" class="w-4 h-4" />
                {@student.degree}<%= if @student.specialization, do: " - #{@student.specialization}" %>
              </span>
            <% end %>
            <%= if @student.year_of_passing do %>
              <span class="flex items-center gap-1">
                <.icon name="hero-calendar" class="w-4 h-4" />
                Year: {@student.year_of_passing}
              </span>
            <% end %>
            <%= if @student.cgpa do %>
              <span class="flex items-center gap-1">
                <.icon name="hero-chart-bar" class="w-4 h-4" />
                CGPA: {Float.round(@student.cgpa * 1.0, 2)}
              </span>
            <% end %>
          </div>
        </div>
        <!-- Action Buttons -->
        <div class="flex flex-wrap gap-2 sm:flex-nowrap">
          <button
            phx-click="share_profile"
            class="flex items-center gap-1.5 px-3 py-2 text-sm text-gray-600 border border-gray-200 rounded-lg hover:bg-gray-50 transition"
          >
            <.icon name="hero-share" class="w-4 h-4" />
            Share Profile
          </button>
          <%= if @ats_data && @ats_data[:resume_url] do %>
            <button
              phx-click="download_resume"
              class="flex items-center gap-1.5 px-3 py-2 text-sm text-gray-600 border border-gray-200 rounded-lg hover:bg-gray-50 transition"
            >
              <.icon name="hero-arrow-down-tray" class="w-4 h-4" />
              Resume
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp about_section(assigns) do
    summary = if assigns.ats_data, do: assigns.ats_data[:professional_summary] || %{}, else: %{}
    summary_text = summary["summary"] || summary["professional_summary"]

    assigns = assign(assigns, :summary_text, summary_text)

    ~H"""
    <%= if @summary_text do %>
      <div class="bg-white border border-gray-100 rounded-xl p-5 sm:p-6 mb-6 hover:shadow-md transition-shadow">
        <h3 class="font-bold text-gray-900 mb-3">About</h3>
        <p class="text-sm text-gray-600 leading-relaxed">{@summary_text}</p>
      </div>
    <% end %>
    """
  end

  defp ai8_score_card(assigns) do
    score = assigns.ai8_data.ai8_score
    completed = assigns.ai8_data.completed_count
    total = assigns.ai8_data.total_assessments
    # SVG circle math: r=52, circumference=2*pi*52=326.73
    dash_offset = 326.73 * (1 - score / 100)

    assigns =
      assigns
      |> assign(:score, score)
      |> assign(:completed, completed)
      |> assign(:total, total)
      |> assign(:dash_offset, dash_offset)

    ~H"""
    <div class="bg-white border border-gray-100 rounded-xl p-5 sm:p-6 hover:shadow-md transition-shadow">
      <h3 class="font-bold text-gray-900 mb-4">Vyaasa Score</h3>
      <div class="flex flex-col items-center">
        <!-- Circular Progress -->
        <div class="relative w-36 h-36 mb-3">
          <svg class="w-full h-full" viewBox="0 0 120 120" style="transform: rotate(-90deg)">
            <defs>
              <linearGradient id="vyaasaGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" stop-color="#f97316"/>
                <stop offset="100%" stop-color="#22c55e"/>
              </linearGradient>
            </defs>
            <circle cx="60" cy="60" r="52" fill="none" stroke="#f3f4f6" stroke-width="8"/>
            <circle
              cx="60" cy="60" r="52" fill="none"
              stroke="url(#vyaasaGradient)"
              stroke-width="8"
              stroke-linecap="round"
              stroke-dasharray="326.73"
              stroke-dashoffset={@dash_offset}
              style="transition: stroke-dashoffset 1s ease"
            />
          </svg>
          <div class="absolute inset-0 flex flex-col items-center justify-center">
            <span class="text-3xl font-bold text-gray-900">{round(@score)}</span>
            <span class="text-sm text-gray-400">/ 100</span>
          </div>
        </div>
        <p class="text-xs text-gray-500 text-center mb-4">
          Average of {@completed}/{@total} completed assessments.
        </p>
        <!-- Score Breakdown -->
        <div class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm w-full max-w-xs">
          <div class="flex justify-between">
            <span class="text-gray-500">Resume Score</span>
            <span class="font-semibold text-gray-900">{display_score(@rankings.ats)}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-500">MCQ</span>
            <span class="font-semibold text-gray-900">{display_score(@rankings.mcq, :percentage)}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-500">Behavioral</span>
            <span class="font-semibold text-gray-900">{display_score(@rankings.behavioral)}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-500">JAM</span>
            <span class="font-semibold text-gray-900">{display_score(@rankings.jam)}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-500">Interview</span>
            <span class="font-semibold text-gray-900">{display_score(@rankings.interview)}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-500">Psychometric</span>
            <span class="font-semibold text-gray-900">{display_score(@rankings.psychometric)}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp skill_radar_card(assigns) do
    # Compute radar points from behavioral competencies (0-100 each)
    competencies =
      if assigns.rankings.behavioral[:completed] do
        c = assigns.rankings.behavioral[:competencies] || %{}

        %{
          communication: (c[:communication] || 0) / 100,
          teamwork: (c[:teamwork] || 0) / 100,
          leadership: (c[:leadership] || 0) / 100,
          adaptability: (c[:adaptability] || 0) / 100,
          work_ethics: (c[:work_ethics] || 0) / 100
        }
      else
        %{communication: 0, teamwork: 0, leadership: 0, adaptability: 0, work_ethics: 0}
      end

    # Pentagon points at 100%: top, top-right, bottom-right, bottom-left, top-left
    # Center is (100, 100), radius 80
    # Angles: -90, -18, 54, 126, 198 degrees
    angles = [-90, -18, 54, 126, 198]

    values = [
      competencies.communication,
      competencies.teamwork,
      competencies.work_ethics,
      competencies.adaptability,
      competencies.leadership
    ]

    r = 80

    data_points =
      Enum.zip(angles, values)
      |> Enum.map(fn {angle, val} ->
        rad = angle * :math.pi() / 180
        x = 100 + r * val * :math.cos(rad)
        y = 100 + r * val * :math.sin(rad)
        "#{Float.round(x, 1)},#{Float.round(y, 1)}"
      end)
      |> Enum.join(" ")

    assigns = assign(assigns, :data_points, data_points)

    ~H"""
    <div class="bg-white border border-gray-100 rounded-xl p-5 sm:p-6 hover:shadow-md transition-shadow">
      <h3 class="font-bold text-gray-900 mb-4">Skill Radar</h3>
      <div class="flex items-center justify-center h-64">
        <div class="relative w-56 h-56">
          <svg viewBox="0 0 200 200" class="w-full h-full">
            <!-- Pentagon grids -->
            <polygon points="100,20 175,65 155,155 45,155 25,65" fill="none" stroke="#e5e7eb" stroke-width="1"/>
            <polygon points="100,40 155,75 140,140 60,140 45,75" fill="none" stroke="#e5e7eb" stroke-width="1"/>
            <polygon points="100,60 135,85 125,125 75,125 65,85" fill="none" stroke="#e5e7eb" stroke-width="1"/>
            <polygon points="100,80 115,95 110,110 90,110 85,95" fill="none" stroke="#e5e7eb" stroke-width="1"/>
            <!-- Axis lines -->
            <line x1="100" y1="100" x2="100" y2="20" stroke="#e5e7eb" stroke-width="1"/>
            <line x1="100" y1="100" x2="175" y2="65" stroke="#e5e7eb" stroke-width="1"/>
            <line x1="100" y1="100" x2="155" y2="155" stroke="#e5e7eb" stroke-width="1"/>
            <line x1="100" y1="100" x2="45" y2="155" stroke="#e5e7eb" stroke-width="1"/>
            <line x1="100" y1="100" x2="25" y2="65" stroke="#e5e7eb" stroke-width="1"/>
            <!-- Data polygon -->
            <polygon points={@data_points}
              fill="rgba(249,115,22,0.15)"
              stroke="#f97316"
              stroke-width="2"/>
          </svg>
          <!-- Labels -->
          <span class="absolute text-xs text-gray-500 -top-1 left-1/2 -translate-x-1/2">Communication</span>
          <span class="absolute text-xs text-gray-500 top-1/4 -right-2">Teamwork</span>
          <span class="absolute text-xs text-gray-500 bottom-1 right-2">Work Ethics</span>
          <span class="absolute text-xs text-gray-500 bottom-1 left-2">Adaptability</span>
          <span class="absolute text-xs text-gray-500 top-1/4 -left-2">Leadership</span>
        </div>
      </div>
      <%= unless @rankings.behavioral[:completed] do %>
        <p class="text-xs text-gray-400 text-center mt-2">Complete the behavioral assessment to see your skill radar.</p>
      <% end %>
    </div>
    """
  end

  defp verified_skills_card(assigns) do
    technical_skills =
      if assigns.ats_data, do: DH.get_skills_list(assigns.ats_data[:skills] || %{}, "technical_skills"), else: []

    non_technical_skills =
      if assigns.ats_data, do: DH.get_skills_list(assigns.ats_data[:skills] || %{}, "non_technical_skills"), else: []

    all_skills = technical_skills ++ non_technical_skills

    assigns = assign(assigns, :all_skills, all_skills)

    ~H"""
    <%= if @all_skills != [] do %>
      <div class="bg-white border border-gray-100 rounded-xl p-5 sm:p-6 mb-6 hover:shadow-md transition-shadow">
        <div class="flex items-center gap-2 mb-4">
          <.icon name="hero-check-circle" class="w-5 h-5 text-green-500" />
          <h3 class="font-bold text-gray-900">Verified Skills</h3>
        </div>
        <div class="flex flex-wrap gap-2">
          <%= for skill <- @all_skills do %>
            <span class="inline-flex items-center gap-1.5 px-3 py-1.5 border border-gray-200 rounded-full text-sm text-gray-700 bg-white hover:border-orange-500 hover:bg-orange-50 transition">
              <span class="w-3.5 h-3.5 bg-green-500 rounded-full flex items-center justify-center">
                <.icon name="hero-check" class="w-2.5 h-2.5 text-white" />
              </span>
              {skill}
            </span>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  defp assessment_performance_section(assigns) do
    cards =
      Enum.map(DH.assessment_cards(), fn card ->
        data = Map.get(assigns.rankings, card.key, %{completed: false})
        score_display = if card.key == :mcq, do: display_score(data, :percentage), else: display_score(data)
        details = assessment_card_details(card.key, data)
        Map.merge(card, %{data: data, score_display: score_display, details: details})
      end)

    assigns = assign(assigns, :cards, cards)

    ~H"""
    <div class="mb-6">
      <h3 class="font-bold text-gray-900 text-lg mb-4">Assessment Performance</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <%= for card <- @cards do %>
          <div class="bg-white border border-gray-100 rounded-xl p-5 hover:shadow-md transition-shadow">
            <div class="flex items-start justify-between mb-3">
              <div class="flex items-center gap-2">
                <div class={"w-8 h-8 #{card.bg} rounded-lg flex items-center justify-center"}>
                  <.icon name={card.icon} class={"w-4 h-4 #{card.text}"} />
                </div>
                <span class="font-semibold text-gray-900">{card.label}</span>
              </div>
              <span class="text-lg font-bold text-gray-900">{card.score_display}<span class="text-sm text-gray-400">/100</span></span>
            </div>
            <%= if card.data[:completed] do %>
              <div class="space-y-1 text-sm text-gray-500 mb-3">
                <%= for detail <- card.details do %>
                  <p class="flex items-center gap-2"><span class="w-1.5 h-1.5 bg-green-500 rounded-full"></span>{detail}</p>
                <% end %>
              </div>
            <% else %>
              <p class="text-sm text-gray-400">Not yet completed</p>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp assessment_card_details(:behavioral, data) do
    c = data[:competencies] || %{}

    [
      "Leadership: #{c[:leadership] || "-"}",
      "Communication: #{c[:communication] || "-"}",
      "Teamwork: #{c[:teamwork] || "-"}",
      "Rank: #{data[:rank]} of #{data[:total]}"
    ]
  end

  defp assessment_card_details(:mcq, data) do
    [
      "Marks: #{data[:obtained_marks] || "-"}/#{data[:total_marks] || "-"}",
      "Rank: #{data[:rank]} of #{data[:total]}"
    ]
  end

  defp assessment_card_details(:psychometric, data) do
    f = data[:factors] || %{}

    [
      "Openness: #{f[:openness] || "-"}",
      "Conscientiousness: #{f[:conscientiousness] || "-"}",
      "Rank: #{data[:rank]} of #{data[:total]}"
    ]
  end

  defp assessment_card_details(_key, data) do
    ["Rank: #{data[:rank]} of #{data[:total]}"]
  end

  defp communication_insights_card(assigns) do
    # Derive communication data from behavioral competencies and JAM
    behavioral = assigns.rankings.behavioral
    jam = assigns.rankings.jam

    has_data = behavioral[:completed] || jam[:completed]

    communication_score =
      if behavioral[:completed], do: (behavioral[:competencies] || %{})[:communication] || 0, else: 0

    jam_score = if jam[:completed], do: jam[:score] || 0, else: 0

    assigns =
      assigns
      |> assign(:has_data, has_data)
      |> assign(:communication_score, communication_score)
      |> assign(:jam_score, jam_score)

    ~H"""
    <%= if @has_data do %>
      <div class="bg-white border border-gray-100 rounded-xl p-5 sm:p-6 mb-6 hover:shadow-md transition-shadow">
        <div class="flex items-center gap-2 mb-2">
          <.icon name="hero-arrow-trending-up" class="w-5 h-5 text-orange-500" />
          <h3 class="font-bold text-gray-900">Communication Insights</h3>
        </div>
        <p class="text-xs text-gray-500 mb-5">Derived from JAM Session & Behavioral Assessment.</p>
        <div class="space-y-4">
          <%= if @jam_score > 0 do %>
            <div>
              <div class="flex justify-between text-sm mb-1.5">
                <span class="text-gray-700">JAM Speaking Score</span>
                <span class="font-semibold text-gray-900">{round(@jam_score)}%</span>
              </div>
              <div class="h-1.5 bg-gray-200 rounded-full overflow-hidden">
                <div class="h-full bg-linear-to-r from-orange-500 to-orange-400 rounded-full" style={"width: #{@jam_score}%"}></div>
              </div>
            </div>
          <% end %>
          <%= if @communication_score > 0 do %>
            <div>
              <div class="flex justify-between text-sm mb-1.5">
                <span class="text-gray-700">Communication (Behavioral)</span>
                <span class="font-semibold text-gray-900">{@communication_score}%</span>
              </div>
              <div class="h-1.5 bg-gray-200 rounded-full overflow-hidden">
                <div class="h-full bg-linear-to-r from-orange-500 to-orange-400 rounded-full" style={"width: #{@communication_score}%"}></div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  defp experience_tabs_card(assigns) do
    has_ats = assigns.ats_data != nil
    work_experience = if has_ats, do: assigns.ats_data[:work_experience] || [], else: []
    education = if has_ats, do: assigns.ats_data[:education] || [], else: []
    projects = if has_ats, do: assigns.ats_data[:projects] || [], else: []
    certifications = if has_ats, do: assigns.ats_data[:certifications] || [], else: []

    has_content = work_experience != [] || education != [] || projects != [] || certifications != []

    assigns =
      assigns
      |> assign(:has_content, has_content)
      |> assign(:work_experience, work_experience)
      |> assign(:education, education)
      |> assign(:projects, projects)
      |> assign(:certifications, certifications)

    ~H"""
    <%= if @has_content do %>
      <div class="bg-white border border-gray-100 rounded-xl p-5 sm:p-6 mb-6 hover:shadow-md transition-shadow">
        <!-- Tabs -->
        <div class="flex flex-wrap gap-2 mb-5 border-b border-gray-100 pb-4">
          <%= for {tab_id, tab_label} <- [{"experience", "Experience"}, {"education", "Education"}, {"projects", "Projects"}, {"certifications", "Certifications"}] do %>
            <button
              phx-click="switch_tab"
              phx-value-tab={tab_id}
              class={[
                "px-4 py-2 text-sm rounded-md transition-all",
                if(@active_tab == tab_id, do: "bg-gray-900 text-white", else: "text-gray-500 hover:bg-gray-100")
              ]}
            >
              {tab_label}
            </button>
          <% end %>
        </div>

        <!-- Tab Content -->
        <%= if @active_tab == "experience" do %>
          <div class="space-y-4">
            <%= for exp <- @work_experience do %>
              <div class="flex gap-3">
                <div class="w-10 h-10 bg-gray-100 rounded-lg flex items-center justify-center shrink-0">
                  <.icon name="hero-building-office-2" class="w-5 h-5 text-gray-500" />
                </div>
                <div>
                  <h4 class="font-semibold text-gray-900">{exp["job_title"] || "Position"}</h4>
                  <p class="text-sm text-gray-500">{exp["company_name"] || "Company"} · {exp["start_date"] || ""} – {exp["end_date"] || "Present"}</p>
                  <%= if exp["responsibilities"] do %>
                    <p class="text-sm text-gray-600 mt-1">{exp["responsibilities"]}</p>
                  <% end %>
                </div>
              </div>
            <% end %>
            <%= if @work_experience == [] do %>
              <p class="text-sm text-gray-400">No work experience data available.</p>
            <% end %>
          </div>
        <% end %>

        <%= if @active_tab == "education" do %>
          <div class="space-y-4">
            <%= for edu <- @education do %>
              <div class="flex gap-3">
                <div class="w-10 h-10 bg-gray-100 rounded-lg flex items-center justify-center shrink-0">
                  <.icon name="hero-academic-cap" class="w-5 h-5 text-gray-500" />
                </div>
                <div>
                  <h4 class="font-semibold text-gray-900">{edu["Degree"] || edu["degree"] || "Degree"}</h4>
                  <p class="text-sm text-gray-500">{edu["Institution"] || edu["institution"] || "Institution"}</p>
                  <%= if edu["Years"] || edu["year"] do %>
                    <p class="text-xs text-gray-400 mt-1">{edu["Years"] || edu["year"]}</p>
                  <% end %>
                </div>
              </div>
            <% end %>
            <%= if @education == [] do %>
              <p class="text-sm text-gray-400">No education data available.</p>
            <% end %>
          </div>
        <% end %>

        <%= if @active_tab == "projects" do %>
          <div class="space-y-4">
            <%= for project <- @projects do %>
              <div class="bg-gray-50 border border-gray-200 rounded-lg p-4">
                <h4 class="font-semibold text-gray-900 mb-1">{project["Project_Name"] || project["name"] || "Project"}</h4>
                <%= if project["Description"] || project["description"] do %>
                  <p class="text-sm text-gray-700">{project["Description"] || project["description"]}</p>
                <% end %>
                <% techs = project["Technologies_Used"] || project["technologies"] || [] %>
                <%= if is_list(techs) && techs != [] do %>
                  <div class="flex flex-wrap gap-1 mt-2">
                    <%= for tech <- techs do %>
                      <span class="px-2 py-0.5 bg-orange-100 text-orange-800 rounded text-xs font-medium">{tech}</span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
            <%= if @projects == [] do %>
              <p class="text-sm text-gray-400">No project data available.</p>
            <% end %>
          </div>
        <% end %>

        <%= if @active_tab == "certifications" do %>
          <div class="space-y-4">
            <%= for cert <- @certifications do %>
              <div class="flex gap-3">
                <div class="w-10 h-10 bg-amber-100 rounded-lg flex items-center justify-center shrink-0">
                  <.icon name="hero-trophy" class="w-5 h-5 text-amber-600" />
                </div>
                <div>
                  <h4 class="font-semibold text-gray-900">{cert["name"] || cert["Name"] || "Certification"}</h4>
                  <p class="text-sm text-gray-500">{cert["organization"] || cert["Organization"] || ""}</p>
                </div>
              </div>
            <% end %>
            <%= if @certifications == [] do %>
              <p class="text-sm text-gray-400">No certification data available.</p>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # ATTEMPT HISTORY COMPONENT
  # ============================================================================

  defp attempt_history_section(assigns) do
    types = DH.attempt_history_types()

    sections =
      Enum.filter(types, fn t -> Map.get(assigns.attempt_history, t.key, []) != [] end)
      |> Enum.map(fn t -> Map.put(t, :attempts, Map.get(assigns.attempt_history, t.key, [])) end)

    assigns = assign(assigns, :sections, sections)

    ~H"""
    <%= if @sections != [] do %>
      <div class="mb-6">
        <h3 class="font-bold text-gray-900 text-lg mb-4">Assessment History</h3>
        <div class="space-y-4">
          <%= for section <- @sections do %>
            <div class="bg-white border border-gray-100 rounded-xl p-5 hover:shadow-md transition-shadow">
              <div class="flex items-center gap-2 mb-4">
                <div class={"w-7 h-7 #{section.bg} rounded-lg flex items-center justify-center"}>
                  <.icon name={section.icon} class={"w-4 h-4 #{section.text}"} />
                </div>
                <h4 class="font-semibold text-gray-900">{section.label}</h4>
                <span class="text-xs text-gray-400 ml-auto"><%= length(section.attempts) %> {section.count_label}(s)</span>
              </div>
              <div class="space-y-3">
                <%= for attempt <- section.attempts do %>
                  <.attempt_row type={section.key} attempt={attempt} bar_color={section.bar} />
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  defp attempt_row(%{type: :mcq} = assigns) do
    ~H"""
    <div class="bg-gray-50 rounded-lg p-4 border border-gray-100">
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm font-medium text-gray-700">Attempt #{@attempt.attempt_number}</span>
        <div class="flex items-center gap-3">
          <span class="text-lg font-bold text-gray-900">
            <%= if @attempt.percentage, do: "#{Decimal.round(@attempt.percentage, 1)}%", else: "-" %>
          </span>
          <span class="text-xs text-gray-400">
            <%= if @attempt.obtained_marks && @attempt.total_marks, do: "#{@attempt.obtained_marks}/#{@attempt.total_marks}", else: "" %>
          </span>
        </div>
      </div>
      <div class="h-1.5 bg-gray-200 rounded-full overflow-hidden">
        <div class={@bar_color <> " h-full rounded-full"} style={"width: #{if @attempt.percentage, do: Decimal.to_float(@attempt.percentage), else: 0}%"}></div>
      </div>
      <p class="text-xs text-gray-400 mt-2">
        <%= if @attempt.submitted_at, do: DateTimeFormatter.format_datetime(@attempt.submitted_at), else: "In progress" %>
      </p>
    </div>
    """
  end

  defp attempt_row(%{type: :behavioral} = assigns) do
    ~H"""
    <div class="bg-gray-50 rounded-lg p-4 border border-gray-100">
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm font-medium text-gray-700">Attempt #{@attempt.attempt_number}</span>
        <span class="text-lg font-bold text-gray-900"><%= @attempt.overall_score || "-" %>/100</span>
      </div>
      <div class="h-1.5 bg-gray-200 rounded-full overflow-hidden mb-3">
        <div class={@bar_color <> " h-full rounded-full"} style={"width: #{@attempt.overall_score || 0}%"}></div>
      </div>
      <.sub_score_grid scores={[
        %{label: "Leadership", value: @attempt.leadership_score},
        %{label: "Communication", value: @attempt.communication_score},
        %{label: "Teamwork", value: @attempt.teamwork_score},
        %{label: "Adaptability", value: @attempt.adaptability_score},
        %{label: "Work Ethics", value: @attempt.work_ethics_score}
      ]} />
      <.strengths_and_improvements strengths={@attempt.strengths || []} improvements={@attempt.areas_for_development || []} />
      <p class="text-xs text-gray-400 mt-2">
        <%= if @attempt.completed_at, do: DateTimeFormatter.format_datetime(@attempt.completed_at), else: "" %>
      </p>
    </div>
    """
  end

  defp attempt_row(%{type: :jam} = assigns) do
    ~H"""
    <div class="bg-gray-50 rounded-lg p-4 border border-gray-100">
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm font-medium text-gray-700 truncate max-w-50"><%= @attempt.topic_title || "JAM Session" %></span>
        <span class="text-lg font-bold text-gray-900"><%= @attempt.final_score || "-" %>/100</span>
      </div>
      <div class="h-1.5 bg-gray-200 rounded-full overflow-hidden mb-3">
        <div class={@bar_color <> " h-full rounded-full"} style={"width: #{@attempt.final_score || 0}%"}></div>
      </div>
      <.sub_score_grid scores={[
        %{label: "Clarity", value: @attempt.clarity_score},
        %{label: "Structure", value: @attempt.structure_score},
        %{label: "Relevance", value: @attempt.relevance_score},
        %{label: "Impact", value: @attempt.impact_score},
        %{label: "Confidence", value: @attempt.confidence_score}
      ]} />
      <%= if @attempt.overall_summary do %>
        <p class="text-xs text-gray-600 mt-2 line-clamp-2">{@attempt.overall_summary}</p>
      <% end %>
      <p class="text-xs text-gray-400 mt-2">
        <%= if @attempt.completed_at, do: DateTimeFormatter.format_datetime(@attempt.completed_at), else: "" %>
      </p>
    </div>
    """
  end

  defp attempt_row(%{type: :interview} = assigns) do
    ~H"""
    <div class="bg-gray-50 rounded-lg p-4 border border-gray-100">
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm font-medium text-gray-700">Interview Session</span>
        <span class="text-lg font-bold text-gray-900">
          <%= if @attempt.overall_score, do: "#{Decimal.round(@attempt.overall_score, 1)}", else: "-" %>/100
        </span>
      </div>
      <div class="h-1.5 bg-gray-200 rounded-full overflow-hidden mb-3">
        <div class={@bar_color <> " h-full rounded-full"} style={"width: #{if @attempt.overall_score, do: Decimal.to_float(@attempt.overall_score), else: 0}%"}></div>
      </div>
      <.strengths_and_improvements strengths={@attempt.strengths || []} improvements={@attempt.improvements || []} />
      <p class="text-xs text-gray-400 mt-2">
        <%= if @attempt.completed_at, do: DateTimeFormatter.format_datetime(@attempt.completed_at), else: "" %>
      </p>
    </div>
    """
  end

  defp attempt_row(%{type: :psychometric} = assigns) do
    ~H"""
    <div class="bg-gray-50 rounded-lg p-4 border border-gray-100">
      <div class="flex items-center justify-between mb-3">
        <span class="text-sm font-medium text-gray-700">Attempt #{@attempt.attempt_number}</span>
        <span class="text-xs text-gray-400">Big Five</span>
      </div>
      <.sub_score_grid scores={[
        %{label: "Open", value: if(@attempt.openness_score, do: Float.round(@attempt.openness_score * 1.0, 1))},
        %{label: "Consc", value: if(@attempt.conscientiousness_score, do: Float.round(@attempt.conscientiousness_score * 1.0, 1))},
        %{label: "Extra", value: if(@attempt.extraversion_score, do: Float.round(@attempt.extraversion_score * 1.0, 1))},
        %{label: "Agree", value: if(@attempt.agreeableness_score, do: Float.round(@attempt.agreeableness_score * 1.0, 1))},
        %{label: "Neuro", value: if(@attempt.neuroticism_score, do: Float.round(@attempt.neuroticism_score * 1.0, 1))}
      ]} />
      <.strengths_and_improvements strengths={@attempt.strengths || []} improvements={@attempt.development_areas || []} />
      <p class="text-xs text-gray-400 mt-2">
        <%= if @attempt.completed_at, do: DateTimeFormatter.format_datetime(@attempt.completed_at), else: "" %>
      </p>
    </div>
    """
  end

  # Shared sub-components for attempt rows

  defp sub_score_grid(assigns) do
    ~H"""
    <div class={"grid grid-cols-#{length(@scores)} gap-2 text-xs mb-3"}>
      <%= for score <- @scores do %>
        <div class="text-center p-1.5 bg-white rounded border border-gray-100">
          <div class="font-semibold text-gray-700"><%= score.value || "-" %></div>
          <div class="text-gray-400">{score.label}</div>
        </div>
      <% end %>
    </div>
    """
  end

  defp strengths_and_improvements(assigns) do
    ~H"""
    <%= if @strengths != [] do %>
      <div class="mb-2">
        <p class="text-xs font-semibold text-green-700 mb-1">Strengths:</p>
        <div class="flex flex-wrap gap-1">
          <%= for s <- Enum.take(@strengths, 3) do %>
            <span class="px-2 py-0.5 bg-green-50 text-green-700 rounded text-xs border border-green-200">{s}</span>
          <% end %>
        </div>
      </div>
    <% end %>
    <%= if @improvements != [] do %>
      <div>
        <p class="text-xs font-semibold text-amber-700 mb-1">Areas to Improve:</p>
        <div class="flex flex-wrap gap-1">
          <%= for a <- Enum.take(@improvements, 3) do %>
            <span class="px-2 py-0.5 bg-amber-50 text-amber-700 rounded text-xs border border-amber-200">{a}</span>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================

  defp get_initials(name), do: DH.get_initials(name)
  defp display_score(data, field), do: DH.display_score(data, field)
  defp display_score(data), do: DH.display_score(data)

  # Private functions

  defp handle_authenticated_mount(socket, current_user, tenant, tenant_alias, tenant_schema) do
    require Logger

    if connected?(socket), do: DashboardEvents.subscribe_student(current_user.id)

    case load_student_data(current_user, tenant_schema) do
      {:ok, {student, ats_data}} ->
        user_info = get_user_info_from_current_user(current_user, ats_data)

        # Check if student has a submitted assessment attempt
        submitted_attempt =
          try do
            Assessments.get_student_latest_submitted_attempt(current_user.id, tenant_schema)
          rescue
            e ->
              Logger.error("Failed to check assessment status: #{inspect(e)}")
              nil
          end

        # Check for completed AI Interview session
        has_completed_interview =
          try do
            case Interview.get_completed_interviews(current_user.id, tenant_schema) do
              [_ | _] -> true
              _ -> false
            end
          rescue
            _ -> false
          end

        # Check for completed JAM session
        has_completed_jam =
          try do
            case Jam.get_completed_jam_sessions(current_user.id, tenant_schema) do
              [_ | _] -> true
              _ -> false
            end
          rescue
            _ -> false
          end

        # Check if student has a completed behavioral assessment
        behavioral_completed =
          try do
            Behavioral.assessment_completed?(current_user.id, tenant_schema)
          rescue
            e ->
              Logger.error("Failed to check behavioral assessment status: #{inspect(e)}")
              false
          end

        # Check if student has a completed psychometric assessment
        psychometric_completed =
          try do
            Psychometric.assessment_completed?(current_user.id, tenant_schema)
          rescue
            _ -> false
          end

        module_statuses = load_module_statuses(current_user.id, tenant_schema)

        # Load scores, ranks, and Vyaasa score
        {rankings, ai8_data} = load_rankings(current_user.id, tenant_schema)

        socket =
          socket
          |> assign(:tenant_alias, tenant_alias)
          |> assign(:tenant, tenant)
          |> assign(:tenant_schema, tenant_schema)
          |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: tenant_alias))
          |> assign(:user_info, user_info)
          |> assign(:current_scope, :student)
          |> assign(:page_title, "Dashboard - #{if(tenant, do: tenant.full_name, else: tenant_alias)}")
          |> assign(:student, student)
          |> assign(:ats_data, ats_data)
          |> assign(:submitted_attempt, submitted_attempt)
          |> assign(:has_completed_interview, has_completed_interview)
          |> assign(:has_completed_jam, has_completed_jam)
          |> assign(:behavioral_completed, behavioral_completed)
          |> assign(:psychometric_completed, psychometric_completed)
          |> assign(module_statuses)
          |> assign(:instructions, get_instructions())
          |> assign(:rankings, rankings)
          |> assign(:ai8_tags, ai8_pills())
          |> assign(:ai8_data, ai8_data)
          |> assign(:attempt_history, load_attempt_history(current_user.id, tenant_schema))
          |> assign(:attempt_counts, load_attempt_counts(current_user.id, tenant_schema))
          |> assign(:attempt_limits, load_attempt_limits(current_user.id, tenant, tenant_schema))
          |> assign(:active_tab, "experience")
          |> assign(:active_section, "dashboard")
          |> assign(:loading?, false)
          |> assign(:error_message, nil)
          |> assign(:show_share_modal, false)
          |> assign(:share_url, nil)

        {:ok, socket}

      {:error, reason} ->
        Logger.error("Failed to load student data: #{inspect(reason)}")
        {:ok, setup_error_socket(socket, "Failed to load student data")}
    end
  end

  defp load_student_data(current_user, tenant_schema) do
    require Logger

    Logger.info("Loading student data for user: #{inspect(current_user)}")

    # Get student ID from current user
    student_id = current_user.id

    # Load student data from the tenant schema
    case Students.get_student(student_id, tenant_schema) do
      nil ->
        Logger.error("Student not found with ID: #{student_id} in schema: #{tenant_schema}")
        {:error, :student_not_found}

      student ->
        # Load ATS data
        ats_data = StudentAts.get_by_student_id(student_id, tenant_schema)

        # Convert to simple maps
        simple_student = convert_student_to_simple_map(student)
        simple_ats_data = convert_ats_data_to_simple_map(ats_data)

        Logger.info("Successfully loaded student data for: #{student.email}")
        {:ok, {simple_student, simple_ats_data}}
    end
  end

  defp get_user_info_from_current_user(current_user, ats_data \\ nil) do
    %{
      name: "#{current_user.first_name} #{current_user.last_name}",
      role: "Student",
      email: current_user.email,
      profile_picture_url: ats_data && ats_data[:profile_picture_url]
    }
  end

  defp get_instructions do
    [
      %{
        id: "resume_parsing",
        title: "Resume Parsing & Profile Extraction",
        description: "Field extraction and profile structuring ensure high accuracy and contextual understanding."
      },
      %{
        id: "ai_introduction",
        title: "Interactive Session",
        description:
          "Personalized question generation and real-time evaluation provide an interactive, tailored candidate experience."
      },
      %{
        id: "psychometric",
        title: "Psychometric Assessment",
        description: "Not required; relies strictly on standardized, validated psychometric testing."
      },
      %{
        id: "jam_session",
        title: "JAM (Just A Minute) Session",
        description: "Topic assignment and speech assessment, using linguistic and logical analysis."
      },
      %{
        id: "behavioral_questions",
        title: "Situational Behavioral Questions",
        description:
          "Scenario generation, interactive follow-ups, and response evaluation to gauge behavioral competencies."
      },
      # %{
      #   id: "case_study",
      #   title: "AI-Generated Case Study",
      #   description: "Personalization, real-time clarification, and nuanced evaluation."
      # },
      %{
        id: "objective_evaluation",
        title: "Objective Evaluation (MCQs & Practical Task)",
        description:
          "Not utilized, as this section relies on standardized question banks and objective evaluation mechanisms."
      }
      # %{
      #   id: "domain_project",
      #   title: "Domain Mini Project",
      #   description: "Not required; relies strictly on standardized, validated psychometric testing."
      # }
    ]
  end

  defp convert_student_to_simple_map(student) do
    %{
      id: student.id,
      email: student.email,
      first_name: student.first_name,
      last_name: student.last_name,
      phone: student.phone,
      registration_id: student.registration_id,
      degree: student.degree,
      specialization: student.specialization,
      year_of_passing: student.year_of_passing,
      cgpa: if(student.cgpa, do: Decimal.to_float(student.cgpa), else: nil),
      status: student.status,
      profile_completed: student.profile_completed,
      profile_submitted_at: student.profile_submitted_at,
      profile_approved_at: student.profile_approved_at,
      profile_reviewed_at: student.profile_reviewed_at,
      profile_rejected_at: student.profile_rejected_at,
      admin_notes: student.admin_notes,
      edit_request_notes: student.edit_request_notes,
      inserted_at: student.inserted_at,
      profile_token: student.profile_token
    }
  end

  defp convert_ats_data_to_simple_map(ats_data), do: DH.convert_ats_data_to_simple_map(ats_data)

  # Score display helpers — delegate to DH
  defp safe_score(score), do: DH.safe_score(score)
  defp rating_label(score), do: DH.score_tier(score).label
  defp rating_class(score), do: DH.score_tier(score).badge
  defp score_color_class(score), do: DH.score_tier(score).text
  defp bar_color_class(score), do: DH.score_tier(score).bar

  defp setup_successful_socket(socket, student, ats_data, tenant_schema) do
    if connected?(socket), do: DashboardEvents.subscribe_student(student.id)

    # Get tenant information
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_schema))
    tenant_alias = if tenant, do: tenant.alias, else: tenant_schema

    # Convert to simple maps
    simple_student = convert_student_to_simple_map(student)
    simple_ats_data = convert_ats_data_to_simple_map(ats_data)

    # Check if student has a submitted assessment attempt
    submitted_attempt =
      try do
        Assessments.get_student_latest_submitted_attempt(student.id, tenant_schema)
      rescue
        _ -> nil
      end

    # Check if student has a completed behavioral assessment
    behavioral_completed =
      try do
        Behavioral.assessment_completed?(student.id, tenant_schema)
      rescue
        _ -> false
      end

    # Check if student has a completed psychometric assessment
    psychometric_completed =
      try do
        Psychometric.assessment_completed?(student.id, tenant_schema)
      rescue
        _ -> false
      end

    # Mock user info for profile token access
    user_info = %{
      name: "#{student.first_name} #{student.last_name}",
      role: "Student",
      email: student.email,
      profile_picture_url: simple_ats_data && simple_ats_data[:profile_picture_url]
    }

    # Check for completed AI Interview and JAM sessions
    has_completed_interview =
      try do
        case Interview.get_completed_interviews(student.id, tenant_schema) do
          [_ | _] -> true
          _ -> false
        end
      rescue
        _ -> false
      end

    has_completed_jam =
      try do
        case Jam.get_completed_jam_sessions(student.id, tenant_schema) do
          [_ | _] -> true
          _ -> false
        end
      rescue
        _ -> false
      end

    module_statuses = load_module_statuses(student.id, tenant_schema)

    # Load scores, ranks, and Vyaasa score
    {rankings, ai8_data} = load_rankings(student.id, tenant_schema)

    socket
    |> assign(:tenant_alias, tenant_alias)
    |> assign(:tenant, tenant)
    |> assign(:tenant_schema, tenant_schema)
    |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: tenant_alias))
    |> assign(:user_info, user_info)
    |> assign(:current_scope, :student)
    |> assign(:page_title, "Dashboard - #{if(tenant, do: tenant.full_name, else: tenant_alias)}")
    |> assign(:student, simple_student)
    |> assign(:ats_data, simple_ats_data)
    |> assign(:submitted_attempt, submitted_attempt)
    |> assign(:has_completed_interview, has_completed_interview)
    |> assign(:has_completed_jam, has_completed_jam)
    |> assign(:behavioral_completed, behavioral_completed)
    |> assign(:psychometric_completed, psychometric_completed)
    |> assign(module_statuses)
    |> assign(:instructions, get_instructions())
    |> assign(:rankings, rankings)
    |> assign(:ai8_tags, ai8_pills())
    |> assign(:ai8_data, ai8_data)
    |> assign(:attempt_history, load_attempt_history(student.id, tenant_schema))
    |> assign(:attempt_counts, load_attempt_counts(student.id, tenant_schema))
    |> assign(:attempt_limits, load_attempt_limits(student.id, tenant, tenant_schema))
    |> assign(:active_tab, "experience")
    |> assign(:active_section, "dashboard")
    |> assign(:loading?, false)
    |> assign(:error_message, nil)
    |> assign(:show_share_modal, false)
    |> assign(:show_reupload_modal, false)
    |> assign(:share_url, nil)
  end

  defp setup_error_socket(socket, reason) do
    socket
    |> assign(:tenant_alias, "unknown")
    |> assign(:tenant, nil)
    |> assign(:tenant_schema, nil)
    |> assign(:tenant_name, "Unknown")
    |> assign(:user_info, %{name: "Unknown", role: "Student", email: "unknown@example.com"})
    |> assign(:current_scope, :student)
    |> assign(:page_title, "Dashboard - Error")
    |> assign(:student, nil)
    |> assign(:ai8_tags, %{})
    |> assign(:ats_data, nil)
    |> assign(:submitted_attempt, nil)
    |> assign(:has_completed_interview, false)
    |> assign(:has_completed_jam, false)
    |> assign(:behavioral_completed, false)
    |> assign(:psychometric_completed, false)
    |> assign(:case_study_started, false)
    |> assign(:case_study_completed, false)
    |> assign(:case_study_progress, 0)
    |> assign(:mini_project_started, false)
    |> assign(:mini_project_completed, false)
    |> assign(:mini_project_progress, 0)
    |> assign(:instructions, [])
    |> assign(:rankings, %{
      mcq: %{completed: false},
      behavioral: %{completed: false},
      ats: %{completed: false},
      jam: %{completed: false},
      interview: %{completed: false},
      psychometric: %{completed: false, factors: %{}}
    })
    |> assign(:ai8_data, %{ai8_score: 0.0, completed_count: 0, total_assessments: 6})
    |> assign(:attempt_history, %{mcq: [], behavioral: [], jam: [], interview: [], psychometric: []})
    |> assign(:attempt_counts, %{
      mcq: 0,
      interview: 0,
      jam: 0,
      behavioral: 0,
      psychometric: 0,
      case_study: 0,
      mini_project: 0
    })
    |> assign(:attempt_limits, %{})
    |> assign(:active_tab, "experience")
    |> assign(:active_section, "dashboard")
    |> assign(:loading?, false)
    |> assign(:error_message, reason)
    |> assign(:show_share_modal, false)
    |> assign(:show_reupload_modal, false)
    |> assign(:share_url, nil)
  end

  defp load_rankings(student_id, tenant_schema) do
    require Logger

    try do
      rankings = StudentRankings.get_student_scores_and_ranks(student_id, tenant_schema)
      ai8_data = StudentRankings.calculate_ai8_score(student_id, tenant_schema)
      {rankings, ai8_data}
    rescue
      e ->
        Logger.error("Failed to load rankings: #{inspect(e)}")

        default_rankings = %{
          mcq: %{completed: false, score: nil, rank: nil, total: 0},
          behavioral: %{completed: false, score: nil, rank: nil, total: 0},
          ats: %{completed: false, score: nil, rank: nil, total: 0},
          jam: %{completed: false, score: nil, rank: nil, total: 0},
          interview: %{completed: false, score: nil, rank: nil, total: 0},
          psychometric: %{completed: false, score: nil, rank: nil, total: 0, factors: %{}}
        }

        {default_rankings, %{ai8_score: 0.0, completed_count: 0, total_assessments: 6}}
    end
  end

  defp load_attempt_history(student_id, tenant_schema) do
    require Logger

    try do
      %{
        mcq:
          Assessments.list_student_attempts(student_id, tenant_schema)
          |> Enum.filter(&(&1.status in ["submitted", "evaluated", "completed"])),
        behavioral:
          Behavioral.list_student_assessments(student_id, tenant_schema) |> Enum.filter(&(&1.status == "completed")),
        jam: Jam.list_jam_sessions(student_id, tenant_schema) |> Enum.filter(&(&1.status == "completed")),
        interview:
          Interview.list_student_interviews(student_id, tenant_schema) |> Enum.filter(&(&1.status == "completed")),
        psychometric:
          Psychometric.list_student_assessments(student_id, tenant_schema) |> Enum.filter(&(&1.status == "completed"))
      }
    rescue
      e ->
        Logger.error("Failed to load attempt history: #{inspect(e)}")
        %{mcq: [], behavioral: [], jam: [], interview: [], psychometric: []}
    end
  end

  # Number of attempts per module, counted from each module's own session/attempt
  # table. Each count is wrapped defensively so a missing table or context never
  # crashes the dashboard — display only, never affects scoring.
  defp load_attempt_counts(student_id, tenant_schema) do
    %{
      mcq: safe_count(fn -> Assessments.list_student_attempts(student_id, tenant_schema) end),
      interview: safe_count(fn -> Interview.list_student_interviews(student_id, tenant_schema) end),
      jam: safe_count(fn -> Jam.list_jam_sessions(student_id, tenant_schema) end),
      behavioral: safe_count(fn -> Behavioral.list_student_assessments(student_id, tenant_schema) end),
      psychometric: safe_count(fn -> Psychometric.list_student_assessments(student_id, tenant_schema) end),
      case_study: safe_count(fn -> CaseStudy.list_student_sessions(student_id, tenant_schema) end),
      mini_project: safe_count(fn -> MiniProject.list_sessions(student_id, tenant_schema) end)
    }
  end

  # Attempt caps per module (entitlement default/override + admin grants), for
  # the "used/limit" display on each card. `nil` means unlimited — falls back
  # to the plain "N attempts" wording. Wrapped defensively so a tenant without
  # entitlements configured never breaks the dashboard.
  defp load_attempt_limits(_student_id, nil, _tenant_schema), do: %{}

  defp load_attempt_limits(student_id, tenant, tenant_schema) do
    entitlements = Entitlements.map_for_tenant(tenant.id)

    (Entitlements.attempt_modules() -- ["resume"])
    |> Map.new(fn module ->
      limit =
        case Entitlements.attempt_limit(entitlements, module) do
          nil -> nil
          base -> base + AttemptGuard.granted_extra(student_id, module, tenant_schema)
        end

      {String.to_atom(module), limit}
    end)
  rescue
    _ -> %{}
  end

  defp load_module_statuses(student_id, tenant_schema) do
    case_study_sessions = safe_list(fn -> CaseStudy.list_student_sessions(student_id, tenant_schema) end)
    completed_case_study = Enum.find(case_study_sessions, &(&1.status == "completed"))

    mini_project_sessions = safe_list(fn -> MiniProject.list_sessions(student_id, tenant_schema) end)
    completed_mini_project = Enum.find(mini_project_sessions, &(&1.phase == "completed"))

    %{
      case_study_started: case_study_sessions != [],
      case_study_completed: completed_case_study != nil,
      case_study_progress: completed_score(completed_case_study && completed_case_study.total_score),
      mini_project_started: mini_project_sessions != [],
      mini_project_completed: completed_mini_project != nil,
      mini_project_progress: completed_score(completed_mini_project && completed_mini_project.final_score)
    }
  end

  defp safe_list(fun) do
    case fun.() do
      list when is_list(list) -> list
      _ -> []
    end
  rescue
    _ -> []
  end

  defp completed_score(nil), do: 0
  defp completed_score(score) when is_integer(score), do: score |> min(100) |> max(0)
  defp completed_score(score) when is_float(score), do: score |> round() |> min(100) |> max(0)

  defp completed_score(%Decimal{} = score) do
    score
    |> Decimal.to_float()
    |> completed_score()
  end

  defp completed_score(_), do: 0

  defp safe_count(fun) do
    case fun.() do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  rescue
    _ -> 0
  end

  # Renders the per-module attempt count line on a card.
  defp attempts_label(0), do: "Not attempted"
  defp attempts_label(1), do: "1 attempt"
  defp attempts_label(n) when is_integer(n) and n > 1, do: "#{n} attempts"
  defp attempts_label(_), do: "Not attempted"

  # "1/3" once the tenant has an attempt cap for this module; otherwise the
  # plain "N attempts" wording (unlimited).
  defp attempts_display(used, limit) when is_integer(used) and is_integer(limit), do: "#{used}/#{limit}"
  defp attempts_display(used, _limit), do: attempts_label(used)

  # Helper functions for route handling
  defp find_student_by_token(profile_token) do
    require Logger
    alias VyaasaCampus.Contexts.Tenants

    Logger.info("Finding student by profile token: #{profile_token}")

    # Get all tenants to search for the student
    tenants = Tenants.list_tenants()

    Enum.find_value(tenants, {:error, :token_not_found}, fn tenant ->
      case Students.verify_profile_token(profile_token, tenant.schema_name) do
        {:ok, student} ->
          Logger.info("Found student: #{student.email} in tenant: #{tenant.alias}")
          # Load ATS data for this student
          ats_data = StudentAts.get_by_student_id(student.id, tenant.schema_name)
          {:ok, {student, ats_data, tenant.schema_name}}

        {:error, _reason} ->
          nil
      end
    end)
  end
end
