defmodule VyaasaCampusWeb.Admin.DashboardLive do
  @moduledoc """
  LiveView for the super admin dashboard.
  Shows tenants list and allows creating new tenants.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Accounts.User
  alias VyaasaCampusWeb.TenantUser.DashboardLive, as: TenantDashboard

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Admin.SuperAdminShell

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: DashboardEvents.subscribe_tenants()

    tenants = Tenants.list_tenants()
    colleges = tenants |> Enum.map(&college_summary/1) |> Enum.sort_by(& &1.health, :desc)
    platform = platform_stats(colleges)

    socket =
      socket
      |> assign(:page_title, "Super Admin Dashboard")
      |> assign(:tenants, tenants)
      |> assign(:colleges, colleges)
      |> assign(:platform, platform)
      |> assign(:active_tenants, length(tenants))
      |> assign(:user_info, admin_user_info(socket.assigns[:current_user]))
      |> assign(:show_create_modal, false)
      |> assign(:form, build_tenant_form())
      |> assign(:form_errors, %{})
      |> assign(:creating?, false)
      |> assign(:tenants_page, 1)
      |> assign(:tenants_per_page, 10)

    {:ok, socket}
  end

  @impl true
  def handle_info({:dashboard_event, %{kind: :tenant}}, socket) do
    {:noreply, assign(socket, :tenants, Tenants.list_tenants())}
  end

  @impl true
  def handle_event("goto_tenants_page", %{"page" => page}, socket) do
    parsed =
      case Integer.parse(to_string(page)) do
        {n, _} when n >= 1 -> n
        _ -> 1
      end

    total = length(socket.assigns[:tenants] || [])
    per_page = socket.assigns[:tenants_per_page] || 10
    total_pages = if total == 0, do: 1, else: div(total - 1, per_page) + 1
    parsed = parsed |> max(1) |> min(total_pages)

    {:noreply, assign(socket, :tenants_page, parsed)}
  end

  @impl true
  def handle_event("show_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:form, build_tenant_form())
     |> assign(:form_errors, %{})}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, false)}
  end

  @impl true
  def handle_event("validate_tenant", %{"tenant" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :tenant))}
  end

  @impl true
  def handle_event("create_tenant", %{"tenant" => params}, socket) do
    socket = assign(socket, :creating?, true)
    current_user = socket.assigns.current_user

    tenant_attrs =
      params
      |> Map.put("created_by", current_user.id)

    case Tenants.create_tenant(tenant_attrs) do
      {:ok, tenant} ->
        # Create tenant admin user
        admin_password = params["admin_password"] || "admin123"

        admin_attrs = %{
          email: params["admin_email"],
          encrypted_password: Bcrypt.hash_pwd_salt(admin_password),
          first_name: params["admin_first_name"] || "Admin",
          last_name: params["admin_last_name"] || tenant.short_name,
          role: "admin",
          status: "active",
          tenant_id: tenant.id,
          created_by_id: current_user.id,
          created_by_type: "public"
        }

        case %User{} |> User.changeset(admin_attrs) |> Repo.insert(prefix: tenant.schema_name) do
          {:ok, _user} -> :ok
          {:error, reason} ->
            require Logger
            Logger.warning("Tenant created but admin user creation failed: #{inspect(reason)}")
        end

        tenants = Tenants.list_tenants()

        {:noreply,
         socket
         |> assign(:tenants, tenants)
         |> assign(:show_create_modal, false)
         |> assign(:creating?, false)
         |> put_flash(:info, "Tenant \"#{params["full_name"]}\" created with admin #{params["admin_email"]}!")}

      {:error, :tenant_already_exists} ->
        {:noreply,
         socket
         |> assign(:creating?, false)
         |> assign(:form_errors, %{alias: "A tenant with this alias already exists."})}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
          end)
          |> Enum.into(%{}, fn {k, v} -> {k, Enum.join(v, ", ")} end)

        {:noreply,
         socket
         |> assign(:creating?, false)
         |> assign(:form_errors, errors)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:creating?, false)
         |> put_flash(:error, "Failed to create tenant: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("activate_tenant", %{"id" => id}, socket) do
    tenant = Tenants.get_tenant!(id)

    case Tenants.activate_tenant(tenant) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:tenants, Tenants.list_tenants())
         |> put_flash(:info, "Tenant activated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to activate tenant.")}
    end
  end

  @impl true
  def handle_event("deactivate_tenant", %{"id" => id}, socket) do
    tenant = Tenants.get_tenant!(id)

    case Tenants.deactivate_tenant(tenant) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:tenants, Tenants.list_tenants())
         |> put_flash(:info, "Tenant deactivated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to deactivate tenant.")}
    end
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> redirect(to: "/auth/admin/logout")}
  end

  defp build_tenant_form do
    to_form(%{}, as: :tenant)
  end

  @impl true
  def handle_event("show_coming_soon", _params, socket) do
    {:noreply, put_flash(socket, :info, "Coming soon!")}
  end

  @impl true
  def handle_event("view_colleges", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/colleges")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={:super_admin}>
      <.admin_layout active_tenants={@active_tenants} user_info={@user_info} current_section="dashboard">
        <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-350 mx-auto w-full space-y-5">
          <!-- Header -->
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div>
              <h1 class="text-2xl font-bold text-gray-900">Platform Dashboard</h1>
              <p class="text-sm text-gray-500 mt-0.5">What's happening across the VYAASA platform</p>
            </div>
            <div class="flex items-center gap-2">
              <.link navigate={~p"/admin/colleges"} class="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg text-sm font-semibold text-white transition" style="background-color: #FF7A00;">
                <.icon name="hero-plus" class="w-4 h-4" /> Add College
              </.link>
              <.link navigate={~p"/admin/colleges"} class="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg text-sm font-semibold text-gray-700 bg-white border border-gray-200 hover:bg-gray-50 transition">
                Create Assessment
              </.link>
            </div>
          </div>

          <!-- Stat tiles (two rows) -->
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <.stat label="Total Colleges" value={@platform.total_colleges} icon="hero-building-office-2" delta={"#{@platform.active_colleges} active"} />
            <.stat label="Total Students" value={fmt_k(@platform.total_students)} icon="hero-academic-cap" />
            <.stat label="Placement Ready" value={@platform.placement_ready} icon="hero-check-badge" delta={"#{@platform.placement_pct}% of students"} />
            <.stat label="Students Completed" value={@platform.students_completed} icon="hero-check-circle" delta="all 8 modules" />
            <.stat label="High Potential" value={@platform.high_potential} icon="hero-bolt" />
            <.stat label="Total Users" value={@platform.total_users} icon="hero-users" />
            <.stat label="Assessments Pending" value={@platform.assessments_pending} icon="hero-clipboard-document-list" />
            <.stat label="Integrity Flags" value={@platform.integrity_flags} icon="hero-shield-exclamation" />
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
            <!-- Placement readiness distribution -->
            <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
              <h2 class="text-sm font-bold text-gray-900 mb-4">Placement Readiness Distribution</h2>
              <div class="flex w-full h-2.5 rounded-full overflow-hidden bg-gray-100 mb-4">
                <div :for={t <- readiness_tiers(@platform.tiers, @platform.total_students)} class="h-full" style={"width: #{t.pct}%; background-color: #{t.color};"}></div>
              </div>
              <div class="space-y-2.5">
                <div :for={t <- readiness_tiers(@platform.tiers, @platform.total_students)} class="flex items-center gap-2 text-sm">
                  <span class="w-2.5 h-2.5 rounded-full shrink-0" style={"background-color: #{t.color};"}></span>
                  <span class="flex-1 text-gray-700">{t.label}</span>
                  <span class="font-semibold text-gray-900">{t.count} Students</span>
                </div>
              </div>
            </div>

            <!-- AI Insights -->
            <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
              <div class="flex items-center gap-2 mb-4">
                <.icon name="hero-sparkles" class="w-4 h-4" style="color: #FF7A00;" />
                <h2 class="text-sm font-bold text-gray-900">Vyaasa Insights</h2>
              </div>
              <div class="space-y-2.5">
                <div :for={{tone, text} <- @platform.insights} class="rounded-lg px-3 py-2.5 text-sm text-gray-700" style={"background-color: #{insight_bg(tone)}; border-left: 3px solid #{insight_border(tone)};"}>
                  {text}
                </div>
                <div :if={@platform.insights == []} class="text-sm text-gray-400 py-3 text-center">No insights yet — onboard colleges and run assessments.</div>
              </div>
            </div>
          </div>

          <!-- College performance -->
          <div class="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
            <div class="flex items-center justify-between px-5 py-4">
              <h2 class="text-sm font-bold text-gray-900">College Performance</h2>
              <.link navigate={~p"/admin/colleges"} class="text-xs font-semibold hover:underline" style="color: #FF7A00;">View All</.link>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full min-w-190 text-sm">
                <thead>
                  <tr class="text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 border-y border-gray-100 bg-gray-50/50">
                    <th class="text-left px-5 py-2.5">College</th>
                    <th class="text-left px-3 py-2.5">Type</th>
                    <th class="text-center px-3 py-2.5">Rankings</th>
                    <th class="text-center px-3 py-2.5">Students</th>
                    <th class="text-center px-3 py-2.5">Users</th>
                    <th class="text-left px-3 py-2.5">Status</th>
                    <th class="text-left px-3 py-2.5">Created</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@colleges == []}><td colspan="7" class="px-5 py-10 text-center text-sm text-gray-400">No colleges onboarded yet.</td></tr>
                  <tr :for={{c, i} <- Enum.with_index(Enum.take(@colleges, 6), 1)} class="border-b border-gray-50 hover:bg-gray-50/40">
                    <td class="px-5 py-3">
                      <div class="flex items-center gap-3">
                        <span class="w-8 h-8 rounded-lg flex items-center justify-center text-[11px] font-bold shrink-0" style="background-color: #FFE9D2; color: #B85F00;">{initials(c.code)}</span>
                        <div class="min-w-0">
                          <p class="font-semibold text-gray-900 truncate">{c.name}</p>
                          <p class="text-[11px] text-gray-400 truncate">{c.code}</p>
                        </div>
                      </div>
                    </td>
                    <td class="px-3 py-3 text-gray-600">{c.type}</td>
                    <td class="px-3 py-3 text-center text-gray-700">{i}</td>
                    <td class="px-3 py-3 text-center text-gray-700">{c.students}</td>
                    <td class="px-3 py-3 text-center text-gray-700">{c.users}</td>
                    <td class="px-3 py-3"><span class={["px-2.5 py-1 rounded-full text-[11px] font-semibold whitespace-nowrap", status_class(c.status)]}>{c.status}</span></td>
                    <td class="px-3 py-3 text-gray-500">{fmt_date(c.created)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <!-- Quick actions -->
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <.quick_action navigate={~p"/admin/colleges"} icon="hero-building-office-2" title="Onboard New College" sub="Add a new institution to the platform" />
            <.quick_action navigate={~p"/admin/colleges"} icon="hero-clipboard-document-list" title="Create Assessment" sub="Build a new evaluation template" />
            <.quick_action phx_click="show_coming_soon" icon="hero-list-bullet" title="Review Audit Logs" sub="Coming soon — platform activity log" />
          </div>
        </div>
      </.admin_layout>
    </Layouts.app>
    """
  end

  # ── Stat card + quick action ──────────────────────────────────────────────
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :delta, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-4">
      <div class="flex items-start justify-between">
        <p class="text-[11px] font-medium text-gray-500">{@label}</p>
        <span class="w-7 h-7 rounded-lg flex items-center justify-center shrink-0" style="background-color: #FFF4E7;">
          <.icon name={@icon} class="w-4 h-4" style="color: #FF7A00;" />
        </span>
      </div>
      <p class="text-2xl font-bold text-gray-900 mt-1.5">{@value}</p>
      <p :if={@delta} class="text-[11px] font-medium text-emerald-600 mt-0.5">{@delta}</p>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :sub, :string, required: true
  attr :navigate, :string, default: nil
  attr :phx_click, :string, default: nil

  defp quick_action(assigns) do
    ~H"""
    <%= if @navigate do %>
      <.link navigate={@navigate} class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5 flex items-center gap-4 hover:border-orange-200 hover:shadow-md transition">
        <span class="w-10 h-10 rounded-xl flex items-center justify-center shrink-0" style="background-color: #FFF4E7;">
          <.icon name={@icon} class="w-5 h-5" style="color: #FF7A00;" />
        </span>
        <div class="min-w-0">
          <p class="text-sm font-semibold text-gray-900">{@title}</p>
          <p class="text-[11px] text-gray-400">{@sub}</p>
        </div>
      </.link>
    <% else %>
      <button phx-click={@phx_click} class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5 flex items-center gap-4 hover:border-orange-200 hover:shadow-md transition w-full text-left">
        <span class="w-10 h-10 rounded-xl flex items-center justify-center shrink-0" style="background-color: #FFF4E7;">
          <.icon name={@icon} class="w-5 h-5" style="color: #FF7A00;" />
        </span>
        <div class="min-w-0">
          <p class="text-sm font-semibold text-gray-900">{@title}</p>
          <p class="text-[11px] text-gray-400">{@sub}</p>
        </div>
      </button>
    <% end %>
    """
  end

  # Readiness distribution tiers with colors + pct.
  defp readiness_tiers(tiers, total) do
    total = max(total, 1)

    [
      {"Elite Talent", tiers.elite, "#16A34A"},
      {"High Potential", tiers.high, "#FF7A00"},
      {"Placement Ready", tiers.ready, "#FBBF24"},
      {"Emerging Talent", tiers.emerging, "#60A5FA"},
      {"Developing", tiers.developing, "#9CA3AF"}
    ]
    |> Enum.map(fn {label, count, color} -> %{label: label, count: count, color: color, pct: round(count / total * 100)} end)
  end

  defp insight_bg(:emerald), do: "#ECFDF5"
  defp insight_bg(:amber), do: "#FFFBEB"
  defp insight_bg(:red), do: "#FEF2F2"
  defp insight_bg(_), do: "#F9FAFB"

  defp insight_border(:emerald), do: "#16A34A"
  defp insight_border(:amber), do: "#F59E0B"
  defp insight_border(:red), do: "#EF4444"
  defp insight_border(_), do: "#D1D5DB"

  defp initials(code) when is_binary(code), do: code |> String.upcase() |> String.slice(0, 3)
  defp initials(_), do: "—"

  defp fmt_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp fmt_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp fmt_date(_), do: "—"

  # ── Cross-tenant aggregation ──────────────────────────────────────────────
  defp college_summary(tenant) do
    scored = safe_scored(tenant.schema_name)
    students = length(scored)
    vy = scored |> Enum.map(&Map.get(&1, :ai8_score)) |> Enum.reject(&is_nil/1)
    ready = Enum.count(vy, &(&1 >= 70))
    done_sum = Enum.sum(Enum.map(scored, &done_count/1))
    completion = if students > 0, do: round(done_sum / (students * 6) * 100), else: 0
    placement = pct(ready, students)
    avg = if vy != [], do: round(Enum.sum(vy) / length(vy)), else: 0
    health = round(placement * 0.6 + completion * 0.4)
    tiers = tier_breakdown(vy)

    %{
      id: tenant.id,
      name: tenant.full_name || tenant.alias,
      code: tenant.short_name || tenant.alias,
      type: college_type(tenant),
      users: safe_user_count(tenant.schema_name),
      created: tenant.inserted_at,
      students: students,
      ready: ready,
      completed: Enum.count(scored, &(done_count(&1) >= 6)),
      integrity_flags: safe_integrity_count(tenant.schema_name),
      high_potential: tiers.elite + tiers.high,
      tiers: tiers,
      vy_sum: Enum.sum(vy),
      vy_count: length(vy),
      done_sum: done_sum,
      max_vy: if(vy != [], do: round(Enum.max(vy)), else: 0),
      avg: avg,
      completion: completion,
      placement: placement,
      health: health,
      status: if(tenant.status == "active" or health >= 65, do: "Active", else: "Inactive"),
      health_status: status_for(health),
      pending?: tenant.status == "pending"
    }
  end

  # Readiness tiers from VYAASA scores (mirrors the platform distribution).
  defp tier_breakdown(vy) do
    %{
      elite: Enum.count(vy, &(&1 >= 85)),
      high: Enum.count(vy, &(&1 >= 70 and &1 < 85)),
      ready: Enum.count(vy, &(&1 >= 55 and &1 < 70)),
      emerging: Enum.count(vy, &(&1 >= 40 and &1 < 55)),
      developing: Enum.count(vy, &(&1 < 40))
    }
  end

  defp college_type(tenant), do: tenant.affiliation_type || "College"

  defp safe_user_count(schema) do
    import Ecto.Query

    User
    |> where([u], u.role in ["admin", "tenant_user", "staff"])
    |> Repo.aggregate(:count, :id, prefix: schema)
  rescue
    _ -> 0
  end

  # Real integrity-flag count for a tenant: interview sessions terminated for
  # content-moderation violations.
  defp safe_integrity_count(schema) do
    import Ecto.Query

    VyaasaCampus.Schema.Interview.InterviewSession
    |> where([i], i.status == "terminated")
    |> Repo.aggregate(:count, :id, prefix: schema)
  rescue
    _ -> 0
  end

  defp platform_stats(colleges) do
    students = Enum.sum(Enum.map(colleges, & &1.students))
    ready = Enum.sum(Enum.map(colleges, & &1.ready))
    vy_sum = Enum.sum(Enum.map(colleges, & &1.vy_sum))
    vy_count = Enum.sum(Enum.map(colleges, & &1.vy_count))
    done_sum = Enum.sum(Enum.map(colleges, & &1.done_sum))

    tiers =
      Enum.reduce(colleges, %{elite: 0, high: 0, ready: 0, emerging: 0, developing: 0}, fn c, acc ->
        Map.merge(acc, Map.new(c.tiers, fn {k, v} -> {k, acc[k] + v} end))
      end)

    %{
      total_colleges: length(colleges),
      total_students: students,
      placement_ready: ready,
      placement_pct: pct(ready, students),
      high_potential: tiers.elite + tiers.high,
      total_users: Enum.sum(Enum.map(colleges, & &1.users)),
      assessments_pending: Enum.sum(Enum.map(colleges, fn c -> c.students * 6 - c.done_sum end)) |> max(0),
      integrity_flags: Enum.sum(Enum.map(colleges, & &1.integrity_flags)),
      students_completed: Enum.sum(Enum.map(colleges, & &1.completed)),
      active_colleges: Enum.count(colleges, &(&1.status == "Active")),
      avg: if(vy_count > 0, do: round(vy_sum / vy_count), else: 0),
      completion: if(students > 0, do: round(done_sum / (students * 6) * 100), else: 0),
      highest: colleges |> Enum.map(& &1.max_vy) |> Enum.max(fn -> 0 end),
      tiers: tiers,
      low_adoption: Enum.count(colleges, &(&1.students == 0)),
      completion_low: Enum.count(colleges, &(&1.students > 0 and &1.completion < 50)),
      at_risk: Enum.count(colleges, &(&1.health < 65)),
      pending: Enum.count(colleges, & &1.pending?),
      insights: build_insights(colleges, students, ready),
      top: colleges |> Enum.filter(&(&1.students > 0)) |> Enum.sort_by(& &1.placement, :desc) |> Enum.take(3),
      attention: colleges |> Enum.filter(&(&1.students > 0)) |> Enum.sort_by(& &1.completion, :asc) |> Enum.take(3)
    }
  end

  # Lightweight rule-based "AI Insights" derived from the cross-tenant aggregates.
  defp build_insights(colleges, students, ready) do
    no_students = Enum.filter(colleges, &(&1.students == 0))
    inactive = Enum.filter(colleges, &(&1.status == "Inactive"))
    low_completion = colleges |> Enum.filter(&(&1.students > 0 and &1.completion < 50))
    top = colleges |> Enum.filter(&(&1.students > 0)) |> Enum.max_by(& &1.placement, fn -> nil end)

    [
      students > 0 && {:emerald, "#{ready} students are assessment-ready across the platform"},
      top && {:emerald, "#{top.name} leads with the highest placement readiness (#{top.placement}%)"},
      no_students != [] && {:amber, "#{length(no_students)} college(s) have not onboarded any students yet"},
      low_completion != [] && {:amber, "#{length(low_completion)} college(s) have assessment completion below 50%"},
      inactive != [] && {:red, "#{length(inactive)} college(s) appear inactive — consider follow-up"}
    ]
    |> Enum.filter(& &1)
    |> Enum.take(6)
  end

  defp safe_scored(schema) do
    TenantDashboard.load_all_students_with_scores(schema)
  rescue
    _ -> []
  end

  defp done_count(s) do
    [:ats_score, :mcq_percentage, :behavioral_score, :jam_score, :interview_score, :psychometric_score]
    |> Enum.count(fn k -> Map.get(s, k) not in [nil, ""] end)
  end

  defp pct(_n, 0), do: 0
  defp pct(n, total), do: round(n / total * 100)

  defp status_for(h) when h >= 85, do: "Excellent"
  defp status_for(h) when h >= 65, do: "Healthy"
  defp status_for(_), do: "At Risk"

  defp status_class("Active"), do: "bg-emerald-50 text-emerald-700"
  defp status_class("Inactive"), do: "bg-gray-100 text-gray-500"
  defp status_class("Excellent"), do: "bg-emerald-100 text-emerald-700"
  defp status_class("Healthy"), do: "bg-blue-100 text-blue-700"
  defp status_class(_), do: "bg-red-100 text-red-700"

  defp fmt_k(n) when is_number(n) and n >= 1000, do: "#{Float.round(n / 1000, 1)}K"
  defp fmt_k(n), do: "#{n}"

  defp admin_user_info(nil), do: %{name: "Super Admin", role: "Platform Admin"}
  defp admin_user_info(u), do: %{name: String.trim("#{u.first_name} #{u.last_name}"), role: "Platform Admin", email: u.email}
end
