defmodule VyaasaCampusWeb.Student.SharedProfileLiveTest do
  @moduledoc """
  The shared/public student-profile card used to render only 5 of the
  platform's 8 assessment types, in an order that didn't match the real
  dashboard, behind a 195+ character signed-token URL. Covers all three
  fixes: all 8 types render, in the dashboard's canonical order (Resume,
  Interview, MCQ, JAM, Behavioral, Psychometric, Case Study, Mini Project),
  and the mount path resolves a short DB-backed slug instead of verifying a
  `Phoenix.Token`.
  """

  use VyaasaCampusWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VyaasaCampus.Contexts.SharedProfileLinks
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Tenants.Tenant

  @tenant_schema "test"

  setup do
    tenant =
      Repo.get_by(Tenant, alias: "SHAREDPROFILETEST") ||
        insert_tenant(
          %{
            alias: "SHAREDPROFILETEST",
            schema_name: @tenant_schema,
            full_name: "Shared Profile Test College"
          },
          insert_admin_user()
        )

    student = insert_student(tenant, %{first_name: "Jordan", last_name: "Lee"})

    %{tenant: tenant, student: student}
  end

  test "an unknown slug shows the invalid-link screen", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/profile/shared/nosuchslug")

    assert html =~ "Invalid or Expired Link"
  end

  test "a valid slug renders the student's profile with all 8 assessments in dashboard order",
       %{conn: conn, student: student} do
    slug = SharedProfileLinks.get_or_create_slug(student.id, @tenant_schema)

    {:ok, _view, html} = live(conn, ~p"/profile/shared/#{slug}")

    assert html =~ "Jordan Lee"

    for label <- [
          "Resume Score",
          "Interview",
          "MCQ",
          "JAM",
          "Behavioral",
          "Psychometric",
          "Case Study",
          "Mini Project"
        ] do
      assert html =~ label
    end

    # "Behavioral"/"Psychometric"/"Case Study"/"Mini Project" also appear
    # earlier in the compact "Vyaasa Score" list — scope the order check to
    # just the "Assessment Scores" detail-card section so those labels'
    # *second* occurrence (the one that matters for this section's order)
    # isn't shadowed by their first.
    [_before, detail_section] = String.split(html, "Assessment Scores</h3>", parts: 2)

    detail_order = [
      "Resume Analysis",
      "Interactive Session",
      "Objective Eval",
      "JAM Session",
      "Behavioral",
      "Psychometric",
      "Case Study",
      "Mini Project"
    ]

    positions =
      Enum.map(detail_order, fn label ->
        {pos, _len} = :binary.match(detail_section, label)
        pos
      end)

    assert positions == Enum.sort(positions)
  end

  test "the same student always gets the same shared URL slug", %{conn: conn, student: student} do
    slug1 = SharedProfileLinks.get_or_create_slug(student.id, @tenant_schema)
    slug2 = SharedProfileLinks.get_or_create_slug(student.id, @tenant_schema)

    assert slug1 == slug2

    {:ok, _view, html} = live(conn, ~p"/profile/shared/#{slug1}")
    assert html =~ "Jordan Lee"
  end
end
