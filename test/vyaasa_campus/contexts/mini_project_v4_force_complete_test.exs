defmodule VyaasaCampus.Contexts.MiniProjectV4ForceCompleteTest do
  @moduledoc """
  MiniProjectV4.force_complete/2 closes the gap the investigation flagged
  for this type specifically: `choose_scenario/3` sets a real
  `submission_deadline`, but nothing anywhere reads it — a session that
  timed out mid-submission or mid-viva just sat there forever. This is also
  what finally wires that field up: the safety-net sweep (built separately)
  treats a non-terminal V4 session past its deadline the same as a closed
  tab, both routing through here.

  Deliberately does not exercise the "has an answered viva question, gets
  evaluated for real" branch — that's EngineV4.score_viva_answers/3 +
  EngineV4.feedback/4, two closing LLM calls already exercised by the live
  finalize/2 flow; hitting them here would make this test slow,
  non-deterministic and API-key-dependent, matching how the rest of this
  codebase avoids unit-testing LLM call paths (see JamForceCompleteTest).
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.MiniProjectV4
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.StudentMiniProjectSession, as: Session

  @tenant_schema "tenant_test"

  # create_changeset_v4/1 forces phase: "profile" unconditionally — insert
  # normally, then apply the extra attrs (including the desired phase)
  # directly, matching the pattern used for the v1 session fixtures.
  defp insert_session!(attrs) do
    {rest, extra} = Map.split(attrs, [:student_id, :tenant_id, :session_token])

    defaults = %{
      student_id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      session_token: "tok-#{System.unique_integer([:positive])}"
    }

    {:ok, session} =
      Session.create_changeset_v4(Map.merge(defaults, rest))
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

  test "a session abandoned before any viva question was answered gets a direct zero score, not an LLM call" do
    session = insert_session!(%{phase: "submission"})

    assert {:ok, updated} = MiniProjectV4.force_complete(session.id, @tenant_schema)
    assert updated.phase == "completed"
    assert updated.final_score == 0
    assert updated.grade_band == "Not ready"
    assert updated.time_expired == true
  end

  test "a session with viva questions but no answers yet also gets a direct zero score" do
    session =
      insert_session!(%{
        phase: "viva",
        viva_questions: [%{"id" => "q1", "metric" => "domain", "question" => "Why X?", "answer" => nil}]
      })

    assert {:ok, updated} = MiniProjectV4.force_complete(session.id, @tenant_schema)
    assert updated.phase == "completed"
    assert updated.final_score == 0
  end

  test "an already-completed session is left untouched" do
    session = insert_session!(%{phase: "completed", final_score: 92, grade_band: "Outstanding"})

    assert {:ok, :already_terminal} = MiniProjectV4.force_complete(session.id, @tenant_schema)

    reloaded = MiniProjectV4.get_session(session.id, @tenant_schema)
    assert reloaded.final_score == 92
    assert reloaded.grade_band == "Outstanding"
  end

  test "an unknown session id returns an error, not a crash" do
    assert {:error, :not_found} = MiniProjectV4.force_complete(Ecto.UUID.generate(), @tenant_schema)
  end
end
