defmodule VyaasaCampusWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use VyaasaCampusWeb, :html

  embed_templates "error_html/*"

  # Fallback for any status without a matching template (e.g. "410.html").
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
