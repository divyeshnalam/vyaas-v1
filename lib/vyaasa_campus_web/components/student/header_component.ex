defmodule VyaasaCampusWeb.Components.Student.HeaderComponent do
  @moduledoc """
  Header component for student dashboard.
  Displays the user profile dropdown (with change password) and a mobile menu button.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI
  alias Phoenix.LiveView.JS

  attr :user_info, :map, required: true
  # Required for the Profile and Change Password links — every caller must pass it.
  attr :tenant_alias, :string, required: true
  attr :page_title, :string, default: "Dashboard"
  # When set (assessment pages), an "Exit" button appears in focus mode — i.e.
  # exactly when the side-nav is hidden — so the student is never left without a
  # way out. Confirms before leaving so an exam isn't abandoned by accident.
  attr :exit_href, :string, default: nil
  # Server-driven focus mode: when true the Exit button is shown unconditionally
  # (no dependency on the JS body.assessment-focus class). Left false, the button
  # falls back to the CSS-gated `.assessment-exit` behaviour used elsewhere.
  attr :focus?, :boolean, default: false

  def header(assigns) do
    ~H"""
    <header class="bg-white relative z-10" style="box-shadow: 0 2px 6px rgba(80,50,10,0.06);">
      <div class="px-4 lg:px-8 py-7">
        <div class="flex items-center gap-3">
          <!-- Mobile Menu Button -->
          <button
            class="lg:hidden p-2 rounded-md text-gray-500 hover:text-gray-700 hover:bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            phx-click={
              JS.show(to: "#mobile-sidebar-backdrop")
              |> JS.remove_class("-translate-x-full", to: "#mobile-sidebar")
              |> JS.add_class("translate-x-0", to: "#mobile-sidebar")
            }
          >
            <.icon name="hero-bars-3" class="w-6 h-6" />
            <span class="sr-only">Open sidebar</span>
          </button>

          <!-- Exit assessment — shown in focus mode (side-nav hidden). focus?
               forces it visible server-side; otherwise it's CSS-gated on body.assessment-focus. -->
          <.link
            :if={@exit_href}
            navigate={@exit_href}
            data-confirm="Leave the assessment? Your progress won't be submitted."
            class={[
              "items-center gap-1.5 px-3 py-2 rounded-lg text-sm font-medium text-gray-600 bg-white border border-gray-200 hover:bg-gray-50",
              if(@focus?, do: "inline-flex", else: "assessment-exit")
            ]}
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Exit
          </.link>

          <div class="flex-1"></div>

          <!-- User Profile Dropdown -->
          <div class="relative" phx-click-away={JS.hide(to: "#user-dropdown")}>
            <button
              class="flex items-center gap-2.5 rounded-full hover:bg-white pr-2 transition"
              phx-click={JS.toggle(to: "#user-dropdown")}
            >
              <div
                :if={avatar_url(@user_info)}
                class="w-9 h-9 rounded-full shadow-sm shrink-0 overflow-hidden"
              >
                <img src={avatar_url(@user_info)} alt={@user_info.name} class="w-full h-full object-cover" />
              </div>
              <div
                :if={!avatar_url(@user_info)}
                class="w-9 h-9 rounded-full flex items-center justify-center shadow-sm shrink-0"
                style="background-color: #FF8B00;"
              >
                <span class="text-white font-bold text-sm">
                  {initials(@user_info.name)}
                </span>
              </div>
              <.icon name="hero-chevron-down" class="w-5 h-5 text-gray-500" />
            </button>

            <div
              id="user-dropdown"
              class="hidden absolute right-0 mt-2 w-56 bg-white rounded-xl shadow-lg py-2 z-50 border border-gray-100"
            >
              <.link
                navigate={"/student/#{@tenant_alias}/profile"}
                class="flex items-center gap-2 w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
              >
                <.icon name="hero-user-circle" class="w-4 h-4" />
                Your Profile
              </.link>
              <.link
                navigate={"/student/#{@tenant_alias}/change-password"}
                class="flex items-center gap-2 w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
              >
                <.icon name="hero-key" class="w-4 h-4" />
                Change Password
              </.link>
            </div>
          </div>
        </div>
      </div>
    </header>
    """
  end

  defp avatar_url(user_info) do
    case Map.get(user_info, :profile_picture_url) do
      url when is_binary(url) and url != "" -> url
      _ -> nil
    end
  end

  defp initials(nil), do: "S"

  defp initials(name) when is_binary(name) do
    name
    |> String.split(" ", trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
    |> case do
      "" -> "S"
      s -> s
    end
  end

  defp initials(_), do: "S"
end
