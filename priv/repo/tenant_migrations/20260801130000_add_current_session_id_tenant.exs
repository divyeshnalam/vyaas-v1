defmodule VyaasaCampus.Repo.TenantMigrations.AddCurrentSessionIdTenant do
  use Ecto.Migration

  # Single-active-session support (per-tenant users + students). See the public
  # counterpart. A token whose session id != the row's current_session_id is
  # rejected, so a fresh login supersedes other devices.
  @tables ["users", "students"]

  def up do
    schema = prefix()

    for tbl <- @tables do
      if table_exists?(schema, tbl) do
        repo().query!(
          ~s[ALTER TABLE "#{schema}".#{tbl} ADD COLUMN IF NOT EXISTS current_session_id varchar(64)]
        )
      end
    end
  end

  def down do
    schema = prefix()

    for tbl <- @tables do
      if table_exists?(schema, tbl) do
        repo().query!(~s[ALTER TABLE "#{schema}".#{tbl} DROP COLUMN IF EXISTS current_session_id])
      end
    end
  end

  defp table_exists?(schema, tbl) do
    case repo().query(
           "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = $2",
           [schema, tbl]
         ) do
      {:ok, %{rows: [_ | _]}} -> true
      _ -> false
    end
  end
end
