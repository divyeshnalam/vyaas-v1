defmodule VyaasaCampus.Repo.TenantMigrations.AddAtsColumnsAndJobProfiles do
  use Ecto.Migration

  def change do
    # Add new columns to student_ats_phases table
    alter table(:student_ats_phases) do
      add :ats_score, :decimal, precision: 5, scale: 2
      add :completeness_score  , :decimal, precision: 5, scale: 2
      add :sanity_score, :decimal, precision: 5, scale: 2
      add :processing_attempts, :integer, default: 0
      add :last_processing_error, :text
      add :processor_metadata, :map, default: %{}
      add :raw_result_json, :map, default: %{}
      add :idempotency_key, :string
      add :callback_received_at, :utc_datetime
      add :deleted_at, :utc_datetime
      add :retention_policy_days, :integer, default: 90
    end

    # Create indexes for the new columns
    create index(:student_ats_phases, [:ats_score])
    create index(:student_ats_phases, [:processing_attempts])
    create index(:student_ats_phases, [:callback_received_at])
    create index(:student_ats_phases, [:deleted_at])

    # Create job_profiles table
    create table(:job_profiles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :role, :string, null: false
      add :profile_text, :text, null: false
      add :tenant_id, :uuid, null: false
      add :created_by_id, :uuid
      add :created_by_type, :string
      timestamps(type: :utc_datetime)
    end

    # Create indexes for job_profiles
    create unique_index(:job_profiles, [:tenant_id, :role])
    create index(:job_profiles, [:tenant_id])

    # Insert predefined job profiles data
    # Note: Since this is a tenant-specific migration, we need to handle tenant_id
    # In Triplex/Ecto tenant migrations, the tenant_id is typically available in the migration context
    # For now, we'll assume the tenant_id will be provided or we'll use a default approach

    # Since we can't easily determine tenant_id in the migration context,
    # we'll create a separate seed file for the job profiles data

    # For now, we'll create the data structure but note that tenant_id needs to be handled
    # when the migration is actually run in the tenant context.
  end
end
