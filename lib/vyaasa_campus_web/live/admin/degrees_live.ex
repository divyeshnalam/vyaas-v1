defmodule VyaasaCampusWeb.Admin.DegreesLive do
  @moduledoc """
  Super admin LiveView for managing degrees and specializations.
  These are global and shared across all tenants.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Academics

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Admin.SuperAdminShell

  @impl true
  def mount(_params, _session, socket) do
    degrees = Academics.list_degrees()

    {:ok,
     socket
     |> assign(:page_title, "Degrees & Specializations")
     |> assign(:user_info, user_info(socket.assigns[:current_user]))
     |> assign(:degrees, degrees)
     |> assign(:show_degree_form, false)
     |> assign(:show_spec_form, false)
     |> assign(:selected_degree, nil)
     |> assign(:degree_form, to_form(%{}, as: :degree))
     |> assign(:spec_form, to_form(%{}, as: :spec))
     |> assign(:editing_degree, nil)
     |> assign(:editing_spec, nil)}
  end

  # --- Degree events ---

  @impl true
  def handle_event("show_degree_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_degree_form, true)
     |> assign(:editing_degree, nil)
     |> assign(:degree_form, to_form(%{}, as: :degree))}
  end

  def handle_event("close_degree_form", _params, socket) do
    {:noreply, assign(socket, :show_degree_form, false)}
  end

  def handle_event("save_degree", %{"degree" => params}, socket) do
    case socket.assigns.editing_degree do
      nil ->
        case Academics.create_degree(params) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:degrees, Academics.list_degrees())
             |> assign(:show_degree_form, false)
             |> put_flash(:info, "Degree created!")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, format_errors(changeset))}
        end

      degree ->
        case Academics.update_degree(degree, params) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:degrees, Academics.list_degrees())
             |> assign(:show_degree_form, false)
             |> assign(:editing_degree, nil)
             |> put_flash(:info, "Degree updated!")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, format_errors(changeset))}
        end
    end
  end

  def handle_event("edit_degree", %{"id" => id}, socket) do
    degree = Academics.get_degree!(id)

    {:noreply,
     socket
     |> assign(:show_degree_form, true)
     |> assign(:editing_degree, degree)
     |> assign(:degree_form, to_form(%{"name" => degree.name, "code" => degree.code}, as: :degree))}
  end

  def handle_event("delete_degree", %{"id" => id}, socket) do
    degree = Academics.get_degree!(id)

    case Academics.delete_degree(degree) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:degrees, Academics.list_degrees())
         |> assign(:selected_degree, nil)
         |> put_flash(:info, "Degree deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete degree.")}
    end
  end

  # --- Specialization events ---

  def handle_event("select_degree", %{"id" => id}, socket) do
    degree = Academics.get_degree!(id) |> VyaasaCampus.Repo.preload(:specializations, prefix: "public")
    {:noreply, assign(socket, :selected_degree, degree)}
  end

  def handle_event("show_spec_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_spec_form, true)
     |> assign(:editing_spec, nil)
     |> assign(:spec_form, to_form(%{}, as: :spec))}
  end

  def handle_event("close_spec_form", _params, socket) do
    {:noreply, assign(socket, :show_spec_form, false)}
  end

  def handle_event("save_spec", %{"spec" => params}, socket) do
    degree = socket.assigns.selected_degree
    params = Map.put(params, "degree_id", degree.id)

    case socket.assigns.editing_spec do
      nil ->
        case Academics.create_specialization(params) do
          {:ok, _} ->
            updated_degree = Academics.get_degree!(degree.id) |> VyaasaCampus.Repo.preload(:specializations, prefix: "public")

            {:noreply,
             socket
             |> assign(:selected_degree, updated_degree)
             |> assign(:degrees, Academics.list_degrees())
             |> assign(:show_spec_form, false)
             |> put_flash(:info, "Specialization created!")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, format_errors(changeset))}
        end

      spec ->
        case Academics.update_specialization(spec, params) do
          {:ok, _} ->
            updated_degree = Academics.get_degree!(degree.id) |> VyaasaCampus.Repo.preload(:specializations, prefix: "public")

            {:noreply,
             socket
             |> assign(:selected_degree, updated_degree)
             |> assign(:degrees, Academics.list_degrees())
             |> assign(:show_spec_form, false)
             |> assign(:editing_spec, nil)
             |> put_flash(:info, "Specialization updated!")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, format_errors(changeset))}
        end
    end
  end

  def handle_event("edit_spec", %{"id" => id}, socket) do
    spec = Academics.get_specialization!(id)

    {:noreply,
     socket
     |> assign(:show_spec_form, true)
     |> assign(:editing_spec, spec)
     |> assign(:spec_form, to_form(%{"name" => spec.name, "code" => spec.code}, as: :spec))}
  end

  def handle_event("delete_spec", %{"id" => id}, socket) do
    spec = Academics.get_specialization!(id)
    degree = socket.assigns.selected_degree

    case Academics.delete_specialization(spec) do
      {:ok, _} ->
        updated_degree = Academics.get_degree!(degree.id) |> VyaasaCampus.Repo.preload(:specializations, prefix: "public")

        {:noreply,
         socket
         |> assign(:selected_degree, updated_degree)
         |> assign(:degrees, Academics.list_degrees())
         |> put_flash(:info, "Specialization deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete.")}
    end
  end

  defp user_info(nil), do: %{name: "Super Admin", role: "Platform Admin"}

  defp user_info(u),
    do: %{name: String.trim("#{u.first_name} #{u.last_name}"), role: "Platform Admin", email: u.email}

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={:super_admin}>
      <.admin_layout user_info={@user_info} current_section="degrees">
        <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-[1400px] mx-auto w-full">
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <!-- Degrees Panel -->
              <div class="bg-white rounded-xl shadow-sm border border-gray-200">
                <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
                  <h2 class="text-base font-semibold text-gray-900">Degrees</h2>
                  <button
                    phx-click="show_degree_form"
                    class="inline-flex items-center px-3 py-1.5 bg-orange-500 hover:bg-orange-600 text-white text-sm font-medium rounded-lg"
                  >
                    <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add
                  </button>
                </div>

                <!-- Inline Degree Form -->
                <%= if @show_degree_form do %>
                  <div class="px-6 py-4 bg-orange-50 border-b border-orange-200">
                    <.form for={@degree_form} phx-submit="save_degree" class="flex items-end gap-3">
                      <div class="flex-1">
                        <.input field={@degree_form[:name]} type="text" label="Degree Name" placeholder="e.g. B.Tech" required class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500" />
                      </div>
                      <div class="w-32">
                        <.input field={@degree_form[:code]} type="text" label="Code" placeholder="e.g. BTECH" required class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500" />
                      </div>
                      <div class="flex gap-2 pb-1">
                        <button type="submit" class="px-3 py-2 bg-orange-500 text-white text-sm rounded-lg hover:bg-orange-600">
                          {if @editing_degree, do: "Update", else: "Add"}
                        </button>
                        <button type="button" phx-click="close_degree_form" class="px-3 py-2 bg-gray-200 text-gray-700 text-sm rounded-lg hover:bg-gray-300">
                          Cancel
                        </button>
                      </div>
                    </.form>
                  </div>
                <% end %>

                <div class="divide-y divide-gray-100 max-h-[500px] overflow-y-auto">
                  <%= if Enum.empty?(@degrees) do %>
                    <div class="px-6 py-8 text-center text-sm text-gray-500">
                      No degrees yet. Add your first degree.
                    </div>
                  <% else %>
                    <%= for degree <- @degrees do %>
                      <div
                        class={[
                          "px-6 py-3 flex items-center justify-between cursor-pointer hover:bg-gray-50 transition-colors",
                          @selected_degree && @selected_degree.id == degree.id && "bg-orange-50 border-l-4 border-orange-500"
                        ]}
                        phx-click="select_degree"
                        phx-value-id={degree.id}
                      >
                        <div>
                          <p class="text-sm font-medium text-gray-900">{degree.name}</p>
                          <p class="text-xs text-gray-500">
                            <code class="bg-gray-100 px-1.5 py-0.5 rounded">{degree.code}</code>
                            <span class="ml-2">{length(degree.specializations)} specialization(s)</span>
                          </p>
                        </div>
                        <div class="flex items-center gap-2">
                          <button phx-click="edit_degree" phx-value-id={degree.id} class="text-gray-400 hover:text-blue-600">
                            <.icon name="hero-pencil-square" class="h-4 w-4" />
                          </button>
                          <button phx-click="delete_degree" phx-value-id={degree.id} data-confirm="Delete this degree and all its specializations?" class="text-gray-400 hover:text-red-600">
                            <.icon name="hero-trash" class="h-4 w-4" />
                          </button>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>

              <!-- Specializations Panel -->
              <div class="bg-white rounded-xl shadow-sm border border-gray-200">
                <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
                  <h2 class="text-base font-semibold text-gray-900">
                    <%= if @selected_degree do %>
                      Specializations - {@selected_degree.name}
                    <% else %>
                      Specializations
                    <% end %>
                  </h2>
                  <%= if @selected_degree do %>
                    <button
                      phx-click="show_spec_form"
                      class="inline-flex items-center px-3 py-1.5 bg-blue-500 hover:bg-blue-600 text-white text-sm font-medium rounded-lg"
                    >
                      <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add
                    </button>
                  <% end %>
                </div>

                <!-- Inline Spec Form -->
                <%= if @show_spec_form && @selected_degree do %>
                  <div class="px-6 py-4 bg-blue-50 border-b border-blue-200">
                    <.form for={@spec_form} phx-submit="save_spec" class="flex items-end gap-3">
                      <div class="flex-1">
                        <.input field={@spec_form[:name]} type="text" label="Specialization Name" placeholder="e.g. Computer Science" required class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-blue-500" />
                      </div>
                      <div class="w-32">
                        <.input field={@spec_form[:code]} type="text" label="Code" placeholder="e.g. CSE" required class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-blue-500" />
                      </div>
                      <div class="flex gap-2 pb-1">
                        <button type="submit" class="px-3 py-2 bg-blue-500 text-white text-sm rounded-lg hover:bg-blue-600">
                          {if @editing_spec, do: "Update", else: "Add"}
                        </button>
                        <button type="button" phx-click="close_spec_form" class="px-3 py-2 bg-gray-200 text-gray-700 text-sm rounded-lg hover:bg-gray-300">
                          Cancel
                        </button>
                      </div>
                    </.form>
                  </div>
                <% end %>

                <div class="divide-y divide-gray-100 max-h-[500px] overflow-y-auto">
                  <%= if is_nil(@selected_degree) do %>
                    <div class="px-6 py-12 text-center">
                      <.icon name="hero-academic-cap" class="h-12 w-12 text-gray-300 mx-auto mb-3" />
                      <p class="text-sm text-gray-500">Select a degree to manage its specializations.</p>
                    </div>
                  <% else %>
                    <%= if Enum.empty?(@selected_degree.specializations) do %>
                      <div class="px-6 py-8 text-center text-sm text-gray-500">
                        No specializations yet for {@selected_degree.name}.
                      </div>
                    <% else %>
                      <%= for spec <- @selected_degree.specializations do %>
                        <div class="px-6 py-3 flex items-center justify-between hover:bg-gray-50">
                          <div>
                            <p class="text-sm font-medium text-gray-900">{spec.name}</p>
                            <code class="text-xs bg-gray-100 px-1.5 py-0.5 rounded text-gray-500">{spec.code}</code>
                          </div>
                          <div class="flex items-center gap-2">
                            <button phx-click="edit_spec" phx-value-id={spec.id} class="text-gray-400 hover:text-blue-600">
                              <.icon name="hero-pencil-square" class="h-4 w-4" />
                            </button>
                            <button phx-click="delete_spec" phx-value-id={spec.id} data-confirm="Delete this specialization?" class="text-gray-400 hover:text-red-600">
                              <.icon name="hero-trash" class="h-4 w-4" />
                            </button>
                          </div>
                        </div>
                      <% end %>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
        </div>
      </.admin_layout>
    </Layouts.app>
    """
  end
end
