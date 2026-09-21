defmodule VyaasaCampus.Repo.TenantMigrations.DropDuplicateQuestionBankTables do
  use Ecto.Migration

  @moduledoc """
  Drops duplicate question bank tables from tenant schemas.

  These tables were incorrectly created in tenant schemas by duplicate migrations.
  Question bank data (qa, topics, subjects, etc.) is global and lives only in the
  public schema. Only assessment_questions belongs in the tenant schema.
  """

  def up do
    # Drop in reverse dependency order
    drop_if_exists table(:topic_requirements)
    drop_if_exists table(:subject_requirements)
    drop_if_exists table(:user_question_history)
    drop_if_exists table(:question_set_items)
    drop_if_exists table(:question_sets)
    drop_if_exists table(:qa)
    drop_if_exists table(:topics)
    drop_if_exists table(:curricula_subjects)
    drop_if_exists table(:subjects)
    drop_if_exists table(:curricula)
    drop_if_exists table(:branches)
    drop_if_exists table(:qualifications)
  end

  def down do
    # No-op: we don't want to recreate these in tenant schemas
    :ok
  end
end
