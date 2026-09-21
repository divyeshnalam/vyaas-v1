defmodule VyaasaCampusWeb.SessionController do
  @moduledoc """
  Controller for managing authentication sessions.
  Handles setting session tokens from URL parameters for LiveView authentication.
  """

  use VyaasaCampusWeb, :controller

  def set_session(conn, %{"tenant" => tenant_alias} = params) do
    auth_token = params["auth_token"]
    user_type = params["user_type"] || "tenant_user"
    has_temp_password = params["has_temp_password"] == "true"

    if auth_token do
      # Store token and user type in session for LiveView to access
      conn =
        conn
        |> put_session(:auth_token, auth_token)
        |> put_session(:user_type, user_type)

      # First-time login with a temp password: force a password change before
      # letting the user reach their normal dashboard.
      redirect_path =
        cond do
          has_temp_password and user_type == "student" ->
            "/student/#{tenant_alias}/change-password?first_login=true"

          has_temp_password ->
            "/user/#{tenant_alias}/change-password?first_login=true"

          user_type == "student" ->
            "/student/#{tenant_alias}/ai8-overview"

          true ->
            "/user/#{tenant_alias}/dashboard"
        end

      redirect(conn, to: redirect_path)
    else
      # No token provided, redirect to login
      redirect(conn, to: "/auth/tenant/#{tenant_alias}/login")
    end
  end

  def set_admin_session(conn, params) do
    auth_token = params["auth_token"]

    if auth_token do
      conn
      |> put_session(:auth_token, auth_token)
      |> put_session(:user_type, "admin")
      |> redirect(to: "/admin/dashboard")
    else
      redirect(conn, to: "/admin/login")
    end
  end

  def admin_logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/admin/login")
  end

  @doc """
  Student / tenant-user logout. Runs on the plain :browser pipeline (NOT behind
  the auth pipeline), so it signs the user out even when their session was
  superseded by a newer login (single-active-session). Clears the auth cookie —
  the authoritative source LiveView reads — and best-effort revokes the cached
  token, then returns to the login page.
  """
  def tenant_logout(conn, %{"tenant" => tenant_alias}) do
    case get_session(conn, :auth_token) do
      token when is_binary(token) ->
        VyaasaCampus.Guardian.logout_user(token)
        VyaasaCampus.Auth.AuthServer.remove_user(token)

      _ ->
        :ok
    end

    conn
    |> clear_session()
    |> redirect(to: "/auth/tenant/#{tenant_alias}/login")
  end
end
