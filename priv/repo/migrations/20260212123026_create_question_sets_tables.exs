defmodule VyaasaCampus.Repo.Migrations.CreateQuestionSetsTables do
  use Ecto.Migration

  def up do
    # Question Sets table - stores generated assessment question sets
    create_if_not_exists table(:question_sets) do
      add :name, :string, null: false, size: 255
      add :curricula_id, :integer
      add :branch_id, :integer
      add :total_questions, :integer, default: 20
      add :easy_percentage, :decimal, precision: 5, scale: 2, default: 0.40
      add :medium_percentage, :decimal, precision: 5, scale: 2, default: 0.40
      add :hard_percentage, :decimal, precision: 5, scale: 2, default: 0.20
      add :duration_minutes, :integer, default: 60
      add :metadata, :map  # JSONB for additional data

      timestamps()
    end

    create_if_not_exists index(:question_sets, [:curricula_id])
    create_if_not_exists index(:question_sets, [:branch_id])
    create_if_not_exists index(:question_sets, [:inserted_at])

    # Question Set Items table - links question sets to specific questions
    create_if_not_exists table(:question_set_items) do
      add :question_set_id, references(:question_sets, on_delete: :delete_all), null: false
      add :qa_id, :integer, null: false
      add :display_order, :integer, default: 0
      add :marks, :decimal, precision: 5, scale: 2, default: 1.0

      timestamps()
    end

    create_if_not_exists index(:question_set_items, [:question_set_id])
    create_if_not_exists index(:question_set_items, [:qa_id])
    create_if_not_exists unique_index(:question_set_items, [:question_set_id, :qa_id])
    create_if_not_exists index(:question_set_items, [:display_order])

    # User Question History table - tracks student performance on questions
    create_if_not_exists table(:user_question_history) do
      add :user_id, :binary_id, null: false
      add :qa_id, :integer, null: false
      add :attempted_at, :utc_datetime, null: false
      add :is_correct, :boolean, default: false
      add :score, :decimal, precision: 5, scale: 2, default: 0.0
      add :time_taken_seconds, :integer
      add :selected_option, :string
      add :metadata, :map  # JSONB for additional data

      timestamps()
    end

    create_if_not_exists index(:user_question_history, [:user_id])
    create_if_not_exists index(:user_question_history, [:qa_id])
    create_if_not_exists index(:user_question_history, [:attempted_at])
    create_if_not_exists index(:user_question_history, [:user_id, :qa_id])

    # Subject Requirements table - defines required subjects for curricula
    create_if_not_exists table(:subject_requirements) do
      add :subject_id, references(:subjects, on_delete: :delete_all), null: false
      add :curricula_id, references(:curricula, on_delete: :delete_all), null: false
      add :is_required, :boolean, default: false
      add :min_questions, :integer, default: 0
      add :weightage_multiplier, :decimal, precision: 5, scale: 2, default: 1.0

      timestamps()
    end

    create_if_not_exists index(:subject_requirements, [:subject_id])
    create_if_not_exists index(:subject_requirements, [:curricula_id])
    create_if_not_exists unique_index(:subject_requirements, [:subject_id, :curricula_id])

    # Topic Requirements table - defines required topics for subjects
    create_if_not_exists table(:topic_requirements) do
      add :topic_id, references(:topics, on_delete: :delete_all), null: false
      add :subject_id, references(:subjects, on_delete: :delete_all), null: false
      add :is_required, :boolean, default: false
      add :min_questions, :integer, default: 0

      timestamps()
    end

    create_if_not_exists index(:topic_requirements, [:topic_id])
    create_if_not_exists index(:topic_requirements, [:subject_id])
    create_if_not_exists unique_index(:topic_requirements, [:topic_id, :subject_id])
  end

  def down do
    drop_if_exists table(:topic_requirements)
    drop_if_exists table(:subject_requirements)
    drop_if_exists table(:user_question_history)
    drop_if_exists table(:question_set_items)
    drop_if_exists table(:question_sets)
  end
end
