defmodule VyaasaCampus.Release do
  @moduledoc """
  Release-safe migration tasks — runnable **without Mix**, unlike
  `mix tenants.migrate`. In a production release:

      bin/vyaasa_campus eval "VyaasaCampus.Release.migrate()"

  `migrate/0` runs the shared/public migrations first, then every tenant
  schema's migrations, so application code can never ship ahead of the tenant
  DB schema (defect Vya-016: `column m0.submission_type does not exist`).

  Deploy should call `VyaasaCampus.Release.migrate()` after each build.
  """
  @app :vyaasa_campus

  require Logger

  @doc "Run public migrations, then all tenant-schema migrations."
  def migrate do
    load_app()
    migrate_public()
    migrate_all_tenants()
    :ok
  end

  @doc "Run the shared/public-schema migrations only."
  def migrate_public do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, public_migrations_path(), :up, all: true)
        end)
    end

    :ok
  end

  @doc "Run the tenant migrations across every tenant schema."
  def migrate_all_tenants do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          for schema <- tenant_schemas(repo) do
            Logger.info("Release.migrate | tenant schema=#{schema}")
            Ecto.Migrator.run(repo, tenant_migrations_path(), :up, all: true, prefix: schema)
          end
        end)
    end

    :ok
  end

  @doc "Run the tenant migrations for a single schema (e.g. \"tenant_bite\")."
  def migrate_tenant(schema) when is_binary(schema) do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, tenant_migrations_path(), :up, all: true, prefix: schema)
        end)
    end

    :ok
  end

  @doc "Roll a repo back to a specific public-migration version."
  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  # Every provisioned tenant's schema, read from the public tenants table.
  defp tenant_schemas(repo) do
    %{rows: rows} =
      repo.query!("SELECT schema_name FROM public.tenants WHERE schema_name IS NOT NULL")

    List.flatten(rows)
  end

  defp public_migrations_path, do: Application.app_dir(@app, "priv/repo/migrations")
  defp tenant_migrations_path, do: Application.app_dir(@app, "priv/repo/tenant_migrations")

  defp load_app, do: Application.load(@app)
end
