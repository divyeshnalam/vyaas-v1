defmodule VyaasaCampus.Schema.Tenants.Entitlement do
  @moduledoc """
  A single per-tenant quota, keyed by string (public schema).

  `value` NULL means **unlimited**, which is also how a missing row behaves — so
  a tenant with no entitlements is unrestricted, exactly as before this feature.

  Keys in use:

    * `attempts.default`   — attempts allowed for any assessment
    * `attempts.<module>`  — override for one module (mcq, jam, interview,
      behavioral, psychometric, case_study, mini_project, resume)

  Future keys (`students.max`, `ai_credits.period`, `feature.*`) need no schema
  change; a subscription plan writes rows here.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :tenant_id, :key, :value, :inserted_at, :updated_at]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tenant_entitlements" do
    field :tenant_id, :binary_id
    field :key, :string
    field :value, :integer
    field :updated_by_id, :binary_id

    timestamps()
  end

  def changeset(entitlement, attrs) do
    entitlement
    |> cast(attrs, [:tenant_id, :key, :value, :updated_by_id])
    |> validate_required([:tenant_id, :key])
    |> validate_number(:value, greater_than_or_equal_to: 0)
    |> unique_constraint([:tenant_id, :key])
  end
end
