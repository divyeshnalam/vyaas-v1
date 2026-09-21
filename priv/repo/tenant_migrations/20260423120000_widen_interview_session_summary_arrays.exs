defmodule VyaasaCampus.Repo.Migrations.WidenInterviewSessionSummaryArrays do
  use Ecto.Migration

  # The LLM's placement-readiness report produces bullets that are often full
  # sentences well beyond 255 chars. `strengths` and `improvements` were
  # created as `{:array, :string}` (= `varchar(255)[]`), which truncated /
  # rejected those bullets. Promote to `text[]` so the full content stores
  # losslessly. Data already present stays — Postgres casts `varchar[]` to
  # `text[]` without loss.

  def up do
    # Use Ecto's `alter table` so the tenant schema prefix is applied
    # automatically (raw `execute "ALTER TABLE ..."` skips the prefix
    # and breaks on new-tenant creation when multiple connections may
    # not share the search_path).
    alter table(:interview_sessions) do
      modify :strengths, {:array, :text}
      modify :improvements, {:array, :text}
    end
  end

  def down do
    # Truncate any row that exceeds 255 chars per element before shrinking.
    execute """
    UPDATE interview_sessions
       SET strengths = ARRAY(
             SELECT LEFT(s, 255) FROM unnest(strengths) AS s
           )
     WHERE EXISTS (
             SELECT 1 FROM unnest(strengths) AS s WHERE length(s) > 255
           )
    """

    execute """
    UPDATE interview_sessions
       SET improvements = ARRAY(
             SELECT LEFT(s, 255) FROM unnest(improvements) AS s
           )
     WHERE EXISTS (
             SELECT 1 FROM unnest(improvements) AS s WHERE length(s) > 255
           )
    """

    execute "ALTER TABLE interview_sessions ALTER COLUMN strengths TYPE varchar(255)[] USING strengths::varchar(255)[]"

    execute "ALTER TABLE interview_sessions ALTER COLUMN improvements TYPE varchar(255)[] USING improvements::varchar(255)[]"
  end
end
