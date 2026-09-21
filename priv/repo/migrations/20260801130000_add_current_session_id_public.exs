defmodule VyaasaCampus.Repo.Migrations.AddCurrentSessionIdPublic do
  use Ecto.Migration

  # Single-active-session support: the id of the session that most recently
  # logged in. A request whose token carries a different session id is rejected,
  # so a new login on one device logs out the others. Public-schema tables.
  @tables ["platform_admins", "users", "students"]

  def up do
    for tbl <- @tables do
      if table_exists?("public", tbl) do
        repo().query!(
          ~s[ALTER TABLE public.#{tbl} ADD COLUMN IF NOT EXISTS current_session_id varchar(64)]
        )
      end
    end
  end

  def down do
    for tbl <- @tables do
      if table_exists?("public", tbl) do
        repo().query!(~s[ALTER TABLE public.#{tbl} DROP COLUMN IF EXISTS current_session_id])
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
