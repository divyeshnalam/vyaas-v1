defmodule VyaasaCampusWeb.Components.Student.SidebarComponent do
  @moduledoc """
  Sidebar component for student dashboard.
  Provides navigation menu with dashboard sections and assessment links.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  attr :current_section, :string, default: "dashboard"
  attr :tenant_alias, :string, default: "default"
  attr :student_name, :string, default: "Student"
  attr :rankings, :map, default: %{}

  def sidebar(assigns) do
    ~H"""
    <aside data-app-sidenav class="hidden lg:flex lg:flex-col bg-white h-screen sticky top-0 border-r border-gray-100 w-64 shrink-0">
      <div class="flex flex-col h-full px-5 py-6">
        <!-- Logo -->
        <div class="mb-8 px-1">
          <img src="/images/side-bar-logo.png" alt="Vyaasa" class="h-14 w-auto" />
        </div>

        <!-- Nav (scrolls when taller than the viewport) -->
        <nav class="flex-1 min-h-0 overflow-y-auto space-y-6">
          <.nav_section title="OVERVIEW">
            <.nav_link
              navigate={"/student/#{@tenant_alias}/ai8-overview"}
              icon="hero-cursor-arrow-rays"
              label="AI8 Overview"
              active={@current_section == "ai8_overview"}
            />
            <.nav_link
              navigate={"/student/#{@tenant_alias}/dashboard"}
              icon="hero-squares-2x2"
              label="Assessments"
              active={@current_section == "dashboard"}
            />
          </.nav_section>

          <.nav_section title="ASSESSMENTS">
            <.nav_link
              navigate={"/student/#{@tenant_alias}/resume/insights"}
              icon="hero-document-text"
              label="Resume Insights"
              active={@current_section == "resume_insights"}
            />
            <.nav_link
              navigate={"/student/#{@tenant_alias}/interview/session"}
              icon="hero-microphone"
              label="Interactive Session"
              active={@current_section == "interview"}
            />
            <.nav_link
              navigate={"/student/#{@tenant_alias}/assessment/instructions"}
              icon="hero-puzzle-piece"
              label="Objective / MCQs"
              active={@current_section == "mcq"}
            />
            <.nav_link
              navigate={"/student/#{@tenant_alias}/jam/session"}
              icon="hero-chat-bubble-left-right"
              label="JAM Session"
              active={@current_section == "jam"}
            />
            <.nav_link
              navigate={"/student/#{@tenant_alias}/assessment/behavioral"}
              icon="hero-user-group"
              label="Situational & Behavioral"
              active={@current_section == "behavioral"}
            />
            <.nav_link
              navigate={"/student/#{@tenant_alias}/assessment/psychometric"}
              icon="hero-light-bulb"
              label="Psychometric Assessment"
              active={@current_section == "psychometric"}
            />
            <.nav_link
              navigate={"/student/#{@tenant_alias}/case-study"}
              icon="hero-academic-cap"
              label="Case Studies"
              active={@current_section == "case_studies"}
            />
            <.nav_link
              navigate={"/student/#{@tenant_alias}/mini-project"}
              icon="hero-wrench-screwdriver"
              label="Mini Project"
              active={@current_section == "mini_project"}
            />
          </.nav_section>
        </nav>
      </div>
      <!-- Footer -->
        <div class="px-3 py-4 border-t border-gray-100 shrink-0">
          <button
            phx-click="logout"
            class="w-full h-9 px-3 rounded-lg flex items-center justify-between text-sm font-medium text-gray-500 hover:text-red-500 hover:bg-red-50 transition-colors"
          >
            <span class="sidebar-label">Logout</span>
            <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" />
          </button>
        </div>
    </aside>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp nav_section(assigns) do
    ~H"""
    <div>
      <p class="text-xs font-semibold tracking-[0.12em] text-gray-400 mb-3 px-4">
        {@title}
      </p>
      <div class="space-y-1.5">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :coming_soon, :boolean, default: false

  defp nav_link(assigns) do
    ~H"""
    <%= cond do %>
      <% @coming_soon -> %>
        <button
          type="button"
          phx-click="show_coming_soon"
          class={[nav_class(@active), "w-full justify-between"]}
        >
          <span class="flex items-center gap-3 overflow-hidden">
            <.icon name={@icon} class="w-5 h-5 shrink-0" />
            <span class="truncate">{@label}</span>
          </span>
          <span class="text-[10px] font-semibold px-1.5 py-0.5 rounded-full bg-gray-100 text-gray-500 tracking-wide shrink-0">SOON</span>
        </button>
      <% @navigate -> %>
        <.link navigate={@navigate} class={nav_class(@active)}>
          <.icon name={@icon} class="w-5 h-5 shrink-0" />
          <span>{@label}</span>
        </.link>
      <% true -> %>
        <a href={@href || "#"} class={nav_class(@active)}>
          <.icon name={@icon} class="w-5 h-5 shrink-0" />
          <span>{@label}</span>
        </a>
    <% end %>
    """
  end

  defp nav_class(true),
    do:
      "flex items-center gap-3.5 px-4 py-3 rounded-xl text-base font-semibold leading-tight bg-brand-50 text-brand-600 border border-brand-200 shadow-card-soft transition"

  defp nav_class(false),
    do:
      "flex items-center gap-3.5 px-4 py-3 rounded-xl text-base text-gray-600 leading-tight bg-white border border-gray-100 shadow-card-soft hover:bg-brand-50/60 hover:text-brand-600 hover:border-brand-200 transition"
end
