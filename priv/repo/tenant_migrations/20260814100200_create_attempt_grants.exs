defmodule VyaasaCampus.Repo.Migrations.CreateAttemptGrants do
  use Ecto.Migration

  @moduledoc """
  Extra assessment attempts granted to an individual student by a tenant admin.

  Append-only: rows accumulate and are summed, so every grant stays attributable
  to who made it and why (the "her internet dropped mid-interview" case) rather
  than someone quietly editing a limit for the whole tenant.
  """

  def change do
    create table(:attempt_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :student_id, :binary_id, null: false
      add :module, :string, null: false
      add :extra_attempts, :integer, null: false, default: 1
      add :reason, :text
      add :granted_by_id, :binary_id
      add :granted_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:attempt_grants, [:student_id, :module])
  end
end
