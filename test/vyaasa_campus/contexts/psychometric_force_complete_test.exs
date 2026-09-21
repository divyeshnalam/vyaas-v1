defmodule VyaasaCampus.Contexts.PsychometricForceCompleteTest do
  @moduledoc """
  Psychometric.force_complete/2 closes the gap the investigation flagged, and
  is the one type where that meant reversing a documented prior decision: the
  code deliberately did NOT resume/score a partial adaptive attempt, since a
  composite from 2 of ~20 answered items was judged noise, not a real
  personality score. force_complete/2 now applies "force real evaluation"
  here too, with one nuance kept: zero-answer sessions get a direct terminal
  write with score columns left nil (not fabricated), skipping the LLM call
  entirely rather than asking it to interpret nothing.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.Psychometric
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.StudentPsychometricAssessment

  @tenant_schema "tenant_test"

  # student_psychometric_assessments.student_id has a real FK to students — a
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
        [Ecto.UUID.dump!(tenant_id), "psych-test-#{suffix}@vyaasa.test", "PREG#{suffix}"]
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
      StudentPsychometricAssessment.start_changeset(Map.merge(defaults, attrs))
      |> Repo.insert(prefix: @tenant_schema)

    assessment
  end

  defp with_engine_state(assessment, trait_scores) do
    metadata = %{"engine_state" => %{"trait_scores" => trait_scores, "all_questions" => []}}

    assessment
    |> StudentPsychometricAssessment.changeset(%{metadata: metadata})
    |> Repo.update!(prefix: @tenant_schema)
  end

  test "a session abandoned before answering anything gets a direct terminal write with no fabricated scores" do
    assessment = insert_assessment!(%{})

    assert {:ok, updated} = Psychometric.force_complete(assessment.session_id, @tenant_schema)
    assert updated.status == "completed"
    assert updated.overall_summary =~ "abandoned"
    assert updated.openness_score == nil
    assert updated.conscientiousness_score == nil
    assert updated.extraversion_score == nil
    assert updated.agreeableness_score == nil
    assert updated.neuroticism_score == nil
  end

  test "a session with an empty trait_scores map (freshly started engine state) also short-circuits" do
    assessment =
      insert_assessment!(%{})
      |> with_engine_state(%{
        "Openness" => [],
        "Conscientiousness" => [],
        "Extraversion" => [],
        "Agreeableness" => [],
        "Emotional Stability" => []
      })

    assert {:ok, updated} = Psychometric.force_complete(assessment.session_id, @tenant_schema)
    assert updated.status == "completed"
    assert updated.openness_score == nil
  end

  test "an already-completed assessment is left untouched" do
    assessment = insert_assessment!(%{})

    {:ok, completed} =
      assessment
      |> StudentPsychometricAssessment.complete_changeset(%{overall_summary: "real report"})
      |> Repo.update(prefix: @tenant_schema)

    assert {:ok, :already_terminal} = Psychometric.force_complete(completed.session_id, @tenant_schema)

    reloaded = Psychometric.get_assessment_by_session(completed.session_id, @tenant_schema)
    assert reloaded.overall_summary == "real report"
  end

  test "an already-failed assessment is also left untouched" do
    assessment = insert_assessment!(%{})

    {:ok, failed} =
      assessment
      |> StudentPsychometricAssessment.status_changeset("failed")
      |> Repo.update(prefix: @tenant_schema)

    assert {:ok, :already_terminal} = Psychometric.force_complete(failed.session_id, @tenant_schema)
  end

  test "an unknown session id returns an error, not a crash" do
    assert {:error, :not_found} = Psychometric.force_complete("no-such-session", @tenant_schema)
  end
end
