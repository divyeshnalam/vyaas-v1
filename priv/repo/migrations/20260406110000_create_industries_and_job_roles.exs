defmodule VyaasaCampus.Repo.Migrations.CreateIndustriesAndJobRoles do
  use Ecto.Migration

  def up do
    create table(:industries) do
      add :name, :string, null: false, size: 255
      add :code, :string, size: 50
      add :description, :text
      add :icon, :string, size: 100
      add :is_active, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:industries, [:name])
    create unique_index(:industries, [:code])

    create table(:job_roles) do
      add :title, :string, null: false, size: 255
      add :code, :string, size: 50
      add :description, :text
      add :skills, {:array, :string}, default: []
      add :experience_level, :string, size: 50, default: "entry"
      add :is_active, :boolean, default: true, null: false
      add :industry_id, references(:industries, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:job_roles, [:industry_id])
    create unique_index(:job_roles, [:title, :industry_id])
    create index(:job_roles, [:is_active])
  end

  def down do
    drop table(:job_roles)
    drop table(:industries)
  end
end
