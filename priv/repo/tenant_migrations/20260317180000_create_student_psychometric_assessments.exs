defmodule VyaasaCampus.Repo.TenantMigrations.CreateStudentPsychometricAssessments do
  use Ecto.Migration

  def change do
    create table(:student_psychometric_assessments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :student_id, references(:students, type: :binary_id, on_delete: :delete_all), null: false
      add :tenant_id, :binary_id, null: false

      # Session tracking
      add :session_id, :string, null: false
      add :request_id, :string
      add :status, :string, default: "started", null: false
      add :attempt_number, :integer, default: 1, null: false

      # Timing
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      # Big Five Factor Scores (1.0 - 5.0)
      add :openness_score, :float
      add :conscientiousness_score, :float
      add :extraversion_score, :float
      add :agreeableness_score, :float
      add :neuroticism_score, :float

      # AI Report (JSONB)
      add :overall_summary, :text
      add :factor_reports, :map
      add :strengths, {:array, :string}, default: []
      add :development_areas, {:array, :string}, default: []
      add :suggestions, {:array, :string}, default: []

      # Raw data
      add :factor_scores, :map
      add :raw_report_json, :map
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:student_psychometric_assessments, [:session_id])
    create unique_index(:student_psychometric_assessments, [:student_id, :attempt_number])
    create index(:student_psychometric_assessments, [:tenant_id])
    create index(:student_psychometric_assessments, [:student_id])
    create index(:student_psychometric_assessments, [:status])
    create index(:student_psychometric_assessments, [:completed_at])
  end
end
