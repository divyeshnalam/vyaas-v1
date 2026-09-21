defmodule VyaasaCampusWeb.Admin.CollegeConfigLiveTest do
  @moduledoc """
  The merged per-college config screen renders and saves.

  Worth pinning because the limits it writes decide whether students are let
  into assessments — a screen that silently fails to save is worse than no
  screen.
  """

  use VyaasaCampusWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VyaasaCampus.Contexts.Entitlements
  alias VyaasaCampus.Guardian
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Platform.AdminUser
  alias VyaasaCampus.Schema.Tenants.Tenant

  setup %{conn: conn} do
    admin =
      Repo.get_by(AdminUser, email: "limits-test@vyaasa.test") ||
        Repo.insert!(%AdminUser{
          email: "limits-test@vyaasa.test",
          encrypted_password: Bcrypt.hash_pwd_salt("password123"),
          first_name: "Limits",
          last_name: "Tester",
          role: "super_admin",
          status: "active"
        })

    # Selecting a college loads its assessments, so schema_name must point at a
    # real schema — reuse the one test_helper.exs creates via Triplex.
    tenant =
      Repo.get_by(Tenant, alias: "LIMITSTEST") ||
        Repo.insert!(%Tenant{
          full_name: "Limits Test College",
          short_name: "LimitsTest",
          alias: "LIMITSTEST",
          schema_name: "tenant_test",
          affiliation_type: "autonomous",
          status: "active"
        })

    {:ok, token, _} = Guardian.encode_and_sign(admin)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:auth_token, token)

    {:ok, conn: conn, tenant: tenant}
  end

  # The college now comes from the URL, so reaching limits is a single tab click.
  defp open_limits(view) do
    view |> element("button[phx-value-tab='limits']") |> render_click()
  end

  test "opens scoped to the college in the URL, with no picker", %{conn: conn, tenant: tenant} do
    {:ok, _view, html} = live(conn, ~p"/admin/colleges/#{tenant.id}/config")

    assert html =~ tenant.full_name
    assert html =~ "Back to Colleges"
    # The old college picker is gone — the college comes from the route.
    refute html =~ "phx-value-tenant_id"
  end

  test "defaults to the Assessments tab and offers a Limits tab", %{conn: conn, tenant: tenant} do
    {:ok, _view, html} = live(conn, ~p"/admin/colleges/#{tenant.id}/config")

    assert html =~ "Limits &amp; Attempts"
    # Assessments tab is active, so the limits form is not on the page yet.
    refute html =~ "limits[default]"
  end

  test "the Limits tab exposes an input for every assessment", %{conn: conn, tenant: tenant} do
    {:ok, view, _html} = live(conn, ~p"/admin/colleges/#{tenant.id}/config")

    html = open_limits(view)

    assert html =~ "limits[default]"
    assert html =~ "period[period_start]"

    for module <- Entitlements.attempt_modules() do
      assert html =~ "limits[#{module}]", "missing an input for #{module}"
    end
  end

  test "saving limits persists a default and an override, and blank clears", %{conn: conn, tenant: tenant} do
    {:ok, view, _html} = live(conn, ~p"/admin/colleges/#{tenant.id}/config")

    open_limits(view)

    view
    |> form("form[phx-submit='save_limits']", %{
      "limits" => %{"default" => "3", "mcq" => "5", "jam" => ""}
    })
    |> render_submit()

    entitlements = Entitlements.map_for_tenant(tenant.id)

    assert Entitlements.attempt_limit(entitlements, :mcq) == 5, "override should win"
    assert Entitlements.attempt_limit(entitlements, :jam) == 3, "blank should inherit the default"
    assert Entitlements.attempt_limit(entitlements, :interview) == 3

    on_exit(fn ->
      Enum.each(["default" | Entitlements.attempt_modules()], fn m ->
        Entitlements.clear(tenant.id, Entitlements.attempts_key(m))
      end)
    end)
  end

  test "a reversed subscription period is rejected", %{conn: conn, tenant: tenant} do
    {:ok, view, _html} = live(conn, ~p"/admin/colleges/#{tenant.id}/config")

    open_limits(view)

    html =
      view
      |> form("form[phx-submit='save_period']", %{
        "period" => %{"period_start" => "2026-12-31T00:00", "period_end" => "2026-01-01T00:00"}
      })
      |> render_submit()

    assert html =~ "Could not save period"
  end
end
