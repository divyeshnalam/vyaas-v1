defmodule VyaasaCampusWeb.Shared.ControllerHelpers do
  @moduledoc """
  Unified shared controller helpers following Phoenix 1.8 best practices.

  This module consolidates all shared controller functionality into a single,
  well-organized module to eliminate code duplication and improve maintainability.

  ## Features:
  - JWT token handling and user extraction
  - Tenant access validation and schema resolution
  - Parameter processing and validation
  - Standardized error responses
  - DateTime formatting utilities
  - Creator/updater information management
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Guardian
  alias VyaasaCampus.Schema.Accounts.User
  alias VyaasaCampus.Schema.Platform.AdminUser

  # ============================================================================
  # TENANT RESOLUTION AND VALIDATION
  # ============================================================================

  @doc """
  Gets tenant schema from request using consistent logic.

  Priority order:
  1. x-tenant header
  2. tenant query parameter
  3. subdomain (triplex_prefix)
  4. fallback to "public"
  """
  def get_tenant_schema_from_request(conn) do
    header_alias = get_req_header(conn, "x-tenant") |> List.first()
    alias_param = conn.params["tenant"]
    chosen_alias = header_alias || alias_param

    cond do
      is_binary(chosen_alias) ->
        get_tenant_schema_by_alias(chosen_alias)

      is_binary(conn.assigns[:triplex_prefix]) ->
        conn.assigns[:triplex_prefix]

      true ->
        "public"
    end
  end

  @doc """
  Gets tenant schema from JWT claims or header.
  Provides consistent tenant schema resolution logic.
  """
  def get_tenant_schema_from_jwt(conn) do
    case get_req_header(conn, "x-tenant") do
      [tenant_alias] ->
        case Tenants.get_tenant_by_alias(tenant_alias) do
          nil -> "public"
          tenant -> tenant.schema_name
        end

      _ ->
        # No tenant context - determine by user type
        case conn.assigns.current_user do
          nil -> "public"
          %AdminUser{} -> "public"
          _ -> "public"
        end
    end
  end

  @doc """
  Gets tenant alias from request headers or query parameters.
  """
  def get_tenant_alias_from_request(conn) do
    case get_req_header(conn, "x-tenant") do
      [tenant_alias] -> tenant_alias
      _ -> conn.params["tenant"]
    end
  end

  @doc """
  Extracts tenant alias from request header.
  Returns {:ok, tenant_alias} or {:error, :missing_tenant_header}
  """
  def get_tenant_alias_from_header(conn) do
    case get_req_header(conn, "x-tenant") do
      [tenant_alias] -> {:ok, tenant_alias}
      _ -> {:error, :missing_tenant_header}
    end
  end

  @doc """
  Gets tenant ID from tenant alias.
  Returns {:ok, tenant_id} or {:error, :tenant_not_found}
  """
  def get_tenant_id_from_alias(tenant_alias) do
    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil -> {:error, :tenant_not_found}
      tenant -> {:ok, tenant.id}
    end
  end

  @doc """
  Validate that the current user has access to the specified tenant.
  Returns {:ok, tenant_schema} if valid, {:error, reason} if not.

  Tenant isolation is enforced at the database schema level:
  - Each tenant has its own schema (e.g., tenant_ti17539425)
  - Users are stored in their respective tenant schemas
  - Platform admins can access any tenant
  - Regular users can only access their own tenant schema
  """
  def validate_tenant_access(conn, tenant_alias) do
    current_user = conn.assigns.current_user

    cond do
      is_nil(current_user) ->
        {:error, :unauthorized}

      match?(%AdminUser{}, current_user) ->
        validate_admin_tenant_access(tenant_alias)

      match?(%User{}, current_user) ->
        validate_user_tenant_access(current_user, tenant_alias)

      true ->
        {:error, :unknown_user_type}
    end
  end

  @doc """
  Derive tenant schema name from tenant UUID.
  Uses consistent naming: tenant_{first_8_chars_of_uuid}
  """
  def derive_tenant_schema(tenant_id) do
    "tenant_" <> String.downcase(String.slice(tenant_id, 0, 8))
  end

  # ============================================================================
  # USER AND AUTHENTICATION HELPERS
  # ============================================================================

  @doc """
  Gets current user from connection.
  """
  def get_current_user(conn) do
    conn.assigns.current_user
  end

  @doc """
  Gets user type from current user.
  """
  def get_current_user_type(conn) do
    conn
    |> get_current_user()
    |> Guardian.get_user_type()
  end

  @doc """
  Get current user ID from JWT claims.
  """
  def get_current_user_id(conn) do
    case conn.assigns[:creator_info] do
      %{created_by_id: id} -> id
      _ -> nil
    end
  end

  @doc """
  Adds creator information from authenticated user to params.
  It is used to track the creator of a record.
  """
  def add_creator_info(params, conn) do
    current_user = conn.assigns.current_user
    user_type = Guardian.get_user_type(current_user)

    # Map Guardian user types to schema creator types
    creator_type =
      case user_type do
        "admin" -> "public"
        "user" -> "tenant"
        "student" -> "tenant"
        _ -> "public"
      end

    Map.merge(params, %{
      "created_by_id" => current_user.id,
      "created_by_type" => creator_type
    })
  end

  @doc """
  Adds updater information from authenticated user to params.
  It is used to track who updated a record.
  """
  def add_updater_info(params, conn) do
    case conn.assigns[:creator_info] do
      %{created_by_id: id, created_by_type: type} ->
        params
        |> Map.put("updated_by_id", id)
        |> Map.put("updated_by_type", type)
        |> Map.put("updated_by", id)

      _ ->
        params
    end
  end

  # ============================================================================
  # VALIDATION HELPERS
  # ============================================================================

  @doc """
  Validates UUID format.
  Returns {:ok, uuid} if valid, {:error, :invalid_uuid} otherwise.
  """
  def validate_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_uuid}
    end
  end

  @doc """
  Validates required fields in params.
  Returns :ok or {:error, :missing_fields, missing_fields}
  """
  def validate_required_fields(params, required_fields) do
    missing_fields =
      Enum.filter(required_fields, fn field ->
        is_nil(Map.get(params, field)) or Map.get(params, field) == ""
      end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, :missing_fields, missing_fields}
    end
  end

  # ============================================================================
  # ERROR RESPONSE HELPERS
  # ============================================================================

  @doc """
  Standardized error response for missing tenant header.
  """
  def handle_missing_tenant_header(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Tenant header is required"})
  end

  @doc """
  Standardized error response for unauthorized access.
  """
  def handle_unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Unauthorized access"})
  end

  @doc """
  Standardized error response for tenant not found.
  """
  def handle_tenant_not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Tenant not found"})
  end

  @doc """
  Standardized error response for access denied.
  """
  def handle_access_denied(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Access denied to this tenant"})
  end

  @doc """
  Standardized error response for unknown user type.
  """
  def handle_unknown_user_type(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Invalid user type"})
  end

  @doc """
  Standardized error response for resource not found.
  """
  def handle_resource_not_found(conn, resource_name \\ "Resource") do
    conn
    |> put_status(:not_found)
    |> json(%{error: "#{resource_name} not found"})
  end

  @doc """
  Standardized error response for validation errors.
  """
  def handle_validation_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: format_changeset_errors(changeset)})
  end

  @doc """
  Formats Ecto changeset errors for JSON response.
  """
  def format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @doc """
  Handles missing fields error response.
  """
  def handle_missing_fields_error(conn, missing_fields) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "The following required fields are missing: #{Enum.join(missing_fields, ", ")}"
    })
  end

  @doc """
  Standardized success response with message.
  """
  def handle_success(conn, data, message) do
    json(conn, Map.merge(data, %{message: message}))
  end

  @doc """
  Standardized success response for resource operations.
  """
  def handle_resource_success(conn, resource, resource_name, action) do
    handle_success(conn, %{resource_name => resource}, "#{resource_name} #{action} successfully")
  end

  @doc """
  Standardized error handling for common controller patterns.
  """
  def handle_common_errors(conn, error) do
    error_handlers = %{
      {:error, :missing_tenant_header} => &handle_missing_tenant_header/1,
      {:error, :unauthorized} => &handle_unauthorized/1,
      {:error, :tenant_not_found} => &handle_tenant_not_found/1,
      {:error, :access_denied} => &handle_access_denied/1,
      {:error, :unknown_user_type} => &handle_unknown_user_type/1,
      {:error, :resource_not_found} => &handle_resource_not_found/1
    }

    case error do
      {:error, :missing_fields, missing_fields} ->
        handle_missing_fields_error(conn, missing_fields)

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        handle_validation_error(conn, changeset)

      {:error, reason} ->
        handle_unexpected_error(conn, reason)

      error_key when is_map_key(error_handlers, error_key) ->
        error_handlers[error_key].(conn)
    end
  end

  # ============================================================================
  # UTILITY FUNCTIONS
  # ============================================================================

  @doc """
  Formats datetime to IST (Indian Standard Time) for display.

  Converts UTC datetime to Asia/Kolkata timezone and returns as string.
  Returns nil if input is nil.
  """
  def format_datetime_ist(datetime) do
    case datetime do
      nil ->
        nil

      %DateTime{} = dt ->
        # Convert UTC to IST (UTC+5:30)
        dt
        |> DateTime.shift_zone!("Asia/Kolkata")
        |> DateTime.to_string()

      _ ->
        # Handle other datetime formats
        datetime
    end
  end

  @doc """
  Creates a standardized error response.
  """
  def error_response(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end

  @doc """
  Creates a standardized success response with optional data.
  """
  def success_response(conn, data \\ %{}) do
    json(conn, data)
  end

  # ============================================================================
  # PRIVATE HELPER FUNCTIONS
  # ============================================================================

  defp get_tenant_schema_by_alias(alias) do
    # Try exact match first, then uppercase match for case-insensitive lookup
    case Tenants.get_tenant_by_alias(alias) do
      nil ->
        case Tenants.get_tenant_by_alias(String.upcase(alias)) do
          nil -> "public"
          tenant -> tenant.schema_name
        end

      tenant ->
        tenant.schema_name
    end
  end

  defp validate_admin_tenant_access(tenant_alias) do
    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil -> {:error, :tenant_not_found}
      tenant -> {:ok, tenant.schema_name}
    end
  end

  defp validate_user_tenant_access(current_user, tenant_alias) do
    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil ->
        {:error, :tenant_not_found}

      tenant ->
        if current_user.tenant_id == tenant.id do
          {:ok, tenant.schema_name}
        else
          {:error, :access_denied}
        end
    end
  end

  defp handle_unexpected_error(conn, reason) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "An unexpected error occurred: #{inspect(reason)}"})
  end
end
