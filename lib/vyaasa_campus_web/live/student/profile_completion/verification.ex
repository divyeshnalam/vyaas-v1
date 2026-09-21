defmodule VyaasaCampusWeb.Student.ProfileCompletion.Verification do
  @moduledoc """
  Verification step component for profile completion.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  def render_verification_section(assigns) do
    ~H"""
    <div>
      <!-- Success Message -->
      <div class="text-center mb-8">
        <div class="w-20 h-20 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
          <.icon name="hero-check" class="w-10 h-10 text-green-600" />
        </div>
        <h3 class="text-xl font-semibold text-gray-900 mb-2">Profile Submitted Successfully!</h3>
        <p class="text-gray-600">
          Your profile has been submitted for admin review. You will receive an email notification
          once your profile is verified and approved.
        </p>
      </div>

      <!-- Next Steps -->
      <div class="bg-blue-50 border border-blue-200 rounded-lg p-6 mb-8">
        <h4 class="font-medium text-blue-900 mb-3">What happens next?</h4>
        <ul class="space-y-2 text-sm text-blue-800">
          <li class="flex items-start">
            <.icon name="hero-clock" class="w-4 h-4 mt-0.5 mr-2 shrink-0" />
            Your profile will be reviewed by our admin team within 24-48 hours
          </li>
          <li class="flex items-start">
            <.icon name="hero-envelope" class="w-4 h-4 mt-0.5 mr-2 shrink-0" />
            You'll receive an email notification with your login credentials once approved
          </li>
          <li class="flex items-start">
            <.icon name="hero-user-circle" class="w-4 h-4 mt-0.5 mr-2 shrink-0" />
            You can then access your student dashboard and start using the platform
          </li>
        </ul>
      </div>

    </div>
    """
  end
end
