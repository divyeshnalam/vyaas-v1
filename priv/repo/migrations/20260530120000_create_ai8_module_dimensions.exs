defmodule VyaasaCampus.Repo.Migrations.CreateAi8ModuleDimensions do
  use Ecto.Migration

  @moduledoc """
  Global (super-admin managed) matrix of which AI8 skill dimensions each module
  evaluates. One row per (module, dimension). Lives in the public schema — the
  same config applies to all tenants. `weight` is nullable for now (weights are
  added later); until then aggregation treats enabled dimensions equally.
  """

  def change do
    create table(:ai8_module_dimensions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :module, :string, null: false
      add :dimension, :string, null: false
      add :enabled, :boolean, null: false, default: false
      add :weight, :decimal, precision: 6, scale: 3
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai8_module_dimensions, [:module, :dimension])
    create index(:ai8_module_dimensions, [:module])
  end
end
