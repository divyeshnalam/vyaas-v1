defmodule VyaasaCampus.Repo.TenantMigrations.AddMetadataToInterviewSessions do
  use Ecto.Migration

  # Adds a metadata jsonb column to store proctoring violations for the
  # Interactive Session (interview) assessment.
  def up do
    schema = prefix()

    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'interview_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} ->
        repo().query!(
          ~s[ALTER TABLE "#{schema}".interview_sessions] <>
            " ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'"
        )

      _ ->
        :ok
    end
  end

  def down do
    schema = prefix()

    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'interview_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} ->
        repo().query!(~s[ALTER TABLE "#{schema}".interview_sessions DROP COLUMN IF EXISTS metadata])

      _ ->
        :ok
    end
  end
end
