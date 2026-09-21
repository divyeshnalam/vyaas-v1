defmodule VyaasaCampus.Auth.AuthServerScopeTest do
  use ExUnit.Case, async: true

  alias VyaasaCampus.Auth.{AuthServer, Scope}

  test "scope cache miss then put and hit" do
    key = "k1"
    assert {:miss} = AuthServer.get_scope(key)

    scope = %Scope{user_id: "u1", user_type: "admin", issued_at: DateTime.utc_now()}
    AuthServer.put_scope(key, scope, 1)

    assert {:hit, %Scope{user_id: "u1"}} = AuthServer.get_scope(key)
    :timer.sleep(1100)
    assert {:expired} = AuthServer.get_scope(key)
  end

  test "invalidate scope" do
    key = "k2"
    scope = %Scope{user_id: "u2", user_type: "student", issued_at: DateTime.utc_now()}
    AuthServer.put_scope(key, scope, 60)
    assert {:hit, _} = AuthServer.get_scope(key)
    AuthServer.invalidate_scope(key)
    assert {:miss} = AuthServer.get_scope(key)
  end
end
