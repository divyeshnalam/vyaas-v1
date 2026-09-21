defmodule VyaasaCampusWeb.Student.Reanalyze.ReanalyzeService do
  @moduledoc """
  Service for re-analyzing an authenticated student's resume.
  Creates a new ATS phase record (incremented attempt_number) so each
  re-analysis is preserved as history for score tracking.

  Requires only a new resume file + preferred job role — ID card and
  profile picture are carried forward from the prior verified phase.
  """

  import Phoenix.LiveView, only: [uploaded_entries: 2, consume_uploaded_entries: 3]

  alias VyaasaCampus.Contexts.{StudentAts, Tenants}
  alias VyaasaCampus.Jobs.AtsResumeProcessor

  require Logger

  @upload_base_path "priv/uploads"

  @doc """
  Process a resume re-analysis request.
  Returns {:ok, ats_phase_id} or {:error, reason}.
  """
  def process_reanalysis(socket) do
    student = socket.assigns.student
    tenant_alias = socket.assigns.tenant_alias
    preferred_role = socket.assigns.preferred_job_role

    Logger.info("REANALYZE | Starting | student=#{student.id} | role=#{preferred_role}")

    with {:ok, tenant} <- get_tenant(tenant_alias),
         {:ok, resume_path} <- save_resume_file(socket, tenant, student),
         {:ok, ats_phase} <- create_reanalysis_phase(student, tenant, resume_path, preferred_role),
         {:ok, _job} <- enqueue_processing_job(ats_phase, tenant.schema_name) do
      Logger.info("REANALYZE | Queued | ats_phase=#{ats_phase.id} | attempt=#{ats_phase.attempt_number}")
      {:ok, ats_phase.id}
    else
      # AttemptGuard.check/4 returns a 3-tuple on a blocked attempt — without
      # this clause it doesn't match {:error, reason} below and the `with` (no
      # `else` on create_reanalysis_phase/4 itself) lets the 3-tuple escape
      # unmatched, raising WithClauseError and crashing the LiveView process.
      {:error, :attempt_limit_reached, meta} ->
        Logger.warning("REANALYZE | Blocked by attempt limit: #{inspect(meta)}")
        {:error, {:attempt_limit_reached, meta}}

      {:error, reason} ->
        Logger.error("REANALYZE | Failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_tenant(tenant_alias) do
    case Tenants.get_tenant_by_alias(String.upcase(tenant_alias)) do
      nil -> {:error, "Tenant not found: #{tenant_alias}"}
      tenant -> {:ok, tenant}
    end
  end

  defp save_resume_file(socket, tenant, student) do
    case uploaded_entries(socket, :resume) do
      {[entry], []} when entry.done? ->
        files =
          consume_uploaded_entries(socket, :resume, fn meta, entry ->
            case File.read(meta.path) do
              {:ok, content} ->
                {:ok,
                 %{
                   filename: entry.client_name,
                   content: content,
                   content_type: entry.client_type
                 }}

              {:error, reason} ->
                {:error, "Failed to read uploaded file: #{reason}"}
            end
          end)

        case files do
          [file] -> write_file(file, student, tenant)
          [] -> {:error, "No resume file uploaded"}
          _ -> {:error, "Multiple resume files not supported"}
        end

      {[entry], []} ->
        {:error, "Resume file is still uploading (#{entry.progress}%)"}

      _ ->
        {:error, "No resume file uploaded"}
    end
  end

  defp write_file(file, student, tenant) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    sanitized = sanitize_filename(file.filename)
    unique_filename = "#{timestamp}_resume_#{sanitized}"

    tenant_path = Path.join([@upload_base_path, tenant.id, "students", student.id])
    full_path = Path.join(tenant_path, unique_filename)

    File.mkdir_p!(tenant_path)

    case File.write(full_path, file.content) do
      :ok ->
        {:ok, Path.join([tenant.id, "students", student.id, unique_filename])}

      {:error, reason} ->
        {:error, "Failed to save resume: #{inspect(reason)}"}
    end
  end

  defp sanitize_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^\w\.-]/, "_")
    |> String.slice(0, 100)
  end

  defp create_reanalysis_phase(student, tenant, resume_path, preferred_role) do
    StudentAts.create_reanalysis_phase(
      student.id,
      tenant.id,
      %{resume_url: resume_path, preferred_role: preferred_role},
      tenant.schema_name
    )
  end

  defp enqueue_processing_job(ats_phase, tenant_schema) do
    AtsResumeProcessor.enqueue_processing(ats_phase, tenant_schema)
  end
end
