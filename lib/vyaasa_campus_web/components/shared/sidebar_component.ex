defmodule VyaasaCampusWeb.Components.Shared.SidebarComponent do
  @moduledoc """
  Sidebar component for tenant dashboard.
  Provides navigation menu with collapse/expand toggle on desktop
  and slide-in drawer on mobile.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI
  alias Phoenix.LiveView.JS

  def sidebar(assigns) do
    ~H"""
    <!-- Desktop Sidebar (collapsible) -->
    <div
      id="desktop-sidebar"
      class="hidden lg:flex lg:flex-col bg-white min-h-screen border-r border-gray-200 transition-all duration-300 w-64"
      phx-hook="SidebarToggle"
    >
      <div class="flex flex-col h-full">
        <!-- Logo + Collapse Toggle -->
        <div class="flex items-center justify-between h-16 px-4 border-b border-gray-100">
          <div class="flex items-center sidebar-expanded-only">
            <img src="/images/logo.png" alt="Vyaasa Logo" class="w-30 h-30 p-4" />
          </div>
          <button
            id="sidebar-toggle-btn"
            class="p-1.5 rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors"
            phx-click={JS.dispatch("toggle-sidebar", to: "#desktop-sidebar")}
            title="Toggle sidebar"
          >
            <.icon name="hero-chevron-double-left" class="w-5 h-5 sidebar-expanded-icon" />
            <.icon name="hero-chevron-double-right" class="w-5 h-5 sidebar-collapsed-icon hidden" />
          </button>
        </div>

        <!-- Navigation Menu -->
        <nav class="flex-1 px-3 py-6 space-y-1 overflow-y-auto">
          <.sidebar_link
            href={"/user/#{@tenant_alias}/dashboard"}
            icon="hero-home"
            label="Dashboard"
            active={@current_section == "dashboard"}
            theme="light"
          />
          <.sidebar_link
            href={"/user/#{@tenant_alias}/dashboard/programs"}
            icon="hero-academic-cap"
            label="Programs"
            active={@current_section == "programs"}
            theme="light"
          />
        </nav>

        <!-- Footer -->
        <div class="px-3 py-4 border-t border-gray-200">
          <.sidebar_link
            href={"/user/#{@tenant_alias}/change-password"}
            icon="hero-key"
            label="Change Password"
            active={@current_section == "change_password"}
            theme="light"
          />
        </div>
      </div>
    </div>

    <!-- Mobile Sidebar -->
    <div
      class="lg:hidden fixed inset-y-0 left-0 z-30 w-64 bg-gray-800 transform -translate-x-full transition-transform duration-200 ease-in-out"
      id="mobile-sidebar"
    >
      <div class="flex flex-col h-full">
        <!-- Logo + Close Button -->
        <div class="flex items-center justify-between h-16 px-4 border-b border-gray-700">
          <div class="flex items-center">
            <img src="/images/logo.png" alt="Vyaasa Logo" class="w-8 h-8" />
            <span class="ml-2 text-xl font-bold text-white">VYAASA</span>
          </div>
          <button
            class="text-gray-300 hover:text-white p-2"
            phx-click={JS.add_class("-translate-x-full", to: "#mobile-sidebar") |> JS.remove_class("translate-x-0", to: "#mobile-sidebar") |> JS.hide(to: "#mobile-sidebar-backdrop")}
          >
            <.icon name="hero-x-mark" class="w-6 h-6" />
          </button>
        </div>

        <!-- Navigation Menu -->
        <nav class="flex-1 px-4 py-6 space-y-2 overflow-y-auto">
          <.sidebar_link
            href={"/user/#{@tenant_alias}/dashboard"}
            icon="hero-home"
            label="Dashboard"
            active={@current_section == "dashboard"}
            theme="dark"
            close_mobile={true}
          />
          <.sidebar_link
            href={"/user/#{@tenant_alias}/dashboard/programs"}
            icon="hero-academic-cap"
            label="Programs"
            active={@current_section == "programs"}
            theme="dark"
            close_mobile={true}
          />
        </nav>

        <!-- Footer -->
        <div class="px-4 py-4 border-t border-gray-700">
          <.sidebar_link
            href={"/user/#{@tenant_alias}/change-password"}
            icon="hero-key"
            label="Change Password"
            active={@current_section == "change_password"}
            theme="dark"
            close_mobile={true}
          />
        </div>
      </div>
    </div>
    """
  end

  # Reusable nav link component
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :theme, :string, default: "light"
  attr :close_mobile, :boolean, default: false

  defp sidebar_link(assigns) do
    close_js = if assigns.close_mobile do
      JS.add_class("-translate-x-full", to: "#mobile-sidebar")
      |> JS.remove_class("translate-x-0", to: "#mobile-sidebar")
      |> JS.hide(to: "#mobile-sidebar-backdrop")
    else
      nil
    end

    active_class = case {assigns.active, assigns.theme} do
      {true, "light"} -> "bg-orange-500 text-white"
      {true, "dark"} -> "bg-orange-500 text-white"
      {false, "light"} -> "text-gray-600 hover:bg-gray-100 hover:text-gray-900"
      {false, "dark"} -> "text-gray-300 hover:bg-gray-700 hover:text-white"
    end

    assigns = assigns |> assign(:close_js, close_js) |> assign(:active_class, active_class)

    ~H"""
    <.link
      navigate={@href}
      class={"flex items-center px-3 py-2.5 rounded-lg text-sm font-medium transition-colors cursor-pointer " <> @active_class}
      phx-click={@close_js}
    >
      <.icon name={@icon} class="w-5 h-5 mr-3 shrink-0" />
      <span class="sidebar-label">{@label}</span>
    </.link>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :theme, :string, default: "light"

  defp sidebar_disabled(assigns) do
    text_class = if assigns.theme == "light", do: "text-gray-400", else: "text-gray-500"
    badge_class = if assigns.theme == "light", do: "bg-gray-100 text-gray-400", else: "bg-gray-700 text-gray-400"
    assigns = assigns |> assign(:text_class, text_class) |> assign(:badge_class, badge_class)

    ~H"""
    <span class={"flex items-center px-3 py-2.5 rounded-lg text-sm font-medium cursor-not-allowed " <> @text_class} title="Coming Soon">
      <.icon name={@icon} class="w-5 h-5 mr-3 shrink-0" />
      <span class="sidebar-label">{@label}</span>
      <span class={"ml-auto text-xs px-2 py-0.5 rounded-full sidebar-label " <> @badge_class}>Soon</span>
    </span>
    """
  end
end
