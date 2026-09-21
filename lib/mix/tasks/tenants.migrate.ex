defmodule Mix.Tasks.Tenants.Migrate do
  @moduledoc """
  Runs migrations for all tenant schemas.

  Usage:
      mix tenants.migrate
      mix tenants.migrate --tenant BITE
  """

  use Mix.Task
  require Logger

  @shortdoc "Runs migrations for tenant schemas"

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, _, _} = OptionParser.parse(args, switches: [tenant: :string])

    case Keyword.get(opts, :tenant) do
      nil ->
        # Migrate all tenants
        migrate_all_tenants()

      tenant_alias ->
        # Migrate specific tenant
        migrate_tenant(tenant_alias)
    end
  end

  defp migrate_all_tenants do
    tenants = VyaasaCampus.Contexts.Tenants.list_tenants()

    if Enum.empty?(tenants) do
      Mix.shell().info("No tenants found.")
    else
      Mix.shell().info("Found #{length(tenants)} tenant(s). Running migrations...")

      Enum.each(tenants, fn tenant ->
        Mix.shell().info("\n=== Migrating tenant: #{tenant.full_name} (#{tenant.schema_name}) ===")
        run_tenant_migrations(tenant.schema_name)
      end)

      Mix.shell().info("\n✅ All tenant migrations completed!")
    end
  end

  defp migrate_tenant(tenant_alias) do
    case VyaasaCampus.Contexts.Tenants.get_tenant_by_alias(String.upcase(tenant_alias)) do
      nil ->
        Mix.shell().error("Tenant with alias '#{tenant_alias}' not found.")

      tenant ->
        Mix.shell().info("=== Migrating tenant: #{tenant.full_name} (#{tenant.schema_name}) ===")
        run_tenant_migrations(tenant.schema_name)
        Mix.shell().info("\n✅ Tenant migration completed!")
    end
  end

  defp run_tenant_migrations(schema_name) do
    path = Application.app_dir(:vyaasa_campus, "priv/repo/tenant_migrations")

    Ecto.Migrator.run(
      VyaasaCampus.Repo,
      path,
      :up,
      all: true,
      prefix: schema_name
    )
  end
end
