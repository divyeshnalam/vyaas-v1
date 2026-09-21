defmodule VyaasaCampus.Schema.AI8.ModuleDimension do
  @moduledoc """
  One cell of the global super-admin matrix: whether `module` evaluates
  `dimension`, plus its (later) weight and display position.
  Lives in the public schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias VyaasaCampus.AI8.{Dimensions, Modules}

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "ai8_module_dimensions" do
    field :module, :string
    field :dimension, :string
    field :enabled, :boolean, default: false
    field :weight, :decimal
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:module, :dimension, :enabled, :weight, :position])
    |> validate_required([:module, :dimension])
    |> validate_inclusion(:module, Modules.string_keys())
    |> validate_inclusion(:dimension, Dimensions.string_keys())
    |> validate_number(:weight, greater_than_or_equal_to: 0)
    |> unique_constraint([:module, :dimension])
  end
end
