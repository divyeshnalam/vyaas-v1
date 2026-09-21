defmodule VyaasaCampusWeb.Student.AI8OverviewLive do
  @moduledoc """
  Student AI8 Overview — the post-login landing. Shows the 8-dimension radar,
  the overall AI8 Index (with completion + strength/opportunity), and a card per
  skill dimension, all from `Contexts.AI8.ai8_index/2`.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.{AI8, StudentAts, Tenants}

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Shared.AI8Radar

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok, socket |> put_flash(:error, "Authentication required") |> redirect(to: "/auth/tenant/#{tenant_alias}/login")}

      user ->
        tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
        prefix = if tenant, do: tenant.schema_name, else: "public"
        profile = AI8.ai8_index(user.id, prefix)

        # Per-dimension scores in canonical order (0 when not yet assessed).
        dims = dims_from_profile(profile)

        assessed = Enum.filter(dims, & &1.score > 0)

        {:ok,
         socket
         |> assign(:tenant_alias, tenant_alias)
         |> assign(:tenant_schema, prefix)
         |> assign(:current_scope, :student)
         |> assign(:user_info, %{
           name: "#{user.first_name} #{user.last_name}",
           role: "Student",
           email: user.email,
           profile_picture_url: StudentAts.get_student_ats_fields(user.id, prefix)[:profile_picture_url]
         })
         |> assign(:page_title, "AI8 Overview")
         |> assign(:index, round(profile.index || 0))
         |> assign(:completion, round(profile.completion || 0))
         |> assign(:dims, dims)
         |> assign(:strength, Enum.max_by(assessed, & &1.score, fn -> nil end))
         |> assign(:opportunity, Enum.min_by(assessed, & &1.score, fn -> nil end))}
    end
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply, socket |> put_flash(:info, "Logged out successfully") |> redirect(to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}
  end

  def handle_event("show_coming_soon", _params, socket), do: {:noreply, put_flash(socket, :info, "Coming soon!")}

  def handle_event("email_ai8_report", _params, socket) do
    user = socket.assigns.current_user
    VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:ai8, user.id, socket.assigns.tenant_schema)
    {:noreply, put_flash(socket, :info, "Your AI8 profile report is on its way to your email ✉️")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-[#FBFAF7] flex">
        <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar current_section="ai8_overview" tenant_alias={@tenant_alias} student_name={@user_info.name} />
        <div class="flex-1 flex flex-col min-w-0">
          <VyaasaCampusWeb.Components.Student.HeaderComponent.header user_info={@user_info} tenant_alias={@tenant_alias} page_title="AI8 Overview" />
          <main class="flex-1 overflow-auto bg-white">
            <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-7xl mx-auto w-full">
              <div class="flex items-start justify-between mb-6">
                <div class="flex items-start gap-3">
                  <div class="w-10 h-10 rounded-xl bg-[#FFF4E7] flex items-center justify-center shrink-0">
                    <.icon name="hero-cursor-arrow-rays" class="w-5 h-5 text-[#EE6D18]" />
                  </div>
                  <div>
                    <h1 class="text-2xl font-bold text-gray-900">AI8 Overview</h1>
                    <p class="text-sm text-gray-500 mt-0.5">Eight dimensions that shape your career readiness — visualised, compared, and explained.</p>
                  </div>
                </div>
                <button
                  phx-click="email_ai8_report"
                  class="inline-flex items-center gap-2 text-white text-sm font-semibold px-4 py-2.5 rounded-lg transition shrink-0"
                  style="background-color: #EE6D18;"
                >
                  <.icon name="hero-envelope" class="w-4 h-4" /> Email me my AI8 report
                </button>
              </div>

              <!-- Top: radar + overall -->
              <div class="grid grid-cols-1 lg:grid-cols-[1.3fr_1fr] gap-5 mb-6">
                <div class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-5">
                  <p class="text-sm font-bold text-gray-900 mb-2">Eight-dimension radar</p>
                  <.ai8_radar dims={@dims} />
                </div>

                <div class="space-y-4">
                  <div class="bg-linear-to-br from-[#EE6D18] to-[#F18A42] text-white rounded-2xl p-5">
                    <p class="text-[10px] uppercase tracking-wide opacity-80">Overall AI8</p>
                    <p class="text-4xl font-bold mt-1">{@index}<span class="text-xl opacity-80">/100</span></p>
                    <p class="text-xs opacity-90 mt-1">{@completion}% of the AI8 assessed</p>
                  </div>
                  <div :if={@strength} class="bg-green-50 border border-green-200 rounded-2xl p-4">
                    <p class="text-[10px] uppercase tracking-wide text-green-700 font-semibold mb-0.5">Your top strength</p>
                    <p class="text-sm font-semibold text-gray-900">{@strength.label}</p>
                    <p class="text-xs text-gray-500">{@strength.score}/100 — keep leaning on this.</p>
                  </div>
                  <div :if={@opportunity} class="bg-[#FFF4E7] border border-[#F8C095] rounded-2xl p-4">
                    <p class="text-[10px] uppercase tracking-wide text-[#EE6D18] font-semibold mb-0.5">Best opportunity</p>
                    <p class="text-sm font-semibold text-gray-900">{@opportunity.label}</p>
                    <p class="text-xs text-gray-500">{@opportunity.score}/100 — your fastest way to raise the index.</p>
                  </div>
                </div>
              </div>

              <!-- 8 dimension cards -->
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div :for={d <- @dims} class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-5">
                  <div class="flex items-center justify-between mb-2">
                    <p class="font-semibold text-gray-900 text-sm">{d.label}</p>
                    <span class={["text-xl font-bold", score_color(d.score)]}>{d.score}<span class="text-xs text-gray-400">/100</span></span>
                  </div>
                  <div class="h-2 bg-[#F3E7DA] rounded-full overflow-hidden">
                    <div class={["h-full rounded-full", bar_color(d.score)]} style={"width: #{d.score}%"}></div>
                  </div>
                </div>
              </div>
            </div>
          </main>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp score_color(s) when s >= 80, do: "text-green-600"
  defp score_color(_), do: "text-[#EE6D18]"

  defp bar_color(s) when s >= 80, do: "bg-green-500"
  defp bar_color(_), do: "bg-[#EE6D18]"
end
