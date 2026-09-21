defmodule VyaasaCampusWeb.Components.Shared.DashboardLayout do
  @moduledoc """
  Main dashboard layout component that combines header, sidebar, and content area.
  Supports collapsible sidebar on desktop.
  """

  use Phoenix.Component

  def dashboard_layout(assigns) do
    ~H"""
    <div id="dashboard-layout" class="min-h-screen bg-gray-50 lg:flex">
      <!-- Sidebar -->
      <VyaasaCampusWeb.Components.Shared.SidebarComponent.sidebar
        tenant_alias={@tenant_alias}
        current_section={@current_section}
      />

      <!-- Main Content Area -->
      <div class="flex-1 flex flex-col min-h-screen min-w-0">
        <!-- Header -->
        <VyaasaCampusWeb.Components.Shared.HeaderComponent.header user_info={@user_info} page_title={@page_title} />

        <!-- Page Content -->
        <main class="flex-1 bg-gray-50 overflow-auto">
          <div class="p-4 lg:p-6 w-full">
            <%= render_slot(@inner_block) %>
          </div>
        </main>

        <!-- Footer -->
        <VyaasaCampusWeb.Components.Shared.FooterComponent.footer />
      </div>
    </div>

    <!-- Mobile Sidebar Backdrop -->
    <div
      id="mobile-sidebar-backdrop"
      class="lg:hidden fixed inset-0 z-20 bg-gray-600 bg-opacity-75 hidden"
      phx-click={Phoenix.LiveView.JS.add_class("-translate-x-full", to: "#mobile-sidebar") |> Phoenix.LiveView.JS.remove_class("translate-x-0", to: "#mobile-sidebar") |> Phoenix.LiveView.JS.hide(to: "#mobile-sidebar-backdrop")}
    >
    </div>
    """
  end
end
