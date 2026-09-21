defmodule VyaasaCampusWeb.Admin.CollegesController do
  @moduledoc "CSV export of platform colleges (tenants) for the super-admin Colleges screen."
  use VyaasaCampusWeb, :controller

  alias VyaasaCampus.Contexts.Tenants

  def export(conn, _params) do
    header = ["Name", "Code", "Type", "Status", "Created"]

    rows =
      Tenants.list_tenants()
      |> Enum.map(fn t ->
        [
          t.full_name || t.alias,
          t.short_name || t.alias,
          t.affiliation_type || "College",
          if(t.status == "active", do: "Active", else: "Inactive"),
          fmt(t.inserted_at)
        ]
      end)

    csv =
      [header | rows]
      |> Enum.map_join("\n", fn cols -> Enum.map_join(cols, ",", &escape/1) end)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="colleges.csv"))
    |> send_resp(200, csv)
  end

  defp escape(v) do
    s = to_string(v)
    if String.contains?(s, [",", "\"", "\n"]), do: ~s("#{String.replace(s, "\"", "\"\"")}"), else: s
  end

  defp fmt(%DateTime{} = d), do: Calendar.strftime(d, "%Y-%m-%d")
  defp fmt(%NaiveDateTime{} = d), do: Calendar.strftime(d, "%Y-%m-%d")
  defp fmt(_), do: ""
end
