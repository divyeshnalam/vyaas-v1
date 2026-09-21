defmodule VyaasaCampusWeb.Admin.AI8ConfigLive do
  @moduledoc """
  Super-admin screen to configure the AI8 evaluation matrix: which of the 8 skill
  dimensions each of the 8 modules evaluates. Global config (`ai8_module_dimensions`).
  Toggling a cell enables/disables that dimension for that module — it drives the
  per-module LLM rubric, the dashboard pills, and score aggregation.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.AI8.{Dimensions, Modules}

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Admin.SuperAdminShell

  @impl true
  def mount(_params, _session, socket) do
    AI8.ensure_seeded()
    AI8.ensure_global_seeded()

    {:ok,
     socket
     |> assign(:page_title, "AI8 Evaluation Config")
     |> assign(:modules, Modules.all())
     |> assign(:dimensions, Dimensions.all())
     |> assign(:matrix, AI8.config_matrix())
     |> assign(:global, global_map())
     |> assign(:user_info, user_info(socket.assigns[:current_user]))}
  end

  defp user_info(nil), do: %{name: "Super Admin", email: nil, role: "Platform Admin"}

  defp user_info(u),
    do: %{
      name: String.trim("#{u.first_name} #{u.last_name}"),
      email: u.email,
      role: "Platform Admin"
    }

  defp global_map do
    AI8.list_global_weights() |> Map.new(fn r -> {r.dimension, r} end)
  end

  @impl true
  def handle_event("set_weight", %{"module" => module, "dimension" => dimension, "value" => value}, socket) do
    {:ok, _} = AI8.set_weight(module, dimension, parse_pct(value))

    {:noreply, assign(socket, :matrix, AI8.config_matrix())}
  end

  @impl true
  def handle_event("set_global_weight", %{"dimension" => dimension, "value" => value}, socket) do
    {:ok, _} = AI8.set_global_weight(dimension, parse_pct(value))

    {:noreply, assign(socket, :global, global_map())}
  end

  defp global_weight_val(global, dimension) do
    case Map.get(global, to_string(dimension)) do
      %{weight: %Decimal{} = w} -> w |> Decimal.to_float() |> fmt_num()
      _ -> ""
    end
  end

  defp global_total(global) do
    global
    |> Map.values()
    |> Enum.reduce(0.0, fn
      %{weight: %Decimal{} = w}, acc -> acc + Decimal.to_float(w)
      _, acc -> acc
    end)
  end

  # Percentage entered in a cell. >0 enables + sets weight; blank/0/invalid clears it.
  defp parse_pct(value) do
    case Float.parse(String.trim(to_string(value))) do
      {n, _} when n > 0 -> n |> min(100.0) |> Float.round(2)
      _ -> nil
    end
  end

  # Current weight for a cell as a display string ("" when unset).
  defp weight_val(matrix, module, dimension) do
    case get_in(matrix, [to_string(module), to_string(dimension)]) do
      %{weight: %Decimal{} = w} -> w |> Decimal.to_float() |> fmt_num()
      _ -> ""
    end
  end

  # Sum of a module's configured weights (for the 100% check).
  defp module_total(matrix, module) do
    matrix
    |> Map.get(to_string(module), %{})
    |> Map.values()
    |> Enum.reduce(0.0, fn
      %{weight: %Decimal{} = w}, acc -> acc + Decimal.to_float(w)
      _, acc -> acc
    end)
  end

  defp fmt_num(f) do
    if f == Float.round(f), do: Integer.to_string(trunc(f)), else: Float.to_string(f)
  end

  defp total_class(0.0), do: "text-gray-400"
  defp total_class(100.0), do: "text-green-600"
  defp total_class(_), do: "text-amber-600"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={:super_admin}>
      <.admin_layout user_info={@user_info} current_section="ai8">
        <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-[1400px] mx-auto w-full">
          <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-5 mb-6">
              <h2 class="text-base font-bold text-gray-900 mb-1">Module × Skill-Dimension Weights</h2>
              <p class="text-sm text-gray-500">
                Set the <span class="font-semibold">percentage</span> each skill dimension
                contributes to a module's score (e.g. Interview → Domain 50, Leadership 30).
                A value &gt; 0 enables that dimension for the module — only enabled dimensions
                are requested from the LLM, shown as dashboard pills, and included in scoring.
                Each module's weights should add up to <span class="font-semibold">100%</span>.
                This config is global (applies to all tenants).
              </p>
            </div>

            <!-- Global dimension weights → the overall AI8 Index -->
            <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-5 mb-6">
              <div class="flex items-center justify-between mb-1">
                <h2 class="text-base font-bold text-gray-900">Overall AI8 Index Weights</h2>
                <span class={["text-sm font-bold", total_class(global_total(@global))]}>
                  Total: {fmt_num(global_total(@global))}%
                </span>
              </div>
              <p class="text-sm text-gray-500 mb-4">
                How much each skill dimension counts toward a student's overall
                <span class="font-semibold">AI8 Index</span> (the assessment index shown on the
                AI8 Overview). Percentages should add up to <span class="font-semibold">100%</span>.
              </p>
              <div class="flex flex-wrap gap-4">
                <div :for={{dkey, label} <- @dimensions} class="flex flex-col items-start">
                  <label class="text-xs text-gray-500 mb-1" title={label}>{Dimensions.short_label(dkey)}</label>
                  <div class="flex items-center gap-1">
                    <input
                      type="number"
                      min="0"
                      max="100"
                      step="1"
                      inputmode="numeric"
                      class="w-20 px-2 py-1.5 text-center text-sm border border-gray-200 rounded-lg focus:ring-orange-500 focus:border-orange-500"
                      value={global_weight_val(@global, dkey)}
                      placeholder="—"
                      phx-blur="set_global_weight"
                      phx-value-dimension={dkey}
                    />
                    <span class="text-xs text-gray-400">%</span>
                  </div>
                </div>
              </div>
            </div>

            <div class="bg-white rounded-xl shadow-sm border border-gray-200 overflow-x-auto">
              <table class="min-w-full text-sm">
                <thead>
                  <tr class="border-b border-gray-200 bg-gray-50">
                    <th class="text-left font-semibold text-gray-700 px-4 py-3 sticky left-0 bg-gray-50">
                      Module
                    </th>
                    <th
                      :for={{dkey, label} <- @dimensions}
                      class="px-3 py-3 text-center font-semibold text-gray-600"
                      title={label}
                    >
                      {Dimensions.short_label(dkey)}
                    </th>
                    <th class="px-3 py-3 text-center font-semibold text-gray-500">Total</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={{mkey, mname} <- @modules} class="border-b border-gray-100 hover:bg-orange-50/40">
                    <td class="px-4 py-3 font-medium text-gray-900 whitespace-nowrap sticky left-0 bg-white">
                      {mname}
                    </td>
                    <td :for={{dkey, _label} <- @dimensions} class="px-3 py-3 text-center">
                      <input
                        type="number"
                        min="0"
                        max="100"
                        step="1"
                        inputmode="numeric"
                        class="w-16 px-1.5 py-1 text-center text-sm border border-gray-200 rounded-lg focus:ring-orange-500 focus:border-orange-500"
                        value={weight_val(@matrix, mkey, dkey)}
                        placeholder="—"
                        phx-blur="set_weight"
                        phx-value-module={mkey}
                        phx-value-dimension={dkey}
                      />
                    </td>
                    <td class={["px-3 py-3 text-center text-sm font-bold", total_class(module_total(@matrix, to_string(mkey)))]}>
                      {fmt_num(module_total(@matrix, to_string(mkey)))}%
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <p class="text-xs text-gray-400 mt-3">
              A module's score is the weighted average of its dimension scores using these
              percentages. If a module has enabled dimensions with no weights set, they are
              treated equally until you assign percentages.
            </p>
        </div>
      </.admin_layout>
    </Layouts.app>
    """
  end
end
