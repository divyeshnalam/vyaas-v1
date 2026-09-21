defmodule VyaasaCampusWeb.Admin.ForgotPasswordLive do
  @moduledoc """
  LiveView for admin forgot password page.
  Calls PasswordResetService directly (no HTTP self-call).
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Auth.PasswordResetService

  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Forgot Password - Super Admin")
      |> assign(:form, to_form(%{}, as: :forgot_password))
      |> assign(:loading?, false)
      |> assign(:error_message, nil)
      |> assign(:email_sent?, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"forgot_password" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :forgot_password))}
  end

  @impl true
  def handle_event("request_reset", %{"forgot_password" => %{"email" => email}}, socket) do
    socket = assign(socket, :loading?, true)

    case PasswordResetService.request_password_reset(email, nil, "public") do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:email_sent?, true)
         |> assign(:loading?, false)
         |> assign(:error_message, nil)}

      {:error, :user_not_found} ->
        {:noreply,
         socket
         |> assign(:loading?, false)
         |> assign(:error_message, "No admin account found with that email.")}

      {:error, :email_send_failed} ->
        {:noreply,
         socket
         |> assign(:loading?, false)
         |> assign(:error_message, "Failed to send reset email. Please try again.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:loading?, false)
         |> assign(:error_message, "Something went wrong. Please try again.")}
    end
  end

  @impl true
  def handle_event("back_to_login", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 px-4 sm:px-6 lg:px-8">
        <div class="w-full max-w-md mx-auto space-y-10">
          <div class="bg-white rounded-xl shadow-2xl border border-slate-200 p-8">
            <!-- Header -->
            <div class="text-center mb-8">
              <div class="flex items-center justify-center mb-4">
                <div class="w-16 h-16 bg-gradient-to-br from-orange-500 to-orange-600 rounded-full flex items-center justify-center shadow-lg">
                  <.icon name="hero-envelope" class="h-8 w-8 text-white" />
                </div>
              </div>
              <h1 class="text-2xl font-bold text-gray-900 mb-1">Forgot Password?</h1>
              <p class="text-sm text-gray-500">
                Enter your admin email and we'll send you a reset link.
              </p>
            </div>

            <%= if @email_sent? do %>
              <!-- Success State -->
              <div class="text-center space-y-6">
                <div class="bg-green-50 border border-green-200 rounded-lg p-6">
                  <div class="flex justify-center mb-4">
                    <.icon name="hero-check-circle" class="h-12 w-12 text-green-500" />
                  </div>
                  <h3 class="text-lg font-semibold text-green-800 mb-2">Email Sent!</h3>
                  <p class="text-sm text-green-700">
                    We've sent a password reset link to your email. Please check your inbox.
                  </p>
                </div>

                <button
                  phx-click="back_to_login"
                  class="w-full flex justify-center py-3 px-4 border border-transparent rounded-lg text-sm font-medium text-white bg-orange-500 hover:bg-orange-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500"
                >
                  Back to Login
                </button>

                <p class="text-sm text-gray-500">
                  Didn't receive the email? Check your spam folder or try again.
                </p>
              </div>
            <% else %>
              <!-- Forgot Password Form -->
              <.form for={@form} id="admin-forgot-password-form" phx-submit="request_reset" phx-change="validate" class="space-y-5">
                <div>
                  <.input
                    field={@form[:email]}
                    type="email"
                    label="Email Address"
                    placeholder="admin@vyaasa.com"
                    required
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                  />
                </div>

                <%= if @error_message do %>
                  <div class="bg-red-50 border border-red-200 rounded-lg p-4">
                    <div class="flex">
                      <.icon name="hero-exclamation-circle" class="h-5 w-5 text-red-400 shrink-0" />
                      <p class="ml-3 text-sm text-red-800">{@error_message}</p>
                    </div>
                  </div>
                <% end %>

                <button
                  type="submit"
                  disabled={@loading?}
                  class={[
                    "w-full flex justify-center py-3 px-4 border border-transparent rounded-lg text-sm font-semibold text-white",
                    "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500",
                    "disabled:opacity-50 disabled:cursor-not-allowed transition-colors",
                    if(@loading?, do: "bg-orange-400", else: "bg-orange-500 hover:bg-orange-600")
                  ]}
                >
                  <%= if @loading? do %>
                    <.icon name="hero-arrow-path" class="animate-spin h-5 w-5 mr-2" />
                    Sending...
                  <% else %>
                    Send Reset Link
                  <% end %>
                </button>

                <div class="text-center">
                  <button
                    type="button"
                    phx-click="back_to_login"
                    class="text-sm text-orange-500 hover:text-orange-600 font-medium"
                  >
                    Back to Login
                  </button>
                </div>
              </.form>
            <% end %>
          </div>

          <div class="text-center">
            <p class="text-sm text-slate-400">
              Copyright &copy; {Date.utc_today().year} BeamX. All Rights Reserved.
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
