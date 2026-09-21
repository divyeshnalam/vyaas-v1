defmodule VyaasaCampusWeb.Auth.LoginLive do
  @moduledoc """
  LiveView for unified login page supporting both tenant users and students.

  This module handles:
  - Tenant identification from URL parameter
  - User authentication for both tenant users and students
  - Form validation and error handling
  - Redirect to appropriate dashboard after login based on user type
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Tenants

  # Import UI components
  import VyaasaCampusWeb.Components.UI
  import Phoenix.LiveView

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    # Get tenant information (case-insensitive lookup)
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))

    socket =
      socket
      |> assign(:tenant_alias, tenant_alias)
      |> assign(:tenant, tenant)
      |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: tenant_alias))
      |> assign(:current_scope, :tenant_login)
      |> assign(:page_title, "Login - #{if(tenant, do: tenant.full_name, else: tenant_alias)}")
      |> assign(:form, to_form(%{}, as: :login))
      |> assign(:loading?, false)
      |> assign(:error_message, nil)
      |> assign(:tenant_not_found?, is_nil(tenant))

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"login" => params}, socket) do
    # Update form with current params for validation
    form = to_form(params, as: :login)
    socket = assign(socket, :form, form)

    {:noreply, socket}
  end

  @impl true
  def handle_event("login", %{"login" => params}, socket) do
    socket = assign(socket, :loading?, true)

    # Prepare login request
    login_data = %{
      email: params["email"],
      password: params["password"]
    }

    # Try tenant user login first, then student login
    case make_tenant_user_login_request(login_data, String.upcase(socket.assigns.tenant_alias)) do
      {:ok, response} ->
        # Tenant user login successful
        token = response["token"]
        user_type = response["user_type"] || "tenant_user"
        has_temp_password = get_in(response, ["user", "has_temp_password"]) || false

        socket =
          socket
          |> put_flash(:info, "Welcome back!")
          |> assign(:loading?, false)

        tenant_alias = socket.assigns.tenant_alias

        require Logger
        Logger.info("LoginLive: Tenant user login successful for #{params["email"]}")

        # Redirect to tenant user dashboard
        session_url =
          "/auth/set-session/#{tenant_alias}?auth_token=#{token}&user_type=#{user_type}&has_temp_password=#{has_temp_password}"

        {:noreply,
         socket
         |> push_event("store_token", %{token: token})
         |> redirect(to: session_url)}

      {:error, _reason} ->
        # Try student login
        case make_student_login_request(login_data, String.upcase(socket.assigns.tenant_alias)) do
          {:ok, response} ->
            # Student login successful
            token = response["token"]
            user_type = response["user_type"] || "student"
            has_temp_password = get_in(response, ["user", "has_temp_password"]) || false

            socket =
              socket
              |> put_flash(:info, "Welcome back!")
              |> assign(:loading?, false)

            tenant_alias = socket.assigns.tenant_alias

            require Logger
            Logger.info("LoginLive: Student login successful for #{params["email"]}")

            # Redirect to student dashboard
            session_url =
              "/auth/set-session/#{tenant_alias}?auth_token=#{token}&user_type=#{user_type}&has_temp_password=#{has_temp_password}"

            {:noreply,
             socket
             |> push_event("store_token", %{token: token})
             |> redirect(to: session_url)}

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
  def handle_event("forgot_password", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/auth/tenant/#{socket.assigns.tenant_alias}/forgot-password")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="login-container" class="min-h-screen flex items-center justify-center px-4 sm:px-6 lg:px-8" phx-hook="StoreToken">
        <div class="w-full max-w-md mx-auto space-y-10">
          <!-- Login Card -->
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
                Welcome Back!
              </h1>
              <p class="text-sm text-gray-600">
                Sign in to your account at <span class="font-semibold text-orange-500">{@tenant_name}</span>
              </p>
            </div>

            <%= if @tenant_not_found? do %>
              <!-- Tenant Not Found Error -->
              <div class="bg-red-50 border border-red-200 rounded-lg p-6 mb-6">
                <div class="flex">
                  <div class="shrink-0">
                    <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-red-400" />
                  </div>
                  <div class="ml-3">
                    <h3 class="text-sm font-medium text-red-800">Institution Not Found</h3>
                    <p class="mt-1 text-sm text-red-700">
                      The institution "<span class="font-semibold">{@tenant_alias}</span>" could not be found.
                      Please check the URL or contact your administrator.
                    </p>
                  </div>
                </div>
              </div>
            <% else %>
              <!-- Login Form -->
            <.form for={@form} id="login-form" phx-submit="login" phx-change="validate" class="space-y-6">
              <!-- Email Field -->
              <div>
                <.input
                  field={@form[:email]}
                  type="email"
                  label="Email ID"
                  placeholder="Enter your email address"
                  required
                  class="w-full px-4 py-3 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500 focus:text-black"
                />
              </div>

              <!-- Password Field -->
              <div>
                <.input
                  field={@form[:password]}
                  type="password"
                  label="Password"
                  placeholder="Enter your password"
                  required
                  class="w-full px-4 py-3 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500 focus:text-black"
                />
              </div>

              <!-- Forgot Password -->
              <div class="flex items-center justify-end">
                <button
                  type="button"
                  phx-click="forgot_password"
                  class="text-sm text-blue-600 hover:text-blue-500 font-medium"
                >
                  Forgot Password?
                </button>
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

              <!-- Login Button -->
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
                    Signing in...
                  <% else %>
                    Login
                  <% end %>
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

  defp make_tenant_user_login_request(login_data, tenant_alias) do
    # Use Req library for HTTP requests as per project guidelines
    url = "#{get_base_url()}/api/auth/tenant-user/login"

    headers = [
      {"Content-Type", "application/json"},
      {"x-tenant", tenant_alias}
    ]

    case Req.post(url, json: login_data, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, Map.put(body, "user_type", "tenant_user")}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_message =
          case status do
            401 -> "Invalid email or password"
            404 -> "User not found"
            _ -> body["message"] || "Login failed"
          end

        {:error, error_message}

      {:error, _reason} ->
        {:error, "Unable to connect to server. Please try again."}
    end
  end

  defp make_student_login_request(login_data, tenant_alias) do
    # Use Req library for HTTP requests as per project guidelines
    url = "#{get_base_url()}/api/auth/student/login"

    headers = [
      {"Content-Type", "application/json"},
      {"x-tenant", tenant_alias}
    ]

    case Req.post(url, json: login_data, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, Map.put(body, "user_type", "student")}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_message =
          case status do
            401 -> "Invalid email or password"
            404 -> "User not found"
            _ -> body["message"] || "Login failed"
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
