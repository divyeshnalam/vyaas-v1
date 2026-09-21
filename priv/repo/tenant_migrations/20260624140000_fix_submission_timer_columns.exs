defmodule VyaasaCampus.Repo.TenantMigrations.FixSubmissionTimerColumns do
  use Ecto.Migration

  def change do
    execute(
      """
      DO $$
      BEGIN
        ALTER TABLE mini_project_sessions
          ADD COLUMN IF NOT EXISTS submission_deadline timestamp without time zone,
          ADD COLUMN IF NOT EXISTS time_expired boolean NOT NULL DEFAULT false;
      EXCEPTION
        WHEN undefined_table THEN NULL;
      END $$;
      """,
      """
      DO $$
      BEGIN
        ALTER TABLE mini_project_sessions
          DROP COLUMN IF EXISTS submission_deadline,
          DROP COLUMN IF EXISTS time_expired;
      EXCEPTION
        WHEN undefined_table THEN NULL;
      END $$;
      """
    )
  end
end
