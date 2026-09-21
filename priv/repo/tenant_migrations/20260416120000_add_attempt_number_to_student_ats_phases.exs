defmodule VyaasaCampus.Repo.Migrations.AddAttemptNumberToStudentAtsPhases do
  use Ecto.Migration

  def up do
    # Allow multiple ATS phases per student to track resume improvement over time.
    # The existing unique index on student_id is replaced with a compound index
    # on (student_id, attempt_number).
    #
    # Made idempotent: in some tenant schemas the column/indexes were applied
    # out-of-band without recording this migration, so re-running it raised
    # "column already exists". Ecto DDL (alter table / create_if_not_exists)
    # carries the Triplex schema prefix automatically; the column add is guarded
    # by a prefix-aware information_schema check.
    schema = prefix() || "public"

    unless column_exists?(schema, "student_ats_phases", "attempt_number") do
      # `default: 1` backfills existing rows atomically (Postgres 11+).
      alter table(:student_ats_phases) do
        add :attempt_number, :integer, default: 1, null: false
      end
    end

    # Drop old unique constraint
    drop_if_exists index(:student_ats_phases, [:student_id], name: :student_ats_phases_student_id_index)

    # Add new compound unique constraint
    create_if_not_exists unique_index(:student_ats_phases, [:student_id, :attempt_number],
                           name: :student_ats_phases_student_id_attempt_index)

    # Index for fetching latest phase quickly
    create_if_not_exists index(:student_ats_phases, [:student_id, :attempt_number])
  end

  defp column_exists?(schema, table, column) do
    %{rows: rows} =
      repo().query!(
        """
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = $2 AND column_name = $3
        """,
        [schema, table, column]
      )

    rows != []
  end

  def down do
    drop_if_exists index(:student_ats_phases, [:student_id, :attempt_number],
                     name: :student_ats_phases_student_id_attempt_index)
    drop_if_exists index(:student_ats_phases, [:student_id, :attempt_number])

    # Keep only the first phase per student to restore unique constraint
    execute """
    DELETE FROM student_ats_phases
    WHERE (student_id, attempt_number) NOT IN (
      SELECT student_id, MIN(attempt_number)
      FROM student_ats_phases
      GROUP BY student_id
    )
    """

    create unique_index(:student_ats_phases, [:student_id],
             name: :student_ats_phases_student_id_index)

    alter table(:student_ats_phases) do
      remove :attempt_number
    end
  end
end
