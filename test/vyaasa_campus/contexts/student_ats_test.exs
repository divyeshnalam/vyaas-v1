defmodule VyaasaCampus.Contexts.StudentAtsTest do
  @moduledoc """
  `create_reanalysis_phase/4`'s blocked-attempt return shape is a contract
  `ReanalyzeService.process_reanalysis/1` pattern-matches on. It used to be a
  plain 2-tuple everywhere; AttemptGuard.check/4 (added for per-college
  attempt limits) returns a 3-tuple on block, and the caller's `with/else`
  only had a clause for the 2-tuple shape — the mismatch raised an uncaught
  WithClauseError, crashing the LiveView process instead of showing the
  student a message. Pinning the exact shape here so that regression can't
  silently reopen if either side's tuple arity drifts again.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.Entitlements
  alias VyaasaCampus.Contexts.StudentAts
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Tenants.Tenant

  setup do
    suffix = System.unique_integer([:positive])

    tenant =
      Repo.insert!(%Tenant{
        full_name: "StudentAts Test College #{suffix}",
        short_name: "SATest#{suffix}",
        alias: "SATEST#{suffix}",
        schema_name: "tenant_test",
        affiliation_type: "autonomous",
        status: "active"
      })

    on_exit(fn ->
      Entitlements.clear(tenant.id, "attempts.resume")
      Entitlements.clear(tenant.id, "attempts.default")
    end)

    {:ok, tenant: tenant}
  end

  test "returns a 3-tuple {:error, :attempt_limit_reached, meta} when blocked, not a 2-tuple",
       %{tenant: tenant} do
    student_id = Ecto.UUID.generate()
    Entitlements.put_attempt_limits(tenant.id, %{"resume" => 0})

    result =
      StudentAts.create_reanalysis_phase(
        student_id,
        tenant.id,
        %{resume_url: "x", preferred_role: "y"},
        tenant.schema_name
      )

    assert {:error, :attempt_limit_reached, meta} = result
    assert %{used: _, limit: 0, granted: 0} = meta

    # The exact with/else shape ReanalyzeService.process_reanalysis/1 uses —
    # this must not raise WithClauseError for either arity.
    outcome =
      with {:ok, ats_phase} <- result do
        {:ok, ats_phase.id}
      else
        {:error, :attempt_limit_reached, m} -> {:error, {:attempt_limit_reached, m}}
        {:error, reason} -> {:error, reason}
      end

    assert {:error, {:attempt_limit_reached, ^meta}} = outcome
  end

  test "unlimited (no entitlement configured) never blocks re-analysis", %{tenant: tenant} do
    student_id = Ecto.UUID.generate()

    # No entitlement set — tenant is unrestricted. create_reanalysis_phase
    # will still fail (student doesn't exist), but NOT with an attempt-limit
    # error — proving the guard doesn't fire when there's no configured cap.
    result =
      StudentAts.create_reanalysis_phase(
        student_id,
        tenant.id,
        %{resume_url: "x", preferred_role: "y"},
        tenant.schema_name
      )

    refute match?({:error, :attempt_limit_reached, _}, result)
  end
end
