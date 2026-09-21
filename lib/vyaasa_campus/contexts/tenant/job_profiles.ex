defmodule VyaasaCampus.Contexts.Tenant.JobProfiles do
  @moduledoc """
  The JobProfiles context for managing job profiles within a tenant.

  This module handles:
  - Creating and updating job profiles
  - Listing job profiles by tenant
  - Managing job profile lifecycle
  """

  import Ecto.Query, warn: false
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Tenants.JobProfile

  @doc """
  Returns the list of job profiles for a tenant.
  """
  def list_by_tenant(tenant_id, tenant_schema \\ "public") do
    from(jp in JobProfile,
      where: jp.tenant_id == ^tenant_id,
      order_by: [asc: jp.role]
    )
    |> Repo.all(prefix: tenant_schema)
  end

  @doc """
  Gets a single job_profile by ID.
  """
  def get_job_profile!(id), do: Repo.get!(JobProfile, id)

  @doc """
  Gets a single job_profile by ID.
  """
  def get_job_profile(id), do: Repo.get(JobProfile, id)

  @doc """
  Gets a job_profile by tenant and role name. Used by the resume scoring
  pipeline to look up the structured `profile_text` for a student's
  preferred_role at scoring time.

  Role lookup is case-insensitive so "Software Engineer" matches
  "software engineer" in the seeds.
  """
  def get_by_role(tenant_id, role, tenant_schema)
      when is_binary(role) and is_binary(tenant_schema) do
    normalized = role |> String.trim() |> String.downcase()

    from(jp in JobProfile,
      where: jp.tenant_id == ^tenant_id and fragment("lower(?)", jp.role) == ^normalized,
      limit: 1
    )
    |> Repo.one(prefix: tenant_schema)
  end

  def get_by_role(_, _, _), do: nil

  @doc """
  Creates a job profile.
  """
  def create_job_profile(attrs \\ %{}) do
    %JobProfile{}
    |> JobProfile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a job profile.
  """
  def update_job_profile(%JobProfile{} = job_profile, attrs) do
    job_profile
    |> JobProfile.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a job profile.
  """
  def delete_job_profile(%JobProfile{} = job_profile) do
    Repo.delete(job_profile)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking job_profile changes.
  """
  def change_job_profile(%JobProfile{} = job_profile, attrs \\ %{}) do
    JobProfile.changeset(job_profile, attrs)
  end

  @doc """
  Gets job profiles for a tenant formatted as {role, id} tuples for dropdowns.
  """
  def list_job_profiles_for_dropdown(tenant_id, tenant_schema \\ "public") do
    list_by_tenant(tenant_id, tenant_schema)
    |> Enum.map(&{&1.role, &1.id})
  end
end
