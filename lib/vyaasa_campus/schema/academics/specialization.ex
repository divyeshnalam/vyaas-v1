defmodule VyaasaCampus.Schema.Academics.Specialization do
  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: [:id, :name, :code, :degree_id, :is_active, :inserted_at, :updated_at]}

  schema "specializations" do
    field :name, :string
    field :code, :string
    field :is_active, :boolean, default: true

    belongs_to :degree, VyaasaCampus.Schema.Academics.Degree

    timestamps()
  end

  def changeset(spec, attrs) do
    spec
    |> cast(attrs, [:name, :code, :degree_id, :is_active])
    |> validate_required([:name, :code, :degree_id])
    |> validate_length(:name, max: 200)
    |> validate_length(:code, max: 50)
    |> foreign_key_constraint(:degree_id)
    |> unique_constraint([:degree_id, :code])
  end
end
