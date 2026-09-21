defmodule VyaasaCampus.Contexts.InterviewForceCompleteTest do
  @moduledoc """
  Interview.force_complete/2 is the FIRST force-completion path this type has
  ever had — the investigation found the countdown timer reaching zero
  doesn't even submit for a connected student, let alone one who closed the
  tab. Scores from whatever questions were already answered
  (average_question_score/1), the same fallback the live completion path
  uses. Deliberately does not exercise the conversational engine itself
  (in-memory only, lost with the LiveView process) or a real LLM call —
  matching how the rest of this codebase avoids unit-testing LLM paths.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.Interview
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.AI8.ModuleEvaluation
  alias VyaasaCampus.Schema.Interview.InterviewSession

  @tenant_schema "tenant_test"

  # create_changeset/2 forces status: "created" unconditionally — insert
  # normally, then set the desired status/data directly, matching how the
  # real lifecycle changesets progress a session.
  defp insert_session!(attrs) do
    {status, rest} = Map.pop(attrs, :status)

    {:ok, session} =
      %InterviewSession{}
      |> InterviewSession.create_changeset(%{student_id: Ecto.UUID.generate(), tenant_id: Ecto.UUID.generate()})
      |> Repo.insert(prefix: @tenant_schema)

    {:ok, session} =
      session
      |> Ecto.Changeset.change(Map.merge(rest, %{status: status || session.status}))
      |> Repo.update(prefix: @tenant_schema)

    session
  end

  describe "average_question_score/1" do
    test "averages the score field across answered questions" do
      assert Interview.average_question_score([%{"score" => 80}, %{"score" => 60}]) == 70.0
    end

    test "is zero for no questions" do
      assert Interview.average_question_score([]) == 0
    end
  end

  test "a session abandoned before any question was answered gets a direct zero score" do
    session = insert_session!(%{status: "initialized"})

    assert {:ok, updated} = Interview.force_complete(session.id, @tenant_schema)
    assert updated.status == "completed"
    assert Decimal.to_integer(updated.overall_score) == 0
    assert updated.session_summary["answered_questions"] == 0
    assert updated.final_report =~ "abandoned before any questions"
  end

  test "a session abandoned mid-interview scores from whatever was already answered" do
    session =
      insert_session!(%{
        status: "interviewing",
        questions_data: %{
          "questions" => [
            %{"question_number" => 1, "score" => 80},
            %{"question_number" => 2, "score" => 60}
          ]
        }
      })

    assert {:ok, updated} = Interview.force_complete(session.id, @tenant_schema)
    assert updated.status == "completed"
    assert Decimal.to_integer(updated.overall_score) == 70
    assert updated.session_summary["answered_questions"] == 2
    assert updated.final_report =~ "2 question(s) were answered"
  end

  test "an already-completed session is left untouched" do
    session = insert_session!(%{status: "completed", overall_score: 91})

    assert {:ok, :already_terminal} = Interview.force_complete(session.id, @tenant_schema)

    reloaded = Interview.get_interview_session(session.id, @tenant_schema)
    assert Decimal.to_integer(reloaded.overall_score) == 91
  end

  test "an already-failed session is also left untouched" do
    session = insert_session!(%{status: "failed"})

    assert {:ok, :already_terminal} = Interview.force_complete(session.id, @tenant_schema)

    reloaded = Interview.get_interview_session(session.id, @tenant_schema)
    assert reloaded.status == "failed"
  end

  test "an unknown session id returns an error, not a crash" do
    assert {:error, :not_found} = Interview.force_complete(Ecto.UUID.generate(), @tenant_schema)
  end

  test "force_complete's zero-content session_summary has no skill_scores, so no AI8 row is published" do
    session = insert_session!(%{status: "initialized"})

    assert {:ok, updated} = Interview.force_complete(session.id, @tenant_schema)
    refute Repo.get_by(ModuleEvaluation, [source_id: updated.id], prefix: @tenant_schema)
  end

  # Regression: AI8.publish_evaluation used to be called only from the
  # LiveView's live evaluation-done handler, never from
  # Interview.complete_interview/3 itself — so force_complete/2 (which also
  # calls complete_interview/3) silently never reached AI8. Testing
  # complete_interview/3 directly here covers every caller without invoking
  # the real conversational engine/LLM. Also pins that the live path's
  # original behavior — the AI8-weighted module score overriding the
  # plain-average fallback — was preserved by the move, not just the call
  # itself.
  test "complete_interview/3 publishes to AI8 and overrides overall_score with the weighted module score" do
    session = insert_session!(%{status: "interviewing"})

    attrs = %{
      overall_score: 999,
      final_report: "report",
      session_summary: %{"skill_scores" => %{"communication" => 80, "confidence" => 70}},
      strengths: [],
      improvements: []
    }

    assert {:ok, updated} = Interview.complete_interview(session, attrs, @tenant_schema)

    eval = Repo.get_by(ModuleEvaluation, [source_id: updated.id], prefix: @tenant_schema)
    assert eval
    assert eval.module == "interview"
    # No AI8 dimension weights configured in test env -> plain average of the
    # two scores (80 + 70) / 2 = 75, not the 999 the caller passed in.
    refute Decimal.to_integer(updated.overall_score) == 999
    assert Decimal.to_integer(updated.overall_score) == 75
  end
end
