defmodule VyaasaCampus.Repo.Migrations.CreateTenantEntitlements do
  use Ecto.Migration

  @moduledoc """
  Generic per-tenant quotas, keyed by string so new entitlements need no schema
  change.

  First use is assessment attempt caps (`attempts.default` plus optional
  `attempts.<module>` overrides). Seat counts, AI credits and feature flags slot
  in later under their own keys, and a subscription plan simply writes rows here.

  `value` NULL means **unlimited** — which is also the behaviour when no row
  exists, so tenants are unaffected until a limit is configured.
  """

  def change do
    create table(:tenant_entitlements, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :value, :integer
      add :updated_by_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenant_entitlements, [:tenant_id, :key])
    create index(:tenant_entitlements, [:key])
  end
end
