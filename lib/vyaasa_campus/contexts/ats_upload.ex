defmodule VyaasaCampus.Contexts.AtsUpload do
  @moduledoc """
  Context for handling ATS resume upload and processing operations.

  This module provides functions for:
  - File upload validation and storage
  - ATS phase creation and management
  - Job profile integration
  - File path management and cleanup
  """

  import Ecto.Query, warn: false
  alias VyaasaCampus.Contexts.StudentAts
  alias VyaasaCampus.Jobs.AtsResumeProcessor
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.StudentAtsPhase
  alias VyaasaCampus.Schema.Tenants.JobProfile

  @allowed_extensions ~w(.pdf .docx .doc)
  @default_upload_base_path "priv/uploads"
  @default_retention_days 90

  @doc """
  Validates and processes a resume file upload for ATS processing.

  ## Parameters
    - student: The student struct
    - uploaded_file: Phoenix uploaded file struct
    - job_profile_id: ID of selected job profile
    - opts: Additional options (retention_days, tenant_schema, etc.)

  ## Returns
    - {:ok, ats_phase} on success
    - {:error, reason} on failure
  """
  def process_resume_upload(student, uploaded_file, job_profile_id, opts \\ []) do
    tenant_schema = Keyword.get(opts, :tenant_schema, "public")

    require Logger
    Logger.info("Starting resume upload process for student #{student.id}")
    Logger.info("Uploaded file: #{uploaded_file.filename}")
    Logger.info("Job profile ID: #{job_profile_id}, tenant_schema: #{tenant_schema}")

    with {:ok, job_profile} <- get_job_profile(job_profile_id, tenant_schema),
         {:ok, _} <- validate_tenant_access(job_profile, student),
         {:ok, _} <- validate_file(uploaded_file),
         {:ok, file_path} <- save_uploaded_file(student, uploaded_file),
         {:ok, ats_phase} <- create_ats_phase_record(student, job_profile, file_path, opts, tenant_schema) do
      # Try to enqueue the job, but don't fail the upload if it fails
      case enqueue_processing_job(ats_phase, tenant_schema) do
        {:ok, _} ->
          Logger.info("Resume upload completed successfully, file saved to: #{file_path}")
          {:ok, ats_phase}

        {:error, reason} ->
          Logger.error("Resume uploaded but job enqueueing failed: #{inspect(reason)}")

          Logger.warning(
            "Resume uploaded successfully but ATS processing job failed to enqueue. Manual intervention may be required."
          )

          {:ok, ats_phase}
      end
    else
      {:error, reason} ->
        Logger.error("Resume upload failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets the full file path for a resume URL.

  ## Parameters
    - resume_url: The relative path stored in database

  ## Returns
    - Full file system path or nil if file doesn't exist
  """
  def get_resume_file_path(resume_url) do
    base_path = upload_base_path()
    full_path = Path.join(base_path, resume_url)

    # Convert to absolute path for Python service
    absolute_path = Path.absname(full_path)

    if File.exists?(absolute_path), do: absolute_path, else: nil
  end

  @doc """
  Validates that a job profile belongs to the student's tenant.
  """
  def validate_tenant_access(job_profile, student) do
    if job_profile.tenant_id == student.tenant_id do
      {:ok, job_profile}
    else
      {:error, "Job profile not accessible for this tenant"}
    end
  end

  @doc """
  Validates uploaded file size and type.
  """
  def validate_file(%{filename: filename}) do
    if valid_file_extension?(filename) do
      {:ok, :valid}
    else
      {:error, "Invalid file type. Only PDF and DOCX files are allowed"}
    end
  end

  def validate_file(_), do: {:error, "Invalid file upload"}

  @doc """
  Saves an uploaded file to the permanent storage location.
  """
  def save_uploaded_file(student, uploaded_file) do
    require Logger

    # Generate secure filename and path
    sanitized_filename = sanitize_filename(uploaded_file.filename)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    unique_filename = "#{timestamp}_#{sanitized_filename}"

    # Create directory structure: uploads/{tenant_id}/students/{student_id}/
    tenant_path = Path.join([upload_base_path(), student.tenant_id, "students", student.id])
    full_path = Path.join(tenant_path, unique_filename)

    Logger.info("Attempting to save file content to: #{full_path}")

    # Ensure directory exists
    File.mkdir_p!(tenant_path)

    # Write file content directly to permanent location
    case File.write(full_path, uploaded_file.content) do
      :ok ->
        Logger.info("File saved successfully to: #{full_path}")
        # Return relative path from uploads directory
        relative_path =
          Path.join([
            student.tenant_id,
            "students",
            student.id,
            unique_filename
          ])

        {:ok, relative_path}

      {:error, reason} ->
        Logger.error("Failed to write file: #{inspect(reason)}")
        {:error, "Failed to save file: #{inspect(reason)}"}
    end
  end

  @doc """
  Creates or updates an ATS phase record for processing.
  """
  def create_ats_phase_record(student, job_profile, file_path, opts, tenant_schema) do
    retention_days = Keyword.get(opts, :retention_days, @default_retention_days)

    attrs = %{
      student_id: student.id,
      tenant_id: student.tenant_id,
      resume_url: file_path,
      preferred_role: job_profile.role,
      status: "queued",
      processing_attempts: 0,
      retention_policy_days: retention_days
    }

    # Check if student already has an ATS phase
    case StudentAts.get_by_student_id(student.id, tenant_schema) do
      nil ->
        # Create new ATS phase. Student status is left untouched here — it
        # only flips to "unverified" (invalidating the profile_token) once
        # the student clicks "Continue to Verification" on the results step
        # (see Students.finalize_profile_submission/2), not on upload.
        StudentAts.create_ats_phase_with_profile(student.id, student.tenant_id, attrs, tenant_schema)

      existing_phase ->
        # Update existing phase with new upload
        attrs = Map.put(attrs, :status, "queued")
        StudentAts.update_ats_fields(existing_phase, attrs, tenant_schema)
    end
  end

  @doc """
  Updates ATS phase fields.
  """
  def update_ats_fields(ats_phase, attrs, tenant_schema \\ "public") do
    ats_phase
    |> Ecto.Changeset.change(attrs)
    |> Repo.update(prefix: tenant_schema)
  end

  @doc """
  Updates ATS phase with processing results from external service.
  """
  def update_ats_processing_results(ats_phase, service_response, tenant_schema \\ "public") do
    require Logger
    Logger.info("📝 Updating ATS processing results for phase #{ats_phase.id}")
    Logger.info("Service response keys: #{inspect(Map.keys(service_response))}")
    Logger.info("Tenant schema: #{tenant_schema}")

    attrs = build_processing_result_attrs(service_response)
    Logger.info("Built attrs with status: #{attrs[:status]}, score: #{attrs[:ats_score]}")
    Logger.info("Skills extracted: #{inspect(attrs[:skills])}")
    Logger.info("Work experience count: #{length(attrs[:work_experience] || [])}")

    # Apply attrs directly via changeset — build_processing_result_attrs already
    # extracted all fields from the Python response structure
    alias VyaasaCampus.Schema.Students.StudentAtsPhase

    case ats_phase
         |> StudentAtsPhase.changeset(attrs)
         |> Repo.update(prefix: tenant_schema) do
      {:ok, updated_phase} ->
        Logger.info("✅ Successfully updated ATS phase #{updated_phase.id} with status: #{updated_phase.status}")
        VyaasaCampus.DashboardEvents.broadcast_ats_event(:processed, tenant_schema, updated_phase.student_id)
        {:ok, updated_phase}

      {:error, changeset} ->
        Logger.error("❌ Failed to update ATS phase: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp build_processing_result_attrs(service_response) do
    # The Python service response has this structure:
    # %{
    #   "final_score" => 55,
    #   "completeness" => %{"score" => 62, "feedback" => [...], "corrected_groq_data" => %{...}, "other_links" => [...]},
    #   "relevance" => %{"score" => 38, "details" => %{...}},
    #   "sanity_check" => %{"score" => 55, "final_score" => 55, "status" => "...", "low_confidence" => false,
    #                       "structural_report" => %{"findings" => [...]}, "linguistic_report" => %{"feedback" => [...]}},
    #   "groq_data" => %{"Full_Name" => "...", "Skills" => %{...}, ...},
    #   "request_id" => "...",
    #   "student_id" => "..."
    # }
    # We need to extract from this structure, not from flat top-level keys.

    ats_score = service_response["final_score"] || service_response["ats_score"]
    completeness = service_response["completeness"] || %{}
    relevance = service_response["relevance"] || %{}
    # Python sends "sanity_check" key — fall back to "sanity" for backwards compatibility
    sanity = service_response["sanity_check"] || service_response["sanity"] || %{}
    groq_data = get_in(completeness, ["corrected_groq_data"]) || service_response["groq_data"] || %{}

    %{
      ats_score: ats_score,
      raw_result_json: service_response,
      status: determine_processing_status(ats_score, sanity),
      processed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      callback_received_at: DateTime.utc_now() |> DateTime.truncate(:second),
      metadata: build_metadata(completeness, relevance, sanity),
      sanity_check: sanity,
      personal_information: extract_personal_info_from_groq(groq_data),
      skills: extract_skills_from_groq(groq_data),
      work_experience: extract_work_experience_from_groq(groq_data),
      education: normalize_education(groq_data["Education"] || []),
      projects: extract_projects_from_groq(groq_data),
      certifications: normalize_certifications(groq_data["Certifications"] || []),
      languages: extract_languages_from_groq(groq_data),
      achievements_and_activities: extract_achievements_from_groq(groq_data),
      portfolio_and_links: %{"other_links" => completeness["other_links"] || []},
      professional_summary: %{
        "summary_text" => groq_data["Professional_Summary"] || [],
        "total_experience" => groq_data["Total_Experience"]
      },
      extracted_raw_text_snippets: %{}
    }
  end

  defp build_metadata(completeness, relevance, sanity) do
    # Python sanity structure:
    # %{"final_sanity_score" => 85, "total_penalty" => 15,
    #   "breakdown" => %{
    #     "professional_language" => %{"score" => 5, "issues" => [...]},
    #     "spelling"              => %{"score" => 5, "issues" => [...]},
    #     "consistent_formatting" => %{"score" => 0, "issues" => []},
    #     "consistent_date_format"=> %{"score" => 5, "issues" => [...]},
    #     "page_count"            => %{"score" => 0, "issues" => [...]}
    #   }}
    breakdown = sanity["breakdown"] || %{}
    all_issues = extract_sanity_issues(breakdown)

    %{
      "completeness_score" => completeness["score"],
      "completeness_feedback" => completeness["feedback"] || [],
      "relevance_score" => relevance["score"],
      "relevance_justification" => get_in(relevance, ["details", "justification"]),
      "matching_keywords" => get_in(relevance, ["details", "matching_keywords"]) || [],
      "missing_keywords" => get_in(relevance, ["details", "missing_keywords"]) || [],
      "sanity_score" => sanity["final_sanity_score"] || sanity["score"] || sanity["final_score"],
      "sanity_total_penalty" => sanity["total_penalty"],
      "sanity_issues" => all_issues
    }
  end

  # Flatten all issues from all breakdown categories into a single list
  defp extract_sanity_issues(breakdown) when is_map(breakdown) do
    breakdown
    |> Enum.flat_map(fn {_category, data} ->
      case data do
        %{"issues" => issues} when is_list(issues) -> issues
        _ -> []
      end
    end)
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
  end

  defp extract_sanity_issues(_), do: []

  defp extract_personal_info_from_groq(groq_data) do
    %{
      "full_name" => groq_data["Full_Name"],
      "email_address" => groq_data["Email_Address"],
      "contact_number" => groq_data["Contact_Number"],
      "location" => groq_data["Location"],
      "linkedin_profile" => groq_data["LinkedIn_Profile"],
      "github_profile" => groq_data["GitHub_Profile"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp extract_skills_from_groq(groq_data) do
    skills_data = groq_data["Skills"] || %{}

    %{
      "technical_skills" => skills_data["Technical"] || [],
      "non_technical_skills" => skills_data["Non-Technical"] || [],
      "languages_spoken" => groq_data["Languages_Spoken"] || []
    }
  end

  defp extract_work_experience_from_groq(groq_data) do
    (groq_data["Work_Experience"] || [])
    |> Enum.map(fn exp ->
      responsibilities =
        case exp["Responsibilities"] do
          resp when is_list(resp) -> Enum.join(resp, " ")
          resp when is_binary(resp) -> resp
          _ -> ""
        end

      %{
        "job_title" => exp["Job_Title"],
        "company_name" => exp["Company_Name"],
        "start_date" => exp["start_date"],
        "end_date" => exp["end_date"],
        "responsibilities" => responsibilities
      }
    end)
  end

  defp extract_projects_from_groq(groq_data) do
    (groq_data["Projects"] || [])
    |> Enum.map(fn project ->
      description =
        case project["Description"] do
          desc when is_list(desc) -> Enum.join(desc, " ")
          desc when is_binary(desc) -> desc
          _ -> ""
        end

      %{
        "Project_Name" => project["Project_Name"],
        "Technologies_Used" => project["Technologies_Used"] || [],
        "Description" => description,
        "Github_Link" => project["Github_Link"] || project["GitHub_Link"] || ""
      }
    end)
  end

  defp extract_languages_from_groq(groq_data) do
    case groq_data["Languages_Spoken"] do
      langs when is_list(langs) ->
        Enum.map(langs, fn lang -> %{"language" => lang, "proficiency" => "Not specified"} end)

      _ ->
        []
    end
  end

  defp extract_achievements_from_groq(groq_data) do
    case groq_data["Achievements"] do
      achievements when is_list(achievements) ->
        Enum.map(achievements, fn a -> %{"achievement" => a, "description" => ""} end)

      _ ->
        []
    end
  end

  # FastAPI sends certifications as a list of strings or a list of maps.
  # The schema requires {:array, :map}, so normalize strings to maps.
  defp normalize_certifications(certifications) do
    Enum.map(certifications, fn
      cert when is_binary(cert) -> %{"name" => cert}
      cert when is_map(cert) -> cert
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # FastAPI sends education with PascalCase keys. Normalize to lowercase for consistency.
  defp normalize_education(education) do
    Enum.map(education, fn
      entry when is_map(entry) ->
        %{
          "degree" => entry["Degree"] || entry["degree"],
          "institution" => entry["Institution"] || entry["institution"],
          "specialization" => entry["Specialization"] || entry["specialization"],
          "years" => entry["Years"] || entry["years"],
          "cgpa_or_percentage" => entry["CGPA/Percentage"] || entry["cgpa_or_percentage"]
        }
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Updates processing attempt count and error message.
  """
  def update_processing_attempt(ats_phase, error_message \\ nil, tenant_schema \\ "public") do
    attempts = (ats_phase.processing_attempts || 0) + 1

    attrs = %{
      processing_attempts: attempts,
      last_processing_error: error_message
    }

    # Set status to errored if max attempts reached
    max_attempts = Application.get_env(:vyaasa_campus, :max_ats_processing_attempts, 3)

    attrs =
      if attempts >= max_attempts do
        Map.put(attrs, :status, "errored")
      else
        attrs
      end

    StudentAts.update_ats_fields(ats_phase, attrs, tenant_schema)
  end

  @doc """
  Applies business rules after successful ATS processing.
  """
  def apply_business_rules(ats_phase, student, tenant_schema \\ "public") do
    require Logger
    ats_threshold = Application.get_env(:vyaasa_campus, :ats_threshold, 70.0)

    # Normalize ats_score to float — the DB field is :decimal
    score =
      case ats_phase.ats_score do
        nil -> 0.0
        %Decimal{} = d -> Decimal.to_float(d)
        n when is_number(n) -> n * 1.0
        s when is_binary(s) -> case Float.parse(s) do {f, _} -> f; :error -> 0.0 end
        _ -> 0.0
      end

    Logger.info("🎯 Applying business rules for student #{student.id}")
    Logger.info("📊 ATS Score: #{score}, Threshold: #{ats_threshold}")

    if score >= ats_threshold do
      Logger.info("✅ Auto-approval criteria met - triggering auto approval")
      auto_approve_profile(student, tenant_schema)
    else
      Logger.info("📉 ATS score #{score} below threshold #{ats_threshold} - manual review required")
      {:manual_review, "ATS score below threshold"}
    end
  end

  @doc """
  Marks files for deletion based on retention policy.
  """
  def mark_for_deletion_expired_files do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-@default_retention_days, :day)

    from(ats in StudentAtsPhase,
      where: ats.inserted_at < ^cutoff_date and is_nil(ats.deleted_at)
    )
    |> Repo.update_all(set: [deleted_at: DateTime.utc_now()])
  end

  @doc """
  Physically deletes marked files from filesystem.
  """
  def cleanup_deleted_files do
    from(ats in StudentAtsPhase,
      where: not is_nil(ats.deleted_at)
    )
    |> Repo.all()
    |> Enum.each(&delete_file_from_filesystem/1)
  end

  @doc """
  Enqueues an Oban job to process the ATS phase.
  """
  def enqueue_processing_job(ats_phase, tenant_schema) do
    require Logger
    Logger.info("Enqueueing processing job for ATS phase #{ats_phase.id} in tenant #{tenant_schema}")

    case AtsResumeProcessor.enqueue_processing(ats_phase, tenant_schema) do
      {:ok, job} ->
        Logger.info("Processing job enqueued successfully: #{job.id}")
        {:ok, job}

      {:error, reason} ->
        Logger.error("Failed to enqueue processing job: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Synchronizes student status for completed ATS phases.
  Use this to fix existing records where ATS processing completed but student status wasn't updated.
  """
  def sync_completed_ats_phases(tenant_alias) when is_binary(tenant_alias) do
    # Get the tenant to get the schema name
    alias VyaasaCampus.Contexts.Tenants

    case Tenants.get_tenant_by_alias(String.upcase(tenant_alias)) do
      nil ->
        {:error, "Tenant #{tenant_alias} not found"}

      tenant ->
        sync_completed_ats_phases_for_schema(tenant.schema_name)
    end
  end

  def sync_completed_ats_phases(tenant_schema) when is_binary(tenant_schema) do
    sync_completed_ats_phases_for_schema(tenant_schema)
  end

  defp sync_completed_ats_phases_for_schema(tenant_schema) do
    require Logger
    Logger.info("Starting ATS phase synchronization for tenant: #{tenant_schema}")

    # Find all completed ATS phases
    import Ecto.Query
    alias VyaasaCampus.Contexts.Students
    alias VyaasaCampus.Repo

    completed_phases =
      from(ats in StudentAtsPhase,
        where: ats.status == "completed",
        select: ats
      )
      |> Repo.all(prefix: tenant_schema)

    Logger.info("Found #{length(completed_phases)} completed ATS phases to sync")

    results =
      Enum.map(completed_phases, fn ats_phase ->
        case Students.get_student(ats_phase.student_id, tenant_schema) do
          nil ->
            Logger.warning("Student #{ats_phase.student_id} not found for ATS phase #{ats_phase.id}")
            {:error, :student_not_found, ats_phase.id}

          student ->
            # Check if student status needs updating
            update_student_status_if_needed(student, ats_phase, tenant_schema)
        end
      end)

    # Count results by type
    synced_count = Enum.count(results, fn {type, _, _} -> type == :synced end)
    already_synced_count = Enum.count(results, fn {type, _, _} -> type == :already_synced end)
    errors_count = Enum.count(results, fn {type, _, _} -> type == :error end)

    Logger.info("""
    ATS phase synchronization completed:
    - Synced: #{synced_count}
    - Already synced: #{already_synced_count}
    - Errors: #{errors_count}
    """)

    {:ok,
     %{
       synced: synced_count,
       already_synced: already_synced_count,
       errors: errors_count,
       total: length(completed_phases)
     }}
  end

  # Extract student status update logic to reduce nesting
  defp update_student_status_if_needed(student, ats_phase, tenant_schema) do
    require Logger
    alias VyaasaCampus.Contexts.Students

    cond do
      student.status == "pending" ->
        Logger.info("Updating student #{student.id} from pending to unverified")

        case Students.update_student(
               student.id,
               %{
                 status: "unverified",
                 profile_completed: true,
                 profile_submitted_at: DateTime.utc_now() |> DateTime.truncate(:second)
               },
               tenant_schema
             ) do
          {:ok, updated_student} ->
            {:synced, updated_student.id, ats_phase.id}

          {:error, changeset} ->
            Logger.error("Failed to sync student #{student.id}: #{inspect(changeset.errors)}")
            {:error, :sync_failed, student.id}
        end

      student.status in ["unverified", "verified", "active"] ->
        Logger.info("Student #{student.id} already has proper status: #{student.status}")
        {:already_synced, student.id, ats_phase.id}

      true ->
        Logger.warning("Student #{student.id} has unexpected status: #{student.status}")
        {:unexpected_status, student.id, student.status}
    end
  end

  # Private functions

  defp get_job_profile(job_profile_id, tenant_schema) do
    case Repo.get(JobProfile, job_profile_id, prefix: tenant_schema) do
      nil -> {:error, "Job profile not found"}
      job_profile -> {:ok, job_profile}
    end
  end

  defp valid_file_extension?(filename) do
    extension = Path.extname(filename) |> String.downcase()
    extension in @allowed_extensions
  end

  defp sanitize_filename(filename) do
    # Remove any path separators and special characters
    filename
    |> Path.basename()
    |> String.replace(~r/[^\w\.-]/, "_")
    # Limit length
    |> String.slice(0, 100)
  end

  defp upload_base_path do
    Application.get_env(:vyaasa_campus, :upload_base_path, @default_upload_base_path)
  end

  defp determine_processing_status(ats_score, _sanity_check) do
    ats_threshold = Application.get_env(:vyaasa_campus, :ats_threshold, 70.0)

    # Python sanity no longer has a low_confidence flag — use score threshold only
    if ats_score >= ats_threshold, do: "completed", else: "completed"
  end

  @doc """
  Auto-approves a student profile based on ATS criteria.
  Updates the student status to 'unverified' for admin review.
  """
  def auto_approve_profile(student, tenant_schema) do
    require Logger
    Logger.info("🔄 Auto-approving student profile: #{student.id} based on ATS score")
    Logger.info("🔍 Current student status: #{student.status}, tenant_schema: #{tenant_schema}")

    # Import the Students context to update student status
    alias VyaasaCampus.Contexts.Students

    update_attrs = %{
      status: "unverified",
      profile_completed: true,
      profile_submitted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    Logger.info("📝 Attempting to update student #{student.id} with attrs: #{inspect(update_attrs)}")

    case Students.update_student(student.id, update_attrs, tenant_schema) do
      {:ok, updated_student} ->
        Logger.info("✅ Student #{updated_student.id} status updated successfully!")

        Logger.info(
          "📊 Updated status: #{updated_student.status}, profile_completed: #{updated_student.profile_completed}"
        )

        {:auto_approved, "Profile meets ATS criteria for auto-approval"}

      {:error, changeset} ->
        Logger.error("❌ Failed to auto-approve student #{student.id}")
        Logger.error("🔍 Changeset errors: #{inspect(changeset.errors)}")
        Logger.error("🔍 Changeset valid?: #{changeset.valid?}")
        Logger.error("🔍 Changeset changes: #{inspect(changeset.changes)}")
        {:error, "Failed to update student status"}
    end
  end

  defp delete_file_from_filesystem(ats_phase) do
    if ats_phase.resume_url do
      file_path = get_resume_file_path(ats_phase.resume_url)
      if file_path, do: File.rm(file_path)
    end
  end
end
