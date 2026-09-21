defmodule VyaasaCampusWeb.Auth.ForgotPasswordLive do
  @moduledoc """
  LiveView for unified forgot password page supporting both tenant users and students.

  This module handles:
  - Tenant identification from URL parameter
  - Password reset request submission for both user types
  - Form validation and error handling
  - Success confirmation
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Tenants

  # Import UI components
  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    # Get tenant information (case-insensitive lookup)
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))

    socket =
      socket
      |> assign(:tenant_alias, tenant_alias)
      |> assign(:tenant, tenant)
      |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: tenant_alias))
      |> assign(:current_scope, :tenant_forgot_password)
      |> assign(:page_title, "Forgot Password - #{if(tenant, do: tenant.full_name, else: tenant_alias)}")
      |> assign(:form, to_form(%{}, as: :forgot_password))
      |> assign(:loading?, false)
      |> assign(:error_message, nil)
      |> assign(:success_message, nil)
      |> assign(:email_sent?, false)

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"forgot_password" => params}, socket) do
    # Update form with current params for validation
    form = to_form(params, as: :forgot_password)
    socket = assign(socket, :form, form)

    {:noreply, socket}
  end

  @impl true
  def handle_event("request_reset", %{"forgot_password" => params}, socket) do
    socket = assign(socket, :loading?, true)

    # Prepare password reset request
    reset_data = %{
      email: params["email"]
    }

    # Make API request to backend
    case make_reset_request(reset_data, String.upcase(socket.assigns.tenant_alias)) do
      {:ok, _response} ->
        socket =
          socket
          |> assign(:email_sent?, true)
          |> assign(:success_message, "Password reset email sent successfully!")
          |> assign(:loading?, false)
          |> assign(:error_message, nil)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:error_message, reason)
          |> assign(:loading?, false)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("back_to_login", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/auth/tenant/#{socket.assigns.tenant_alias}/login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
    <div class="min-h-screen flex items-center justify-center px-4 sm:px-6 lg:px-8">
    <div class="w-full max-w-md mx-auto space-y-8">
          <!-- Forgot Password Card -->
            <div class="bg-white rounded-lg shadow-lg border border-orange-200 p-8">
            <!-- Header -->
            <div class="text-center mb-8">
              <div class="flex items-center justify-center mb-4">
                <div class="flex items-center space-x-4">
                  <!-- Vyaasa Logo -->
                  <div class="w-12 h-12 bg-orange-500 rounded-full flex items-center justify-center">
                    <span class="text-white font-bold text-xl">V</span>
                  </div>
                  <!-- Infinity Symbol -->
                  <div class="text-orange-500 text-2xl">∞</div>
                  <!-- Tenant Logo -->
                  <div class="w-12 h-12 bg-purple-500 rounded-full flex items-center justify-center">
                    <span class="text-white font-bold text-xl">C</span>
                  </div>
                </div>
              </div>

              <h1 class="text-2xl font-bold text-gray-900 mb-2">
                Forgot Password?
              </h1>
              <p class="text-sm text-gray-600">
                Enter your email address and we'll send you a link to reset your password.
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
                    We've sent a password reset link to your email address. Please check your inbox and follow the instructions to reset your password.
                  </p>
                </div>

                <div class="space-y-4">
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
              </div>
            <% else %>
              <!-- Forgot Password Form -->
              <.form for={@form} id="forgot-password-form" phx-submit="request_reset" phx-change="validate" class="space-y-6">
                <!-- Email Field -->
                <div>
                  <.input
                    field={@form[:email]}
                    type="email"
                    label="Email Address"
                    placeholder="Enter your email address"
                    required
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-orange-500 text-black"
                  />
                </div>

                <!-- Error Message -->
                <%= if @error_message do %>
                  <div class="bg-red-50 border border-red-200 rounded-lg p-4">
                    <div class="flex">
                      <div class="shrink-0">
                        <.icon name="hero-exclamation-circle" class="h-5 w-5 text-red-400" />
                      </div>
                      <div class="ml-3">
                        <p class="text-sm text-red-800">{@error_message}</p>
                      </div>
                    </div>
                  </div>
                <% end %>

                <!-- Submit Button -->
                <div>
                  <button
                    type="submit"
                    disabled={@loading?}
                    class={[
                      "w-full flex justify-center py-3 px-4 border border-transparent rounded-lg text-sm font-medium text-white",
                      "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500",
                      "disabled:opacity-50 disabled:cursor-not-allowed",
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
                </div>

                <!-- Back to Login -->
                <div class="text-center">
                  <button
                    type="button"
                    phx-click="back_to_login"
                    class="text-sm text-blue-600 hover:text-blue-500 font-medium"
                  >
                    ← Back to Login
                  </button>
                </div>
              </.form>
            <% end %>
          </div>

          <!-- Footer -->
          <div class="text-center">
            <p class="text-sm text-gray-500">
              Copyright © {Date.utc_today().year} BeamX. All Rights Reserved. Designed & Developed by Vyaasa.com
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Private functions

  defp make_reset_request(reset_data, tenant_alias) do
    # Use Req library for HTTP requests as per project guidelines
    url = "#{get_base_url()}/api/auth/password-reset/request"

    headers = [
      {"Content-Type", "application/json"},
      {"x-tenant", tenant_alias}
    ]

    case Req.post(url, json: reset_data, headers: headers) do
      {:ok, %Req.Response{status: 200, body: _body}} ->
        {:ok, :success}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_message =
          case status do
            404 -> "No user found with this email address"
            _ -> (is_map(body) && body["message"]) || "Failed to send reset email"
          end

        {:error, error_message}

      {:error, _reason} ->
        {:error, "Unable to connect to server. Please try again."}
    end
  end

  defp get_base_url do
    # Get base URL from application config or environment
    endpoint_config = Application.get_env(:vyaasa_campus, VyaasaCampusWeb.Endpoint)
    host = endpoint_config[:url][:host] || "localhost"
    port = endpoint_config[:url][:port] || 4000
    "http://#{host}:#{port}"
  end
end
