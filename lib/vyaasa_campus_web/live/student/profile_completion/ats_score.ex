defmodule VyaasaCampusWeb.Student.ProfileCompletion.AtsScore do
  @moduledoc """
  ATS Score display component for profile completion.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  def render_ats_score_section(assigns) do
    ~H"""
    <div>
      <!-- Step Header -->
      <div class="mb-8">
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-2xl font-bold text-gray-900">Step 3: Resume Score</h2>
            <p class="text-gray-600 mt-1">AI Powered Resume Parser & Scorer to improve the Resume</p>
          </div>
          <div class="text-right">
            <div class="text-sm text-gray-500">Completion: <%= @assigns.completion_percentage %>%</div>
          </div>
        </div>

        <!-- Progress Bar -->
        <div class="w-full bg-gray-200 rounded-full h-2 mt-4">
          <div class="bg-orange-600 h-2 rounded-full transition-all duration-300" style={"width: #{@assigns.completion_percentage}%"}></div>
        </div>
      </div>

      <%= if @assigns.ats_data do %>
        <!-- ATS Score Display -->
        <div class="text-center mb-8">
          <!-- Score Circle -->
          <div class="relative inline-block">
            <svg class="w-40 h-40 transform -rotate-90" viewBox="0 0 100 100">
              <!-- Background circle -->
              <circle
                cx="50"
                cy="50"
                r="40"
                stroke="#e5e7eb"
                stroke-width="8"
                fill="none"
              />
              <!-- Score circle -->
              <circle
                cx="50"
                cy="50"
                r="40"
                stroke={score_color(@assigns.ats_score)}
                stroke-width="8"
                fill="none"
                stroke-linecap="round"
                stroke-dasharray={circumference()}
                stroke-dashoffset={score_offset(@assigns.ats_score)}
                class="transition-all duration-1000 ease-out"
              />
            </svg>
            <div class="absolute inset-0 flex items-center justify-center">
              <div class="text-center">
                <div class={"text-2xl font-bold #{score_text_color(@assigns.ats_score)}"}><%= score_label(@assigns.ats_score) %></div>
                <div class="text-4xl font-bold text-gray-900"><%= @assigns.ats_score %>/100</div>
              </div>
            </div>
          </div>
        </div>

        <!-- Improvement Areas -->
        <%= if @assigns.ats_feedback && @assigns.ats_feedback != [] do %>
          <div class="mb-8">
            <div class="flex items-center justify-center mb-4">
              <.icon name="hero-light-bulb" class="w-5 h-5 text-orange-500 mr-2" />
              <h3 class="text-lg font-medium text-gray-900">Areas for Improvement to Maximize Your Score</h3>
            </div>

            <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
              <ul class="space-y-2 text-sm text-gray-700">
                <%= for {feedback, index} <- Enum.with_index(@assigns.ats_feedback) do %>
                  <li class="flex items-start">
                    <span class="font-medium text-yellow-700 mr-2"><%= index + 1 %>.</span>
                    <%= feedback %>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        <% else %>
          <div class="mb-8">
            <div class="bg-green-50 border border-green-200 rounded-lg p-4 text-center">
              <.icon name="hero-check-circle" class="w-8 h-8 text-green-600 mx-auto mb-2" />
              <h3 class="text-lg font-medium text-green-900">Excellent Resume!</h3>
              <p class="text-sm text-green-700">Your resume meets all the criteria for a high Resume Score.</p>
            </div>
          </div>
        <% end %>
      <% else %>
        <!-- No ATS Data Available -->
        <div class="text-center mb-8 py-12">
          <div class="w-20 h-20 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-document-magnifying-glass" class="w-10 h-10 text-gray-400" />
          </div>
          <h3 class="text-xl font-semibold text-gray-900 mb-2">Resume Analysis Pending</h3>
          <p class="text-gray-600 mb-4">
            Your resume is being processed by our AI system. This usually takes a few minutes.
          </p>
          <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 text-left max-w-md mx-auto">
            <h4 class="font-medium text-blue-900 mb-2">What happens next?</h4>
            <ul class="text-sm text-blue-800 space-y-1">
              <li class="flex items-start">
                <.icon name="hero-cog-6-tooth" class="w-4 h-4 mt-0.5 mr-2 shrink-0" />
                AI analysis extracts key information from your resume
              </li>
              <li class="flex items-start">
                <.icon name="hero-chart-bar" class="w-4 h-4 mt-0.5 mr-2 shrink-0" />
                Resume Score calculated based on industry standards
              </li>
              <li class="flex items-start">
                <.icon name="hero-light-bulb" class="w-4 h-4 mt-0.5 mr-2 shrink-0" />
                Personalized improvement suggestions provided
              </li>
            </ul>
          </div>
        </div>
      <% end %>

      <!-- Navigation -->
      <div class="flex justify-between pt-6 border-t border-gray-200">
        <button
          phx-click="prev_step"
          class="px-6 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors flex items-center"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4 mr-2" />
          Back
        </button>
        <button
          phx-click="next_step"
          class="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
        >
          Next - Step 4
          <.icon name="hero-arrow-right" class="w-4 h-4 ml-2" />
        </button>
      </div>
    </div>
    """
  end

  defp circumference, do: 2 * :math.pi() * 40

  defp score_offset(score) do
    circumference() * (1 - score / 100)
  end

  defp score_color(score) when score >= 80, do: "#22c55e"  # green-500
  defp score_color(score) when score >= 60, do: "#f59e0b"  # amber-500
  defp score_color(_score), do: "#ef4444"                   # red-500

  defp score_text_color(score) when score >= 80, do: "text-green-600"
  defp score_text_color(score) when score >= 60, do: "text-amber-600"
  defp score_text_color(_score), do: "text-red-600"

  defp score_label(score) when score >= 90, do: "Excellent"
  defp score_label(score) when score >= 80, do: "Good"
  defp score_label(score) when score >= 70, do: "Average"
  defp score_label(score) when score >= 60, do: "Below Average"
  defp score_label(_score), do: "Needs Improvement"
end
