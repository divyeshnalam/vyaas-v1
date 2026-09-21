defmodule VyaasaCampus.Auth.AuthSupervisor do
  @moduledoc """
  Supervisor for authentication-related processes.
  Ensures AuthServer is always running with fault tolerance.
  """

  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("Starting AuthSupervisor")

    children = [
      # AuthServer with restart strategy
      {VyaasaCampus.Auth.AuthServer, []}
    ]

    # Strategy: :one_for_one means if AuthServer crashes, only restart that process
    # max_restarts: 3 in max_seconds: 5 means if it crashes more than 3 times in 5 seconds,
    # the supervisor itself will crash
    opts = [
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    ]

    Supervisor.init(children, opts)
  end

  @doc """
  Get supervisor status and children info
  """
  def status do
    children = Supervisor.which_children(__MODULE__)
    count = Supervisor.count_children(__MODULE__)

    %{
      children: children,
      count: count,
      supervisor_pid: Process.whereis(__MODULE__)
    }
  end
end
