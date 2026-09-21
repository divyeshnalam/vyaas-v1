defmodule VyaasaCampusWeb.Components.Shared.HeaderComponent do
  @moduledoc """
  Header component for tenant dashboard.
  Displays user profile, notifications, and main navigation.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI
  alias Phoenix.LiveView.JS

  def header(assigns) do
    ~H"""
    <div class="bg-white shadow-sm border-b border-gray-200">
      <div class="px-4 lg:px-6 py-4">
        <div class="flex justify-between items-center">
          <!-- Mobile Menu Button + Page Title -->
          <div class="flex items-center">
            <!-- Mobile Menu Button -->
            <button
              class="lg:hidden p-2 rounded-md text-gray-400 hover:text-gray-500 hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-orange-500 mr-3"
              phx-click={JS.show(to: "#mobile-sidebar-backdrop") |> JS.remove_class("-translate-x-full", to: "#mobile-sidebar") |> JS.add_class("translate-x-0", to: "#mobile-sidebar")}
            >
              <.icon name="hero-bars-3" class="w-6 h-6" />
              <span class="sr-only">Open sidebar</span>
            </button>

            <!-- Page Title -->
            <div>
              <h1 class="text-xl lg:text-2xl font-semibold text-gray-900">{@page_title || "Dashboard"}</h1>
              <p class="text-sm text-gray-600 mt-1 hidden sm:block">Welcome back, <%= @user_info.name || "User" %>!</p>
            </div>
          </div>

          <!-- User Profile Dropdown -->
          <div class="relative">
            <button
              class="flex items-center space-x-3 p-2 rounded-lg hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-orange-500 transition-colors"
              phx-click={JS.toggle(to: "#user-dropdown")}
            >
              <div class="w-10 h-10 bg-gradient-to-br from-orange-400 to-orange-600 rounded-full flex items-center justify-center shadow-sm">
                <span class="text-white font-semibold text-sm">
                  <%= String.first(@user_info.name || "U") %>
                </span>
              </div>
              <div class="text-left">
                <p class="text-sm font-medium text-gray-900"><%= @user_info.name || "User" %></p>
                <p class="text-xs text-gray-500"><%= @user_info.role || "Role" %></p>
              </div>
              <.icon name="hero-chevron-down" class="w-4 h-4 text-gray-400" />
            </button>

            <!-- Dropdown Menu -->
            <div id="user-dropdown" class="hidden absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg py-1 z-50 border border-gray-200">
              <button
                phx-click="logout"
                class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="w-4 h-4 inline mr-2" />
                Logout
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
