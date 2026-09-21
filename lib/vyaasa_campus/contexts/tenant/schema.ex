defmodule VyaasaCampus.Contexts.Tenant.Schema do
  @moduledoc """
  Tenant schema operations context.
  Provides low-level database operations within tenant schemas.
  """

  alias VyaasaCampus.Repo

  # === Tenant Schema Operations ===

  def query_in_tenant(schema_name, queryable) do
    Repo.all(queryable, prefix: schema_name)
  end

  def get_in_tenant(schema_name, queryable, id) do
    Repo.get(queryable, id, prefix: schema_name)
  end

  def get_by_in_tenant(schema_name, queryable, attrs) do
    Repo.get_by(queryable, attrs, prefix: schema_name)
  end

  def insert_in_tenant(schema_name, changeset) do
    Repo.insert(changeset, prefix: schema_name)
  end

  def update_in_tenant(schema_name, changeset) do
    Repo.update(changeset, prefix: schema_name)
  end

  def delete_in_tenant(schema_name, struct) do
    Repo.delete(struct, prefix: schema_name)
  end

  def update_all_in_tenant(schema_name, queryable, updates) do
    Repo.update_all(queryable, updates, prefix: schema_name)
  end

  def exists_in_tenant?(schema_name, queryable) do
    Repo.exists?(queryable, prefix: schema_name)
  end

  def aggregate_in_tenant(schema_name, queryable, aggregate, field) do
    Repo.aggregate(queryable, aggregate, field, prefix: schema_name)
  end

  def transaction_in_tenant(schema_name, fun) do
    Repo.transaction(fun, prefix: schema_name)
  end
end
