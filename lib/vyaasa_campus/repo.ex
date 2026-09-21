defmodule VyaasaCampus.Repo do
  use Ecto.Repo,
    otp_app: :vyaasa_campus,
    adapter: Ecto.Adapters.Postgres,
    migration_primary_key: [type: :binary_id],
    migration_foreign_key: [type: :binary_id]
end
