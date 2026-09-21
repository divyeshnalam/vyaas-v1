defmodule VyaasaCampusWeb.Student.Assessment.InstructionsLive do
  @moduledoc """
  LiveView for MCQ Assessment Instructions Screen.
  Shows assessment overview, rules, and start button.
  """

  use VyaasaCampusWeb, :live_view
  alias VyaasaCampus.Contexts.{Assessments, StudentAts, Tenants}
  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    require Logger

    # Get tenant information
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    tenant_schema = if tenant, do: tenant.schema_name, else: nil

    # Get current user from socket assigns
    current_user = socket.assigns[:current_user]

    Logger.info("Assessment instructions mount - tenant: #{tenant_alias}")

    case current_user do
      nil ->
        {:ok, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}

      _user ->
        # If the student already submitted an attempt, resume straight to the
        # report instead of re-generating a new "Start Assessment" screen.
        case Assessments.get_student_latest_submitted_attempt(current_user.id, tenant_schema) do
          %{assessment_id: assessment_id} ->
            {:ok,
             redirect(socket,
               to: ~p"/student/#{tenant_alias}/assessment/#{assessment_id}/result"
             )}

          nil ->
            mount_instructions(tenant_alias, tenant_schema, tenant, current_user, socket)
        end
    end
  end

  defp mount_instructions(tenant_alias, tenant_schema, tenant, current_user, socket) do
    # Get or create dynamic assessment for this student
    case Assessments.get_or_create_dynamic_assessment(current_user.id, tenant_schema) do
      {:ok, assessment} ->
        # Build section breakdown from actual assessment questions
        questions = assessment.settings["questions"] || []
        sections = build_section_breakdown(questions, assessment.duration_minutes)

        socket =
          socket
          |> assign(:tenant_alias, tenant_alias)
          |> assign(:tenant_schema, tenant_schema)
          |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: tenant_alias))
          |> assign(:current_user, current_user)
          |> assign(
            :profile_picture_url,
            StudentAts.get_student_ats_fields(current_user.id, tenant_schema)[:profile_picture_url]
          )
          |> assign(:assessment, assessment)
          |> assign(:total_questions, length(questions))
          |> assign(:sections, sections)
          |> assign(:section_count, length(sections))
          |> assign(:agreed_to_terms, true)

        {:ok, socket}

      {:error, _reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to generate assessment. Please try again.")
          |> redirect(to: "/student/#{tenant_alias}/dashboard")

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("toggle_agreement", _params, socket) do
    {:noreply, assign(socket, :agreed_to_terms, !socket.assigns.agreed_to_terms)}
  end

  @impl true
  def handle_event("start_assessment", _params, socket) do
    if socket.assigns.agreed_to_terms do
      # Create or resume assessment attempt
      case Assessments.start_assessment(
             socket.assigns.assessment.id,
             socket.assigns.current_user.id,
             socket.assigns.tenant_schema
           ) do
        {:ok, attempt} ->
          {:noreply,
           redirect(socket,
             to:
               ~p"/student/#{socket.assigns.tenant_alias}/assessment/#{socket.assigns.assessment.id}/test?attempt=#{attempt.id}"
           )}

        {:error, :already_submitted} ->
          # Retake: generate a new assessment with a fresh random question set so
          # the student cannot rely on memorised answers from the previous attempt.
          with {:ok, new_assessment} <-
                 Assessments.create_dynamic_assessment_for_student(
                   socket.assigns.current_user.id,
                   socket.assigns.tenant_schema
                 ),
               {:ok, attempt} <-
                 Assessments.start_assessment_attempt(
                   new_assessment.id,
                   socket.assigns.current_user.id,
                   socket.assigns.tenant_schema
                 ) do
            {:noreply,
             redirect(socket,
               to:
                 ~p"/student/#{socket.assigns.tenant_alias}/assessment/#{new_assessment.id}/test?attempt=#{attempt.id}"
             )}
          else
            _ ->
              {:noreply, put_flash(socket, :error, "Failed to start a new attempt. Please try again.")}
          end

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start assessment. Please try again.")}
      end
    else
      {:noreply, put_flash(socket, :warning, "Please agree to the terms before starting.")}
    end
  end

  @impl true
  def handle_event("back_to_dashboard", _params, socket) do
    {:noreply, redirect(socket, to: "/student/#{socket.assigns.tenant_alias}/dashboard")}
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

    assigns = assign(assigns, :user_info, user_info)

    ~H"""
    <div class="min-h-screen bg-cream-50 flex">
      <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar
        current_section="mcq"
        tenant_alias={@tenant_alias}
        student_name={@user_info.name}
      />

      <div class="flex-1 flex flex-col min-w-0">
        <VyaasaCampusWeb.Components.Student.HeaderComponent.header
          user_info={@user_info}
          tenant_alias={@tenant_alias}
          page_title={@assessment.title}
        />

        <main class="flex-1 overflow-auto">
          <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-[1200px] mx-auto w-full">
            <!-- Page header -->
            <div class="flex items-start gap-3 mb-6">
              <div
                class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
                style="background-color: #FFE9D2;"
              >
                <.icon name="hero-puzzle-piece" class="w-5 h-5" style="color: #B85F00;" />
              </div>
              <div>
                <p class="text-[11px] font-semibold tracking-[0.18em] uppercase" style="color: #FF8B00;">
                  Domain · Problem-Solving
                </p>
                <h1 class="text-2xl font-bold text-gray-900">Objective Evaluation</h1>
                <p class="text-sm text-gray-500 mt-1">Take it at your own pace. We'll guide you, not grade you.</p>
              </div>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <!-- Main card -->
              <div class="lg:col-span-2 rounded-2xl p-6 relative overflow-hidden"
                style="background: linear-gradient(180deg, #FFEDD5 0%, #FFF6EC 30%, #FFFFFF 80%); border: 1px solid #FBD9AE;"
              >
                <span class="inline-block text-[10px] font-semibold px-3 py-1 rounded-full mb-3"
                  style="background-color: #FF8B00; color: white;">Assessment Instructions</span>
                <h2 class="text-2xl font-bold text-gray-900 mb-1">Let's get you ready for success.</h2>
                <p class="text-sm text-gray-500 mb-6">Please read the rules below carefully. Following these ensures a fair, smooth, and stress-free assessment experience for everyone.</p>

                <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mb-6">
                  <.rule_tile icon="hero-clock" title="Timer starts immediately" description="You cannot pause the test" />
                  <.rule_tile icon="hero-check-circle" title="4 options per question" description="Select one answer only" />
                  <.rule_tile icon="hero-bookmark" title="Mark for Review" description="Flag questions to revisit" />
                  <.rule_tile icon="hero-arrows-right-left" title="Navigate freely in section" description="Jump between questions freely" />
                  <.rule_tile icon="hero-exclamation-triangle" title="Negative marking -0.25" description="Applies for each wrong answer" />
                  <.rule_tile icon="hero-arrow-uturn-left" title="No going back" description="Can't return to prev. Section" />
                  <.rule_tile icon="hero-arrow-up-tray" title="Auto-submit on timeout" description="Timer expiry submits the test" />
                  <.rule_tile icon="hero-no-symbol" title="No tab switching" description="May be flagged as violation" />
                  <.rule_tile icon="hero-wifi" title="Stable internet required" description="Ensure connection throughout" />
                </div>

                <!-- Single Start Assessment button -->
                <button
                  type="button"
                  phx-click="start_assessment"
                  class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold transition cursor-pointer"
                  style="background-color: #FF8B00;"
                >
                  Start Assessment →
                </button>
              </div>

              <!-- Helper sidebar -->
              <div class="space-y-4">
                <div class="rounded-2xl border border-cream-200 p-4" style="background-color: #FFF1DE;">
                  <div class="flex items-start gap-2 mb-1">
                    <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5" style="color: #B85F00;" />
                    <p class="text-sm font-semibold text-gray-800">Tip from your Vyaasa Coach</p>
                  </div>
                  <p class="text-xs text-gray-600 leading-relaxed">
                    A calm mind performs better. Take a deep breath, read carefully, and trust your preparation.
                  </p>
                </div>

                <div class="bg-white rounded-2xl border border-gray-100 p-4">
                  <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">
                    What we'll evaluate
                  </p>
                  <ul class="space-y-2 text-sm text-gray-700">
                    <li class="flex items-center gap-2"><span class="w-1.5 h-1.5 rounded-full" style="background-color: #FF8B00;"></span>Conceptual Understanding</li>
                    <li class="flex items-center gap-2"><span class="w-1.5 h-1.5 rounded-full" style="background-color: #FF8B00;"></span>Analytical Thinking</li>
                    <li class="flex items-center gap-2"><span class="w-1.5 h-1.5 rounded-full" style="background-color: #FF8B00;"></span>Problem Solving</li>
                    <li class="flex items-center gap-2"><span class="w-1.5 h-1.5 rounded-full" style="background-color: #FF8B00;"></span>Accuracy & Consistency</li>
                    <li class="flex items-center gap-2"><span class="w-1.5 h-1.5 rounded-full" style="background-color: #FF8B00;"></span>Time Management</li>
                  </ul>
                </div>

              </div>
            </div>
          </div>
        </main>
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp rule_tile(assigns) do
    ~H"""
    <div class="bg-white rounded-xl p-3.5 border border-cream-200 hover:border-brand-200 transition">
      <div class="flex items-start gap-2.5 mb-1">
        <div
          class="w-7 h-7 rounded-full flex items-center justify-center shrink-0"
          style="background-color: #FFE9D2;"
        >
          <.icon name={@icon} class="w-3.5 h-3.5" style="color: #B85F00;" />
        </div>
        <p class="text-xs font-semibold text-gray-900 leading-snug mt-0.5">{@title}</p>
      </div>
      <p class="text-[11px] text-gray-500 leading-relaxed ml-9">{@description}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp meta_tile(assigns) do
    ~H"""
    <div class="bg-white rounded-xl px-3 py-2.5 border border-cream-200">
      <p class="text-[10px] uppercase tracking-wider text-gray-500 font-semibold">{@label}</p>
      <p class="text-lg font-bold text-gray-900 mt-0.5">{@value}</p>
    </div>
    """
  end

  defp _legacy_render(assigns) do
    ~H"""
    <div>
      <!-- Main Content Card -->
      <div class="max-w-4xl mx-auto">
        <div class="bg-white rounded-xl shadow-md border-t-4 border-orange-500">
          <!-- Section A: Assessment Overview -->
          <div class="p-8 border-b border-gray-200">
            <div class="flex items-center space-x-3 mb-6">
              <.icon name="hero-clipboard-document-list" class="w-8 h-8 text-orange-500" />
              <h2 class="text-2xl font-bold text-gray-900">Assessment Instructions</h2>
            </div>

            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
              <!-- Info Cards -->
              <div class="bg-orange-50 rounded-lg p-4 border border-orange-200">
                <div class="flex items-center space-x-2 mb-2">
                  <.icon name="hero-question-mark-circle" class="w-5 h-5 text-orange-600" />
                  <span class="text-xs font-medium text-orange-700 uppercase">Questions</span>
                </div>
                <p class="text-2xl font-bold text-gray-900">{@total_questions}</p>
              </div>

              <div class="bg-blue-50 rounded-lg p-4 border border-blue-200">
                <div class="flex items-center space-x-2 mb-2">
                  <.icon name="hero-clock" class="w-5 h-5 text-blue-600" />
                  <span class="text-xs font-medium text-blue-700 uppercase">Duration</span>
                </div>
                <p class="text-2xl font-bold text-gray-900">{@assessment.duration_minutes} min</p>
              </div>

              <div class="bg-green-50 rounded-lg p-4 border border-green-200">
                <div class="flex items-center space-x-2 mb-2">
                  <.icon name="hero-star" class="w-5 h-5 text-green-600" />
                  <span class="text-xs font-medium text-green-700 uppercase">Total Marks</span>
                </div>
                <p class="text-2xl font-bold text-gray-900">{@assessment.total_marks}</p>
              </div>

              <div class="bg-purple-50 rounded-lg p-4 border border-purple-200">
                <div class="flex items-center space-x-2 mb-2">
                  <.icon name="hero-squares-2x2" class="w-5 h-5 text-purple-600" />
                  <span class="text-xs font-medium text-purple-700 uppercase">Sections</span>
                </div>
                <p class="text-2xl font-bold text-gray-900">{@section_count}</p>
              </div>
            </div>
          </div>
          <!-- Section B: Section Breakdown -->
          <div class="p-8 border-b border-gray-200">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Section Breakdown</h3>

            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Section
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Questions
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Duration
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Marks per Q
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Negative Marking
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for section <- @sections do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        {section.name}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-700">{section.count}</td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-700">{section.duration} min</td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-700">1</td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-700">-0.25</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
          <!-- Section C: Rules & Guidelines -->
          <div class="p-8 border-b border-gray-200">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Rules & Guidelines</h3>

            <div class="space-y-3">
              <div class="flex items-start space-x-3">
                <span class="text-xl">⏱️</span>
                <p class="text-sm text-gray-700 leading-relaxed">
                  The timer starts immediately once you begin. You cannot pause the test.
                </p>
              </div>

              <div class="flex items-start space-x-3">
                <span class="text-xl">📝</span>
                <p class="text-sm text-gray-700 leading-relaxed">
                  Each question has 4 options. Select one answer per question.
                </p>
              </div>

              <div class="flex items-start space-x-3">
                <span class="text-xl">⚠️</span>
                <p class="text-sm text-gray-700 leading-relaxed">
                  Negative marking of -0.25 applies for each wrong answer.
                </p>
              </div>

              <div class="flex items-start space-x-3">
                <span class="text-xl">⏭️</span>
                <p class="text-sm text-gray-700 leading-relaxed">
                  You can navigate between questions freely within a section.
                </p>
              </div>

              <div class="flex items-start space-x-3">
                <span class="text-xl">🔖</span>
                <p class="text-sm text-gray-700 leading-relaxed">
                  Use "Mark for Review" to flag questions you want to revisit.
                </p>
              </div>

              <div class="flex items-start space-x-3">
                <span class="text-xl">🔒</span>
                <p class="text-sm text-gray-700 leading-relaxed">
                  You cannot go back to a previous section once you move to the next.
                </p>
              </div>

              <div class="flex items-start space-x-3">
                <span class="text-xl">📤</span>
                <p class="text-sm text-gray-700 leading-relaxed">
                  The test will auto-submit when the timer expires.
                </p>
              </div>

              <div class="flex items-start space-x-3">
                <span class="text-xl">🚫</span>
                <p class="text-sm text-gray-700 leading-relaxed">
                  Do not switch tabs or minimize the browser — this may be flagged.
                </p>
              </div>

              <div class="flex items-start space-x-3">
                <span class="text-xl">🌐</span>
                <p class="text-sm text-gray-700 leading-relaxed">
                  Ensure a stable internet connection throughout the test.
                </p>
              </div>
            </div>
          </div>
          <!-- Section D: Acknowledgment -->
          <div class="p-8">
            <div class="mb-6">
              <label class="flex items-start space-x-3 cursor-pointer">
                <input
                  type="checkbox"
                  class="mt-1 h-5 w-5 rounded border-gray-300 text-orange-600 focus:ring-orange-500"
                  phx-click="toggle_agreement"
                  checked={@agreed_to_terms}
                />
                <span class="text-sm text-gray-700 leading-relaxed">
                  I have read and understood all the instructions and rules. I agree to abide by them.
                </span>
              </label>
            </div>

            <div class="flex items-center justify-between">
              <button
                type="button"
                phx-click="back_to_dashboard"
                class="px-6 py-3 border border-gray-300 rounded-md text-gray-700 font-medium hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500 transition-colors"
              >
                ← Back to Dashboard
              </button>

              <button
                type="button"
                phx-click="start_assessment"
                disabled={!@agreed_to_terms}
                class={"px-8 py-3 rounded-md font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500 #{if @agreed_to_terms, do: "bg-orange-500 hover:bg-orange-600 text-white cursor-pointer", else: "bg-gray-300 text-gray-500 cursor-not-allowed"}"}
              >
                Start Assessment →
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp build_section_breakdown(questions, total_duration) do
    grouped =
      questions
      |> Enum.group_by(fn q -> q["subject"] || "General" end)
      |> Enum.map(fn {subject, qs} -> {subject, length(qs)} end)
      |> Enum.sort_by(fn {subject, _} -> if subject == "Aptitude", do: 0, else: 1 end)

    total_count = max(1, length(questions))

    Enum.map(grouped, fn {subject, count} ->
      duration = round(count / total_count * total_duration)
      %{name: subject, count: count, duration: duration}
    end)
  end
end
