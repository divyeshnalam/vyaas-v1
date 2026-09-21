defmodule VyaasaCampusWeb.ErrorJSONTest do
  use VyaasaCampusWeb.ConnCase, async: true

  test "renders 404" do
    assert VyaasaCampusWeb.ErrorJSON.render("404.json", %{}) == %{
             error: "Not Found",
             message: "The requested resource was not found",
             status: 404
           }
  end

  test "renders 500" do
    assert VyaasaCampusWeb.ErrorJSON.render("500.json", %{}) == %{
             error: "Internal Server Error",
             message: "An unexpected error occurred on the server",
             status: 500
           }
  end
end
