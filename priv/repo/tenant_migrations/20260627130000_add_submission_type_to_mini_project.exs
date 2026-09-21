defmodule VyaasaCampus.Repo.TenantMigrations.AddSubmissionTypeToMiniProject do
  use Ecto.Migration

  def up do
    schema = prefix()

    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'mini_project_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} ->
        repo().query!(
          ~s[ALTER TABLE "#{schema}".mini_project_sessions] <>
            " ADD COLUMN IF NOT EXISTS submission_type varchar(32) NOT NULL DEFAULT 'github'"
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
          ~s[ALTER TABLE "#{schema}".mini_project_sessions DROP COLUMN IF EXISTS submission_type]
        )

      _ ->
        :ok
    end
  end
end
