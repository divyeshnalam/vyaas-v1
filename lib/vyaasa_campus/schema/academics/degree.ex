defmodule VyaasaCampus.Schema.Academics.Degree do
  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: [:id, :name, :code, :is_active, :inserted_at, :updated_at]}

  schema "degrees" do
    field :name, :string
    field :code, :string
    field :is_active, :boolean, default: true

    has_many :specializations, VyaasaCampus.Schema.Academics.Specialization

    timestamps()
  end

  def changeset(degree, attrs) do
    degree
    |> cast(attrs, [:name, :code, :is_active])
    |> validate_required([:name, :code])
    |> validate_length(:name, max: 200)
    |> validate_length(:code, max: 50)
    |> unique_constraint(:code)
  end
end
