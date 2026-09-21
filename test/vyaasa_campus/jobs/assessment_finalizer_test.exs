defmodule VyaasaCampus.Jobs.AssessmentFinalizerTest do
  @moduledoc """
  terminate/2 and the safety-net sweep can both enqueue for the same
  session — a terminate/2-enqueued job still queued when the sweep next
  runs, or two sweep ticks either side of a slow job. Without dedup, both
  instances would run `force_complete/2` concurrently: each type's
  idempotency guard only protects against a *sequential* repeat (it
  re-reads status from the DB), not two instances reading "not yet
  terminal" at the same moment and both re-running real evaluation (e.g.
  JAM re-transcribing/re-scoring the same recording twice).

  This pins the fix: `unique: [fields: [:args], ...]` on the worker.
  """

  use VyaasaCampus.DataCase, async: false
  use Oban.Testing, repo: VyaasaCampus.Repo

  alias VyaasaCampus.Jobs.AssessmentFinalizer

  test "enqueueing the same session twice while the first job is still pending only inserts one job" do
    session_id = "sess-#{System.unique_integer([:positive])}"

    assert {:ok, %Oban.Job{id: first_id}} = AssessmentFinalizer.enqueue("jam", session_id, "tenant_test")
    assert {:ok, %Oban.Job{id: second_id}} = AssessmentFinalizer.enqueue("jam", session_id, "tenant_test")

    assert first_id == second_id

    assert [_one] =
             all_enqueued(
               worker: AssessmentFinalizer,
               args: %{"type" => "jam", "session_id" => session_id, "tenant_schema" => "tenant_test"}
             )
  end

  test "different sessions of the same type both get their own job" do
    id_a = "sess-#{System.unique_integer([:positive])}"
    id_b = "sess-#{System.unique_integer([:positive])}"

    {:ok, job_a} = AssessmentFinalizer.enqueue("jam", id_a, "tenant_test")
    {:ok, job_b} = AssessmentFinalizer.enqueue("jam", id_b, "tenant_test")

    assert job_a.id != job_b.id
  end

  test "the same session can be enqueued again once the prior job has completed" do
    session_id = "sess-#{System.unique_integer([:positive])}"

    {:ok, first} = AssessmentFinalizer.enqueue("jam", session_id, "tenant_test")

    first
    |> Ecto.Changeset.change(state: "completed")
    |> VyaasaCampus.Repo.update!()

    {:ok, second} = AssessmentFinalizer.enqueue("jam", session_id, "tenant_test")

    assert second.id != first.id
  end
end
