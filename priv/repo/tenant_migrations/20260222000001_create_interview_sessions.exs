defmodule VyaasaCampus.Repo.Migrations.CreateInterviewSessions do
  use Ecto.Migration

  def change do
    create table(:interview_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :student_id, :binary_id, null: false
      add :tenant_id, :binary_id, null: false

      # Session management
      add :session_token, :string, null: false
      add :status, :string, null: false, default: "created"

      # Python service reference
      add :python_session_id, :string
      add :resume_url, :string
      add :resume_file_path, :string
      add :candidate_name, :string

      # Interview configuration
      add :max_questions, :integer, default: 5
      add :max_duration_minutes, :integer, default: 10

      # Questions and answers (stored as JSON)
      add :questions_data, :map, default: %{"questions" => []}

      # Overall results
      add :overall_score, :decimal, precision: 5, scale: 2
      add :final_report, :text
      add :session_summary, :map
      add :strengths, {:array, :string}, default: []
      add :improvements, {:array, :string}, default: []

      # Progress tracking
      add :current_question_number, :integer, default: 0
      add :questions_completed, :integer, default: 0
      add :remaining_time_seconds, :integer

      # Error handling
      add :error_message, :text
      add :retry_count, :integer, default: 0

      # Timestamps
      add :created_at, :utc_datetime, null: false, default: fragment("NOW()")
      add :updated_at, :utc_datetime, null: false, default: fragment("NOW()")
      add :completed_at, :utc_datetime
      add :started_at, :utc_datetime
    end

    create unique_index(:interview_sessions, [:session_token])
    create index(:interview_sessions, [:student_id])
    create index(:interview_sessions, [:tenant_id])
    create index(:interview_sessions, [:status])
    create index(:interview_sessions, [:python_session_id])
    create index(:interview_sessions, [:student_id, :tenant_id])
  end
end
