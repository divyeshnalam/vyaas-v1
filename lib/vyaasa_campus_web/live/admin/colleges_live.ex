defmodule VyaasaCampusWeb.Admin.CollegesLive do
  @moduledoc """
  Super-admin "Colleges" — every onboarded tenant with per-college stats
  (students, users, type, status) aggregated from each tenant's own schema.
  Matches the new platform mockup: search + Type/Status filters + Export, a
  table with Actions (activate / deactivate / view), and an AI Insights panel.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Academics
  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Accounts.User
  alias VyaasaCampusWeb.TenantUser.DashboardLive

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Admin.SuperAdminShell

  require Logger

  @per_page 10

  @impl true
  def mount(_params, _session, socket) do
    colleges = load_colleges()

    {:ok,
     socket
     |> assign(:active_tenants, length(colleges))
     |> assign(:user_info, user_info(socket.assigns[:current_user]))
     |> assign(:all_colleges, colleges)
     |> assign(:search, "")
     |> assign(:type_filter, "all")
     |> assign(:status_filter, "all")
     |> assign(:open_menu, nil)
     |> assign(:page, 1)
     |> assign(:per_page, @per_page)
     |> assign(:detail_college, nil)
     |> paginate()}
  end

  # ── Events ──────────────────────────────────────────────────────────────
  @impl true
  def handle_event("search", %{"value" => term}, socket),
    do: {:noreply, socket |> assign(:search, term) |> assign(:page, 1) |> paginate()}

  def handle_event("filter_type", %{"type" => t}, socket),
    do: {:noreply, socket |> assign(:type_filter, t) |> assign(:page, 1) |> paginate()}

  def handle_event("filter_status", %{"status" => s}, socket),
    do: {:noreply, socket |> assign(:status_filter, s) |> assign(:page, 1) |> paginate()}

  def handle_event("goto_page", %{"page" => page}, socket),
    do: {:noreply, socket |> assign(:page, parse_page(page)) |> paginate()}

  def handle_event("toggle_menu", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :open_menu, if(socket.assigns.open_menu == id, do: nil, else: id))}

  def handle_event("close_menu", _params, socket),
    do: {:noreply, assign(socket, :open_menu, nil)}

  def handle_event("add_college", _params, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/admin/colleges/new")}

  def handle_event("activate", %{"id" => id}, socket), do: set_active(socket, id, true)
  def handle_event("deactivate", %{"id" => id}, socket), do: set_active(socket, id, false)

  def handle_event("view_details", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:open_menu, nil)
     |> assign(:detail_college, load_college_detail(id))}
  end

  def handle_event("close_details", _params, socket),
    do: {:noreply, assign(socket, :detail_college, nil)}

  defp set_active(socket, id, active?) do
    tenant = Tenants.get_tenant!(id)
    op = if active?, do: &Tenants.activate_tenant/1, else: &Tenants.deactivate_tenant/1

    case op.(tenant) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:all_colleges, load_colleges())
         |> assign(:open_menu, nil)
         |> put_flash(:info, "College #{if active?, do: "activated", else: "deactivated"}.")
         |> paginate()}

      _ ->
        {:noreply, put_flash(socket, :error, "Action failed.")}
    end
  end

  # ── Render ──────────────────────────────────────────────────────────────
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={:super_admin}>
      <.admin_layout active_tenants={@active_tenants} user_info={@user_info} current_section="colleges">
        <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-350 mx-auto w-full">
          <nav class="text-[12px] text-gray-400 mb-2">
            <.link navigate={~p"/admin/dashboard"} class="hover:text-gray-600">Dashboard</.link>
            <span class="mx-1.5">&rsaquo;</span><span class="text-gray-600">Colleges</span>
          </nav>

          <div class="flex flex-wrap items-start justify-between gap-4 mb-5">
            <div>
              <h1 class="text-2xl font-bold text-gray-900">Colleges</h1>
              <p class="text-sm text-gray-500 mt-0.5">Manage institutions registered on the platform</p>
            </div>
            <button phx-click="add_college" class="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg text-sm font-semibold text-white transition" style="background-color: #FF7A00;">
              <.icon name="hero-plus" class="w-4 h-4" /> Add College
            </button>
          </div>

          <div class="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-visible">
            <!-- Toolbar -->
            <div class="flex flex-wrap items-center gap-3 px-5 py-4 border-b border-gray-100">
              <div class="relative flex-1 min-w-50 max-w-md">
                <.icon name="hero-magnifying-glass" class="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2" />
                <form phx-change="search" onsubmit="return false">
                  <input type="text" name="value" value={@search} placeholder="Search colleges…" phx-debounce="300"
                    class="w-full pl-9 pr-3 py-2 rounded-lg bg-[#FBFAF7] border border-gray-200 text-sm text-gray-700 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-100 focus:border-[#FF7A00]" />
                </form>
              </div>
              <form phx-change="filter_type">
                <select name="type" class="px-3 py-2 rounded-lg border border-gray-200 text-sm text-gray-600 bg-white focus:outline-none">
                  <option value="all" selected={@type_filter == "all"}>Type</option>
                  <option :for={t <- @types} value={t} selected={@type_filter == t}>{t}</option>
                </select>
              </form>
              <form phx-change="filter_status">
                <select name="status" class="px-3 py-2 rounded-lg border border-gray-200 text-sm text-gray-600 bg-white focus:outline-none">
                  <option value="all" selected={@status_filter == "all"}>Status</option>
                  <option value="Active" selected={@status_filter == "Active"}>Active</option>
                  <option value="Inactive" selected={@status_filter == "Inactive"}>Inactive</option>
                </select>
              </form>
              <a href={~p"/admin/colleges/export"} class="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg border border-gray-200 text-sm font-medium text-gray-600 hover:bg-gray-50">
                <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Export
              </a>
            </div>

            <!-- Table -->
            <div>
              <table class="w-full min-w-215 text-sm">
                <thead>
                  <tr class="text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 border-b border-gray-100">
                    <th class="text-left px-5 py-3">College</th>
                    <th class="text-left px-3 py-3">Type</th>
                    <th class="text-center px-3 py-3">Students</th>
                    <th class="text-center px-3 py-3">Users</th>
                    <th class="text-left px-3 py-3">Status</th>
                    <th class="text-left px-3 py-3">Created</th>
                    <th class="text-right px-5 py-3">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@colleges == []}><td colspan="7" class="px-5 py-12 text-center text-sm text-gray-400">No colleges found.</td></tr>
                  <tr :for={c <- @colleges} class="border-b border-gray-50 hover:bg-[#FBFAF7] transition">
                    <td class="px-5 py-3">
                      <div class="flex items-center gap-3">
                        <div class="w-8 h-8 rounded-lg text-[11px] font-bold flex items-center justify-center shrink-0" style="background-color: #FFE9D2; color: #B85F00;">{initials(c.code)}</div>
                        <div class="min-w-0">
                          <p class="font-semibold text-gray-900 truncate">{c.name}</p>
                          <p class="text-[11px] text-gray-400 truncate">{c.code}</p>
                        </div>
                      </div>
                    </td>
                    <td class="px-3 py-3 text-gray-600">{c.type}</td>
                    <td class="px-3 py-3 text-center text-gray-700">{c.students}</td>
                    <td class="px-3 py-3 text-center text-gray-700">{c.users}</td>
                    <td class="px-3 py-3"><span class={["px-2.5 py-1 rounded-full text-[11px] font-semibold whitespace-nowrap", status_class(c.status)]}>{c.status}</span></td>
                    <td class="px-3 py-3 text-gray-500">{fmt_date(c.created)}</td>
                    <td class="px-5 py-3 text-right relative">
                      <button phx-click="toggle_menu" phx-value-id={c.id} class="w-7 h-7 rounded-lg hover:bg-gray-100 inline-flex items-center justify-center text-gray-400">
                        <.icon name="hero-ellipsis-horizontal" class="w-5 h-5" />
                      </button>
                      <div :if={@open_menu == c.id} phx-click-away="close_menu" class="absolute right-5 top-11 z-20 w-40 bg-white rounded-lg border border-gray-100 shadow-lg py-1 text-left">
                        <button :if={c.status != "Active"} phx-click="activate" phx-value-id={c.id} class="w-full px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 text-left">Activate</button>
                        <button :if={c.status == "Active"} phx-click="deactivate" phx-value-id={c.id} class="w-full px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 text-left">Deactivate</button>
                        <button phx-click="view_details" phx-value-id={c.id} class="w-full px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 text-left">View details</button>
                        <.link navigate={~p"/admin/colleges/#{c.id}/config"} class="block w-full px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 text-left">Configure</.link>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <!-- Pagination -->
            <div class="flex items-center justify-between gap-3 px-5 py-4 border-t border-gray-100">
              <span class="text-xs text-gray-400">Showing {@total} records</span>
              <div class="flex items-center gap-2">
                <button phx-click="goto_page" phx-value-page={@page - 1} disabled={@page <= 1}
                  class="px-2.5 py-1 rounded-md border border-gray-200 text-xs text-gray-500 hover:bg-gray-50 disabled:opacity-40">Previous</button>
                <span class="text-xs text-gray-500">{@page} / {total_pages(@total, @per_page)}</span>
                <button phx-click="goto_page" phx-value-page={@page + 1} disabled={@page >= total_pages(@total, @per_page)}
                  class="px-2.5 py-1 rounded-md border border-gray-200 text-xs text-gray-500 hover:bg-gray-50 disabled:opacity-40">Next</button>
              </div>
            </div>
          </div>

          <!-- AI Insights -->
          <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5 mt-5">
            <div class="flex items-center gap-2 mb-3">
              <.icon name="hero-sparkles" class="w-4 h-4" style="color: #FF7A00;" />
              <h2 class="text-sm font-bold text-gray-900">Vyaasa Insights</h2>
            </div>
            <div class="space-y-2.5">
              <div :for={{tone, text} <- @insights} class="rounded-lg px-3 py-2.5 text-sm text-gray-700" style={"background-color: #{insight_bg(tone)}; border-left: 3px solid #{insight_border(tone)};"}>{text}</div>
              <div :if={@insights == []} class="text-sm text-gray-400 py-2 text-center">No insights right now — all colleges look healthy.</div>
            </div>
          </div>
        </div>

        <!-- Backdrop -->
        <div :if={@detail_college} phx-click="close_details" class="fixed inset-0 bg-black/20 z-30" />

        <!-- College Detail drawer -->
        <div class={[
          "fixed top-0 right-0 h-full w-105 bg-white shadow-2xl z-40 flex flex-col transition-transform duration-300 ease-in-out",
          if(@detail_college, do: "translate-x-0", else: "translate-x-full pointer-events-none")
        ]}>
          <.college_detail_sidebar :if={@detail_college} college={@detail_college} />
        </div>
      </.admin_layout>
    </Layouts.app>
    """
  end

  # ── College Detail drawer ──────────────────────────────────────────────────
  attr :college, :map, required: true

  defp college_detail_sidebar(assigns) do
    ~H"""
    <!-- Header -->
    <div class="flex items-center justify-between px-5 py-4 border-b border-gray-100 shrink-0">
      <h2 class="text-base font-bold text-gray-900">Details</h2>
      <button phx-click="close_details" class="w-8 h-8 rounded-lg hover:bg-gray-100 flex items-center justify-center text-gray-400 hover:text-gray-600 transition">
        <.icon name="hero-x-mark" class="w-5 h-5" />
      </button>
    </div>

    <!-- Scrollable body -->
    <div class="flex-1 overflow-y-auto px-5 py-5 space-y-5">
      <!-- Avatar + name -->
      <div class="flex items-center gap-4">
        <div class="w-14 h-14 rounded-2xl text-lg font-bold flex items-center justify-center shrink-0" style="background-color: #FFE9D2; color: #B85F00;">
          {initials(@college.code)}
        </div>
        <div class="min-w-0">
          <p class="font-bold text-gray-900 text-base truncate">{@college.name}</p>
          <p class="text-xs text-gray-400 mt-0.5">{@college.type} Institution</p>
        </div>
      </div>

      <!-- Stats -->
      <div class="grid grid-cols-2 gap-3">
        <div class="rounded-xl border border-gray-100 bg-gray-50 px-4 py-3">
          <p class="text-xs text-gray-400">Students</p>
          <p class="text-2xl font-bold text-gray-900 mt-0.5">{@college.students}</p>
        </div>
        <div class="rounded-xl border border-gray-100 bg-gray-50 px-4 py-3">
          <p class="text-xs text-gray-400">Branches</p>
          <p class="text-2xl font-bold text-gray-900 mt-0.5">{@college.branches}</p>
        </div>
      </div>

      <!-- Contact Information -->
      <div>
        <p class="text-[10px] font-bold uppercase tracking-widest text-gray-400 mb-3">Contact Information</p>
        <div class="space-y-2.5">
          <div class="flex items-center gap-2.5 text-sm text-gray-700">
            <.icon name="hero-envelope" class="w-4 h-4 text-gray-400 shrink-0" />
            <span class="truncate">{@college.email || "—"}</span>
          </div>
          <div class="flex items-center gap-2.5 text-sm text-gray-700">
            <.icon name="hero-phone" class="w-4 h-4 text-gray-400 shrink-0" />
            <span class="truncate">{@college.phone || "—"}</span>
          </div>
          <div :if={@college.website} class="flex items-center gap-2.5 text-sm">
            <.icon name="hero-globe-alt" class="w-4 h-4 text-gray-400 shrink-0" />
            <a href={website_href(@college.website)} target="_blank" rel="noopener" class="truncate hover:underline" style="color: #FF7A00;">{@college.website}</a>
          </div>
          <div class="flex items-start gap-2.5 text-sm text-gray-700">
            <.icon name="hero-map-pin" class="w-4 h-4 text-gray-400 shrink-0 mt-0.5" />
            <span>{@college.address || "—"}</span>
          </div>
        </div>
      </div>

      <!-- Courses Offered -->
      <div>
        <p class="text-[10px] font-bold uppercase tracking-widest text-gray-400 mb-3">Courses Offered</p>
        <div :if={@college.courses != []} class="flex flex-wrap gap-1.5">
          <span :for={c <- @college.courses} class="px-2.5 py-1 rounded-full text-xs font-medium text-gray-700 bg-gray-50 border border-gray-100">{c.name}</span>
        </div>
        <p :if={@college.courses == []} class="text-sm text-gray-400">No courses selected yet.</p>
      </div>

      <div class="flex items-center gap-2 pt-1 border-t border-gray-100">
        <span class={["mt-3 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap", status_class(@college.status)]}>{@college.status}</span>
        <span class="mt-3 text-xs text-gray-400">Created {fmt_date(@college.created)}</span>
      </div>
    </div>
    """
  end

  # ── Data ────────────────────────────────────────────────────────────────
  defp load_colleges do
    Tenants.list_tenants() |> Enum.map(&summarize/1) |> Enum.sort_by(& &1.created, {:desc, DateTime})
  rescue
    _ -> Tenants.list_tenants() |> Enum.map(&summarize/1)
  end

  defp paginate(socket) do
    term = String.downcase(socket.assigns.search || "")
    tf = socket.assigns.type_filter
    sf = socket.assigns.status_filter

    filtered =
      socket.assigns.all_colleges
      |> Enum.filter(fn c ->
        (term == "" or String.contains?(String.downcase(c.name), term) or String.contains?(String.downcase(to_string(c.code)), term)) and
          (tf == "all" or c.type == tf) and
          (sf == "all" or c.status == sf)
      end)

    total = length(filtered)
    page = socket.assigns.page |> max(1) |> min(total_pages(total, @per_page))

    socket
    |> assign(:colleges, paginate_list(filtered, page, @per_page))
    |> assign(:total, total)
    |> assign(:page, page)
    |> assign(:types, Enum.uniq(Enum.map(socket.assigns.all_colleges, & &1.type)) |> Enum.sort())
    |> assign(:insights, build_insights(socket.assigns.all_colleges))
  end

  defp summarize(tenant) do
    scored = safe_scored(tenant.schema_name)
    students = length(scored)
    status = if tenant.status == "active", do: "Active", else: "Inactive"

    %{
      id: tenant.id,
      name: tenant.full_name || tenant.alias,
      code: tenant.short_name || tenant.alias,
      type: tenant.affiliation_type || "College",
      students: students,
      users: safe_user_count(tenant.schema_name),
      status: status,
      created: tenant.inserted_at,
      last_activity_days: 30
    }
  end

  defp load_college_detail(id) do
    tenant = Tenants.get_tenant!(id)
    locations = safe_locations(id)
    primary = Enum.find(locations, & &1.is_primary) || List.first(locations)

    %{
      id: tenant.id,
      name: tenant.full_name || tenant.alias,
      code: tenant.short_name || tenant.alias,
      type: tenant.affiliation_type || "College",
      students: length(safe_scored(tenant.schema_name)),
      branches: length(locations),
      email: tenant.email,
      phone: tenant.phone,
      website: tenant.website_url,
      address: format_address(primary),
      status: if(tenant.status == "active", do: "Active", else: "Inactive"),
      created: tenant.inserted_at,
      courses: safe_courses(tenant.id)
    }
  rescue
    e ->
      Logger.warning("Failed to load college detail for #{id}: #{Exception.message(e)}")
      nil
  end

  defp safe_locations(tenant_id) do
    Tenants.list_tenant_locations(tenant_id)
  rescue
    _ -> []
  end

  defp safe_courses(tenant_id) do
    {degrees, _specializations} = Academics.list_tenant_degrees_with_specializations(tenant_id)
    degrees
  rescue
    _ -> []
  end

  defp format_address(nil), do: nil

  defp format_address(%{address: address, city: city, state: state, pincode: pincode}) do
    [address, city, state, pincode]
    |> Enum.filter(&(&1 not in [nil, ""]))
    |> Enum.join(", ")
    |> case do
      "" -> nil
      s -> s
    end
  end

  defp website_href(url) do
    if String.starts_with?(url, "http"), do: url, else: "https://#{url}"
  end

  defp build_insights(colleges) do
    no_students = Enum.filter(colleges, &(&1.students == 0))
    inactive = Enum.filter(colleges, &(&1.status == "Inactive"))

    [
      no_students != [] && {:amber, "#{length(no_students)} college(s) have not onboarded any students yet"},
      inactive != [] && {:red, "#{length(inactive)} college(s) are currently inactive"}
    ]
    |> Enum.filter(& &1)
  end

  defp safe_scored(schema) do
    DashboardLive.load_all_students_with_scores(schema)
  rescue
    e ->
      Logger.warning("College stats failed for #{schema}: #{Exception.message(e)}")
      []
  end

  defp safe_user_count(schema) do
    import Ecto.Query
    User |> where([u], u.role in ["admin", "tenant_user", "staff"]) |> Repo.aggregate(:count, :id, prefix: schema)
  rescue
    _ -> 0
  end

  # ── Helpers ───────────────────────────────────────────────────────────────
  defp status_class("Active"), do: "bg-emerald-50 text-emerald-700"
  defp status_class(_), do: "text-red-500 bg-red-50"

  defp insight_bg(:amber), do: "#FFFBEB"
  defp insight_bg(:red), do: "#FEF2F2"
  defp insight_bg(_), do: "#F9FAFB"
  defp insight_border(:amber), do: "#F59E0B"
  defp insight_border(:red), do: "#EF4444"
  defp insight_border(_), do: "#D1D5DB"

  defp initials(code) when is_binary(code), do: code |> String.upcase() |> String.slice(0, 3)
  defp initials(_), do: "—"

  defp fmt_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp fmt_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp fmt_date(_), do: "—"

  defp total_pages(total, _pp) when total <= 0, do: 1
  defp total_pages(total, pp), do: div(total - 1, pp) + 1

  defp parse_page(v) when is_binary(v), do: (case Integer.parse(v) do {n, _} when n >= 1 -> n; _ -> 1 end)
  defp parse_page(_), do: 1

  defp user_info(nil), do: %{name: "Super Admin", role: "Platform Admin"}
  defp user_info(u), do: %{name: String.trim("#{u.first_name} #{u.last_name}"), role: "Platform Admin", email: u.email}
end
