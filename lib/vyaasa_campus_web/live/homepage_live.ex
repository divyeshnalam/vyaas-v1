defmodule VyaasaCampusWeb.HomepageLive do
  @moduledoc """
  Homepage LiveView for institution selection.

  Allows users to search and select their institution to proceed to authentication.
  """

  use VyaasaCampusWeb, :live_view
  alias VyaasaCampus.Contexts.Tenants

  # Import UI components
  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search_query, "")
     |> assign(:tenants, [])
     |> assign(:show_results, false)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("search", params, socket) do
    # Handle form submission with query parameter
    query =
      case params do
        %{"query" => q} -> q
        _ -> ""
      end

    search_query = String.trim(query)

    socket =
      if String.length(search_query) >= 3 do
        socket
        |> assign(:loading, true)
        |> assign(:search_query, search_query)
        |> search_tenants(search_query)
      else
        socket
        |> assign(:search_query, search_query)
        |> assign(:tenants, [])
        |> assign(:show_results, false)
        |> assign(:loading, false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_tenant", %{"tenant_alias" => tenant_alias}, socket) do
    # Navigate directly to tenant login page
    {:noreply, push_navigate(socket, to: ~p"/auth/tenant/#{tenant_alias}/login")}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:tenants, [])
     |> assign(:show_results, false)
     |> assign(:loading, false)}
  end

  defp search_tenants(socket, query) do
    # Search tenants by full_name, short_name, or alias
    tenants =
      Tenants.list_active_tenants()
      |> Enum.filter(fn tenant ->
        String.contains?(String.downcase(tenant.full_name || ""), String.downcase(query)) or
          String.contains?(String.downcase(tenant.short_name || ""), String.downcase(query)) or
          String.contains?(String.downcase(tenant.alias || ""), String.downcase(query))
      end)
      # Limit to 10 results
      |> Enum.take(10)

    socket
    |> assign(:tenants, tenants)
    |> assign(:show_results, true)
    |> assign(:loading, false)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center justify-center px-4 sm:px-6 lg:px-8 mt-10">
        <div class="w-full space-y-8">
          <!-- Logo and Header -->
          <div class="text-center">
            <div class="flex items-center justify-center mb-6">
              <!-- Vyaasa Logo -->
              <img src="/images/logo.png" alt="Vyaasa Logo" class="w-40 h-40" />
            </div>

            <h1 class="text-4xl font-bold text-gray-900 mb-2">
              VYAASA CAMPUS
            </h1>
            <p class="text-lg text-gray-600">
              Select your institution to continue
            </p>
          </div>

          <!-- Institution Search Form -->
          <div class="bg-white rounded-xl shadow-lg p-8 max-w-md mx-auto">
            <div class="space-y-4">
              <label for="institution-search" class="block text-sm font-medium text-gray-700">
                Select your institution
              </label>

              <form phx-change="search">
                <div class="relative">
                  <input
                    id="institution-search"
                    name="query"
                    type="text"
                    value={@search_query}
                    placeholder="Type at least 3 characters to search..."
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-orange-500 text-lg"
                    autocomplete="off"
                  />

                  <%= if @search_query != "" do %>
                    <button
                      type="button"
                      phx-click="clear_search"
                      class="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
                    >
                      <.icon name="hero-x-mark" class="w-5 h-5" />
                    </button>
                  <% end %>
                </div>
              </form>

                <!-- Validation Message -->
                <%= if @search_query != "" and String.length(@search_query) < 3 do %>
                  <p class="text-sm text-red-600">
                    Please enter 3 or more characters
                  </p>
                <% end %>

                <!-- Loading Indicator -->
                <%= if @loading do %>
                  <div class="flex items-center justify-center py-4">
                    <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-orange-500"></div>
                    <span class="ml-2 text-gray-600">Searching...</span>
                  </div>
                <% end %>

                <!-- Search Results -->
                <%= if @show_results and @tenants != [] do %>
                  <div class="space-y-2 max-h-60 overflow-y-auto">
                    <%= for tenant <- @tenants do %>
                      <button
                        type="button"
                        phx-click="select_tenant"
                        phx-value-tenant_alias={tenant.alias}
                        class="w-full text-left p-3 rounded-lg border border-gray-200 hover:border-orange-300 hover:bg-orange-50 transition-colors"
                      >
                        <div class="flex items-center space-x-3">
                          <%= if tenant.logo_url do %>
                            <img src={tenant.logo_url} alt={tenant.full_name} class="w-8 h-8 rounded-full object-cover" />
                          <% else %>
                            <div class="w-8 h-8 bg-gray-200 rounded-full flex items-center justify-center">
                              <span class="text-gray-600 font-semibold text-sm">
                                <%= String.first(tenant.short_name || tenant.full_name) %>
                              </span>
                            </div>
                          <% end %>

                          <div class="flex-1 min-w-0">
                            <p class="text-sm font-medium text-gray-900 truncate">
                              {tenant.full_name}
                            </p>
                            <%= if tenant.short_name != tenant.full_name do %>
                              <p class="text-xs text-gray-500 truncate">
                                {tenant.short_name}
                              </p>
                            <% end %>
                          </div>
                        </div>
                      </button>
                    <% end %>
                  </div>
                <% end %>

                <!-- No Results -->
                <%= if @show_results and @tenants == [] and not @loading do %>
                  <div class="text-center py-8">
                    <div class="text-gray-400 mb-2">
                      <.icon name="hero-magnifying-glass" class="w-12 h-12 mx-auto" />
                    </div>
                    <p class="text-gray-600">No institutions found</p>
                    <p class="text-sm text-gray-500">Try a different search term</p>
                  </div>
                <% end %>
            </div>
          </div>

          <!-- Footer -->
          <div class="text-center">
            <p class="text-sm text-gray-500">
              Powered by <span class="font-semibold text-orange-500">Vyaasa</span> • Beamx Tech Labs
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
