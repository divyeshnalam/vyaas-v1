defmodule VyaasaCampusWeb.TenantUser.ProgramsLive do
  @moduledoc """
  Tenant admin LiveView for selecting which degrees and specializations
  their institution offers. Students can only be created with these selections.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Academics
  alias VyaasaCampus.Contexts.Tenants

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.TenantAdmin.AdminShell

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))

    if is_nil(tenant) do
      {:ok, push_navigate(socket, to: ~p"/auth/tenant/#{tenant_alias}/login")}
    else
      all_degrees = Academics.list_degrees()
      selected_degree_ids = MapSet.new(Academics.list_tenant_degree_ids(tenant.id))
      selected_spec_ids = MapSet.new(Academics.list_tenant_specialization_ids(tenant.id))

      {:ok,
       socket
       |> assign(:page_title, "Programs")
       |> assign(:tenant_alias, tenant_alias)
       |> assign(:tenant, tenant)
       |> assign(:current_scope, :tenant_admin)
       |> assign(:user_info, build_user_info(socket.assigns[:current_user]))
       |> assign(:all_degrees, all_degrees)
       |> assign(:selected_degree_ids, selected_degree_ids)
       |> assign(:selected_spec_ids, selected_spec_ids)
       |> assign(:current_section, "programs")}
    end
  end

  @impl true
  def handle_event("toggle_degree", %{"id" => degree_id}, socket) do
    tenant = socket.assigns.tenant
    Academics.toggle_tenant_degree(tenant.id, degree_id)

    selected_degree_ids = MapSet.new(Academics.list_tenant_degree_ids(tenant.id))
    selected_spec_ids = MapSet.new(Academics.list_tenant_specialization_ids(tenant.id))

    {:noreply,
     socket
     |> assign(:selected_degree_ids, selected_degree_ids)
     |> assign(:selected_spec_ids, selected_spec_ids)}
  end

  @impl true
  def handle_event("toggle_spec", %{"id" => spec_id}, socket) do
    tenant = socket.assigns.tenant
    Academics.toggle_tenant_specialization(tenant.id, spec_id)

    selected_spec_ids = MapSet.new(Academics.list_tenant_specialization_ids(tenant.id))
    {:noreply, assign(socket, :selected_spec_ids, selected_spec_ids)}
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Logged out successfully")
     |> redirect(to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.admin_layout
        tenant_alias={@tenant_alias}
        tenant_name={@tenant.full_name}
        current_section={@current_section}
        user_info={@user_info}
      >
        <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-[1400px] mx-auto w-full">
            <div class="max-w-4xl">
              <div class="mb-6">
                <h2 class="text-lg font-semibold text-gray-900">Select Programs Your Institution Offers</h2>
                <p class="text-sm text-gray-500">
                  Toggle the degrees and specializations available at your institution.
                  Only selected programs will be available when creating students.
                </p>
              </div>

              <%= if Enum.empty?(@all_degrees) do %>
                <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-12 text-center">
                  <.icon name="hero-academic-cap" class="h-16 w-16 text-gray-300 mx-auto mb-4" />
                  <h3 class="text-lg font-medium text-gray-900 mb-1">No Programs Available</h3>
                  <p class="text-sm text-gray-500">Contact the platform administrator to add degrees and specializations.</p>
                </div>
              <% else %>
                <div class="space-y-4">
                  <%= for degree <- @all_degrees do %>
                    <% degree_selected = MapSet.member?(@selected_degree_ids, degree.id) %>
                    <div class={"bg-white rounded-xl shadow-sm border transition-colors " <> if(degree_selected, do: "border-orange-300", else: "border-gray-200")}>
                      <!-- Degree Header -->
                      <div class="px-6 py-4 flex items-center justify-between">
                        <div class="flex items-center">
                          <button
                            phx-click="toggle_degree"
                            phx-value-id={degree.id}
                            class={[
                              "w-6 h-6 rounded-md border-2 flex items-center justify-center transition-colors mr-4",
                              if(degree_selected,
                                do: "bg-orange-500 border-orange-500",
                                else: "border-gray-300 hover:border-orange-400")
                            ]}
                          >
                            <%= if degree_selected do %>
                              <.icon name="hero-check" class="h-4 w-4 text-white" />
                            <% end %>
                          </button>
                          <div>
                            <p class="text-base font-semibold text-gray-900">{degree.name}</p>
                            <code class="text-xs bg-gray-100 px-1.5 py-0.5 rounded text-gray-500">{degree.code}</code>
                          </div>
                        </div>
                        <span class="text-xs text-gray-400">
                          {length(degree.specializations)} specialization(s)
                        </span>
                      </div>

                      <!-- Specializations (show only if degree is selected) -->
                      <%= if degree_selected && length(degree.specializations) > 0 do %>
                        <div class="px-6 pb-4 border-t border-gray-100 pt-3">
                          <p class="text-xs font-medium text-gray-500 uppercase mb-2">Specializations</p>
                          <div class="flex flex-wrap gap-2">
                            <%= for spec <- degree.specializations do %>
                              <% spec_selected = MapSet.member?(@selected_spec_ids, spec.id) %>
                              <button
                                phx-click="toggle_spec"
                                phx-value-id={spec.id}
                                class={[
                                  "inline-flex items-center px-3 py-1.5 rounded-full text-sm font-medium border transition-colors",
                                  if(spec_selected,
                                    do: "bg-blue-500 text-white border-blue-500",
                                    else: "bg-white text-gray-700 border-gray-300 hover:border-blue-400 hover:bg-blue-50")
                                ]}
                              >
                                <%= if spec_selected do %>
                                  <.icon name="hero-check" class="h-3.5 w-3.5 mr-1" />
                                <% end %>
                                {spec.name}
                              </button>
                            <% end %>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
        </div>
      </.admin_layout>
    </Layouts.app>
    """
  end

  defp build_user_info(nil), do: %{name: "Admin", email: "", role: "Admin"}

  defp build_user_info(u),
    do: %{name: String.trim("#{u.first_name} #{u.last_name}"), email: u.email || "", role: u.role || "Admin"}
end
