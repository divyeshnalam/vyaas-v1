defmodule VyaasaCampus.Repo.TenantMigrations.AddMetadataToJamSessions do
  use Ecto.Migration

  # Adds a metadata jsonb column to store proctoring violations for the JAM
  # assessment (same shape as behavioral/psychometric/case-study sessions).
  def up do
    schema = prefix()

    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'jam_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} ->
        repo().query!(
          ~s[ALTER TABLE "#{schema}".jam_sessions] <>
            " ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'"
        )

      _ ->
        :ok
    end
  end

  def down do
    schema = prefix()

    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'jam_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} ->
        repo().query!(~s[ALTER TABLE "#{schema}".jam_sessions DROP COLUMN IF EXISTS metadata])

      _ ->
        :ok
    end
  end
end
