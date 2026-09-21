defmodule VyaasaCampus.Repo.Migrations.CreateAssessmentConfigs do
  use Ecto.Migration

  def change do
    create table(:assessment_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :total_questions, :integer, default: 60, null: false
      add :aptitude_percentage, :integer, default: 40, null: false
      add :technical_percentage, :integer, default: 60, null: false
      add :duration_minutes, :integer, default: 90, null: false
      add :negative_marking, :decimal, precision: 5, scale: 2, default: 0.25, null: false
      add :easy_percentage, :integer, default: 40, null: false
      add :medium_percentage, :integer, default: 40, null: false
      add :hard_percentage, :integer, default: 20, null: false
      add :passing_percentage, :integer, default: 50, null: false
      add :is_active, :boolean, default: true, null: false
      add :created_by, references(:platform_admins, type: :binary_id, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assessment_configs, [:tenant_id])
  end
end
