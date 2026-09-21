defmodule VyaasaCampus.Repo.TenantMigrations.EnsureTimerColsOnMiniProject do
  use Ecto.Migration

  # Catches undefined_table instead of using an IF EXISTS guard — the guard
  # approaches (information_schema.tables + current_schema(), pg_class) both
  # have cross-schema visibility issues in tenant migrations. The exception
  # handler is the only approach that is reliably schema-scoped.

  def up do
    execute """
    DO $$
    BEGIN
      ALTER TABLE mini_project_sessions
        ADD COLUMN IF NOT EXISTS submission_deadline timestamp without time zone,
        ADD COLUMN IF NOT EXISTS time_expired boolean NOT NULL DEFAULT false;
    EXCEPTION
      WHEN undefined_table THEN NULL;
    END $$;
    """
  end

  def down do
    execute """
    DO $$
    BEGIN
      ALTER TABLE mini_project_sessions
        DROP COLUMN IF EXISTS submission_deadline,
        DROP COLUMN IF EXISTS time_expired;
    EXCEPTION
      WHEN undefined_table THEN NULL;
    END $$;
    """
  end
end
