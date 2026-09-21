defmodule VyaasaCampus.Repo.Migrations.CreateAi8DimensionWeights do
  use Ecto.Migration

  @moduledoc """
  Global (super-admin managed) weight of each AI8 skill dimension in the overall
  AI8 Index. One row per dimension; weights are percentages that should sum to
  100. Public schema — the same global weighting applies to all tenants.

  Distinct from `ai8_module_dimensions` (per-module weights): those decide each
  module's own score; these decide how the 8 dimensions roll up into the single
  AI8 Index / assessment index shown on the AI8 Overview.
  """

  def change do
    create table(:ai8_dimension_weights, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :dimension, :string, null: false
      add :weight, :decimal, precision: 6, scale: 3
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai8_dimension_weights, [:dimension])
  end
end
