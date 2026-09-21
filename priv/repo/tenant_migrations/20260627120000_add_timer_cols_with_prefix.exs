defmodule VyaasaCampus.Repo.TenantMigrations.AddTimerColsWithPrefix do
  use Ecto.Migration

  # All previous attempts used unqualified table names inside DO $$ blocks.
  # PostgreSQL runs DO blocks with the session's default search_path (public),
  # not the prefix Ecto sets for schema_migrations tracking. Using prefix() and
  # repo() with explicit schema qualification is the only reliable approach.

  def up do
    schema = prefix()

    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'mini_project_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} ->
        repo().query!(
          ~s[ALTER TABLE "#{schema}".mini_project_sessions] <>
            " ADD COLUMN IF NOT EXISTS submission_deadline timestamp without time zone," <>
            " ADD COLUMN IF NOT EXISTS time_expired boolean NOT NULL DEFAULT false"
        )

      _ ->
        :ok
    end
  end

  def down do
    schema = prefix()

    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'mini_project_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} ->
        repo().query!(
          ~s[ALTER TABLE "#{schema}".mini_project_sessions] <>
            " DROP COLUMN IF EXISTS submission_deadline," <>
            " DROP COLUMN IF EXISTS time_expired"
        )

      _ ->
        :ok
    end
  end
end
