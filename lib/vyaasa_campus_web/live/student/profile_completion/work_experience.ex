defmodule VyaasaCampusWeb.Student.ProfileCompletion.WorkExperience do
  @moduledoc """
  Work experience section component for profile completion.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  def render_work_experience_section(assigns) do
    ~H"""
    <div class="mb-8">
      <h3 class="text-lg font-medium text-orange-600 mb-4 flex items-center">
        <.icon name="hero-briefcase" class="w-5 h-5 mr-2" />
        Work Experience
      </h3>

      <%= if @assigns.ats_data && has_work_experience?(@assigns.work_experiences) do %>
        <!-- Show populated work experience from ATS data -->
        <div class="space-y-4">
          <%= for {experience, index} <- Enum.with_index(@assigns.work_experiences) do %>
            <%= if experience.job_title != "" or experience.company_name != "" do %>
              <div class="bg-purple-50 border border-purple-200 rounded-lg p-4">
                <div class="flex items-start justify-between mb-3">
                  <div class="flex items-center">
                    <.icon name="hero-sparkles" class="w-4 h-4 text-purple-600 mr-2" />
                    <span class="text-sm font-medium text-purple-900">Experience <%= index + 1 %></span>
                  </div>
                  <span class="text-xs text-purple-700 bg-purple-100 px-2 py-1 rounded-full">From Resume</span>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-3">
                  <div>
                    <span class="text-xs font-medium text-gray-600">Job Title</span>
                    <p class="text-sm font-semibold text-gray-900"><%= experience.job_title %></p>
                  </div>
                  <div>
                    <span class="text-xs font-medium text-gray-600">Company</span>
                    <p class="text-sm font-semibold text-gray-900"><%= experience.company_name %></p>
                  </div>
                </div>

                <%= if experience.start_date != "" or experience.end_date != "" do %>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-3">
                    <div>
                      <span class="text-xs font-medium text-gray-600">Start Date</span>
                      <p class="text-sm text-gray-900"><%= experience.start_date || "Not specified" %></p>
                    </div>
                    <div>
                      <span class="text-xs font-medium text-gray-600">End Date</span>
                      <p class="text-sm text-gray-900"><%= experience.end_date || "Not specified" %></p>
                    </div>
                  </div>
                <% end %>

                <%= if experience.responsibilities != "" do %>
                  <div>
                    <span class="text-xs font-medium text-gray-600">Responsibilities</span>
                    <p class="text-sm text-gray-700 mt-1"><%= experience.responsibilities %></p>
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <!-- Manual work experience entry -->
        <%= for {experience, _index} <- Enum.with_index(@assigns.work_experiences) do %>
          <div class="border border-gray-200 rounded-lg p-4 mb-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Job Title</label>
                <input
                  type="text"
                  placeholder="Job Title"
                  value={experience.job_title}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Company Name</label>
                <input
                  type="text"
                  placeholder="Company Name"
                  value={experience.company_name}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
                <input
                  type="date"
                  value={experience.start_date}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">End Date</label>
                <input
                  type="date"
                  value={experience.end_date}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Responsibilities</label>
              <textarea
                placeholder="Responsibilities"
                rows="3"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              ><%= experience.responsibilities %></textarea>
            </div>
          </div>
        <% end %>

        <button
          phx-click="add_work_experience"
          class="flex items-center text-blue-600 hover:text-blue-700 text-sm font-medium"
        >
          <.icon name="hero-plus" class="w-4 h-4 mr-1" />
          Add other work experience
        </button>
      <% end %>
    </div>
    """
  end

  defp has_work_experience?(work_experiences) do
    case work_experiences do
      [] -> false
      [first | _] when is_map(first) ->
        Map.get(first, :job_title, "") != ""
      _ -> false
    end
  end
end
