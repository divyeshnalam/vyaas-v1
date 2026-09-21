defmodule VyaasaCampus.Schema.Academics.TenantSpecialization do
  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tenant_specializations" do
    field :tenant_id, :binary_id
    field :specialization_id, :binary_id

    timestamps()
  end

  def changeset(ts, attrs) do
    ts
    |> cast(attrs, [:tenant_id, :specialization_id])
    |> validate_required([:tenant_id, :specialization_id])
    |> unique_constraint([:tenant_id, :specialization_id])
  end
end
