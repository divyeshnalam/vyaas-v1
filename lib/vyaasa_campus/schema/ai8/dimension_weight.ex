defmodule VyaasaCampus.Schema.AI8.DimensionWeight do
  @moduledoc """
  Global weight of one AI8 skill dimension in the overall AI8 Index (percentage;
  the 8 should sum to 100). Lives in the public schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias VyaasaCampus.AI8.Dimensions

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "ai8_dimension_weights" do
    field :dimension, :string
    field :weight, :decimal
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:dimension, :weight, :position])
    |> validate_required([:dimension])
    |> validate_inclusion(:dimension, Dimensions.string_keys())
    |> validate_number(:weight, greater_than_or_equal_to: 0)
    |> unique_constraint(:dimension)
  end
end
