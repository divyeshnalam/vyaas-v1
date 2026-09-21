defmodule VyaasaCampus.Contexts.CaseStudyForceCompleteTest do
  @moduledoc """
  CaseStudy.force_complete/2 closes the gap where a session left mid-attempt
  (7 sections answered only in LiveView assigns, never persisted
  incrementally) sat non-terminal forever if the student never submitted.

  Same as Behavioral, there is nothing partial to recover — every path here
  produces a direct zero score. What's worth pinning: idempotency across all
  three pre-existing terminal statuses, including the pre-existing
  `"terminated"` status (proctoring auto-finalize with no score), which must
  NOT be reprocessed into a `"completed"` record.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.CaseStudy
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.CaseStudy.CaseStudySession

  @tenant_schema "tenant_test"

  defp insert_session!(attrs) do
    defaults = %{
      student_id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      session_token: "tok-#{System.unique_integer([:positive])}",
      specialization_sub: "backend"
    }

    {:ok, session} =
      %CaseStudySession{}
      |> CaseStudySession.create_changeset(Map.merge(defaults, attrs))
      |> Repo.insert(prefix: @tenant_schema)

    session
  end

  test "a session abandoned mid-attempt gets a direct zero score" do
    session = insert_session!(%{})

    assert {:ok, updated} = CaseStudy.force_complete(session.session_token, @tenant_schema)
    assert updated.status == "completed"
    assert updated.total_score == 0
    assert updated.domain_score == 0
    assert updated.report["summary"] =~ "abandoned"
  end

  test "an already-completed session is left untouched" do
    session = insert_session!(%{})

    {:ok, completed} =
      session
      |> CaseStudySession.complete_changeset(%{status: "completed", total_score: 91})
      |> Repo.update(prefix: @tenant_schema)

    assert {:ok, :already_terminal} = CaseStudy.force_complete(completed.session_token, @tenant_schema)

    reloaded = CaseStudy.get_session_by_token(completed.session_token, @tenant_schema)
    assert reloaded.total_score == 91
  end

  test "an already-failed session is also left untouched" do
    session = insert_session!(%{})

    {:ok, failed} =
      session
      |> CaseStudySession.complete_changeset(%{status: "failed"})
      |> Repo.update(prefix: @tenant_schema)

    assert {:ok, :already_terminal} = CaseStudy.force_complete(failed.session_token, @tenant_schema)
  end

  test "a session already terminated by the proctoring auto-finalize is left untouched, not rescored" do
    session = insert_session!(%{})

    {:ok, terminated} = CaseStudy.terminate(session, @tenant_schema)
    assert terminated.status == "terminated"

    assert {:ok, :already_terminal} = CaseStudy.force_complete(terminated.session_token, @tenant_schema)

    reloaded = CaseStudy.get_session_by_token(terminated.session_token, @tenant_schema)
    assert reloaded.status == "terminated"
    assert reloaded.total_score == nil
  end

  test "an unknown session token returns an error, not a crash" do
    assert {:error, :not_found} = CaseStudy.force_complete("no-such-token", @tenant_schema)
  end
end
