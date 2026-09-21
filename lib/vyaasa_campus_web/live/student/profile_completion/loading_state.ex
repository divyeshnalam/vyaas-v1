defmodule VyaasaCampusWeb.Student.ProfileCompletion.LoadingState do
  @moduledoc """
  Loading state component for Python service processing.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  def render_loading_state(assigns) do
    ~H"""
    <div class="text-center py-16">
      <!-- Orange Loading Spinner -->
      <div class="relative w-20 h-20 mx-auto mb-8">
        <div class="w-20 h-20 border-4 border-orange-200 rounded-full animate-spin">
          <div class="absolute top-0 left-0 w-20 h-20 border-4 border-transparent border-t-orange-500 rounded-full animate-spin"></div>
        </div>
      </div>

      <!-- Loading Messages -->
      <div class="max-w-md mx-auto">
        <h3 class="text-xl font-semibold text-gray-900 mb-4">Processing Your Profile</h3>
        <p class="text-gray-600 mb-6">
          Our AI is analyzing your resume and matching it with your preferred job role.
          This usually takes 30-60 seconds.
        </p>

        <!-- Processing Steps -->
        <div class="text-left bg-orange-50 border border-orange-200 rounded-lg p-4">
          <h4 class="font-medium text-orange-900 mb-3 flex items-center">
            <.icon name="hero-cog-6-tooth" class="w-5 h-5 mr-2 animate-spin" />
            What's happening behind the scenes:
          </h4>
          <ul class="space-y-2 text-sm text-orange-800">
            <li class="flex items-start">
              <.icon name="hero-document-text" class="w-4 h-4 mt-0.5 mr-2 shrink-0" />
              Uploading and parsing your resume
            </li>
            <li class="flex items-start">
              <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5 mr-2 shrink-0" />
              Extracting skills, experience, and qualifications
            </li>
            <li class="flex items-start">
              <.icon name="hero-chart-bar" class="w-4 h-4 mt-0.5 mr-2 shrink-0" />
              Calculating Resume Score for <%= @preferred_job_role || "your role" %>
            </li>
            <li class="flex items-start">
              <.icon name="hero-light-bulb" class="w-4 h-4 mt-0.5 mr-2 shrink-0" />
              Generating personalized improvement suggestions
            </li>
          </ul>
        </div>

        <!-- Progress Indicator -->
        <div class="mt-6">
          <div class="flex items-center justify-center space-x-2 text-sm text-gray-500">
            <span>Please wait...</span>
            <div class="flex space-x-1">
              <div class="w-2 h-2 bg-orange-500 rounded-full animate-bounce"></div>
              <div class="w-2 h-2 bg-orange-500 rounded-full animate-bounce" style="animation-delay: 0.1s"></div>
              <div class="w-2 h-2 bg-orange-500 rounded-full animate-bounce" style="animation-delay: 0.2s"></div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
