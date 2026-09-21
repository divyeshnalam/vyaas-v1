defmodule VyaasaCampusWeb.Auth.ResetPasswordLive do
  @moduledoc """
  LiveView for unified password reset page supporting both tenant users and students.

  This module handles:
  - Token validation from URL parameters
  - New password form submission
  - Password confirmation validation
  - Terms and conditions acceptance
  - Success confirmation and redirect
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Tenants

  # Import UI components
  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(%{"tenant" => tenant_alias, "token" => token}, _session, socket) do
    # Get tenant information (case-insensitive lookup)
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))

    socket =
      socket
      |> assign(:tenant_alias, tenant_alias)
      |> assign(:tenant, tenant)
      |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: tenant_alias))
      |> assign(:token, token)
      |> assign(:current_scope, :reset_password)
      |> assign(:page_title, "Reset Password - #{if(tenant, do: tenant.full_name, else: tenant_alias)}")
      |> assign(:form, to_form(%{}, as: :reset_password))
      |> assign(:loading?, false)
      |> assign(:error_message, nil)
      |> assign(:success_message, nil)
      |> assign(:password_reset?, false)
      |> assign(:terms_accepted?, false)
      |> assign(:user_email, nil)

    # Validate token and get user email
    {:ok, socket} = validate_token_and_get_email(socket)

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"reset_password" => params}, socket) do
    # Update form with current params for validation
    form = to_form(params, as: :reset_password)

    # Check password confirmation
    password = params["password"]
    confirm_password = params["confirm_password"]
    password_match? = password == confirm_password and password != ""

    socket =
      socket
      |> assign(:form, form)
      |> assign(:password_match?, password_match?)

    {:noreply, socket}
  end

  @impl true
  def handle_event("reset_password", %{"reset_password" => params}, socket) do
    socket = assign(socket, :loading?, true)

    cond do
      params["password"] != params["confirm_password"] ->
        socket =
          socket
          |> assign(:error_message, "Passwords do not match")
          |> assign(:loading?, false)

        {:noreply, socket}

      not socket.assigns.terms_accepted? ->
        socket =
          socket
          |> assign(:error_message, "Please accept the Terms and Conditions to continue")
          |> assign(:loading?, false)

        {:noreply, socket}

      true ->
        # Prepare password reset request
        reset_data = %{
          password: params["password"],
          token: socket.assigns.token
        }

        # Make API request to backend
        case make_reset_request(reset_data, socket.assigns.tenant_alias) do
          {:ok, _response} ->
            socket =
              socket
              |> assign(:password_reset?, true)
              |> assign(:success_message, "Password updated successfully!")
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
  end

  @impl true
  def handle_event("toggle_terms", _params, socket) do
    socket = assign(socket, :terms_accepted?, !socket.assigns.terms_accepted?)
    {:noreply, socket}
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
          <!-- Reset Password Card -->
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
                Create New Password
              </h1>
              <%= if @user_email do %>
                <p class="text-sm text-gray-600">
                  We received a request to reset the password for <span class="font-semibold">{@user_email}</span>.
                </p>
              <% end %>
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
                    Your password has been successfully updated. You can now log in with your new password.
                  </p>
                </div>

                <button
                  phx-click="back_to_login"
                  class="w-full flex justify-center py-3 px-4 border border-transparent rounded-lg text-sm font-medium text-white bg-orange-500 hover:bg-orange-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500"
                >
                  Continue to Login
                </button>
              </div>
            <% else %>
              <!-- Reset Password Form -->
              <.form for={@form} id="reset-password-form" phx-submit="reset_password" phx-change="validate" class="space-y-6">
                <!-- New Password Field -->
                <div>
                  <.input
                    field={@form[:password]}
                    type="password"
                    label="New Password"
                    placeholder="Enter new password"
                    required
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-orange-500 text-black"
                  />
                </div>

                <!-- Confirm Password Field -->
                <div>
                  <.input
                    field={@form[:confirm_password]}
                    type="password"
                    label="Confirm Password"
                    placeholder="Re-Enter your Password"
                    required
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-orange-500 text-black"
                  />
                </div>

                <!-- Password Match Validation -->
                <%= if assigns[:password_match?] == false and assigns[:form][:confirm_password].value != "" do %>
                  <div class="bg-red-50 border border-red-200 rounded-lg p-3">
                    <div class="flex">
                      <div class="shrink-0">
                        <.icon name="hero-exclamation-circle" class="h-5 w-5 text-red-400" />
                      </div>
                      <div class="ml-3">
                        <p class="text-sm text-red-800">Passwords do not match</p>
                      </div>
                    </div>
                  </div>
                <% end %>

                <!-- Terms and Conditions -->
                <div class="flex items-start">
                  <div class="flex items-center h-5">
                    <input
                      type="checkbox"
                      checked={@terms_accepted?}
                      phx-click="toggle_terms"
                      class="rounded border-gray-300 text-orange-500 focus:ring-orange-500"
                    />
                  </div>
                  <div class="ml-3 text-sm">
                    <label class="text-gray-600">
                      I accept the
                      <a href="#" class="text-orange-500 underline hover:text-orange-600">Terms</a>
                      and
                      <a href="#" class="text-orange-500 underline hover:text-orange-600">Conditions</a>.
                    </label>
                  </div>
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
                    disabled={@loading? or !@terms_accepted?}
                    class={[
                      "w-full flex justify-center py-3 px-4 border border-transparent rounded-lg text-sm font-medium text-white",
                      "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500",
                      "disabled:opacity-50 disabled:cursor-not-allowed",
                      if(@loading?, do: "bg-orange-400", else: "bg-orange-500 hover:bg-orange-600")
                    ]}
                  >
                    <%= if @loading? do %>
                      <.icon name="hero-arrow-path" class="animate-spin h-5 w-5 mr-2" />
                      Updating Password...
                    <% else %>
                      Update Password
                    <% end %>
                  </button>
                </div>
              </.form>
            <% end %>
          </div>

          <!-- Footer -->
          <div class="text-center mt-4">
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

  defp validate_token_and_get_email(socket) do
    # For now, we'll assume the token is valid and extract email from token
    # In a real implementation, you might want to validate the token with the backend
    # and get the associated email address

    # Extract email from token (this is a simplified approach)
    # In practice, you'd decode the JWT token or make an API call to validate it
    case decode_token_email(socket.assigns.token) do
      {:ok, email} ->
        socket = assign(socket, :user_email, email)
        {:ok, socket}

      {:error, _reason} ->
        socket =
          socket
          |> assign(:user_email, nil)

        {:ok, socket}
    end
  end

  defp decode_token_email(token) do
    # This is a simplified token validation
    # In practice, you'd decode the JWT token or validate it with the backend
    # For demo purposes, we'll extract email from a base64 encoded token
    # In real implementation, use JWT decoding
    decoded = Base.decode64!(token)
    email = String.split(decoded, "|") |> List.last()
    {:ok, email}
  rescue
    _ -> {:error, :invalid_token}
  end

  defp make_reset_request(reset_data, tenant_alias) do
    # Use Req library for HTTP requests as per project guidelines
    url = "#{get_base_url()}/api/auth/password-reset/reset"

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
            400 -> "Invalid or expired reset token"
            422 -> "Password does not meet requirements"
            _ -> body["message"] || "Failed to reset password"
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
