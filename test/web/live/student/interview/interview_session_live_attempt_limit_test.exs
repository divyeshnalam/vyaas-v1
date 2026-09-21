defmodule VyaasaCampusWeb.Student.Interview.InterviewSessionLiveAttemptLimitTest do
  @moduledoc """
  Two bugs found while investigating "attempts increased but I still can't
  start a new interview":

  1. `maybe_restore_completed_session/3` unconditionally jumped to the
     :results screen on every mount if the student had ANY completed
     interview, with no button anywhere to start a new attempt — an
     increased limit had no way to ever be used. Fixed by adding
     "start_new_interview", which resets the LiveView back to the start
     screen (NOT via the destructive `retry_interview`, which wipes and
     reuses the same completed row).

  2. `AttemptGuard.check/4` rejects with a 3-tuple —
     `{:error, :attempt_limit_reached, %{used:, limit:, granted:}}` — the
     exact same shape that already caused a WithClauseError crash in ATS
     re-analysis (see StudentAtsTest). The interview start flow's
     `handle_info({:session_ready, {:error, reason}}, socket)` only matched
     a 2-tuple, so this fell through to the LiveView's catch-all
     `handle_info(_msg, socket)` and was silently dropped — the student
     just saw the loading spinner hang forever with no message, even once
     they'd genuinely hit the limit.

  Doesn't re-test AttemptGuard's own blocking logic (covered by
  StudentAtsTest's identical pattern) — this only pins the interview
  LiveView's handling of that exact rejection shape, and that a fresh start
  is actually reachable from a completed result.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampusWeb.Student.Interview.InterviewSessionLive

  defp connected_socket(assigns) do
    %Phoenix.LiveView.Socket{transport_pid: self(), assigns: Map.merge(%{__changed__: %{}}, assigns)}
  end

  test "a 3-tuple attempt_limit_reached rejection sets a friendly error, not a stuck spinner" do
    socket =
      connected_socket(%{
        current_step: :initialize,
        loading: :indexing,
        interview_phase: :indexing,
        error: nil
      })

    {:noreply, updated} =
      InterviewSessionLive.handle_info(
        {:session_ready, {:error, :attempt_limit_reached, %{used: 3, limit: 3, granted: 0}}},
        socket
      )

    assert updated.assigns.loading == nil
    assert updated.assigns.interview_phase == :welcome
    assert updated.assigns.error =~ "contact your college admin"
  end

  test "an ordinary 2-tuple start failure still goes through the existing error path" do
    socket =
      connected_socket(%{current_step: :initialize, loading: :indexing, interview_phase: :indexing, error: nil})

    {:noreply, updated} =
      InterviewSessionLive.handle_info({:session_ready, {:error, :no_resume}}, socket)

    assert updated.assigns.loading == nil
    assert updated.assigns.interview_phase == :welcome
    assert updated.assigns.error =~ "resume"
  end

  test "start_new_interview on a results-locked socket with no resume shows an error in place, without leaving :results" do
    socket =
      connected_socket(%{
        current_step: :results,
        interview_phase: :results,
        overall_score: 91,
        ats_data: nil
      })

    {:noreply, updated} = InterviewSessionLive.handle_event("start_new_interview", %{}, socket)

    # Same pattern as the MCQ retry flow: the completed report stays on
    # screen and the error is layered on top, instead of bouncing to the
    # :initialize start screen first.
    assert updated.assigns.current_step == :results
    assert updated.assigns.interview_phase == :results
    assert updated.assigns.overall_score == 91
    assert updated.assigns.error =~ "resume"
  end

  test "start_new_interview succeeding replaces the old report and moves off :results" do
    socket =
      connected_socket(%{
        current_step: :results,
        interview_phase: :results,
        overall_score: 91,
        error: nil,
        ats_data: nil
      })

    session = %{
      session_id: "sess-1",
      session_state: %{},
      max_questions: 5,
      greeting: %{text: "Hi", spoken: nil}
    }

    db_session = %{max_duration_minutes: 10}

    {:noreply, updated} =
      InterviewSessionLive.handle_info({:session_ready, {:ok, db_session, session}}, socket)

    assert updated.assigns.current_step == :initialize
    assert updated.assigns.interview_phase == :ready
    assert updated.assigns.overall_score == nil
  end
end
