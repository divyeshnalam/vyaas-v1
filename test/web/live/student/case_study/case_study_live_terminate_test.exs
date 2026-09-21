defmodule VyaasaCampusWeb.Student.CaseStudy.CaseStudyLiveTerminateTest do
  @moduledoc """
  Closing the tab mid-attempt must enqueue finalization — this type had no
  completion path at all for an abandoned session. Verified by calling
  CaseStudyLive.terminate/2 directly against a synthetic connected socket,
  then asserting on the real Oban job via Oban.Testing (queues run in
  :manual mode in test).
  """

  use VyaasaCampus.DataCase, async: false
  use Oban.Testing, repo: VyaasaCampus.Repo

  alias VyaasaCampus.Jobs.AssessmentFinalizer
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.CaseStudy.CaseStudySession
  alias VyaasaCampusWeb.Student.CaseStudy.CaseStudyLive

  @tenant_schema "tenant_test"

  defp insert_session! do
    {:ok, session} =
      %CaseStudySession{}
      |> CaseStudySession.create_changeset(%{
        student_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate(),
        session_token: "tok-#{System.unique_integer([:positive])}",
        specialization_sub: "backend"
      })
      |> Repo.insert(prefix: @tenant_schema)

    session
  end

  defp connected_socket(assigns) do
    %Phoenix.LiveView.Socket{transport_pid: self(), assigns: Map.merge(%{__changed__: %{}}, assigns)}
  end

  test "a connected socket closing mid-attempt enqueues an AssessmentFinalizer job" do
    session = insert_session!()
    socket = connected_socket(%{session: session, tenant_schema: @tenant_schema})

    assert :ok = CaseStudyLive.terminate(:shutdown, socket)

    assert_enqueued(
      worker: AssessmentFinalizer,
      args: %{"type" => "case_study", "session_id" => session.session_token, "tenant_schema" => @tenant_schema}
    )
  end

  test "the disconnected initial render does not enqueue anything" do
    session = insert_session!()

    socket = %Phoenix.LiveView.Socket{
      transport_pid: nil,
      assigns: %{__changed__: %{}, session: session, tenant_schema: @tenant_schema}
    }

    assert :ok = CaseStudyLive.terminate(:shutdown, socket)
    refute_enqueued(worker: AssessmentFinalizer, args: %{"session_id" => session.session_token})
  end

  test "no session assign (still on the intro/choose step) does not raise" do
    socket = connected_socket(%{session: nil, tenant_schema: @tenant_schema})
    assert :ok = CaseStudyLive.terminate(:shutdown, socket)
    refute_enqueued(worker: AssessmentFinalizer)
  end
end
