defmodule VyaasaCampus.Contexts.StudentAts do
  @moduledoc """
  Context for managing Student ATS (Applicant Tracking System) data.

  This module provides functions for creating, updating, and retrieving
  ATS data that comes from the Python resume analysis service.
  """

  import Ecto.Query, warn: false
  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.{Student, StudentAtsPhase}

  @doc """
  Creates an ATS phase record from Python service response.

  ## Parameters
    - service_data: The JSON response from the Python ATS service
    - student_id: The ID of the student
    - tenant_id: The tenant ID

  ## Examples

      iex> create_ats_phase_from_service(service_data, student_id, tenant_id)
      {:ok, %StudentAtsPhase{}}

      iex> create_ats_phase_from_service(bad_data, student_id, tenant_id)
      {:error, %Ecto.Changeset{}}
  """
  def create_ats_phase_from_service(service_data, student_id, tenant_id) do
    %StudentAtsPhase{}
    |> StudentAtsPhase.create_from_service_changeset(service_data, student_id, tenant_id)
    |> Repo.insert()
  end

  @doc """
  Updates an existing ATS phase record with new service data.
  """
  def update_ats_phase_from_service(ats_phase, service_data, tenant_schema \\ "public") do
    require Logger

    processed_attrs =
      base_completion_attrs()
      |> Map.merge(extract_service_data_fields(service_data))

    Logger.info("=== ATS DATA EXTRACTION DEBUG ===")
    Logger.info("Service data keys: #{inspect(Map.keys(service_data))}")
    Logger.info("Processed attrs keys: #{inspect(Map.keys(processed_attrs))}")
    Logger.info("Personal information: #{inspect(processed_attrs[:personal_information])}")
    Logger.info("Skills: #{inspect(processed_attrs[:skills])}")
    Logger.info("Projects: #{inspect(processed_attrs[:projects])}")
    Logger.info("Portfolio and links: #{inspect(processed_attrs[:portfolio_and_links])}")
    Logger.info("==================================")

    case ats_phase
         |> StudentAtsPhase.changeset(processed_attrs)
         |> Repo.update(prefix: tenant_schema) do
      {:ok, updated_ats_phase} ->
        Logger.info("✅ ATS phase updated successfully: #{updated_ats_phase.id}")
        DashboardEvents.broadcast_ats_event(:updated, tenant_schema, updated_ats_phase.student_id)
        publish_ai8(updated_ats_phase, tenant_schema)
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:resume, updated_ats_phase.id, tenant_schema)
        {:ok, updated_ats_phase}

      {:error, changeset} ->
        Logger.error("❌ Failed to update ATS phase: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp base_completion_attrs do
    %{
      status: "completed",
      processed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  # Publish the resume's ATS score into the AI8 framework. Resume evidences the
  # candidate's domain/technical standing, so the overall ATS score maps to the
  # domain_expertise dimension.
  defp publish_ai8(ats_phase, tenant_schema) do
    score = StudentAtsPhase.get_overall_score(ats_phase) |> to_number()

    AI8.publish_module(
      "resume",
      %{"domain_expertise" => score},
      %{
        student_id: ats_phase.student_id,
        tenant_id: ats_phase.tenant_id,
        source_type: "student_ats_phase",
        source_id: ats_phase.id
      },
      tenant_schema
    )
  end

  defp to_number(%Decimal{} = d), do: d |> Decimal.to_float() |> round()
  defp to_number(n) when is_number(n), do: round(n)
  defp to_number(_), do: nil

  defp extract_service_data_fields(service_data) do
    extract_metadata_fields(service_data)
    |> Map.merge(extract_profile_data_fields(service_data))
    |> Map.merge(extract_experience_data_fields(service_data))
    |> Map.merge(extract_analysis_data_fields(service_data))
  end

  defp extract_metadata_fields(service_data) do
    %{
      metadata: service_data["metadata"] || %{}
    }
  end

  defp extract_profile_data_fields(service_data) do
    require Logger

    # NEW STRUCTURE: Data is directly in service_data or in groq_data
    raw_data = get_raw_data(service_data)
    groq_data = get_groq_data(service_data, raw_data)
    completeness_data = service_data["completeness"] || service_data[:completeness] || %{}

    log_debug_info(service_data, raw_data, groq_data)

    %{
      personal_information: extract_personal_info(groq_data),
      portfolio_and_links: extract_portfolio_links(completeness_data),
      professional_summary: extract_professional_summary(groq_data),
      skills: extract_skills(groq_data)
    }
  end

  defp get_raw_data(service_data) do
    service_data[:raw_result_json] || service_data["raw_result_json"] || %{}
  end

  defp get_groq_data(service_data, raw_data) do
    # NEW: Try direct groq_data first, then corrected_groq_data from completeness, then raw_data
    service_data["groq_data"] || service_data[:groq_data] ||
      get_in(service_data, ["completeness", "corrected_groq_data"]) ||
      get_in(service_data, [:completeness, :corrected_groq_data]) ||
      raw_data["corrected_groq_data"] ||
      raw_data["groq_data"] ||
      %{}
  end

  defp log_debug_info(service_data, raw_data, groq_data) do
    require Logger

    Logger.info("=== DEBUGGING SERVICE DATA STRUCTURE ===")
    Logger.info("Service data keys: #{inspect(Map.keys(service_data))}")
    Logger.info("Raw data keys: #{inspect(Map.keys(raw_data))}")
    Logger.info("Has corrected_groq_data: #{Map.has_key?(raw_data, "corrected_groq_data")}")
    Logger.info("Has groq_data: #{Map.has_key?(raw_data, "groq_data")}")
    Logger.info("Has other_links: #{Map.has_key?(raw_data, "other_links")}")
    Logger.info("Other links value: #{inspect(raw_data["other_links"])}")
    Logger.info("Groq data keys: #{inspect(Map.keys(groq_data))}")
    Logger.info("Groq data: #{inspect(groq_data)}")
  end

  defp extract_personal_info(groq_data) do
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

  defp extract_portfolio_links(completeness_data) do
    # NEW: other_links is now in completeness object
    other_links = completeness_data["other_links"] || completeness_data[:other_links] || []

    %{"other_links" => other_links}
  end

  defp extract_professional_summary(groq_data) do
    # NEW: Total_Experience is now in groq_data
    %{
      "summary_text" => groq_data["Professional_Summary"] || [],
      "total_experience" => groq_data["Total_Experience"]
    }
  end

  defp extract_skills(groq_data) do
    skills_data = groq_data["Skills"] || %{}

    %{
      "technical_skills" => skills_data["Technical"] || [],
      "non_technical_skills" => skills_data["Non-Technical"] || [],
      "languages_spoken" => groq_data["Languages_Spoken"] || []
    }
  end

  defp extract_experience_data_fields(service_data) do
    raw_data = get_raw_data(service_data)
    groq_data = get_groq_data(service_data, raw_data)

    # NEW: All data is now in groq_data with consistent naming
    work_experience = normalize_work_experience(groq_data["Work_Experience"] || [])
    projects = normalize_projects(groq_data["Projects"] || [])
    education = groq_data["Education"] || []
    certifications = groq_data["Certifications"] || []
    languages = extract_languages(groq_data)
    achievements_and_activities = extract_achievements(groq_data)

    log_experience_extraction(
      work_experience,
      projects,
      education,
      certifications,
      languages,
      achievements_and_activities
    )

    %{
      work_experience: work_experience,
      projects: projects,
      education: education,
      certifications: certifications,
      languages: languages,
      achievements_and_activities: achievements_and_activities
    }
  end

  # NEW: Normalize work experience to match our expected format
  defp normalize_work_experience(work_exp) when is_list(work_exp) do
    Enum.map(work_exp, fn exp ->
      # NEW STRUCTURE: Responsibilities is now an array, convert to string
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

  defp normalize_work_experience(_), do: []

  # NEW: Normalize projects to match our expected format
  defp normalize_projects(projects) when is_list(projects) do
    Enum.map(projects, fn project ->
      # NEW STRUCTURE: Description is now an array
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
        # Preserve each project's repo link — the parser extracts it but it was
        # being dropped here, so project GitHub repos never reached the UI.
        "Github_Link" => project["Github_Link"] || project["github_link"] || ""
      }
    end)
  end

  defp normalize_projects(_), do: []

  defp extract_languages(groq_data) do
    case groq_data["Languages_Spoken"] do
      lang_list when is_list(lang_list) ->
        Enum.map(lang_list, fn lang -> %{"language" => lang, "proficiency" => "Not specified"} end)

      _ ->
        []
    end
  end

  defp extract_achievements(groq_data) do
    case groq_data["Achievements"] do
      achievement_list when is_list(achievement_list) ->
        Enum.map(achievement_list, fn achievement -> %{"achievement" => achievement, "description" => ""} end)

      _ ->
        []
    end
  end

  defp log_experience_extraction(
         work_experience,
         projects,
         education,
         certifications,
         languages,
         achievements_and_activities
       ) do
    require Logger

    Logger.info("=== EXPERIENCE DATA EXTRACTION ===")
    Logger.info("Work experience: #{inspect(work_experience)}")
    Logger.info("Projects: #{inspect(projects)}")
    Logger.info("Education: #{inspect(education)}")
    Logger.info("Certifications: #{inspect(certifications)}")
    Logger.info("Languages: #{inspect(languages)}")
    Logger.info("Achievements: #{inspect(achievements_and_activities)}")
    Logger.info("===================================")
  end

  defp extract_analysis_data_fields(service_data) do
    require Logger

    # NEW STRUCTURE: Data is directly in service_data
    # Try new structure first, then fall back to old structure
    completeness = service_data["completeness"] || service_data[:completeness] || %{}
    relevance = service_data["relevance"] || service_data[:relevance] || %{}
    sanity = service_data["sanity"] || service_data[:sanity] || %{}

    # NEW: final_score is at root level
    ats_score =
      service_data["final_score"] || service_data[:final_score] ||
        service_data["ats_score"] || service_data[:ats_score]

    # Build comprehensive metadata from new structure
    metadata = build_metadata_from_new_structure(completeness, relevance, sanity)

    Logger.info("=== ANALYSIS DATA EXTRACTION (NEW STRUCTURE) ===")
    Logger.info("Completeness score: #{completeness["score"]}")
    Logger.info("Relevance score: #{relevance["score"]}")
    Logger.info("Sanity score: #{sanity["score"]}")
    Logger.info("Final ATS score: #{inspect(ats_score)}")
    Logger.info("=================================")

    %{
      sanity_check: sanity,
      # Not in new structure
      extracted_raw_text_snippets: %{},
      ats_score: ats_score,
      # Store entire response
      raw_result_json: service_data,
      metadata: metadata,
      callback_received_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  defp build_metadata_from_new_structure(completeness, relevance, sanity) do
    %{
      "completeness_score" => completeness["score"],
      "completeness_feedback" => completeness["feedback"] || [],
      "relevance_score" => relevance["score"],
      "relevance_justification" => get_in(relevance, ["details", "justification"]),
      "matching_keywords" => get_in(relevance, ["details", "matching_keywords"]) || [],
      "missing_keywords" => get_in(relevance, ["details", "missing_keywords"]) || [],
      "sanity_score" => sanity["score"] || sanity["final_score"],
      "sanity_status" => sanity["status"],
      "sanity_structural_findings" => get_in(sanity, ["structural_report", "findings"]) || [],
      "sanity_linguistic_feedback" => get_in(sanity, ["linguistic_report", "feedback"])
    }
  end

  @doc """
  Creates a processing record when a resume is uploaded.
  """
  def create_processing_record(student_id, tenant_id, resume_url, tenant_schema \\ "public") do
    attrs = %{
      student_id: student_id,
      tenant_id: tenant_id,
      resume_url: resume_url,
      status: "processing"
    }

    %StudentAtsPhase{}
    |> StudentAtsPhase.changeset(attrs)
    |> Repo.insert(prefix: tenant_schema)
  end

  @doc """
  Creates an ATS phase record with student profile fields.
  Used when a student completes their profile with ATS-related data.
  """
  def create_ats_phase_with_profile(student_id, tenant_id, attrs, tenant_schema \\ "public") do
    ats_attrs = %{
      student_id: student_id,
      tenant_id: tenant_id,
      resume_url: attrs[:resume_url],
      preferred_role: attrs[:preferred_role],
      college_id_card_url: attrs[:college_id_card_url],
      profile_picture_url: attrs[:profile_picture_url],
      # Will be processed by ATS service
      status: "processing"
    }

    %StudentAtsPhase{}
    |> StudentAtsPhase.changeset(ats_attrs)
    |> Repo.insert(prefix: tenant_schema)
  end

  @doc """
  Updates ATS fields for an existing ATS phase record.
  """
  def update_ats_fields(ats_phase, attrs, tenant_schema \\ "public") do
    ats_phase
    |> StudentAtsPhase.update_ats_fields_changeset(attrs)
    |> Repo.update(prefix: tenant_schema)
    |> case do
      {:ok, updated} = ok ->
        DashboardEvents.broadcast_ats_event(:updated, tenant_schema, updated.student_id)
        ok

      other ->
        other
    end
  end

  @doc """
  Updates the student-editable profile fields (bio, location, skills/tags,
  profile picture) on an existing ATS phase record. Used by the student
  profile page, which only touches these fields — not the resume/ATS
  scoring data that the rest of this module manages.
  """
  def update_profile_fields(ats_phase, attrs, tenant_schema \\ "public") do
    ats_phase
    |> StudentAtsPhase.changeset(attrs)
    |> Repo.update(prefix: tenant_schema)
  end

  @doc """
  Gets the student's ATS phase, creating a placeholder one if they haven't
  gone through resume analysis yet. `resume_url` is `NOT NULL` at the DB
  level, so a sentinel value is used until a real resume is uploaded — this
  just gives the student profile page (avatar/bio/location/tags) somewhere
  to persist to.
  """
  def ensure_profile_phase(student, tenant_schema \\ "public") do
    case get_by_student_id(student.id, tenant_schema) do
      nil ->
        attrs = %{
          student_id: student.id,
          tenant_id: student.tenant_id,
          resume_url: "profile-only://no-resume",
          status: "manual_review",
          attempt_number: next_attempt_number(student.id, tenant_schema)
        }

        %StudentAtsPhase{}
        |> StudentAtsPhase.changeset(attrs)
        |> Repo.insert(prefix: tenant_schema)

      ats_phase ->
        {:ok, ats_phase}
    end
  end

  @doc """
  Updates the status of an ATS phase record.
  """
  def update_status(ats_phase, status, tenant_schema \\ "public")
      when status in ["processing", "completed", "failed", "manual_review", "queued", "errored"] do
    ats_phase
    |> StudentAtsPhase.status_changeset(status)
    |> Repo.update(prefix: tenant_schema)
  end

  @doc """
  Marks an ATS phase as failed.
  """
  def mark_as_failed(ats_phase) do
    update_status(ats_phase, "failed")
  end

  @doc """
  Gets the ATS phase record for a student.
  """
  def get_by_student_id(student_id, tenant_schema \\ "public") do
    # Returns the LATEST attempt (highest attempt_number).
    # History-aware callers should use list_all_by_student/2 or get_latest_by_student/2.
    from(ats in StudentAtsPhase,
      where: ats.student_id == ^student_id,
      order_by: [desc: ats.attempt_number, desc: ats.inserted_at],
      limit: 1
    )
    |> Repo.one(prefix: tenant_schema)
  end

  @doc """
  Lists all ATS phases for a student, newest first.
  Used to display re-analysis history and score trends.
  """
  def list_all_by_student(student_id, tenant_schema \\ "public") do
    from(ats in StudentAtsPhase,
      where: ats.student_id == ^student_id,
      order_by: [desc: ats.attempt_number, desc: ats.inserted_at]
    )
    |> Repo.all(prefix: tenant_schema)
  end

  @doc """
  Compute the next attempt_number for this student.
  """
  def next_attempt_number(student_id, tenant_schema \\ "public") do
    current =
      from(ats in StudentAtsPhase,
        where: ats.student_id == ^student_id,
        select: max(ats.attempt_number)
      )
      |> Repo.one(prefix: tenant_schema)

    (current || 0) + 1
  end

  @doc """
  Creates a new ATS phase for a re-analysis attempt, carrying forward the
  previously verified ID card and profile picture so the student doesn't
  need to re-upload them.

  ## Parameters
    - student_id, tenant_id
    - attrs: at minimum `resume_url` and `preferred_role`
    - tenant_schema
  """
  def create_reanalysis_phase(student_id, tenant_id, attrs, tenant_schema \\ "public") do
    # Only re-analysis is capped. The FIRST resume upload updates the existing
    # phase in place rather than inserting, so onboarding can never be blocked
    # by a resume attempt limit.
    with :ok <- VyaasaCampus.Contexts.AttemptGuard.check(student_id, :resume, tenant_id, tenant_schema) do
      do_create_reanalysis_phase(student_id, tenant_id, attrs, tenant_schema)
    end
  end

  defp do_create_reanalysis_phase(student_id, tenant_id, attrs, tenant_schema) do
    attempt_number = next_attempt_number(student_id, tenant_schema)

    # Carry forward verified documents from the latest prior phase
    prior = get_by_student_id(student_id, tenant_schema)

    ats_attrs = %{
      student_id: student_id,
      tenant_id: tenant_id,
      resume_url: attrs[:resume_url],
      preferred_role: attrs[:preferred_role],
      college_id_card_url: attrs[:college_id_card_url] || (prior && prior.college_id_card_url),
      profile_picture_url: attrs[:profile_picture_url] || (prior && prior.profile_picture_url),
      status: "queued",
      processing_attempts: 0,
      attempt_number: attempt_number
    }

    %StudentAtsPhase{}
    |> StudentAtsPhase.changeset(ats_attrs)
    |> Repo.insert(prefix: tenant_schema)
  end

  @doc """
  Gets the ATS phase record by its ID.
  """
  def get_by_id(ats_phase_id, tenant_schema \\ "public") do
    Repo.get(StudentAtsPhase, ats_phase_id, prefix: tenant_schema)
  end

  @doc """
  Gets the ATS phase record by idempotency key.
  Used for callback processing to find the original request.
  Searches across all active tenant schemas.
  """
  def get_by_idempotency_key(request_id) do
    # Get all active tenant schemas to search
    case get_active_tenant_schemas() do
      [] ->
        {:error, :not_found}

      schemas ->
        find_in_tenant_schemas(request_id, schemas)
    end
  end

  defp get_active_tenant_schemas do
    # Get all tenants and extract their schema names
    alias VyaasaCampus.Contexts.Tenants

    try do
      Tenants.list_tenants()
      |> Enum.map(& &1.schema_name)
    rescue
      _ ->
        # Fallback to known schemas if tenant listing fails
        ["tenant_gbit", "public"]
    end
  end

  defp find_in_tenant_schemas(request_id, schemas) do
    require Logger
    Logger.info("Searching for ATS phase with idempotency_key: #{request_id} across #{length(schemas)} schemas")

    Enum.find_value(schemas, fn schema ->
      Logger.debug("Searching in schema: #{schema}")

      case Repo.get_by(StudentAtsPhase, [idempotency_key: request_id], prefix: schema) do
        nil ->
          nil

        ats_phase ->
          Logger.info("Found ATS phase in schema: #{schema}")
          {:ok, ats_phase}
      end
    end) || {:error, :not_found}
  end

  @doc """
  Gets the ATS phase record for a student, raises if not found.
  """
  def get_by_student_id!(student_id) do
    Repo.get_by!(StudentAtsPhase, student_id: student_id)
  end

  @doc """
  Gets all ATS phase records for a tenant with optional status filter.
  """
  def list_by_tenant(tenant_id, opts \\ []) do
    query = from(ats in StudentAtsPhase, where: ats.tenant_id == ^tenant_id)

    query =
      if status = opts[:status] do
        from(ats in query, where: ats.status == ^status)
      else
        query
      end

    query =
      if opts[:preload_student] do
        from(ats in query, preload: [:student])
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets student with their ATS phase data.
  """
  def get_student_with_ats(student_id) do
    case Repo.get(Student, student_id) do
      nil -> nil
      student -> Repo.preload(student, :ats_phase)
    end
  end

  @doc """
  Gets ATS fields for a student.
  Returns a map with preferred_role, resume_url, college_id_card_url, profile_picture_url
  """
  def get_student_ats_fields(student_id, tenant_schema \\ "public") do
    case get_by_student_id(student_id, tenant_schema) do
      nil ->
        %{
          preferred_role: nil,
          resume_url: nil,
          college_id_card_url: nil,
          profile_picture_url: nil
        }

      ats_phase ->
        %{
          preferred_role: ats_phase.preferred_role,
          resume_url: ats_phase.resume_url,
          college_id_card_url: ats_phase.college_id_card_url,
          profile_picture_url: ats_phase.profile_picture_url
        }
    end
  end

  @doc """
  Gets preferred role for a student.
  """
  def get_student_preferred_role(student_id, tenant_schema \\ "public") do
    case get_by_student_id(student_id, tenant_schema) do
      nil -> nil
      ats_phase -> ats_phase.preferred_role
    end
  end

  @doc """
  Checks if a student has completed ATS processing.
  """
  def ats_completed?(student_id, tenant_schema \\ "public") do
    case get_by_student_id(student_id, tenant_schema) do
      nil -> false
      ats_phase -> ats_phase.status in ["completed", "manual_review", "errored"]
    end
  end

  @doc """
  Gets the overall ATS score for a student.
  """
  def get_student_ats_score(student_id, tenant_schema \\ "public") do
    case get_by_student_id(student_id, tenant_schema) do
      nil -> 0
      ats_phase -> StudentAtsPhase.get_overall_score(ats_phase)
    end
  end

  @doc """
  Gets areas for improvement for a student based on ATS analysis.
  """
  def get_areas_for_improvement(student_id, tenant_schema \\ "public") do
    case get_by_student_id(student_id, tenant_schema) do
      nil -> %{}
      ats_phase -> StudentAtsPhase.get_areas_for_improvement(ats_phase)
    end
  end

  @doc """
  Gets matching and missing keywords for a student.
  """
  def get_keyword_analysis(student_id) do
    case get_by_student_id(student_id) do
      nil ->
        %{matching: [], missing: []}

      ats_phase ->
        %{
          matching: StudentAtsPhase.get_matching_keywords(ats_phase),
          missing: StudentAtsPhase.get_missing_keywords(ats_phase)
        }
    end
  end

  @doc """
  Deletes an ATS phase record.
  """
  def delete_ats_phase(ats_phase) do
    Repo.delete(ats_phase)
  end

  @doc """
  Gets all processing ATS records (for monitoring/cleanup).
  """
  def list_processing_records do
    from(ats in StudentAtsPhase, where: ats.status == "processing")
    |> Repo.all()
  end

  @doc """
  Gets all failed ATS records (for error monitoring).
  """
  def list_failed_records do
    from(ats in StudentAtsPhase, where: ats.status == "failed")
    |> Repo.all()
  end

  @doc """
  Gets paginated ATS phases for a tenant with optional filters.
  """
  def list_by_tenant_paginated(tenant_id, opts \\ []) do
    query =
      from(ats in StudentAtsPhase,
        where: ats.tenant_id == ^tenant_id,
        preload: [:student]
      )

    # Apply status filter
    query =
      if status = opts[:status] do
        from(ats in query, where: ats.status == ^status)
      else
        query
      end

    # Apply search filter
    query =
      case opts[:query] do
        search_query when is_binary(search_query) and search_query != "" ->
          search_pattern = "%#{search_query}%"

          from(ats in query,
            join: s in assoc(ats, :student),
            where:
              ilike(s.first_name, ^search_pattern) or
                ilike(s.last_name, ^search_pattern) or
                ilike(s.email, ^search_pattern)
          )

        _ ->
          query
      end

    # Get total count
    total_count = Repo.aggregate(query, :count, :id)

    # Apply pagination
    page = opts[:page] || 1
    per_page = opts[:per_page] || 20
    offset = (page - 1) * per_page

    results =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    {results, total_count}
  end

  @doc """
  Updates student profile completion status.
  """
  def approve_student_profile(_student_id) do
    # This would integrate with your existing approval workflow
    # For now, just return success
    {:ok, :approved}
  end

  @doc """
  Rejects student profile with notes.
  """
  def reject_student_profile(_student_id, _notes) do
    # This would integrate with your existing rejection workflow
    # For now, just return success
    {:ok, :rejected}
  end
end
