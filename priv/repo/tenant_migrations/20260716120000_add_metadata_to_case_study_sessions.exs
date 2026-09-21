defmodule VyaasaCampus.Repo.TenantMigrations.AddMetadataToCaseStudySessions do
  use Ecto.Migration

  # Adds a metadata jsonb column used to store proctoring violations for the
  # case-study assessment (same shape as behavioral/psychometric sessions).
  def up do
    schema = prefix()

    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'case_study_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} ->
        repo().query!(
          ~s[ALTER TABLE "#{schema}".case_study_sessions] <>
            " ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'"
        )

      _ ->
        :ok
    end
  end

  def down do
    schema = prefix()

    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'case_study_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} ->
        repo().query!(
          ~s[ALTER TABLE "#{schema}".case_study_sessions DROP COLUMN IF EXISTS metadata]
        )

      _ ->
        :ok
    end
  end
end
