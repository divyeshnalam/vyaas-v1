defmodule VyaasaCampus.Contexts.Tenant.Locations do
  @moduledoc """
  Tenant location management context.
  Handles CRUD operations for tenant locations and primary location logic.
  """

  import Ecto.Query, warn: false
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Tenants.TenantLocation

  # === Location Management ===

  def list_tenant_locations(tenant_id) do
    from(l in TenantLocation, where: l.tenant_id == ^tenant_id)
    |> Repo.all(prefix: "public")
  end

  def get_tenant_location!(id) do
    Repo.get!(TenantLocation, id, prefix: "public")
  end

  def create_tenant_location(attrs \\ %{}) do
    %TenantLocation{}
    |> TenantLocation.changeset(attrs)
    |> Repo.insert(prefix: "public")
  end

  def update_tenant_location(%TenantLocation{} = location, attrs) do
    location
    |> TenantLocation.changeset(attrs)
    |> Repo.update(prefix: "public")
  end

  def delete_tenant_location(%TenantLocation{} = location) do
    Repo.delete(location, prefix: "public")
  end

  def set_primary_location(location_id, tenant_id) do
    Repo.transaction(fn ->
      # Unset all primary locations for this tenant
      from(l in TenantLocation, where: l.tenant_id == ^tenant_id)
      |> Repo.update_all([set: [is_primary: false]], prefix: "public")

      # Set the specified location as primary
      location = get_tenant_location!(location_id)
      update_tenant_location(location, %{is_primary: true})
    end)
  end

  def get_primary_location(tenant_id) do
    from(l in TenantLocation, where: l.tenant_id == ^tenant_id and l.is_primary == true)
    |> Repo.one(prefix: "public")
  end
end
