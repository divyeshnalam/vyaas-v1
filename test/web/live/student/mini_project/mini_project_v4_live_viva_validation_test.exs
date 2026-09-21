defmodule VyaasaCampusWeb.Student.MiniProject.MiniProjectV4LiveVivaValidationTest do
  @moduledoc """
  Unlike its V1 sibling, the V4 viva's "submit_viva_answer" handler called
  advance_viva/1 unconditionally — a student could click through all 12
  viva questions with an empty textbox, silently persisting blank answers
  (scored accordingly) with no warning. Pinning the guard added to match
  V1's existing "Please type your answer before submitting." behavior.

  Deliberately doesn't exercise the real advance_viva/1 path (DB + LLM
  calls) — only that a blank answer short-circuits before ever reaching it.
  """

  use ExUnit.Case, async: true

  alias VyaasaCampusWeb.Student.MiniProject.MiniProjectV4Live

  defp socket(viva_answer) do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, viva_answer: viva_answer, error: nil}}
  end

  test "an empty viva answer is rejected with a message, not silently submitted" do
    {:noreply, updated} = MiniProjectV4Live.handle_event("submit_viva_answer", %{}, socket(""))

    assert updated.assigns.error == "Please type your answer before submitting."
  end

  test "a whitespace-only viva answer is also rejected" do
    {:noreply, updated} = MiniProjectV4Live.handle_event("submit_viva_answer", %{}, socket("   "))

    assert updated.assigns.error == "Please type your answer before submitting."
  end
end
