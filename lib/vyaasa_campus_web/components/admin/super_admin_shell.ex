defmodule VyaasaCampusWeb.Components.Admin.SuperAdminShell do
  @moduledoc """
  Shared shell (full left nav + top header) for the redesigned super-admin
  (platform) screens, matched to the Bolt mockup. Inter font, #F97316 primary,
  white sidebar, #FBFAF7 page bg, user in the top-right header.

  Nav items without a screen yet emit `show_coming_soon` (host LiveView handles
  it with a flash).
  """

  use Phoenix.Component
  use VyaasaCampusWeb, :verified_routes

  import VyaasaCampusWeb.Components.UI
  alias Phoenix.LiveView.JS

  attr(:active_tenants, :integer, default: nil)
  attr(:user_info, :map, required: true)
  attr(:current_section, :string, default: nil)
  attr(:search_placeholder, :string, default: "Search students, colleges, assessments…")
  slot(:inner_block, required: true)

  def admin_layout(assigns) do
    ~H"""
    <div class="min-h-screen flex bg-[#FBFAF7] font-sans text-gray-900">
      <aside
        id="super-admin-sidebar"
        class="w-60 shrink-0 bg-white border-r border-gray-100 flex flex-col h-screen sticky top-0 transition-all duration-300"
        phx-hook="SidebarToggle"
        data-expanded-width="240px"
        data-collapsed-width="72px"
      >
        <div class="px-4 h-16 flex items-center justify-between gap-2 shrink-0">
          <.link navigate={~p"/admin/dashboard"} class="min-w-0 sidebar-expanded-only">
            <img src="/images/side-bar-logo.png" alt="Vyaasa" class="h-8 w-auto" />
          </.link>
          <button
            id="super-admin-sidebar-toggle"
            type="button"
            phx-click={JS.dispatch("toggle-sidebar", to: "#super-admin-sidebar")}
            title="Toggle sidebar"
            class="w-10 h-10 rounded-lg flex items-center justify-center text-gray-500 hover:text-gray-900 hover:bg-gray-50 transition-colors"
          >
            <.sidebar_toggle_icon class="w-5 h-5 sidebar-expanded-icon" />
            <span class="sidebar-collapsed-icon hidden relative w-8 h-8">
              <img src="/images/vyaasa-mark.svg" alt="Vyaasa" class="w-8 h-8" />
            </span>
          </button>
        </div>

        <nav class="flex-1 overflow-y-auto px-3 py-2 space-y-0.5">
          <.nav navigate={~p"/admin/dashboard"} section="dashboard" current={@current_section} icon="hero-squares-2x2" label="Dashboard" />
          <.nav navigate={~p"/admin/colleges"} section="colleges" current={@current_section} icon="hero-building-office-2" label="Colleges" />
          <.nav navigate={~p"/admin/question-bank"} section="question_bank" current={@current_section} icon="hero-rectangle-stack" label="Question Bank" />
          <.nav navigate={~p"/admin/jobs"} section="jobs" current={@current_section} icon="hero-briefcase" label="Job Roles" />
          <.nav navigate={~p"/admin/ai8-config"} section="ai8" current={@current_section} icon="hero-adjustments-horizontal" label="AI8 Config" />
          <.nav navigate={~p"/admin/degrees"} section="degrees" current={@current_section} icon="hero-academic-cap" label="Degrees" />
        </nav>

        <div class="px-3 py-4 border-t border-gray-100 shrink-0">
          <.link
            navigate={~p"/auth/admin/logout"}
            title="Sign out"
            class="w-full h-9 px-3 rounded-lg flex items-center justify-between text-sm font-medium text-gray-500 hover:text-red-500 hover:bg-red-50 transition-colors"
          >
            <span class="sidebar-label">Logout</span>
            <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" />
          </.link>
        </div>
      </aside>

      <div class="flex-1 flex flex-col min-w-0">
        <header class="h-16 bg-white border-b border-gray-100 flex items-center gap-4 px-6 lg:px-8 shrink-0">
          <div class="flex-1 max-w-xl">
            <div class="relative">
              <.icon name="hero-magnifying-glass" class="w-4 h-4 text-gray-400 absolute left-4 top-1/2 -translate-y-1/2" />
              <input type="text" disabled placeholder={@search_placeholder}
                class="w-full pl-10 pr-3 py-2.5 rounded-full bg-[#F3F4F6] border border-transparent text-sm text-gray-600 placeholder-gray-400 focus:outline-none" />
            </div>
          </div>
          <div class="ml-auto flex items-center gap-5">
            <%!-- <div class="relative">
              <.icon name="hero-bell" class="w-5 h-5 text-gray-600" />
              <span class="absolute -top-1.5 -right-1.5 min-w-4 h-4 px-1 rounded-full bg-[#F97316] text-white text-[9px] font-bold flex items-center justify-center">3</span>
            </div> --%>
            <div class="flex items-center gap-2.5">
              <div class="text-right leading-tight hidden sm:block">
                <p class="text-sm font-bold text-gray-900">{@user_info[:name]}</p>
                <p class="text-[11px] text-gray-400">{@user_info[:email] || @user_info[:role]}</p>
              </div>
              <div class="w-9 h-9 rounded-full bg-[#0F1B2D] flex items-center justify-center text-white text-[11px] font-bold shrink-0">
                {user_initials(@user_info[:name])}
              </div>
            </div>
          </div>
        </header>

        <main class="flex-1 overflow-auto bg-white">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end

  attr(:class, :string, default: "w-5 h-5")

  defp sidebar_toggle_icon(assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="20" height="18" rx="2" />
      <path d="M9 4v16" />
      <%!-- <path d="m15 9-3 3 3 3" /> --%>
    </svg>
    """
  end

  attr(:navigate, :string, default: nil)
  attr(:section, :string, required: true)
  attr(:current, :string, default: nil)
  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)

  defp nav(%{navigate: nil} = assigns) do
    ~H"""
    <button type="button" phx-click="show_coming_soon" class={["w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition", nav_class(@section, @current)]}>
      <.icon name={@icon} class="w-5 h-5 shrink-0" /> <span class="sidebar-label">{@label}</span>
    </button>
    """
  end

  defp nav(assigns) do
    ~H"""
    <.link navigate={@navigate} class={["w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition", nav_class(@section, @current)]}>
      <.icon name={@icon} class="w-5 h-5 shrink-0" /> <span class="sidebar-label">{@label}</span>
    </.link>
    """
  end

  defp nav_class(section, current) when section == current, do: "bg-[#FFF4E7] text-[#F97316]"
  defp nav_class(_section, _current), do: "text-gray-600 hover:bg-gray-50 hover:text-gray-900"

  defp user_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  defp user_initials(_), do: "SA"
end
