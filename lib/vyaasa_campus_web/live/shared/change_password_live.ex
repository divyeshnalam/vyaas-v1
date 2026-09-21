defmodule VyaasaCampusWeb.Shared.ChangePasswordLive do
  @moduledoc """
  Shared LiveView for changing password. Works for all user types:
  - Admin (/admin/change-password)
  - Tenant User (/user/:tenant/change-password)
  - Student (/student/:tenant/change-password)
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Auth.PasswordResetService
  alias VyaasaCampus.Contexts.Accounts
  alias VyaasaCampus.Contexts.Students
  alias VyaasaCampus.Contexts.Tenants

  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(params, session, socket) do
    user = socket.assigns.current_user
    user_type = socket.assigns[:user_type] || detect_user_type(user)
    tenant_alias = params["tenant"]
    first_login? = params["first_login"] == "true"
    auth_token = session["auth_token"] || session[:auth_token]

    schema_prefix =
      case user_type do
        "admin" ->
          "public"

        _ ->
          if tenant_alias do
            tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
            if tenant, do: tenant.schema_name, else: "public"
          else
            "public"
          end
      end

    back_path =
      case user_type do
        "admin" -> ~p"/admin/dashboard"
        "user" -> ~p"/user/#{tenant_alias}/dashboard"
        "student" -> ~p"/student/#{tenant_alias}/dashboard"
        _ -> ~p"/"
      end

    socket =
      socket
      |> assign(:page_title, if(first_login?, do: "Set Your Password", else: "Change Password"))
      |> assign(:user_type, user_type)
      |> assign(:tenant_alias, tenant_alias)
      |> assign(:schema_prefix, schema_prefix)
      |> assign(:back_path, back_path)
      |> assign(:first_login?, first_login?)
      |> assign(:auth_token, auth_token)
      |> assign(:form, to_form(%{}, as: :change_password))
      |> assign(:loading?, false)
      |> assign(:error_message, nil)
      |> assign(:success?, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"change_password" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :change_password))}
  end

  @impl true
  def handle_event("change_password", %{"change_password" => params}, socket) do
    current_password = params["current_password"] || ""
    new_password = params["new_password"] || ""
    confirm_password = params["confirm_password"] || ""

    cond do
      String.length(new_password) < 6 ->
        {:noreply, assign(socket, :error_message, "New password must be at least 6 characters.")}

      new_password != confirm_password ->
        {:noreply, assign(socket, :error_message, "New passwords do not match.")}

      true ->
        socket = assign(socket, :loading?, true)

        case PasswordResetService.change_password(
               socket.assigns.current_user,
               current_password,
               new_password,
               socket.assigns.schema_prefix
             ) do
          {:ok, user} ->
            if socket.assigns.first_login? do
              clear_temp_password(
                user,
                socket.assigns.user_type,
                socket.assigns.schema_prefix,
                socket.assigns.auth_token
              )
            end

            socket =
              socket
              |> assign(:loading?, false)
              |> assign(:success?, true)
              |> assign(:error_message, nil)

            if socket.assigns.first_login? do
              {:noreply,
               socket
               |> put_flash(:info, "Password set successfully. Welcome!")
               |> push_navigate(to: socket.assigns.back_path)}
            else
              {:noreply, socket}
            end

          {:error, :invalid_current_password} ->
            {:noreply,
             socket
             |> assign(:loading?, false)
             |> assign(:error_message, "Current password is incorrect.")}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:loading?, false)
             |> assign(:error_message, "Failed to update password. Please try again.")}
        end
    end
  end

  @impl true
  def handle_event("go_back", _params, socket) do
    {:noreply, push_navigate(socket, to: socket.assigns.back_path)}
  end

  # `change_password/4` doesn't clear the temp-password flag (it's also used
  # for a regular password change, where there's no temp password to clear).
  # On the forced first-login flow we clear it explicitly so the user isn't
  # sent back through this page on their next login.
  #
  # Guardian caches the resolved user struct per-token for an hour
  # (`AuthServer`) and reads from that cache before hitting the DB, so the
  # AuthPlug on_mount guard would keep seeing the stale (still-set)
  # temp_password on the very next navigation and bounce the user right back
  # here. Refresh the cache entry with the updated struct so it reflects the
  # DB write immediately.
  defp clear_temp_password(user, "student", schema_prefix, auth_token) do
    with {:ok, updated} <- Students.clear_temp_password(user.id, schema_prefix) do
      refresh_auth_cache(auth_token, updated)
    end
  end

  defp clear_temp_password(user, "user", schema_prefix, auth_token) do
    with {:ok, updated} <- Accounts.clear_temp_password(user.id, schema_prefix) do
      refresh_auth_cache(auth_token, updated)
    end
  end

  defp clear_temp_password(_user, _user_type, _schema_prefix, _auth_token), do: :ok

  defp refresh_auth_cache(auth_token, updated_user) when is_binary(auth_token) do
    VyaasaCampus.Auth.AuthServer.cache_user(auth_token, updated_user, 3600)
  end

  defp refresh_auth_cache(_auth_token, _updated_user), do: :ok

  defp detect_user_type(user) do
    case user.__struct__ do
      VyaasaCampus.Schema.Platform.AdminUser -> "admin"
      VyaasaCampus.Schema.Accounts.User -> "user"
      VyaasaCampus.Schema.Students.Student -> "student"
      _ -> "unknown"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-50 to-slate-100 px-4 sm:px-6 lg:px-8">
        <div class="w-full max-w-md mx-auto space-y-8">
          <div class="bg-white rounded-xl shadow-lg border border-gray-200 p-8">
            <!-- Header -->
            <div class="text-center mb-8">
              <div class="flex items-center justify-center mb-4">
                <div class="w-14 h-14 bg-gradient-to-br from-orange-500 to-orange-600 rounded-full flex items-center justify-center shadow-lg">
                  <.icon name="hero-key" class="h-7 w-7 text-white" />
                </div>
              </div>
              <h1 class="text-2xl font-bold text-gray-900 mb-1">
                {if @first_login?, do: "Set Your Password", else: "Change Password"}
              </h1>
              <p class="text-sm text-gray-500">
                <%= if @first_login? do %>
                  Enter the temporary password you were emailed, then choose a new one to continue.
                <% else %>
                  Enter your current password and choose a new one.
                <% end %>
              </p>
            </div>

            <%= if @success? do %>
              <!-- Success State -->
              <div class="text-center space-y-6">
                <div class="bg-green-50 border border-green-200 rounded-lg p-6">
                  <div class="flex justify-center mb-4">
                    <.icon name="hero-check-circle" class="h-12 w-12 text-green-500" />
                  </div>
                  <h3 class="text-lg font-semibold text-green-800 mb-2">Password Updated!</h3>
                  <p class="text-sm text-green-700">
                    Your password has been changed successfully.
                  </p>
                </div>

                <button
                  phx-click="go_back"
                  class="w-full flex justify-center py-3 px-4 border border-transparent rounded-lg text-sm font-medium text-white bg-orange-500 hover:bg-orange-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500"
                >
                  Back to Dashboard
                </button>
              </div>
            <% else %>
              <!-- Change Password Form -->
              <.form for={@form} id="change-password-form" phx-submit="change_password" phx-change="validate" class="space-y-5">
                <div>
                  <.input
                    field={@form[:current_password]}
                    type="password"
                    label="Current Password"
                    placeholder="Enter current password"
                    required
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                  />
                </div>

                <div>
                  <.input
                    field={@form[:new_password]}
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
                    label="Confirm New Password"
                    placeholder="Re-enter new password"
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
                    Updating...
                  <% else %>
                    Update Password
                  <% end %>
                </button>

                <div class="text-center">
                  <button
                    type="button"
                    phx-click="go_back"
                    class="text-sm text-gray-500 hover:text-gray-700 font-medium"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
