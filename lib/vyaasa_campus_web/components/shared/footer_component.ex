defmodule VyaasaCampusWeb.Components.Shared.FooterComponent do
  @moduledoc """
  Footer component for tenant dashboard.
  Displays copyright and additional information.
  """

  use Phoenix.Component

  def footer(assigns) do
    ~H"""
    <footer class="bg-white border-t border-gray-100 mt-auto">
      <div class="max-w-4xl mx-auto px-4 sm:px-6 py-4 text-center">
        <p class="text-[11px] text-gray-400">
          Copyrights © {Date.utc_today().year} BeamX. All Rights Reserved. Designed &amp; Developed by Vyaasa.com
        </p>
      </div>
    </footer>
    """
  end
end
