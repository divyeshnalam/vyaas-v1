defmodule VyaasaCampusWeb.TenantUser.StudentsLive do
  @moduledoc """
  Tenant-admin Students screen with two right-side slide-over drawers:
    • Create Student — form that creates and sends a profile-completion invite
    • Student Detail — score overview + actions for any row the admin clicks
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.{Academics, AI8, AttemptGuard, Entitlements, StudentAts, Students,
                               StudentCsvImport, Tenants}
  alias VyaasaCampus.Schema.Students.Student
  alias VyaasaCampusWeb.Components.Shared.AI8Radar
  alias VyaasaCampusWeb.TenantUser.DashboardLive

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Shared.AI8Radar
  import VyaasaCampusWeb.Components.TenantAdmin.AdminShell
  import VyaasaCampusWeb.Components.TenantUser.CsvUploadComponents

  @per_page 10

  # ── Mount / params ────────────────────────────────────────────────────────

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))

    if tenant do
      if connected?(socket), do: VyaasaCampus.DashboardEvents.subscribe_tenant(tenant.schema_name)

      {degrees, _specializations} = load_degree_options(tenant.id)
      specializations_by_degree = load_specializations_by_degree(tenant.id)

      socket =
        socket
        |> assign(:tenant_alias, tenant_alias)
        |> assign(:tenant, tenant)
        |> assign(:current_section, "students")
        |> assign(:current_scope, :tenant_admin)
        |> assign(:user_info, get_user_info(socket.assigns[:current_user]))
        |> assign(:search_term, "")
        |> assign(:status_filter, "all")
        |> assign(:department_filter, "all")
        |> assign(:year_filter, "all")
        |> assign(:per_page, @per_page)
        # sidebars
        |> assign(:show_sidebar, :none)
        |> assign(:sidebar_student, nil)
        |> assign(:sidebar_ats_phase, nil)
        |> assign(:sidebar_ai8_dims, AI8Radar.dims_from_profile(nil))
        |> assign(:sidebar_ai8, %{index: 0, completion: 0, completed: 0, total: 0})
        |> assign(:sidebar_attempts, [])
        |> assign(:pending_student_ids, MapSet.new())
        |> assign(:create_form, blank_create_form())
        |> assign(:create_loading, false)
        |> assign(:create_errors, [])
        |> assign(:degree_options, degrees)
        |> assign(:specializations_by_degree, specializations_by_degree)
        |> assign(:specialization_options, [{"Select specialization", ""}])
        # CSV import
        |> assign(:show_csv_upload, false)
        |> assign(:uploading?, false)
        |> assign(:csv_result, nil)
        |> assign(:drawer, nil)
        |> allow_upload(:csv_students, accept: ~w(.csv), max_entries: 1, max_file_size: 5_000_000)
        |> load_students(1)

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "Tenant not found")
       |> redirect(to: ~p"/auth/tenant/#{tenant_alias}/login")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = parse_page(params["page"])

    socket =
      socket
      |> load_students(page)
      |> maybe_open_student_detail(params["student"])

    {:noreply, socket}
  end

  # When arriving with ?student=ID (e.g. from the dashboard drawer), open that
  # student's detail drawer. Falls back to a direct DB fetch when the student
  # isn't on the currently-loaded/filtered page.
  defp maybe_open_student_detail(socket, nil), do: socket
  defp maybe_open_student_detail(socket, ""), do: socket

  defp maybe_open_student_detail(socket, student_id) do
    schema = socket.assigns.tenant.schema_name

    student =
      Enum.find(socket.assigns.students, &(to_string(&1.id) == to_string(student_id))) ||
        safe_get_student(student_id, schema)

    if student do
      socket
      |> assign(:show_sidebar, :detail)
      |> assign(:sidebar_student, student)
      |> assign(:sidebar_ats_phase, fetch_ats_phase(student.id, schema))
      |> assign_ai8_detail(student.id, schema)
    else
      socket
    end
  end

  # Tolerate a malformed / unknown id in the URL param without crashing.
  defp safe_get_student(id, schema) do
    Students.get_student(id, schema)
  rescue
    _ -> nil
  end

  # ── Filter / search events ─────────────────────────────────────────────────

  @impl true
  def handle_event("search_students", %{"value" => term}, socket) do
    socket = socket |> assign(:search_term, term) |> load_students(1)
    {:noreply, push_patch(socket, to: page_path(socket, 1))}
  end

  @impl true
  def handle_event("filter_status", %{"value" => v}, socket) do
    socket = socket |> assign(:status_filter, v) |> load_students(1)
    {:noreply, push_patch(socket, to: page_path(socket, 1))}
  end

  @impl true
  def handle_event("filter_department", %{"value" => v}, socket) do
    socket = socket |> assign(:department_filter, v) |> load_students(1)
    {:noreply, push_patch(socket, to: page_path(socket, 1))}
  end

  @impl true
  def handle_event("filter_year", %{"value" => v}, socket) do
    socket = socket |> assign(:year_filter, v) |> load_students(1)
    {:noreply, push_patch(socket, to: page_path(socket, 1))}
  end

  @impl true
  def handle_event("goto_students_page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: page_path(socket, parse_page(page)))}
  end

  # ── Sidebar: Create Student ───────────────────────────────────────────────

  @impl true
  def handle_event("open_create_sidebar", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_sidebar, :create)
     |> assign(:create_errors, [])
     |> assign(:create_form, blank_create_form())
     |> assign(:specialization_options, [{"Select specialization", ""}])}
  end

  @impl true
  def handle_event("validate_create_student", %{"student" => params}, socket) do
    form =
      %Student{}
      |> Student.changeset(params)
      |> Map.put(:action, :validate)
      |> to_form()

    specialization_options =
      specialization_options_for(socket.assigns.specializations_by_degree, params["degree"])

    {:noreply,
     socket
     |> assign(:create_form, form)
     |> assign(:specialization_options, specialization_options)}
  end

  @impl true
  def handle_event("save_create_student", %{"student" => params}, socket) do
    socket = assign(socket, :create_loading, true)
    tenant = socket.assigns.tenant
    user = socket.assigns[:current_user]

    full_params =
      params
      |> Map.put("tenant_id", tenant.id)
      |> Map.put("created_by_id", user && user.id)
      |> Map.put("created_by_type", "tenant")
      |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)
      |> Map.new()

    case Students.create_student(full_params, socket.assigns.tenant_alias, tenant.schema_name) do
      {:ok, _student} ->
        {:noreply,
         socket
         |> assign(:create_loading, false)
         |> assign(:show_sidebar, :none)
         |> put_flash(:info, "Student created. A profile-completion invite was sent to their email.")
         |> load_students(socket.assigns[:current_page] || 1)}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         socket
         |> assign(:create_loading, false)
         |> assign(:create_form, to_form(Map.put(cs, :action, :validate)))
         |> assign(:create_errors, changeset_errors(cs))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:create_loading, false)
         |> assign(:create_errors, [to_string(reason)])}
    end
  end

  # ── Sidebar: Student Detail ───────────────────────────────────────────────

  @impl true
  def handle_event("open_student_detail", %{"student_id" => sid}, socket) do
    student =
      Enum.find(socket.assigns.students, &(to_string(&1.id) == to_string(sid))) ||
        Enum.find(socket.assigns.all_students, &(to_string(&1.id) == to_string(sid)))

    if student do
      schema = socket.assigns.tenant.schema_name
      ats_phase = fetch_ats_phase(student.id, schema)

      {:noreply,
       socket
       |> assign(:drawer, nil)
       |> assign(:show_sidebar, :detail)
       |> assign(:sidebar_student, student)
       |> assign(:sidebar_ats_phase, ats_phase)
       |> assign_ai8_detail(student.id, schema)}
    else
      {:noreply, socket}
    end
  end

  # ── Stat card drawer (Total / Placement Ready / High Potential / etc.) ─────

  @impl true
  def handle_event("show_stat_category", %{"category" => category}, socket) do
    all = socket.assigns.all_students

    {title, students} =
      case category do
        "total" -> {"Total Students", all}
        "placement_ready" -> {"Placement Ready", Enum.filter(all, &(ai8_of(&1) >= 65))}
        "high_potential" -> {"High Potential", Enum.filter(all, &(ai8_of(&1) >= 75))}
        "needs_mentoring" -> {"Needs Mentoring", Enum.filter(all, fn s -> v = ai8_of(s); v > 0 and v < 45 end)}
        "incomplete" -> {"Incomplete Profiles", Enum.filter(all, &(&1.status in ["pending", "profile_incomplete"]))}
        _ -> {"Students", []}
      end

    current = socket.assigns.drawer

    socket =
      if current && current.category == category do
        assign(socket, :drawer, nil)
      else
        assign(socket, :drawer, %{category: category, title: title, students: students})
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer, nil)}
  end

  @impl true
  def handle_event("grant_attempt", %{"module" => module}, socket) do
    student = socket.assigns.sidebar_student
    schema = socket.assigns.tenant.schema_name
    admin = socket.assigns[:current_user]

    case AttemptGuard.grant_extra(student.id, module, 1, "Granted from student detail", admin && admin.id, schema) do
      {:ok, _grant} ->
        {:noreply,
         socket
         |> assign_ai8_detail(student.id, schema)
         |> put_flash(:info, "Granted one more #{attempt_label(module)} attempt to #{full_name(student)}.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not grant the attempt.")}
    end
  end

  @impl true
  def handle_event("close_sidebar", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_sidebar, :none)
     |> assign(:sidebar_student, nil)
     |> assign(:sidebar_ats_phase, nil)}
  end

  # ── Misc events ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("show_coming_soon", _params, socket) do
    {:noreply, put_flash(socket, :info, "Coming soon!")}
  end

  # ── CSV export ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("export_students", _params, socket) do
    tenant_schema = socket.assigns.tenant.schema_name
    all = DashboardLive.load_all_students_with_scores(tenant_schema, :all)
    filtered = filter_students(all, socket)

    csv = students_to_csv(filtered)
    filename = "students-#{Date.utc_today()}.csv"

    {:noreply, push_event(socket, "download_content", %{content: csv, filename: filename, mime: "text/csv"})}
  end

  @csv_headers ~w(first_name last_name email registration_id degree specialization
                  year_of_passing cgpa status ai8_score)

  defp students_to_csv(students) do
    rows =
      Enum.map(students, fn s ->
        [
          s.first_name,
          s.last_name,
          s.email,
          s.registration_id,
          s.degree,
          s.specialization,
          s.year_of_passing,
          s.cgpa,
          s.status,
          ai8_of(s)
        ]
        |> Enum.map(&to_string(&1 || ""))
      end)

    [@csv_headers | rows]
    |> CSV.encode()
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end

  # ── CSV import ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("show_csv_upload", _params, socket) do
    {:noreply, socket |> assign(:show_csv_upload, true) |> assign(:csv_result, nil)}
  end

  @impl true
  def handle_event("hide_csv_upload", _params, socket) do
    {:noreply, assign(socket, :show_csv_upload, false)}
  end

  @impl true
  def handle_event("validate_csv_upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("cancel_csv_entry", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :csv_students, ref)}
  end

  @impl true
  def handle_event("submit_csv_upload", _params, socket) do
    user = socket.assigns.current_user
    tenant = socket.assigns.tenant

    ctx = %{
      tenant_id: tenant.id,
      tenant_alias: socket.assigns.tenant_alias,
      tenant_schema: tenant.schema_name,
      created_by_id: user && user.id,
      created_by_type: "tenant"
    }

    # Copy the upload out of Phoenix's temp entry (which gets deleted as soon
    # as this callback returns) so the actual parse/import can run after this
    # handle_event replies — otherwise the "uploading?" assign never reaches
    # the client before the blocking work finishes and the spinner never paints.
    paths =
      consume_uploaded_entries(socket, :csv_students, fn %{path: path}, _entry ->
        dest = Path.join(System.tmp_dir!(), "csv_import_#{System.unique_integer([:positive])}.csv")
        File.cp!(path, dest)
        {:ok, dest}
      end)

    case paths do
      [path] ->
        send(self(), {:process_csv_upload, path, ctx})
        {:noreply, socket |> assign(:uploading?, true) |> assign(:csv_result, nil)}

      _ ->
        {:noreply, put_flash(socket, :error, "Please choose a CSV file to upload.")}
    end
  end

  # ── Live updates ──────────────────────────────────────────────────────────
  #
  # A score landing anywhere in this tenant (any of the 8 AI8 modules) arrives
  # here. Roster changes reload the page of students; a score change refreshes
  # just that student's row — and the open detail drawer if it's the same
  # student, so the module scores and AI8 radar update while you watch them.

  @impl true
  def handle_info({:dashboard_event, %{action: action}}, socket) when action in [:created, :deleted] do
    {:noreply, load_students(socket, socket.assigns[:current_page] || 1)}
  end

  @impl true
  def handle_info({:dashboard_event, %{student_id: student_id}}, socket) when not is_nil(student_id) do
    pending = socket.assigns[:pending_student_ids] || MapSet.new()
    if MapSet.size(pending) == 0, do: Process.send_after(self(), :flush_student_refresh, 500)
    {:noreply, assign(socket, :pending_student_ids, MapSet.put(pending, to_string(student_id)))}
  end

  @impl true
  def handle_info({:dashboard_event, _payload}, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:flush_student_refresh, socket) do
    ids = MapSet.to_list(socket.assigns[:pending_student_ids] || MapSet.new())
    schema = socket.assigns.tenant.schema_name

    refreshed =
      ids
      |> Enum.map(&DashboardLive.load_student_with_scores(&1, schema))
      |> Enum.reject(&is_nil/1)
      |> Map.new(&{to_string(&1.id), &1})

    socket =
      socket
      |> assign(:pending_student_ids, MapSet.new())
      |> assign(:students, Enum.map(socket.assigns.students, &Map.get(refreshed, to_string(&1.id), &1)))
      |> refresh_open_drawer(refreshed, schema)

    {:noreply, socket}
  end

  # Keep the open detail drawer in sync when its student is one of the updated.
  defp refresh_open_drawer(socket, refreshed, schema) do
    current = socket.assigns[:sidebar_student]

    case current && Map.get(refreshed, to_string(current.id)) do
      nil ->
        socket

      updated ->
        socket
        |> assign(:sidebar_student, updated)
        |> assign_ai8_detail(updated.id, schema)
    end
  end

  @impl true
  def handle_info({:process_csv_upload, path, ctx}, socket) do
    result = StudentCsvImport.parse_and_create(path, ctx)
    File.rm(path)

    socket = assign(socket, :uploading?, false)

    case result do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:csv_result, result)
         |> put_flash(:info, "#{result.success_count} student(s) created, #{result.error_count} failed.")
         |> load_students(1)}

      {:error, :missing_headers, missing} ->
        {:noreply, put_flash(socket, :error, "CSV missing columns: #{Enum.join(missing, ", ")}")}

      {:error, :no_rows} ->
        {:noreply, put_flash(socket, :error, "The CSV file has no data rows.")}

      {:error, :invalid_csv, msg} ->
        {:noreply, put_flash(socket, :error, "Could not read CSV: #{msg}")}
    end
  end

  @impl true
  def handle_event("verify_student", %{"student_id" => student_id}, socket) do
    tenant_schema = socket.assigns.tenant.schema_name
    tenant_alias = socket.assigns.tenant_alias

    case Students.verify_student_and_notify(student_id, tenant_alias, tenant_schema) do
      {:ok, _final, email_result} ->
        socket = load_students(socket, socket.assigns[:current_page] || 1)

        # Refresh sidebar if this student is currently open
        sidebar_student =
          if socket.assigns.sidebar_student &&
               to_string(socket.assigns.sidebar_student.id) == to_string(student_id) do
            Enum.find(socket.assigns.students, &(to_string(&1.id) == to_string(student_id)))
          else
            socket.assigns.sidebar_student
          end

        socket = assign(socket, :sidebar_student, sidebar_student)

        socket =
          case email_result do
            {:ok, :email_sent} ->
              put_flash(socket, :info, "Student verified. Temporary-password email sent.")

            {:error, _reason} ->
              put_flash(
                socket,
                :warning,
                "Student verified, but the temporary-password email could not be sent. " <>
                  "Please check email settings."
              )
          end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to verify student.")}
    end
  end

  @impl true
  def handle_event("resend_invite", %{"student_id" => student_id}, socket) do
    tenant = socket.assigns.tenant

    case Students.resend_profile_completion_email(
           student_id,
           socket.assigns.tenant_alias,
           tenant.schema_name
         ) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Profile-completion invite resent.")}

      {:error, :student_not_found} ->
        {:noreply, put_flash(socket, :error, "Student not found.")}

      {:error, :invalid_status} ->
        {:noreply, put_flash(socket, :error, "Cannot resend invite — student profile is already complete.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send invite. Check server logs for SMTP errors.")}
    end
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Logged out successfully")
     |> redirect(to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}
  end

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.admin_layout
        tenant_alias={@tenant_alias}
        tenant_name={@tenant.full_name}
        student_count={@total_students}
        current_section={@current_section}
        user_info={@user_info}
      >
        <!-- Main content + sidebar share a relative container -->
        <div class="relative flex h-full min-h-screen">

          <!-- Main panel shrinks when sidebar is open -->
          <div class={["flex-1 transition-all duration-300 ease-in-out", if(@show_sidebar != :none, do: "mr-[420px]", else: "mr-0")]}>
            <div class="px-4 sm:px-6 lg:px-10 py-8 w-full">

              <!-- Breadcrumb -->
              <nav class="flex items-center gap-1.5 text-xs text-gray-400 mb-4">
                <span>Dashboard</span>
                <.icon name="hero-chevron-right" class="w-3 h-3" />
                <span class="text-gray-700 font-medium">Students</span>
              </nav>

              <!-- Page header -->
              <div class="flex flex-wrap items-start justify-between gap-4 mb-6">
                <div>
                  <h1 class="text-2xl font-bold text-gray-900">Students</h1>
                  <p class="text-sm text-gray-400 mt-0.5">{@total_students} students in {@tenant.full_name}</p>
                </div>
                <div class="flex items-center gap-2">
                  <button phx-click="show_csv_upload" class="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg border border-gray-200 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50 transition">
                    <.icon name="hero-arrow-up-tray" class="w-4 h-4" /> Import
                  </button>
                  <button phx-click="open_create_sidebar" class="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg text-sm font-semibold text-white transition" style="background-color: #F97316;">
                    <.icon name="hero-plus" class="w-4 h-4" /> Add Student
                  </button>
                </div>
              </div>

              <!-- Stat cards -->
              <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-5 mb-6">
                <.stat_card category="total"           label="Total Students"      value={@stats.total}           icon="hero-academic-cap" icon_color="text-orange-500" bg="bg-orange-50" />
                <.stat_card category="placement_ready" label="Placement Ready"     value={@stats.placement_ready} icon="hero-briefcase"    icon_color="text-blue-500"   bg="bg-blue-50" />
                <.stat_card category="high_potential"  label="High Potential"      value={@stats.high_potential}  icon="hero-star"         icon_color="text-amber-500"  bg="bg-amber-50" />
                <.stat_card category="needs_mentoring" label="Needs Mentoring"     value={@stats.needs_mentoring} icon="hero-light-bulb"   icon_color="text-purple-500" bg="bg-purple-50" />
                <.stat_card category="incomplete"      label="Incomplete Profiles" value={@stats.incomplete}      icon="hero-clock"        icon_color="text-red-400"    bg="bg-red-50" />
              </div>

              <!-- Table card -->
              <div class="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">

                <!-- Filters -->
                <div class="flex flex-wrap items-center gap-3 px-5 py-4 border-b border-gray-100">
                  <div class="relative flex-1 min-w-[200px] max-w-sm">
                    <.icon name="hero-magnifying-glass" class="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2" />
                    <form phx-change="search_students" onsubmit="return false">
                      <input type="text" name="value" value={@search_term}
                        placeholder="Search students by name, ID, email..."
                        phx-debounce="300"
                        class="w-full pl-9 pr-3 py-2 rounded-lg bg-gray-50 border border-gray-200 text-sm text-gray-700 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-100 focus:border-[#F97316]"
                      />
                    </form>
                  </div>
                  <form phx-change="filter_status">
                    <select name="value" class={fsel()}>
                      <option value="all"        selected={@status_filter == "all"}>Status</option>
                      <option value="verified"   selected={@status_filter == "verified"}>Verified</option>
                      <option value="unverified" selected={@status_filter == "unverified"}>Unverified</option>
                    </select>
                  </form>
                  <form phx-change="filter_department">
                    <select name="value" class={fsel()}>
                      <option value="all" selected={@department_filter == "all"}>Department</option>
                      <option :for={d <- @dept_options} value={d} selected={@department_filter == d}>{d}</option>
                    </select>
                  </form>
                  <form phx-change="filter_year">
                    <select name="value" class={fsel()}>
                      <option value="all" selected={@year_filter == "all"}>Year</option>
                      <option :for={y <- @year_options} value={to_string(y)} selected={@year_filter == to_string(y)}>{y}</option>
                    </select>
                  </form>
                  <button id="export-students-btn" phx-hook="FileDownload" phx-click="export_students" class="ml-auto inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg border border-gray-200 bg-white text-sm font-medium text-gray-600 hover:bg-gray-50 transition">
                    <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Export
                  </button>
                </div>

                <!-- Table -->
                <div class="overflow-x-auto">
                  <table class="w-full min-w-[700px] text-sm">
                    <thead>
                      <tr class="text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 border-b border-gray-100 bg-gray-50/50">
                        <th class="text-left font-semibold px-5 py-3">Student</th>
                        <th class="text-left font-semibold px-3 py-3">Department</th>
                        <th class="text-center font-semibold px-3 py-3">CGPA</th>
                        <th class="text-left font-semibold px-3 py-3">Readiness</th>
                        <th class="text-left font-semibold px-3 py-3">Tags</th>
                        <th class="text-left font-semibold px-3 py-3">Status</th>
                        <th class="text-right font-semibold px-5 py-3">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr :if={@students == []}>
                        <td colspan="7" class="px-5 py-14 text-center text-sm text-gray-400">No students found.</td>
                      </tr>
                      <tr
                        :for={s <- @students}
                        phx-click="open_student_detail"
                        phx-value-student_id={s.id}
                        class={["border-b border-gray-50 hover:bg-orange-50/30 cursor-pointer transition-colors", if(selected?(s, @sidebar_student), do: "bg-orange-50/50", else: "")]}
                      >
                        <td class="px-5 py-3.5">
                          <div class="flex items-center gap-3">
                            <div class={["w-10 h-10 rounded-full flex items-center justify-center text-xs font-bold shrink-0", avatar_class(s)]}>
                              {row_initials(s)}
                            </div>
                            <div class="min-w-0">
                              <p class="font-semibold text-gray-900 truncate flex items-center gap-1">
                                <span class="truncate">{full_name(s)}</span>
                                <.icon :if={verified?(s)} name="hero-check-badge-solid" class="w-4 h-4 text-green-500 shrink-0" />
                              </p>
                              <p class="text-[11px] text-gray-400 truncate">{s.registration_id || s.email || "—"}</p>
                            </div>
                          </div>
                        </td>
                        <td class="px-3 py-3.5">
                          <span class="text-gray-700">{dept(s)}</span>
                          <span :if={s.year_of_passing} class="block text-[11px] text-gray-400">{s.year_of_passing}</span>
                        </td>
                        <td class="px-3 py-3.5 text-center">
                          <span class="font-medium text-gray-800">{cgpa_display(s)}</span>
                        </td>
                        <td class="px-3 py-3.5">
                          <span class={["inline-block px-2.5 py-1 rounded-full text-[11px] font-semibold whitespace-nowrap", readiness_class(s)]}>
                            {readiness_label(s)}
                          </span>
                        </td>
                        <td class="px-3 py-3.5">
                          <div class="flex flex-wrap gap-1">
                            <span :for={tag <- student_tags(s)} class={["inline-block px-2 py-0.5 rounded-full text-[10px] font-semibold whitespace-nowrap", tag_class(tag)]}>{tag}</span>
                            <span :if={student_tags(s) == []} class="text-[11px] text-gray-300">—</span>
                          </div>
                        </td>
                        <td class="px-3 py-3.5">
                          <span class={["inline-block px-2.5 py-1 rounded-full text-[11px] font-semibold whitespace-nowrap", status_class(s)]}>
                            {status_label(s)}
                          </span>
                        </td>
                        <td class="px-5 py-3.5 text-right">
                          <button
                            :if={can_verify_row?(s)}
                            phx-click="verify_student"
                            phx-value-student_id={s.id}
                            phx-disable-with="Verifying..."
                            data-confirm={"Verify #{full_name(s)}?"}
                            class="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-semibold text-white bg-emerald-500 hover:bg-emerald-600 transition disabled:opacity-60 disabled:cursor-wait"
                          >
                            <.icon name="hero-check-badge" class="w-3.5 h-3.5" /> Verify
                          </button>
                          <span :if={!can_verify_row?(s)} class="text-[11px] text-gray-300">—</span>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>

                <!-- Pagination -->
                <div class="flex items-center justify-between gap-3 px-5 py-4 border-t border-gray-100">
                  <span class="text-xs text-gray-400">{page_range_label(@current_page, @per_page, @filtered_count)} of {@total_students} students</span>
                  <div class="flex items-center gap-2">
                    <button phx-click="goto_students_page" phx-value-page={1} disabled={@current_page <= 1}
                      title="First page"
                      class="w-7 h-7 rounded-lg border border-gray-200 flex items-center justify-center text-gray-500 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed">
                      <.icon name="hero-chevron-double-left" class="w-4 h-4" />
                    </button>
                    <button phx-click="goto_students_page" phx-value-page={@current_page - 1} disabled={@current_page <= 1}
                      title="Previous page"
                      class="w-7 h-7 rounded-lg border border-gray-200 flex items-center justify-center text-gray-500 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed">
                      <.icon name="hero-chevron-left" class="w-4 h-4" />
                    </button>
                    <form phx-submit="goto_students_page" class="flex items-center gap-1">
                      <input
                        type="number"
                        name="page"
                        min="1"
                        max={total_pages(@filtered_count, @per_page)}
                        value={@current_page}
                        id="students-page-input"
                        class="w-10 h-7 text-center text-xs font-medium text-gray-600 border border-gray-200 rounded-lg focus:outline-none focus:ring-1 focus:ring-emerald-400 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                      />
                      <span class="text-xs font-medium text-gray-600">/ {total_pages(@filtered_count, @per_page)}</span>
                    </form>
                    <button phx-click="goto_students_page" phx-value-page={@current_page + 1} disabled={@current_page >= total_pages(@filtered_count, @per_page)}
                      title="Next page"
                      class="w-7 h-7 rounded-lg border border-gray-200 flex items-center justify-center text-gray-500 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed">
                      <.icon name="hero-chevron-right" class="w-4 h-4" />
                    </button>
                    <button phx-click="goto_students_page" phx-value-page={total_pages(@filtered_count, @per_page)} disabled={@current_page >= total_pages(@filtered_count, @per_page)}
                      title="Last page"
                      class="w-7 h-7 rounded-lg border border-gray-200 flex items-center justify-center text-gray-500 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed">
                      <.icon name="hero-chevron-double-right" class="w-4 h-4" />
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Stat card drawer -->
          <div
            :if={@drawer}
            phx-click="close_drawer"
            phx-window-keydown="close_drawer"
            phx-key="Escape"
            class="fixed inset-0 bg-black/20 z-40"
          />
          <div class={[
            "fixed top-0 right-0 h-full w-110 max-w-[95vw] bg-white shadow-2xl z-50 flex flex-col transition-transform duration-300 ease-in-out",
            if(@drawer, do: "translate-x-0", else: "translate-x-full pointer-events-none")
          ]}>
            <%= if @drawer do %>
              <div class="flex items-start justify-between px-5 py-4 border-b border-gray-100 shrink-0">
                <div>
                  <p class="text-sm font-bold text-gray-900">{@drawer.title}</p>
                  <p class="text-[11px] text-gray-400 mt-0.5">{length(@drawer.students)} students</p>
                </div>
                <button type="button" phx-click="close_drawer" class="text-gray-400 hover:text-gray-600 p-1 rounded-full hover:bg-gray-100" aria-label="Close">
                  <.icon name="hero-x-mark" class="w-6 h-6" />
                </button>
              </div>
              <div class="flex-1 overflow-y-auto">
                <button
                  :for={{s, i} <- Enum.with_index(@drawer.students, 1)}
                  type="button"
                  phx-click="open_student_detail"
                  phx-value-student_id={s.id}
                  class="w-full flex items-start gap-3 px-5 py-3 border-b border-gray-50 hover:bg-orange-50/30 text-left"
                >
                  <span class="w-6 h-6 rounded-full bg-[#FFF4E7] text-[#F97316] text-[11px] font-bold flex items-center justify-center shrink-0 mt-0.5">{i}</span>
                  <div class="min-w-0 flex-1">
                    <p class="text-sm font-semibold text-gray-900 truncate">{s.first_name} {s.last_name}</p>
                    <p class="text-[11px] text-gray-400 truncate">
                      {Map.get(s, :registration_id) || s.email || "—"} · {Map.get(s, :specialization) || Map.get(s, :degree) || "—"}
                    </p>
                    <span class="inline-block mt-1 px-2 py-0.5 rounded-full text-[10px] font-semibold bg-gray-100 text-gray-600">{s.status || "—"}</span>
                  </div>
                  <div class="flex items-center gap-1 shrink-0 mt-0.5">
                    <span class="text-sm font-bold text-[#F97316]">{Map.get(s, :ai8_score) || "—"}</span>
                    <.icon name="hero-chevron-right" class="w-4 h-4 text-gray-300" />
                  </div>
                </button>
                <div :if={@drawer.students == []} class="text-center text-sm text-gray-400 py-16">
                  No students in this category.
                </div>
              </div>
            <% end %>
          </div>

          <!-- Backdrop (closes any open sidebar) -->
          <div
            :if={@show_sidebar != :none}
            phx-click="close_sidebar"
            class="fixed inset-0 bg-black/20 z-30"
          />

          <!-- Create Student drawer -->
          <div class={[
            "fixed top-0 right-0 h-full w-105 bg-white shadow-2xl z-40 flex flex-col transition-transform duration-300 ease-in-out",
            if(@show_sidebar == :create, do: "translate-x-0", else: "translate-x-full pointer-events-none")
          ]}>
            <.create_sidebar
              form={@create_form}
              loading={@create_loading}
              errors={@create_errors}
              degree_options={@degree_options}
              specialization_options={@specialization_options}
            />
          </div>

          <!-- Student Detail drawer -->
          <div class={[
            "fixed top-0 right-0 h-full w-105 bg-white shadow-2xl z-40 flex flex-col transition-transform duration-300 ease-in-out",
            if(@show_sidebar == :detail, do: "translate-x-0", else: "translate-x-full pointer-events-none")
          ]}>
            <.detail_sidebar
              :if={@sidebar_student}
              student={@sidebar_student}
              ats_phase={@sidebar_ats_phase}
              tenant_alias={@tenant_alias}
              ai8_dims={@sidebar_ai8_dims}
              ai8={@sidebar_ai8}
              attempts={@sidebar_attempts}
            />
          </div>
        </div>

        <.csv_upload_modal
          :if={@show_csv_upload}
          uploads={@uploads}
          uploading?={@uploading?}
          result={@csv_result}
        />
      </.admin_layout>
    </Layouts.app>
    """
  end

  # ── Stat card ──────────────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :icon_color, :string, required: true
  attr :bg, :string, required: true
  attr :category, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="show_stat_category"
      phx-value-category={@category}
      class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5 flex items-center gap-4 text-left hover:shadow-md hover:border-[#F8C095] transition"
    >
      <div class={["w-14 h-14 rounded-2xl flex items-center justify-center shrink-0", @bg]}>
        <.icon name={@icon} class={["w-7 h-7", @icon_color]} />
      </div>
      <div class="min-w-0">
        <p class="text-3xl font-bold text-gray-900 leading-tight">{@value}</p>
        <p class="text-xs text-gray-400 leading-tight mt-1 truncate">{@label}</p>
      </div>
    </button>
    """
  end

  # ── Create Student drawer ──────────────────────────────────────────────────

  attr :form, :any, required: true
  attr :loading, :boolean, required: true
  attr :errors, :list, required: true
  attr :degree_options, :list, required: true
  attr :specialization_options, :list, required: true

  defp create_sidebar(assigns) do
    ~H"""
    <!-- Header -->
    <div class="flex items-center justify-between px-5 py-4 border-b border-gray-100 shrink-0">
      <div>
        <h2 class="text-base font-bold text-gray-900">Add Student</h2>
        <p class="text-[11px] text-gray-400 mt-0.5">An invite email will be sent to the student.</p>
      </div>
      <button phx-click="close_sidebar" class="w-8 h-8 rounded-lg hover:bg-gray-100 flex items-center justify-center text-gray-400 hover:text-gray-600 transition">
        <.icon name="hero-x-mark" class="w-5 h-5" />
      </button>
    </div>

    <!-- Scrollable body -->
    <div class="flex-1 overflow-y-auto px-5 py-5">
      <div :if={@errors != []} class="mb-4 rounded-lg p-3 text-sm bg-red-50 border border-red-200 text-red-700 space-y-0.5">
        <p :for={e <- @errors}>{e}</p>
      </div>

      <.form for={@form} phx-change="validate_create_student" phx-submit="save_create_student" id="create-student-form" class="space-y-5">
        <!-- Personal -->
        <div>
          <p class="text-[10px] font-bold uppercase tracking-widest text-gray-400 mb-3">Personal</p>
          <div class="grid grid-cols-2 gap-3">
            <.sf
              field={@form[:first_name]}
              label="First Name"
              placeholder="Anya"
              pattern="[A-Za-z\s]+"
              title="Only letters are allowed"
              phx_hook="LettersOnly"
            />
            <.sf
              field={@form[:last_name]}
              label="Last Name"
              placeholder="Forger"
              pattern="[A-Za-z\s]+"
              title="Only letters are allowed"
              phx_hook="LettersOnly"
            />
          </div>
          <div class="mt-3">
            <.sf field={@form[:email]} label="Email" type="email" placeholder="student@college.edu" />
          </div>
          <div class="grid grid-cols-2 gap-3 mt-3">
            <.sf
              field={@form[:phone]}
              label="Mobile"
              placeholder="Enter Mobile Number"
              type="tel"
              inputmode="numeric"
              pattern="[0-9]{10}"
              title="Mobile number must be exactly 10 digits"
              maxlength="10"
              phx_hook="DigitsOnly"
            />
            <.sf
              field={@form[:registration_id]}
              label="Reg. No."
              placeholder="105"
              pattern="[A-Za-z0-9].*"
              title="Registration number must start with a letter or number"
            />
          </div>
        </div>

        <!-- Academic -->
        <div>
          <p class="text-[10px] font-bold uppercase tracking-widest text-gray-400 mb-3">Academic</p>
          <div class="space-y-3">
            <div>
              <label class="block text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 mb-1.5">Department</label>
              <select name={@form[:degree].name} id={@form[:degree].id} class={sinput()}>
                <option :for={{label, value} <- @degree_options} value={value} selected={to_string(@form[:degree].value) == to_string(value)}>{label}</option>
              </select>
            </div>
            <div>
              <label class="block text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 mb-1.5">Specialization</label>
              <select name={@form[:specialization].name} id={@form[:specialization].id} class={sinput()}>
                <option :for={{label, value} <- @specialization_options} value={value} selected={to_string(@form[:specialization].value) == to_string(value)}>{label}</option>
              </select>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <.sf field={@form[:cgpa]}            label="CGPA"           placeholder="8.7" />
              <.sf field={@form[:year_of_passing]} label="Year of Passing" type="number" placeholder="2026" />
            </div>
          </div>
        </div>

        <!-- Submit -->
        <div class="pt-2 flex gap-2">
          <button type="button" phx-click="close_sidebar"
            class="flex-1 px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-medium text-gray-600 hover:bg-gray-50 transition">
            Cancel
          </button>
          <button type="submit" disabled={@loading}
            class="flex-1 px-4 py-2.5 rounded-xl text-sm font-semibold text-white transition disabled:opacity-60"
            style="background-color: #F97316;">
            {if @loading, do: "Creating…", else: "Create Student"}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  # Sidebar form field component
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, default: ""
  attr :type, :string, default: "text"
  attr :pattern, :string, default: nil
  attr :title, :string, default: nil
  attr :inputmode, :string, default: nil
  attr :maxlength, :string, default: nil
  attr :phx_hook, :string, default: nil

  defp sf(assigns) do
    ~H"""
    <div>
      <label for={@field.id} class="block text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 mb-1.5">{@label}</label>
      <input
        type={@type}
        name={@field.name}
        id={@field.id}
        value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
        placeholder={@placeholder}
        pattern={@pattern}
        title={@title}
        inputmode={@inputmode}
        maxlength={@maxlength}
        data-maxlength={@maxlength}
        phx-hook={@phx_hook}
        class={sinput()}
      />
    </div>
    """
  end

  defp sinput do
    "w-full px-3 py-2.5 rounded-xl bg-gray-50 border border-gray-200 text-sm text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-100 focus:border-[#F97316]"
  end

  # ── Student Detail drawer ──────────────────────────────────────────────────

  attr :student, :map, required: true
  attr :ats_phase, :any, required: true
  attr :tenant_alias, :string, required: true
  attr :ai8_dims, :list, required: true
  attr :ai8, :map, required: true
  attr :attempts, :list, required: true

  defp detail_sidebar(assigns) do
    ~H"""
    <!-- Header -->
    <div class="flex items-center justify-between px-5 py-4 border-b border-gray-100 shrink-0">
      <h2 class="text-base font-bold text-gray-900">Student Profile</h2>
      <button phx-click="close_sidebar" class="w-8 h-8 rounded-lg hover:bg-gray-100 flex items-center justify-center text-gray-400 hover:text-gray-600 transition">
        <.icon name="hero-x-mark" class="w-5 h-5" />
      </button>
    </div>

    <!-- Scrollable body -->
    <div class="flex-1 overflow-y-auto px-5 py-5 space-y-5">
      <!-- Avatar + name -->
      <div class="flex items-center gap-4">
        <div class={["w-14 h-14 rounded-2xl flex items-center justify-center text-lg font-bold shrink-0", avatar_class(@student)]}>
          {row_initials(@student)}
        </div>
        <div class="min-w-0">
          <p class="font-bold text-gray-900 text-base flex items-center gap-1.5">
            {full_name(@student)}
            <.icon :if={verified?(@student)} name="hero-check-badge-solid" class="w-4 h-4 text-green-500" />
          </p>
          <p class="text-xs text-gray-400 mt-0.5">{@student.email || "—"}</p>
          <span class={["mt-1 inline-block px-2.5 py-0.5 rounded-full text-[10px] font-semibold", status_class(@student)]}>
            {status_label(@student)}
          </span>
        </div>
      </div>

      <!-- Info grid -->
      <div class="bg-gray-50 rounded-xl p-4 grid grid-cols-2 gap-3">
        <.info_row label="Registration"    value={@student.registration_id || "—"} />
        <.info_row label="Phone"           value={@student.phone || "—"} />
        <.info_row label="Department"      value={dept(@student)} />
        <.info_row label="Specialization"  value={@student.specialization || "—"} />
        <.info_row label="CGPA"            value={cgpa_display(@student)} />
        <.info_row label="Year of Passing" value={to_string(@student.year_of_passing || "—")} />
      </div>

      <!-- Uploaded Documents -->
      <div>
        <p class="text-[10px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-3">Documents</p>
        <div class="space-y-2">
          <!-- Resume -->
          <div class="flex items-center justify-between rounded-xl border border-gray-100 bg-gray-50 px-3.5 py-2.5">
            <div class="flex items-center gap-2.5 min-w-0">
              <div class={["w-7 h-7 rounded-lg flex items-center justify-center shrink-0",
                if(doc_present?(@ats_phase, :resume_url), do: "bg-orange-100", else: "bg-gray-100")]}>
                <.icon name="hero-document-text" class={["w-4 h-4", if(doc_present?(@ats_phase, :resume_url), do: "text-orange-600", else: "text-gray-400")]} />
              </div>
              <div class="min-w-0">
                <p class="text-xs font-semibold text-gray-700">Resume</p>
                <p class="text-[10px] text-gray-400 truncate">
                  {if doc_present?(@ats_phase, :resume_url), do: Path.basename(@ats_phase.resume_url), else: "Not uploaded"}
                </p>
              </div>
            </div>
            <div :if={doc_present?(@ats_phase, :resume_url)} class="ml-2 shrink-0 flex items-center gap-1.5">
              <a
                href={"/api/tenant/students/#{@student.id}/resume/#{Path.basename(@ats_phase.resume_url)}?tenant=#{@tenant_alias}&mode=view"}
                target="_blank"
                rel="noopener"
                onclick="event.stopPropagation()"
                title="View"
                class="inline-flex items-center justify-center w-6 h-6 rounded-lg text-orange-600 bg-orange-50 hover:bg-orange-100 transition"
              >
                <.icon name="hero-eye" class="w-3.5 h-3.5" />
              </a>
              <a
                href={"/api/tenant/students/#{@student.id}/resume/#{Path.basename(@ats_phase.resume_url)}?tenant=#{@tenant_alias}"}
                onclick="event.stopPropagation()"
                title="Download"
                class="inline-flex items-center justify-center w-6 h-6 rounded-lg text-orange-600 bg-orange-50 hover:bg-orange-100 transition"
              >
                <.icon name="hero-arrow-down-tray" class="w-3.5 h-3.5" />
              </a>
            </div>
            <span :if={!doc_present?(@ats_phase, :resume_url)} class="shrink-0 inline-flex items-center gap-1 px-2 py-1 rounded-lg text-[10px] font-semibold text-gray-400 bg-gray-100">
              <.icon name="hero-x-mark" class="w-3 h-3" /> Missing
            </span>
          </div>

          <!-- College ID Card -->
          <div class="flex items-center justify-between rounded-xl border border-gray-100 bg-gray-50 px-3.5 py-2.5">
            <div class="flex items-center gap-2.5 min-w-0">
              <div class={["w-7 h-7 rounded-lg flex items-center justify-center shrink-0",
                if(doc_present?(@ats_phase, :college_id_card_url), do: "bg-blue-100", else: "bg-gray-100")]}>
                <.icon name="hero-identification" class={["w-4 h-4", if(doc_present?(@ats_phase, :college_id_card_url), do: "text-blue-600", else: "text-gray-400")]} />
              </div>
              <div class="min-w-0">
                <p class="text-xs font-semibold text-gray-700">College ID Card</p>
                <p class="text-[10px] text-gray-400 truncate">
                  {if doc_present?(@ats_phase, :college_id_card_url), do: Path.basename(@ats_phase.college_id_card_url), else: "Not uploaded"}
                </p>
              </div>
            </div>
            <div :if={doc_present?(@ats_phase, :college_id_card_url)} class="ml-2 shrink-0 flex items-center gap-1.5">
              <a
                href={"/api/tenant/students/#{@student.id}/document/id_card?tenant=#{@tenant_alias}"}
                target="_blank"
                rel="noopener"
                onclick="event.stopPropagation()"
                title="View"
                class="inline-flex items-center justify-center w-6 h-6 rounded-lg text-blue-600 bg-blue-50 hover:bg-blue-100 transition"
              >
                <.icon name="hero-eye" class="w-3.5 h-3.5" />
              </a>
              <a
                href={"/api/tenant/students/#{@student.id}/document/id_card?tenant=#{@tenant_alias}&mode=download"}
                onclick="event.stopPropagation()"
                title="Download"
                class="inline-flex items-center justify-center w-6 h-6 rounded-lg text-blue-600 bg-blue-50 hover:bg-blue-100 transition"
              >
                <.icon name="hero-arrow-down-tray" class="w-3.5 h-3.5" />
              </a>
            </div>
            <span :if={!doc_present?(@ats_phase, :college_id_card_url)} class="shrink-0 inline-flex items-center gap-1 px-2 py-1 rounded-lg text-[10px] font-semibold text-gray-400 bg-gray-100">
              <.icon name="hero-x-mark" class="w-3 h-3" /> Missing
            </span>
          </div>

          <!-- Profile Photo (optional) -->
          <div class="flex items-center justify-between rounded-xl border border-gray-100 bg-gray-50 px-3.5 py-2.5">
            <div class="flex items-center gap-2.5 min-w-0">
              <div class={["w-7 h-7 rounded-lg flex items-center justify-center shrink-0",
                if(doc_present?(@ats_phase, :profile_picture_url), do: "bg-purple-100", else: "bg-gray-100")]}>
                <.icon name="hero-camera" class={["w-4 h-4", if(doc_present?(@ats_phase, :profile_picture_url), do: "text-purple-600", else: "text-gray-400")]} />
              </div>
              <div class="min-w-0">
                <p class="text-xs font-semibold text-gray-700">Profile Photo <span class="text-gray-400 font-normal">(optional)</span></p>
                <p class="text-[10px] text-gray-400 truncate">
                  {if doc_present?(@ats_phase, :profile_picture_url), do: Path.basename(@ats_phase.profile_picture_url), else: "Not uploaded"}
                </p>
              </div>
            </div>
            <div :if={doc_present?(@ats_phase, :profile_picture_url)} class="ml-2 shrink-0 flex items-center gap-1.5">
              <a
                href={"/api/tenant/students/#{@student.id}/document/profile_photo?tenant=#{@tenant_alias}"}
                target="_blank"
                rel="noopener"
                onclick="event.stopPropagation()"
                title="View"
                class="inline-flex items-center justify-center w-6 h-6 rounded-lg text-purple-600 bg-purple-50 hover:bg-purple-100 transition"
              >
                <.icon name="hero-eye" class="w-3.5 h-3.5" />
              </a>
              <a
                href={"/api/tenant/students/#{@student.id}/document/profile_photo?tenant=#{@tenant_alias}&mode=download"}
                onclick="event.stopPropagation()"
                title="Download"
                class="inline-flex items-center justify-center w-6 h-6 rounded-lg text-purple-600 bg-purple-50 hover:bg-purple-100 transition"
              >
                <.icon name="hero-arrow-down-tray" class="w-3.5 h-3.5" />
              </a>
            </div>
            <span :if={!doc_present?(@ats_phase, :profile_picture_url)} class="shrink-0 inline-flex items-center gap-1 px-2 py-1 rounded-lg text-[10px] font-semibold text-gray-400 bg-gray-100">
              <.icon name="hero-x-mark" class="w-3 h-3" /> Missing
            </span>
          </div>
        </div>
      </div>

      <!-- AI Readiness -->
      <div>
        <p class="text-[10px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-2">AI Readiness</p>
        <div class="flex items-center gap-3">
          <span class={["px-3 py-1.5 rounded-full text-sm font-semibold", readiness_class(@student)]}>
            {readiness_label(@student)}
          </span>
          <span class="text-2xl font-bold text-gray-900">{score_display(ai8_of(@student))}</span>
          <span class="text-sm text-gray-400">/ 100</span>
        </div>
        <div class="flex flex-wrap gap-1.5 mt-2">
          <span :for={tag <- student_tags(@student)} class={["inline-block px-2.5 py-0.5 rounded-full text-[10px] font-semibold", tag_class(tag)]}>{tag}</span>
        </div>
      </div>

      <!-- AI8 web (8-dimension radar) — same chart the student sees on their AI8 Overview -->
      <div>
        <div class="flex items-baseline justify-between mb-1">
          <p class="text-[10px] font-bold uppercase tracking-[0.1em] text-gray-400">AI8 Dimensions</p>
          <p class="text-[10px] text-gray-400">{@ai8.completed}/{@ai8.total} assessments · {@ai8.completion}%</p>
        </div>
        <div class="rounded-xl border border-gray-100 bg-[#FBFAF7] px-2 pt-2 pb-1">
          <.ai8_radar dims={@ai8_dims} class="w-full max-w-[290px] mx-auto" label_size="8px" />
        </div>
        <div class="grid grid-cols-2 gap-x-3 gap-y-1.5 mt-3">
          <div :for={d <- @ai8_dims} class="flex items-center justify-between gap-2">
            <span class="text-[11px] text-gray-500 truncate" title={d.label}>{VyaasaCampus.AI8.Dimensions.short_label(d.key)}</span>
            <span class={["text-[11px] font-bold shrink-0", if(d.score >= 80, do: "text-green-600", else: "text-[#EE6D18]")]}>{d.score}</span>
          </div>
        </div>
      </div>

      <!-- Module Scores -->
      <div>
        <p class="text-[10px] font-bold uppercase tracking-widest text-gray-400 mb-3">Module Scores</p>
        <div class="space-y-2.5">
          <.score_row label="Resume"                  score={Map.get(@student, :ats_score)}            color="bg-orange-400" />
          <.score_row label="Interactive Session"     score={Map.get(@student, :interview_score)}      color="bg-emerald-400" />
          <.score_row label="Objective / MCQs"        score={Map.get(@student, :mcq_percentage)}       color="bg-blue-400" />
          <.score_row label="JAM Session"             score={Map.get(@student, :jam_score)}            color="bg-amber-400" />
          <.score_row label="Situational & Behavioral" score={Map.get(@student, :behavioral_score)}     color="bg-violet-400" />
          <.score_row label="Psychometric Assessment" score={Map.get(@student, :psychometric_score)}   color="bg-pink-400" />
          <.score_row label="Case Studies"            score={Map.get(@student, :case_study_score)}     color="bg-teal-400" />
          <.score_row label="Mini Project"            score={Map.get(@student, :mini_project_score)}   color="bg-indigo-400" />
        </div>
      </div>

      <!-- Attempts: usage against the tenant's limit, with a grant action -->
      <div :if={@attempts != []}>
        <p class="text-[10px] font-bold uppercase tracking-widest text-gray-400 mb-2">Attempts</p>
        <div class="space-y-1.5">
          <div :for={a <- @attempts} class="flex items-center justify-between gap-2 text-xs">
            <span class="text-gray-600 truncate">{a.label}</span>
            <div class="flex items-center gap-2 shrink-0">
              <span class={[
                "font-semibold tabular-nums",
                if(a.blocked?, do: "text-red-600", else: "text-gray-700")
              ]}>
                {a.used}/{a.limit}
              </span>
              <span :if={a.granted > 0} class="text-[10px] text-emerald-600" title="Includes granted attempts">
                +{a.granted}
              </span>
              <button
                phx-click="grant_attempt"
                phx-value-module={a.module}
                data-confirm={"Grant #{full_name(@student)} one more #{a.label} attempt?"}
                class="px-2 py-0.5 rounded-md text-[10px] font-semibold text-orange-700 bg-orange-50 border border-orange-200 hover:bg-orange-100"
              >
                +1
              </button>
            </div>
          </div>
        </div>
        <p class="text-[10px] text-gray-400 mt-1.5">
          Only assessments with a limit are listed. Grants are logged against your account.
        </p>
      </div>

      <!-- Verify action -->
      <div class="pt-1 space-y-2">
        <button
          :if={can_verify_full?(@student, @ats_phase)}
          phx-click="verify_student"
          phx-value-student_id={@student.id}
          phx-disable-with="Verifying..."
          data-confirm={"Verify #{full_name(@student)}?"}
          class="w-full py-2.5 rounded-xl text-sm font-semibold text-white bg-emerald-500 hover:bg-emerald-600 transition flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-wait"
        >
          <.icon name="hero-check-badge" class="w-4 h-4" /> Verify Student
        </button>
        <div :if={!can_verify_full?(@student, @ats_phase) and @student.status in ["unverified", "pending"]}
          class="rounded-xl border border-amber-100 bg-amber-50 p-3 text-center">
          <p class="text-xs font-semibold text-amber-700">Cannot verify yet</p>
          <p class="text-[10px] text-amber-600 mt-0.5">
            {verify_block_reason(@student, @ats_phase)}
          </p>
        </div>
        <!-- Resend invite — only for students who haven't completed their profile yet -->
        <button
          :if={@student.status in ["unverified", "pending"]}
          phx-click="resend_invite"
          phx-value-student_id={@student.id}
          data-confirm={"Resend profile-completion invite to #{@student.email}?"}
          class="w-full py-2.5 rounded-xl text-sm font-semibold text-indigo-700 bg-indigo-50 hover:bg-indigo-100 transition flex items-center justify-center gap-2"
        >
          <.icon name="hero-envelope" class="w-4 h-4" /> Resend Invite
        </button>
        <p :if={@student.status not in ["unverified", "pending"]} class="text-center text-xs text-gray-400">
          No pending actions for this student.
        </p>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp info_row(assigns) do
    ~H"""
    <div>
      <p class="text-[9px] font-bold uppercase tracking-widest text-gray-400">{@label}</p>
      <p class="text-sm font-medium text-gray-700 mt-0.5 truncate">{@value}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :score, :any, required: true
  attr :color, :string, required: true

  defp score_row(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-1">
        <span class="text-xs text-gray-600">{@label}</span>
        <span class="text-xs font-semibold text-gray-700">
          {if is_nil(@score) or score_num(@score) == 0, do: "—", else: "#{round(score_num(@score))}"}
        </span>
      </div>
      <div class="h-1.5 bg-gray-100 rounded-full overflow-hidden">
        <div class={["h-full rounded-full transition-all", @color]} style={"width: #{min(100, round(score_num(@score || 0)))}%"} />
      </div>
    </div>
    """
  end

  # The 8-dimension AI8 breakdown behind the radar in the detail drawer. Loaded
  # per-open (not with the list) so the students table stays cheap.
  defp assign_ai8_detail(socket, student_id, schema) do
    profile = AI8.ai8_index(student_id, schema)

    socket
    |> assign(:sidebar_ai8_dims, AI8Radar.dims_from_profile(profile))
    |> assign(:sidebar_ai8, %{
      index: round(profile.index || 0),
      completion: round(profile.completion || 0),
      completed: Map.get(profile, :modules_completed, 0),
      total: Map.get(profile, :modules_total, 0)
    })
    |> assign(:sidebar_attempts, attempt_rows(student_id, socket.assigns.tenant, schema))
  rescue
    e ->
      require Logger
      Logger.error("AI8 detail load failed for #{student_id}: #{Exception.message(e)}")

      socket
      |> assign(:sidebar_ai8_dims, AI8Radar.dims_from_profile(nil))
      |> assign(:sidebar_ai8, %{index: 0, completion: 0, completed: 0, total: 0})
      |> assign(:sidebar_attempts, [])
  end

  # Only assessments the tenant actually caps are listed — an unlimited tenant
  # sees no Attempts section at all rather than eight "0/∞" rows.
  @attempt_order ~w(resume interview mcq jam behavioral psychometric case_study mini_project)

  defp attempt_rows(student_id, tenant, schema) do
    modules =
      @attempt_order ++ (Entitlements.attempt_modules() -- @attempt_order)

    Enum.flat_map(modules, fn module ->
      case AttemptGuard.status(student_id, module, tenant.id, schema) do
        %{limit: nil} ->
          []

        st ->
          [Map.merge(st, %{module: module, label: attempt_label(module)})]
      end
    end)
  rescue
    _ -> []
  end

  defp attempt_label("resume"), do: "Resume Insights"
  defp attempt_label("interview"), do: "Interactive Session"
  defp attempt_label("mcq"), do: "Objective / MCQs"
  defp attempt_label("jam"), do: "JAM Session"
  defp attempt_label("behavioral"), do: "Situational & Behavioral"
  defp attempt_label("psychometric"), do: "Psychometric Assessment"
  defp attempt_label("case_study"), do: "Case Studies"
  defp attempt_label("mini_project"), do: "Mini Project"
  defp attempt_label(other), do: other

  # ── Data loading ──────────────────────────────────────────────────────────

  defp load_students(socket, page) do
    tenant_schema = socket.assigns.tenant.schema_name
    all = DashboardLive.load_all_students_with_scores(tenant_schema, :all)

    stats = compute_stats(all)
    dept_options = all |> Enum.map(&dept/1) |> Enum.reject(&(&1 == "—")) |> Enum.uniq() |> Enum.sort()
    year_options = all |> Enum.map(& &1.year_of_passing) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

    filtered = filter_students(all, socket)
    filtered_count = length(filtered)
    total_pages = total_pages(filtered_count, @per_page)
    page = page |> max(1) |> min(total_pages)

    socket
    |> assign(:stats, stats)
    |> assign(:all_students, all)
    |> assign(:dept_options, dept_options)
    |> assign(:year_options, year_options)
    |> assign(:total_students, length(all))
    |> assign(:filtered_count, filtered_count)
    |> assign(:current_page, page)
    |> assign(:students, paginate(filtered, page, @per_page))
  end

  defp compute_stats(students) do
    %{
      total: length(students),
      placement_ready: Enum.count(students, &(ai8_of(&1) >= 65)),
      high_potential: Enum.count(students, &(ai8_of(&1) >= 75)),
      needs_mentoring: Enum.count(students, fn s -> v = ai8_of(s); v > 0 and v < 45 end),
      incomplete: Enum.count(students, &(&1.status in ["pending", "profile_incomplete"]))
    }
  end

  defp filter_students(students, socket) do
    students
    |> apply_search(socket.assigns[:search_term] || "")
    |> apply_status(socket.assigns[:status_filter] || "all")
    |> apply_department(socket.assigns[:department_filter] || "all")
    |> apply_year(socket.assigns[:year_filter] || "all")
  end

  defp apply_search(students, t) when t in [nil, ""], do: students

  defp apply_search(students, t) do
    lc = String.downcase(t)
    Enum.filter(students, fn s ->
      [s.first_name, s.last_name, s.email, s.registration_id]
      |> Enum.any?(fn v -> v && String.contains?(String.downcase(v), lc) end)
    end)
  end

  defp apply_status(students, "all"), do: students
  defp apply_status(students, "verified"), do: Enum.filter(students, &verified?/1)
  defp apply_status(students, "unverified"), do: Enum.filter(students, &(not verified?(&1)))

  defp apply_department(students, "all"), do: students
  defp apply_department(students, d), do: Enum.filter(students, &(dept(&1) == d))

  defp apply_year(students, "all"), do: students
  defp apply_year(students, y), do: Enum.filter(students, &(to_string(&1.year_of_passing) == y))

  defp paginate(list, page, per), do: list |> Enum.drop((page - 1) * per) |> Enum.take(per)
  defp total_pages(t, _) when t <= 0, do: 1
  defp total_pages(t, per), do: div(t - 1, per) + 1

  defp page_range_label(_, _, 0), do: "Showing 0"
  defp page_range_label(page, per, total), do: "Showing #{(page - 1) * per + 1}–#{min(page * per, total)}"

  defp parse_page(nil), do: 1
  defp parse_page(n) when is_integer(n) and n >= 1, do: n
  defp parse_page(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} when n >= 1 -> n
      _ -> 1
    end
  end
  defp parse_page(_), do: 1

  defp page_path(socket, page), do: ~p"/user/#{socket.assigns.tenant_alias}/dashboard/students?page=#{page}"

  # ── Presentation helpers ──────────────────────────────────────────────────

  defp full_name(s), do: String.trim("#{s.first_name} #{s.last_name}")
  defp dept(s), do: s.specialization || s.degree || "—"

  defp cgpa_display(s) do
    case s.cgpa do
      nil -> "—"
      %Decimal{} = d -> d |> Decimal.round(1) |> Decimal.to_string()
      v when is_float(v) -> :erlang.float_to_binary(v, decimals: 1)
      v when is_integer(v) -> "#{v}.0"
      _ -> "—"
    end
  end

  defp row_initials(s) do
    [s.first_name, s.last_name]
    |> Enum.map(&(&1 && String.first(&1)))
    |> Enum.reject(&is_nil/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
    |> then(fn str -> if str == "", do: "?", else: str end)
  end

  @palette [
    "bg-orange-100 text-orange-700", "bg-blue-100 text-blue-700",
    "bg-emerald-100 text-emerald-700", "bg-purple-100 text-purple-700",
    "bg-pink-100 text-pink-700", "bg-amber-100 text-amber-700"
  ]

  defp avatar_class(s) do
    Enum.at(@palette, :erlang.phash2(s.id || full_name(s), length(@palette)))
  end

  defp ai8_of(s) do
    case Map.get(s, :ai8_score) do
      nil -> 0
      %Decimal{} = d -> Decimal.to_float(d)
      n when is_number(n) -> n
      _ -> 0
    end
  end

  defp score_num(nil), do: 0
  defp score_num(%Decimal{} = d), do: Decimal.to_float(d)
  defp score_num(n) when is_number(n), do: n
  defp score_num(_), do: 0

  defp score_display(0), do: "—"
  defp score_display(v), do: "#{round(v)}"

  defp readiness_band(s) do
    case ai8_of(s) do
      v when v >= 85 -> "elite"
      v when v >= 75 -> "high"
      v when v >= 65 -> "ready"
      v when v >= 50 -> "emerging"
      v when v >= 35 -> "mentoring"
      v when v > 0 -> "developing"
      _ -> "unassessed"
    end
  end

  defp readiness_label(s) do
    case readiness_band(s) do
      "elite" -> "Elite Talent"
      "high" -> "High Potential"
      "ready" -> "Placement Ready"
      "emerging" -> "Emerging Talent"
      "mentoring" -> "Needs Mentoring"
      "developing" -> "Developing"
      _ -> "Not Assessed"
    end
  end

  defp readiness_class(s) do
    case readiness_band(s) do
      "elite" -> "bg-indigo-100 text-indigo-700"
      "high" -> "bg-blue-100 text-blue-700"
      "ready" -> "bg-emerald-100 text-emerald-700"
      "emerging" -> "bg-amber-100 text-amber-700"
      "mentoring" -> "bg-orange-100 text-orange-700"
      "developing" -> "bg-gray-100 text-gray-500"
      _ -> "bg-gray-100 text-gray-400"
    end
  end

  defp student_tags(s) do
    v = ai8_of(s)
    interview = score_num(Map.get(s, :interview_score))
    jam = score_num(Map.get(s, :jam_score))

    []
    |> then(fn t -> if v >= 85, do: ["Top Performer" | t], else: t end)
    |> then(fn t -> if v >= 80 and v < 85, do: ["High Potential" | t], else: t end)
    |> then(fn t -> if interview >= 75, do: ["Leadership Candidate" | t], else: t end)
    |> then(fn t -> if v >= 65 and v < 75, do: ["Placement Ready" | t], else: t end)
    |> then(fn t -> if v >= 50 and v < 65, do: ["Internship Ready" | t], else: t end)
    |> then(fn t -> if jam > 0 and jam < 40, do: t ++ ["Communication Risk"], else: t end)
    |> then(fn t -> if v > 0 and v < 35, do: t ++ ["Needs Mentoring"], else: t end)
    |> Enum.take(3)
  end

  defp tag_class("Top Performer"),        do: "bg-emerald-50 text-emerald-700"
  defp tag_class("High Potential"),       do: "bg-blue-50 text-blue-600"
  defp tag_class("Leadership Candidate"), do: "bg-indigo-50 text-indigo-600"
  defp tag_class("Placement Ready"),      do: "bg-teal-50 text-teal-600"
  defp tag_class("Internship Ready"),     do: "bg-amber-50 text-amber-600"
  defp tag_class("Communication Risk"),   do: "bg-red-50 text-red-500"
  defp tag_class("Needs Mentoring"),      do: "bg-orange-50 text-orange-500"
  defp tag_class(_),                      do: "bg-gray-100 text-gray-500"

  # Table row: show Verify when status is pending/unverified AND resume is uploaded.
  # resume_url is merged onto student by enhance_student_with_ats_data — no extra DB call.
  defp can_verify_row?(s) do
    s.status in ["unverified", "pending"] and not is_nil_or_blank(Map.get(s, :resume_url))
  end

  # Sidebar: requires resume + college ID card (the two mandatory docs for full verification).
  defp can_verify_full?(s, ats_phase) do
    s.status in ["unverified", "pending"] and
      doc_present?(ats_phase, :resume_url) and
      doc_present?(ats_phase, :college_id_card_url)
  end

  defp verify_block_reason(s, ats_phase) do
    missing =
      []
      |> then(fn m -> if doc_present?(ats_phase, :resume_url), do: m, else: ["resume" | m] end)
      |> then(fn m -> if doc_present?(ats_phase, :college_id_card_url), do: m, else: ["college ID card" | m] end)

    if missing == [] do
      "Status: #{status_label(s)}"
    else
      "Waiting for: #{Enum.join(Enum.reverse(missing), " and ")}"
    end
  end

  defp doc_present?(nil, _key), do: false
  defp doc_present?(ats, key), do: not is_nil_or_blank(Map.get(ats, key))

  defp is_nil_or_blank(nil), do: true
  defp is_nil_or_blank(""), do: true
  defp is_nil_or_blank(s) when is_binary(s), do: String.trim(s) == ""
  defp is_nil_or_blank(_), do: false

  defp fetch_ats_phase(student_id, tenant_schema) do
    StudentAts.get_by_student_id(student_id, tenant_schema)
  rescue
    _ -> nil
  end

  defp verified?(s), do: s.status in ["verified", "active"]
  defp selected?(_s, nil), do: false
  defp selected?(s, sel), do: to_string(s.id) == to_string(sel.id)

  defp status_label(s) do
    case s.status do
      "verified" -> "Verified"
      "active" -> "Active"
      "unverified" -> "Unverified"
      "pending" -> "Pending"
      "profile_incomplete" -> "Incomplete"
      other -> other |> to_string() |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp status_class(s) do
    case s.status do
      st when st in ["verified", "active"] -> "bg-emerald-100 text-emerald-700"
      "unverified" -> "bg-amber-100 text-amber-700"
      "profile_incomplete" -> "bg-red-50 text-red-500"
      _ -> "bg-gray-100 text-gray-500"
    end
  end

  defp fsel do
    "rounded-lg border border-gray-200 bg-white text-sm text-gray-600 py-2 pl-3 pr-8 focus:outline-none focus:ring-2 focus:ring-orange-100 focus:border-[#F97316] cursor-pointer"
  end

  defp blank_create_form do
    %Student{} |> Student.changeset(%{}) |> to_form()
  end

  defp load_degree_options(tenant_id) do
    Academics.get_tenant_degree_options(tenant_id)
  rescue
    _ -> {[{"Select department", ""}], [{"Select specialization", ""}]}
  end

  defp load_specializations_by_degree(tenant_id) do
    Academics.get_tenant_specializations_by_degree(tenant_id)
  rescue
    _ -> %{}
  end

  # Specialization options scoped to the chosen department, so students_live's
  # dropdown never shows specializations (or duplicate names) from other
  # degrees. No department selected yet → just the placeholder.
  defp specialization_options_for(specializations_by_degree, degree_name) do
    case Map.get(specializations_by_degree, degree_name) do
      nil -> [{"Select specialization", ""}]
      specs -> [{"Select specialization", ""} | specs]
    end
  end

  defp changeset_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map(fn {field, errs} ->
      "#{Phoenix.Naming.humanize(field)}: #{Enum.join(errs, ", ")}"
    end)
  end

  defp get_user_info(nil), do: %{name: "Unknown User", role: "Placement Coordinator", email: ""}

  defp get_user_info(u) do
    %{
      name: String.trim("#{u.first_name} #{u.last_name}"),
      role: u.role || "Placement Coordinator",
      email: u.email || ""
    }
  end
end
