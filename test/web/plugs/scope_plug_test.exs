defmodule VyaasaCampusWeb.Plugs.ScopePlugTest do
  use VyaasaCampusWeb.ConnCase, async: true

  import Plug.Conn
  alias VyaasaCampusWeb.Plugs.ScopePlug
  alias VyaasaCampus.Auth.{AuthServer, Scope}

  test "assigns scope from cache when present", %{conn: conn} do
    token = "t-cache"
    scope = %Scope{user_id: "u", user_type: "admin", issued_at: DateTime.utc_now()}
    AuthServer.put_scope(token, scope, 60)

    conn =
      conn
      |> init_test_session(%{})
      |> put_req_header("authorization", "Bearer " <> token)
      |> ScopePlug.call([])

    assert %Scope{user_id: "u"} = conn.assigns[:scope]
  end

  test "no auth header assigns nil scope", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> ScopePlug.call([])

    refute conn.assigns[:scope]
  end
end
