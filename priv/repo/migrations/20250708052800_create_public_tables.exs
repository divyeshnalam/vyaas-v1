defmodule VyaasaCampus.Repo.Migrations.CreatePublicTables do
  use Ecto.Migration

  def change do
    # This is main platform "SuperUsers" table
    create table(:platform_admins, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :email, :string, null: false
      add :encrypted_password, :string, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :role, :string, null: false
      add :status, :string, default: "active"
      add :last_login_at, :utc_datetime
      add :password_reset_token, :string
      add :password_reset_sent_at, :utc_datetime
      add :metadata, :map, default: %{}
      # Refresh token support
      add :refresh_token_hash, :string
      add :refresh_token_expires_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:platform_admins, [:email])

    create table(:tenants, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :full_name, :string, null: false
      add :short_name, :string, null: false
      add :alias, :string, null: false
      add :schema_name, :string, null: false
      add :affiliation_type, :string, null: false
      add :email, :string
      add :phone, :string
      add :website_url, :string
      add :logo_url, :text
      add :status, :string, default: "active"
      add :settings, :map, default: %{}
      add :created_by, references(:platform_admins, type: :uuid)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:alias])
    create unique_index(:tenants, [:schema_name])

    # Helpful index for admin refresh lookup
    create index(:platform_admins, [:refresh_token_hash])

    # This is the tenant locations table only after a tenant has been created by the super user (by id) and tenant specific tables have been created after only we can add thier locations
    create table(:tenant_locations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, references(:tenants, type: :uuid, on_delete: :delete_all)
      add :name, :string, null: false
      add :address, :text
      add :city, :string
      add :state, :string
      add :pincode, :string
      add :is_primary, :boolean, default: false
      timestamps(type: :utc_datetime)
    end
  end
end
