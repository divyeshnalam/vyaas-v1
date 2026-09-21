# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :vyaasa_campus,
  ecto_repos: [VyaasaCampus.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure your database (base config — dev overrides stacktrace/show_sensitive in dev.exs)
config :vyaasa_campus, VyaasaCampus.Repo,
  username: System.get_env("DATABASE_USERNAME") || "postgres",
  password: System.get_env("DATABASE_PASSWORD") || "R@vi@7284",
  hostname: System.get_env("DATABASE_HOST") || "localhost",
  database: System.get_env("DATABASE_NAME") || "vvayaasa_test",
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "10")

# Configures the endpoint
config :vyaasa_campus, VyaasaCampusWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: VyaasaCampusWeb.ErrorHTML, json: VyaasaCampusWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: VyaasaCampus.PubSub,
  live_view: [signing_salt: "cO7e1dmQ", hibernate_after: 30_000]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :vyaasa_campus, VyaasaCampus.Mailer, adapter: Swoosh.Adapters.Local

# Configure Swoosh to use Dev.Mailbox adapter for local email delivery
config :swoosh, :api_client, false

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  vyaasa_campus: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  vyaasa_campus: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger (timestamps in UTC)
config :logger, utc_log: true

config :logger, :default_formatter,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:request_id]

# Daily log files, rotated at midnight IST, previous day zipped, 3 days kept.
config :vyaasa_campus, VyaasaCampus.Logging.FileRotator,
  enabled: true,
  dir: "log",
  basename: "vyaasa_campus",
  time_zone: "Asia/Kolkata",
  keep_days: 3

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Timezone database — required for DateTime.shift_zone/2 to non-UTC zones
# (e.g. "Asia/Kolkata" for IST display in dashboards).
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Triplex configuration for multi-tenancy
config :triplex,
  repo: VyaasaCampus.Repo,
  tenant_name_prefix: "tenant_",
  tenant_migrations_path: "priv/repo/tenant_migrations"

# Oban configuration
config :vyaasa_campus, Oban,
  repo: VyaasaCampus.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    # Rescues jobs orphaned by a node crash/restart mid-execution — without
    # this, a job stuck in `executing` (e.g. AtsResumeProcessor) stays there
    # forever instead of being retried or eventually discarded. 30 minutes is
    # generous relative to how long resume scoring actually takes (each Groq
    # call is capped at 60s; a stuck job is almost always orphaned, not slow).
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab: [
       # Daily cleanup at 2 AM
       {"0 2 * * *", VyaasaCampus.Jobs.AtsFileCleanup},
       # Safety net for assessments abandoned mid-session that terminate/2
       # couldn't catch (a node crash skips it entirely) — see
       # AssessmentAbandonmentSweep. terminate/2 is the primary, immediate
       # trigger; this just mops up what it structurally can't.
       {"*/15 * * * *", VyaasaCampus.Jobs.AssessmentAbandonmentSweep}
     ]}
  ],
  queues: [
    default: 10,
    emails: 5,
    imports: 3,
    ats_processing: 5,
    ai_reports: 10,
    cleanup: 1,
    # Finalizing an assessment abandoned mid-session (tab closed, terminate/2,
    # or picked up by the abandonment sweep) — see AssessmentFinalizer. Sized
    # for 5 concurrent abandonments; at large-cohort scale (e.g. an exam
    # window's time limit lapsing for hundreds of students within the same
    # minute), 5 workers backlog badly since each job may make an LLM call.
    # Raising POOL_SIZE accordingly is required alongside this — see
    # docs/1000-user-readiness.md.
    assessment_finalize: 15
  ]

# Guardian configuration for JWT authentication
config :vyaasa_campus, VyaasaCampus.Guardian,
  issuer: "vyaasa_campus",
  secret_key: System.get_env("GUARDIAN_SECRET_KEY") || "dev-guardian-secret-change-in-production",
  ttl: {String.to_integer(System.get_env("ACCESS_TOKEN_TTL_MINUTES") || "30"), :minutes},
  allowed_drift: 60,
  verify_issuer: true

# Password hashing cost (bcrypt work factor). Cost 12 ≈ 776ms/hash on our
# hardware and serializes concurrent logins (the login-burst bottleneck); cost 10
# ≈ 207ms — ~3.7x more login throughput on the same CPU while remaining secure.
# Overridable at deploy time via BCRYPT_LOG_ROUNDS (see runtime.exs). Only affects
# NEWLY created/changed passwords — existing hashes keep their embedded cost.
config :bcrypt_elixir, log_rounds: 10

# Nx backend — XLA gives JIT-compiled ops on CPU/GPU for the embedding server
config :nx, default_backend: EXLA.Backend

# OpenTelemetry — traces exported over OTLP/HTTP (protobuf) to the self-hosted
# Opik instance. Opik routes spans by the `projectName` header and the
# `Comet-Workspace` header; no auth is enforced on this instance, so no
# `Authorization` header. The traces endpoint is used verbatim (no /v1/traces
# suffix appended), so it must be the full path.
config :opentelemetry,
  resource: [service: [name: "vyaasa_campus"]],
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_traces_endpoint:
    System.get_env("OPIK_OTLP_TRACES_ENDPOINT") ||
      "http://122.175.56.6:5174/api/v1/private/otel/v1/traces",
  otlp_headers: [
    {"projectName", System.get_env("OPIK_PROJECT_NAME") || "Vyaas Demo Test"},
    {"Comet-Workspace", System.get_env("OPIK_WORKSPACE") || "default"}
  ]

# ChromicPDF options are set directly on the supervisor spec in
# VyaasaCampus.Application — see chromic_pdf_opts/0 there.

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"