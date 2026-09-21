defmodule VyaasaCampusWeb.Admin.ResetPasswordLive do
  @moduledoc """
  LiveView for admin password reset via token (from email link).
  URL: /admin/reset-password/:token
  Calls PasswordResetService directly.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Auth.PasswordResetService

  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Reset Password - Super Admin")
      |> assign(:token, token)
      |> assign(:form, to_form(%{}, as: :reset_password))
      |> assign(:loading?, false)
      |> assign(:error_message, nil)
      |> assign(:password_reset?, false)

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/admin/login")}
  end

  @impl true
  def handle_event("validate", %{"reset_password" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :reset_password))}
  end

  @impl true
  def handle_event("reset_password", %{"reset_password" => params}, socket) do
    new_password = params["password"] || ""
    confirm_password = params["confirm_password"] || ""

    cond do
      String.length(new_password) < 6 ->
        {:noreply, assign(socket, :error_message, "Password must be at least 6 characters.")}

      new_password != confirm_password ->
        {:noreply, assign(socket, :error_message, "Passwords do not match.")}

      true ->
        socket = assign(socket, :loading?, true)

        case PasswordResetService.reset_password_with_token(
               socket.assigns.token,
               new_password,
               nil,
               "public"
             ) do
          {:ok, _user} ->
            {:noreply,
             socket
             |> assign(:password_reset?, true)
             |> assign(:loading?, false)
             |> assign(:error_message, nil)}

          {:error, :invalid_token} ->
            {:noreply,
             socket
             |> assign(:loading?, false)
             |> assign(:error_message, "Invalid or expired reset link. Please request a new one.")}

          {:error, :token_expired} ->
            {:noreply,
             socket
             |> assign(:loading?, false)
             |> assign(:error_message, "This reset link has expired. Please request a new one.")}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:loading?, false)
             |> assign(:error_message, "Failed to reset password. Please try again.")}
        end
    end
  end

  @impl true
  def handle_event("go_to_login", _params, socket) do
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
                  <.icon name="hero-lock-closed" class="h-8 w-8 text-white" />
                </div>
              </div>
              <h1 class="text-2xl font-bold text-gray-900 mb-1">Create New Password</h1>
              <p class="text-sm text-gray-500">
                Choose a strong password for your admin account.
              </p>
            </div>

            <%= if @password_reset? do %>
              <!-- Success State -->
              <div class="text-center space-y-6">
                <div class="bg-green-50 border border-green-200 rounded-lg p-6">
                  <div class="flex justify-center mb-4">
                    <.icon name="hero-check-circle" class="h-12 w-12 text-green-500" />
                  </div>
                  <h3 class="text-lg font-semibold text-green-800 mb-2">Password Updated!</h3>
                  <p class="text-sm text-green-700">
                    Your password has been successfully reset. You can now log in.
                  </p>
                </div>

                <button
                  phx-click="go_to_login"
                  class="w-full flex justify-center py-3 px-4 border border-transparent rounded-lg text-sm font-medium text-white bg-orange-500 hover:bg-orange-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500"
                >
                  Continue to Login
                </button>
              </div>
            <% else %>
              <!-- Reset Password Form -->
              <.form for={@form} id="admin-reset-password-form" phx-submit="reset_password" phx-change="validate" class="space-y-5">
                <div>
                  <.input
                    field={@form[:password]}
                    type="password"
                    label="New Password"
                    placeholder="Enter new password (min 6 characters)"
                    required
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                  />
                </div>

                <div>
                  <.input
                    field={@form[:confirm_password]}
                    type="password"
                    label="Confirm Password"
                    placeholder="Re-enter your new password"
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
                    Updating Password...
                  <% else %>
                    Reset Password
                  <% end %>
                </button>

                <div class="text-center">
                  <.link
                    navigate={~p"/admin/login"}
                    class="text-sm text-orange-500 hover:text-orange-600 font-medium"
                  >
                    Back to Login
                  </.link>
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
