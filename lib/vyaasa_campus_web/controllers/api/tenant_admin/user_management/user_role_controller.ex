defmodule VyaasaCampusWeb.TenantAdmin.UserManagement.UserRoleController do
  @moduledoc """
  Controller for managing user-role assignments within tenant contexts.

  This controller handles user-role relationship operations including:
  - Role assignment to users
  - User-role assignment listing
  - Role removal from users

  only platform admins can manage user roles in any tenant and tenant users can manage user roles in their own tenant only
  """

  use VyaasaCampusWeb, :controller
  import VyaasaCampusWeb.Shared.ControllerHelpers

  import VyaasaCampusWeb.Shared.ErrorHandler,
    except: [format_changeset_errors: 1, validate_uuid: 1, handle_validation_error: 2]

  require Logger
  alias VyaasaCampus.Contexts.Accounts

  @doc """
  Lists all user-role assignments in the given tenant /api/tenant/user_roles
  """
  def index(conn, _params) do
    # Get tenant alias from header for validation
    case get_req_header(conn, "x-tenant") do
      [tenant_alias] ->
        case validate_tenant_access(conn, tenant_alias) do
          {:ok, schema} ->
            user_roles = Accounts.list_user_roles(schema)
            json(conn, user_roles)

          {:error, :unauthorized} ->
            handle_auth_error(
              conn,
              :unauthorized,
              "Authentication is required to access user roles"
            )

          {:error, :tenant_not_found} ->
            handle_tenant_error(
              conn,
              :tenant_not_found,
              tenant_alias,
              "The specified tenant was not found"
            )

          {:error, :access_denied} ->
            handle_authorization_error(
              conn,
              :tenant_access_denied,
              "You do not have access to this tenant's user roles"
            )

          {:error, :unknown_user_type} ->
            handle_authorization_error(
              conn,
              :forbidden,
              "Unknown user type - access denied to user roles"
            )
        end

      _ ->
        handle_tenant_error(
          conn,
          :tenant_header_required,
          nil,
          "The 'x-tenant' header is required for this operation"
        )
    end
  end

  @doc """
  Assigns a role to a user in the given tenant /api/tenant/user_roles
  only platform admins can manage user roles in any tenant and tenant users can manage user roles in their own tenant only
  """
  def create(conn, %{"user_role" => user_role_params}) do
    with [tenant_alias] <- get_req_header(conn, "x-tenant"),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         :ok <- validate_role_management_permission(conn, tenant_alias),
         {:ok, creator_info} <- get_creator_info(conn),
         {:ok, user_id, role_id} <- validate_role_params(user_role_params),
         {:ok, user_role} <- assign_role_to_user(user_id, role_id, creator_info, schema, tenant_alias) do
      json(conn, %{
        user_role: user_role,
        message: "Role assigned successfully"
      })
    else
      [] ->
        handle_parameter_error(conn, ["x-tenant"], "Tenant header is required")

      {:error, :unauthorized} ->
        handle_auth_error(conn, :unauthorized, "Authentication is required to assign roles")

      {:error, :tenant_not_found} ->
        handle_tenant_error(
          conn,
          :tenant_not_found,
          nil,
          "The specified tenant was not found"
        )

      {:error, :access_denied} ->
        handle_authorization_error(
          conn,
          :tenant_access_denied,
          "You do not have access to assign roles in this tenant"
        )

      {:error, :unknown_user_type} ->
        handle_authorization_error(
          conn,
          :forbidden,
          "Unknown user type - access denied to assign roles"
        )

      {:error, :missing_creator_info} ->
        handle_auth_error(conn, :unauthorized, "Authentication information is missing")

      {:error, :invalid_params} ->
        handle_parameter_error(conn, ["user_id", "role_id"], "User ID and Role ID are required")

      {:error, changeset} ->
        handle_validation_error(
          conn,
          changeset,
          "Failed to assign role due to validation errors"
        )
    end
  end

  # === Private Functions ===

  defp validate_role_management_permission(conn, tenant_alias) do
    case conn.assigns[:user_type] do
      "admin" -> :ok
      "user" -> validate_user_tenant_access(conn, tenant_alias)
      _ -> {:error, :unknown_user_type}
    end
  end

  defp validate_user_tenant_access(conn, tenant_alias) do
    case conn.assigns[:current_user] do
      %{tenant_id: user_tenant_id} ->
        if user_tenant_id == get_tenant_id_from_alias(tenant_alias) do
          :ok
        else
          {:error, :access_denied}
        end

      _ ->
        {:error, :access_denied}
    end
  end

  defp get_creator_info(conn) do
    case conn.assigns[:creator_info] do
      nil -> {:error, :missing_creator_info}
      creator_info -> {:ok, creator_info}
    end
  end

  defp validate_role_params(user_role_params) do
    user_id = Map.get(user_role_params, "user_id")
    role_id = Map.get(user_role_params, "role_id")

    case {user_id, role_id} do
      {nil, _} -> {:error, :invalid_params}
      {_, nil} -> {:error, :invalid_params}
      {user_id, role_id} -> {:ok, user_id, role_id}
    end
  end

  defp assign_role_to_user(user_id, role_id, creator_info, schema, tenant_alias) do
    %{created_by_id: assigned_by_id, created_by_type: assigned_by_type} = creator_info

    Accounts.assign_role(
      user_id,
      role_id,
      assigned_by_id,
      assigned_by_type,
      schema,
      tenant_alias
    )
  end
end
