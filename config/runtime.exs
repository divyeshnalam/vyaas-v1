import Config

# Load .env for local development only
if config_env() == :dev do
  DotenvParser.load_file(".env")
end

# Enable Phoenix server in releases
if System.get_env("PHX_SERVER") do
  config :vyaasa_campus, VyaasaCampusWeb.Endpoint, server: true
end

# Shared DB config for DEV + PROD
if config_env() in [:dev, :prod] do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      DATABASE_URL is missing.
      Example:
      ecto://USER:PASSWORD@localhost/DATABASE_NAME
      """

  config :vyaasa_campus, VyaasaCampus.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "40"),
    queue_target: 500,
    queue_interval: 2000
end

# Log file location / retention (handy for releases, where the working
# directory is not the project root).
config :vyaasa_campus, VyaasaCampus.Logging.FileRotator,
  enabled: System.get_env("LOG_TO_FILE", "true") == "true",
  dir: System.get_env("LOG_DIR") || "log",
  keep_days: String.to_integer(System.get_env("LOG_KEEP_DAYS") || "3")

# Groq API configuration (for native AI features — psychometric, behavioral, JAM, interview)
config :vyaasa_campus, :groq_api_key, System.get_env("GROQ_API_KEY")

# Groq rate limiter (adjust for your Groq plan tier)
config :vyaasa_campus, VyaasaCampus.AI.GroqRateLimiter,
  max_concurrent: String.to_integer(System.get_env("GROQ_MAX_CONCURRENT") || "50"),
  max_queue_size: String.to_integer(System.get_env("GROQ_MAX_QUEUE_SIZE") || "500")

# Password hashing cost — deploy-time override of the config.exs default (10).
# Lower = faster logins under load; higher = more brute-force resistance.
if rounds = System.get_env("BCRYPT_LOG_ROUNDS") do
  config :bcrypt_elixir, log_rounds: String.to_integer(rounds)
end


# Frontend URL (used for user-facing links in emails - must be browser-accessible)
config :vyaasa_campus, :frontend_url, System.get_env("FRONTEND_URL", "https://dev-ui.vyaasa.in")

# SMTP email configuration (shared across environments)
config :vyaasa_campus, :smtp_from_email, System.get_env("SMTP_FROM_EMAIL", "noreply@vyaasa.com")

# ======================
# Production-only config
# ======================
if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      SECRET_KEY_BASE is missing.
      Run:
      mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :vyaasa_campus, VyaasaCampusWeb.Endpoint,
    url: [host: host, scheme: "https", port: 443],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port,
      thousand_island_options: [
        num_acceptors: 100,
        read_timeout: 60_000
      ]
    ],
    secret_key_base: secret_key_base

  # SMTP email delivery (production)
  config :vyaasa_campus, VyaasaCampus.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("SMTP_RELAY") || "smtp.gmail.com",
    port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
    username: System.get_env("SMTP_USERNAME"),
    password: System.get_env("SMTP_PASSWORD"),
    ssl: false,
    tls: :always,
    tls_options: [
      verify: :verify_none
    ],
    auth: :always,
    retries: 2,
    no_mx_lookups: true,
    sockopts: [:inet]
end

# Dev SMTP override: if SMTP_USERNAME is set in .env, use SMTP instead of Local adapter
if config_env() == :dev and System.get_env("SMTP_USERNAME") not in [nil, ""] do
  config :vyaasa_campus, VyaasaCampus.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("SMTP_RELAY") || "smtp.gmail.com",
    port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
    username: System.get_env("SMTP_USERNAME"),
    password: System.get_env("SMTP_PASSWORD"),
    ssl: false,
    tls: :always,
    tls_options: [
      verify: :verify_none
    ],
    auth: :always,
    retries: 2,
    no_mx_lookups: true,
    sockopts: [:inet]
end
