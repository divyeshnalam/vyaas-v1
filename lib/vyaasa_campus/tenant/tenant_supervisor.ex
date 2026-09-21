defmodule VyaasaCampus.Tenant.TenantSupervisor do
  @moduledoc """
  DynamicSupervisor for managing tenant-specific processes and operations.

  This supervisor provides fault tolerance for tenant operations including:
  - Bulk student operations
  - Email sending workers
  - File processing workers
  - Background tenant tasks

  Follows Phoenix 1.8 and OTP best practices for dynamic process management.
  """

  use DynamicSupervisor
  require Logger

  @name __MODULE__

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: @name)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("Starting TenantSupervisor for dynamic tenant operations")

    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60
    )
  end

  @doc """
  Starts a worker for bulk student operations with fault tolerance.

  ## Parameters
    - tenant_alias: The tenant identifier
    - operation_type: Type of operation (:bulk_create, :bulk_email, :bulk_update)
    - args: Arguments for the worker

  ## Returns
    - `{:ok, pid}` on success
    - `{:error, reason}` on failure
  """
  def start_tenant_worker(tenant_alias, operation_type, args) do
    worker_spec = {
      VyaasaCampus.Tenant.TenantWorker,
      %{
        tenant_alias: tenant_alias,
        operation_type: operation_type,
        args: args,
        started_at: DateTime.utc_now()
      }
    }

    case DynamicSupervisor.start_child(@name, worker_spec) do
      {:ok, pid} ->
        Logger.info("Started tenant worker for #{tenant_alias}, operation: #{operation_type}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start tenant worker: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Starts a bulk email worker for sending emails concurrently.
  """
  def start_bulk_email_worker(tenant_alias, email_jobs) do
    start_tenant_worker(tenant_alias, :bulk_email, %{jobs: email_jobs})
  end

  @doc """
  Starts a bulk student creation worker.
  """
  def start_bulk_student_worker(tenant_alias, student_data, prefix) do
    start_tenant_worker(tenant_alias, :bulk_create_students, %{
      student_data: student_data,
      prefix: prefix
    })
  end

  @doc """
  Lists all currently running tenant workers.
  """
  def list_workers do
    DynamicSupervisor.which_children(@name)
  end

  @doc """
  Gets count of running workers.
  """
  def worker_count do
    DynamicSupervisor.count_children(@name)
  end

  @doc """
  Terminates a specific worker by PID.
  """
  def terminate_worker(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(@name, pid)
  end

  @doc """
  Stops all workers gracefully.
  """
  def stop_all_workers do
    @name
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(@name, pid)
    end)

    Logger.info("All tenant workers stopped")
  end
end
