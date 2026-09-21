defmodule VyaasaCampus.Contexts.BehavioralForceCompleteTest do
  @moduledoc """
  Behavioral.force_complete/2 closes the gap the investigation flagged: this
  type explicitly abandons (never resumes) a stale "started"/"interviewing"
  row when the student returns — meaning a closed tab left that row stuck
  non-terminal forever with no path back to it at all.

  Unlike JAM/Interview, there is nothing partial to recover: per-scenario
  ratings live only in the conversational engine's in-memory state and are
  written to the DB in one shot at final completion, not incrementally — so
  force_complete/2 always produces a direct zero score. That's the one thing
  worth pinning here (plus idempotency); there's no "partial content" branch
  to test since the implementation has none.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.Behavioral
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.StudentBehavioralAssessment

  @tenant_schema "tenant_test"

  # student_behavioral_assessments.student_id has a real FK to students — a
  # minimal real row to satisfy it, via raw SQL to sidestep the full
  # profile-completeness changeset this test doesn't care about.
  defp insert_student!(tenant_id) do
    suffix = System.unique_integer([:positive])

    {:ok, %{rows: [[id]]}} =
      Repo.query(
        """
        INSERT INTO tenant_test.students (
          id, tenant_id, email, first_name, last_name, encrypted_password,
          phone, registration_id, degree, specialization, year_of_passing, cgpa,
          created_by_id, created_by_type, status, inserted_at, updated_at
        ) VALUES (
          gen_random_uuid(), $1, $2, 'Test', 'Student', 'x',
          '9999999999', $3, 'B.Tech', 'CSE', 2026, 8.0,
          $1, 'tenant', 'pending', NOW(), NOW()
        ) RETURNING id
        """,
        [Ecto.UUID.dump!(tenant_id), "behavioral-test-#{suffix}@vyaasa.test", "BREG#{suffix}"]
      )

    Ecto.UUID.load!(id)
  end

  defp insert_assessment!(attrs) do
    tenant_id = Ecto.UUID.generate()

    defaults = %{
      student_id: insert_student!(tenant_id),
      tenant_id: tenant_id,
      session_id: "sess-#{System.unique_integer([:positive])}"
    }

    {:ok, assessment} =
      StudentBehavioralAssessment.start_changeset(Map.merge(defaults, attrs))
      |> Repo.insert(prefix: @tenant_schema)

    assessment
  end

  test "an abandoned assessment gets a direct zero score" do
    assessment = insert_assessment!(%{})

    assert {:ok, updated} = Behavioral.force_complete(assessment.session_id, @tenant_schema)
    assert updated.status == "completed"
    assert updated.overall_score == 0
    assert updated.summary =~ "abandoned"
  end

  test "an assessment already interviewing (mid-conversation) still gets a zero score, not a crash" do
    assessment = insert_assessment!(%{})

    {:ok, mid} =
      assessment
      |> StudentBehavioralAssessment.status_changeset("interviewing")
      |> Repo.update(prefix: @tenant_schema)

    assert {:ok, updated} = Behavioral.force_complete(mid.session_id, @tenant_schema)
    assert updated.status == "completed"
    assert updated.overall_score == 0
  end

  test "an already-completed assessment is left untouched" do
    assessment = insert_assessment!(%{})

    {:ok, completed} =
      assessment
      |> StudentBehavioralAssessment.complete_changeset(%{"report" => %{"overall_score" => 82}})
      |> Repo.update(prefix: @tenant_schema)

    assert {:ok, :already_terminal} = Behavioral.force_complete(completed.session_id, @tenant_schema)

    reloaded = Behavioral.get_assessment_by_session(completed.session_id, @tenant_schema)
    assert reloaded.overall_score == 82
  end

  test "an already-failed assessment is also left untouched" do
    assessment = insert_assessment!(%{})

    {:ok, failed} =
      assessment
      |> StudentBehavioralAssessment.status_changeset("failed")
      |> Repo.update(prefix: @tenant_schema)

    assert {:ok, :already_terminal} = Behavioral.force_complete(failed.session_id, @tenant_schema)
  end

  test "an unknown session id returns an error, not a crash" do
    assert {:error, :not_found} = Behavioral.force_complete("no-such-session", @tenant_schema)
  end
end
