defmodule VyaasaCampus.Repo.Migrations.CreateJamSessions do
  use Ecto.Migration

  def change do
    create table(:jam_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :student_id, :binary_id, null: false
      add :tenant_id, :binary_id, null: false

      # Session management
      add :session_token, :string, null: false
      add :status, :string, null: false, default: "created"

      # Topic information
      add :topic_title, :text
      add :topic_explanation, :text
      add :topic_changed, :boolean, default: false
      add :change_topic_available, :boolean, default: true

      # Audio and recording
      add :recording_file_path, :text
      add :recording_duration_seconds, :integer
      add :recording_active, :boolean, default: false

      # Speech processing
      add :transcript, :text
      add :word_count, :integer
      add :speech_duration_seconds, :integer

      # AI Evaluation (stored as JSON)
      add :evaluation_data, :map
      add :final_score, :integer # 0-100
      add :clarity_score, :integer # 1-10
      add :structure_score, :integer # 1-10
      add :relevance_score, :integer # 1-10
      add :impact_score, :integer # 1-10
      add :confidence_score, :integer # 1-10
      add :overall_summary, :text

      # Timing information
      add :decision_time_seconds, :integer, default: 60
      add :preparation_time_seconds, :integer, default: 15
      add :speech_time_seconds, :integer, default: 60
      add :actual_decision_time_used, :integer
      add :actual_preparation_time_used, :integer
      add :actual_speech_time_used, :integer

      # WebRTC and technical
      add :webrtc_connected, :boolean, default: false
      add :audio_quality_score, :decimal, precision: 3, scale: 2
      add :noise_level, :decimal, precision: 3, scale: 2

      # Error handling
      add :error_message, :text
      add :retry_count, :integer, default: 0

      # Timestamps
      add :created_at, :utc_datetime, null: false, default: fragment("NOW()")
      add :updated_at, :utc_datetime, null: false, default: fragment("NOW()")
      add :completed_at, :utc_datetime
    end

    create unique_index(:jam_sessions, [:session_token])
    create index(:jam_sessions, [:student_id])
    create index(:jam_sessions, [:tenant_id])
    create index(:jam_sessions, [:status])
    create index(:jam_sessions, [:created_at])
    create index(:jam_sessions, [:completed_at])
    create index(:jam_sessions, [:final_score])

    # Composite indexes for common queries
    create index(:jam_sessions, [:student_id, :tenant_id])
    create index(:jam_sessions, [:tenant_id, :status])
  end
end
