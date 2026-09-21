import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :vyaasa_campus, VyaasaCampus.Repo,
  username: System.get_env("DATABASE_USERNAME") || "postgres",
  password: System.get_env("DATABASE_PASSWORD") || "postgres",
  hostname: System.get_env("DATABASE_HOST") || "localhost",
  database: "vyaasa_campus_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 30,
  queue_target: 10000,
  queue_interval: 20000,
  timeout: 30000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :vyaasa_campus, VyaasaCampusWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "VdHJkoOWY8yxUOuJ8XfShC/WOGMcRVlR7FZ8aJ4R9gbox6KuNDMYGPSWEWvN39hy",
  server: false

# In test we don't send emails
config :vyaasa_campus, VyaasaCampus.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

config :vyaasa_campus, VyaasaCampus.Logging.FileRotator, enabled: false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Minimum bcrypt cost in tests — password hashing dominates auth-test time otherwise.
config :bcrypt_elixir, log_rounds: 4

# Without this, Oban's queues actively poll and its Stager/Peer processes run
# for real during tests — against a sandboxed DB connection they don't own,
# which is the source of the recurring "cannot find ownership process for
# #PID<...>" noise in every test run. :manual disables automatic execution so
# jobs only run when a test explicitly calls them (Oban.Testing helpers) or
# when a Worker's perform/1 is invoked directly.
config :vyaasa_campus, Oban, testing: :manual

# ATS service JWT for testing - now handled in runtime.exs
