defmodule VyaasaCampus.Jobs.AtsJobRecorderTest do
  @moduledoc """
  A resume-scoring job that dies from a node crash on every attempt (not a
  graceful `{:error, reason}` return) never runs the code that normally
  records a failure — AtsUpload.update_processing_attempt/3, called from
  inside AtsResumeProcessor.perform/1. Oban.Plugins.Lifeline rescues the
  orphaned job and retries it, but once retries are exhausted and Oban marks
  it `discarded`, nothing was watching for that — the student's ats_phase
  stays at status "processing" forever with no explanation.

  AtsJobRecorder is a telemetry handler on Oban's own job lifecycle events,
  so it catches the discard regardless of why the job actually died. Exercised
  here directly against synthetic Oban telemetry metadata (real end-to-end
  Oban retry-exhaustion would need minutes of wall-clock backoff to
  reproduce) — handle_event/4 is the actual boundary Oban calls, so this is a
  real test of the handler's own logic, not of Oban's internals.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.StudentAts
  alias VyaasaCampus.Jobs.AtsJobRecorder
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.StudentAtsPhase
  alias VyaasaCampus.Schema.Tenants.Tenant

  setup do
    suffix = System.unique_integer([:positive])

    tenant =
      Repo.insert!(%Tenant{
        full_name: "AtsJobRecorder Test College #{suffix}",
        short_name: "AJRTest#{suffix}",
        alias: "AJRTEST#{suffix}",
        schema_name: "tenant_test",
        affiliation_type: "autonomous",
        status: "active"
      })

    student_id = insert_student!(tenant.id)

    {:ok, phase} =
      %StudentAtsPhase{}
      |> StudentAtsPhase.changeset(%{
        student_id: student_id,
        tenant_id: tenant.id,
        resume_url: "test://resume.pdf",
        status: "processing"
      })
      |> Repo.insert(prefix: "tenant_test")

    {:ok, tenant: tenant, phase: phase, student_id: student_id}
  end

  # student_ats_phases.student_id has an FK to students — a minimal real row
  # to satisfy it, via raw SQL to sidestep the full profile-completeness
  # changeset this test doesn't care about.
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
        [Ecto.UUID.dump!(tenant_id), "ats-recorder-#{suffix}@vyaasa.test", "REG#{suffix}"]
      )

    Ecto.UUID.load!(id)
  end

  defp discard_event(phase, tenant_schema) do
    job = %Oban.Job{
      queue: "ats_processing",
      worker: "VyaasaCampus.Jobs.AtsResumeProcessor",
      args: %{"ats_phase_id" => phase.id, "tenant_schema" => tenant_schema}
    }

    AtsJobRecorder.handle_event([:oban, :job, :exception], %{}, %{state: :discard, job: job}, nil)
  end

  test "marks a stuck ats_phase errored when its job is discarded", %{phase: phase} do
    discard_event(phase, "tenant_test")

    reloaded = StudentAts.get_by_id(phase.id, "tenant_test")
    assert reloaded.status == "errored"
  end

  test "leaves an already-terminal ats_phase alone", %{tenant: tenant} do
    {:ok, completed} =
      %StudentAtsPhase{}
      |> StudentAtsPhase.changeset(%{
        student_id: insert_student!(tenant.id),
        tenant_id: tenant.id,
        resume_url: "test://resume.pdf",
        status: "completed"
      })
      |> Repo.insert(prefix: "tenant_test")

    discard_event(completed, "tenant_test")

    reloaded = StudentAts.get_by_id(completed.id, "tenant_test")
    assert reloaded.status == "completed"
  end

  test "ignores non-discard events entirely (success/failure/snoozed)", %{phase: phase} do
    job = %Oban.Job{
      queue: "ats_processing",
      worker: "VyaasaCampus.Jobs.AtsResumeProcessor",
      args: %{"ats_phase_id" => phase.id, "tenant_schema" => "tenant_test"}
    }

    AtsJobRecorder.handle_event([:oban, :job, :stop], %{}, %{state: :success, job: job}, nil)
    AtsJobRecorder.handle_event([:oban, :job, :stop], %{}, %{state: :snoozed, job: job}, nil)

    reloaded = StudentAts.get_by_id(phase.id, "tenant_test")
    assert reloaded.status == "processing"
  end

  test "ignores discards from unrelated queues", %{phase: phase} do
    job = %Oban.Job{
      queue: "emails",
      worker: "VyaasaCampus.Jobs.SomeEmailWorker",
      args: %{"ats_phase_id" => phase.id, "tenant_schema" => "tenant_test"}
    }

    AtsJobRecorder.handle_event([:oban, :job, :exception], %{}, %{state: :discard, job: job}, nil)

    reloaded = StudentAts.get_by_id(phase.id, "tenant_test")
    assert reloaded.status == "processing"
  end
end
