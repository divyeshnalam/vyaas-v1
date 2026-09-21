defmodule VyaasaCampus.Repo.Migrations.AddChaptersAndRestructure do
  use Ecto.Migration

  def up do
    # 1. Add specialization_id to subjects (direct link to academics.specializations)
    alter table(:subjects) do
      add :specialization_id, :binary_id
    end

    create index(:subjects, [:specialization_id])

    # 2. Create chapters table (between subjects and topics)
    create table(:chapters) do
      add :name, :string, null: false, size: 255
      add :code, :string, size: 50
      add :subject_id, references(:subjects, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:chapters, [:subject_id])
    create unique_index(:chapters, [:name, :subject_id])

    # 3. Add chapter_id to topics (keep subject_id for backward compat)
    alter table(:topics) do
      add :chapter_id, references(:chapters, on_delete: :nilify_all)
    end

    create index(:topics, [:chapter_id])
  end

  def down do
    alter table(:topics) do
      remove :chapter_id
    end

    drop table(:chapters)

    alter table(:subjects) do
      remove :specialization_id
    end
  end
end
