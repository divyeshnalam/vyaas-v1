defmodule VyaasaCampus.Contexts.AttemptGuardInterviewTest do
  @moduledoc """
  Pins AttemptGuard.status/3 for interview quotas. The LiveView now lets
  students click Start Interview first, then shows the shared out-of-attempts
  error card if the guarded start call is rejected. This test keeps the
  underlying quota status behavior covered without coupling the UI to a
  proactive mount-time block.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.{AttemptGuard, Entitlements}
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Tenants.Tenant

  setup do
    suffix = System.unique_integer([:positive])

    tenant =
      Repo.insert!(%Tenant{
        full_name: "AttemptGuard Interview Test College #{suffix}",
        short_name: "AGITest#{suffix}",
        alias: "AGITEST#{suffix}",
        schema_name: "tenant_test",
        affiliation_type: "autonomous",
        status: "active"
      })

    on_exit(fn ->
      Entitlements.clear(tenant.id, "attempts.interview")
      Entitlements.clear(tenant.id, "attempts.default")
    end)

    {:ok, tenant: tenant}
  end

  test "status/3 reports blocked?: true once the interview limit is exhausted", %{tenant: tenant} do
    student_id = Ecto.UUID.generate()
    Entitlements.put_attempt_limits(tenant.id, %{"interview" => 0})

    status = AttemptGuard.status(student_id, :interview, tenant.schema_name)

    assert status.blocked? == true
    assert status.limit == 0
    assert status.remaining == 0
  end

  test "status/3 reports blocked?: false when unlimited (no entitlement configured)", %{tenant: tenant} do
    student_id = Ecto.UUID.generate()

    status = AttemptGuard.status(student_id, :interview, tenant.schema_name)

    assert status.blocked? == false
    assert status.limit == nil
  end
end
