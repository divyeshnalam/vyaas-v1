defmodule VyaasaCampusWeb.Student.ProfileCompletion.AtsService do
  @moduledoc """
  ATS scoring orchestration for the profile-completion flow.

  Handles uploaded-file persistence, ATS phase creation, and Oban job
  enqueue. Scoring itself runs in `VyaasaCampus.AI.ResumeScorer` (native
  Elixir + Bumblebee).
  """

  import Phoenix.LiveView, only: [uploaded_entries: 2, consume_uploaded_entries: 3]

  alias VyaasaCampus.Contexts.{StudentAts, Tenants}
  alias VyaasaCampus.Jobs.AtsResumeProcessor

  @upload_base_path "priv/uploads"

  @doc """
  Processes resume and ID card upload, then enqueues an ATS scoring job.

  ## Parameters
    - socket: LiveView socket with uploads and assigns

  ## Returns
    - {:ok, request_id} on success
    - {:error, reason} on failure
  """
  def process_resume_and_documents(socket) do
    require Logger
    Logger.info("=== PROFILE COMPLETION PYTHON SERVICE ===")

    student = socket.assigns.student
    tenant_alias = socket.assigns.tenant_alias
    preferred_role = socket.assigns.preferred_job_role

    Logger.info("Student ID: #{student.id}")
    Logger.info("Tenant: #{tenant_alias}")
    Logger.info("Preferred role: #{preferred_role}")

    # Debug upload entries
    resume_entries = uploaded_entries(socket, :resume)
    id_card_entries = uploaded_entries(socket, :id_card)

    Logger.info("Resume entries: #{inspect(resume_entries)}")
    Logger.info("ID card entries: #{inspect(id_card_entries)}")

    with {:ok, tenant} <- get_tenant(tenant_alias),
         {:ok, resume_path} <- save_resume_file(socket, tenant),
         {:ok, id_card_path} <- save_id_card_file(socket, tenant),
         {:ok, ats_phase} <- create_or_update_ats_phase(student, tenant, resume_path, id_card_path, preferred_role),
         {:ok, _job} <- enqueue_processing_job(ats_phase, tenant.schema_name) do

      Logger.info("✅ ATS processing initiated successfully")
      Logger.info("ATS Phase ID: #{ats_phase.id}")
      Logger.info("Resume saved to: #{resume_path}")
      Logger.info("ID card saved to: #{id_card_path}")

      {:ok, ats_phase.id}
    else
      {:error, reason} ->
        Logger.error("❌ ATS processing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Checks if ATS processing is complete for a student.
  """
  def processing_complete?(student_id, tenant_alias) do
    case get_tenant(tenant_alias) do
      {:ok, tenant} ->
        case StudentAts.get_by_student_id(student_id, tenant.schema_name) do
          nil -> false
          ats_phase -> ats_phase.status in ["completed", "manual_review", "errored"]
        end
      {:error, _} -> false
    end
  end

  # Private functions

  defp get_tenant(tenant_alias) do
    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil -> {:error, "Tenant not found: #{tenant_alias}"}
      tenant -> {:ok, tenant}
    end
  end

  defp save_resume_file(socket, tenant) do
    require Logger
    resume_entries = uploaded_entries(socket, :resume)
    Logger.info("Resume entries detailed: #{inspect(resume_entries)}")

    case resume_entries do
      {[entry], []} when entry.done? ->
        Logger.info("Resume file is done, consuming...")
        # File is fully uploaded, consume it
        uploaded_files = consume_uploaded_entries(socket, :resume, &read_uploaded_file/2)
        case uploaded_files do
          [file] -> save_uploaded_file_content(file, "resume", socket.assigns.student, tenant)
          [] -> {:error, "No resume file uploaded"}
          _ -> {:error, "Multiple resume files not supported"}
        end
      {[entry], []} ->
        # File exists but not done yet
        Logger.info("Resume file exists but not done - Progress: #{entry.progress}%, Done: #{entry.done?}")
        {:error, "Resume file is still uploading (#{entry.progress}%)"}
      _ ->
        Logger.info("No resume file found in entries: #{inspect(resume_entries)}")
        {:error, "No resume file uploaded"}
    end
  end

  defp save_id_card_file(socket, tenant) do
    require Logger
    id_card_entries = uploaded_entries(socket, :id_card)
    Logger.info("ID card entries detailed: #{inspect(id_card_entries)}")

    case id_card_entries do
      {[entry], []} when entry.done? ->
        Logger.info("ID card file is done, consuming...")
        # File is fully uploaded, consume it
        uploaded_files = consume_uploaded_entries(socket, :id_card, &read_uploaded_file/2)
        case uploaded_files do
          [file] -> save_uploaded_file_content(file, "id_card", socket.assigns.student, tenant)
          [] -> {:error, "No ID card file uploaded"}
          _ -> {:error, "Multiple ID card files not supported"}
        end
      {[entry], []} ->
        # File exists but not done yet
        Logger.info("ID card file exists but not done - Progress: #{entry.progress}%, Done: #{entry.done?}")
        {:error, "ID card file is still uploading (#{entry.progress}%)"}
      _ ->
        Logger.info("No ID card file found in entries: #{inspect(id_card_entries)}")
        {:error, "No ID card file uploaded"}
    end
  end

  # Helper function to read uploaded file content
  defp read_uploaded_file(meta, entry) do
    case File.read(meta.path) do
      {:ok, content} ->
        {:ok, %{
          filename: entry.client_name,
          content: content,
          content_type: entry.client_type
        }}

      {:error, reason} ->
        {:error, "Failed to read uploaded file: #{reason}"}
    end
  end

  defp save_uploaded_file_content(file, file_type, student, tenant) do
    require Logger

    # Create unique filename with timestamp (following existing pattern)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    sanitized_filename = sanitize_filename(file.filename)
    unique_filename = "#{timestamp}_#{file_type}_#{sanitized_filename}"

    # Create directory structure: uploads/{tenant_id}/students/{student_id}/
    # Following the existing pattern from AtsUpload.save_uploaded_file
    tenant_path = Path.join([@upload_base_path, tenant.id, "students", student.id])
    full_path = Path.join(tenant_path, unique_filename)

    Logger.info("Attempting to save #{file_type} file to: #{full_path}")

    # Ensure directory exists
    File.mkdir_p!(tenant_path)

    # Write file content directly to permanent location
    case File.write(full_path, file.content) do
      :ok ->
        Logger.info("File saved successfully: #{file_type} -> #{full_path}")
            # Return relative path from uploads directory (following existing pattern)
            relative_path = Path.join([tenant.id, "students", student.id, unique_filename])
        {:ok, relative_path}

      {:error, reason} ->
        Logger.error("Failed to write #{file_type} file: #{inspect(reason)}")
        {:error, "Failed to save #{file_type} file: #{inspect(reason)}"}
    end
  end

  defp sanitize_filename(filename) do
    # Remove any path separators and special characters (from existing AtsUpload)
    filename
    |> Path.basename()
    |> String.replace(~r/[^\w\.-]/, "_")
    # Limit length
    |> String.slice(0, 100)
  end

  defp create_or_update_ats_phase(student, tenant, resume_path, id_card_path, preferred_role) do
    require Logger
    Logger.info("Creating/updating ATS phase for student #{student.id}")

    attrs = %{
      student_id: student.id,
      tenant_id: tenant.id,
      resume_url: resume_path,
      college_id_card_url: id_card_path,
      preferred_role: preferred_role,
      status: "queued",
      processing_attempts: 0
    }

    # Check if student already has an ATS phase
    case StudentAts.get_by_student_id(student.id, tenant.schema_name) do
      nil ->
        # Create new ATS phase
        Logger.info("Creating new ATS phase")
        StudentAts.create_ats_phase_with_profile(student.id, tenant.id, attrs, tenant.schema_name)

      existing_phase ->
        # Update existing phase
        Logger.info("Updating existing ATS phase: #{existing_phase.id}")
        update_attrs = Map.merge(attrs, %{status: "queued", processing_attempts: 0})
        StudentAts.update_ats_fields(existing_phase, update_attrs, tenant.schema_name)
    end
  end

  defp enqueue_processing_job(ats_phase, tenant_schema) do
    require Logger
    Logger.info("Enqueueing ATS processing job for phase #{ats_phase.id}")

    case AtsResumeProcessor.enqueue_processing(ats_phase, tenant_schema) do
      {:ok, job} ->
        Logger.info("Processing job enqueued successfully: #{job.id}")
        {:ok, job}

      {:error, reason} ->
        Logger.error("Failed to enqueue processing job: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
