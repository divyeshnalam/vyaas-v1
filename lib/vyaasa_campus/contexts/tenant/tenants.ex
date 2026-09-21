defmodule VyaasaCampus.Contexts.Tenant.Tenants do
  @moduledoc """
  Core tenant management context.
  Handles tenant CRUD operations, schema creation/deletion, and status management.
  """

  import Ecto.Query, warn: false
  import VyaasaCampus.Types
  require Logger
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampus.Mail.EmailOrchestrator
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Tenants.Tenant

  @doc """
  Creates a new tenant with schema
  """
  def create_tenant(attrs \\ %{}) do
    alias = Map.fetch!(attrs, "alias")
    schema_name = "#{tenant_schema_prefix()}#{String.downcase(alias)}"

    if tenant_exists?(schema_name) do
      Logger.warning("Tenant creation failed - schema already exists: #{schema_name}")
      {:error, :tenant_already_exists}
    else
      with {:ok, _} <- Triplex.create(schema_name, Repo),
           :ok <- run_triplex_migrations(schema_name),
           {:ok, tenant} <- insert_tenant_record(attrs, schema_name) do
        Logger.info("Tenant created successfully: #{tenant.full_name} (#{tenant.alias})")
        DashboardEvents.broadcast_tenant_event(:created, tenant)
        {:ok, tenant}
      else
        {:error, reason} ->
          Logger.error("Tenant creation failed: #{inspect(reason)}")
          drop_tenant_schema(schema_name)
          {:error, reason}
      end
    end
  end

  @doc """
  Updates a tenant
  """
  def update_tenant(%Tenant{} = tenant, attrs) do
    safe_attrs = safe_atom_conversion(attrs)

    tenant
    |> Tenant.changeset(safe_attrs)
    |> Repo.update(prefix: public_schema())
    |> case do
      {:ok, updated_tenant} ->
        Logger.info("Tenant updated: #{updated_tenant.full_name}")
        DashboardEvents.broadcast_tenant_event(:updated, updated_tenant)
        {:ok, updated_tenant}

      {:error, changeset} ->
        Logger.error("Failed to update tenant: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Activates a tenant
  """
  def activate_tenant(%Tenant{} = tenant) do
    update_tenant(tenant, %{"status" => tenant_status_active()})
  end

  @doc """
  Deactivates a tenant
  """
  def deactivate_tenant(%Tenant{} = tenant) do
    update_tenant(tenant, %{"status" => tenant_status_inactive()})
  end

  @doc """
  Deletes a tenant and its schema
  """
  def delete_tenant(%Tenant{} = tenant) do
    Repo.transaction(fn ->
      with :ok <- drop_tenant_schema(tenant.schema_name),
           {:ok, deleted} <- Repo.delete(tenant, prefix: public_schema()) do
        Logger.info("Tenant deleted: #{deleted.full_name} (#{deleted.alias})")
        DashboardEvents.broadcast_tenant_event(:deleted, deleted)
        deleted
      else
        {:error, reason} ->
          Logger.error("Failed to delete tenant: #{inspect(reason)}")
          Repo.rollback(reason)

        err ->
          Logger.error("Failed to delete tenant with error: #{inspect(err)}")
          Repo.rollback(err)
      end
    end)
  end

  defp insert_tenant_record(attrs, schema_name) do
    tenant_data =
      attrs
      |> Map.put("schema_name", schema_name)
      |> Map.put_new("status", tenant_status_active())
      |> Map.put_new("settings", %{})
      |> Map.put("created_by", Map.get(attrs, "created_by"))

    try do
      case Tenant.changeset(%Tenant{}, tenant_data) |> Repo.insert(prefix: public_schema()) do
        {:ok, tenant} ->
          EmailOrchestrator.send_tenant_creation_email(tenant)
          {:ok, tenant}

        {:error, changeset} ->
          Logger.error("Failed to insert tenant record: #{inspect(changeset.errors)}")
          {:error, changeset}
      end
    rescue
      e ->
        Logger.error("Exception inserting tenant record: #{inspect(e)}")
        {:error, :db_error}
    end
  end

  defp run_triplex_migrations(schema_name) do
    Triplex.migrate(schema_name, Repo)
    Logger.info("Triplex migrations completed for schema: #{schema_name}")
    :ok
  rescue
    e ->
      Logger.error("Triplex migration failed for schema #{schema_name}: #{Exception.message(e)}")

      {:error, Exception.message(e)}
  end

  @doc """
  True if a tenant already exists for this alias/code (schema or DB record).
  Used by the Add College form for live inline validation before submit.
  """
  def alias_taken?(alias) when is_binary(alias) and alias != "" do
    tenant_exists?("#{tenant_schema_prefix()}#{String.downcase(alias)}")
  end

  def alias_taken?(_), do: false

  defp tenant_exists?(schema_name) do
    db_record = Repo.exists?(from t in Tenant, prefix: "public", where: t.schema_name == ^schema_name)
    db_record or postgres_schema_exists?(schema_name)
  end

  defp postgres_schema_exists?(schema_name) do
    case Repo.query("SELECT 1 FROM information_schema.schemata WHERE schema_name = $1", [schema_name]) do
      {:ok, %{rows: [_ | _]}} -> true
      _ -> false
    end
  end

  defp drop_tenant_schema(schema_name) do
    if valid_schema_name?(schema_name) do
      # DDL identifiers can't be parameterized — safe here because valid_schema_name? enforces [a-zA-Z][a-zA-Z0-9_-]
      Repo.query("DROP SCHEMA IF EXISTS \"#{schema_name}\" CASCADE", [])
      Logger.info("Dropped tenant schema: #{schema_name}")
      :ok
    else
      Logger.error("Invalid schema name provided: #{schema_name}")
      {:error, :invalid_schema_name}
    end
  end

  defp valid_schema_name?(schema_name) when is_binary(schema_name) do
    # Only allow alphanumeric characters, underscores, and hyphens
    # Must start with a letter and be reasonable length
    String.match?(schema_name, ~r/^[a-zA-Z][a-zA-Z0-9_-]{0,62}$/) and
      byte_size(schema_name) <= 63
  end

  defp valid_schema_name?(_), do: false

  @doc """
  Lists all tenants
  """
  def list_tenants, do: Repo.all(Tenant, prefix: public_schema())

  @doc """
  Lists active tenants only
  """
  def list_active_tenants do
    from(t in Tenant, where: t.status == ^tenant_status_active())
    |> Repo.all(prefix: public_schema())
  end

  @doc """
  Gets a tenant by ID, raises if not found
  """
  @spec get_tenant!(any()) :: any()
  def get_tenant!(id), do: Repo.get!(Tenant, id, prefix: public_schema())

  @doc """
  Gets a tenant by alias
  """
  def get_tenant_by_alias(alias) do
    normalized = alias |> to_string() |> String.downcase()
    from(t in Tenant, where: fragment("lower(?)", t.alias) == ^normalized)
    |> Repo.one(prefix: public_schema())
  end

  @doc """
  Gets a tenant by schema name
  """
  def get_tenant_by_schema_name(schema_name) do
    Repo.get_by(Tenant, [schema_name: schema_name], prefix: public_schema())
  end
end
