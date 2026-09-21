defmodule VyaasaCampus.Repo.Migrations.AddJobDescriptionToJobRoles do
  use Ecto.Migration

  # Canonical job description authored by the super admin per role. When present
  # it becomes the relevance-scoring rubric (decomposed + cached once), so every
  # tenant scores résumés for this role against the same requirement set.
  def change do
    alter table(:job_roles) do
      add :job_description, :text
    end
  end
end
