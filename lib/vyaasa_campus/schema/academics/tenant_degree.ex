defmodule VyaasaCampus.Schema.Academics.TenantDegree do
  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tenant_degrees" do
    field :tenant_id, :binary_id
    field :degree_id, :binary_id

    timestamps()
  end

  def changeset(td, attrs) do
    td
    |> cast(attrs, [:tenant_id, :degree_id])
    |> validate_required([:tenant_id, :degree_id])
    |> unique_constraint([:tenant_id, :degree_id])
  end
end
