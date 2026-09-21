defmodule VyaasaCampus.Contexts.Jobs do
  @moduledoc """
  Context for managing industries and job roles.
  Data lives in public schema, shared across all tenants.
  """

  import Ecto.Query
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Platform.{Industry, JobRole, JobRoleSubject}
  alias VyaasaCampus.Schema.QuestionBank.Subject

  # ============================================================================
  # INDUSTRIES
  # ============================================================================

  def list_industries do
    Industry
    |> order_by(:name)
    |> Repo.all()
  end

  def list_active_industries do
    Industry
    |> where([i], i.is_active == true)
    |> order_by(:name)
    |> Repo.all()
  end

  def get_industry!(id), do: Repo.get!(Industry, id)

  def create_industry(attrs) do
    %Industry{}
    |> Industry.changeset(attrs)
    |> Repo.insert()
  end

  def update_industry(%Industry{} = industry, attrs) do
    industry
    |> Industry.changeset(attrs)
    |> Repo.update()
  end

  def delete_industry(%Industry{} = industry) do
    Repo.delete(industry)
  end

  # ============================================================================
  # JOB ROLES
  # ============================================================================

  def list_job_roles do
    JobRole
    |> preload(:industry)
    |> order_by(:title)
    |> Repo.all()
  end

  def list_active_job_roles do
    JobRole
    |> where([jr], jr.is_active == true)
    |> preload(:industry)
    |> order_by(:title)
    |> Repo.all()
  end

  def list_job_roles_by_industry(industry_id) do
    JobRole
    |> where([jr], jr.industry_id == ^industry_id)
    |> order_by(:title)
    |> Repo.all()
  end

  def list_active_job_roles_grouped do
    industries = list_active_industries()

    Enum.map(industries, fn industry ->
      roles =
        JobRole
        |> where([jr], jr.industry_id == ^industry.id and jr.is_active == true)
        |> order_by(:title)
        |> Repo.all()

      {industry, roles}
    end)
    |> Enum.reject(fn {_industry, roles} -> roles == [] end)
  end

  def get_job_role!(id), do: Repo.get!(JobRole, id) |> Repo.preload(:industry)

  @doc """
  Find an active job role by (case-insensitive) title — used to resolve a
  student's `preferred_role` to the super-admin's skills + JD description.
  Returns the `JobRole` or `nil`.
  """
  def get_active_job_role_by_title(title) when is_binary(title) do
    normalized = title |> String.trim() |> String.downcase()

    if normalized == "" do
      nil
    else
      JobRole
      |> where([jr], jr.is_active == true and fragment("lower(?)", jr.title) == ^normalized)
      |> limit(1)
      |> Repo.one()
    end
  end

  def get_active_job_role_by_title(_), do: nil

  def create_job_role(attrs) do
    %JobRole{}
    |> JobRole.changeset(attrs)
    |> Repo.insert()
  end

  def update_job_role(%JobRole{} = job_role, attrs) do
    job_role
    |> JobRole.changeset(attrs)
    |> Repo.update()
  end

  def delete_job_role(%JobRole{} = job_role) do
    Repo.delete(job_role)
  end

  @doc """
  Returns all active job role titles as a flat list.
  Used by student profile completion for the role picker.
  """
  def list_active_job_role_titles do
    JobRole
    |> where([jr], jr.is_active == true)
    |> select([jr], jr.title)
    |> order_by(:title)
    |> Repo.all()
  end

  @doc """
  Returns active job roles grouped by industry for the student picker.
  Returns: [{industry_name, [role_title, ...]}, ...]
  """
  def list_active_roles_for_picker do
    query = """
    SELECT i.name as industry_name, jr.title as role_title
    FROM public.job_roles jr
    INNER JOIN public.industries i ON jr.industry_id = i.id
    WHERE jr.is_active = true AND i.is_active = true
    ORDER BY i.name, jr.title
    """

    case Repo.query(query) do
      {:ok, %{rows: rows}} ->
        rows
        |> Enum.group_by(fn [industry, _] -> industry end, fn [_, role] -> role end)
        |> Enum.sort_by(fn {industry, _} -> industry end)

      _ ->
        []
    end
  end

  def industry_stats do
    query = """
    SELECT i.id, i.name, i.is_active, COUNT(jr.id)::integer as role_count
    FROM public.industries i
    LEFT JOIN public.job_roles jr ON jr.industry_id = i.id
    GROUP BY i.id, i.name, i.is_active
    ORDER BY i.name
    """

    case Repo.query(query) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name, is_active, role_count] ->
          %{id: id, name: name, is_active: is_active, role_count: role_count}
        end)

      _ ->
        []
    end
  end

  # ============================================================================
  # ROLE → SUBJECT BLUEPRINT (role-aware MCQ selection — Vya-036)
  # ============================================================================

  @doc "Find an active job role by (case-insensitive) title, else nil."
  def get_job_role_by_title(title) when is_binary(title) do
    t = title |> String.trim() |> String.downcase()

    JobRole
    |> where([r], fragment("lower(?)", r.title) == ^t)
    |> limit(1)
    |> Repo.one()
  end

  def get_job_role_by_title(_), do: nil

  @doc "All job roles with their industry preloaded (for the cards view)."
  def list_all_roles_with_industry do
    JobRole
    |> order_by([r], r.title)
    |> preload(:industry)
    |> Repo.all()
  end

  @doc "How many subjects each role has mapped (role_id => count)."
  def role_subject_counts do
    JobRoleSubject
    |> group_by([j], j.job_role_id)
    |> select([j], {j.job_role_id, count(j.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "All subjects (question-bank), for the admin subject picker."
  def list_subjects do
    Subject
    |> order_by([s], s.name)
    |> Repo.all()
  end

  # ── Question-bank cascade for the role subject picker ───────────────────────
  # qualifications (Degree) → branches → curricula → curricula_subjects → subjects

  defp qb_rows(sql, params \\ []) do
    Repo.query!(sql, params).rows
    |> Enum.map(fn [id, name] -> %{id: id, name: name} end)
  end

  @doc "Degrees (qualifications)."
  def qb_degrees, do: qb_rows("SELECT id, name FROM qualifications ORDER BY name")

  @doc "Branches under a degree (qualification)."
  def qb_branches(nil), do: []

  def qb_branches(qualification_id),
    do: qb_rows("SELECT id, name FROM branches WHERE qualification_id = $1 ORDER BY name", [qualification_id])

  @doc "Curricula under a branch."
  def qb_curricula(nil), do: []

  def qb_curricula(branch_id),
    do: qb_rows("SELECT id, name FROM curricula WHERE branch_id = $1 ORDER BY name", [branch_id])

  @doc "Subjects mapped to a curriculum (that have questions countable elsewhere)."
  def qb_subjects(nil), do: []

  def qb_subjects(curricula_id) do
    qb_rows(
      """
      SELECT DISTINCT s.id, s.name
      FROM subjects s
      JOIN curricula_subjects cs ON cs.subject_id = s.id
      WHERE cs.curricula_id = $1
      ORDER BY s.name
      """,
      [curricula_id]
    )
  end

  @doc "The `%JobRoleSubject{}` rows for a role, with subject preloaded."
  def get_role_subjects(job_role_id) do
    JobRoleSubject
    |> where([jrs], jrs.job_role_id == ^job_role_id)
    |> preload(:subject)
    |> Repo.all()
  end

  @doc """
  The role's blueprint as `[{subject_id, question_count}]`, only entries with a
  positive quota. Empty list means the role has no MCQ blueprint configured.
  """
  def role_blueprint(job_role_id) do
    JobRoleSubject
    |> where([jrs], jrs.job_role_id == ^job_role_id and jrs.question_count > 0)
    |> select([jrs], {jrs.subject_id, jrs.question_count})
    |> Repo.all()
  end

  @doc """
  Replace a role's subject blueprint. `entries` is a list of
  `%{subject_id: id, question_count: n}`; entries with count <= 0 are dropped.
  """
  def set_role_subjects(job_role_id, entries) when is_list(entries) do
    Repo.transaction(fn ->
      Repo.delete_all(from jrs in JobRoleSubject, where: jrs.job_role_id == ^job_role_id)

      for %{subject_id: sid} = e <- entries,
          (count = normalize_count(e[:question_count] || e["question_count"])) > 0 do
        %JobRoleSubject{}
        |> JobRoleSubject.changeset(%{
          job_role_id: job_role_id,
          subject_id: sid,
          question_count: count
        })
        |> Repo.insert!()
      end

      :ok
    end)
  end

  defp normalize_count(n) when is_integer(n), do: n
  defp normalize_count(n) when is_binary(n), do: String.to_integer(String.trim(n))
  defp normalize_count(_), do: 0
end
