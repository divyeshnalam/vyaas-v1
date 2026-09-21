defmodule VyaasaCampus.Repo.Migrations.CreateAi8ModuleEvaluations do
  use Ecto.Migration

  @moduledoc """
  Per-student, per-module AI8 evaluation results (lives in each tenant schema,
  like the other assessment result tables).

  `skill_scores` holds the raw per-dimension scores (0–100) the LLM produced for
  the dimensions that module is configured to evaluate. `module_score` is the
  deterministically aggregated overall (0–100). `source_type`/`source_id` link
  back to the native result row (e.g. "jam_session" + its id) for traceability.
  """

  def change do
    create table(:ai8_module_evaluations, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :student_id, :binary_id, null: false
      add :tenant_id, :binary_id

      add :module, :string, null: false
      add :attempt_number, :integer, null: false, default: 1

      # Link back to the native module result row (polymorphic, optional).
      add :source_type, :string
      add :source_id, :binary_id

      # Raw per-dimension scores (0–100) + which dimensions were assessed.
      add :skill_scores, :map
      add :dimensions_assessed, {:array, :string}, null: false, default: []

      # Deterministic aggregate of skill_scores (0–100).
      add :module_score, :float

      # Full native engine output, for traceability/debugging.
      add :raw_payload, :map

      add :status, :string, null: false, default: "completed"
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai8_module_evaluations, [:student_id, :module, :attempt_number])
    create index(:ai8_module_evaluations, [:student_id])
    create index(:ai8_module_evaluations, [:module])
    create index(:ai8_module_evaluations, [:tenant_id])
  end
end
