defmodule VyaasaCampusWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # Custom error responses for specific status codes
  def render("400.json", _assigns) do
    %{
      error: "Bad Request",
      message: "The request could not be understood or contained invalid parameters",
      status: 400
    }
  end

  def render("401.json", _assigns) do
    %{
      error: "Unauthorized",
      message: "Authentication is required to access this resource",
      status: 401
    }
  end

  def render("403.json", _assigns) do
    %{
      error: "Forbidden",
      message: "You do not have permission to access this resource",
      status: 403
    }
  end

  def render("404.json", _assigns) do
    %{
      error: "Not Found",
      message: "The requested resource was not found",
      status: 404
    }
  end

  def render("409.json", _assigns) do
    %{
      error: "Conflict",
      message: "The request conflicts with the current state of the resource",
      status: 409
    }
  end

  def render("422.json", _assigns) do
    %{
      error: "Unprocessable Entity",
      message: "The request was well-formed but contains invalid parameters",
      status: 422
    }
  end

  def render("500.json", _assigns) do
    %{
      error: "Internal Server Error",
      message: "An unexpected error occurred on the server",
      status: 500
    }
  end

  # Default error response for other status codes
  def render(template, _assigns) do
    status = template |> String.replace(".json", "") |> String.to_integer()

    %{
      error: Phoenix.Controller.status_message_from_template(template),
      message: "An error occurred while processing your request",
      status: status
    }
  end
end
