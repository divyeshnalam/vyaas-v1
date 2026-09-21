defmodule VyaasaCampus.Jobs.AssessmentAbandonmentSweepTest do
  @moduledoc """
  The safety net for whatever terminate/2 structurally can't catch (a node
  crash). Covers the two staleness rules the sweep applies:

    * Types with a real deadline (MCQ via duration_minutes, Mini Project via
      submission_deadline) are only swept once that deadline has actually
      passed — a session still validly mid-attempt must never be touched
      just because it's been quiet for a while.
    * Types with no deadline concept (JAM here, standing in for
      Interview/Behavioral/Psychometric/Case Study, which all share the same
      sweep_by_field/6 codepath) use a flat inactivity grace window.

  Doesn't re-test each force_complete/2's own branching (empty vs partial
  content, idempotency) — that's already covered per-type in
  *_force_complete_test.exs. This only tests that the sweep finds the right
  rows and leaves the wrong ones alone.
  """

  use VyaasaCampus.DataCase, async: false
  use Oban.Testing, repo: VyaasaCampus.Repo

  @moduletag :shared_data

  alias VyaasaCampus.Contexts.Assessments
  alias VyaasaCampus.Jobs.{AssessmentAbandonmentSweep, AssessmentFinalizer}
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Jam.JamSession

  @tenant_schema "tenant_test"

  defp seed_tenant! do
    insert_tenant(%{schema_name: @tenant_schema, alias: "sweep-#{System.unique_integer([:positive])}"})
  end

  defp run_sweep do
    AssessmentAbandonmentSweep.perform(%Oban.Job{args: %{}})
  end

  defp insert_jam_session!(attrs) do
    {status, rest} = Map.pop(attrs, :status)

    defaults = %{
      student_id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      session_token: "tok-#{System.unique_integer([:positive])}"
    }

    {:ok, session} =
      %JamSession{}
      |> JamSession.create_changeset(Map.merge(defaults, rest))
      |> Repo.insert(prefix: @tenant_schema)

    {:ok, session} =
      session
      |> Ecto.Changeset.change(Map.merge(rest, %{status: status || session.status}))
      |> Repo.update(prefix: @tenant_schema)

    session
  end

  defp backdate!(session, minutes) do
    stale_at = DateTime.utc_now() |> DateTime.add(-minutes * 60, :second) |> DateTime.truncate(:second)

    session
    |> Ecto.Changeset.change(updated_at: stale_at)
    |> Repo.update!(prefix: @tenant_schema, force: true)
  end

  describe "no-deadline types (grace window)" do
    test "a JAM session idle past the grace window gets enqueued" do
      seed_tenant!()
      session = insert_jam_session!(%{status: "decision_phase"}) |> backdate!(45)

      run_sweep()

      assert_enqueued(
        worker: AssessmentFinalizer,
        args: %{"type" => "jam", "session_id" => session.id, "tenant_schema" => @tenant_schema}
      )
    end

    test "a JAM session updated recently is left alone" do
      seed_tenant!()
      session = insert_jam_session!(%{status: "decision_phase"})

      run_sweep()

      refute_enqueued(worker: AssessmentFinalizer, args: %{"session_id" => session.id})
    end

    test "an already-completed JAM session, even if stale, is left alone" do
      seed_tenant!()
      session = insert_jam_session!(%{status: "completed", final_score: 80}) |> backdate!(45)

      run_sweep()

      refute_enqueued(worker: AssessmentFinalizer, args: %{"session_id" => session.id})
    end
  end

  describe "MCQ (deadline-based, synchronous — bypasses AssessmentFinalizer)" do
    setup do
      admin_id = Ecto.UUID.generate()
      suffix = System.unique_integer([:positive])

      {:ok, user} =
        Repo.insert(
          VyaasaCampus.Schema.Accounts.User.changeset(%VyaasaCampus.Schema.Accounts.User{}, %{
            email: "sweep-mcq-#{suffix}@example.com",
            first_name: "Test",
            last_name: "User",
            password_hash: "x",
            status: "active",
            role: "admin",
            tenant_id: Ecto.UUID.generate(),
            created_by_id: admin_id,
            created_by_type: "public"
          }),
          prefix: @tenant_schema
        )

      {:ok, student} =
        Repo.insert(
          VyaasaCampus.Schema.Students.Student.changeset(%VyaasaCampus.Schema.Students.Student{}, %{
            email: "sweep-mcq-student-#{suffix}@example.com",
            first_name: "Test",
            last_name: "Student",
            degree: "B.Tech",
            specialization: "Computer Science",
            status: "active",
            phone: "9000001#{suffix}",
            registration_id: "SWREG#{suffix}",
            year_of_passing: 2024,
            cgpa: "8.5",
            tenant_id: user.tenant_id,
            created_by_id: admin_id,
            created_by_type: "public"
          }),
          prefix: @tenant_schema
        )

      {:ok, assessment} = Assessments.get_or_create_dynamic_assessment(student.id, @tenant_schema)
      {:ok, attempt} = Assessments.start_assessment_attempt(assessment.id, student.id, @tenant_schema)

      %{assessment: assessment, attempt: attempt}
    end

    test "an attempt past its duration_minutes deadline gets force-submitted", %{assessment: assessment, attempt: attempt} do
      seed_tenant!()

      assessment
      |> Ecto.Changeset.change(duration_minutes: 30)
      |> Repo.update!(prefix: @tenant_schema)

      long_ago = DateTime.utc_now() |> DateTime.add(-60 * 60, :second) |> DateTime.truncate(:second)

      attempt
      |> Ecto.Changeset.change(started_at: long_ago)
      |> Repo.update!(prefix: @tenant_schema)

      run_sweep()

      reloaded = Repo.get(VyaasaCampus.Schema.Assessments.AssessmentAttempt, attempt.id, prefix: @tenant_schema)
      assert reloaded.status in ["submitted", "evaluated", "completed"]
    end

    test "an attempt still within its duration_minutes window is left alone", %{assessment: assessment, attempt: attempt} do
      seed_tenant!()

      assessment
      |> Ecto.Changeset.change(duration_minutes: 60)
      |> Repo.update!(prefix: @tenant_schema)

      recent = DateTime.utc_now() |> DateTime.add(-5 * 60, :second) |> DateTime.truncate(:second)

      attempt
      |> Ecto.Changeset.change(started_at: recent)
      |> Repo.update!(prefix: @tenant_schema)

      run_sweep()

      reloaded = Repo.get(VyaasaCampus.Schema.Assessments.AssessmentAttempt, attempt.id, prefix: @tenant_schema)
      assert reloaded.status == attempt.status
    end
  end
end
