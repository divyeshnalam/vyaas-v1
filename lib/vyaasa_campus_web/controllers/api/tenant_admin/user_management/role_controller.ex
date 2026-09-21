defmodule VyaasaCampusWeb.TenantAdmin.UserManagement.RoleController do
  @moduledoc """
  Controller for managing roles within tenant contexts.

  This controller handles CRUD operations for roles including:
  - Role creation and management
  - Role listing and retrieval
  - Authorization-based access control
  ## Authorization
  - Platform admins can create roles in any tenant
  - Tenant users can create roles in their own tenant only
  """

  use VyaasaCampusWeb, :controller
  import VyaasaCampusWeb.Shared.ControllerHelpers

  import VyaasaCampusWeb.Shared.ErrorHandler,
    except: [format_changeset_errors: 1, validate_uuid: 1, handle_validation_error: 2]

  alias VyaasaCampus.Contexts.Accounts
  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Guardian

  @doc """
  Lists all roles in the given tenant /api/tenant/roles
  """
  def index(conn, _params) do
    # Get tenant alias from header for validation
    case get_req_header(conn, "x-tenant") do
      [tenant_alias] ->
        case validate_tenant_access(conn, tenant_alias) do
          {:ok, schema} ->
            roles = Accounts.list_roles(schema)
            json(conn, roles)

          {:error, :unauthorized} ->
            handle_auth_error(conn, :unauthorized, "Authentication is required to access roles")

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
              "You do not have access to this tenant's roles"
            )

          {:error, :unknown_user_type} ->
            handle_authorization_error(
              conn,
              :forbidden,
              "Unknown user type - access denied to roles"
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
  Shows a specific role in the given tenant /api/tenant/roles/:id
  """
  def show(conn, %{"id" => id}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, _uuid} <- validate_uuid(id) do
      role = Accounts.get_role!(id, schema)
      json(conn, role)
    else
      {:error, :invalid_uuid} ->
        handle_parameter_error(
          conn,
          ["valid UUID"],
          "The provided ID is not a valid UUID format"
        )

      {:error, :unauthorized} ->
        handle_auth_error(conn, :unauthorized, "Authentication is required to access roles")

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
          "You do not have access to this tenant's roles"
        )

      {:error, :unknown_user_type} ->
        handle_authorization_error(
          conn,
          :forbidden,
          "Unknown user type - access denied to roles"
        )

      {:error, :missing_tenant_header} ->
        handle_tenant_error(
          conn,
          :tenant_header_required,
          nil,
          "The 'x-tenant' header is required for this operation"
        )
    end
  end

  @doc """
  Creates a role in the given tenant /api/tenant/roles
  only platform admins can create roles in any tenant and tenant users can create roles in their own tenant only
  """
  def create(conn, %{"role" => role_params}) do
    current_user = conn.assigns.current_user
    user_type = Guardian.get_user_type(current_user)

    case {user_type, can_create_role_in_tenant?(current_user, conn)} do
      {"admin", true} ->
        tenant_schema = get_tenant_schema_from_jwt(conn)
        create_role_in_tenant(role_params, conn, tenant_schema)

      {"user", true} ->
        tenant_schema = get_tenant_schema_from_jwt(conn)
        create_role_in_tenant(role_params, conn, tenant_schema)

      _ ->
        handle_authorization_error(
          conn,
          :forbidden,
          "You are not authorized to create roles in this tenant"
        )
    end
  end

  # === Private Functions ===

  defp can_create_role_in_tenant?(user, conn) do
    user_type = Guardian.get_user_type(user)

    cond do
      user_type == "admin" ->
        true

      user_type == "user" ->
        with [tenant_alias] <- get_req_header(conn, "x-tenant"),
             %{id: tenant_id} <- Tenants.get_tenant_by_alias(tenant_alias) do
          user.tenant_id == tenant_id
        else
          _ -> false
        end

      true ->
        false
    end
  end

  defp create_role_in_tenant(role_params, conn, schema) do
    role_params_with_creator = add_creator_info(role_params, conn)

    # Add tenant_id from the tenant header
    tenant_id =
      case get_req_header(conn, "x-tenant") do
        [tenant_alias] ->
          case Tenants.get_tenant_by_alias(tenant_alias) do
            nil -> nil
            tenant -> tenant.id
          end

        _ ->
          nil
      end

    role_params_with_tenant = Map.put(role_params_with_creator, "tenant_id", tenant_id)

    # Validate required fields
    required_fields = ["name", "display_name", "tenant_id"]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        is_nil(Map.get(role_params_with_tenant, field)) or
          Map.get(role_params_with_tenant, field) == ""
      end)

    if length(missing_fields) > 0 do
      handle_parameter_error(
        conn,
        missing_fields,
        "The following required fields are missing: #{Enum.join(missing_fields, ", ")}"
      )
    else
      case Accounts.create_role(role_params_with_tenant, schema) do
        {:ok, role} ->
          json(conn, %{role: role, message: "Role created successfully"})

        {:error, changeset} ->
          handle_validation_error(
            conn,
            changeset,
            "Failed to create role due to validation errors"
          )
      end
    end
  end
end
