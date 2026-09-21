defmodule VyaasaCampusWeb.Admin.LoginLive do
  @moduledoc """
  LiveView for super admin (platform admin) login.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Auth
  alias VyaasaCampus.Guardian

  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(_params, session, socket) do
    # If already logged in as admin, redirect to dashboard
    token = session["auth_token"] || session[:auth_token]

    socket =
      if token do
        case Guardian.current_user(token) do
          {:ok, user} ->
            if Guardian.admin?(user) do
              push_navigate(socket, to: ~p"/admin/dashboard")
            else
              init_socket(socket)
            end

          _ ->
            init_socket(socket)
        end
      else
        init_socket(socket)
      end

    {:ok, socket}
  end

  defp init_socket(socket) do
    socket
    |> assign(:page_title, "Super Admin Login")
    |> assign(:form, to_form(%{}, as: :login))
    |> assign(:loading?, false)
    |> assign(:error_message, nil)
  end

  @impl true
  def handle_event("validate", %{"login" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :login))}
  end

  @impl true
  def handle_event("login", %{"login" => %{"email" => email, "password" => password}}, socket) do
    socket = assign(socket, :loading?, true)

    case Auth.authenticate_admin(email, password) do
      {:ok, admin_user} ->
        case Guardian.create_token(admin_user, %{user_type: "admin"}) do
          {:ok, token, _claims} ->
            session_url = "/auth/admin/set-session?auth_token=#{token}"

            {:noreply,
             socket
             |> assign(:loading?, false)
             |> redirect(to: session_url)}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:loading?, false)
             |> assign(:error_message, "Failed to create session. Please try again.")}
        end

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:loading?, false)
         |> assign(:error_message, "No admin account found with that email.")}

      {:error, :invalid_password} ->
        {:noreply,
         socket
         |> assign(:loading?, false)
         |> assign(:error_message, "Invalid email or password.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:loading?, false)
         |> assign(:error_message, "Login failed. Please try again.")}
    end
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
                  <.icon name="hero-shield-check" class="h-8 w-8 text-white" />
                </div>
              </div>
              <h1 class="text-2xl font-bold text-gray-900 mb-1">
                Super Admin
              </h1>
              <p class="text-sm text-gray-500">
                VyaasaCampus Platform Administration
              </p>
            </div>

            <!-- Login Form -->
            <.form for={@form} id="admin-login-form" phx-submit="login" phx-change="validate" class="space-y-5">
              <div>
                <.input
                  field={@form[:email]}
                  type="email"
                  label="Email"
                  placeholder="admin@vyaasa.com"
                  required
                  class="w-full px-4 py-3 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                />
              </div>

              <div>
                <.input
                  field={@form[:password]}
                  type="password"
                  label="Password"
                  placeholder="Enter your password"
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
                  Signing in...
                <% else %>
                  Sign In
                <% end %>
              </button>
            </.form>

            <div class="text-center mt-4">
              <.link navigate={~p"/admin/forgot-password"} class="text-sm text-orange-500 hover:text-orange-600 font-medium">
                Forgot Password?
              </.link>
            </div>
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
