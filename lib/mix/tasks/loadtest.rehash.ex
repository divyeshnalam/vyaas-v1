defmodule Mix.Tasks.Loadtest.Rehash do
  @moduledoc """
  Re-hash the load-test student pool (`email LIKE 'loadtest_%'`) at the currently
  configured bcrypt cost.

  The seed script hashed the whole pool at the old cost (12), so those accounts
  keep verifying at ~800ms even after lowering `:bcrypt_elixir, :log_rounds`.
  Since the pool shares one known password we can re-hash it directly (real users
  can't be bulk re-hashed — they upgrade via rehash-on-verify on next login).

  Scoped to `loadtest_%` accounts only — it never touches real students.

      mix loadtest.rehash <tenant_alias> [password]
      mix loadtest.rehash Bites "LoadTest@123"

  Defaults: password "LoadTest@123" (the seed default).
  """
  use Mix.Task

  import Ecto.Query, only: [from: 2]

  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Repo

  @shortdoc "Re-hash the loadtest_% student pool at the current bcrypt cost"

  @impl true
  def run(args) do
    tenant_alias = Enum.at(args, 0) || Mix.raise("Usage: mix loadtest.rehash <tenant_alias> [password]")
    password = Enum.at(args, 1) || "LoadTest@123"

    Mix.Task.run("app.start")

    tenant =
      case Tenants.get_tenant_by_alias(tenant_alias) do
        nil -> Mix.raise("No tenant/college found for alias #{inspect(tenant_alias)}")
        t -> t
      end

    prefix = tenant.schema_name
    cost = Application.get_env(:bcrypt_elixir, :log_rounds, 12)

    # One hash for the shared password (matches how the pool was seeded).
    hash = Bcrypt.hash_pwd_salt(password)

    Mix.shell().info("Re-hashing loadtest_%% students in #{prefix} at bcrypt cost #{cost}...")

    {count, _} =
      Repo.update_all(
        from(s in "students", where: like(s.email, "loadtest_%")),
        [set: [encrypted_password: hash, updated_at: DateTime.utc_now()]],
        prefix: prefix
      )

    Mix.shell().info("Done. Re-hashed #{count} load-test account(s) to cost #{cost}.")
    Mix.shell().info("They now log in with password #{inspect(password)} at the new cost.")
  end
end
