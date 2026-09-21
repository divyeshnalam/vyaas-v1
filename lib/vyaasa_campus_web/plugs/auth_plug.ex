defmodule VyaasaCampusWeb.Plugs.AuthPlug do
  @moduledoc """
  Authentication plug for verifying JWT tokens and setting current user.
  """

  import Plug.Conn
  import Phoenix.LiveView, only: [redirect: 2]
  alias VyaasaCampus.Guardian

  @doc """
  Plug to verify JWT token and set current user
  """
  def init(opts), do: opts

  # Base authentication phase (no enforcement)
  def call(conn, opts) when opts in [nil, :base, [], %{}] do
    token = get_auth_token(conn)

    case token do
      nil ->
        assign_no_user(conn)

      token ->
        handle_authenticated_token(conn, token)
    end
  end

  # Enforcement variants that run base auth first and then enforce
  def call(conn, :require_auth) do
    conn |> call(:base) |> require_auth(nil)
  end

  def call(conn, :require_admin) do
    conn |> call(:base) |> require_admin(nil)
  end

  def call(conn, :require_tenant_user_or_admin) do
    conn |> call(:base) |> require_tenant_user_or_admin(nil)
  end

  def call(conn, :require_student) do
    conn |> call(:base) |> require_student(nil)
  end

  def call(conn, :require_tenant_user_only) do
    conn |> call(:base) |> require_tenant_user_only(nil)
  end

  defp assign_no_user(conn) do
    conn
    |> assign(:current_user, nil)
    |> assign(:user_type, nil)
    |> assign(:creator_info, nil)
  end

  defp handle_authenticated_token(conn, token) do
    case Guardian.current_user(token) do
      {:ok, user} ->
        process_user_auth(conn, token, user)

      {:ok, _claims, user} ->
        process_user_auth(conn, token, user)

      {:error, _reason} ->
        assign_no_user(conn)
    end
  end

  defp process_user_auth(conn, token, user) do
    user_type = Guardian.get_user_type(user)
    creator_info = build_creator_info(user, user_type)

    conn
    |> maybe_store_token_in_session(token)
    |> assign(:current_user, user)
    |> assign(:user_type, user_type)
    |> assign(:creator_info, creator_info)
  end

  defp maybe_store_token_in_session(conn, token) do
    # Always store token in session for LiveView compatibility
    put_session(conn, :auth_token, token)
  end

  @doc """
  Plug to require authentication
  """
  def require_auth(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: "Authentication required"}))
      |> halt()
    end
  end

  @doc """
  Plug to require admin authentication
  """
  def require_admin(conn, _opts) do
    if Guardian.admin?(conn.assigns[:current_user]) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{error: "Admin access required"}))
      |> halt()
    end
  end

  @doc """
  Plug to require tenant user authentication
  """
  def require_tenant_user(conn, _opts) do
    if Guardian.tenant_user?(conn.assigns[:current_user]) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{error: "Tenant user access required"}))
      |> halt()
    end
  end

  @doc """
  Plug to require student authentication
  """
  def require_student(conn, _opts) do
    if Guardian.student?(conn.assigns[:current_user]) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{error: "Student access required"}))
      |> halt()
    end
  end

  @doc """
  Plug to require tenant user or admin authentication
  """
  def require_tenant_user_or_admin(conn, _opts) do
    user_type = conn.assigns[:user_type]

    case user_type do
      "admin" ->
        # Platform admin can access any tenant
        conn

      "user" ->
        # Tenant user can access their own tenant
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{error: "Tenant user or admin access required"}))
        |> halt()
    end
  end

  @doc """
  Plug to require tenant user only (no platform admin)
  """
  def require_tenant_user_only(conn, _opts) do
    current_user = conn.assigns[:current_user]
    user_type = conn.assigns[:user_type]

    case {current_user, user_type} do
      {nil, _} ->
        conn
        |> put_status(:unauthorized)
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Authentication required"}))
        |> halt()

      {_, "user"} ->
        # Only tenant users can access
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{error: "Tenant user access required"}))
        |> halt()
    end
  end

  defp get_auth_token(conn) do
    # Priority order: header > session > params > assigns
    # Session is important for LiveView requests
    token =
      get_auth_token_from_header(conn) ||
        get_auth_token_from_session(conn) ||
        get_auth_token_from_params(conn) ||
        get_auth_token_from_assigns(conn)

    require Logger

    Logger.info(
      "AuthPlug: Token retrieval - header: #{inspect(get_auth_token_from_header(conn) != nil)}, session: #{inspect(get_auth_token_from_session(conn) != nil)}, params: #{inspect(get_auth_token_from_params(conn) != nil)}, assigns: #{inspect(get_auth_token_from_assigns(conn) != nil)}"
    )

    token
  end

  defp get_auth_token_from_header(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  defp get_auth_token_from_session(conn) do
    case get_session(conn, :auth_token) do
      token when is_binary(token) and byte_size(token) > 0 -> token
      _ -> nil
    end
  end

  defp get_auth_token_from_params(conn) do
    case conn.params["authorization"] do
      "Bearer " <> token ->
        token

      _ ->
        # Also check for direct token parameter
        conn.params["auth_token"]
    end
  end

  defp get_auth_token_from_assigns(conn) do
    case conn.assigns[:auth_token] do
      token when is_binary(token) -> token
      _ -> nil
    end
  end

  defp build_creator_info(user, user_type) do
    created_by_type =
      case user_type do
        "admin" -> "public"
        "user" -> "tenant"
        "student" -> "tenant"
        _ -> "unknown"
      end

    %{
      created_by_id: user.id,
      created_by_type: created_by_type
    }
  end

  # =============================
  # LiveView on_mount hooks
  # =============================

  @doc """
  on_mount hook for requiring authentication in LiveViews
  """
  def on_mount(:require_admin, _params, session, socket) do
    token = get_comprehensive_token(socket, session, %{})

    require Logger
    Logger.info("AuthPlug on_mount (admin): token_present=#{token != nil}")

    case token do
      nil ->
        {:halt, redirect(socket, to: "/admin/login")}

      token ->
        handle_admin_token_verification(socket, token)
    end
  end

  def on_mount(:require_tenant_user_only, params, session, socket) do
    # Get token from multiple sources with better priority
    token = get_comprehensive_token(socket, session, params)
    # Dynamic tenant or fallback
    tenant_alias = params["tenant"] || "gbit"

    require Logger
    Logger.info("AuthPlug on_mount: tenant=#{tenant_alias}, token_present=#{token != nil}")

    case token do
      nil ->
        {:halt, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}

      token ->
        handle_token_verification(socket, token, tenant_alias)
    end
  end

  def on_mount(:require_student, params, session, socket) do
    # Get token from multiple sources with better priority
    token = get_comprehensive_token(socket, session, params)
    # Dynamic tenant or fallback
    tenant_alias = params["tenant"] || "gbit"

    require Logger
    Logger.info("AuthPlug on_mount (student): tenant=#{tenant_alias}, token_present=#{token != nil}")

    case token do
      nil ->
        {:halt, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}

      token ->
        handle_student_token_verification(socket, token, tenant_alias)
    end
  end

  defp get_comprehensive_token(socket, session, params) do
    # Try multiple sources in priority order
    socket.assigns[:auth_token] ||
      socket.assigns[:current_user_token] ||
      params["auth_token"] ||
      session["auth_token"] ||
      session[:auth_token] ||
      get_token_from_connect_params(socket)
  end

  defp get_token_from_connect_params(socket) do
    # Extract from the initial connection params
    connect_params = socket.private[:connect_params] || %{}
    connect_params["auth_token"] || connect_params[:auth_token]
  end

  defp handle_token_verification(socket, token, tenant_alias) do
    case Guardian.current_user(token) do
      {:ok, user} ->
        verify_user_type(socket, user, tenant_alias)

      {:ok, _claims, user} ->
        verify_user_type(socket, user, tenant_alias)

      {:error, _reason} ->
        {:halt, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}
    end
  end

  defp verify_user_type(socket, user, tenant_alias) do
    user_type = Guardian.get_user_type(user)

    if user_type == "user" or user_type == "tenant_user" do
      # Store user and token info in socket assigns for subsequent navigation
      socket = %{
        socket
        | assigns:
            Map.merge(socket.assigns, %{
              current_user: user,
              user_type: user_type
            })
      }

      enforce_password_change(socket, user, "/user/#{tenant_alias}/change-password?first_login=true")
    else
      {:halt, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}
    end
  end

  defp handle_student_token_verification(socket, token, tenant_alias) do
    case Guardian.current_user(token) do
      {:ok, user} ->
        verify_student_type(socket, user, tenant_alias)

      {:ok, _claims, user} ->
        verify_student_type(socket, user, tenant_alias)

      {:error, _reason} ->
        {:halt, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}
    end
  end

  defp verify_student_type(socket, user, tenant_alias) do
    user_type = Guardian.get_user_type(user)

    if user_type == "student" do
      # Store user and token info in socket assigns for subsequent navigation
      socket = %{
        socket
        | assigns:
            Map.merge(socket.assigns, %{
              current_user: user,
              user_type: user_type
            })
      }

      enforce_password_change(socket, user, "/student/#{tenant_alias}/change-password?first_login=true")
    else
      {:halt, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}
    end
  end

  # A user still sitting on a temp password (issued at approval/verification)
  # must set a real one before reaching anywhere else — otherwise they could
  # skip the forced first-login change-password page via a direct URL. The
  # `socket.view` check avoids redirecting the change-password page to itself.
  defp enforce_password_change(socket, user, redirect_path) do
    if socket.view != VyaasaCampusWeb.Shared.ChangePasswordLive and not is_nil(Map.get(user, :temp_password)) do
      {:halt, redirect(socket, to: redirect_path)}
    else
      {:cont, socket}
    end
  end

  defp handle_admin_token_verification(socket, token) do
    case Guardian.current_user(token) do
      {:ok, user} ->
        verify_admin_type(socket, user)

      {:ok, _claims, user} ->
        verify_admin_type(socket, user)

      {:error, _reason} ->
        {:halt, redirect(socket, to: "/admin/login")}
    end
  end

  defp verify_admin_type(socket, user) do
    if Guardian.admin?(user) do
      socket = %{
        socket
        | assigns:
            Map.merge(socket.assigns, %{
              current_user: user,
              user_type: "admin"
            })
      }

      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/admin/login")}
    end
  end
end
