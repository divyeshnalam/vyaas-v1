ExUnit.start()

# Prepare tenant schema and run tenant migrations once for tests, before sandbox
{:ok, _} = Application.ensure_all_started(:vyaasa_campus)

# Use Triplex to create and migrate tenant schema to reflect production behavior
tenant_name = "test"

try do
  # Create tenant schema
  Triplex.create(tenant_name, VyaasaCampus.Repo)
  Triplex.migrate(tenant_name, VyaasaCampus.Repo)
rescue
  exception ->
    IO.warn("Triplex setup failed: #{Exception.message(exception)}")
    IO.warn(Exception.format(:error, exception, __STACKTRACE__))
    # Fallback to direct Ecto migrator in case Triplex is unavailable in tests
    migrations_path = Application.app_dir(:vyaasa_campus, "priv/repo/tenant_migrations")
    tenant_schema = "tenant_#{tenant_name}"
    VyaasaCampus.Repo.query!("CREATE SCHEMA IF NOT EXISTS \"#{tenant_schema}\"")
    Ecto.Migrator.run(VyaasaCampus.Repo, migrations_path, :up, all: true, prefix: tenant_schema)
end

# Set sandbox mode to manual for better control
Ecto.Adapters.SQL.Sandbox.mode(VyaasaCampus.Repo, :manual)
