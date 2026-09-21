defmodule VyaasaCampusWeb.Admin.CollegeConfigLive do
  @moduledoc """
  Super-admin configuration for **one college**, reached from the Colleges list
  (`/admin/colleges/:id/config`).

  Two tabs:

    * **Assessments** — MCQ settings (question count, aptitude/technical split,
      difficulty distribution, duration, negative marking, passing percentage).
    * **Limits & Attempts** — how many attempts each assessment allows, plus the
      subscription period those allowances reset on.

  These were once two separate menu items, each with its own college picker.
  Now the college comes from the URL, so there is no picker at all and Colleges
  is the single entry point. Subscription plans become a third tab here rather
  than another menu entry.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Contexts.AssessmentConfigs
  alias VyaasaCampus.Contexts.Assessments
  alias VyaasaCampus.Contexts.Entitlements

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Admin.SuperAdminShell

  @impl true
  def mount(%{"id" => tenant_id}, _session, socket) do
    tenant = Tenants.get_tenant!(tenant_id)
    config = AssessmentConfigs.get_or_default_config_for_tenant(tenant.id)
    configs = AssessmentConfigs.list_configs()
    config_map = Map.new(configs, fn c -> {c.tenant_id, c} end)

    current_user = socket.assigns[:current_user]

    user_info =
      case current_user do
        nil ->
          %{name: "Super Admin", email: nil, role: "Platform Admin"}

        u ->
          name = String.trim("#{u.first_name} #{u.last_name}")
          name = if name == "", do: "Super Admin", else: name
          %{name: name, email: u.email, role: "Platform Admin"}
      end

    socket =
      socket
      |> assign(:page_title, "#{tenant.short_name} · Config")
      |> assign(:user_info, user_info)
      |> assign(:config_map, config_map)
      |> assign(:selected_tenant, tenant)
      |> assign(:config, config)
      |> assign(:config_form, build_config_form(config))
      |> assign(:config_saving?, false)
      |> assign(:assessments, safe_list_assessments(tenant))
      |> assign(:save_success, false)
      |> assign(:tab, "assessments")
      |> assign(:limits, load_limits(tenant.id))
      |> assign(:subscription, Entitlements.get_subscription(tenant.id))
      |> assign(:limits_saved?, false)

    {:ok, socket}
  end

  # A college whose schema hasn't been provisioned yet shouldn't 500 the config
  # page — show it with an empty assessments list instead.
  defp safe_list_assessments(tenant) do
    Assessments.list_assessments(tenant.schema_name)
  rescue
    _ -> []
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, socket |> assign(:tab, tab) |> assign(:limits_saved?, false)}
  end

  @impl true
  def handle_event("save_limits", %{"limits" => params}, socket) do
    tenant = socket.assigns.selected_tenant
    admin = socket.assigns[:current_user]

    Entitlements.put_attempt_limits(tenant.id, params, admin && admin.id)

    {:noreply,
     socket
     |> assign(:limits, load_limits(tenant.id))
     |> assign(:limits_saved?, true)
     |> put_flash(:info, "Attempt limits saved for #{tenant.full_name}.")}
  end

  @impl true
  def handle_event("save_period", %{"period" => params}, socket) do
    tenant = socket.assigns.selected_tenant

    attrs = %{
      "period_start" => parse_dt(params["period_start"]),
      "period_end" => parse_dt(params["period_end"])
    }

    case Entitlements.put_subscription(tenant.id, attrs) do
      {:ok, sub} ->
        {:noreply, socket |> assign(:subscription, sub) |> put_flash(:info, "Subscription period updated.")}

      {:error, changeset} ->
        msg = Enum.map_join(changeset.errors, "; ", fn {f, {m, _}} -> "#{f} #{m}" end)
        {:noreply, put_flash(socket, :error, "Could not save period: #{msg}")}
    end
  end

  @impl true
  def handle_event("clear_period", _params, socket) do
    tenant = socket.assigns.selected_tenant
    {:ok, sub} = Entitlements.put_subscription(tenant.id, %{period_start: nil, period_end: nil})

    {:noreply,
     socket
     |> assign(:subscription, sub)
     |> put_flash(:info, "Period cleared — attempts now count over all time.")}
  end

  @impl true
  def handle_event("validate_config", %{"config" => params}, socket) do
    # Auto-calculate technical_percentage when aptitude changes
    params = auto_calculate_percentages(params)
    {:noreply, assign(socket, :config_form, to_form(params, as: :config))}
  end

  @impl true
  def handle_event("save_config", %{"config" => params}, socket) do
    socket = assign(socket, :config_saving?, true)
    tenant = socket.assigns.selected_tenant
    current_user = socket.assigns.current_user

    params = auto_calculate_percentages(params)

    attrs =
      params
      |> Map.put("created_by", current_user.id)
      |> Map.put("tenant_id", tenant.id)

    case AssessmentConfigs.upsert_config_for_tenant(tenant.id, attrs) do
      {:ok, config} ->
        configs = AssessmentConfigs.list_configs()
        config_map = Map.new(configs, fn c -> {c.tenant_id, c} end)

        {:noreply,
         socket
         |> assign(:config, config)
         |> assign(:config_form, build_config_form(config))
         |> assign(:config_map, config_map)
         |> assign(:config_saving?, false)
         |> assign(:save_success, true)
         |> put_flash(:info, "Assessment config saved for #{tenant.short_name}!")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
          end)
          |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
          |> Enum.join("; ")

        {:noreply,
         socket
         |> assign(:config_saving?, false)
         |> put_flash(:error, "Validation failed: #{errors}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:config_saving?, false)
         |> put_flash(:error, "Failed to save: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("reset_defaults", _params, socket) do
    defaults = AssessmentConfigs.defaults()
    config = struct(socket.assigns.config, defaults)

    {:noreply,
     socket
     |> assign(:config_form, build_config_form(config))
     |> assign(:save_success, false)}
  end

  # ── Limits helpers ─────────────────────────────────────────────────────────

  defp load_limits(tenant_id) do
    entitlements = Entitlements.map_for_tenant(tenant_id)

    Map.new(["default" | Entitlements.attempt_modules()], fn m ->
      {m, Map.get(entitlements, Entitlements.attempts_key(m))}
    end)
  end

  defp parse_dt(nil), do: nil
  defp parse_dt(""), do: nil

  defp parse_dt(str) do
    case NaiveDateTime.from_iso8601(str <> ":00") do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC") |> DateTime.truncate(:second)
      _ -> nil
    end
  end

  defp dt_value(nil), do: ""
  defp dt_value(dt), do: dt |> DateTime.to_naive() |> NaiveDateTime.to_iso8601() |> String.slice(0, 16)

  @module_labels %{
    "resume" => "Resume re-analysis",
    "mcq" => "MCQ",
    "behavioral" => "Behavioural",
    "psychometric" => "Psychometric",
    "jam" => "JAM",
    "interview" => "AI Interview",
    "case_study" => "Case Study",
    "mini_project" => "Mini Project"
  }

  defp label_for(module), do: Map.get(@module_labels, module, module)

  # What a module resolves to right now, so the admin sees the effect of the
  # default without having to save first.
  defp effective(limits, module) do
    case Map.get(limits, module) do
      nil ->
        case Map.get(limits, "default") do
          nil -> "Unlimited"
          d -> "#{d} (default)"
        end

      0 ->
        "Blocked"

      v ->
        "#{v}"
    end
  end

  defp build_config_form(config) do
    data = %{
      "total_questions" => to_string(config.total_questions),
      "aptitude_percentage" => to_string(config.aptitude_percentage),
      "technical_percentage" => to_string(config.technical_percentage),
      "duration_minutes" => to_string(config.duration_minutes),
      "negative_marking" => to_string(config.negative_marking),
      "easy_percentage" => to_string(config.easy_percentage),
      "medium_percentage" => to_string(config.medium_percentage),
      "hard_percentage" => to_string(config.hard_percentage),
      "passing_percentage" => to_string(config.passing_percentage)
    }

    to_form(data, as: :config)
  end

  defp auto_calculate_percentages(params) do
    apt = parse_int(params["aptitude_percentage"], 40)
    tech = 100 - apt

    easy = parse_int(params["easy_percentage"], 40)
    medium = parse_int(params["medium_percentage"], 40)
    hard = 100 - easy - medium
    hard = max(hard, 0)

    params
    |> Map.put("technical_percentage", to_string(tech))
    |> Map.put("hard_percentage", to_string(hard))
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(val, default) do
    case Integer.parse(to_string(val)) do
      {n, _} -> n
      :error -> default
    end
  end

  defp status_badge_class("draft"), do: "bg-gray-100 text-gray-700"
  defp status_badge_class("published"), do: "bg-blue-100 text-blue-800"
  defp status_badge_class("active"), do: "bg-green-100 text-green-800"
  defp status_badge_class("completed"), do: "bg-purple-100 text-purple-800"
  defp status_badge_class("archived"), do: "bg-amber-100 text-amber-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-600"

  defp has_saved_config?(config_map, tenant_id), do: Map.has_key?(config_map, tenant_id)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={:super_admin}>
      <.admin_layout user_info={@user_info} current_section="colleges">
        <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-[1400px] mx-auto w-full">
          <!-- College header — the college comes from the URL, so no picker -->
            <div class="mb-6">
              <nav class="flex items-center gap-1.5 text-xs text-gray-400 mb-2">
                <.link navigate={~p"/admin/colleges"} class="hover:text-gray-600">Colleges</.link>
                <span>/</span>
                <span class="text-gray-600">{@selected_tenant.short_name}</span>
                <span>/</span>
                <span class="text-gray-600">Config</span>
              </nav>
              <div class="flex items-start justify-between gap-4">
                <div>
                  <h1 class="text-2xl font-bold text-gray-900">{@selected_tenant.full_name}</h1>
                  <p class="text-sm text-gray-500 mt-0.5">
                    Assessment settings, attempt limits and subscription period for this college.
                  </p>
                </div>
                <.link
                  navigate={~p"/admin/colleges"}
                  class="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg text-sm font-semibold text-gray-700 bg-white border border-gray-200 hover:bg-gray-50 transition shrink-0"
                >
                  <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to Colleges
                </.link>
              </div>
            </div>

            <!-- Tabs: both operate on the college chosen above -->
            <div :if={@selected_tenant} class="flex items-center gap-1 mb-5 border-b border-gray-200">
              <button
                :for={{key, label} <- [{"assessments", "Assessments"}, {"limits", "Limits & Attempts"}]}
                phx-click="switch_tab"
                phx-value-tab={key}
                class={[
                  "px-4 py-2.5 text-sm font-semibold border-b-2 -mb-px transition-colors",
                  if(@tab == key,
                    do: "border-orange-500 text-orange-600",
                    else: "border-transparent text-gray-500 hover:text-gray-700")
                ]}
              >
                {label}
              </button>
            </div>

            <%= if @selected_tenant && @tab == "limits" do %>
              <div class="space-y-6 mb-6">
                <!-- Attempt limits -->
                <form phx-submit="save_limits" class="bg-white rounded-xl shadow-sm border border-gray-200">
                  <div class="px-6 py-4 border-b border-gray-200">
                    <h2 class="text-lg font-semibold text-gray-900">
                      Attempt limits — {@selected_tenant.full_name}
                    </h2>
                    <p class="text-sm text-gray-500">
                      Blank inherits the default. 0 blocks the assessment entirely.
                    </p>
                  </div>

                  <div class="p-6 space-y-5">
                    <div class="rounded-lg bg-orange-50 border border-orange-200 p-4">
                      <label class="block text-sm font-semibold text-gray-800 mb-1">
                        Default for every assessment
                      </label>
                      <input
                        type="number"
                        min="0"
                        name="limits[default]"
                        value={Map.get(@limits, "default")}
                        placeholder="Unlimited"
                        class="w-40 rounded-lg border-gray-300 text-sm focus:border-orange-500 focus:ring-orange-500"
                      />
                      <p class="text-xs text-gray-500 mt-1">
                        Leave blank for unlimited — which is how every college behaves until you set this.
                      </p>
                    </div>

                    <div>
                      <h3 class="text-sm font-semibold text-gray-700 mb-3">Per-assessment overrides</h3>
                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div
                          :for={m <- Entitlements.attempt_modules()}
                          class="flex items-center justify-between gap-3 rounded-lg border border-gray-200 px-3 py-2.5"
                        >
                          <div class="min-w-0">
                            <p class="text-sm font-medium text-gray-800 truncate">{label_for(m)}</p>
                            <p class="text-[11px] text-gray-400">Effective: {effective(@limits, m)}</p>
                          </div>
                          <input
                            type="number"
                            min="0"
                            name={"limits[#{m}]"}
                            value={Map.get(@limits, m)}
                            placeholder="—"
                            class="w-20 shrink-0 rounded-lg border-gray-300 text-sm text-center focus:border-orange-500 focus:ring-orange-500"
                          />
                        </div>
                      </div>
                    </div>
                  </div>

                  <div class="px-6 py-4 border-t border-gray-200 flex items-center gap-3">
                    <button type="submit" class="px-4 py-2 rounded-lg text-sm font-semibold text-white bg-orange-500 hover:bg-orange-600">
                      Save limits
                    </button>
                    <span :if={@limits_saved?} class="text-sm text-green-600 font-medium">Saved</span>
                  </div>
                </form>

                <!-- Subscription period -->
                <form phx-submit="save_period" class="bg-white rounded-xl shadow-sm border border-gray-200">
                  <div class="px-6 py-4 border-b border-gray-200">
                    <h2 class="text-lg font-semibold text-gray-900">Subscription period</h2>
                    <p class="text-sm text-gray-500">
                      Attempts are counted inside this window. Leave both blank to count over all time.
                    </p>
                  </div>

                  <div class="p-6 grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Period start</label>
                      <input
                        type="datetime-local"
                        name="period[period_start]"
                        value={dt_value(@subscription && @subscription.period_start)}
                        class="w-full rounded-lg border-gray-300 text-sm focus:border-orange-500 focus:ring-orange-500"
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Period end</label>
                      <input
                        type="datetime-local"
                        name="period[period_end]"
                        value={dt_value(@subscription && @subscription.period_end)}
                        class="w-full rounded-lg border-gray-300 text-sm focus:border-orange-500 focus:ring-orange-500"
                      />
                    </div>
                  </div>

                  <div class="px-6 py-4 border-t border-gray-200 flex items-center gap-3">
                    <button type="submit" class="px-4 py-2 rounded-lg text-sm font-semibold text-white bg-orange-500 hover:bg-orange-600">
                      Save period
                    </button>
                    <button
                      type="button"
                      phx-click="clear_period"
                      class="px-4 py-2 rounded-lg text-sm font-semibold text-gray-700 border border-gray-300 hover:bg-gray-50"
                    >
                      Clear
                    </button>
                  </div>
                </form>
              </div>
            <% end %>

            <%= if @selected_tenant && @config_form && @tab == "assessments" do %>
              <!-- Config Editor -->
              <div class="bg-white rounded-xl shadow-sm border border-gray-200 mb-6">
                <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
                  <div>
                    <h2 class="text-lg font-semibold text-gray-900">
                      Config - {@selected_tenant.full_name}
                    </h2>
                    <p class="text-sm text-gray-500">
                      <%= if has_saved_config?(@config_map, @selected_tenant.id) do %>
                        Saved configuration
                      <% else %>
                        Using defaults (not yet saved)
                      <% end %>
                    </p>
                  </div>
                  <%= if @save_success do %>
                    <span class="inline-flex items-center text-sm text-green-600 font-medium">
                      <.icon name="hero-check-circle" class="h-5 w-5 mr-1" /> Saved
                    </span>
                  <% end %>
                </div>

                <.form for={@config_form} id="config-form" phx-submit="save_config" phx-change="validate_config" class="p-6">
                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    <!-- Exam Settings -->
                    <div class="space-y-4">
                      <h3 class="text-sm font-semibold text-gray-800 flex items-center">
                        <.icon name="hero-cog-6-tooth" class="h-4 w-4 mr-2 text-orange-500" />
                        Exam Settings
                      </h3>
                      <div>
                        <.input
                          field={@config_form[:total_questions]}
                          type="number"
                          label="Total Questions"
                          min="1"
                          max="200"
                          class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                        />
                      </div>
                      <div>
                        <.input
                          field={@config_form[:duration_minutes]}
                          type="number"
                          label="Duration (minutes)"
                          min="1"
                          max="300"
                          class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                        />
                      </div>
                      <div>
                        <.input
                          field={@config_form[:negative_marking]}
                          type="number"
                          label="Negative Marking (per wrong answer)"
                          step="0.05"
                          min="0"
                          max="1"
                          class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                        />
                      </div>
                      <div>
                        <.input
                          field={@config_form[:passing_percentage]}
                          type="number"
                          label="Passing Percentage (%)"
                          min="0"
                          max="100"
                          class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                        />
                      </div>
                    </div>

                    <!-- Question Split -->
                    <div class="space-y-4">
                      <h3 class="text-sm font-semibold text-gray-800 flex items-center">
                        <.icon name="hero-chart-pie" class="h-4 w-4 mr-2 text-blue-500" />
                        Aptitude / Technical Split
                      </h3>
                      <div>
                        <.input
                          field={@config_form[:aptitude_percentage]}
                          type="number"
                          label="Aptitude (%)"
                          min="0"
                          max="100"
                          class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 mb-1">Technical (%)</label>
                        <input
                          type="number"
                          name="config[technical_percentage]"
                          value={@config_form[:technical_percentage].value}
                          readonly
                          class="w-full px-3 py-2 border border-gray-200 rounded-lg bg-gray-50 text-gray-500 cursor-not-allowed"
                        />
                        <p class="mt-1 text-xs text-gray-400">Auto-calculated: 100 - Aptitude</p>
                      </div>
                      <!-- Visual split bar -->
                      <div class="mt-2">
                        <div class="flex h-4 rounded-full overflow-hidden">
                          <div
                            class="bg-orange-400 transition-all duration-300"
                            style={"width: #{@config_form[:aptitude_percentage].value || 40}%"}
                          >
                          </div>
                          <div
                            class="bg-blue-400 transition-all duration-300"
                            style={"width: #{@config_form[:technical_percentage].value || 60}%"}
                          >
                          </div>
                        </div>
                        <div class="flex justify-between text-xs text-gray-500 mt-1">
                          <span>Aptitude: {@config_form[:aptitude_percentage].value || 40}%</span>
                          <span>Technical: {@config_form[:technical_percentage].value || 60}%</span>
                        </div>
                      </div>
                    </div>

                    <!-- Difficulty Distribution -->
                    <div class="space-y-4">
                      <h3 class="text-sm font-semibold text-gray-800 flex items-center">
                        <.icon name="hero-signal" class="h-4 w-4 mr-2 text-purple-500" />
                        Difficulty Distribution
                      </h3>
                      <div>
                        <.input
                          field={@config_form[:easy_percentage]}
                          type="number"
                          label="Easy (%)"
                          min="0"
                          max="100"
                          class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                        />
                      </div>
                      <div>
                        <.input
                          field={@config_form[:medium_percentage]}
                          type="number"
                          label="Medium (%)"
                          min="0"
                          max="100"
                          class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 mb-1">Hard (%)</label>
                        <input
                          type="number"
                          name="config[hard_percentage]"
                          value={@config_form[:hard_percentage].value}
                          readonly
                          class="w-full px-3 py-2 border border-gray-200 rounded-lg bg-gray-50 text-gray-500 cursor-not-allowed"
                        />
                        <p class="mt-1 text-xs text-gray-400">Auto-calculated: 100 - Easy - Medium</p>
                      </div>
                      <!-- Visual difficulty bar -->
                      <div class="mt-2">
                        <div class="flex h-4 rounded-full overflow-hidden">
                          <div class="bg-green-400 transition-all duration-300" style={"width: #{@config_form[:easy_percentage].value || 40}%"}></div>
                          <div class="bg-yellow-400 transition-all duration-300" style={"width: #{@config_form[:medium_percentage].value || 40}%"}></div>
                          <div class="bg-red-400 transition-all duration-300" style={"width: #{@config_form[:hard_percentage].value || 20}%"}></div>
                        </div>
                        <div class="flex justify-between text-xs text-gray-500 mt-1">
                          <span>Easy: {@config_form[:easy_percentage].value || 40}%</span>
                          <span>Medium: {@config_form[:medium_percentage].value || 40}%</span>
                          <span>Hard: {@config_form[:hard_percentage].value || 20}%</span>
                        </div>
                      </div>
                    </div>
                  </div>

                  <!-- Summary -->
                  <div class="mt-6 p-4 bg-slate-50 rounded-lg border border-slate-200">
                    <h4 class="text-xs font-semibold text-slate-600 uppercase mb-2">Summary</h4>
                    <% total = parse_int(@config_form[:total_questions].value, 60) %>
                    <% apt_pct = parse_int(@config_form[:aptitude_percentage].value, 40) %>
                    <% tech_pct = parse_int(@config_form[:technical_percentage].value, 60) %>
                    <% apt_count = round(total * apt_pct / 100) %>
                    <% tech_count = total - apt_count %>
                    <p class="text-sm text-slate-700">
                      <span class="font-medium">{total}</span> questions
                      (<span class="text-orange-600 font-medium">{apt_count} aptitude</span> +
                       <span class="text-blue-600 font-medium">{tech_count} technical</span>)
                      in <span class="font-medium">{@config_form[:duration_minutes].value || 90} min</span>,
                      pass at <span class="font-medium">{@config_form[:passing_percentage].value || 50}%</span>,
                      negative marking <span class="font-medium">{@config_form[:negative_marking].value || "0.25"}</span>/wrong answer
                    </p>
                  </div>

                  <!-- Actions -->
                  <div class="flex items-center justify-between mt-6 pt-4 border-t border-gray-200">
                    <button
                      type="button"
                      phx-click="reset_defaults"
                      class="text-sm text-gray-500 hover:text-gray-700 font-medium"
                    >
                      Reset to Defaults
                    </button>
                    <button
                      type="submit"
                      disabled={@config_saving?}
                      class={[
                        "px-6 py-2.5 text-sm font-medium text-white rounded-lg transition-colors",
                        "disabled:opacity-50 disabled:cursor-not-allowed",
                        if(@config_saving?, do: "bg-orange-400", else: "bg-orange-500 hover:bg-orange-600")
                      ]}
                    >
                      <%= if @config_saving? do %>
                        <.icon name="hero-arrow-path" class="animate-spin h-4 w-4 inline mr-1" />
                        Saving...
                      <% else %>
                        Save Configuration
                      <% end %>
                    </button>
                  </div>
                </.form>
              </div>

              <!-- Existing Assessments Table -->
              <div class="bg-white rounded-xl shadow-sm border border-gray-200">
                <div class="px-6 py-4 border-b border-gray-200">
                  <h2 class="text-base font-semibold text-gray-900">
                    Existing Assessments ({length(@assessments)})
                  </h2>
                  <p class="text-sm text-gray-500">Assessments generated for students in this tenant</p>
                </div>

                <div class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-gray-200">
                    <thead class="bg-gray-50">
                      <tr>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Title</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Type</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Questions</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Duration</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Marks</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                      </tr>
                    </thead>
                    <tbody class="bg-white divide-y divide-gray-200">
                      <%= if Enum.empty?(@assessments) do %>
                        <tr>
                          <td colspan="6" class="px-6 py-8 text-center text-sm text-gray-500">
                            No assessments generated yet.
                          </td>
                        </tr>
                      <% else %>
                        <%= for assessment <- @assessments do %>
                          <tr class="hover:bg-gray-50">
                            <td class="px-6 py-3 text-sm font-medium text-gray-900 max-w-xs truncate">{assessment.title}</td>
                            <td class="px-6 py-3 text-sm text-gray-600 uppercase">{assessment.assessment_type}</td>
                            <td class="px-6 py-3 text-sm text-gray-600">{assessment.settings["total_questions"] || "-"}</td>
                            <td class="px-6 py-3 text-sm text-gray-600">{assessment.duration_minutes} min</td>
                            <td class="px-6 py-3 text-sm text-gray-600">{assessment.passing_marks}/{assessment.total_marks}</td>
                            <td class="px-6 py-3">
                              <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium capitalize #{status_badge_class(assessment.status)}"}>
                                {assessment.status}
                              </span>
                            </td>
                          </tr>
                        <% end %>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            <% end %>


        </div>
      </.admin_layout>
    </Layouts.app>
    """
  end
end
