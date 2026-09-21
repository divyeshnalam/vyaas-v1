defmodule VyaasaCampus.Jobs.AtsResumeProcessor do
  @moduledoc """
  Oban job for native Elixir resume scoring.

  Reads the uploaded resume, runs `VyaasaCampus.AI.ResumeScorer`, persists
  the result, and broadcasts completion to the student's PubSub topic so
  the LiveView dashboard refreshes.
  """

  use Oban.Worker,
    queue: :ats_processing,
    max_attempts: 3,
    priority: 1

  alias Ecto.Adapters.SQL
  alias VyaasaCampus.AI.ResumeScorer
  alias VyaasaCampus.Contexts.Jobs
  alias VyaasaCampus.Contexts.Tenant.JobProfiles
  alias VyaasaCampus.{Contexts.AtsUpload, Contexts.StudentAts, Repo}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ats_phase_id" => ats_phase_id, "tenant_schema" => tenant_schema}}) do
    require Logger
    Logger.info("Starting ATS processing job for phase #{ats_phase_id} in schema #{tenant_schema}")

    # Get the ATS phase record
    case StudentAts.get_by_id(ats_phase_id, tenant_schema) do
      nil ->
        Logger.error("ATS phase not found: #{ats_phase_id} in schema: #{tenant_schema}")
        {:error, "ATS phase not found: #{ats_phase_id} in schema: #{tenant_schema}"}

      ats_phase ->
        Logger.info("Found ATS phase #{ats_phase_id}, starting processing")
        process_ats_phase(ats_phase, tenant_schema)
    end
  end

  # Legacy support for old job format (without tenant_schema)
  def perform(%Oban.Job{args: %{"ats_phase_id" => ats_phase_id}}) do
    # Try to find the ATS phase in common tenant schemas
    # This is a fallback for jobs enqueued before the tenant_schema was added
    case find_ats_phase_in_any_tenant(ats_phase_id) do
      {:ok, {ats_phase, tenant_schema}} ->
        process_ats_phase(ats_phase, tenant_schema)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Legacy support for old job format
  def perform(%Oban.Job{args: %{"student_id" => student_id}}) do
    perform(%Oban.Job{args: %{"ats_phase_id" => student_id}})
  end

  @doc """
  Enqueues an ATS processing job for the given ATS phase.
  """
  def enqueue_processing(ats_phase, tenant_schema \\ "public") do
    require Logger
    Logger.info("Enqueueing ATS processing job for phase #{ats_phase.id} in schema #{tenant_schema}")

    result =
      %{ats_phase_id: ats_phase.id, tenant_schema: tenant_schema}
      |> new()
      |> Oban.insert()

    case result do
      {:ok, job} ->
        Logger.info("ATS processing job enqueued successfully: #{job.id}")
        {:ok, job}

      {:error, reason} ->
        Logger.error("Failed to enqueue ATS processing job: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      require Logger
      Logger.error("Failed to enqueue ATS processing job: #{inspect(error)}")
      {:error, "Failed to enqueue job: #{inspect(error)}"}
  end

  # Private functions

  defp process_ats_phase(ats_phase, tenant_schema) do
    # Opik filter labels for the resume.analyze trace this job emits.
    VyaasaCampus.AI.Tracing.put_metadata(%{student_id: ats_phase.student_id, module: "resume", tenant: tenant_schema})

    with {:ok, _} <- update_status(ats_phase, "processing", tenant_schema),
         {:ok, file_path} <- get_resume_file(ats_phase),
         {:ok, request_id} <- generate_request_id(ats_phase, tenant_schema) do
      run_native_pipeline(file_path, ats_phase, tenant_schema, request_id)
    else
      {:error, reason} ->
        AtsUpload.update_processing_attempt(ats_phase, reason, tenant_schema)
        {:error, reason}
    end
  end

  # ============================================================================
  # Native Elixir scoring path
  # ============================================================================

  defp run_native_pipeline(file_path, ats_phase, tenant_schema, request_id) do
    require Logger
    Logger.info("ATS | Native scorer starting | phase=#{ats_phase.id} | request=#{request_id}")

    case File.read(file_path) do
      {:ok, binary} ->
        profile_text = lookup_job_profile_text(ats_phase, tenant_schema)

        # Prefer the super-admin-authored canonical JD for this role as the
        # scoring rubric (decomposed + cached once, identical across tenants).
        # Fall back to the tenant profile text when no JD has been authored.
        job_description = lookup_role_jd(ats_phase) || profile_text

        opts = [
          job_description: job_description,
          job_profile: profile_text
        ]

        case ResumeScorer.run(binary, file_path, opts) do
          {:ok, service_response} ->
            service_response = Map.put(service_response, "request_id", request_id)
            handle_native_result(ats_phase, tenant_schema, service_response)

          {:error, reason} ->
            Logger.error("ATS | Native scorer failed | phase=#{ats_phase.id} | reason=#{inspect(reason)}")
            AtsUpload.update_processing_attempt(ats_phase, reason, tenant_schema)
            {:error, reason}
        end

      {:error, reason} ->
        msg = "Resume file unreadable: #{inspect(reason)}"
        AtsUpload.update_processing_attempt(ats_phase, msg, tenant_schema)
        {:error, msg}
    end
  end

  defp handle_native_result(ats_phase, tenant_schema, service_response) do
    require Logger

    case AtsUpload.update_ats_processing_results(ats_phase, service_response, tenant_schema) do
      {:ok, updated_phase} ->
        # The student's status stays "pending"/"profile_incomplete" here — it
        # only flips to "unverified" (and the profile_token is invalidated)
        # once the student clicks "Continue to Verification" on the results
        # step (see Students.finalize_profile_submission/2). Flipping it here
        # instead would invalidate the token before the student confirms,
        # so a refresh or dropped connection while reviewing the score would
        # wrongly show "already submitted".
        broadcast_completion(updated_phase)
        Logger.info("ATS | Native scorer complete | phase=#{updated_phase.id} | score=#{updated_phase.ats_score}")
        {:ok, "ATS scored natively"}

      {:error, changeset} ->
        msg = "Failed to persist native ATS result: #{inspect(changeset.errors)}"
        Logger.error("ATS | #{msg}")
        AtsUpload.update_processing_attempt(ats_phase, msg, tenant_schema)
        {:error, msg}
    end
  end

  # Look up the structured job-profile markdown for the student's chosen role
  # from the per-tenant `job_profiles` table. The `Relevance` module parses
  # **Core Technical Skills**, **Essential Tools**, and **Appreciated Skills**
  # sections out of this text. Falls back to the raw role name if no profile
  # exists — relevance scoring will then degrade gracefully.
  # The canonical JD the super admin authored for this role (public job_roles),
  # or nil when none is set. Used as the relevance-scoring rubric.
  defp lookup_role_jd(ats_phase) do
    role = ats_phase.preferred_role || ""

    case Jobs.get_job_role_by_title(role) do
      %{job_description: jd} when is_binary(jd) ->
        if String.trim(jd) == "", do: nil, else: jd

      _ ->
        nil
    end
  end

  defp lookup_job_profile_text(ats_phase, tenant_schema) do
    require Logger
    role = ats_phase.preferred_role || ""
    profile = JobProfiles.get_by_role(ats_phase.tenant_id, role, tenant_schema)

    cond do
      # 1. An explicit, structured job_profile for this tenant + role (best).
      is_map(profile) and is_binary(profile.profile_text) and profile.profile_text != "" ->
        Logger.info("ATS | Loaded job profile for role=#{inspect(role)}")
        profile.profile_text

      # 2. Build a relevance profile from the skills the super admin defined on
      #    the matching global job role (Jobs screen). These were previously
      #    never seen by the scorer — hence the weak relevance scores.
      profile_from_role = build_profile_from_role_skills(role) ->
        Logger.info("ATS | Built relevance profile from job-role skills for role=#{inspect(role)}")
        profile_from_role

      true ->
        Logger.warning(
          "ATS | No job profile or role skills for tenant=#{ats_phase.tenant_id} role=#{inspect(role)} — relevance scoring will be weak"
        )

        role
    end
  end

  # Turn the admin's flat skill list for a job role into the tier-headed profile
  # text the Relevance scorer parses (all skills go under Core Technical Skills).
  defp build_profile_from_role_skills(role) when is_binary(role) and role != "" do
    normalized = role |> String.trim() |> String.downcase()

    Jobs.list_active_job_roles()
    |> Enum.find(fn r -> String.downcase(to_string(r.title || "")) == normalized end)
    |> case do
      %{skills: skills} when is_list(skills) and skills != [] ->
        "**Core Technical Skills:**\n" <> Enum.join(skills, ", ")

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp build_profile_from_role_skills(_), do: nil

  defp broadcast_completion(updated_phase) do
    topic = "student:#{updated_phase.student_id}:ats_processing"
    payload = %{
      ats_phase_id: updated_phase.id,
      student_id: updated_phase.student_id,
      status: updated_phase.status
    }

    Phoenix.PubSub.broadcast(VyaasaCampus.PubSub, topic, {:ats_processing_complete, payload})
  end

  # Fallback function to find ATS phase in any tenant (for legacy jobs)
  defp find_ats_phase_in_any_tenant(ats_phase_id) do
    case get_tenant_schemas() do
      {:ok, tenant_schemas} ->
        search_ats_phase_in_schemas(ats_phase_id, tenant_schemas)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_tenant_schemas do
    case SQL.query(
           Repo,
           "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'tenant_%'"
         ) do
      {:ok, %{rows: rows}} ->
        tenant_schemas = Enum.map(rows, fn [schema] -> schema end)
        {:ok, tenant_schemas}

      {:error, _} ->
        {:error, "Failed to query tenant schemas"}
    end
  end

  defp search_ats_phase_in_schemas(ats_phase_id, tenant_schemas) do
    Enum.find_value(tenant_schemas, {:error, "ATS phase not found in any tenant"}, fn schema ->
      find_ats_phase_in_schema(ats_phase_id, schema)
    end)
  end

  defp find_ats_phase_in_schema(ats_phase_id, schema) do
    case StudentAts.get_by_id(ats_phase_id, schema) do
      nil -> nil
      ats_phase -> {:ok, {ats_phase, schema}}
    end
  end

  defp update_status(ats_phase, status, tenant_schema) do
    case StudentAts.update_status(ats_phase, status, tenant_schema) do
      {:ok, _} -> {:ok, :updated}
      {:error, changeset} -> {:error, "Failed to update status: #{inspect(changeset.errors)}"}
    end
  end

  defp get_resume_file(ats_phase) do
    case AtsUpload.get_resume_file_path(ats_phase.resume_url) do
      nil -> {:error, "Resume file not found: #{ats_phase.resume_url}"}
      file_path -> {:ok, file_path}
    end
  end

  defp generate_request_id(ats_phase, tenant_schema) do
    request_id = Ecto.UUID.generate()

    # Update ATS phase with idempotency key
    case AtsUpload.update_ats_fields(ats_phase, %{idempotency_key: request_id}, tenant_schema) do
      {:ok, _} -> {:ok, request_id}
      {:error, _} -> {:error, "Failed to generate request ID"}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 1min, 4min, 9min
    attempt * attempt * 60
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end
