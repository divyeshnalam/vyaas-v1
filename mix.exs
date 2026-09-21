defmodule VyaasaCampus.MixProject do
  use Mix.Project

  def project do
    [
      app: :vyaasa_campus,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {VyaasaCampus.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.4"},
      {:bandit, "~> 1.5"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.17"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.2"},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.3"},
      {:gen_smtp, "~> 1.1"},
      {:finch, "~> 0.13"},
      {:req, "~> 0.4"},
      {:eqrcode, "~> 0.2"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},

      # Distributed tracing — OTLP/HTTP export to the self-hosted Opik instance
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.8"},

      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:pre_commit, "~> 0.3.4", only: :dev},
      {:dotenv_parser, "~> 1.2"},
      # Multi-tenancy & Auth
      {:triplex, "~> 1.3"},
      {:guardian, "~> 2.0"},

      # Background Jobs
      {:oban, "~> 2.15"},

      # Native ML stack — sentence embeddings for resume scoring (replaces Python sentence-transformers)
      {:bumblebee, "~> 0.6"},
      {:nx, "~> 0.10"},
      {:exla, "~> 0.10"},

      # File Upload
      {:waffle, "~> 1.1"},
      {:waffle_ecto, "~> 0.0.12"},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:sweet_xml, "~> 0.0"},

      # CSV Processing
      {:csv, "~> 3.0"},

      # Environment Variables
      # {:dotenv, "~> 3.0.0", only: [:dev, :test]},

      # Utilities
      {:bcrypt_elixir, "~> 3.0"},
      {:uuid, "~> 1.1"},
      {:timex, "~> 3.0"},

      # Testing
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:wallaby, "~> 0.30", runtime: false, only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {
        :heroicons,
        # or a newer tag you prefer
        github: "tailwindlabs/heroicons", tag: "v2.1.5", sparse: "optimized", app: false, compile: false, depth: 1
      }
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind vyaasa_campus", "esbuild vyaasa_campus"],
      "assets.deploy": [
        "tailwind vyaasa_campus --minify",
        "esbuild vyaasa_campus --minify",
        "phx.digest"
      ]
    ]
  end
end