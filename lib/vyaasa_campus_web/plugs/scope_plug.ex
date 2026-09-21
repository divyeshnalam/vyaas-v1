defmodule VyaasaCampusWeb.Plugs.ScopePlug do
  @moduledoc """
  Plug to load a request scope and assign it to conn.assigns[:scope].

  Follows Phoenix 1.8 guidance: derive on each request, use ETS-cached scope when possible.
  """

  import Plug.Conn
  alias VyaasaCampus.Auth.{AuthServer, Scope}
  alias VyaasaCampus.Guardian
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Accounts.User
  alias VyaasaCampus.Schema.Platform.AdminUser
  alias VyaasaCampus.Schema.Students.Student

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_token(conn) do
      nil ->
        assign(conn, :scope, nil)

      token ->
        scope = get_or_build_scope(token)
        assign(conn, :scope, scope)
    end
  end

  defp get_or_build_scope(token) do
    case AuthServer.get_scope(token) do
      {:hit, %Scope{} = scope} ->
        scope

      _ ->
        build_and_cache_scope(token)
    end
  end

  defp build_and_cache_scope(token) do
    scope = build_scope_from_token(token)

    case scope do
      %Scope{} = s ->
        AuthServer.put_scope(token, s)
        s

      _ ->
        nil
    end
  end

  defp get_token(conn) do
    # Try header first, then session for LiveView compatibility
    token = get_bearer(conn) || get_session_token(conn)

    require Logger

    Logger.info(
      "ScopePlug: Token retrieval - header: #{inspect(get_bearer(conn) != nil)}, session: #{inspect(get_session_token(conn) != nil)}"
    )

    token
  end

  defp get_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when is_binary(token) -> token
      _ -> nil
    end
  end

  defp get_session_token(conn) do
    case get_session(conn, :auth_token) do
      token when is_binary(token) and byte_size(token) > 0 -> token
      _ -> nil
    end
  end

  defp build_scope_from_token(token) do
    case Guardian.current_user(token) do
      {:ok, %AdminUser{} = admin} ->
        %Scope{
          user_id: admin.id,
          user_type: "admin",
          user_status: admin.status,
          issued_at: DateTime.utc_now()
        }

      {:ok, _claims, %AdminUser{} = admin} ->
        %Scope{
          user_id: admin.id,
          user_type: "admin",
          user_status: admin.status,
          issued_at: DateTime.utc_now()
        }

      {:ok, %User{} = user} ->
        tenant_scope_from_user(user, token)

      {:ok, _claims, %User{} = user} ->
        tenant_scope_from_user(user, token)

      {:ok, %Student{} = student} ->
        tenant_scope_from_student(student, token)

      {:ok, _claims, %Student{} = student} ->
        tenant_scope_from_student(student, token)

      _ ->
        nil
    end
  end

  defp tenant_scope_from_user(user, token) do
    # Extract tenant_schema from token claims if needed
    case Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        schema = Map.get(claims, "tenant_schema", "public")
        roles = preload_roles(user, schema)
        permissions = flatten_permissions(roles)

        %Scope{
          user_id: user.id,
          user_type: "user",
          tenant_schema: schema,
          roles: Enum.map(roles, & &1.name),
          permissions: permissions,
          user_status: user.status,
          issued_at: DateTime.utc_now()
        }

      _ ->
        nil
    end
  end

  defp tenant_scope_from_student(student, token) do
    case Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        schema = Map.get(claims, "tenant_schema", "public")

        %Scope{
          user_id: student.id,
          user_type: "student",
          tenant_schema: schema,
          user_status: student.status,
          issued_at: DateTime.utc_now()
        }

      _ ->
        nil
    end
  end

  defp preload_roles(user, schema) do
    user
    |> Repo.preload([:roles], prefix: schema)
    |> Map.get(:roles, [])
  end

  defp flatten_permissions(roles) do
    roles
    |> Enum.flat_map(fn r -> r.permissions || [] end)
    |> Enum.uniq()
  end
end
