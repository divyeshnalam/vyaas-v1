defmodule VyaasaCampus.Contexts.AttemptGuard do
  @moduledoc """
  Enforces per-tenant assessment attempt limits.

  Call `check/4` from a context's *start* function, before the attempt row is
  created — guarding in the context rather than the LiveView means every caller
  (LiveView, API controller, background job) is covered by one change.

      case AttemptGuard.check(student_id, :mcq, tenant_id, prefix) do
        :ok -> # create the attempt
        {:error, :attempt_limit_reached, info} -> # info has :used, :limit, :granted
      end

  Behaviour:

    * **Unlimited by default** — no entitlement configured means no cap, so
      tenants are unaffected until a super admin sets one.
    * **Started attempts count**, not completed ones. Counting completions would
      let a student abandon and restart forever.
    * The window is the tenant's subscription period (`Entitlements.current_period/1`);
      with no period, attempts are counted over all time.
    * Admin grants (`attempt_grants`) add to the allowance for that student.
  """

  import Ecto.Query, warn: false

  alias VyaasaCampus.Contexts.Entitlements
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.AttemptGrant

  require Logger

  # module => {table, timestamp column used for the period window}.
  # Kept in one place because the eight assessments store attempts differently —
  # notably jam_sessions and interview_sessions have no attempt_number at all, so
  # every module is counted by row.
  @module_sources %{
    "mcq" => {"assessment_attempts", :inserted_at},
    "jam" => {"jam_sessions", :inserted_at},
    "interview" => {"interview_sessions", :inserted_at},
    "behavioral" => {"student_behavioral_assessments", :inserted_at},
    "psychometric" => {"student_psychometric_assessments", :inserted_at},
    "case_study" => {"case_study_sessions", :inserted_at},
    "mini_project" => {"mini_project_sessions", :inserted_at},
    "resume" => {"student_ats_phases", :inserted_at}
  }

  @doc "Modules this guard knows how to count."
  def known_modules, do: Map.keys(@module_sources)

  @doc """
  Like `check/4` but resolves the tenant from the schema name.

  Most assessment contexts only carry `prefix`, so this is the usual call site
  form. Costs one extra lookup, which is fine on a start path.
  """
  def check(student_id, module, prefix) when is_binary(prefix) do
    check(student_id, module, tenant_id_for(prefix), prefix)
  end

  @doc "Attempt status resolved from the schema name (see `status/4`)."
  def status(student_id, module, prefix) when is_binary(prefix) do
    status(student_id, module, tenant_id_for(prefix), prefix)
  end

  defp tenant_id_for(prefix) do
    case VyaasaCampus.Contexts.Tenants.get_tenant_by_schema_name(prefix) do
      nil -> nil
      tenant -> tenant.id
    end
  rescue
    _ -> nil
  end

  @doc """
  May this student start another attempt at `module`?

  Returns `:ok`, or `{:error, :attempt_limit_reached, %{used:, limit:, granted:}}`.
  Never raises — on an unexpected failure it logs and allows the attempt, so a
  bug in quota accounting can't lock students out of their assessments.
  """
  def check(student_id, module, tenant_id, prefix) do
    module = to_string(module)

    with {:ok, base} <- fetch_limit(tenant_id, module) do
      granted = granted_extra(student_id, module, prefix)
      allowed = base + granted
      used = used(student_id, module, prefix, Entitlements.current_period(tenant_id))

      if used < allowed do
        :ok
      else
        {:error, :attempt_limit_reached, %{used: used, limit: allowed, granted: granted}}
      end
    else
      :unlimited -> :ok
    end
  rescue
    e ->
      Logger.error("AttemptGuard.check failed (#{module}/#{student_id}): #{Exception.message(e)}")
      :ok
  end

  @doc "Attempts used, allowance and remaining — for showing state in the UI."
  def status(student_id, module, tenant_id, prefix) do
    module = to_string(module)
    granted = granted_extra(student_id, module, prefix)
    used = used(student_id, module, prefix, Entitlements.current_period(tenant_id))

    case fetch_limit(tenant_id, module) do
      :unlimited ->
        %{used: used, limit: nil, granted: granted, remaining: nil, blocked?: false}

      {:ok, base} ->
        allowed = base + granted

        %{
          used: used,
          limit: allowed,
          granted: granted,
          remaining: max(allowed - used, 0),
          blocked?: used >= allowed
        }
    end
  end

  defp fetch_limit(nil, _module), do: :unlimited

  defp fetch_limit(tenant_id, module) do
    case Entitlements.attempt_limit(tenant_id, module) do
      nil -> :unlimited
      limit when is_integer(limit) -> {:ok, limit}
    end
  end

  @doc """
  How many attempts this student has started at `module` within `period`.

  `period` is `{start, finish}` (either bound may be nil) or nil for all time.
  """
  def used(student_id, module, prefix, period \\ nil) do
    case Map.fetch(@module_sources, to_string(module)) do
      :error ->
        0

      {:ok, {table, ts_field}} ->
        table
        |> attempts_query(student_id, ts_field, period)
        |> Repo.aggregate(:count, prefix: prefix)
    end
  rescue
    e ->
      Logger.error("AttemptGuard.used failed (#{module}): #{Exception.message(e)}")
      0
  end

  defp attempts_query(table, student_id, ts_field, period) do
    query = from(r in table, where: r.student_id == type(^student_id, Ecto.UUID))

    case period do
      nil -> query
      {nil, nil} -> query
      {start, nil} -> from(r in query, where: field(r, ^ts_field) >= ^start)
      {nil, finish} -> from(r in query, where: field(r, ^ts_field) <= ^finish)
      {start, finish} -> from(r in query, where: field(r, ^ts_field) >= ^start and field(r, ^ts_field) <= ^finish)
    end
  end

  # ======================================================================
  # Grants
  # ======================================================================

  @doc "Total extra attempts granted to this student for this module."
  def granted_extra(student_id, module, prefix) do
    AttemptGrant
    |> where([g], g.student_id == ^student_id and g.module == ^to_string(module))
    |> Repo.aggregate(:sum, :extra_attempts, prefix: prefix)
    |> case do
      nil -> 0
      n -> n
    end
  rescue
    _ -> 0
  end

  @doc "Grant a student extra attempts at one module. Appends; never overwrites."
  def grant_extra(student_id, module, count, reason, granted_by_id, prefix) do
    %AttemptGrant{}
    |> AttemptGrant.changeset(%{
      student_id: student_id,
      module: to_string(module),
      extra_attempts: count,
      reason: reason,
      granted_by_id: granted_by_id
    })
    |> Repo.insert(prefix: prefix)
  end

  @doc "Grants for a student, newest first (for the admin drawer)."
  def list_grants(student_id, prefix) do
    AttemptGrant
    |> where([g], g.student_id == ^student_id)
    |> order_by([g], desc: g.granted_at)
    |> Repo.all(prefix: prefix)
  end
end
