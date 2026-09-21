defmodule VyaasaCampusWeb.Student.Resume.InsightsLive do
  @moduledoc """
  LiveView for the Resume Analysis Dashboard — full-page view of a student's
  parsed resume insights, ATS sub-scores, areas for improvement, and the
  structured profile sections extracted from the resume.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.{StudentAts, Students, Tenants}
  alias VyaasaCampusWeb.Components.Student.Dashboard.Helpers, as: DH
  alias VyaasaCampusWeb.Components.Student.ResumeDashboard
  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    tenant_schema = get_tenant_schema(tenant_alias)
    current_user = socket.assigns[:current_user]

    case Students.get_student(current_user.id, tenant_schema) do
      nil ->
        {:ok, redirect(socket, to: "/student/#{tenant_alias}/dashboard")}

      _student ->
        ats_data =
          current_user.id
          |> StudentAts.get_by_student_id(tenant_schema)
          |> DH.convert_ats_data_to_simple_map()

        if is_nil(ats_data) do
          {:ok,
           socket
           |> put_flash(:info, "Upload your resume to see analysis insights.")
           |> redirect(to: "/student/#{tenant_alias}/resume/reanalyze")}
        else
          user_info = %{
            name: "#{current_user.first_name} #{current_user.last_name}",
            role: "Student",
            email: current_user.email,
            profile_picture_url: ats_data[:profile_picture_url]
          }

          tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))

          socket =
            socket
            |> assign(:tenant_alias, tenant_alias)
            |> assign(:tenant_schema, tenant_schema)
            |> assign(:current_user, current_user)
            |> assign(:current_scope, :student)
            |> assign(:user_info, user_info)
            |> assign(:ats_data, ats_data)
            |> assign(:page_title, "Resume Insights - #{if tenant, do: tenant.full_name, else: tenant_alias}")

          {:ok, socket}
        end
    end
  end

  # ============================================================================
  # EVENTS
  # ============================================================================

  @impl true
  def handle_event("continue_to_interview", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/interview/session")}
  end

  @impl true
  def handle_event("reanalyze_resume", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/resume/reanalyze")}
  end

  @impl true
  def handle_event("back_to_dashboard", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/dashboard")}
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply, redirect(socket, to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}
  end

  @impl true
  def handle_event("resend_report", _params, socket) do
    case socket.assigns[:ats_data] do
      %{id: id} ->
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:resume, id, socket.assigns.tenant_schema)
        {:noreply, put_flash(socket, :info, "Your resume analysis report is on its way to your email ✉️")}

      _ ->
        {:noreply, put_flash(socket, :error, "No completed resume analysis to email yet.")}
    end
  end

  # ============================================================================
  # RENDER
  # ============================================================================

  @impl true
  def render(assigns) do
    # All dashboard props (scores, sections, links) are computed by the shared
    # ResumeDashboard builder so this page and the after-parse result match.
    assigns = assign(assigns, ResumeDashboard.props(assigns.ats_data))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-cream-50 flex">
        <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar
          current_section="resume_insights"
          tenant_alias={@tenant_alias}
          student_name={@user_info.name}
        />

        <div class="flex-1 flex flex-col min-w-0">
          <VyaasaCampusWeb.Components.Student.HeaderComponent.header
            user_info={@user_info}
            tenant_alias={@tenant_alias}
            page_title="Resume Insights"
          />

          <main class="flex-1 overflow-auto">
            <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-10 py-6 space-y-6">

              <ResumeDashboard.dashboard
                score={@score}
                completeness={@completeness}
                relevance={@relevance}
                sanity={@sanity}
                completeness_feedback={@completeness_feedback}
                relevance_feedback={@relevance_feedback}
                sanity_feedback={@sanity_feedback}
                meta={@meta}
                improvement_items={@improvement_items}
                summary_text={@summary_text}
                total_experience={@total_experience}
                technical_skills={@technical_skills}
                non_technical_skills={@non_technical_skills}
                work_experience={@work_experience}
                education_list={@education_list}
                projects={@projects}
                ext_links={@ext_links}
              />

              <!-- Action buttons -->
              <VyaasaCampusWeb.Components.Student.AssessmentFooter.assessment_footer
                next_event="continue_to_interview"
                restart_event="reanalyze_resume"
                restart_label="Re-Analyse"
                dashboard_event="back_to_dashboard"
              />
            </div>

            <VyaasaCampusWeb.Components.Shared.FooterComponent.footer />
          </main>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # COMPONENTS
  # ============================================================================

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp get_tenant_schema(tenant_alias) do
    case Tenants.get_tenant_by_alias(String.upcase(tenant_alias)) do
      nil -> nil
      tenant -> tenant.schema_name
    end
  end
end
