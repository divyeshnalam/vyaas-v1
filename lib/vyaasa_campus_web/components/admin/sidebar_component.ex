defmodule VyaasaCampusWeb.Components.Admin.SidebarComponent do
  @moduledoc """
  Sidebar component for super admin dashboard.
  Provides navigation between dashboard sections.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI
  alias Phoenix.LiveView.JS

  attr :current_page, :string, required: true

  def sidebar(assigns) do
    ~H"""
    <!-- Desktop Sidebar -->
    <div
      id="admin-sidebar"
      class="hidden lg:flex lg:flex-col bg-slate-900 min-h-screen border-r border-slate-700 transition-all duration-300 w-64"
      phx-hook="SidebarToggle"
    >
      <div class="flex flex-col h-full">
        <!-- Logo + Collapse Toggle -->
        <div class="flex items-center justify-between h-16 px-4 border-b border-slate-700">
          <div class="flex items-center sidebar-expanded-only">
            <div class="w-9 h-9 bg-linear-to-br from-orange-500 to-orange-600 rounded-lg flex items-center justify-center">
              <.icon name="hero-shield-check" class="h-5 w-5 text-white" />
            </div>
            <div class="ml-3">
              <span class="text-sm font-bold text-white">VyaasaCampus</span>
              <span class="block text-[10px] text-slate-400 leading-none">Super Admin</span>
            </div>
          </div>
          <button
            id="sidebar-toggle-btn"
            class="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-700 transition-colors"
            phx-click={JS.dispatch("toggle-sidebar", to: "#admin-sidebar")}
            title="Toggle sidebar"
          >
            <.icon name="hero-chevron-double-left" class="w-5 h-5 sidebar-expanded-icon" />
            <.icon name="hero-chevron-double-right" class="w-5 h-5 sidebar-collapsed-icon hidden" />
          </button>
        </div>

        <!-- Navigation -->
        <nav class="flex-1 px-3 py-6 space-y-1 overflow-y-auto">
          <p class="px-3 mb-2 text-[10px] font-semibold text-slate-500 uppercase tracking-wider sidebar-label">
            Main
          </p>
          <.sidebar_link
            href="/admin/dashboard"
            icon="hero-home"
            label="Dashboard"
            active={@current_page == "dashboard"}
          />

          <p class="px-3 mt-6 mb-2 text-[10px] font-semibold text-slate-500 uppercase tracking-wider sidebar-label">
            Configuration
          </p>
          <.sidebar_link
            href="/admin/colleges"
            icon="hero-clipboard-document-list"
            label="Assessments Config"
            active={@current_page == "assessments_config"}
          />
          <.sidebar_link
            href="/admin/ai8-config"
            icon="hero-squares-plus"
            label="AI8 Evaluation Config"
            active={@current_page == "ai8_config"}
          />
          <.sidebar_link
            href="/admin/degrees"
            icon="hero-academic-cap"
            label="Degrees & Specs"
            active={@current_page == "degrees"}
          />
          <.sidebar_link
            href="/admin/question-bank"
            icon="hero-circle-stack"
            label="Question Bank"
            active={@current_page == "question_bank"}
          />
          <.sidebar_link
            href="/admin/jobs"
            icon="hero-briefcase"
            label="Industries & Jobs"
            active={@current_page == "jobs"}
          />
        </nav>

        <!-- Footer -->
        <div class="px-3 py-4 border-t border-slate-700 space-y-1">
          <.sidebar_link
            href="/admin/change-password"
            icon="hero-key"
            label="Change Password"
            active={@current_page == "change_password"}
          />
          <.link
            navigate="/auth/admin/logout"
            class="flex items-center px-3 py-2.5 rounded-lg text-sm font-medium text-red-400 hover:bg-slate-800 hover:text-red-300 transition-colors"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5 mr-3 shrink-0" />
            <span class="sidebar-label">Logout</span>
          </.link>
        </div>
      </div>
    </div>

    <!-- Mobile Sidebar -->
    <div
      class="lg:hidden fixed inset-y-0 left-0 z-30 w-64 bg-slate-900 transform -translate-x-full transition-transform duration-200 ease-in-out"
      id="admin-mobile-sidebar"
    >
      <div class="flex flex-col h-full">
        <div class="flex items-center justify-between h-16 px-4 border-b border-slate-700">
          <div class="flex items-center">
            <div class="w-9 h-9 bg-linear-to-br from-orange-500 to-orange-600 rounded-lg flex items-center justify-center">
              <.icon name="hero-shield-check" class="h-5 w-5 text-white" />
            </div>
            <span class="ml-2 text-sm font-bold text-white">Super Admin</span>
          </div>
          <button
            class="text-slate-300 hover:text-white p-2"
            phx-click={JS.add_class("-translate-x-full", to: "#admin-mobile-sidebar") |> JS.remove_class("translate-x-0", to: "#admin-mobile-sidebar") |> JS.hide(to: "#admin-mobile-backdrop")}
          >
            <.icon name="hero-x-mark" class="w-6 h-6" />
          </button>
        </div>

        <nav class="flex-1 px-4 py-6 space-y-2 overflow-y-auto">
          <p class="px-3 mb-2 text-[10px] font-semibold text-slate-500 uppercase tracking-wider">
            Main
          </p>
          <.sidebar_link
            href="/admin/dashboard"
            icon="hero-home"
            label="Dashboard"
            active={@current_page == "dashboard"}
            close_mobile={true}
          />

          <p class="px-3 mt-6 mb-2 text-[10px] font-semibold text-slate-500 uppercase tracking-wider">
            Configuration
          </p>
          <.sidebar_link
            href="/admin/colleges"
            icon="hero-clipboard-document-list"
            label="Assessments Config"
            active={@current_page == "assessments_config"}
            close_mobile={true}
          />
          <.sidebar_link
            href="/admin/ai8-config"
            icon="hero-squares-plus"
            label="AI8 Evaluation Config"
            active={@current_page == "ai8_config"}
            close_mobile={true}
          />
          <.sidebar_link
            href="/admin/degrees"
            icon="hero-academic-cap"
            label="Degrees & Specs"
            active={@current_page == "degrees"}
            close_mobile={true}
          />
          <.sidebar_link
            href="/admin/question-bank"
            icon="hero-circle-stack"
            label="Question Bank"
            active={@current_page == "question_bank"}
            close_mobile={true}
          />
          <.sidebar_link
            href="/admin/jobs"
            icon="hero-briefcase"
            label="Industries & Jobs"
            active={@current_page == "jobs"}
            close_mobile={true}
          />
        </nav>

        <div class="px-4 py-4 border-t border-slate-700 space-y-1">
          <.sidebar_link
            href="/admin/change-password"
            icon="hero-key"
            label="Change Password"
            active={@current_page == "change_password"}
            close_mobile={true}
          />
          <.link
            navigate="/auth/admin/logout"
            class="flex items-center px-3 py-2.5 rounded-lg text-sm font-medium text-red-400 hover:bg-slate-800 hover:text-red-300 transition-colors"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5 mr-3 shrink-0" />
            <span>Logout</span>
          </.link>
        </div>
      </div>
    </div>

    <!-- Mobile Backdrop -->
    <div
      id="admin-mobile-backdrop"
      class="lg:hidden fixed inset-0 z-20 bg-gray-600 bg-opacity-75 hidden"
      phx-click={JS.add_class("-translate-x-full", to: "#admin-mobile-sidebar") |> JS.remove_class("translate-x-0", to: "#admin-mobile-sidebar") |> JS.hide(to: "#admin-mobile-backdrop")}
    >
    </div>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :close_mobile, :boolean, default: false

  defp sidebar_link(assigns) do
    close_js =
      if assigns.close_mobile do
        JS.add_class("-translate-x-full", to: "#admin-mobile-sidebar")
        |> JS.remove_class("translate-x-0", to: "#admin-mobile-sidebar")
        |> JS.hide(to: "#admin-mobile-backdrop")
      else
        nil
      end

    active_class =
      if assigns.active,
        do: "bg-orange-500 text-white",
        else: "text-slate-300 hover:bg-slate-800 hover:text-white"

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
end
