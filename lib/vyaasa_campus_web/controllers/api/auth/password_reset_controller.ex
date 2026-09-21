defmodule VyaasaCampusWeb.API.Auth.PasswordResetController do
  @moduledoc """
  Unified password reset controller for VyaasaCampus application.
  Handles password reset requests for all user types (platform admin, tenant users, students)
  with automatic context detection.
  """

  use VyaasaCampusWeb, :controller

  import VyaasaCampusWeb.Shared.ErrorHandler,
    except: [format_changeset_errors: 1, validate_uuid: 1, handle_validation_error: 2]

  alias VyaasaCampus.Auth.PasswordResetService
  alias VyaasaCampus.Contexts.Tenants

  @doc """
  Request password reset for any user type.
  Automatically detects if it's a platform admin or tenant user/student.
  """
  def request_reset(conn, %{"email" => email} = _params) do
    tenant_alias = get_tenant_alias(conn)
    schema_prefix = get_schema_prefix(tenant_alias)

    case PasswordResetService.request_password_reset(email, tenant_alias, schema_prefix) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Password reset email sent successfully",
          email: email
        })

      {:error, :user_not_found} ->
        handle_user_error(
          conn,
          :user_not_found,
          email,
          "No user found with the provided email address in this tenant"
        )

      {:error, :student_not_verified} ->
        handle_authorization_error(
          conn,
          :forbidden,
          "Your student profile must be verified by an admin before you can reset your password."
        )

      {:error, :email_send_failed} ->
        handle_server_error(
          conn,
          :email_error,
          "We couldn't send the password reset email. Please try again later."
        )

      {:error, changeset} ->
        handle_validation_error(
          conn,
          changeset,
          "Failed to process password reset request due to validation errors"
        )
    end
  end

  @doc """
  Reset password using token for any user type.
  Automatically detects user type from token.
  Supports auto mode for users with temporary passwords.
  """
  def reset_password(conn, %{"password" => password} = params) do
    tenant_alias = get_tenant_alias(conn)
    schema_prefix = get_schema_prefix(tenant_alias)

    # Check if this is auto mode (no token required)
    auto_mode = Map.get(params, "auto_mode", false)
    token = Map.get(params, "token")

    cond do
      auto_mode and is_nil(token) ->
        # Auto mode: reset password for current user (requires authentication or user info)
        user_id = Map.get(params, "user_id")
        user_type = Map.get(params, "user_type")

        if user_id && user_type do
          # Direct user info provided
          handle_auto_password_reset_with_user_info(conn, password, tenant_alias, schema_prefix, user_id, user_type)
        else
          # Fallback to authentication-based approach
          handle_auto_password_reset(conn, password, tenant_alias, schema_prefix)
        end

      not is_nil(token) ->
        # Normal mode: reset password using token
        handle_token_password_reset(conn, token, password, tenant_alias, schema_prefix)

      true ->
        handle_parameter_error(
          conn,
          ["token", "auto_mode"],
          "Either token or auto_mode must be provided"
        )
    end
  end

  # Handle auto mode password reset with direct user info
  defp handle_auto_password_reset_with_user_info(conn, password, tenant_alias, schema_prefix, user_id, user_type) do
    # Get user by ID and type
    case get_user_by_id_and_type(user_id, user_type, tenant_alias, schema_prefix) do
      {:ok, user} ->
        case PasswordResetService.reset_password_auto_mode(user, password, tenant_alias, schema_prefix) do
          {:ok, updated_user} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "Password updated successfully",
              user_id: updated_user.id
            })

          {:error, changeset} ->
            handle_validation_error(
              conn,
              changeset,
              "The new password does not meet the requirements"
            )
        end

      {:error, :not_found} ->
        handle_not_found_error(
          conn,
          "user",
          nil,
          "User not found"
        )
    end
  end

  # Handle auto mode password reset (for users with temporary passwords)
  defp handle_auto_password_reset(conn, password, tenant_alias, schema_prefix) do
    # In auto mode, we need to get the current user from the JWT token
    # This requires the user to be authenticated
    case get_current_user_from_token(conn) do
      {:ok, user} ->
        case PasswordResetService.reset_password_auto_mode(user, password, tenant_alias, schema_prefix) do
          {:ok, updated_user} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "Password updated successfully",
              user_id: updated_user.id
            })

          {:error, changeset} ->
            handle_validation_error(
              conn,
              changeset,
              "The new password does not meet the requirements"
            )
        end

      {:error, :not_authenticated} ->
        handle_auth_error(
          conn,
          :unauthorized,
          "Authentication required for auto password reset"
        )
    end
  end

  # Handle normal token-based password reset
  defp handle_token_password_reset(conn, token, password, tenant_alias, schema_prefix) do
    case PasswordResetService.reset_password_with_token(token, password, tenant_alias, schema_prefix) do
      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Password reset successfully",
          user_id: user.id
        })

      {:error, :invalid_token} ->
        handle_auth_error(
          conn,
          :invalid_token,
          "The password reset token is invalid or has been used"
        )

      {:error, :token_expired} ->
        handle_auth_error(
          conn,
          :token_expired,
          "The password reset token has expired. Please request a new one"
        )

      {:error, :student_not_verified} ->
        handle_authorization_error(
          conn,
          :forbidden,
          "Your student profile must be verified by an admin before you can reset your password."
        )

      {:error, changeset} ->
        handle_validation_error(
          conn,
          changeset,
          "The new password does not meet the requirements"
        )
    end
  end

  # Helper function to get user by ID and type
  defp get_user_by_id_and_type(user_id, user_type, _tenant_alias, schema_prefix) do
    repo = Application.get_env(:vyaasa_campus, :repo, VyaasaCampus.Repo)
    schema = get_schema_for_user_type(user_type)

    case repo.get(schema, user_id, prefix: schema_prefix) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp get_schema_for_user_type("tenant_user"), do: VyaasaCampus.Schema.Accounts.User
  defp get_schema_for_user_type("student"), do: VyaasaCampus.Schema.Students.Student
  defp get_schema_for_user_type(_), do: VyaasaCampus.Schema.Accounts.User

  # Extract current user from JWT token in auto mode
  defp get_current_user_from_token(conn) do
    with {:ok, token} <- extract_bearer_token(conn),
         {:ok, claims} <- VyaasaCampus.Guardian.decode_and_verify(token),
         {:ok, user} <- VyaasaCampus.Guardian.resource_from_claims(claims) do
      {:ok, user}
    else
      _ -> {:error, :not_authenticated}
    end
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :not_authenticated}
    end
  end

  @doc """
  Clear temporary password after first login for any user type.
  """
  def clear_temp_password(conn, %{"user_id" => user_id} = _params) do
    tenant_alias = get_tenant_alias(conn)
    schema_prefix = get_schema_prefix(tenant_alias)

    case PasswordResetService.clear_temp_password(user_id, tenant_alias, schema_prefix) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Temporary password cleared successfully"
        })

      {:error, :user_not_found} ->
        handle_user_error(conn, :user_not_found, user_id, "No user found with the provided ID")

      {:error, changeset} ->
        handle_validation_error(
          conn,
          changeset,
          "Failed to clear temporary password due to validation errors"
        )
    end
  end

  @doc """
  Change password for the currently authenticated user (any type).

  Requires the current (or temporary) password for verification and a new
  password. Used by the first-login flow: a user who logged in with a
  temporary password re-enters it as `current_password` together with their
  chosen `new_password`. On success the temporary password is cleared.
  """
  def change_password(
        conn,
        %{"current_password" => current_password, "new_password" => new_password} = _params
      ) do
    tenant_alias = get_tenant_alias(conn)
    schema_prefix = get_schema_prefix(tenant_alias)

    case conn.assigns[:current_user] do
      nil ->
        handle_auth_error(conn, :unauthorized, "Authentication required to change password")

      user ->
        case PasswordResetService.change_password(
               user,
               current_password,
               new_password,
               schema_prefix
             ) do
          {:ok, updated_user} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "Password changed successfully",
              user_id: updated_user.id
            })

          {:error, :invalid_current_password} ->
            handle_auth_error(
              conn,
              :invalid_credentials,
              "The current (or temporary) password is incorrect"
            )

          {:error, changeset} ->
            handle_validation_error(
              conn,
              changeset,
              "The new password does not meet the requirements"
            )
        end
    end
  end

  # Private helper functions

  defp get_tenant_alias(conn) do
    # TenantPlug now handles x-tenant header priority, so we can use conn.assigns directly
    conn.assigns[:tenant_alias]
  end

  # Platform admins have no tenant → default to the public schema.
  defp get_schema_prefix(nil), do: "public"

  defp get_schema_prefix(tenant_alias) do
    case Tenants.get_tenant_by_alias(String.upcase(tenant_alias)) do
      nil -> "public"
      tenant -> tenant.schema_name
    end
  end

  # Using shared format_changeset_errors from VyaasaCampusWeb.Shared.ControllerHelpers
end
