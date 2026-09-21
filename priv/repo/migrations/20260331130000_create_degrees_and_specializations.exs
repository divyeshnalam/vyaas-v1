defmodule VyaasaCampus.Repo.Migrations.CreateDegreesAndSpecializations do
  use Ecto.Migration

  def change do
    # Degrees (managed by super admin, shared across all tenants)
    create table(:degrees, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :code, :string, null: false
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:degrees, [:code])

    # Specializations belong to a degree (managed by super admin)
    create table(:specializations, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :code, :string, null: false
      add :degree_id, references(:degrees, type: :binary_id, on_delete: :delete_all), null: false
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:specializations, [:degree_id, :code])
    create index(:specializations, [:degree_id])

    # Tenant-selected degrees (which degrees a tenant offers)
    create table(:tenant_degrees, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :degree_id, references(:degrees, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenant_degrees, [:tenant_id, :degree_id])
    create index(:tenant_degrees, [:tenant_id])

    # Tenant-selected specializations
    create table(:tenant_specializations, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :specialization_id, references(:specializations, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenant_specializations, [:tenant_id, :specialization_id])
    create index(:tenant_specializations, [:tenant_id])
  end
end
