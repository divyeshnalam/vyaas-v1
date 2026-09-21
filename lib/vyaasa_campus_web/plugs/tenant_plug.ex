defmodule VyaasaCampusWeb.Plugs.TenantPlug do
  @moduledoc """
  Plug to resolve tenant context from URL parameters or subdomain.

  This plug extracts tenant information and makes it available to LiveViews
  for authentication and tenant-specific operations.
  """

  import Plug.Conn
  alias VyaasaCampus.Contexts.Tenants

  def init(opts), do: opts

  def call(conn, _opts) do
    # Extract tenant from various sources and normalize to uppercase for DB lookup
    raw_alias = get_tenant_from_request(conn)
    tenant_alias = if raw_alias, do: String.upcase(raw_alias), else: raw_alias
    tenant = Tenants.get_tenant_by_alias(tenant_alias)

    conn
    |> assign(:tenant_alias, tenant_alias)
    |> assign(:tenant, tenant)
    |> assign(:tenant_info, get_tenant_info(tenant_alias))
  end

  # Private helper functions

  defp get_tenant_from_request(conn) do
    # Priority order: x-tenant header > URL path > query param > subdomain > default
    cond do
      tenant_from_header?(conn) -> get_tenant_from_header(conn)
      tenant_from_path?(conn) -> get_tenant_from_path(conn)
      tenant_from_query?(conn) -> get_tenant_from_query(conn)
      tenant_from_subdomain?(conn) -> get_tenant_from_subdomain(conn)
      # Default fallback
      true -> "demo_tenant"
    end
  end

  defp tenant_from_header?(conn) do
    case get_req_header(conn, "x-tenant") do
      [tenant_alias] when tenant_alias != "" -> true
      _ -> false
    end
  end

  defp get_tenant_from_header(conn) do
    [tenant_alias] = get_req_header(conn, "x-tenant")
    tenant_alias
  end

  defp tenant_from_path?(conn) do
    # Check if URL path contains /tenant/{tenant_alias}/ or /api/tenant/students/{id}/resume/{filename} pattern
    case conn.path_info do
      ["tenant", tenant_alias | _] when tenant_alias != "" -> true
      ["api", "tenant", "students", _student_id, "resume", _filename] -> true
      _ -> false
    end
  end

  defp get_tenant_from_path(conn) do
    # Extract tenant from URL path like /tenant/KLEF/... or /api/tenant/students/{id}/resume/{filename}
    case conn.path_info do
      ["tenant", tenant_alias | _] ->
        tenant_alias

      ["api", "tenant", "students", _student_id, "resume", _filename] ->
        # For resume API requests, extract tenant from referer header
        extract_tenant_from_referer(conn)

      _ ->
        nil
    end
  end

  defp extract_tenant_from_referer(conn) do
    # For API requests, we need to extract tenant from the referer header
    case get_req_header(conn, "referer") do
      [referer] ->
        # Extract tenant from referer URL patterns:
        # /tenant/KLEF/dashboard, /user/KLEF/dashboard, /student/KLEF/dashboard
        case Regex.run(~r{/(?:tenant|user|student)/([^/]+)/}, referer) do
          [_, tenant_alias] -> tenant_alias
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp tenant_from_query?(conn) do
    Map.has_key?(conn.query_params, "tenant")
  end

  defp get_tenant_from_query(conn) do
    conn.query_params["tenant"]
  end

  defp tenant_from_subdomain?(conn) do
    case get_subdomain(conn) do
      subdomain when not is_nil(subdomain) -> true
      _ -> false
    end
  end

  defp get_tenant_from_subdomain(conn) do
    get_subdomain(conn)
  end

  defp get_subdomain(conn) do
    # Extract subdomain from host
    case get_req_header(conn, "host") do
      [host] ->
        case String.split(host, ".") do
          [subdomain | _] when subdomain != "localhost" and subdomain != "127.0.0.1" ->
            subdomain

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp get_tenant_info(tenant_alias) do
    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil ->
        %{
          alias: tenant_alias,
          full_name: "Tenant Not Found",
          found: false,
          schema_name: nil
        }

      tenant ->
        %{
          id: tenant.id,
          alias: tenant.alias,
          full_name: tenant.full_name,
          found: true,
          schema_name: tenant.schema_name
        }
    end
  end
end
