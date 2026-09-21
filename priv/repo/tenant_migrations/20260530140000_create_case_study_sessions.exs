defmodule VyaasaCampus.Repo.Migrations.CreateCaseStudySessions do
  use Ecto.Migration

  @moduledoc """
  Per-tenant table for AI-generated case-study attempts. Lives in each tenant
  schema like the other assessment result tables.
  """

  def change do
    create table(:case_study_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :student_id, :binary_id, null: false
      add :tenant_id, :binary_id

      add :session_token, :string, null: false
      add :status, :string, null: false, default: "in_progress"
      add :attempt_number, :integer, null: false, default: 1

      add :specialization_group, :string
      add :specialization_sub, :string

      add :scenario, :map
      add :answers, :map

      add :domain_score, :integer
      add :problem_solving_score, :integer
      add :leadership_score, :integer
      add :total_score, :integer
      add :report, :map

      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:case_study_sessions, [:session_token])
    create index(:case_study_sessions, [:student_id])
    create index(:case_study_sessions, [:status])
  end
end
