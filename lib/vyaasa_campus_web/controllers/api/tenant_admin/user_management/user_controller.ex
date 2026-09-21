defmodule VyaasaCampusWeb.TenantAdmin.UserManagement.UserController do
  @moduledoc """
  Controller for managing users within tenant contexts.

  This controller handles CRUD operations for users including:
  - User creation and management
  - User listing and retrieval
  - Authorization-based access control

  only platform admins can create users in any tenant and tenant users can create users in their own tenant only
  """

  use VyaasaCampusWeb, :controller
  import VyaasaCampusWeb.Shared.ControllerHelpers

  import VyaasaCampusWeb.Shared.ErrorHandler,
    except: [format_changeset_errors: 1, validate_uuid: 1, handle_validation_error: 2]

  alias VyaasaCampus.Contexts.Accounts
  alias VyaasaCampus.Guardian

  @doc """
  Lists all users in the given tenant /api/tenant/users
  """
  def index(conn, _params) do
    # Get tenant alias from header
    case get_req_header(conn, "x-tenant") do
      [tenant_alias] ->
        case validate_tenant_access(conn, tenant_alias) do
          {:ok, schema} ->
            users = Accounts.list_users(schema)
            json(conn, users)

          {:error, :unauthorized} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Authentication required"})

          {:error, :tenant_not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Tenant not found"})

          {:error, :unknown_user_type} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})

          {:error, :access_denied} ->
            handle_authorization_error(conn, :tenant_access_denied)
        end

      _ ->
        handle_tenant_error(conn, :tenant_header_required, nil)
    end
  end

  @doc """
  Shows a specific user in the given tenant /api/tenant/users/:id
  """
  def show(conn, %{"id" => id}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, _uuid} <- validate_uuid(id) do
      conn |> json(Accounts.get_user!(id, schema))
    else
      {:error, :invalid_uuid} ->
        handle_parameter_error(
          conn,
          ["valid UUID"],
          "The provided ID is not a valid UUID format"
        )

      {:error, :unauthorized} ->
        handle_auth_error(
          conn,
          :unauthorized,
          "Authentication is required to access this resource"
        )

      {:error, :tenant_not_found} ->
        handle_tenant_error(
          conn,
          :tenant_not_found,
          nil,
          "The specified tenant was not found"
        )

      {:error, :unknown_user_type} ->
        handle_authorization_error(conn, :forbidden, "Unknown user type - access denied")

      {:error, :access_denied} ->
        handle_authorization_error(
          conn,
          :tenant_access_denied,
          "You do not have access to this tenant"
        )

      {:error, :missing_tenant_header} ->
        handle_tenant_error(conn, :tenant_header_required, nil)
    end
  end

  @doc """
  Creates a user in the given tenant /api/tenant/users
  """
  def create(conn, %{"user" => user_params}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         :ok <- validate_user_creation_permission(conn),
         {:ok, user} <- create_user_in_tenant(user_params, conn, schema) do
      safe_user = Map.drop(user, [:encrypted_password, :temp_password])
      handle_resource_success(conn, safe_user, "user", "created")
    else
      error -> handle_common_errors(conn, error)
    end
  end

  defp validate_user_creation_permission(conn) do
    current_user = get_current_user(conn)
    user_type = Guardian.get_user_type(current_user)

    case {user_type, can_create_user_in_tenant?(current_user, conn)} do
      {"admin", true} -> :ok
      {"user", true} -> :ok
      _ -> {:error, :forbidden}
    end
  end

  # === Private Functions ===

  defp can_create_user_in_tenant?(user, conn) do
    user_type = Guardian.get_user_type(user)

    case user_type do
      # Platform admin can access any tenant
      "admin" ->
        true

      "user" ->
        # Check if we're in a tenant context (not public)
        case get_req_header(conn, "x-tenant") do
          # We're in a tenant context
          [_tenant_alias] -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp create_user_in_tenant(user_params, conn, schema) do
    with {:ok, user_params_with_creator} <- prepare_user_params(user_params, conn),
         {:ok, user_params_with_tenant} <- add_tenant_id_to_params(user_params_with_creator, conn),
         :ok <- validate_required_fields(user_params_with_tenant) do
      create_user_record(user_params_with_tenant, conn, schema)
    end
  end

  defp prepare_user_params(user_params, conn) do
    user_params_with_creator = add_creator_info(user_params, conn)
    {:ok, user_params_with_creator}
  end

  defp add_tenant_id_to_params(user_params_with_creator, conn) do
    with [tenant_alias] <- get_req_header(conn, "x-tenant"),
         {:ok, tenant_id} <- get_tenant_id_from_alias(tenant_alias) do
      user_params_with_tenant = Map.put(user_params_with_creator, "tenant_id", tenant_id)
      {:ok, user_params_with_tenant}
    else
      _ -> {:error, :tenant_not_found}
    end
  end

  defp validate_required_fields(user_params_with_tenant) do
    required_fields = ["email", "first_name", "last_name", "role", "tenant_id"]
    validate_required_fields(user_params_with_tenant, required_fields)
  end

  defp create_user_record(user_params_with_tenant, conn, schema) do
    tenant_alias = get_req_header(conn, "x-tenant") |> List.first()
    Accounts.create_user_with_temp_password(user_params_with_tenant, tenant_alias, schema)
  end
end
