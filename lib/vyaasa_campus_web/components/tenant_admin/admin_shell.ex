defmodule VyaasaCampusWeb.Components.TenantAdmin.AdminShell do
  @moduledoc """
  Shared shell (sidebar + top header + black footer bar) for the redesigned
  tenant admin screens. Pixel-matched to the Figma mockups — Inter font,
  #F97316 primary, #FBFAF7 page background, official side-bar-logo.png lockup.

  Nav items that don't have a screen yet emit `show_coming_soon` (the host
  LiveView should handle it with a flash).
  """

  use Phoenix.Component
  use VyaasaCampusWeb, :verified_routes

  import VyaasaCampusWeb.Components.UI
  alias Phoenix.LiveView.JS

  attr :tenant_alias, :string, required: true
  attr :tenant_name, :string, default: "Institution"
  attr :student_count, :integer, default: nil
  attr :current_section, :string, required: true
  attr :user_info, :map, required: true
  attr :search_placeholder, :string, default: "Search, students, assessments…"
  slot :inner_block, required: true

  def admin_layout(assigns) do
    ~H"""
    <div class="h-screen overflow-hidden flex bg-white font-sans text-gray-900">
      <.sidebar
        tenant_alias={@tenant_alias}
        tenant_name={@tenant_name}
        student_count={@student_count}
        current_section={@current_section}
      />
      <div class="flex-1 flex flex-col min-w-0 h-screen">
        <.top_header search_placeholder={@search_placeholder} user_info={@user_info} />
        <main class="flex-1 overflow-y-auto flex flex-col">
          <div class="flex-1">
            {render_slot(@inner_block)}
          </div>
          <VyaasaCampusWeb.Components.Shared.FooterComponent.footer />
        </main>
      </div>
    </div>
    """
  end

  # ── Sidebar ────────────────────────────────────────────────────────────────
  defp sidebar(assigns) do
    ~H"""
    <aside
      id="tenant-admin-sidebar"
      class="w-64 shrink-0 bg-white border-r border-gray-100 flex flex-col h-screen sticky top-0 overflow-hidden transition-all duration-300"
      phx-hook="SidebarToggle"
      data-expanded-width="256px"
      data-collapsed-width="72px"
    >
      <!-- Logo -->
      <div class="px-4 h-16 flex items-center justify-between gap-2 shrink-0">
        <img src="/images/side-bar-logo.png" alt="Vyaasa" class="h-8 w-auto sidebar-expanded-only" />
        <button
          id="tenant-admin-sidebar-toggle"
          type="button"
          phx-click={JS.dispatch("toggle-sidebar", to: "#tenant-admin-sidebar")}
          title="Toggle sidebar"
          class="w-10 h-10 rounded-lg flex items-center justify-center text-gray-500 hover:text-gray-900 hover:bg-gray-50 transition-colors"
        >
          <.sidebar_toggle_icon class="w-5 h-5 sidebar-expanded-icon" />
          <span class="sidebar-collapsed-icon hidden relative w-8 h-8">
            <img src="/images/vyaasa-mark.svg" alt="Vyaasa" class="w-8 h-8" />
          </span>
        </button>
      </div>

      <!-- Tenant -->
      <div class="mx-4 mb-2 rounded-xl border border-gray-100 px-3 py-2.5 flex items-center gap-3 in-[.sidebar-collapsed]:mx-2 in-[.sidebar-collapsed]:px-1 in-[.sidebar-collapsed]:justify-center in-[.sidebar-collapsed]:border-transparent">
        <div class="w-8 h-8 rounded-full bg-[#FFF4E7] flex items-center justify-center text-[#EF6C00] text-xs font-bold shrink-0">
          {tenant_initials(@tenant_name)}
        </div>
        <div class="min-w-0 sidebar-label">
          <p class="text-sm font-bold text-gray-900 truncate leading-tight">{@tenant_name}</p>
          <p :if={@student_count} class="text-[11px] text-gray-400 leading-tight">{@student_count} students</p>
        </div>
      </div>

      <!-- Nav -->
      <nav class="flex-1 overflow-y-auto px-3 py-3 space-y-1">
        <.nav_link tenant_alias={@tenant_alias} section="dashboard" current={@current_section} icon="hero-squares-2x2" label="Dashboard" />
        <.nav_link tenant_alias={@tenant_alias} section="students" current={@current_section} icon="hero-users" label="Students" />
        <.nav_link tenant_alias={@tenant_alias} section="programs" current={@current_section} icon="hero-academic-cap" label="Programs" />
        <.nav_link tenant_alias={@tenant_alias} section="leaderboard" current={@current_section} icon="hero-trophy" label="Leaderboard" />
        <.nav_link tenant_alias={@tenant_alias} section="specializations" current={@current_section} icon="hero-rectangle-group" label="Specializations" />
        <.nav_link tenant_alias={@tenant_alias} section="placement_readiness" current={@current_section} icon="hero-chart-bar" label="Placement Readiness" />
      </nav>

      <!-- Footer -->
      <div class="px-3 py-4 border-t border-gray-100 shrink-0">
        <button
          type="button"
          phx-click="logout"
          title="Sign out"
          class="w-full h-9 px-3 rounded-lg flex items-center justify-between text-sm font-medium text-gray-500 hover:text-red-500 hover:bg-red-50 transition-colors"
        >
          <span class="sidebar-label">Logout</span>
          <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" />
        </button>
      </div>
    </aside>
    """
  end

  attr :class, :string, default: "w-5 h-5"

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
    </svg>
    """
  end

  attr :tenant_alias, :string, default: nil
  attr :section, :string, required: true
  attr :current, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :soon, :boolean, default: false

  defp nav_link(%{soon: true} = assigns) do
    ~H"""
    <button
      type="button"
      phx-click="show_coming_soon"
      class={["w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-[15px] font-medium transition", nav_class(@section, @current)]}
    >
      <.icon name={@icon} class="w-5 h-5 shrink-0" /> <span class="sidebar-label">{@label}</span>
    </button>
    """
  end

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={nav_path(@tenant_alias, @section)}
      class={["w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-[15px] font-medium transition", nav_class(@section, @current)]}
    >
      <.icon name={@icon} class="w-5 h-5 shrink-0" /> <span class="sidebar-label">{@label}</span>
    </.link>
    """
  end

  defp nav_class(section, current) when section == current,
    do: "bg-[#FFF4E7] text-[#F97316]"

  defp nav_class(_section, _current),
    do: "text-gray-600 hover:bg-gray-50 hover:text-gray-900"

  defp nav_path(alias, "dashboard"), do: ~p"/user/#{alias}/dashboard"
  defp nav_path(alias, "students"), do: ~p"/user/#{alias}/dashboard/students"
  defp nav_path(alias, "programs"), do: ~p"/user/#{alias}/dashboard/programs"
  defp nav_path(alias, "leaderboard"), do: ~p"/user/#{alias}/dashboard?tab=leaderboard"
  defp nav_path(alias, "specializations"), do: ~p"/user/#{alias}/dashboard?tab=departments"
  defp nav_path(alias, "placement_readiness"), do: ~p"/user/#{alias}/dashboard?tab=readiness"
  defp nav_path(alias, _), do: ~p"/user/#{alias}/dashboard"

  # ── Top header ───────────────────────────────────────────────────────────
  attr :search_placeholder, :string, required: true
  attr :user_info, :map, required: true

  defp top_header(assigns) do
    ~H"""
    <header class="h-16 bg-white border-b border-gray-100 flex items-center gap-4 px-6 lg:px-8 shrink-0">
      <div class="flex-1 max-w-md">
        <div class="relative">
          <.icon name="hero-magnifying-glass" class="w-4 h-4 text-gray-400 absolute left-4 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            disabled
            placeholder={@search_placeholder}
            class="w-full pl-10 pr-3 py-2.5 rounded-full bg-[#F3F4F6] border border-transparent text-sm text-gray-600 placeholder-gray-400 focus:outline-none"
          />
        </div>
      </div>
      <div class="ml-auto flex items-center gap-5">
        <%!-- <button type="button" class="text-gray-600 hover:text-gray-900">
          <.icon name="hero-globe-alt" class="w-5 h-5" />
        </button>
        <button type="button" class="relative text-gray-600 hover:text-gray-900">
          <.icon name="hero-bell" class="w-5 h-5" />
          <span class="absolute -top-1.5 -right-1.5 min-w-4 h-4 px-1 rounded-full bg-[#F97316] text-white text-[9px] font-bold flex items-center justify-center">3</span>
        </button> --%>
        <div class="flex items-center gap-2.5">
          <div class="text-right leading-tight hidden sm:block">
            <p class="text-sm font-bold text-gray-900">{@user_info[:name]}</p>
            <p class="text-[11px] text-gray-400">{@user_info[:email]}</p>
          </div>
          <div class="w-9 h-9 rounded-full bg-[#F97316] flex items-center justify-center text-white text-[11px] font-bold shrink-0">
            {user_initials(@user_info[:name])}
          </div>
        </div>
      </div>
    </header>
    """
  end

  # ── helpers ──────────────────────────────────────────────────────────────
  defp tenant_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp tenant_initials(_), do: "IN"

  defp user_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  defp user_initials(_), do: "U"
end
