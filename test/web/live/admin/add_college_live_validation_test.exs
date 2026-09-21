defmodule VyaasaCampusWeb.Admin.AddCollegeLiveValidationTest do
  @moduledoc """
  "Contact Email" was never checked before create_college handed off to
  Tenants.create_tenant/1 — which creates and migrates a real Postgres
  schema BEFORE the DB insert's validate_required(:email) catches a blank
  value, then drops the schema again on failure. A wasted schema
  create/migrate/drop cycle on every submit missing this one field, with an
  ambiguous "Email: can't be blank" message on a page with two email
  fields (Contact Email and Admin Email). Pinning the guard that now
  rejects it up front, before any DB/schema work happens.
  """

  use ExUnit.Case, async: true

  alias VyaasaCampusWeb.Admin.AddCollegeLive

  defp socket(college_params_overrides \\ %{}) do
    college_params =
      Map.merge(
        %{"college_name" => "Test College", "college_code" => "TESTCOL", "admin_email" => "admin@test.edu"},
        college_params_overrides
      )

    {%Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}, current_user: %{id: Ecto.UUID.generate()}}},
     %{"college" => college_params}}
  end

  test "a blank contact email is rejected before touching the database" do
    {socket, params} = socket(%{"contact_email" => ""})

    {:noreply, updated} = AddCollegeLive.handle_event("create_college", params, socket)

    assert updated.assigns.saving? == false
  end

  test "a missing contact email key is also rejected" do
    {socket, params} = socket()
    params = %{"college" => Map.delete(params["college"], "contact_email")}

    {:noreply, updated} = AddCollegeLive.handle_event("create_college", params, socket)

    assert updated.assigns.saving? == false
  end
end
