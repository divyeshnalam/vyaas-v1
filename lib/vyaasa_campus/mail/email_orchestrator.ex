defmodule VyaasaCampus.Mail.EmailOrchestrator do
  @moduledoc """
  Centralized email orchestration for the VyaasaCampus application.

  This module handles all email sending operations, separating email logic
  from business logic. It provides a single point of control for all email
  operations and ensures consistent logging and error handling.

  ## Usage Examples:

  ```elixir
  alias VyaasaCampus.Mail.EmailOrchestrator

  # Send welcome email
  EmailOrchestrator.send_welcome_email(user, temp_password, tenant_alias)

  # Send password reset email
  EmailOrchestrator.send_password_reset_email(user, tenant_alias)

  # Send profile completion email
  EmailOrchestrator.send_profile_completion_email(student, profile_url, tenant_alias)
  ```
  """

  require Logger
  alias VyaasaCampus.Mail.EmailService
  alias VyaasaCampus.Tenant.TenantSupervisor
  alias VyaasaCampus.Tenant.TenantWorker
  alias VyaasaCampus.Types

  # ============================================================================
  # USER EMAILS
  # ============================================================================

  @doc """
  Sends welcome email to a new user with temporary password.
  """
  def send_welcome_email(user, temp_password, tenant_alias) do
    Logger.info("Sending welcome email to user: #{user.email}")

    case EmailService.send_welcome_email(user, temp_password, tenant_alias) do
      {:ok, _} ->
        Logger.info("Welcome email sent successfully to: #{user.email}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send welcome email to #{user.email}: #{inspect(reason)}")
        {:error, :email_send_failed}
    end
  end

  @doc """
  Sends welcome email to a user with role assignment details and temporary password.
  """
  def send_welcome_email_with_role(user, role, assigner, tenant_alias) do
    Logger.info("Sending welcome email with role to user: #{user.email}")

    case EmailService.send_welcome_email_with_role(user, role, assigner, tenant_alias) do
      {:ok, _} ->
        Logger.info("Welcome email with role sent successfully to: #{user.email}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send welcome email with role to #{user.email}: #{inspect(reason)}")

        {:error, :email_send_failed}
    end
  end

  @doc """
  Sends password reset email to a user.
  """
  def send_password_reset_email(user, tenant_alias) do
    Logger.info("Sending password reset email to user: #{user.email}")

    case EmailService.send_password_reset_email(user, tenant_alias) do
      {:ok, _} ->
        Logger.info("Password reset email sent successfully to: #{user.email}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send password reset email to #{user.email}: #{inspect(reason)}")
        {:error, :email_send_failed}
    end
  end

  # ============================================================================
  # STUDENT EMAILS
  # ============================================================================

  @doc """
  Sends profile completion email to a student.
  """
  def send_profile_completion_email(student, profile_url, tenant_alias) do
    Logger.info("Sending profile completion email to student: #{student.email}")

    case EmailService.send_profile_completion_email(student, profile_url, tenant_alias) do
      {:ok, _} ->
        Logger.info("Profile completion email sent successfully to: #{student.email}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send profile completion email to #{student.email}: #{inspect(reason)}")

        {:error, :email_send_failed}
    end
  end

  @doc """
  Sends profile approval email to a student with temporary password.
  """
  def send_profile_approved_email(student, temp_password, tenant_alias) do
    Logger.info("Sending profile approval email to student: #{student.email}")

    case EmailService.send_profile_approved_email(student, temp_password, tenant_alias) do
      {:ok, _} ->
        Logger.info("Profile approval email sent successfully to: #{student.email}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send profile approval email to #{student.email}: #{inspect(reason)}")

        {:error, :email_send_failed}
    end
  end

  @doc """
  Sends profile edit request email to a student with feedback.
  """
  def send_profile_edit_request_email(
        student,
        profile_url,
        admin_notes,
        edit_request_notes,
        tenant_alias
      ) do
    Logger.info("Sending profile edit request email to student: #{student.email}")

    case EmailService.send_profile_edit_request_email(
           student,
           profile_url,
           admin_notes,
           edit_request_notes,
           tenant_alias
         ) do
      {:ok, _} ->
        Logger.info("Profile edit request email sent successfully to: #{student.email}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send profile edit request email to #{student.email}: #{inspect(reason)}")

        {:error, :email_send_failed}
    end
  end

  @doc """
  Sends profile edit approved email to a student.
  """
  def send_profile_edit_approved_email(student, admin_notes, tenant_alias) do
    Logger.info("Sending profile edit approved email to student: #{student.email}")

    case EmailService.send_profile_edit_approved_email(student, admin_notes, tenant_alias) do
      {:ok, _} ->
        Logger.info("Profile edit approved email sent successfully to: #{student.email}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send profile edit approved email to #{student.email}: #{inspect(reason)}")

        {:error, :email_send_failed}
    end
  end

  @doc """
  Sends profile edit rejected email to a student.
  """
  def send_profile_edit_rejected_email(student, admin_notes, rejection_notes, tenant_alias) do
    Logger.info("Sending profile edit rejected email to student: #{student.email}")

    case EmailService.send_profile_edit_rejected_email(
           student,
           admin_notes,
           rejection_notes,
           tenant_alias
         ) do
      {:ok, _} ->
        Logger.info("Profile edit rejected email sent successfully to: #{student.email}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send profile edit rejected email to #{student.email}: #{inspect(reason)}")

        {:error, :email_send_failed}
    end
  end

  # ============================================================================
  # ASSESSMENT REPORT EMAILS
  # ============================================================================

  @doc """
  Sends an assessment report PDF to a student as an email attachment.

  `opts` keys:
    * `:report_title` — required (e.g. "MCQ Assessment Report")
    * `:assessment_title` — required (name of the specific assessment)
    * `:tenant_alias` — optional
    * `:filename` — optional, attachment filename (default: "Vyaasa-Report.pdf")
  """
  def send_report_email(student, pdf_binary, opts) when is_binary(pdf_binary) do
    Logger.info("Sending assessment report to student: #{student.email}")

    case EmailService.send_report_email(student, pdf_binary, opts) do
      {:ok, _} ->
        Logger.info("Assessment report sent successfully to: #{student.email}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send assessment report to #{student.email}: #{inspect(reason)}")
        {:error, :email_send_failed}
    end
  end

  # ============================================================================
  # TENANT EMAILS
  # ============================================================================

  @doc """
  Sends tenant creation confirmation email.
  """
  def send_tenant_creation_email(tenant) do
    Logger.info("Sending tenant creation email for tenant: #{tenant.full_name}")

    case EmailService.send_tenant_creation_email(tenant) do
      {:ok, _} ->
        Logger.info("Tenant creation email sent successfully for: #{tenant.full_name}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send tenant creation email for #{tenant.full_name}: #{inspect(reason)}")

        {:error, :email_send_failed}
    end
  end

  # ============================================================================
  # BULK EMAIL OPERATIONS
  # ============================================================================

  @doc """
  Sends bulk emails to multiple recipients using Task.async_stream for concurrent processing.
  Uses fault-tolerant concurrent processing following Phoenix 1.8 guidelines.

  ## Parameters
    - operations: List of email operation tuples
    - opts: Options map with:
      - :max_concurrency (integer) - Max concurrent email operations (default: 5)
      - :timeout (integer) - Timeout per email in ms (default: 30_000)
      - :use_supervisor (boolean) - Whether to use DynamicSupervisor (default: false for emails)

  ## Returns
    - `{:ok, %{sent: count, failed: count, errors: [errors], duration_ms: time}}`
  """
  def send_bulk_emails(operations, opts \\ %{}) when is_list(operations) do
    # Limit email concurrency
    max_concurrency = Map.get(opts, :max_concurrency, 5)
    # 30 seconds per email
    timeout = Map.get(opts, :timeout, 30_000)
    use_supervisor = Map.get(opts, :use_supervisor, false)

    if use_supervisor and length(operations) > 20 do
      send_bulk_emails_with_supervisor(operations, opts)
    else
      send_bulk_emails_concurrent(operations, max_concurrency, timeout)
    end
  end

  @doc """
  Legacy bulk email function using sequential processing.
  Maintained for backward compatibility.
  """
  def send_bulk_emails_sequential(operations) when is_list(operations) do
    Logger.info("Sending #{length(operations)} bulk emails sequentially")

    results = Enum.map(operations, &send_single_email_operation/1)
    {successful, failed} = count_results(results)

    Logger.info("Bulk email operation completed: #{successful} successful, #{failed} failed")

    {:ok, %{successful: successful, failed: failed, results: results}}
  end

  defp count_results(results) do
    successful = Enum.count(results, fn {status, _} -> status == :ok end)
    failed = Enum.count(results, fn {status, _} -> status == :error end)
    {successful, failed}
  end

  @doc """
  Sends bulk emails using Task.async_stream for concurrent processing.
  """
  def send_bulk_emails_concurrent(operations, max_concurrency, timeout) do
    Logger.info("Starting concurrent bulk email sending: #{length(operations)} emails")

    start_time = System.monotonic_time(:millisecond)

    # Use Task.async_stream for concurrent email processing
    results =
      operations
      |> Task.async_stream(
        fn operation ->
          send_single_email_operation(operation)
        end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.to_list()

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    # Process results
    {sent, errors} = process_email_results(results)

    Logger.info(
      "Concurrent bulk email sending completed in #{duration}ms: #{length(sent)} sent, #{length(errors)} failed"
    )

    {:ok,
     %{
       sent: length(sent),
       failed: length(errors),
       total: length(operations),
       errors: errors,
       duration_ms: duration,
       concurrency_used: max_concurrency
     }}
  end

  @doc """
  Sends bulk emails using DynamicSupervisor for fault tolerance.
  Recommended for very large email batches (>20 emails).
  """
  def send_bulk_emails_with_supervisor(operations, opts) do
    # Convert operations to email jobs format
    email_jobs = Enum.map(operations, &operation_to_email_job/1)

    case TenantSupervisor.start_bulk_email_worker("system", email_jobs) do
      {:ok, worker_pid} ->
        # Monitor the worker process
        ref = Process.monitor(worker_pid)
        # 5 minutes default
        timeout = Map.get(opts, :timeout, 300_000)

        receive do
          {:DOWN, ^ref, :process, ^worker_pid, :normal} ->
            TenantWorker.get_status(worker_pid)

          {:DOWN, ^ref, :process, ^worker_pid, reason} ->
            Logger.error("Bulk email worker crashed: #{inspect(reason)}")
            {:error, {:worker_crashed, reason}}
        after
          timeout ->
            Process.demonitor(ref)
            TenantSupervisor.terminate_worker(worker_pid)
            {:error, :operation_timeout}
        end

      {:error, reason} ->
        Logger.error("Failed to start bulk email worker: #{inspect(reason)}")
        {:error, {:supervisor_error, reason}}
    end
  end

  # Helper function to send a single email operation
  defp send_single_email_operation(operation) do
    email_operations = %{
      {:welcome, :_, :_, :_} => &send_welcome_email/3,
      {:password_reset, :_, :_} => &send_password_reset_email/2,
      {:profile_completion, :_, :_, :_} => &send_profile_completion_email/3,
      {:profile_approved, :_, :_, :_} => &send_profile_approved_email/3,
      {:profile_edit_approved, :_, :_, :_} => &send_profile_edit_approved_email/3,
      {:tenant_creation, :_} => &send_tenant_creation_email/1
    }

    case operation do
      {:profile_edit_request, student, profile_url, admin_notes, edit_request_notes, tenant_alias} ->
        send_profile_edit_request_email(student, profile_url, admin_notes, edit_request_notes, tenant_alias)

      {:profile_edit_rejected, student, admin_notes, rejection_notes, tenant_alias} ->
        send_profile_edit_rejected_email(student, admin_notes, rejection_notes, tenant_alias)

      _ ->
        handle_standard_operation(operation, email_operations)
    end
  end

  defp handle_standard_operation(operation, email_operations) do
    operation_key = get_operation_key(operation)

    case Map.get(email_operations, operation_key) do
      nil -> handle_unknown_operation(operation)
      email_fn -> apply_email_function(email_fn, operation)
    end
  end

  defp get_operation_key({operation_type, _}) when operation_type in [:tenant_creation], do: {operation_type, :_}
  defp get_operation_key({operation_type, _, _}) when operation_type in [:password_reset], do: {operation_type, :_, :_}

  defp get_operation_key({operation_type, _, _, _})
       when operation_type in [:welcome, :profile_completion, :profile_approved, :profile_edit_approved],
       do: {operation_type, :_, :_, :_}

  defp get_operation_key(_), do: nil

  defp apply_email_function(email_fn, {operation_type, arg1, arg2, arg3})
       when operation_type in [:welcome, :profile_completion, :profile_approved, :profile_edit_approved],
       do: email_fn.(arg1, arg2, arg3)

  defp apply_email_function(email_fn, {operation_type, arg1, arg2}) when operation_type == :password_reset,
    do: email_fn.(arg1, arg2)

  defp apply_email_function(email_fn, {operation_type, arg1}) when operation_type == :tenant_creation,
    do: email_fn.(arg1)

  defp apply_email_function(_, _), do: handle_unknown_operation(nil)

  defp handle_unknown_operation(operation) do
    Logger.warning("Unknown email operation type: #{inspect(operation)}")
    {:error, :unknown_operation}
  end

  # Helper function to process Task.async_stream email results
  defp process_email_results(results) do
    Enum.reduce(results, {[], []}, fn
      {:ok, {:ok, _}}, {sent, errors} ->
        {[:sent | sent], errors}

      {:ok, {:error, error}}, {sent, errors} ->
        {sent, [error | errors]}

      {:exit, reason}, {sent, errors} ->
        {sent, [{:timeout, reason} | errors]}

      other, {sent, errors} ->
        {sent, [{:unexpected_result, other} | errors]}
    end)
  end

  # Helper function to convert operation to email job format
  defp operation_to_email_job(operation) do
    case operation do
      {:profile_completion, student, profile_url, tenant_alias} ->
        %{type: :profile_completion, student: student, profile_url: profile_url, tenant_alias: tenant_alias}

      {:profile_approved, student, temp_password, tenant_alias} ->
        %{type: :approval, student: student, temp_password: temp_password, tenant_alias: tenant_alias}

      {:password_reset, student, tenant_alias} ->
        %{type: :password_reset, student: student, tenant_alias: tenant_alias}

      _ ->
        %{type: :unknown, operation: operation}
    end
  end

  # ============================================================================
  # EMAIL VALIDATION
  # ============================================================================

  @doc """
  Validates email template type.
  """
  def valid_email_template?(template) do
    Types.valid_email_templates() |> Enum.member?(template)
  end

  @doc """
  Validates email address format.
  """
  def valid_email_format?(email) when is_binary(email) do
    email_regex = ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
    String.match?(email, email_regex) and byte_size(email) <= Types.max_email_length()
  end

  def valid_email_format?(_), do: false

  # ============================================================================
  # EMAIL MONITORING
  # ============================================================================

  @doc """
  Gets email statistics for monitoring.
  """
  def get_email_stats do
    # This could be enhanced to track actual email statistics
    # For now, it returns basic structure
    %{
      total_sent: 0,
      total_failed: 0,
      success_rate: 0.0,
      last_sent: nil,
      templates_used: []
    }
  end

  @doc """
  Checks if email service is healthy.
  """
  def email_service_healthy? do
    # This could be enhanced to actually check email service health
    # For now, it returns true
    true
  end
end
