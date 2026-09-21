defmodule VyaasaCampus.Repo.TenantMigrations.CreateTenantTables do
  use Ecto.Migration

  def change do
    ## USERS
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :string, null: false
      add :encrypted_password, :string
      add :first_name, :string, null: false
      add :middle_name, :string
      add :last_name, :string, null: false
      add :phone, :string
      add :role, :string, null: false
      add :status, :string, default: "pending"
      add :email_verified_at, :utc_datetime
      add :last_login_at, :utc_datetime
      add :metadata, :map, default: %{}
      add :password_reset_token, :string
      add :password_reset_sent_at, :utc_datetime
      add :temp_password, :string
      add :temp_password_sent_at, :utc_datetime
      # Refresh token support per tenant user
      add :refresh_token_hash, :string
      add :refresh_token_expires_at, :utc_datetime
      # Tenant reference for proper isolation
      add :tenant_id, :uuid, null: false
      # Polymorphic creator reference: can be public or tenant user
      add :created_by_id, :uuid
      add :created_by_type, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:tenant_id, :email])
    create index(:users, [:refresh_token_hash])

    ## STUDENTS
    create table(:students, primary_key: false) do
      add :id, :uuid, primary_key: true

      # Basic Authentication & Contact Info (Required for semi-profile)
      add :email, :string, null: false
      add :encrypted_password, :string
      add :first_name, :string, null: false
      add :middle_name, :string
      add :last_name, :string, null: false
      add :phone, :string, null: false

      # Academic Information (Required for semi-profile)
      add :registration_id, :string, null: false
      add :degree, :string, null: false
      add :specialization, :string, null: false
      add :year_of_passing, :integer, null: false
      add :cgpa, :decimal, precision: 4, scale: 2, null: false

      # Additional Academic Info
      add :tenure, :string
      add :current_academic_year, :string
      add :location_id, :uuid

      add :status, :string, default: "pending" # pending -> profile_incomplete -> unverified -> verified -> active
      add :profile_completed, :boolean, default: false
      add :profile_submitted_at, :utc_datetime
      add :profile_approved_at, :utc_datetime
      add :profile_rejected_at, :utc_datetime
      add :profile_reviewed_at, :utc_datetime
      add :edit_requested_at, :utc_datetime
      add :approved_by_id, :uuid # References admin who approved/rejected
      add :admin_notes, :text # For approval/rejection feedback
      add :edit_request_notes, :text # Specific notes for what needs to be edited

      # Profile Completion Token (for multi-step onboarding)
      add :profile_token, :string
      add :profile_token_sent_at, :utc_datetime
      add :profile_token_expires_at, :utc_datetime

      # Profile Edit Request Fields (for active students)
      add :edit_request_data, :map, default: %{}
      add :edit_request_token, :string
      add :edit_request_token_expires_at, :utc_datetime

      # Authentication & Security
      add :email_verified_at, :utc_datetime
      add :last_login_at, :utc_datetime
      add :password_reset_token, :string
      add :password_reset_sent_at, :utc_datetime
      add :temp_password, :string
      add :temp_password_sent_at, :utc_datetime
      # Refresh token support per student
      add :refresh_token_hash, :string
      add :refresh_token_expires_at, :utc_datetime

      # System Fields
      add :metadata, :map, default: %{}
      add :tenant_id, :uuid, null: false
      add :created_by_id, :uuid
      add :created_by_type, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:students, [:tenant_id, :email])
    create index(:students, [:refresh_token_hash])
    create unique_index(:students, [:tenant_id, :registration_id])
    create index(:students, [:tenant_id, :status])
    create index(:students, [:tenant_id, :profile_completed])

    ## ROLES
    create table(:roles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :display_name, :string, null: false
      add :description, :text
      add :permissions, {:array, :text}, default: []
      add :is_system_role, :boolean, default: false
      # Tenant reference for proper isolation
      add :tenant_id, :uuid, null: false
      # Polymorphic creator reference: can be public or tenant user
      add :created_by_id, :uuid
      add :created_by_type, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:roles, [:tenant_id, :name])

    ## USER ROLES
    create table(:user_roles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all)
      add :role_id, references(:roles, type: :uuid, on_delete: :delete_all)
      # Polymorphic assigner reference: can be public or tenant user
      add :assigned_by_id, :uuid
      add :assigned_by_type, :string
      add :assigned_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_roles, [:user_id, :role_id])

    ## ASSESSMENTS
    create table(:assessments, primary_key: false) do
      add :id, :uuid, primary_key: true

      # Basic Assessment Info
      add :title, :string, null: false
      add :description, :text
      add :assessment_type, :string, null: false # quiz, exam, assignment, project, etc.

      # Scoring & Weightage
      add :total_marks, :integer, null: false
      add :weightage, :decimal, precision: 5, scale: 2 # Percentage weightage in overall grade
      add :passing_marks, :integer, null: false

      # Timing
      add :duration_minutes, :integer, null: false
      add :time_period, :map, default: %{} # start_date, end_date, timezone

      # Status & Workflow
      add :status, :string, default: "draft" # draft -> published -> active -> completed -> archived

      # Creator & System Fields
      add :created_by, references(:users, type: :uuid), null: false
      add :settings, :map, default: %{} # Assessment-specific configuration
      add :tenant_id, :uuid, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:assessments, [:tenant_id, :status])
    create index(:assessments, [:tenant_id, :assessment_type])
    create index(:assessments, [:tenant_id, :created_by])

    ## ASSESSMENT ATTEMPTS
    create table(:assessment_attempts, primary_key: false) do
      add :id, :uuid, primary_key: true

      # References
      add :assessment_id, references(:assessments, type: :uuid, on_delete: :delete_all), null: false
      add :student_id, references(:students, type: :uuid, on_delete: :delete_all), null: false

      # Timing
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      add :submitted_at, :utc_datetime

      # Scoring
      add :obtained_marks, :integer # Raw marks obtained
      add :total_marks, :integer # Total marks for this attempt (might differ from assessment)
      add :score, :decimal, precision: 5, scale: 2 # Calculated score/percentage
      add :percentage, :decimal, precision: 5, scale: 2

      # Status & Data
      add :status, :string, default: "started" # started -> in_progress -> submitted -> evaluated -> completed
      add :answers, :map, default: %{} # Student's responses
      add :evaluation_data, :map, default: %{} # Auto-grading results, feedback, etc.

      # System Fields
      add :attempt_number, :integer, default: 1 # If multiple attempts are allowed
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assessment_attempts, [:assessment_id, :student_id, :attempt_number])
    create index(:assessment_attempts, [:student_id, :status])
    create index(:assessment_attempts, [:assessment_id, :status])

    ## STUDENT ATS PHASES
    create table(:student_ats_phases, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      # References
      add :student_id, references(:students, type: :uuid, on_delete: :delete_all), null: false
      add :tenant_id, :uuid, null: false

      # Resume Processing Info
      add :resume_url, :string, null: false
      add :status, :string, default: "processing"
      add :processed_at, :utc_datetime

      # Student ATS Fields (moved from students table)
      add :preferred_role, :string
      add :college_id_card_url, :string
      add :profile_picture_url, :string

      # ATS Analysis Data (JSON fields for flexible structure)
      add :metadata, :map, default: %{}
      add :personal_information, :map, default: %{}
      add :portfolio_and_links, :map, default: %{}
      add :professional_summary, :map, default: %{}
      add :skills, :map, default: %{}
      add :work_experience, {:array, :map}, default: []
      add :projects, {:array, :map}, default: []
      add :education, {:array, :map}, default: []
      add :certifications, {:array, :map}, default: []
      add :languages, {:array, :map}, default: []
      add :achievements_and_activities, {:array, :map}, default: []
      add :sanity_check, :map, default: %{}
      add :extracted_raw_text_snippets, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    # Indexes for efficient querying
    create unique_index(:student_ats_phases, [:student_id])
    create index(:student_ats_phases, [:tenant_id])
    create index(:student_ats_phases, [:status])
    create index(:student_ats_phases, [:processed_at])
    create index(:student_ats_phases, [:tenant_id, :status])
  end
end
