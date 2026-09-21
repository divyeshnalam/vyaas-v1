defmodule VyaasaCampus.Repo.Migrations.DropAssessmentQuestionsFromPublic do
  use Ecto.Migration

  @moduledoc """
  Removes assessment_questions from the public schema.

  assessment_questions is a junction table between tenant-specific assessments
  and global questions (qa). Since assessments live in tenant schemas,
  this table must also live in tenant schemas. The qa table remains in
  the public schema as questions are global.
  """

  def up do
    drop_if_exists table(:assessment_questions)
  end

  def down do
    create table(:assessment_questions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :assessment_id, :binary_id, null: false
      add :qa_id, :bigint, null: false
      add :question_order, :integer
      add :marks, :integer, default: 1

      timestamps()
    end

    create index(:assessment_questions, [:assessment_id])
    create index(:assessment_questions, [:qa_id])
    create unique_index(:assessment_questions, [:assessment_id, :qa_id])
  end
end
