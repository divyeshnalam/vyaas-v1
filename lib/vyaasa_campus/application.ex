defmodule VyaasaCampus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Attach before Oban starts processing jobs — a handler must be attached
    # before the events it listens for can fire.
    VyaasaCampus.Jobs.AtsJobRecorder.attach()

    children = [
      # Daily (midnight IST) rotating file logger — must start early so the
      # rest of boot is captured in the log file.
      VyaasaCampus.Logging.FileRotator,
      VyaasaCampusWeb.Telemetry,
      VyaasaCampus.Repo,
      {Phoenix.PubSub, name: VyaasaCampus.PubSub},
      {Task.Supervisor, name: VyaasaCampus.TaskSupervisor},
      # Finch HTTP connection pool (persistent connections to Groq API)
      {Finch,
       name: VyaasaCampus.Finch,
       pools: %{
         "https://api.groq.com" => [size: 50, count: 2],
         :default => [size: 25, count: 1]
       }},
      # Groq API rate limiter (token bucket + request queue)
      VyaasaCampus.AI.GroqRateLimiter,
      # Sentence-embedding serving for resume relevance scoring (Bumblebee + Nx).
      # Loads all-MiniLM-L6-v2 once, batches encode requests across resume scoring jobs.
      VyaasaCampus.AI.EmbeddingServer,
      {Oban, Application.fetch_env!(:vyaasa_campus, Oban)},
      VyaasaCampus.Auth.AuthSupervisor,
      VyaasaCampus.Tenant.TenantSupervisor,
      VyaasaCampusWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: VyaasaCampus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VyaasaCampusWeb.Endpoint.config_change(changed, removed)
    :ok
  end

end
