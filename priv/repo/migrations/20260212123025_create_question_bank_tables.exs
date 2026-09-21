defmodule VyaasaCampus.Repo.Migrations.CreateQuestionBankTables do
  use Ecto.Migration

  def up do
    # Qualifications table
    create table(:qualifications) do
      add :name, :string, null: false, size: 255
      add :graduation_level, :string, size: 100
      add :field_of_study, :string, size: 255

      timestamps()
    end

    create unique_index(:qualifications, [:name])

    # Branches table
    create table(:branches) do
      add :name, :string, null: false, size: 255
      add :specialization, :string, size: 255
      add :code, :string, size: 50
      add :qualification_id, references(:qualifications, on_delete: :delete_all)

      timestamps()
    end

    create index(:branches, [:qualification_id])

    # Curricula table
    create table(:curricula) do
      add :name, :string, null: false, size: 255
      add :code, :string, size: 50
      add :branch_id, references(:branches, on_delete: :delete_all)

      timestamps()
    end

    create index(:curricula, [:branch_id])

    # Subjects table
    create table(:subjects) do
      add :name, :string, null: false, size: 255
      add :code, :string, size: 50
      add :credits, :integer, default: 0

      timestamps()
    end

    # Curricula-Subjects junction table
    create table(:curricula_subjects, primary_key: false) do
      add :curricula_id, references(:curricula, on_delete: :delete_all), null: false
      add :subject_id, references(:subjects, on_delete: :delete_all), null: false
      add :branch_id, references(:branches, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:curricula_subjects, [:curricula_id])
    create index(:curricula_subjects, [:subject_id])
    create index(:curricula_subjects, [:branch_id])
    create unique_index(:curricula_subjects, [:curricula_id, :subject_id, :branch_id])

    # Topics table
    create table(:topics) do
      add :name, :string, null: false, size: 255
      add :type, :string, size: 100
      add :weightage, :decimal, precision: 5, scale: 2, default: 0.0
      add :subject_id, references(:subjects, on_delete: :delete_all)

      timestamps()
    end

    create index(:topics, [:subject_id])

    # QA (Questions & Answers) table
    create table(:qa) do
      add :question, :text, null: false
      add :answer, :text
      add :difficulty_level, :string, size: 100
      add :options, :map  # JSONB in PostgreSQL
      add :type, :string, size: 50, default: "multiple_choice"
      add :weightage, :decimal, precision: 5, scale: 2, default: 1.0
      add :topic_id, references(:topics, on_delete: :delete_all)

      timestamps()
    end

    create index(:qa, [:topic_id])
    create index(:qa, [:difficulty_level])
    create index(:qa, [:type])

    # Assessment Questions junction table (links assessments to QA)
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

  def down do
    drop table(:assessment_questions)
    drop table(:qa)
    drop table(:topics)
    drop table(:curricula_subjects)
    drop table(:subjects)
    drop table(:curricula)
    drop table(:branches)
    drop table(:qualifications)
  end
end
