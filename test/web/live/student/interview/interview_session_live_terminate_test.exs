defmodule VyaasaCampusWeb.Student.Interview.InterviewSessionLiveTerminateTest do
  @moduledoc """
  Closing the tab mid-interview must enqueue finalization — this type
  previously had no completion path at all for an abandoned session.
  Verified by calling InterviewSessionLive.terminate/2 directly against a
  synthetic connected socket, then asserting on the real Oban job via
  Oban.Testing (queues run in :manual mode in test).
  """

  use VyaasaCampus.DataCase, async: false
  use Oban.Testing, repo: VyaasaCampus.Repo

  alias VyaasaCampus.Jobs.AssessmentFinalizer
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Interview.InterviewSession
  alias VyaasaCampusWeb.Student.Interview.InterviewSessionLive

  @tenant_schema "tenant_test"

  defp insert_session! do
    {:ok, session} =
      %InterviewSession{}
      |> InterviewSession.create_changeset(%{student_id: Ecto.UUID.generate(), tenant_id: Ecto.UUID.generate()})
      |> Repo.insert(prefix: @tenant_schema)

    session
  end

  defp connected_socket(assigns) do
    %Phoenix.LiveView.Socket{transport_pid: self(), assigns: Map.merge(%{__changed__: %{}}, assigns)}
  end

  test "a connected socket closing mid-interview enqueues an AssessmentFinalizer job" do
    session = insert_session!()
    socket = connected_socket(%{interview_session: session, tenant_schema: @tenant_schema})

    assert :ok = InterviewSessionLive.terminate(:shutdown, socket)

    assert_enqueued(
      worker: AssessmentFinalizer,
      args: %{"type" => "interview", "session_id" => session.id, "tenant_schema" => @tenant_schema}
    )
  end

  test "the disconnected initial render does not enqueue anything" do
    session = insert_session!()

    socket = %Phoenix.LiveView.Socket{
      transport_pid: nil,
      assigns: %{__changed__: %{}, interview_session: session, tenant_schema: @tenant_schema}
    }

    assert :ok = InterviewSessionLive.terminate(:shutdown, socket)
    refute_enqueued(worker: AssessmentFinalizer, args: %{"session_id" => session.id})
  end

  test "no interview_session assign does not raise" do
    socket = connected_socket(%{interview_session: nil, tenant_schema: @tenant_schema})
    assert :ok = InterviewSessionLive.terminate(:shutdown, socket)
    refute_enqueued(worker: AssessmentFinalizer)
  end
end
