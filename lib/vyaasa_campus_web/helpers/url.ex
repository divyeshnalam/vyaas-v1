defmodule VyaasaCampusWeb.Helpers.Url do
  @moduledoc """
  Helpers for rendering user/resume-supplied URLs safely.
  """

  @doc """
  Force a user-supplied URL to be an ABSOLUTE href.

  Resume-extracted links are often scheme-less ("www.linkedin.com/...",
  "linkedin.com/in/x"). Rendered in an `<a href>` without a scheme the browser
  treats them as RELATIVE and prepends our own origin, turning a profile link
  into a dead in-app URL. This prepends `https://` when no scheme is present,
  leaving existing schemes (http/https/mailto/etc.) and blank values untouched.
  """
  def absolute(nil), do: nil

  def absolute(url) when is_binary(url) do
    case String.trim(url) do
      "" ->
        url

      trimmed ->
        if Regex.match?(~r{^[a-z][a-z0-9+.-]*://}i, trimmed) or
             String.starts_with?(trimmed, "mailto:") do
          trimmed
        else
          "https://" <> trimmed
        end
    end
  end

  def absolute(url), do: url
end
