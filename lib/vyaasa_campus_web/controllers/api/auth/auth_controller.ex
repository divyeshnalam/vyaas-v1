defmodule VyaasaCampusWeb.Auth.AuthController do
  @moduledoc """
  Authentication controller for handling login and user management.
  Supports PlatformAdmin, User (tenant), and Student authentication.
  Only students can register - platform admins and tenant users are created by administrators.
  """

  use VyaasaCampusWeb, :controller

  import VyaasaCampusWeb.Shared.ErrorHandler,
    except: [format_changeset_errors: 1, validate_uuid: 1, handle_validation_error: 2]

  import VyaasaCampusWeb.Shared.ControllerHelpers
  alias VyaasaCampus.{Auth, Guardian}
  alias VyaasaCampus.Auth.AuthServer
  alias VyaasaCampus.Auth.AuthSupervisor
  alias VyaasaCampus.Contexts.Tenants

  # Platform admin login
  def platform_admin_login(conn, %{"email" => email, "password" => password}) do
    case Auth.authenticate_admin(email, password) do
      {:ok, admin_user} ->
        {:ok, admin_user} = Auth.update_last_login(admin_user)
        sid = Auth.establish_session(admin_user, Auth.new_session_id())
        {:ok, token, _claims} = Guardian.create_token(admin_user, %{user_type: "admin", sid: sid})

        {:ok, refresh_token, refresh_expires_at} =
          VyaasaCampus.Auth.issue_refresh_token(admin_user)

        conn
        |> put_refresh_cookie(refresh_token, refresh_expires_at)
        |> put_status(:ok)
        |> json(%{
          token: token,
          expires_in: access_token_ttl_seconds(),
          user: %{
            id: admin_user.id,
            email: admin_user.email,
            first_name: admin_user.first_name,
            last_name: admin_user.last_name,
            role: admin_user.role,
            user_type: "admin"
          }
        })

      {:error, :not_found} ->
        handle_auth_error(
          conn,
          :invalid_credentials,
          "No user found with the provided email address"
        )

      {:error, :invalid_password} ->
        handle_auth_error(conn, :invalid_credentials, "The provided password is incorrect")
    end
  end

  # Tenant user login
  def tenant_user_login(conn, %{"email" => email, "password" => password}) do
    # Get tenant from header or subdomain
    tenant_schema = get_tenant_schema_from_request(conn)

    case Auth.authenticate_user(email, password, tenant_schema) do
      {:ok, user} ->
        {:ok, user} = Auth.update_last_login(user, tenant_schema)
        sid = Auth.establish_session(user, Auth.new_session_id(), tenant_schema)

        {:ok, token, _claims} =
          Guardian.create_token(user, %{user_type: "user", tenant_schema: tenant_schema, sid: sid})

        {:ok, refresh_token, refresh_expires_at} =
          VyaasaCampus.Auth.issue_refresh_token(user, tenant_schema)

        conn
        |> put_refresh_cookie(refresh_token, refresh_expires_at)
        |> put_status(:ok)
        |> json(%{
          token: token,
          expires_in: access_token_ttl_seconds(),
          user: %{
            id: user.id,
            email: user.email,
            first_name: user.first_name,
            last_name: user.last_name,
            role: user.role,
            user_type: "user",
            has_temp_password: !is_nil(user.temp_password)
          }
        })

      {:error, :not_found} ->
        handle_auth_error(
          conn,
          :invalid_credentials,
          "No user found with the provided email address"
        )

      {:error, :invalid_password} ->
        handle_auth_error(conn, :invalid_credentials, "The provided password is incorrect")
    end
  end

  # Student login
  def student_login(conn, %{"email" => email, "password" => password}) do
    # Get tenant from header or subdomain
    tenant_schema = get_tenant_schema_from_request(conn)

    case Auth.authenticate_student(email, password, tenant_schema) do
      {:ok, student} ->
        {:ok, _student} = Auth.update_last_login(student, tenant_schema)

        # Single active session: supersede any other device before minting this token.
        sid = Auth.establish_session(student, Auth.new_session_id(), tenant_schema)

        {:ok, token, _claims} =
          Guardian.create_token(student, %{user_type: "student", tenant_schema: tenant_schema, sid: sid})

        {:ok, refresh_token, refresh_expires_at} =
          VyaasaCampus.Auth.issue_refresh_token(student, tenant_schema)

        conn
        |> put_refresh_cookie(refresh_token, refresh_expires_at)
        |> put_status(:ok)
        |> json(%{
          token: token,
          expires_in: access_token_ttl_seconds(),
          user: %{
            id: student.id,
            email: student.email,
            first_name: student.first_name,
            last_name: student.last_name,
            user_type: "student",
            has_temp_password: !is_nil(student.temp_password)
          }
        })

      {:error, :not_found} ->
        handle_auth_error(
          conn,
          :invalid_credentials,
          "No user found with the provided email address"
        )

      {:error, :invalid_password} ->
        handle_auth_error(conn, :invalid_credentials, "The provided password is incorrect")

      {:error, :student_not_verified} ->
        handle_authorization_error(
          conn,
          :forbidden,
          "Your student profile must be verified by an admin before you can log in."
        )
    end
  end

  # Student registration
  def student_register(conn, attrs) do
    tenant_schema = get_tenant_schema_from_request(conn)

    case Auth.register_student(attrs, tenant_schema) do
      {:ok, student} ->
        {:ok, token, _claims} =
          Guardian.create_token(student, %{user_type: "student", tenant_schema: tenant_schema})

        conn
        |> put_status(:created)
        |> json(%{
          token: token,
          user: %{
            id: student.id,
            email: student.email,
            first_name: student.first_name,
            last_name: student.last_name,
            user_type: "student"
          }
        })

      {:error, changeset} ->
        handle_validation_error(conn, changeset)
    end
  end

  # Get current user info - works for all user types (SuperAdmin, Institute Admin, Student)
  def me(conn, _params) do
    user = conn.assigns.current_user
    scope = conn.assigns[:scope]

    # Check if user exists
    case user do
      nil ->
        handle_auth_error(conn, :unauthorized)

      user ->
        user_type = Guardian.get_user_type(user)

        # Build user info based on user type
        user_info =
          case user_type do
            "admin" ->
              %{
                id: user.id,
                email: user.email,
                first_name: user.first_name,
                last_name: user.last_name,
                role: user.role,
                status: user.status,
                user_type: user_type,
                last_login_at: format_datetime_ist(user.last_login_at),
                created_at: format_datetime_ist(user.inserted_at),
                updated_at: format_datetime_ist(user.updated_at)
              }

            "user" ->
              %{
                id: user.id,
                email: user.email,
                first_name: user.first_name,
                last_name: user.last_name,
                role: user.role,
                status: user.status,
                user_type: user_type,
                has_temp_password: !is_nil(user.temp_password),
                last_login_at: format_datetime_ist(user.last_login_at),
                created_by_id: user.created_by_id,
                created_by_type: user.created_by_type,
                created_at: format_datetime_ist(user.inserted_at),
                updated_at: format_datetime_ist(user.updated_at)
              }

            "student" ->
              # For students, the user is the student record itself
              %{
                id: user.id,
                email: user.email,
                first_name: user.first_name,
                last_name: user.last_name,
                user_type: user_type,
                has_temp_password: !is_nil(user.temp_password),
                last_login_at: format_datetime_ist(user.last_login_at),
                created_by_id: user.created_by_id,
                created_by_type: user.created_by_type,
                created_at: format_datetime_ist(user.inserted_at),
                updated_at: format_datetime_ist(user.updated_at),
                # Student-specific fields
                student_profile: %{
                  registration_id: user.registration_id,
                  degree: user.degree,
                  specialization: user.specialization,
                  current_academic_year: user.current_academic_year,
                  cgpa: user.cgpa,
                  year_of_passing: user.year_of_passing,
                  profile_completed: user.profile_completed
                }
              }

            _ ->
              # Handle unknown user types gracefully
              %{
                id: user.id,
                user_type: "unknown",
                error: "Unknown user type"
              }
          end

        conn
        |> json(%{
          user: user_info,
          tenant_info: get_tenant_info(conn, user_type),
          scope: scope
        })
    end
  end

  # Logout (remove from cache and invalidate token)
  def logout(conn, _params) do
    # Remove from cache and revoke refresh token
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        VyaasaCampus.Guardian.logout_user(token)
        user = conn.assigns.current_user

        case VyaasaCampus.Guardian.get_user_type(user) do
          "admin" ->
            VyaasaCampus.Auth.revoke_refresh_token(user)

          "user" ->
            with {:ok, claims} <- VyaasaCampus.Guardian.decode_and_verify(token),
                 schema when is_binary(schema) <- Map.get(claims, "tenant_schema") do
              VyaasaCampus.Auth.revoke_refresh_token(user, schema)
            else
              _ -> :ok
            end

          "student" ->
            with {:ok, claims} <- VyaasaCampus.Guardian.decode_and_verify(token),
                 schema when is_binary(schema) <- Map.get(claims, "tenant_schema") do
              VyaasaCampus.Auth.revoke_refresh_token(user, schema)
            else
              _ -> :ok
            end

          "super_admin" ->
            with {:ok, claims} <- VyaasaCampus.Guardian.decode_and_verify(token),
                 schema when is_binary(schema) <- Map.get(claims, "tenant_schema") do
              VyaasaCampus.Auth.revoke_refresh_token(user, schema)
            else
              _ -> :ok
            end

          _ ->
            :ok
        end

      _ ->
        :ok
    end

    conn
    |> delete_resp_cookie("rt", cookie_opts())
    |> json(%{message: "Logged out successfully"})
  end

  # Using shared functions from VyaasaCampusWeb.Shared.ControllerHelpers

  defp get_tenant_info(conn, user_type) do
    case user_type do
      "admin" ->
        %{tenant_type: "platform", schema: "public"}

      user_type when user_type in ["user", "student"] ->
        get_tenant_info_from_header(conn)

      _ ->
        %{tenant_type: "unknown", error: "Unknown user type"}
    end
  end

  defp get_tenant_info_from_header(conn) do
    case get_req_header(conn, "x-tenant") do
      [tenant_alias] ->
        get_tenant_details(tenant_alias)

      _ ->
        %{tenant_type: "unknown"}
    end
  end

  defp get_tenant_details(tenant_alias) do
    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil ->
        %{tenant_type: "unknown", alias: tenant_alias}

      tenant ->
        %{
          tenant_type: "institute",
          alias: tenant.alias,
          name: tenant.full_name,
          schema: tenant.schema_name
        }
    end
  end

  # Get auth cache statistics (admin only)
  def cache_stats(conn, _params) do
    # This should be behind admin authentication
    stats = AuthServer.stats()
    supervisor_status = AuthSupervisor.status()

    conn
    |> json(%{
      cache_stats: stats,
      supervisor_status: %{
        children_count: supervisor_status.count,
        supervisor_pid: inspect(supervisor_status.supervisor_pid)
      }
    })
  end

  defp access_token_ttl_seconds do
    case Application.get_env(:vyaasa_campus, VyaasaCampus.Guardian)[:ttl] do
      {n, :seconds} -> n
      {n, :minutes} -> n * 60
      {n, :hours} -> n * 60 * 60
      {n, :days} -> n * 24 * 60 * 60
      _ -> String.to_integer(System.get_env("ACCESS_TOKEN_TTL_MINUTES") || "30") * 60
    end
  end

  defp cookie_opts do
    secure =
      get_in(Application.get_env(:vyaasa_campus, VyaasaCampusWeb.Endpoint), [:url, :host]) !=
        "localhost"

    days = String.to_integer(System.get_env("REFRESH_TOKEN_TTL_DAYS") || "30")
    [http_only: true, secure: secure, same_site: "Lax", path: "/", max_age: days * 24 * 60 * 60]
  end

  defp put_refresh_cookie(conn, token, _expires_at) do
    put_resp_cookie(conn, "rt", token, cookie_opts())
  end
end
