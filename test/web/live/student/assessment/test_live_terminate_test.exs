defmodule VyaasaCampusWeb.Student.Assessment.TestLiveTerminateTest do
  @moduledoc """
  Closing the tab mid-MCQ-test must not leave the attempt stuck "in_progress"
  forever — verified by calling TestLive.terminate/2 directly against a
  synthetic connected socket (transport_pid: self() — exactly what
  connected?/1 checks), which is the real function LiveView calls when a
  connected process's socket goes away, without the overhead/flakiness of
  driving a full websocket connect+disconnect through Phoenix.LiveViewTest.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.Assessments
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Accounts.User
  alias VyaasaCampus.Schema.Students.Student
  alias VyaasaCampusWeb.Student.Assessment.TestLive

  @tenant_schema "tenant_test"

  setup do
    admin_id = Ecto.UUID.generate()
    suffix = System.unique_integer([:positive])

    user_attrs = %{
      email: "terminate-test-#{suffix}@example.com",
      first_name: "Test",
      last_name: "User",
      password_hash: "test_hash",
      status: "active",
      role: "admin",
      tenant_id: Ecto.UUID.generate(),
      created_by_id: admin_id,
      created_by_type: "public"
    }

    {:ok, user} = Repo.insert(%User{} |> User.changeset(user_attrs), prefix: @tenant_schema)

    student_attrs = %{
      email: "terminate-student-#{suffix}@example.com",
      first_name: "Test",
      last_name: "Student",
      degree: "B.Tech",
      specialization: "Computer Science",
      status: "active",
      phone: "9000000#{suffix}",
      registration_id: "TREG#{suffix}",
      year_of_passing: 2024,
      cgpa: "8.5",
      tenant_id: user.tenant_id,
      created_by_id: admin_id,
      created_by_type: "public"
    }

    {:ok, student} = Repo.insert(%Student{} |> Student.changeset(student_attrs), prefix: @tenant_schema)
    {:ok, assessment} = Assessments.get_or_create_dynamic_assessment(student.id, @tenant_schema)
    {:ok, attempt} = Assessments.start_assessment_attempt(assessment.id, student.id, @tenant_schema)

    %{student: student, assessment: assessment, attempt: attempt, tenant_schema: @tenant_schema}
  end

  defp connected_socket(assigns) do
    %Phoenix.LiveView.Socket{transport_pid: self(), assigns: Map.merge(%{__changed__: %{}}, assigns)}
  end

  test "a connected socket closing mid-test force-submits the attempt", %{attempt: attempt, tenant_schema: tenant_schema} do
    socket = connected_socket(%{attempt: attempt, tenant_schema: tenant_schema, answers: %{}})

    assert :ok = TestLive.terminate(:shutdown, socket)

    reloaded = Repo.get(VyaasaCampus.Schema.Assessments.AssessmentAttempt, attempt.id, prefix: tenant_schema)
    assert reloaded.status in ["submitted", "evaluated", "completed"]
  end

  test "the disconnected initial render (transport_pid nil) does not submit anything", %{
    attempt: attempt,
    tenant_schema: tenant_schema
  } do
    socket = %Phoenix.LiveView.Socket{
      transport_pid: nil,
      assigns: %{__changed__: %{}, attempt: attempt, tenant_schema: tenant_schema, answers: %{}}
    }

    assert :ok = TestLive.terminate(:shutdown, socket)

    reloaded = Repo.get(VyaasaCampus.Schema.Assessments.AssessmentAttempt, attempt.id, prefix: tenant_schema)
    assert reloaded.status == attempt.status
  end

  test "an already-submitted attempt is left untouched (idempotent)", %{
    attempt: attempt,
    tenant_schema: tenant_schema
  } do
    {:ok, submitted} = Assessments.force_submit_assessment(attempt.id, %{}, tenant_schema)
    socket = connected_socket(%{attempt: submitted, tenant_schema: tenant_schema, answers: %{}})

    assert :ok = TestLive.terminate(:shutdown, socket)

    reloaded = Repo.get(VyaasaCampus.Schema.Assessments.AssessmentAttempt, attempt.id, prefix: tenant_schema)
    assert reloaded.status == submitted.status
    assert reloaded.updated_at == submitted.updated_at
  end

  test "no attempt assign (early-redirect mount paths) does not raise" do
    socket = connected_socket(%{})
    assert :ok = TestLive.terminate(:shutdown, socket)
  end
end
