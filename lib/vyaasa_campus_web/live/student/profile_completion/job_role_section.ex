defmodule VyaasaCampusWeb.Student.ProfileCompletion.JobRoleSection do
  @moduledoc """
  Job role selection component for profile completion.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  def render_job_role_section(assigns) do
    ~H"""
    <div class="mb-8">
      <h3 class="text-lg font-medium text-orange-600 mb-4 flex items-center">
        <.icon name="hero-briefcase" class="w-5 h-5 mr-2" />
        Preferred Job Role
      </h3>

      <%= if @assigns.preferred_job_role != "" do %>
        <!-- Show selected job role (read-only in steps 2-4) -->
        <div class="bg-orange-50 border border-orange-200 rounded-lg p-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center">
              <.icon name="hero-check-circle" class="w-5 h-5 text-orange-600 mr-2" />
              <span class="text-sm font-medium text-orange-900">Selected Role:</span>
            </div>
            <span class="text-sm font-bold text-orange-800"><%= @assigns.preferred_job_role %></span>
          </div>
          <p class="text-xs text-orange-700 mt-2">
            <.icon name="hero-user" class="w-3 h-3 mr-1 inline" />
            Selected in step 1
          </p>
        </div>
      <% else %>
        <!-- No job role selected -->
        <div class="bg-gray-50 border border-gray-200 rounded-lg p-4 text-center">
          <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-gray-400 mx-auto mb-2" />
          <p class="text-sm text-gray-600">No job role was selected.</p>
        </div>
      <% end %>
    </div>
    """
  end

end
