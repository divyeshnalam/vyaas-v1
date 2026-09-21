defmodule VyaasaCampus.Contexts.Tenants do
  @moduledoc """
  Multi-tenant context for managing tenant schemas and metadata.
  Uses Triplex for schema creation and Ecto for operations.

  This module provides backward compatibility and delegates to the new modular structure:
  - VyaasaCampus.Contexts.Tenant.Tenants - Core tenant management
  - VyaasaCampus.Contexts.Tenant.Locations - Location management  
  - VyaasaCampus.Contexts.Tenant.Schema - Schema operations
  """

  # Delegate to new modular structure for backward compatibility
  defdelegate list_tenants, to: VyaasaCampus.Contexts.Tenant.Tenants
  defdelegate list_active_tenants, to: VyaasaCampus.Contexts.Tenant.Tenants
  defdelegate get_tenant!(id), to: VyaasaCampus.Contexts.Tenant.Tenants
  defdelegate get_tenant_by_alias(alias), to: VyaasaCampus.Contexts.Tenant.Tenants
  defdelegate get_tenant_by_schema_name(schema_name), to: VyaasaCampus.Contexts.Tenant.Tenants
  defdelegate alias_taken?(alias), to: VyaasaCampus.Contexts.Tenant.Tenants
  defdelegate create_tenant(attrs), to: VyaasaCampus.Contexts.Tenant.Tenants
  defdelegate update_tenant(tenant, attrs), to: VyaasaCampus.Contexts.Tenant.Tenants
  defdelegate activate_tenant(tenant), to: VyaasaCampus.Contexts.Tenant.Tenants
  defdelegate deactivate_tenant(tenant), to: VyaasaCampus.Contexts.Tenant.Tenants
  defdelegate delete_tenant(tenant), to: VyaasaCampus.Contexts.Tenant.Tenants

  # Location management
  defdelegate list_tenant_locations(tenant_id), to: VyaasaCampus.Contexts.Tenant.Locations
  defdelegate get_tenant_location!(id), to: VyaasaCampus.Contexts.Tenant.Locations
  defdelegate create_tenant_location(attrs), to: VyaasaCampus.Contexts.Tenant.Locations
  defdelegate update_tenant_location(location, attrs), to: VyaasaCampus.Contexts.Tenant.Locations
  defdelegate delete_tenant_location(location), to: VyaasaCampus.Contexts.Tenant.Locations

  defdelegate set_primary_location(location_id, tenant_id),
    to: VyaasaCampus.Contexts.Tenant.Locations

  # Schema operations
  defdelegate query_in_tenant(schema_name, queryable), to: VyaasaCampus.Contexts.Tenant.Schema
  defdelegate get_in_tenant(schema_name, queryable, id), to: VyaasaCampus.Contexts.Tenant.Schema
  defdelegate insert_in_tenant(schema_name, changeset), to: VyaasaCampus.Contexts.Tenant.Schema
  defdelegate update_in_tenant(schema_name, changeset), to: VyaasaCampus.Contexts.Tenant.Schema
  defdelegate delete_in_tenant(schema_name, struct), to: VyaasaCampus.Contexts.Tenant.Schema
end
