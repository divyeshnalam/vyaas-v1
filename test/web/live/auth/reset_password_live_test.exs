defmodule VyaasaCampusWeb.Auth.ResetPasswordLiveTest do
  @moduledoc """
  The "Passwords do not match" banner was cosmetic only — handle_event
  "reset_password" never actually checked confirm_password against
  password before calling the backend, so a student could see the
  mismatch warning and still successfully submit, silently using whatever
  was typed in the "New Password" field. Pinning the guard that now
  rejects a mismatch at submit time, reading straight from the submitted
  params rather than relying on the phx-change-only `password_match?`
  assign (which isn't set until the first change event fires).
  """

  use ExUnit.Case, async: true

  alias VyaasaCampusWeb.Auth.ResetPasswordLive

  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{assigns: Map.merge(%{__changed__: %{}, loading?: false}, assigns)}
  end

  test "mismatched password and confirm_password is rejected before hitting the backend" do
    params = %{"reset_password" => %{"password" => "Secret123!", "confirm_password" => "Different123!"}}

    {:noreply, updated} = ResetPasswordLive.handle_event("reset_password", params, socket())

    assert updated.assigns.error_message == "Passwords do not match"
    refute updated.assigns[:password_reset?]
  end

  test "an unaccepted terms checkbox is still rejected when passwords do match" do
    params = %{"reset_password" => %{"password" => "Secret123!", "confirm_password" => "Secret123!"}}

    {:noreply, updated} =
      ResetPasswordLive.handle_event("reset_password", params, socket(%{terms_accepted?: false}))

    assert updated.assigns.error_message == "Please accept the Terms and Conditions to continue"
  end
end
