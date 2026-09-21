defmodule VyaasaCampus.Tenant.TenantWorker do
  @moduledoc """
  GenServer worker for handling tenant-specific operations with fault tolerance.

  This worker handles:
  - Bulk student operations using Task.async_stream
  - Concurrent email sending
  - File processing operations
  - Background tenant maintenance tasks

  Uses Task.async_stream for concurrent processing with proper error handling
  and back-pressure control as recommended by Phoenix 1.8 guidelines.
  """

  use GenServer
  require Logger

  alias VyaasaCampus.Contexts.Students
  alias VyaasaCampus.Mail.EmailOrchestrator

  defstruct [
    :tenant_alias,
    :operation_type,
    :args,
    :started_at,
    :status,
    :progress,
    :total,
    :errors
  ]

  @type t :: %__MODULE__{
          tenant_alias: String.t(),
          operation_type: atom(),
          args: map(),
          started_at: DateTime.t(),
          status: :running | :completed | :failed,
          progress: non_neg_integer(),
          total: non_neg_integer(),
          errors: list()
        }

  # Client API

  def start_link(%{tenant_alias: _, operation_type: _, args: _} = init_args) do
    GenServer.start_link(__MODULE__, init_args)
  end

  def get_status(pid) when is_pid(pid) do
    GenServer.call(pid, :get_status)
  end

  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  end

  # Server Callbacks

  @impl true
  def init(%{tenant_alias: tenant_alias, operation_type: operation_type, args: args} = init_args) do
    state = %__MODULE__{
      tenant_alias: tenant_alias,
      operation_type: operation_type,
      args: args,
      started_at: Map.get(init_args, :started_at, DateTime.utc_now()),
      status: :running,
      progress: 0,
      total: 0,
      errors: []
    }

    Logger.info("TenantWorker started for #{tenant_alias}, operation: #{operation_type}")

    # Start the operation asynchronously
    send(self(), :start_operation)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_operation, state) do
    case state.operation_type do
      :bulk_create_students ->
        handle_bulk_create_students(state)

      :bulk_email ->
        handle_bulk_email(state)

      :bulk_update_students ->
        handle_bulk_update_students(state)

      operation ->
        Logger.error("Unknown operation type: #{operation}")
        {:noreply, %{state | status: :failed, errors: ["Unknown operation type"]}}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status_info = %{
      tenant_alias: state.tenant_alias,
      operation_type: state.operation_type,
      status: state.status,
      progress: state.progress,
      total: state.total,
      started_at: state.started_at,
      errors: state.errors
    }

    {:reply, status_info, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("TenantWorker terminating for #{state.tenant_alias}, reason: #{inspect(reason)}")
    :ok
  end

  # Private Functions - Bulk Operations with Task.async_stream

  defp handle_bulk_create_students(state) do
    %{student_data: student_data, prefix: prefix} = state.args
    total = length(student_data)

    Logger.info("Starting bulk student creation: #{total} students for #{state.tenant_alias}")

    # Use Task.async_stream for concurrent processing with back-pressure
    results =
      student_data
      |> Task.async_stream(
        fn student_attrs ->
          Students.create_partial_student(student_attrs, state.tenant_alias, prefix)
        end,
        max_concurrency: System.schedulers_online() * 2,
        timeout: :infinity,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    # Process results and collect errors
    {successes, errors} = process_bulk_results(results)

    final_state = %{
      state
      | status: if(Enum.empty?(errors), do: :completed, else: :failed),
        progress: length(successes),
        total: total,
        errors: errors
    }

    Logger.info("Bulk student creation completed: #{length(successes)}/#{total} successful")

    if not Enum.empty?(errors) do
      Logger.error("Bulk student creation errors: #{inspect(errors)}")
    end

    {:noreply, final_state}
  end

  defp handle_bulk_email(state) do
    %{jobs: email_jobs} = state.args
    total = length(email_jobs)

    Logger.info("Starting bulk email sending: #{total} emails for #{state.tenant_alias}")

    # Use Task.async_stream for concurrent email sending
    results =
      email_jobs
      |> Task.async_stream(
        fn email_job ->
          send_email_job(email_job, state.tenant_alias)
        end,
        # Limit email concurrency to avoid overwhelming SMTP
        max_concurrency: 5,
        # 30 second timeout per email
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    # Process results
    {successes, errors} = process_bulk_results(results)

    final_state = %{
      state
      | status: if(Enum.empty?(errors), do: :completed, else: :failed),
        progress: length(successes),
        total: total,
        errors: errors
    }

    Logger.info("Bulk email sending completed: #{length(successes)}/#{total} successful")

    {:noreply, final_state}
  end

  defp handle_bulk_update_students(state) do
    %{updates: updates, prefix: prefix} = state.args
    total = length(updates)

    Logger.info("Starting bulk student updates: #{total} updates for #{state.tenant_alias}")

    # Use Task.async_stream for concurrent updates
    results =
      updates
      |> Task.async_stream(
        fn %{student_id: student_id, attrs: attrs} ->
          Students.update_student(student_id, attrs, prefix)
        end,
        max_concurrency: System.schedulers_online(),
        timeout: :infinity,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    # Process results
    {successes, errors} = process_bulk_results(results)

    final_state = %{
      state
      | status: if(Enum.empty?(errors), do: :completed, else: :failed),
        progress: length(successes),
        total: total,
        errors: errors
    }

    Logger.info("Bulk student updates completed: #{length(successes)}/#{total} successful")

    {:noreply, final_state}
  end

  # Helper function to process Task.async_stream results
  defp process_bulk_results(results) do
    Enum.reduce(results, {[], []}, fn
      {:ok, {:ok, _result}}, {successes, errors} ->
        {[true | successes], errors}

      {:ok, {:error, error}}, {successes, errors} ->
        {successes, [error | errors]}

      {:exit, reason}, {successes, errors} ->
        {successes, [{:task_exit, reason} | errors]}

      other, {successes, errors} ->
        {successes, [{:unexpected_result, other} | errors]}
    end)
  end

  # Helper function to send individual emails
  defp send_email_job(%{type: :profile_completion, student: student, profile_url: profile_url}, tenant_alias) do
    EmailOrchestrator.send_profile_completion_email(student, profile_url, tenant_alias)
  end

  defp send_email_job(%{type: :approval, student: student, temp_password: temp_password}, tenant_alias) do
    EmailOrchestrator.send_profile_approved_email(student, temp_password, tenant_alias)
  end

  defp send_email_job(%{type: :password_reset, student: student}, tenant_alias) do
    EmailOrchestrator.send_password_reset_email(student, tenant_alias)
  end

  defp send_email_job(unknown_job, _tenant_alias) do
    Logger.error("Unknown email job type: #{inspect(unknown_job)}")
    {:error, :unknown_job_type}
  end
end
