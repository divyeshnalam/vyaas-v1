defmodule VyaasaCampus.Contexts.JamForceCompleteTest do
  @moduledoc """
  Jam.force_complete/2 is what closes the gap where a JAM session — no
  overall deadline, no resume on return (confirmed during investigation: any
  reconnection starts fresh) — used to sit at a non-terminal status forever
  if the student never came back.

  Deliberately does not exercise the "real recording exists, gets evaluated"
  branch — that's process_audio/2 + complete_processing/3, both pre-existing
  and already exercised by the live JAM flow; hitting a real LLM here would
  make this test slow, non-deterministic and API-key-dependent, matching how
  the rest of this codebase avoids unit-testing LLM call paths. What's new
  and needs coverage is the branching: empty/missing-recording sessions
  short-circuit to a direct zero score instead of a wasted LLM call, and
  already-terminal sessions are left alone.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.Jam
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.AI8.ModuleEvaluation
  alias VyaasaCampus.Schema.Jam.JamSession

  @tenant_schema "tenant_test"

  # create_changeset/2 forces status: "created" unconditionally — insert
  # normally, then apply the extra attrs (including the desired status)
  # directly, matching how the real lifecycle changesets progress a session.
  defp insert_session!(attrs) do
    {status, rest} = Map.pop(attrs, :status)

    defaults = %{
      student_id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      session_token: "tok-#{System.unique_integer([:positive])}"
    }

    {:ok, session} =
      %JamSession{}
      |> JamSession.create_changeset(defaults)
      |> Repo.insert(prefix: @tenant_schema)

    {:ok, session} =
      session
      |> Ecto.Changeset.change(Map.merge(rest, %{status: status || session.status}))
      |> Repo.update(prefix: @tenant_schema)

    session
  end

  test "a session that never reached speaking gets a direct zero score, not an LLM call" do
    session = insert_session!(%{status: "decision_phase"})

    assert {:ok, updated} = Jam.force_complete(session.id, @tenant_schema)
    assert updated.status == "completed"
    assert updated.final_score == 0
    assert updated.transcript != nil and updated.transcript != ""
    assert updated.evaluation_data["abandoned"] == true
  end

  test "a session whose recording file no longer exists on disk also gets a zero score" do
    session =
      insert_session!(%{
        status: "speaking",
        recording_file_path: "/tmp/definitely_does_not_exist_#{System.unique_integer([:positive])}.webm"
      })

    assert {:ok, updated} = Jam.force_complete(session.id, @tenant_schema)
    assert updated.status == "completed"
    assert updated.final_score == 0
  end

  test "an already-completed session is left untouched" do
    session = insert_session!(%{status: "completed", final_score: 87})

    assert {:ok, :already_terminal} = Jam.force_complete(session.id, @tenant_schema)

    reloaded = Jam.get_jam_session(session.id, @tenant_schema)
    assert reloaded.final_score == 87
    assert reloaded.status == "completed"
  end

  test "an already-failed session is also left untouched" do
    session = insert_session!(%{status: "failed"})

    assert {:ok, :already_terminal} = Jam.force_complete(session.id, @tenant_schema)

    reloaded = Jam.get_jam_session(session.id, @tenant_schema)
    assert reloaded.status == "failed"
  end

  test "an unknown session id returns an error, not a crash" do
    assert {:error, :not_found} = Jam.force_complete(Ecto.UUID.generate(), @tenant_schema)
  end

  test "a zero-score force-complete (no ai8_scores in evaluation_data) does not publish a fabricated AI8 row" do
    session = insert_session!(%{status: "decision_phase"})

    assert {:ok, updated} = Jam.force_complete(session.id, @tenant_schema)
    refute Repo.get_by(ModuleEvaluation, [source_id: updated.id], prefix: @tenant_schema)
  end

  # Regression: AI8.publish_evaluation used to be called only from the
  # LiveView's live processing-result handler, never from
  # Jam.complete_processing/3 itself — so force_complete/2's "real
  # recording, re-evaluated" branch (which also calls complete_processing/3)
  # silently never reached AI8. complete_processing/3 is the one function
  # every completion path funnels through, so testing it directly here
  # covers both callers without needing to invoke the real LLM evaluation.
  test "complete_processing/3 publishes to AI8 when the evaluation carries ai8_scores, regardless of caller" do
    session = insert_session!(%{status: "speaking"})

    evaluation_data = %{
      transcript: "a real transcript",
      final_score: 82,
      clarity_score: 8,
      structure_score: 7,
      relevance_score: 8,
      impact_score: 7,
      confidence_score: 8,
      overall_summary: "Solid attempt.",
      evaluation_data: %{"ai8_scores" => %{"communication" => 80, "confidence" => 78}}
    }

    assert {:ok, updated} = Jam.complete_processing(session, evaluation_data, @tenant_schema)

    eval = Repo.get_by(ModuleEvaluation, [source_id: updated.id], prefix: @tenant_schema)
    assert eval
    assert eval.module == "jam"
  end
end
