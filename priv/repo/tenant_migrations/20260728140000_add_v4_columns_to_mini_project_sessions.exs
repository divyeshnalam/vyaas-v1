defmodule VyaasaCampus.Repo.TenantMigrations.AddV4ColumnsToMiniProjectSessions do
  use Ecto.Migration

  # Adds the columns the V4 viva-driven engine needs to the existing
  # mini_project_sessions table (additive — legacy sessions keep working).
  # `engine_version` defaults to 'legacy' so pre-V4 rows are distinguishable;
  # the V4 create path sets it to 'v4'.
  @adds [
    "engine_version varchar(16) NOT NULL DEFAULT 'legacy'",
    "profile jsonb NOT NULL DEFAULT '{}'",
    "artifact_ceilings jsonb NOT NULL DEFAULT '{}'",
    "viva_questions jsonb NOT NULL DEFAULT '[]'",
    "question_scores jsonb NOT NULL DEFAULT '[]'",
    "viva_metric_scores jsonb NOT NULL DEFAULT '{}'",
    "per_metric jsonb NOT NULL DEFAULT '{}'",
    "authenticity varchar(32)",
    "gate_note text",
    "contradiction boolean NOT NULL DEFAULT false",
    "contradiction_detail text",
    "timing jsonb NOT NULL DEFAULT '{}'",
    "feedback jsonb NOT NULL DEFAULT '{}'",
    "composite_raw integer"
  ]

  @cols ~w(engine_version profile artifact_ceilings viva_questions question_scores
           viva_metric_scores per_metric authenticity gate_note contradiction
           contradiction_detail timing feedback composite_raw)

  def up do
    schema = prefix()

    if table_exists?(schema) do
      for add <- @adds do
        repo().query!(
          ~s[ALTER TABLE "#{schema}".mini_project_sessions ADD COLUMN IF NOT EXISTS #{add}]
        )
      end
    end
  end

  def down do
    schema = prefix()

    if table_exists?(schema) do
      for col <- @cols do
        repo().query!(
          ~s[ALTER TABLE "#{schema}".mini_project_sessions DROP COLUMN IF EXISTS #{col}]
        )
      end
    end
  end

  defp table_exists?(schema) do
    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'mini_project_sessions'",
           [schema]
         ) do
      {:ok, %{rows: [_ | _]}} -> true
      _ -> false
    end
  end
end
