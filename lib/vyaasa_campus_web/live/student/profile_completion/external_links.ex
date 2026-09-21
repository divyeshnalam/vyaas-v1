defmodule VyaasaCampusWeb.Student.ProfileCompletion.ExternalLinks do
  @moduledoc """
  External links section component for profile completion.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  def render_external_links_section(assigns) do
    ~H"""
    <div class="mb-8">
      <h3 class="text-lg font-medium text-orange-600 mb-4 flex items-center">
        <.icon name="hero-link" class="w-5 h-5 mr-2" />
        External Links
      </h3>

      <%= if @assigns.ats_data && (@assigns.external_links[:linkedin] != "" || @assigns.external_links[:github] != "" || @assigns.external_links[:portfolio] != "") do %>
        <!-- Show populated external links from ATS data -->
        <div class="space-y-4">
          <%= if @assigns.external_links[:linkedin] != "" do %>
            <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div class="flex items-center">
                  <.icon name="hero-globe-alt" class="w-5 h-5 text-blue-600 mr-2" />
                  <span class="text-sm font-medium text-blue-900">LinkedIn Profile:</span>
                </div>
                <a href={@assigns.external_links[:linkedin]} target="_blank" class="text-sm text-blue-700 hover:text-blue-800 underline">
                  <%= @assigns.external_links[:linkedin] %>
                </a>
              </div>
            </div>
          <% end %>

          <%= if @assigns.external_links[:github] != "" do %>
            <div class="bg-gray-50 border border-gray-200 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div class="flex items-center">
                  <.icon name="hero-code-bracket" class="w-5 h-5 text-gray-600 mr-2" />
                  <span class="text-sm font-medium text-gray-900">GitHub Profile:</span>
                </div>
                <a href={@assigns.external_links[:github]} target="_blank" class="text-sm text-gray-700 hover:text-gray-800 underline">
                  <%= @assigns.external_links[:github] %>
                </a>
              </div>
            </div>
          <% end %>

          <%= if @assigns.external_links[:portfolio] != "" do %>
            <div class="bg-purple-50 border border-purple-200 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div class="flex items-center">
                  <.icon name="hero-briefcase" class="w-5 h-5 text-purple-600 mr-2" />
                  <span class="text-sm font-medium text-purple-900">Portfolio Website:</span>
                </div>
                <a href={@assigns.external_links[:portfolio]} target="_blank" class="text-sm text-purple-700 hover:text-purple-800 underline">
                  <%= @assigns.external_links[:portfolio] %>
                </a>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <!-- No external links found -->
        <div class="bg-gray-50 border border-gray-200 rounded-lg p-4 text-center">
          <.icon name="hero-link-slash" class="w-8 h-8 text-gray-400 mx-auto mb-2" />
          <p class="text-sm text-gray-600">No external links were found in your resume.</p>
          <p class="text-xs text-gray-500 mt-1">LinkedIn, GitHub, and portfolio links are automatically extracted when available.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
