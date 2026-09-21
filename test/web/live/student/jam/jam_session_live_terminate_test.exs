defmodule VyaasaCampusWeb.Student.Jam.JamSessionLiveTerminateTest do
  @moduledoc """
  Closing the tab mid-JAM-session must enqueue finalization — verified by
  calling JamSessionLive.terminate/2 directly against a synthetic connected
  socket (transport_pid: self(), exactly what connected?/1 checks), then
  asserting on the real Oban job it inserts via Oban.Testing (queues run in
  :manual mode in test — see config/test.exs — so this checks the job got
  queued, not that it ran).
  """

  use VyaasaCampus.DataCase, async: false
  use Oban.Testing, repo: VyaasaCampus.Repo

  alias VyaasaCampus.Jobs.AssessmentFinalizer
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Jam.JamSession
  alias VyaasaCampusWeb.Student.Jam.JamSessionLive

  @tenant_schema "tenant_test"

  defp insert_session! do
    {:ok, session} =
      %JamSession{}
      |> JamSession.create_changeset(%{
        student_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate(),
        session_token: "tok-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert(prefix: @tenant_schema)

    session
  end

  defp connected_socket(assigns) do
    %Phoenix.LiveView.Socket{transport_pid: self(), assigns: Map.merge(%{__changed__: %{}}, assigns)}
  end

  test "a connected socket closing mid-session enqueues an AssessmentFinalizer job" do
    session = insert_session!()
    socket = connected_socket(%{jam_session: session, tenant_schema: @tenant_schema})

    assert :ok = JamSessionLive.terminate(:shutdown, socket)

    assert_enqueued(
      worker: AssessmentFinalizer,
      args: %{"type" => "jam", "session_id" => session.id, "tenant_schema" => @tenant_schema}
    )
  end

  test "the disconnected initial render does not enqueue anything" do
    session = insert_session!()

    socket = %Phoenix.LiveView.Socket{
      transport_pid: nil,
      assigns: %{__changed__: %{}, jam_session: session, tenant_schema: @tenant_schema}
    }

    assert :ok = JamSessionLive.terminate(:shutdown, socket)
    refute_enqueued(worker: AssessmentFinalizer, args: %{"session_id" => session.id})
  end

  test "no jam_session assign (pre-load / early-redirect mount paths) does not raise" do
    socket = connected_socket(%{jam_session: nil, tenant_schema: @tenant_schema})
    assert :ok = JamSessionLive.terminate(:shutdown, socket)
    refute_enqueued(worker: AssessmentFinalizer)
  end
end
