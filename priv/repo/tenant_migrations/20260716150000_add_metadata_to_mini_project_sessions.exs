defmodule VyaasaCampus.Repo.TenantMigrations.AddMetadataToMiniProjectSessions do
  use Ecto.Migration

  # Adds a metadata jsonb column to store the authenticity/forensics report for
  # the Mini Project (file-metadata + git-commit provenance + viva authorship).
  def up do
    schema = prefix()

    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'mini_project_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} ->
        repo().query!(
          ~s[ALTER TABLE "#{schema}".mini_project_sessions] <>
            " ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'"
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
          ~s[ALTER TABLE "#{schema}".mini_project_sessions DROP COLUMN IF EXISTS metadata]
        )

      _ ->
        :ok
    end
  end
end
