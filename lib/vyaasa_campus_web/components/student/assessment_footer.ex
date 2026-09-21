defmodule VyaasaCampusWeb.Components.Student.AssessmentFooter do
  @moduledoc """
  Shared action footer for every student assessment result screen.

  Renders one consistent row — Continue to Next Assessment · Email/Report ·
  Restart · Go to Dashboard — so all assessments look and behave the same.
  Each screen keeps its own handlers by passing the matching event names.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  attr :next_event, :string, default: "next_assessment"
  attr :next_label, :string, default: "Continue to Next Assessment"
  attr :resend_event, :string, default: "resend_report"
  attr :show_resend, :boolean, default: true
  attr :restart_event, :string, default: "restart_assessment"
  attr :restart_label, :string, default: "Restart"
  attr :show_restart, :boolean, default: true
  attr :dashboard_event, :string, default: "back_to_dashboard"
  attr :class, :string, default: ""

  def assessment_footer(assigns) do
    ~H"""
    <div class={["flex flex-wrap items-center gap-3 pt-2", @class]}>
      <button
        :if={@show_resend}
        phx-click={@resend_event}
        title="Your detailed report is emailed to you automatically. Click to resend."
        class="inline-flex items-center justify-center gap-2 bg-white border border-gray-200 text-gray-700 text-sm font-medium px-4 py-2.5 rounded-lg hover:bg-gray-50 transition"
      >
        <.icon name="hero-envelope" class="w-4 h-4" />
        Email me the report
      </button>

      <button
        :if={@show_restart}
        phx-click={@restart_event}
        class="inline-flex items-center justify-center gap-2 bg-white border border-gray-200 text-gray-700 text-sm font-medium px-4 py-2.5 rounded-lg hover:bg-gray-50 transition"
      >
        <.icon name="hero-arrow-path" class="w-4 h-4" />
        {@restart_label}
      </button>

      <button
        phx-click={@dashboard_event}
        class="inline-flex items-center justify-center gap-2 text-white text-sm font-semibold px-5 py-2.5 rounded-lg transition"
        style="background-color: #FF8B00;"
      >
        <.icon name="hero-home" class="w-4 h-4" />
        Go to Dashboard
      </button>
    </div>
    """
  end
end
