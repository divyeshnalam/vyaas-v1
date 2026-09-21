defmodule VyaasaCampusWeb.ReportController do
  @moduledoc """
  On-demand report PDF download for ADMINS only (leaderboard / specialization).

  Student assessment reports are no longer downloadable — they are generated and
  emailed automatically on completion (see `VyaasaCampus.Jobs.ReportGenerator`).
  """

  use VyaasaCampusWeb, :controller

  alias VyaasaCampus.Contexts.Tenants

  @doc """
  Admin leaderboard PDF. Accepts optional `department`, `specialization`,
  and `year` query params that mirror the dashboard's leaderboard filters.
  """
  def download_leaderboard(conn, %{"tenant" => tenant_alias} = params) do
    filters = Map.take(params, ["department", "specialization", "year"])
    download_admin(conn, :leaderboard, filters, tenant_alias)
  end

  @doc "Admin specialization-wise performance PDF."
  def download_specialization(conn, %{"tenant" => tenant_alias}) do
    download_admin(conn, :specialization, %{}, tenant_alias)
  end

  @doc "Admin analytics overview PDF (readiness, completion, alerts, departments)."
  def download_analytics(conn, %{"tenant" => tenant_alias}) do
    download_admin(conn, :analytics, %{}, tenant_alias)
  end

  @doc "Admin placement-readiness PDF (funnel, tier distribution, department heatmap)."
  def download_readiness(conn, %{"tenant" => tenant_alias}) do
    download_admin(conn, :readiness, %{}, tenant_alias)
  end

  defp download_admin(conn, type, params, tenant_alias) do
    with {:ok, tenant_schema} <- resolve_tenant_schema(tenant_alias),
         {:ok, context} <- VyaasaCampus.Reports.load_context(type, params, tenant_schema),
         {:ok, binary} <- VyaasaCampus.Reports.generate_pdf(type, params, tenant_schema) do
      filename = VyaasaCampus.Reports.filename(type, context)

      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, binary)
    else
      error -> render_error(conn, error)
    end
  end

  defp render_error(conn, {:error, :tenant_not_found}), do: send_resp(conn, 404, "Tenant not found")
  defp render_error(conn, {:error, _}), do: send_resp(conn, 500, "Unable to generate report")

  defp resolve_tenant_schema(tenant_alias) do
    case Tenants.get_tenant_by_alias(String.upcase(tenant_alias)) do
      nil -> {:error, :tenant_not_found}
      tenant -> {:ok, tenant.schema_name}
    end
  end
end
