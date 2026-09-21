defmodule VyaasaCampus.Contexts.MiniProjectForceCompleteTest do
  @moduledoc """
  MiniProject.force_complete/2 is an idempotency-guarded entry point into
  the existing expire_session/2 (also used by the two pre-existing
  deadline-based call sites) — extended by this same change to actually
  score instead of just flipping phase to "completed" with every score
  field left nil.

  Deliberately does not exercise the "has an answered viva turn, gets
  evaluated for real" branch — that's MiniProjectEngine.evaluate/5, six LLM
  rubric passes, already exercised by the live submit_reflection flow;
  hitting it here would make this test slow, non-deterministic and
  API-key-dependent, matching how the rest of this codebase avoids
  unit-testing LLM call paths (see JamForceCompleteTest). What's new and
  needs coverage is the branching: zero answered viva turns short-circuits
  to a direct zero score instead of a wasted LLM call (true at every phase
  prior to viva — the engine's own viva-defense gate would force 0 anyway),
  and already-terminal sessions are left alone.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.MiniProject
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.AI8.ModuleEvaluation
  alias VyaasaCampus.Schema.Students.StudentMiniProjectSession, as: Session

  @tenant_schema "tenant_test"

  # create_changeset/1 forces phase: "role_assignment" unconditionally —
  # insert normally, then apply the extra attrs (including the desired
  # phase) directly, matching the pattern used for JAM/Interview fixtures.
  defp insert_session!(attrs) do
    {rest, extra} = Map.split(attrs, [:student_id, :tenant_id, :session_token])

    defaults = %{
      student_id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      session_token: "tok-#{System.unique_integer([:positive])}"
    }

    {:ok, session} =
      Session.create_changeset(Map.merge(defaults, rest))
      |> Repo.insert(prefix: @tenant_schema)

    if map_size(extra) == 0 do
      session
    else
      {:ok, session} =
        session
        |> Ecto.Changeset.change(extra)
        |> Repo.update(prefix: @tenant_schema)

      session
    end
  end

  test "a session abandoned before any viva answer gets a direct zero score, not an LLM call" do
    session = insert_session!(%{phase: "discovery"})

    assert {:ok, updated} = MiniProject.force_complete(session.id, @tenant_schema)
    assert updated.phase == "completed"
    assert updated.final_score == 0
    assert updated.grade_band == "Needs Improvement"
    assert updated.time_expired == true

    # Regression: the zero-content path used to write directly (bypassing
    # complete_session/4), so it silently skipped AI8 publish — a force-
    # completed session's score never reached the AI8 rollup. Both branches
    # now go through complete_session/4, so both publish the same way.
    assert Repo.get_by(ModuleEvaluation, [source_id: updated.id], prefix: @tenant_schema)
  end

  test "a session abandoned mid-viva with only unanswered turns also gets a direct zero score" do
    session =
      insert_session!(%{
        phase: "viva",
        viva_turns: [%{"index" => 0, "question" => "Why X?", "answer" => nil}]
      })

    assert {:ok, updated} = MiniProject.force_complete(session.id, @tenant_schema)
    assert updated.phase == "completed"
    assert updated.final_score == 0
  end

  test "an already-completed session is left untouched" do
    session = insert_session!(%{phase: "completed", final_score: 88, grade_band: "Excellent"})

    assert {:ok, :already_terminal} = MiniProject.force_complete(session.id, @tenant_schema)

    reloaded = MiniProject.get_session(session.id, @tenant_schema)
    assert reloaded.final_score == 88
    assert reloaded.grade_band == "Excellent"
  end

  test "an unknown session id returns an error, not a crash" do
    assert {:error, :not_found} = MiniProject.force_complete(Ecto.UUID.generate(), @tenant_schema)
  end
end
