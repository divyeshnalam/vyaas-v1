defmodule VyaasaCampusWeb.PlatformAdmin.TenantLocationController do
  @moduledoc """
  Controller for managing tenant locations.

  This controller handles CRUD operations for tenant locations including:
  - Location creation and management
  - Primary location designation
  - Location updates and deletion

    only platform admins can create locations in any tenant
  """

  use VyaasaCampusWeb, :controller
  alias VyaasaCampus.Contexts.Tenants

  @doc """
  Lists all locations for a tenant /api/platform_admin/locations
  Uses x-tenant header for tenant resolution
  """
  def index(conn, _params) do
    # Get tenant from x-tenant header
    tenant_alias =
      case get_req_header(conn, "x-tenant") do
        [alias] -> alias
        _ -> nil
      end

    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Tenant not found"})

      tenant ->
        locations = Tenants.list_tenant_locations(tenant.id)
        json(conn, locations)
    end
  end

  @doc """
  Shows a specific location /api/tenants/:tenant_id/locations/:id
  """
  def show(conn, %{"id" => id}) do
    location = Tenants.get_tenant_location!(id)
    json(conn, location)
  end

  @doc """
  Creates a new location for a tenant /api/platform_admin/locations
  Uses x-tenant header for tenant resolution - only platform admins can create locations in any tenant
  """
  def create(conn, %{"location" => location_params}) do
    # Get tenant from x-tenant header
    tenant_alias =
      case get_req_header(conn, "x-tenant") do
        [alias] -> alias
        _ -> nil
      end

    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Tenant not found"})

      tenant ->
        location_params = Map.put(location_params, "tenant_id", tenant.id)

        case Tenants.create_tenant_location(location_params) do
          {:ok, location} ->
            conn
            |> put_status(:created)
            |> json(location)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{errors: translate_errors(changeset)})
        end
    end
  end

  @doc """
  Updates an existing location /api/tenants/:tenant_id/locations/:id
  """
  def update(conn, %{"id" => id, "location" => location_params}) do
    location = Tenants.get_tenant_location!(id)

    case Tenants.update_tenant_location(location, location_params) do
      {:ok, updated_location} ->
        json(conn, updated_location)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  @doc """
  Deletes a location /api/tenants/:tenant_id/locations/:id
  """
  def delete(conn, %{"id" => id}) do
    location = Tenants.get_tenant_location!(id)

    case Tenants.delete_tenant_location(location) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end

  @doc """
  Sets a location as primary for the tenant /api/platform_admin/locations/:id/set_primary
  Uses x-tenant header for tenant resolution - only platform admins can set a location as primary for the tenant
  """
  def set_primary(conn, %{"id" => location_id}) do
    # Get tenant from x-tenant header
    tenant_alias =
      case get_req_header(conn, "x-tenant") do
        [alias] -> alias
        _ -> nil
      end

    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Tenant not found"})

      tenant ->
        case Tenants.set_primary_location(location_id, tenant.id) do
          {:ok, _} ->
            send_resp(conn, :no_content, "")

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: reason})
        end
    end
  end

  # === Private Functions ===

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{" <> to_string(key) <> "}", to_string(value))
      end)
    end)
  end
end
