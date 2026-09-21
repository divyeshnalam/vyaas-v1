defmodule VyaasaCampusWeb.ErrorController do
  @moduledoc """
  Catches any request that doesn't match a defined route so the friendly
  404 page renders directly instead of raising Phoenix.Router.NoRouteError
  (which Plug.Debugger intercepts with a routes dump in dev).
  """
  use VyaasaCampusWeb, :controller

  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_view(html: VyaasaCampusWeb.ErrorHTML)
    |> put_root_layout(false)
    |> put_layout(false)
    |> render(:"404")
  end
end
