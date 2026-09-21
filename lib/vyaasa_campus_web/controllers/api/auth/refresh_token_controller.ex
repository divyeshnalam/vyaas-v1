defmodule VyaasaCampusWeb.API.Auth.RefreshTokenController do
  use VyaasaCampusWeb, :controller
  import VyaasaCampusWeb.Shared.ErrorHandler

  alias VyaasaCampus.Auth
  alias VyaasaCampus.Guardian
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Accounts.User
  alias VyaasaCampus.Schema.Platform.AdminUser
  alias VyaasaCampus.Schema.Students.Student

  # Body: { refresh_token: "...", user_type: "admin"|"user"|"student", tenant_schema?: "tenant_x" }
  def refresh(conn, %{"refresh_token" => raw, "user_type" => user_type} = params) do
    case do_refresh(raw, user_type, Map.get(params, "tenant_schema")) do
      {:ok, access_token, expires_in, new_refresh, refresh_expires_at} ->
        conn
        |> put_refresh_cookie(new_refresh, refresh_expires_at)
        |> json(%{
          token: access_token,
          expires_in: expires_in
        })

      {:error, _} ->
        handle_auth_error(conn, :refresh_token_invalid)
    end
  end

  defp do_refresh(raw, "admin", _schema) do
    with %AdminUser{} = user <- conn_user_from_refresh(AdminUser, raw),
         {:ok, new_raw, refresh_exp} <- Auth.verify_and_rotate_refresh_token(user, raw),
         {:ok, access, _claims} <-
           Guardian.create_token(user, %{user_type: "admin", sid: user.current_session_id}) do
      {:ok, access, ttl_seconds(), new_raw, refresh_exp}
    else
      _ -> {:error, :invalid}
    end
  end

  defp do_refresh(raw, "user", schema) when is_binary(schema) do
    with %User{} = user <- conn_user_from_refresh({User, schema}, raw),
         {:ok, new_raw, refresh_exp} <- Auth.verify_and_rotate_refresh_token(user, raw, schema),
         {:ok, access, _claims} <-
           Guardian.create_token(user, %{user_type: "user", tenant_schema: schema, sid: user.current_session_id}) do
      {:ok, access, ttl_seconds(), new_raw, refresh_exp}
    else
      _ -> {:error, :invalid}
    end
  end

  defp do_refresh(raw, "student", schema) when is_binary(schema) do
    with %Student{} = user <- conn_user_from_refresh({Student, schema}, raw),
         {:ok, new_raw, refresh_exp} <- Auth.verify_and_rotate_refresh_token(user, raw, schema),
         {:ok, access, _claims} <-
           Guardian.create_token(user, %{user_type: "student", tenant_schema: schema, sid: user.current_session_id}) do
      {:ok, access, ttl_seconds(), new_raw, refresh_exp}
    else
      _ -> {:error, :invalid}
    end
  end

  defp do_refresh(_, _, _), do: {:error, :invalid}

  defp conn_user_from_refresh(AdminUser, raw) do
    hash = Auth |> :erlang.apply(:hash_refresh_token, [raw])
    Repo.get_by(AdminUser, [refresh_token_hash: hash], prefix: "public")
  end

  defp conn_user_from_refresh({User, schema}, raw) do
    hash = Auth |> :erlang.apply(:hash_refresh_token, [raw])
    Repo.get_by(User, [refresh_token_hash: hash], prefix: schema)
  end

  defp conn_user_from_refresh({Student, schema}, raw) do
    hash = Auth |> :erlang.apply(:hash_refresh_token, [raw])
    Repo.get_by(Student, [refresh_token_hash: hash], prefix: schema)
  end

  defp ttl_seconds do
    String.to_integer(System.get_env("ACCESS_TOKEN_TTL_MINUTES") || "30") * 60
  end

  defp cookie_opts do
    host = get_in(Application.get_env(:vyaasa_campus, VyaasaCampusWeb.Endpoint), [:url, :host])
    secure = host != "localhost"
    days = String.to_integer(System.get_env("REFRESH_TOKEN_TTL_DAYS") || "30")
    [http_only: true, secure: secure, same_site: "Lax", path: "/", max_age: days * 24 * 60 * 60]
  end

  defp put_refresh_cookie(conn, token, _expires_at) do
    put_resp_cookie(conn, "rt", token, cookie_opts())
  end
end
