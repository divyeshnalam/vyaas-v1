defmodule VyaasaCampus.Repo.TenantMigrations.CreateStudentBehavioralAssessments do
  use Ecto.Migration

  def change do
    create table(:student_behavioral_assessments, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      # References
      add :student_id, references(:students, type: :uuid, on_delete: :delete_all), null: false
      add :tenant_id, :uuid, null: false

      # Session Tracking
      add :session_id, :string, null: false
      # started -> interviewing -> completed -> failed
      add :status, :string, default: "started", null: false

      # Timing
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      # Overall Score
      add :overall_score, :integer

      # Competency Ratings (individual columns for querying/sorting/filtering)
      add :work_ethics_score, :integer
      add :teamwork_score, :integer
      add :adaptability_score, :integer
      add :leadership_score, :integer
      add :communication_score, :integer

      # Detailed Analysis (flexible JSON)
      add :ratings, :map, default: %{}
      add :reasoning, :map, default: %{}
      add :summary, :text
      add :strengths, {:array, :string}, default: []
      add :areas_for_development, {:array, :string}, default: []

      # Scenario Responses
      add :completed_scenarios, {:array, :map}, default: []
      add :scenarios_completed_count, :integer, default: 0

      # Candidate Profile snapshot at assessment time
      add :candidate_profile, :map, default: %{}

      # Raw Data (for debugging/reprocessing)
      add :raw_report, :text
      add :raw_response_json, :map, default: %{}

      # Attempt tracking (supports re-assessments)
      add :attempt_number, :integer, default: 1

      # Future extensibility
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    # Unique session — one record per DS session
    create unique_index(:student_behavioral_assessments, [:session_id])

    # Unique per student per attempt
    create unique_index(:student_behavioral_assessments, [:student_id, :attempt_number])

    # Common query patterns
    create index(:student_behavioral_assessments, [:tenant_id])
    create index(:student_behavioral_assessments, [:status])
    create index(:student_behavioral_assessments, [:tenant_id, :status])
    create index(:student_behavioral_assessments, [:student_id])
    create index(:student_behavioral_assessments, [:overall_score])
    create index(:student_behavioral_assessments, [:completed_at])
  end
end
