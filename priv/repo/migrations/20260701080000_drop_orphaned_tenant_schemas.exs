defmodule VyaasaCampus.Repo.Migrations.DropOrphanedTenantSchemas do
  use Ecto.Migration

  # Drops Postgres schemas that were created during failed college provisioning
  # but have no corresponding row in the public.tenants table.
  # Safe: each schema is checked against tenants before dropping.

  @orphaned ~w(tenant_qatest tenant_qatest1 tenant_qatest2 tenant_qatest3 tenant_rqr tenant_yuh)

  def up do
    for schema <- @orphaned do
      # Only drop if there is no tenant row pointing to this schema
      %{rows: rows} =
        repo().query!(
          "SELECT 1 FROM public.tenants WHERE schema_name = $1 LIMIT 1",
          [schema]
        )

      if rows == [] do
        repo().query!("DROP SCHEMA IF EXISTS \"#{schema}\" CASCADE")
        execute("SELECT 1")  # no-op to satisfy Ecto
      end
    end
  end

  def down do
    # Irreversible — orphaned schemas are gone; no data to restore.
    :ok
  end
end
