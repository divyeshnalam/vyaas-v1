defmodule VyaasaCampus.Repo.TenantMigrations.CreateAssessmentQuestions do
  use Ecto.Migration

  @moduledoc """
  Creates assessment_questions in the tenant schema.

  This is a junction table linking tenant-specific assessments to global
  questions (qa) in the public schema. qa_id references public.qa(id)
  as questions are shared across all tenants.
  """

  def up do
    # Drop the old table if it exists from a previous duplicate migration
    # (it lacked proper FK constraints and had wrong qa_id type)
    drop_if_exists table(:assessment_questions)

    create table(:assessment_questions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :assessment_id, references(:assessments, type: :binary_id, on_delete: :delete_all), null: false
      add :qa_id, :integer, null: false
      add :question_order, :integer
      add :marks, :integer, default: 1

      timestamps()
    end

    create index(:assessment_questions, [:assessment_id])
    create index(:assessment_questions, [:qa_id])
    create unique_index(:assessment_questions, [:assessment_id, :qa_id])
  end

  def down do
    drop table(:assessment_questions)
  end
end
