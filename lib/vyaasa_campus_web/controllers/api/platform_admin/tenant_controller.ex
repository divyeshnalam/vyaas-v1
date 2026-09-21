defmodule VyaasaCampusWeb.PlatformAdmin.TenantController do
  @moduledoc """
  Controller for managing tenant metadata and operations.

  This controller handles CRUD operations for tenants including:
  - Tenant creation with schema generation
  - Tenant status management (active/inactive)
  - Tenant metadata updates
  - Tenant deletion with complete data cleanup

  ## Authentication
  All operations require platform admin authentication.

  ## Error Handling
  Returns consistent JSON error responses with appropriate HTTP status codes.
  """

  use VyaasaCampusWeb, :controller

  import VyaasaCampusWeb.Shared.ErrorHandler,
    except: [format_changeset_errors: 1, validate_uuid: 1, handle_validation_error: 2]

  alias VyaasaCampus.Contexts.Tenants

  @doc """
  Lists all tenants on the platform /api/tenants
  """
  def index(conn, _params) do
    tenants = Tenants.list_tenants()
    json(conn, tenants)
  end

  @doc """
  Shows a specific tenant by ID /api/tenants/:id
  """
  def show(conn, %{"id" => id}) do
    tenant = Tenants.get_tenant!(id)
    json(conn, tenant)
  end

  @doc """
  Creates a new tenant with isolated schema /api/tenants
      {
        "tenant": {
          "full_name": "Cambridge University",
          "short_name": "Cambridge",
          "alias": "cambridge_uni",
          "affiliation_type": "university",
          "email": "info@cambridge.edu",
          "phone": "+1-555-0123",
          "website_url": "https://cambridge.edu"
        }
      }

  ## Required Fields
  - `alias` - Unique identifier for the tenant
  - `full_name` - Complete institution name
  - `short_name` - Short display name
  - `affiliation_type` - Type of institution
  - `email` - Contact email

  ## Response
  Returns the created tenant with schema name on success.
  """
  def create(conn, %{"tenant" => tenant_params}) do
    current_user = conn.assigns.current_user
    tenant_params_with_creator = Map.put(tenant_params, "created_by", current_user.id)

    case Tenants.create_tenant(tenant_params_with_creator) do
      {:ok, tenant} ->
        conn
        |> put_status(:created)
        |> json(%{
          tenant: tenant,
          message: "Tenant created successfully with schema: #{tenant.schema_name}"
        })

      {:error, :tenant_already_exists} ->
        handle_tenant_error(
          conn,
          :tenant_already_exists,
          tenant_params["alias"],
          "A tenant with this alias already exists"
        )

      {:error, changeset} ->
        handle_validation_error(
          conn,
          changeset,
          "Failed to create tenant due to validation errors"
        )
    end
  end

  @doc """
  Updates an existing tenant's metadata /api/tenants/:id

      {
        "tenant": {
          "full_name": "Updated University Name",
          "email": "new@email.edu"
        }
      }
  """
  def update(conn, %{"id" => id, "tenant" => tenant_params}) do
    tenant = Tenants.get_tenant!(id)

    case Tenants.update_tenant(tenant, tenant_params) do
      {:ok, updated_tenant} ->
        json(conn, updated_tenant)

      {:error, changeset} ->
        handle_validation_error(
          conn,
          changeset,
          "Failed to update tenant due to validation errors"
        )
    end
  end

  @doc """
  Deletes a tenant and all associated data /api/tenants/:id

  This operation:
  - Drops the tenant's database schema
  - Removes all tenant-specific data
  - Deletes tenant metadata
  - Removes all associated locations

  **Warning**: This action is irreversible.
  """
  def delete(conn, %{"id" => id}) do
    tenant = Tenants.get_tenant!(id)

    case Tenants.delete_tenant(tenant) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end

  @doc """
  Activates a tenant /api/tenants/:id/activate

  Changes tenant status to "active" and enables all operations.
  """
  def activate(conn, %{"id" => id}) do
    tenant = Tenants.get_tenant!(id)

    case Tenants.activate_tenant(tenant) do
      {:ok, updated_tenant} ->
        json(conn, updated_tenant)

      {:error, changeset} ->
        handle_validation_error(
          conn,
          changeset,
          "Failed to activate tenant due to validation errors"
        )
    end
  end

  @doc """
  Deactivates a tenant /api/tenants/:id/deactivate

  Changes tenant status to "inactive" and disables operations.
  """
  def deactivate(conn, %{"id" => id}) do
    tenant = Tenants.get_tenant!(id)

    case Tenants.deactivate_tenant(tenant) do
      {:ok, updated_tenant} ->
        json(conn, updated_tenant)

      {:error, changeset} ->
        handle_validation_error(
          conn,
          changeset,
          "Failed to deactivate tenant due to validation errors"
        )
    end
  end
end
