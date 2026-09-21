defmodule VyaasaCampusWeb.Student.ProfileCompletion.SkillsSection do
  @moduledoc """
  Skills section component for profile completion.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  def render_skills_section(assigns) do
    ~H"""
    <div class="mb-8">
      <h3 class="text-lg font-medium text-orange-600 mb-4 flex items-center">
        <.icon name="hero-light-bulb" class="w-5 h-5 mr-2" />
        Skills & Certifications
      </h3>

      <!-- Skills Section -->
      <div class="mb-6">
        <label class="block text-sm font-medium text-gray-700 mb-3">Skills Extracted from Resume</label>

        <%= if @assigns.ats_data && @assigns.selected_skills != [] do %>
          <!-- Show populated skills from ATS data -->
          <div class="bg-green-50 border border-green-200 rounded-lg p-4 mb-4">
            <div class="flex items-center mb-3">
              <.icon name="hero-sparkles" class="w-5 h-5 text-green-600 mr-2" />
              <span class="text-sm font-medium text-green-900">Skills extracted from your resume:</span>
            </div>
            <div class="flex flex-wrap gap-2">
              <%= for skill <- @assigns.selected_skills do %>
                <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-green-100 text-green-800 border border-green-300">
                  <.icon name="hero-check" class="w-3 h-3 mr-1" />
                  <%= skill %>
                </span>
              <% end %>
            </div>
          </div>
        <% else %>
          <!-- No skills data available -->
          <div class="bg-gray-50 border border-gray-200 rounded-lg p-4 text-center">
            <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-gray-400 mx-auto mb-2" />
            <p class="text-sm text-gray-600">No skills were extracted from your resume.</p>
          </div>
        <% end %>
      </div>

      <!-- Certification Upload -->
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-2">Certification (Optional)</label>
        <div class="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center hover:border-gray-400 transition-colors">
          <.icon name="hero-cloud-arrow-up" class="w-8 h-8 text-gray-400 mx-auto mb-2" />
          <button class="text-blue-600 hover:text-blue-700 font-medium">
            Upload
          </button>
          <p class="text-xs text-gray-500 mt-1">No file chosen</p>
          <p class="text-xs text-gray-400 mt-1">Max size 5MB</p>
        </div>
      </div>
    </div>
    """
  end
end
