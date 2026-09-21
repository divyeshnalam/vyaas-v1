defmodule VyaasaCampusWeb.Student.BehavioralLiveTerminateTest do
  @moduledoc """
  Closing the tab mid-conversation must enqueue finalization — this type
  previously explicitly abandoned a stale row on the student's next visit,
  never resuming or scoring it. Verified by calling BehavioralLive.terminate/2
  directly against a synthetic connected socket, then asserting on the real
  Oban job via Oban.Testing (queues run in :manual mode in test).
  """

  use VyaasaCampus.DataCase, async: false
  use Oban.Testing, repo: VyaasaCampus.Repo

  alias VyaasaCampus.Jobs.AssessmentFinalizer
  alias VyaasaCampusWeb.Student.BehavioralLive

  defp connected_socket(assigns) do
    %Phoenix.LiveView.Socket{transport_pid: self(), assigns: Map.merge(%{__changed__: %{}}, assigns)}
  end

  test "a connected socket closing mid-conversation enqueues an AssessmentFinalizer job" do
    session_id = "sess-#{System.unique_integer([:positive])}"
    socket = connected_socket(%{session_id: session_id, tenant_schema: "tenant_test"})

    assert :ok = BehavioralLive.terminate(:shutdown, socket)

    assert_enqueued(
      worker: AssessmentFinalizer,
      args: %{"type" => "behavioral", "session_id" => session_id, "tenant_schema" => "tenant_test"}
    )
  end

  test "the disconnected initial render does not enqueue anything" do
    session_id = "sess-#{System.unique_integer([:positive])}"

    socket = %Phoenix.LiveView.Socket{
      transport_pid: nil,
      assigns: %{__changed__: %{}, session_id: session_id, tenant_schema: "tenant_test"}
    }

    assert :ok = BehavioralLive.terminate(:shutdown, socket)
    refute_enqueued(worker: AssessmentFinalizer, args: %{"session_id" => session_id})
  end

  test "no session_id assign (pre-load / early-redirect mount paths) does not raise" do
    socket = connected_socket(%{session_id: nil, tenant_schema: "tenant_test"})
    assert :ok = BehavioralLive.terminate(:shutdown, socket)
    refute_enqueued(worker: AssessmentFinalizer)
  end
end
