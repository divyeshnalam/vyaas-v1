defmodule VyaasaCampus.Repo.Migrations.CreateTenantSubscriptions do
  use Ecto.Migration

  @moduledoc """
  A tenant's subscription window.

  Short term this only defines the period that attempt allowances reset on — the
  super admin sets the window by hand and there is no billing. It exists now so
  reset semantics don't change when real subscriptions arrive; a plan will then
  populate `plan_key`, `status` and roll `period_start`/`period_end` forward.
  """

  def change do
    create table(:tenant_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :plan_key, :string, default: "custom", null: false
      add :status, :string, default: "active", null: false
      # NULL period = "count everything ever" (no reset).
      add :period_start, :utc_datetime
      add :period_end, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenant_subscriptions, [:tenant_id])
  end
end
