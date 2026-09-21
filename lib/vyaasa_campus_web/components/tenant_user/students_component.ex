defmodule VyaasaCampusWeb.Components.TenantUser.StudentsComponent do
  @moduledoc """
  Students management component for tenant dashboard.
  Displays approved students with search, filters, and actions.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  def students_section(assigns) do
    ~H"""
    <div class="p-6">
      <!-- Section Header -->
      <div class="flex items-center justify-between mb-6">
        <div class="flex items-center">
          <h2 class="text-2xl font-bold text-gray-900">Students</h2>
          <span class="ml-3 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800">
            <%= @total_students %>
          </span>
        </div>
        <div class="flex space-x-3">
          <.link
            patch={"/user/#{@tenant_alias}/dashboard/students?action=new"}
            class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-orange-500 hover:bg-orange-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500"
          >
            <.icon name="hero-plus" class="w-4 h-4 mr-2" />
            Add Student
          </.link>
          <button class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500">
            <.icon name="hero-document-arrow-up" class="w-4 h-4 mr-2" />
            Upload CSV file
          </button>
        </div>
      </div>

      <!-- Search and Filters -->
      <div class="flex items-center space-x-4 mb-6">
        <!-- Search -->
        <div class="flex-1 max-w-md">
          <div class="relative">
            <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <.icon name="hero-magnifying-glass" class="h-5 w-5 text-gray-400" />
            </div>
            <input
              type="text"
              placeholder="Search students..."
              class="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-orange-500 focus:border-orange-500"
              phx-keyup="search_students"
              phx-debounce="300"
            />
          </div>
        </div>

        <!-- Filters -->
        <select class="block w-48 px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-orange-500 focus:border-orange-500">
          <option>Degree / Class</option>
          <option>BTech CSE</option>
          <option>BCA</option>
          <option>MCA</option>
        </select>

        <select class="block w-32 px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-orange-500 focus:border-orange-500">
          <option>Year</option>
          <option>2025</option>
          <option>2024</option>
          <option>2023</option>
        </select>

        <!-- View Toggle -->
        <div class="flex border border-gray-300 rounded-md">
          <button class="px-3 py-2 text-sm font-medium text-gray-700 bg-white border-r border-gray-300 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-orange-500">
            <.icon name="hero-bars-3" class="w-4 h-4" />
          </button>
          <button class="px-3 py-2 text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-orange-500">
            <.icon name="hero-squares-2x2" class="w-4 h-4" />
          </button>
        </div>
      </div>

      <!-- Students Table -->
      <div class="overflow-hidden shadow ring-1 ring-black ring-opacity-5 md:rounded-lg">
        <table class="min-w-full divide-y divide-gray-300">
          <thead class="bg-orange-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                NAME
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                ID
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                PHONE
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                CLASS
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                YEAR
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                CV/RESUME
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                STATUS
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                ACTIONS
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for student <- @students do %>
              <tr class="hover:bg-gray-50">
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <div class="shrink-0 h-10 w-10">
                      <div class="h-10 w-10 rounded-full bg-gray-300 flex items-center justify-center">
                        <span class="text-sm font-medium text-gray-700">
                          <%= String.first(student.first_name || "S") %>
                        </span>
                      </div>
                    </div>
                    <div class="ml-4">
                      <div class="text-sm font-medium text-gray-900">
                        <%= "#{student.first_name} #{student.last_name}" %>
                      </div>
                      <div class="text-sm text-gray-500">
                        <%= student.email %>
                      </div>
                    </div>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <%= student.registration_id || "N/A" %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <%= student.phone || "N/A" %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <%= student.degree || "N/A" %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <%= student.year_of_passing || "N/A" %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <%= if student.resume_url do %>
                    <.link
                      href={student.resume_url}
                      target="_blank"
                      class="text-orange-600 hover:text-orange-500"
                    >
                      <%= student.resume_filename || "Resume.pdf" %>
                    </.link>
                  <% else %>
                    <span class="text-gray-400">No resume</span>
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={[
                    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                    get_status_class(student.status)
                  ]}>
                    <%= get_status_text(student.status) %>
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <div class="flex items-center justify-end space-x-2">
                    <%= if student.status == "unverified" do %>
                      <button
                        phx-click="verify_student"
                        phx-value-student_id={student.id}
                        class="inline-flex items-center px-3 py-1 border border-transparent text-xs leading-4 font-medium rounded text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                      >
                        <.icon name="hero-check" class="w-3 h-3 mr-1" />
                        Verify
                      </button>
                    <% end %>
                    <button class="text-gray-400 hover:text-gray-600">
                      <.icon name="hero-ellipsis-vertical" class="w-5 h-5" />
                    </button>
                  </div>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <.paginator
        current_page={@current_page}
        total={@total_students}
        per_page={@per_page}
        event="goto_students_page"
        label="students"
      />
    </div>
    """
  end

  # Helper functions for status styling
  defp get_status_class("unverified") do
    "bg-yellow-100 text-yellow-800"
  end

  defp get_status_class("verified") do
    "bg-green-100 text-green-800"
  end

  defp get_status_class("active") do
    "bg-blue-100 text-blue-800"
  end

  defp get_status_class("pending") do
    "bg-gray-100 text-gray-800"
  end

  defp get_status_class("profile_incomplete") do
    "bg-red-100 text-red-800"
  end

  defp get_status_class(_) do
    "bg-gray-100 text-gray-800"
  end

  # Helper function for status text
  defp get_status_text("unverified") do
    "Unverified"
  end

  defp get_status_text("verified") do
    "Verified"
  end

  defp get_status_text("active") do
    "Active"
  end

  defp get_status_text("pending") do
    "Pending"
  end

  defp get_status_text("profile_incomplete") do
    "Profile Incomplete"
  end

  defp get_status_text(status) do
    String.capitalize(status || "Unknown")
  end
end
