defmodule VyaasaCampus.Schema.AI8.ModuleEvaluation do
  @moduledoc """
  A single module's AI8 evaluation for a student attempt. Stored per tenant
  schema (queried with `prefix:`). `skill_scores` is a map of dimension key →
  raw 0–100 score for the dimensions that module was configured to evaluate.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias VyaasaCampus.AI8.Modules

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ai8_module_evaluations" do
    field :student_id, :binary_id
    field :tenant_id, :binary_id

    field :module, :string
    field :attempt_number, :integer, default: 1

    field :source_type, :string
    field :source_id, :binary_id

    field :skill_scores, :map, default: %{}
    field :dimensions_assessed, {:array, :string}, default: []
    field :module_score, :float

    field :raw_payload, :map, default: %{}

    field :status, :string, default: "completed"
    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(eval, attrs) do
    eval
    |> cast(attrs, [
      :student_id,
      :tenant_id,
      :module,
      :attempt_number,
      :source_type,
      :source_id,
      :skill_scores,
      :dimensions_assessed,
      :module_score,
      :raw_payload,
      :status,
      :completed_at
    ])
    |> validate_required([:student_id, :module])
    |> validate_inclusion(:module, Modules.string_keys())
    |> validate_number(:module_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint([:student_id, :module, :attempt_number])
  end
end
