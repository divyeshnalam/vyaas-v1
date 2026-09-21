defmodule VyaasaCampusWeb.TenantUser.DashboardLive do
  @moduledoc """
  LiveView for tenant admin dashboard.
  Provides overview of tenant operations, user management, and system status.
  """

  use VyaasaCampusWeb, :live_view

  alias Ecto.Adapters.SQL
  alias VyaasaCampus.Contexts.Assessments
  alias VyaasaCampus.Contexts.Students
  alias VyaasaCampus.Contexts.StudentRankings
  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Contexts.Tenant.JobProfiles
  alias VyaasaCampus.Contexts.StudentAts
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.Student
  alias VyaasaCampusWeb.DateTimeFormatter
  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.TenantUser.AddStudentComponent
  import Phoenix.LiveView

  @impl true
  def mount(%{"tenant" => tenant_alias}, session, socket) do
    require Logger

    Logger.info("Dashboard mount - tenant_alias from URL: #{tenant_alias}")

    # Get information from assigns (set by AuthPlug and ScopePlug)
    current_user = socket.assigns[:current_user]
    scope = socket.assigns[:scope]

    Logger.info("Dashboard mount - current_user: #{inspect(current_user)}")
    Logger.info("Dashboard mount - scope: #{inspect(scope)}")
    Logger.info("Dashboard mount - session keys: #{inspect(Map.keys(session))}")

    # Check if user is authenticated
    if is_nil(current_user) do
      Logger.warning("Dashboard mount - No authenticated user, redirecting to login")
      {:ok, push_navigate(socket, to: ~p"/auth/tenant/#{tenant_alias}/login")}
    else
      # Get user information
      user_info = get_user_info(current_user)

      # Get tenant information using the alias from URL (case-insensitive lookup)
      tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
      tenant_schema = if tenant, do: tenant.schema_name, else: nil

      Logger.info("Dashboard mount - tenant: #{inspect(tenant)}")
      Logger.info("Dashboard mount - tenant_schema: #{tenant_schema}")

      if connected?(socket) and tenant_schema do
        DashboardEvents.subscribe_tenant(tenant_schema)
      end

      # Load students and log the result
      # Default filter
      initial_filter = "verified"

      initial_students =
        if tenant_schema do
          students = load_students_by_filter(tenant_schema, initial_filter)
          Logger.info("🎯 Dashboard mount: Loaded #{length(students)} verified students")
          students
        else
          Logger.warning("⚠️ Dashboard mount: No tenant schema, loading empty list")
          []
        end

      # Load ALL students (raw) and scored students for statistics
      {all_raw_students, all_scored_students} =
        if tenant_schema do
          raw = Students.list_students(tenant_schema)
          scored = load_all_students_with_scores(tenant_schema)
          {raw, scored}
        else
          {[], []}
        end

      # Compute dashboard analytics
      overview_stats = StudentRankings.get_full_overview_stats(all_raw_students, all_scored_students)
      alerts = StudentRankings.get_alerts(all_raw_students, all_scored_students)
      department_stats = StudentRankings.get_department_stats(all_scored_students)
      assessment_stats = StudentRankings.get_assessment_stats(all_scored_students)
      assessment_toppers = StudentRankings.get_assessment_toppers(all_scored_students, 5)
      low_performers = StudentRankings.get_low_performers(all_scored_students, 40)
      year_wise_stats = StudentRankings.get_year_wise_stats(all_scored_students)
      cgpa_data = StudentRankings.get_cgpa_correlation(all_scored_students)
      ats_distribution = StudentRankings.get_ats_distribution(all_scored_students)

      socket =
        socket
        |> assign(:tenant_alias, tenant_alias)
        |> assign(:tenant_schema, tenant_schema)
        |> assign(:tenant, tenant)
        |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: tenant_alias))
        |> assign(:current_scope, :tenant_admin)
        |> assign(:page_title, "Dashboard - #{if(tenant, do: tenant.full_name, else: tenant_alias)}")
        |> assign(:loading?, false)
        |> assign(:error_message, nil)
        |> assign(:current_user, current_user)
        |> assign(:user_info, user_info)
        |> assign(:tenant_not_found?, !tenant)
        |> assign(:scope, scope)
        |> assign(:current_section, "dashboard")
        |> assign(:student_filter, initial_filter)
        |> assign(:student_search, "")
        |> assign(:student_year, "")
        |> assign(:student_year_options, unique_student_years(all_raw_students))
        |> assign(:students, initial_students)
        # Retained so targeted refreshes can recompute aggregates without re-querying.
        |> assign(:raw_students, all_raw_students)
        |> assign(:pending_student_ids, MapSet.new())
        |> assign(:admin_tab, "overview")
        |> assign(:overview_stats, overview_stats)
        |> assign(:alerts, alerts)
        |> assign(:department_stats, department_stats)
        |> assign(:assessment_stats, assessment_stats)
        |> assign(:assessment_toppers, assessment_toppers)
        |> assign(:low_performers, low_performers)
        |> assign(:year_wise_stats, year_wise_stats)
        |> assign(:cgpa_data, cgpa_data)
        |> assign(:ats_distribution, ats_distribution)
        |> assign(:leaderboard_department, "all")
        |> assign(:leaderboard_specialization, "all")
        |> assign(:leaderboard_year, "all")
        |> assign(:selected_spec, nil)
        |> assign(:selected_spec_students, [])
        |> assign(:drawer, nil)
        |> put_leaderboard_assigns(all_scored_students)
        |> assign(:show_resume_modal, false)
        |> assign(:resume_url, nil)
        |> assign(:resume_student_id, nil)
        |> assign(:resume_student_name, nil)
        |> assign(:resume_filename, nil)
        |> assign(:active_menu, nil)
        |> assign(:sort_by, "ai8_score")
        |> assign(:sort_dir, "desc")
        |> assign(:dashboard_students_page, 1)
        |> assign(:dashboard_students_per_page, 25)
        |> assign(:job_roles, load_job_roles(tenant, tenant_schema))
        |> assign_degree_options(tenant)
        |> setup_initial_view()

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Read filter from URL params if present
    filter = params["filter"] || socket.assigns.student_filter || "verified"

    # Only reload if filter has changed
    socket =
      if filter != socket.assigns.student_filter do
        tenant_schema = socket.assigns.tenant_schema
        students = load_students_by_filter(tenant_schema, filter)

        socket
        |> assign(:student_filter, filter)
        |> assign(:students, students)
      else
        socket
      end

    # Active section is driven by the sidebar via ?tab= (overview is the default).
    tab = params["tab"] || "overview"

    socket =
      socket
      |> assign(:admin_tab, tab)
      |> assign(:current_section, tab_to_section(tab))

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp tab_to_section("leaderboard"), do: "leaderboard"
  defp tab_to_section("departments"), do: "specializations"
  defp tab_to_section("readiness"), do: "placement_readiness"
  defp tab_to_section(_), do: "dashboard"

  @impl true
  def handle_event("show_coming_soon", _params, socket) do
    {:noreply, put_flash(socket, :info, "Coming soon!")}
  end

  @impl true
  def handle_event("show_add_student", _params, socket) do
    tenant_alias = socket.assigns.tenant_alias
    {:noreply, push_patch(socket, to: "/user/#{tenant_alias}/dashboard/addstudent")}
  end

  @impl true
  def handle_event("hide_add_student", _params, socket) do
    tenant_alias = socket.assigns.tenant_alias
    {:noreply, push_patch(socket, to: "/user/#{tenant_alias}/dashboard")}
  end

  @impl true
  def handle_event("filter_students", params, socket) do
    require Logger

    filter = params["filter"] || socket.assigns.student_filter
    search = params["search"] || socket.assigns[:student_search] || ""
    year = params["year"] || socket.assigns[:student_year] || ""

    Logger.info("🔄 Dashboard: Filter change requested to '#{filter}', search: '#{search}', year: '#{year}'")

    tenant_schema = socket.assigns.tenant_schema
    students = load_students_by_filter(tenant_schema, filter)

    # Apply additional filters if needed
    students = apply_search_filter(students, search)
    students = apply_year_filter(students, year)

    Logger.info("📊 Dashboard: Filter '#{filter}' returned #{length(students)} students")

    # Update URL with filter parameter
    tenant_alias = socket.assigns.tenant_alias

    socket =
      socket
      |> assign(:student_filter, filter)
      |> assign(:student_search, search)
      |> assign(:student_year, year)
      |> assign(:students, students)
      |> assign(:student_year_options, unique_student_years(Students.list_students(tenant_schema)))
      |> assign(:dashboard_students_page, 1)
      |> push_patch(to: ~p"/user/#{tenant_alias}/dashboard?filter=#{filter}")
      |> push_event("show_toast", %{
        type: "info",
        message: "Showing #{length(students)} #{get_filter_display_name(filter)} students",
        duration: 3000
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_new_student", %{"student" => student_params}, socket) do
    alias VyaasaCampus.Schema.Students.Student

    merged_params = merge_form_params(socket.assigns.add_student_form, student_params)
    changeset = validate_student_changeset(merged_params)
    form = to_form(changeset, as: :student)

    {:noreply, assign(socket, :add_student_form, form)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    require Logger
    Logger.info("🔄 Dashboard: Manual refresh requested")

    # Refresh the page data
    tenant_schema = socket.assigns.tenant_schema
    current_filter = socket.assigns.student_filter
    students = load_students_by_filter(tenant_schema, current_filter)

    Logger.info("📊 Dashboard: Refresh loaded #{length(students)} students with filter '#{current_filter}'")

    socket =
      socket
      |> assign(:students, students)
      |> assign(:dashboard_students_page, 1)
      |> put_flash(
        :info,
        "Dashboard refreshed - showing #{length(students)} #{get_filter_display_name(current_filter)} students"
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("view_resume", %{"student_id" => student_id, "filename" => filename}, socket) do
    require Logger
    Logger.info("Viewing resume for student: #{student_id}, filename: #{filename}")

    # Find the student to get their name
    student = Enum.find(socket.assigns.students, &(&1.id == student_id))
    student_name = if student, do: "#{student.first_name} #{student.last_name}", else: "Unknown Student"

    # Construct the resume URL for the iframe (include tenant query param for auth)
    tenant_alias = socket.assigns.tenant_alias
    resume_url = "/api/tenant/students/#{student_id}/resume/#{filename}?tenant=#{tenant_alias}"

    socket =
      socket
      |> assign(:show_resume_modal, true)
      |> assign(:resume_url, resume_url)
      |> assign(:resume_student_id, student_id)
      |> assign(:resume_student_name, student_name)
      |> assign(:resume_filename, filename)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_resume_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_resume_modal, false)
      |> assign(:resume_url, nil)
      |> assign(:resume_student_id, nil)
      |> assign(:resume_student_name, nil)
      |> assign(:resume_filename, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("download_resume", %{"student_id" => student_id, "filename" => filename}, socket) do
    tenant_alias = socket.assigns.tenant_alias

    # Construct the download URL with proper tenant header
    download_url = "/api/tenant/students/#{student_id}/resume/#{filename}"

    # Use push_event to trigger a download with proper headers
    socket =
      socket
      |> push_event("download_file", %{
        url: download_url,
        headers: %{"x-tenant" => tenant_alias}
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("verify_student", %{"student_id" => student_id}, socket) do
    require Logger
    Logger.info("Verifying student: #{student_id}")

    alias VyaasaCampus.Contexts.Students
    tenant_alias = socket.assigns.tenant_alias
    tenant_schema = socket.assigns.tenant_schema

    case Students.verify_student_and_notify(student_id, tenant_alias, tenant_schema) do
      {:ok, _final_student, email_result} ->
        # Reload students to show updated list
        current_filter = socket.assigns.student_filter
        students = load_students_by_filter(tenant_schema, current_filter)
        socket = assign(socket, :students, students)

        case email_result do
          {:ok, :email_sent} ->
            {:noreply,
             put_flash(
               socket,
               :info,
               "Student profile verified successfully! Email sent with temporary password."
             )}

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :warning,
               "Student verified, but the temporary-password email could NOT be sent. " <>
                 "Please check email settings and use “Resend” to try again."
             )}
        end

      {:error, changeset} ->
        Logger.error("Failed to verify student #{student_id}: #{inspect(changeset.errors)}")

        {:noreply,
         socket
         |> put_flash(:error, "Failed to verify student profile. Please try again.")}
    end
  end

  @impl true
  def handle_event("toggle_menu", %{"student_id" => student_id}, socket) do
    active_menu =
      if socket.assigns.active_menu == student_id, do: nil, else: student_id

    {:noreply, assign(socket, :active_menu, active_menu)}
  end

  @impl true
  def handle_event("close_menu", _params, socket) do
    {:noreply, assign(socket, :active_menu, nil)}
  end

  @impl true
  def handle_event("reset_assessment", %{"student_id" => student_id}, socket) do
    require Logger
    Logger.info("Resetting assessment for student: #{student_id}")

    tenant_schema = socket.assigns.tenant_schema

    {:ok, count} = Assessments.reset_student_assessment(student_id, tenant_schema)

    # Reload students to refresh assessment status
    current_filter = socket.assigns.student_filter
    students = load_students_by_filter(tenant_schema, current_filter)

    {:noreply,
     socket
     |> put_flash(:info, "Assessment reset successfully! (#{count} attempt(s) cleared)")
     |> assign(:students, students)
     |> assign(:active_menu, nil)}
  end

  @impl true
  def handle_event("update_student_role", %{"student_id" => student_id, "role" => role}, socket) do
    require Logger
    Logger.info("Updating preferred role for student #{student_id} to #{role}")

    tenant_schema = socket.assigns.tenant_schema

    case StudentAts.get_by_student_id(student_id, tenant_schema) do
      nil ->
        {:noreply, put_flash(socket, :error, "No resume profile found for this student")}

      ats_phase ->
        case StudentAts.update_ats_fields(ats_phase, %{preferred_role: role}, tenant_schema) do
          {:ok, _} ->
            students =
              Enum.map(socket.assigns.students, fn s ->
                if s.id == student_id, do: Map.put(s, :preferred_role, role), else: s
              end)

            {:noreply, assign(socket, :students, students)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update role")}
        end
    end
  end

  @impl true
  def handle_event("save_new_student", %{"student" => student_params}, socket) do
    require Logger
    Logger.info("=== STUDENT CREATION DEBUG ===")
    Logger.info("Raw student params: #{inspect(student_params)}")
    Logger.info("Current user: #{inspect(socket.assigns.current_user)}")
    Logger.info("Tenant ID: #{inspect(socket.assigns.tenant.id)}")
    Logger.info("Tenant schema: #{inspect(socket.assigns.tenant_schema)}")

    # Set loading state
    socket = assign(socket, :loading?, true)

    # Get tenant information for the current context
    tenant_id = socket.assigns.tenant.id
    tenant_alias = socket.assigns.tenant_alias
    tenant_schema = socket.assigns.tenant_schema

    # Prepare params with tenant and user context
    context_params =
      student_params
      |> Map.put("tenant_id", tenant_id)
      |> Map.put("created_by_id", socket.assigns.current_user.id)
      |> Map.put("created_by_type", "tenant")
      # New students start as pending
      |> Map.put("status", "pending")

    case Students.create_student(context_params, tenant_alias, tenant_schema) do
      {:ok, student} ->
        Logger.info("Student created successfully: #{student.id}")

        {:noreply,
         socket
         |> assign(:loading?, false)
         |> assign(:show_add_student, false)
         |> put_flash(:info, "Student created successfully! Profile completion email sent.")
         |> push_navigate(to: "/user/#{tenant_alias}/dashboard")}

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("Student creation failed: #{inspect(changeset.errors)}")

        {:noreply,
         socket
         |> assign(:loading?, false)
         |> assign(:add_student_form, to_form(changeset))
         |> assign(:add_student_errors, changeset_errors(changeset))
         |> put_flash(:error, "Failed to create student. Please check the form and try again.")}

      {:error, reason} ->
        Logger.error("Student creation failed: #{reason}")

        {:noreply,
         socket
         |> assign(:loading?, false)
         |> put_flash(:error, "Failed to create student: #{reason}")}
    end
  end

  @impl true
  def handle_event("switch_admin_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :admin_tab, tab)}
  end

  # "Total Students" opens the dedicated Students page (which already has the
  # full table + filters) rather than rendering another table on the dashboard.
  def handle_event("show_category", %{"category" => "total"}, socket) do
    {:noreply, push_navigate(socket, to: "/user/#{socket.assigns.tenant_alias}/dashboard/students")}
  end

  # Clicking any other stat tile opens the right-side drawer with those students.
  def handle_event("show_category", %{"category" => category}, socket) do
    students = socket.assigns[:scored_students] || []

    {title, sub, list} =
      case category do
        "completion" ->
          {"Assessment Completion", "Students who have started assessments",
           Enum.filter(students, &has_any_assessment?/1)}

        "ready" ->
          {"Placement Ready", "AI8 score ≥ 70",
           students
           |> Enum.filter(&((Map.get(&1, :ai8_score) || 0) >= 70))
           |> sort_by_score_desc()}

        "scored" ->
          {"Avg AI8 Score", "Students with an AI8 score",
           students
           |> Enum.filter(&(not is_nil(Map.get(&1, :ai8_score))))
           |> sort_by_score_desc()}

        "top" ->
          {"Top Performers", "Highest AI8 scores",
           students
           |> Enum.filter(&(not is_nil(Map.get(&1, :ai8_score))))
           |> sort_by_score_desc()
           |> Enum.take(25)}

        "assessed" ->
          {"Fully Assessed", "Completed all core assessments", Enum.filter(students, &all_assessments_done?/1)}

        _ ->
          {"Students", nil, students}
      end

    {:noreply, toggle_drawer(socket, category, title, sub, list, :category)}
  end

  # Clicking an Intervention Center card opens the same drawer with those students.
  def handle_event("show_alert", %{"category" => category}, socket) do
    alerts = socket.assigns.alerts

    {title, sub, data} =
      case category do
        "low_performers" ->
          {"Low Performers", "AI8 score below 40", alerts.low_performers}

        "incomplete_profiles" ->
          {"Incomplete Profiles", "Profile pending completion", alerts.incomplete_profiles}

        "not_started" ->
          {"Not Started", "Verified but no assessments completed yet", alerts.not_started}

        "integrity_flags" ->
          {"Integrity Flags", "Recordings that need review", alerts.integrity_flags}

        _ ->
          {"Students", nil, %{students: []}}
      end

    {:noreply, toggle_drawer(socket, category, title, sub, data.students, category)}
  end

  # Clicking a specialization card opens the same drawer with that
  # specialization's students.
  def handle_event("show_specialization", %{"name" => name}, socket) do
    list =
      (socket.assigns[:scored_students] || [])
      |> Enum.filter(&((Map.get(&1, :specialization) || "Unknown") == name))
      |> sort_by_score_desc()

    {:noreply, toggle_drawer(socket, "spec:#{name}", name, nil, list, :category)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer, nil)}
  end

  # Download-icon on a stat tile: CSV of the same student list the tile's
  # drawer would show, without opening the drawer.
  def handle_event("download_category", %{"category" => "total"}, socket) do
    {:noreply, download_students_csv(socket, "total", socket.assigns[:scored_students] || [])}
  end

  def handle_event("download_category", %{"category" => category}, socket) do
    students = socket.assigns[:scored_students] || []

    list =
      case category do
        "completion" ->
          Enum.filter(students, &has_any_assessment?/1)

        "ready" ->
          students
          |> Enum.filter(&((Map.get(&1, :ai8_score) || 0) >= 70))
          |> sort_by_score_desc()

        "scored" ->
          students
          |> Enum.filter(&(not is_nil(Map.get(&1, :ai8_score))))
          |> sort_by_score_desc()

        "top" ->
          students
          |> Enum.filter(&(not is_nil(Map.get(&1, :ai8_score))))
          |> sort_by_score_desc()
          |> Enum.take(25)

        "assessed" ->
          Enum.filter(students, &all_assessments_done?/1)

        _ ->
          students
      end

    {:noreply, download_students_csv(socket, category, list)}
  end

  @impl true
  def handle_event("filter_leaderboard", params, socket) do
    dept = params["department"] || socket.assigns.leaderboard_department || "all"
    spec_input = params["specialization"] || socket.assigns.leaderboard_specialization || "all"
    year = params["year"] || socket.assigns[:leaderboard_year] || "all"

    # If the department changed, reset specialization since the previous one
    # may not exist within the new department.
    spec =
      if dept != socket.assigns.leaderboard_department, do: "all", else: spec_input

    socket =
      socket
      |> assign(:leaderboard_department, dept)
      |> assign(:leaderboard_specialization, spec)
      |> assign(:leaderboard_year, year)
      |> put_leaderboard_assigns(socket.assigns.scored_students || [])

    {:noreply, socket}
  end

  # The Export PDF button in the shared analytics header must export whatever
  # the admin is currently looking at, not always the same report.
  defp export_pdf_href(%{admin_tab: "leaderboard"} = assigns) do
    query =
      URI.encode_query(%{
        "department" => assigns.leaderboard_department,
        "specialization" => assigns.leaderboard_specialization,
        "year" => assigns.leaderboard_year
      })

    "/user/#{assigns.tenant_alias}/reports/leaderboard?#{query}"
  end

  defp export_pdf_href(%{admin_tab: "departments"} = assigns),
    do: "/user/#{assigns.tenant_alias}/reports/specialization"

  defp export_pdf_href(%{admin_tab: "readiness"} = assigns),
    do: "/user/#{assigns.tenant_alias}/reports/readiness"

  defp export_pdf_href(assigns), do: "/user/#{assigns.tenant_alias}/reports/analytics"

  @impl true
  def handle_event("show_spec_students", %{"spec" => spec}, socket) do
    students =
      (socket.assigns[:scored_students] || [])
      |> Enum.filter(fn s -> (Map.get(s, :specialization) || "Unknown") == spec end)
      |> Enum.sort_by(&(Map.get(&1, :ai8_score) || 0), :desc)

    {:noreply,
     socket
     |> assign(:selected_spec, spec)
     |> assign(:selected_spec_students, students)}
  end

  @impl true
  def handle_event("close_spec_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_spec, nil)
     |> assign(:selected_spec_students, [])}
  end

  @impl true
  def handle_event("sort_students", %{"field" => field}, socket) do
    current_sort = socket.assigns.sort_by
    current_dir = socket.assigns.sort_dir

    # Toggle direction if same field, otherwise default desc
    new_dir = if field == current_sort and current_dir == "desc", do: "asc", else: "desc"

    sorted_students = sort_students(socket.assigns.students, field, new_dir)

    {:noreply,
     socket
     |> assign(:sort_by, field)
     |> assign(:sort_dir, new_dir)
     |> assign(:students, sorted_students)
     |> assign(:dashboard_students_page, 1)}
  end

  @impl true
  def handle_event("goto_dashboard_students_page", %{"page" => page}, socket) do
    parsed =
      case Integer.parse(to_string(page)) do
        {n, _} when n >= 1 -> n
        _ -> 1
      end

    total = length(socket.assigns[:students] || [])
    per_page = socket.assigns[:dashboard_students_per_page] || 25
    total_pages = if total == 0, do: 1, else: div(total - 1, per_page) + 1
    parsed = parsed |> max(1) |> min(total_pages)

    {:noreply, assign(socket, :dashboard_students_page, parsed)}
  end

  @impl true
  def handle_event("logout", _params, socket) do
    # Handle logout - redirect to login page
    socket =
      socket
      |> put_flash(:info, "Logged out successfully")
      |> redirect(to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")

    {:noreply, socket}
  end

  # Extract form parameter merging logic
  defp merge_form_params(form, student_params) do
    current_params = get_current_form_params(form)
    clean_new_params = clean_params(student_params)

    Map.merge(current_params, clean_new_params, &merge_param_values/3)
  end

  # Extract parameter cleaning logic
  defp clean_params(params) do
    params
    |> Enum.reject(fn {k, _v} -> is_binary(k) and String.starts_with?(k, "_unused_") end)
    |> Map.new()
  end

  # Extract parameter merging logic
  defp merge_param_values(_key, current, new) do
    cond do
      # If new value is empty string or nil, keep current value
      new == "" or is_nil(new) -> current
      # If current value is empty and new has content, use new
      (current == "" or is_nil(current)) and new != "" -> new
      # If both have content, use new (user is changing it)
      new != "" -> new
      # Default to current
      true -> current
    end
  end

  # Extract changeset validation logic
  defp validate_student_changeset(params) do
    alias VyaasaCampus.Schema.Students.Student

    %Student{}
    |> Student.form_validation_changeset(params)
    |> Map.put(:action, :validate)
  end

  # Extract current form params logic
  defp get_current_form_params(form) do
    case form do
      %Phoenix.HTML.Form{params: params} when is_map(params) ->
        params
        |> clean_params()

      _ ->
        %{}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <!-- Toast Container -->
      <div id="toast-container" phx-hook="ToastContainer" class="fixed top-4 right-4 z-50 space-y-2"></div>

      <!-- Download Hook -->
      <div id="download-hook" phx-hook="DownloadFile" style="display: none;"></div>

      <!-- Shared students drawer (opened by stat tiles + intervention cards) -->
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
              <p class="text-[11px] text-gray-400 mt-0.5">
                {@drawer.sub}<span :if={@drawer.sub} class="mx-1">·</span>{length(@drawer.students)} students
              </p>
            </div>
            <button type="button" phx-click="close_drawer" class="text-gray-400 hover:text-gray-600 p-1 rounded-full hover:bg-gray-100" aria-label="Close">
              <.icon name="hero-x-mark" class="w-6 h-6" />
            </button>
          </div>
          <div class="flex-1 overflow-y-auto">
            <.link
              :for={{s, i} <- Enum.with_index(@drawer.students, 1)}
              navigate={"/user/#{@tenant_alias}/dashboard/students?student=#{Map.get(s, :id)}"}
              class="flex items-start gap-3 px-5 py-3 border-b border-gray-50 hover:bg-orange-50/30"
            >
              <span class="w-6 h-6 rounded-full bg-[#FFF4E7] text-[#F97316] text-[11px] font-bold flex items-center justify-center shrink-0 mt-0.5">{i}</span>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold text-gray-900 truncate">{Map.get(s, :first_name)} {Map.get(s, :last_name)}</p>
                <p class="text-[11px] text-gray-400 truncate">
                  {Map.get(s, :registration_id) || Map.get(s, :email) || "—"} · {Map.get(s, :specialization) || Map.get(s, :degree) || "—"}
                </p>
                <%= if @drawer.kind == "integrity_flags" do %>
                  <ul class="list-disc ml-4 mt-1 text-[11px] text-red-600 space-y-0.5">
                    <li :for={flag <- (Map.get(s, :integrity_flags) || [])}>{flag}</li>
                  </ul>
                <% else %>
                  <span class="inline-block mt-1 px-2 py-0.5 rounded-full text-[10px] font-semibold bg-gray-100 text-gray-600">{Map.get(s, :status) || "—"}</span>
                <% end %>
              </div>
              <div class="flex items-center gap-1 shrink-0 mt-0.5">
                <span class="text-sm font-bold text-[#F97316]">{Map.get(s, :ai8_score) || "—"}</span>
                <.icon name="hero-chevron-right" class="w-4 h-4 text-gray-300" />
              </div>
            </.link>
            <div :if={@drawer.students == []} class="text-center text-sm text-gray-400 py-16">
              No students in this category. 🎉
            </div>
          </div>
        <% end %>
      </div>

      <!-- Resume Modal -->
      <%= if @show_resume_modal do %>
        <div class="fixed inset-0 bg-gray-900 bg-opacity-75 overflow-y-auto h-full w-full z-50" id="resume-modal">
          <div class="relative top-4 mx-auto p-2 border w-[95vw] h-[95vh] max-w-none shadow-2xl rounded-lg bg-white flex flex-col">
            <!-- Modal Header -->
            <div class="flex items-center justify-between pb-3 border-b shrink-0">
              <h3 class="text-xl font-semibold text-gray-900">Resume - <%= @resume_student_name %></h3>
              <button
                phx-click="close_resume_modal"
                class="text-gray-400 hover:text-gray-600 transition-colors p-1 rounded-full hover:bg-gray-100"
              >
                <.icon name="hero-x-mark" class="w-7 h-7" />
              </button>
            </div>

            <!-- Modal Content -->
            <div class="flex-1 mt-3 overflow-hidden">
              <%= if @resume_url do %>
                <div class="w-full h-full border border-gray-300 rounded-lg overflow-hidden shadow-inner">
                  <iframe
                    src={@resume_url}
                    class="w-full h-full"
                    title="Resume Preview"
                    frameborder="0"
                  >
                    <div class="flex items-center justify-center h-full bg-gray-50">
                      <div class="text-center">
                        <div class="mb-4">
                          <.icon name="hero-document-text" class="w-16 h-16 text-gray-400 mx-auto" />
                        </div>
                        <p class="text-gray-600 mb-4">Resume Preview</p>
                        <p class="text-sm text-gray-500 mb-4">Your browser doesn't support iframes</p>
                        <button
                          phx-click="download_resume"
                          phx-value-student_id={@resume_student_id}
                          phx-value-filename={@resume_filename}
                          class="px-4 py-2 bg-orange-500 text-white rounded-md hover:bg-orange-600 transition-colors"
                        >
                          Download Resume
                        </button>
                      </div>
                    </div>
                  </iframe>
                </div>
              <% else %>
                <div class="text-center py-8">
                  <p class="text-gray-500">Resume not available</p>
                </div>
              <% end %>
            </div>

            <!-- Modal Footer -->
            <div class="flex justify-end mt-3 pt-3 border-t shrink-0">
              <button
                phx-click="close_resume_modal"
                class="px-6 py-2 bg-gray-300 text-gray-700 rounded-md hover:bg-gray-400 transition-colors font-medium"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @tenant_not_found? do %>
        <%= render_tenant_not_found_error(assigns) %>
      <% else %>
        <VyaasaCampusWeb.Components.TenantAdmin.AdminShell.admin_layout
          tenant_alias={@tenant_alias}
          tenant_name={@tenant_name}
          student_count={Map.get(@overview_stats || %{}, :total_all_students)}
          current_section={@current_section}
          user_info={@user_info}
        >

          <%= if @show_add_student do %>
            <!-- Add Student Form -->
            <div class="mb-6">
              <div class="flex items-center mb-4">
                <button
                  phx-click="hide_add_student"
                  class="flex items-center text-gray-600 hover:text-gray-800 mr-4"
                >
                  <.icon name="hero-arrow-left" class="w-5 h-5 mr-2" />
                  Add Students
                </button>
              </div>

              <.add_student_form
                form={@add_student_form}
                tenant_alias={@tenant_alias}
                errors={@add_student_errors}
                loading={@loading?}
                degree_options={@degree_options}
                specialization_options={@specialization_options}
              />
            </div>
          <% else %>

          <!-- ============ ANALYTICS HEADER ============ -->
          <div class="px-4 sm:px-6 lg:px-10 pt-8">
            <div class="max-w-350 mx-auto w-full">
              <div class="flex flex-wrap items-start justify-between gap-4 mb-5">
                <div>
                  <p class="text-[11px] font-bold uppercase tracking-[0.14em] text-[#F97316] mb-1">Placement Intelligence</p>
                  <h1 class="text-2xl font-bold text-gray-900">Analytics</h1>
                  <p class="text-sm text-gray-500 mt-0.5">Readiness, potential and placement insight across {@tenant_name}.</p>
                </div>
                <div class="flex items-center gap-2">
                  <button
                    phx-click="refresh"
                    class="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg border border-gray-200 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50 transition"
                  >
                    <.icon name="hero-arrow-path" class="w-4 h-4" /> Refresh
                  </button>
                  <a
                    href={export_pdf_href(assigns)}
                    download
                    class="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg text-sm font-semibold text-white transition"
                    style="background-color: #F97316;"
                  >
                    <.icon name="hero-document-arrow-down" class="w-4 h-4" /> Export PDF
                  </a>
                </div>
              </div>

            </div>
          </div>

          <!-- ==================== OVERVIEW TAB ==================== -->
          <%= if @admin_tab == "overview" do %>
          <div class="px-4 sm:px-6 lg:px-10 pb-8">
            <div id="overview-download-hook" phx-hook="FileDownload" class="max-w-350 mx-auto w-full space-y-6">
              <% total = @overview_stats.total_all_students %>
              <% ready = Enum.count(@scored_students, &((Map.get(&1, :ai8_score) || 0) >= 70)) %>

              <!-- Stat tiles (click a tile to open the students drawer) -->
              <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
                <.stat_tile category="total" selected={drawer_tile(@drawer) == "total"} label="Total Students" value={total} sub={"#{@overview_stats.verified} verified"} />
                <.stat_tile category="scored" selected={drawer_tile(@drawer) == "scored"} label="Avg AI8 Score" value={@overview_stats.avg_ai8_score} sub={"#{@overview_stats.students_with_scores} scored"} />
                <.stat_tile category="ready" selected={drawer_tile(@drawer) == "ready"} label="Placement Ready" value={ready} sub={"of #{total} students"} accent />
                <.stat_tile category="top" selected={drawer_tile(@drawer) == "top"} label="Highest Score" value={@overview_stats.highest_ai8_score} sub="top performers" />
                <.stat_tile category="assessed" selected={drawer_tile(@drawer) == "assessed"} label="Fully Assessed" value={@overview_stats.all_assessments_completed} sub="all assessments" />
              </div>

              <!-- Intervention center -->
              <div>
                <h2 class="text-sm font-bold text-gray-900 mb-3">Intervention Center</h2>
                <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
                  <.alert_card category="low_performers" label="Low Performers" count={@alerts.low_performers.count} sub="Score < 40" icon="hero-exclamation-triangle" tone="red" />
                  <.alert_card category="incomplete_profiles" label="Incomplete Profiles" count={@alerts.incomplete_profiles.count} sub="Pending completion" icon="hero-user-circle" tone="orange" />
                  <.alert_card category="not_started" label="Not Started" count={@alerts.not_started.count} sub="No assessments yet" icon="hero-clock" tone="amber" />
                  <.alert_card category="integrity_flags" label="Integrity Flags" count={@alerts.integrity_flags.count} sub="Needs review" icon="hero-shield-exclamation" tone="purple" />
                </div>

                <%= if @alerts.integrity_flags.count > 0 do %>
                  <div class="mt-3 bg-white rounded-2xl border border-purple-100 p-4">
                    <div class="flex items-center gap-2 mb-3">
                      <.icon name="hero-shield-exclamation" class="w-4 h-4 text-purple-600" />
                      <p class="text-xs font-semibold text-purple-800">Integrity flags — needs review</p>
                    </div>
                    <ul class="space-y-2">
                      <%= for s <- @alerts.integrity_flags.students do %>
                        <li class="text-xs">
                          <span class="font-semibold text-gray-900">{s.first_name} {s.last_name}</span>
                          <ul class="mt-0.5 ml-3 list-disc text-gray-600 space-y-0.5">
                            <%= for flag <- (Map.get(s, :integrity_flags) || []) do %>
                              <li>{flag}</li>
                            <% end %>
                          </ul>
                        </li>
                      <% end %>
                    </ul>
                  </div>
                <% end %>
              </div>

              <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <!-- Placement funnel -->
                <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6">
                  <h2 class="text-sm font-bold text-gray-900 mb-4">Placement Readiness Funnel</h2>
                  <div class="space-y-3">
                    <%= for {label, count, color} <- [
                      {"Registered", total, "#FDBA74"},
                      {"Profile Complete", @overview_stats.profile_completed, "#FB923C"},
                      {"Assessment Completed", @overview_stats.all_assessments_completed, "#F97316"},
                      {"Placement Ready", ready, "#16a34a"}
                    ] do %>
                      <% w = if total > 0, do: round(count / total * 100), else: 0 %>
                      <div>
                        <div class="flex items-center justify-between mb-1 text-sm">
                          <span class="text-gray-700">{label}</span>
                          <span class="font-semibold text-gray-500">{count}</span>
                        </div>
                        <div class="w-full bg-gray-100 rounded-full h-2.5">
                          <div class="h-2.5 rounded-full transition-all" style={"width: #{w}%; background-color: #{color};"}></div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>

                <!-- Assessment completion -->
                <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6">
                  <h2 class="text-sm font-bold text-gray-900 mb-4">Assessment Completion</h2>
                  <div class="space-y-3.5">
                    <%= for {key, label} <- [
                      {:ats, "Resume Score"}, {:mcq, "MCQ"}, {:behavioral, "Behavioral"},
                      {:jam, "JAM Session"}, {:interview, "Interactive Session"}, {:psychometric, "Psychometric"},
                      {:case_study, "Case Study"}, {:mini_project, "Mini Project"}
                    ] do %>
                      <% stat = @overview_stats.assessments[key] %>
                      <% pct = if stat.total > 0, do: round(stat.completed / stat.total * 100), else: 0 %>
                      <div>
                        <div class="flex items-center justify-between mb-1 text-sm">
                          <span class="text-gray-700">{label}</span>
                          <span class="text-xs font-semibold text-gray-500">{stat.completed}/{stat.total} ({pct}%)</span>
                        </div>
                        <div class="w-full bg-gray-100 rounded-full h-2.5">
                          <div class="h-2.5 rounded-full transition-all" style={"width: #{pct}%; background-color: #F97316;"}></div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>

              <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <!-- Top performers -->
                <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6">
                  <h2 class="text-sm font-bold text-gray-900 mb-4">Top Performers</h2>
                  <div class="space-y-2">
                    <div :for={r <- Enum.take(@top_rankers, 5)} class="flex items-center gap-3 py-1.5">
                      <span class="w-6 h-6 rounded-full bg-[#FFF4E7] text-[#F97316] text-xs font-bold flex items-center justify-center shrink-0">{r.rank}</span>
                      <div class="min-w-0 flex-1">
                        <p class="text-sm font-semibold text-gray-900 truncate">{r.name}</p>
                        <p class="text-[11px] text-gray-400 truncate">{r.specialization}</p>
                      </div>
                      <span class="text-sm font-bold text-[#F97316]">{r.ai8_score}</span>
                    </div>
                    <div :if={@top_rankers == []} class="text-center text-sm text-gray-400 py-4">No ranked students yet.</div>
                  </div>
                </div>

                <!-- Department averages -->
                <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6">
                  <h2 class="text-sm font-bold text-gray-900 mb-4">Specialization Averages</h2>
                  <div class="space-y-3">
                    <div :for={dept <- Enum.take(@department_stats, 6)}>
                      <div class="flex items-center justify-between mb-1 text-sm">
                        <span class="text-gray-700 truncate max-w-[60%]">{dept.department}</span>
                        <span class="text-xs text-gray-500">avg {dept.avg_ai8_score} · {dept.student_count} students</span>
                      </div>
                      <div class="w-full bg-gray-100 rounded-full h-2">
                        <div class="h-2 rounded-full" style={"width: #{min(dept.avg_ai8_score, 100)}%; background-color: #F97316;"}></div>
                      </div>
                    </div>
                    <div :if={@department_stats == []} class="text-center text-sm text-gray-400 py-4">No specialization data</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <% end %>

          <!-- ==================== LEADERBOARD TAB ==================== -->
          <%= if @admin_tab == "leaderboard" do %>{leaderboard_tab(assigns)}<% end %>

          <!-- ==================== SPECIALIZATIONS TAB ==================== -->
          <%= if @admin_tab == "departments" do %>{specializations_tab(assigns)}<% end %>
          <%= if @admin_tab == "readiness" do %>{placement_readiness_tab(assigns)}<% end %>

          <% end %>
        </VyaasaCampusWeb.Components.TenantAdmin.AdminShell.admin_layout>
      <% end %>
    </Layouts.app>
    """
  end

  # ── Overview tab pieces ─────────────────────────────────────────────────
  @assessment_score_fields [
    :ats_score,
    :mcq_percentage,
    :behavioral_score,
    :jam_score,
    :interview_score,
    :psychometric_score
  ]

  defp has_any_assessment?(s),
    do: Enum.any?(@assessment_score_fields, &(not is_nil(Map.get(s, &1))))

  # Must match the "Fully Assessed" count on the overview stat card
  # (StudentRankings.get_tenant_overview_stats/1), which checks all 8 AI8 modules.
  defp all_assessments_done?(s) do
    StudentRankings.module_score_keys()
    |> Enum.all?(&(not is_nil(Map.get(s, &1))))
  end

  defp sort_by_score_desc(students),
    do: Enum.sort_by(students, &(Map.get(&1, :ai8_score) || 0), :desc)

  defp drawer_tile(nil), do: nil
  defp drawer_tile(%{tile: tile}), do: tile

  @overview_csv_headers ~w(first_name last_name email registration_id degree specialization
                            year_of_passing cgpa status ai8_score)

  defp download_students_csv(socket, category, students) do
    csv = overview_students_to_csv(students)
    filename = "#{category}-#{Date.utc_today()}.csv"
    push_event(socket, "download_content", %{content: csv, filename: filename, mime: "text/csv"})
  end

  defp overview_students_to_csv(students) do
    rows =
      Enum.map(students, fn s ->
        [
          Map.get(s, :first_name),
          Map.get(s, :last_name),
          Map.get(s, :email),
          Map.get(s, :registration_id),
          Map.get(s, :degree),
          Map.get(s, :specialization),
          Map.get(s, :year_of_passing),
          Map.get(s, :cgpa),
          Map.get(s, :status),
          overview_ai8_of(s)
        ]
        |> Enum.map(&to_string(&1 || ""))
      end)

    [@overview_csv_headers | rows]
    |> CSV.encode()
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end

  defp overview_ai8_of(s) do
    case Map.get(s, :ai8_score) do
      nil -> 0
      %Decimal{} = d -> Decimal.to_float(d)
      n when is_number(n) -> n
      _ -> 0
    end
  end

  # Open the shared right-side drawer, or close it if the same tile/card is
  # clicked again. `tile` identifies the source (for highlighting); `kind` is
  # the category (used to show integrity flags instead of status).
  defp toggle_drawer(socket, tile, title, sub, students, kind) do
    current = socket.assigns[:drawer]

    if current && current.tile == tile do
      assign(socket, :drawer, nil)
    else
      assign(socket, :drawer, %{
        tile: tile,
        title: title,
        sub: sub,
        students: students,
        kind: kind
      })
    end
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, default: nil
  attr :accent, :boolean, default: false
  attr :category, :string, required: true
  attr :selected, :boolean, default: false

  defp stat_tile(assigns) do
    ~H"""
    <div class={[
      "rounded-2xl border p-4 transition hover:shadow-md",
      @selected && "ring-2 ring-[#F97316] ring-offset-1",
      if(@accent, do: "bg-white border-[#ffffff] hover:border-[#F8C095]", else: "border-gray-100 hover:border-[#F8C095]")
    ]}>
      <div class="flex items-center justify-between gap-1">
        <p class="text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 truncate">{@label}</p>
        <button
          type="button"
          phx-click="download_category"
          phx-value-category={@category}
          title={"Download #{@label} (CSV)"}
          class="shrink-0 p-1 -m-1 rounded-md text-[#F97316] hover:bg-orange-50 transition focus:outline-none"
        >
          <.icon name="hero-arrow-down-tray" class="w-3.5 h-3.5" />
        </button>
      </div>
      <button
        type="button"
        phx-click="show_category"
        phx-value-category={@category}
        class="w-full text-left cursor-pointer focus:outline-none"
      >
        <p class="text-2xl font-bold mt-1 text-gray-900">{@value}</p>
        <p :if={@sub} class="text-[11px] text-gray-400 mt-0.5">{@sub}</p>
        <p class="text-[10px] font-semibold text-[#F97316] mt-1.5 flex items-center gap-0.5">
          View students <span aria-hidden="true">→</span>
        </p>
      </button>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :sub, :string, default: nil
  attr :icon, :string, required: true
  attr :tone, :string, default: "orange"
  attr :category, :string, required: true

  defp alert_card(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="show_alert"
      phx-value-category={@category}
      class={["rounded-2xl border p-4 flex items-center justify-between w-full text-left cursor-pointer transition hover:shadow-md focus:outline-none", alert_tone_class(@tone)]}
    >
      <div>
        <p class="text-[11px] font-semibold uppercase tracking-wide">{@label}</p>
        <p class="text-2xl font-bold mt-1">{@count}</p>
        <p :if={@sub} class="text-[11px] opacity-70">{@sub}</p>
        <p class="text-[10px] font-semibold mt-1.5 opacity-80">View students →</p>
      </div>
      <.icon name={@icon} class="w-7 h-7 opacity-40" />
    </button>
    """
  end

  defp alert_tone_class("red"), do: "bg-red-50 border-red-200 text-red-700"
  defp alert_tone_class("orange"), do: "bg-orange-50 border-orange-200 text-orange-700"
  defp alert_tone_class("amber"), do: "bg-amber-50 border-amber-200 text-amber-700"
  defp alert_tone_class("purple"), do: "bg-purple-50 border-purple-200 text-purple-700"
  defp alert_tone_class(_), do: "bg-gray-50 border-gray-200 text-gray-700"

  # ── Leaderboard tab ─────────────────────────────────────────────────────
  defp leaderboard_tab(assigns) do
    ranked =
      assigns.scored_students
      |> filter_scored_students(
        assigns.leaderboard_department,
        assigns.leaderboard_specialization,
        assigns.leaderboard_year
      )
      # Leaderboard top performers: only rank students who have completed ALL
      # assessment modules. Students still missing a module are excluded so we
      # don't surface a partial score as a "top performer" score yet.
      |> Enum.filter(&StudentRankings.completed_all_modules?/1)
      |> Enum.sort_by(&lb_num(Map.get(&1, :ai8_score)), :desc)
      |> Enum.with_index(1)

    assigns = assign(assigns, ranked: ranked, top3: Enum.take(assigns.top_rankers, 3))

    ~H"""
    <div class="px-4 sm:px-6 lg:px-10 pb-8">
      <div class="max-w-350 mx-auto w-full space-y-6">
        <!-- Top 3 cards -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div :for={r <- @top3} class={["rounded-2xl border p-5", if(r.rank == 1, do: "bg-[#FFF4E7] border-[#F8C095]", else: "bg-white border-gray-100")]}>
            <div class="flex items-center justify-between mb-2">
              <span class="w-7 h-7 rounded-full bg-white border border-gray-200 text-gray-700 text-xs font-bold flex items-center justify-center">#{r.rank}</span>
              <span class={["px-2 py-0.5 rounded-full text-[11px] font-semibold", tier_class(lb_num(r.ai8_score))]}>{tier_label(lb_num(r.ai8_score))}</span>
            </div>
            <p class="text-sm font-bold text-gray-900 truncate">{r.name}</p>
            <p class="text-[11px] text-gray-400 truncate mb-2">{r.specialization}</p>
            <p class="text-3xl font-extrabold text-[#F97316]">{r.ai8_score}</p>
          </div>
          <div :if={@top3 == []} class="md:col-span-3 text-center text-sm text-gray-400 py-6 bg-white rounded-2xl border border-gray-100">No fully-assessed students yet.</div>
        </div>

        <!-- Filters -->
        <form phx-change="filter_leaderboard" class="flex flex-wrap items-end gap-3 bg-white rounded-2xl border border-gray-100 p-4">
          <div class="flex-1 min-w-45">
            <label class="block text-[10px] font-semibold uppercase tracking-wide text-gray-400 mb-1">Department</label>
            <select name="department" class="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:border-[#F97316]">
              <option value="all" selected={@leaderboard_department == "all"}>All departments</option>
              <option :for={d <- @leaderboard_department_options} value={d} selected={@leaderboard_department == d}>{d}</option>
            </select>
          </div>
          <div class="flex-1 min-w-45">
            <label class="block text-[10px] font-semibold uppercase tracking-wide text-gray-400 mb-1">Specialization</label>
            <select name="specialization" class="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:border-[#F97316]">
              <option value="all" selected={@leaderboard_specialization == "all"}>All specializations</option>
              <option :for={s <- @leaderboard_specialization_options} value={s} selected={@leaderboard_specialization == s}>{s}</option>
            </select>
          </div>
          <div class="flex-1 min-w-35">
            <label class="block text-[10px] font-semibold uppercase tracking-wide text-gray-400 mb-1">Year</label>
            <select name="year" class="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:border-[#F97316]">
              <option value="all" selected={@leaderboard_year == "all"}>All years</option>
              <option :for={y <- @leaderboard_year_options} value={y} selected={@leaderboard_year == y}>{y}</option>
            </select>
          </div>
        </form>

        <!-- Ranked table -->
        <div class="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full min-w-205 text-sm">
              <thead>
                <tr class="text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 border-b border-gray-100">
                  <th class="text-left px-5 py-3">Rank</th>
                  <th class="text-left px-2 py-3">Student</th>
                  <th class="text-left px-2 py-3">Department</th>
                  <th class="text-center px-2 py-3 text-[#F97316]">AI8</th>
                  <th class="text-left px-3 py-3">Tier</th>
                  <th class="text-left px-3 py-3">Completion</th>
                  <th class="text-left px-3 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@ranked == []}><td colspan="7" class="px-5 py-12 text-center text-sm text-gray-400">No students match the selected filters.</td></tr>
                <tr :for={{s, rank} <- @ranked} class="border-b border-gray-50 hover:bg-[#FBFAF7] transition">
                  <td class="px-5 py-3 font-semibold text-gray-500">#{rank}</td>
                  <td class="px-2 py-3">
                    <p class="font-semibold text-gray-900 truncate">{lb_name(s)}</p>
                    <p class="text-[11px] text-gray-400 truncate">{s.registration_id || "—"}</p>
                  </td>
                  <td class="px-2 py-3 text-gray-600">{s.specialization || s.degree || "—"}</td>
                  <td class="px-2 py-3 text-center font-bold text-[#F97316]">{lb_score_cell(Map.get(s, :ai8_score))}</td>
                  <td class="px-3 py-3"><span class={["px-2.5 py-1 rounded-full text-[11px] font-semibold whitespace-nowrap", tier_class(lb_num(Map.get(s, :ai8_score)))]}>{tier_label(lb_num(Map.get(s, :ai8_score)))}</span></td>
                  <td class="px-3 py-3">
                    <% c = completion_pct(s) %>
                    <div class="flex items-center gap-2">
                      <div class="w-20 bg-gray-100 rounded-full h-2"><div class="h-2 rounded-full" style={"width: #{c}%; background-color: #F97316;"}></div></div>
                      <span class="text-[11px] text-gray-500">{c}%</span>
                    </div>
                  </td>
                  <td class="px-3 py-3"><span class={["px-2.5 py-1 rounded-full text-[11px] font-semibold whitespace-nowrap", lb_status_class(s)]}>{lb_status_label(s)}</span></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp lb_num(nil), do: 0
  defp lb_num(%Decimal{} = d), do: Decimal.to_float(d)
  defp lb_num(n) when is_number(n), do: n
  defp lb_num(_), do: 0

  defp lb_name(s), do: String.trim("#{s.first_name} #{s.last_name}")

  defp lb_score_cell(nil), do: "—"
  defp lb_score_cell(v), do: round(lb_num(v))

  defp tier_label(score) do
    cond do
      score >= 90 -> "Elite Talent"
      score >= 75 -> "High Potential"
      score >= 60 -> "Placement Ready"
      score >= 45 -> "Emerging Talent"
      true -> "Developing"
    end
  end

  defp tier_class(score) do
    cond do
      score >= 90 -> "bg-emerald-100 text-emerald-700"
      score >= 75 -> "bg-orange-100 text-orange-700"
      score >= 60 -> "bg-blue-100 text-blue-700"
      score >= 45 -> "bg-amber-100 text-amber-700"
      true -> "bg-red-100 text-red-700"
    end
  end

  defp completion_pct(s) do
    done =
      [:ats_score, :mcq_percentage, :behavioral_score, :jam_score, :interview_score, :psychometric_score]
      |> Enum.count(fn k -> Map.get(s, k) not in [nil, ""] end)

    round(done / 6 * 100)
  end

  defp lb_status_label(s) do
    cond do
      completion_pct(s) >= 100 -> "Assessment Completed"
      completion_pct(s) > 0 -> "In Progress"
      true -> "Not Started"
    end
  end

  defp lb_status_class(s) do
    cond do
      completion_pct(s) >= 100 -> "bg-emerald-100 text-emerald-700"
      completion_pct(s) > 0 -> "bg-[#FFF4E7] text-[#F97316]"
      true -> "bg-gray-100 text-gray-500"
    end
  end

  # ── Specializations tab ──────────────────────────────────────────────────
  @tier_segments [
    {:elite, "Elite Talent", "#10b981"},
    {:high, "High Potential", "#f97316"},
    {:ready, "Placement Ready", "#3b82f6"},
    {:emerging, "Emerging Talent", "#f59e0b"},
    {:developing, "Developing", "#ef4444"}
  ]

  defp specializations_tab(assigns) do
    depts =
      assigns.scored_students
      |> Enum.group_by(&(Map.get(&1, :specialization) || "Unknown"))
      |> Enum.map(&dept_summary/1)
      |> Enum.sort_by(& &1.avg, :desc)

    assigns = assign(assigns, depts: depts, tier_segments: @tier_segments)

    ~H"""
    <div class="px-4 sm:px-6 lg:px-10 pb-8">
      <div class="max-w-350 mx-auto w-full space-y-6">
        <div :if={@depts == []} class="text-center text-sm text-gray-400 py-10 bg-white rounded-2xl border border-gray-100">No specialization data yet.</div>

        <!-- Department health cards -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <button
            :for={d <- @depts}
            type="button"
            phx-click="show_specialization"
            phx-value-name={d.name}
            class={[
              "bg-white rounded-2xl border shadow-sm p-5 text-left w-full transition hover:shadow-md cursor-pointer focus:outline-none",
              if(drawer_tile(@drawer) == "spec:#{d.name}", do: "border-[#F97316] ring-2 ring-[#F97316] ring-offset-1", else: "border-gray-100 hover:border-[#F8C095]")
            ]}
          >
            <div class="flex items-start justify-between mb-4">
              <div>
                <p class="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{dept_band(d.health)}</p>
                <h3 class="text-lg font-bold text-gray-900">{d.name}</h3>
                <p class="text-[11px] text-gray-400">{d.count} students · Top: {d.topper}</p>
              </div>
              <div class="text-right">
                <span class={["px-2.5 py-1 rounded-full text-sm font-bold", health_class(d.health)]}>{d.health}%</span>
                <p class="text-[10px] text-gray-400 mt-0.5 uppercase tracking-wide">Health</p>
              </div>
            </div>
            <div class="grid grid-cols-3 gap-3">
              <div>
                <p class="text-[10px] uppercase tracking-wide text-gray-400">Placement Ready</p>
                <p class="text-base font-bold text-gray-900">{d.ready}</p>
              </div>
              <div>
                <p class="text-[10px] uppercase tracking-wide text-gray-400">Avg AI8</p>
                <p class="text-base font-bold text-[#F97316]">{d.avg}</p>
              </div>
              <div>
                <p class="text-[10px] uppercase tracking-wide text-gray-400">Completion</p>
                <p class="text-base font-bold text-gray-900">{d.completion}%</p>
              </div>
            </div>
          </button>
        </div>

        <!-- Readiness distribution by department (stacked columns) -->
        <div :if={@depts != []} class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6">
          <h2 class="text-sm font-bold text-gray-900 mb-1">Readiness distribution by department</h2>
          <p class="text-[11px] text-gray-400 mb-5">Stacked tier mix · % of cohort</p>

          <div class="relative h-64">
            <div :for={{lbl, topf} <- [{"100%", 0.0}, {"75%", 0.25}, {"50%", 0.5}, {"25%", 0.75}, {"0%", 1.0}]}
              class="absolute left-0 right-0 grid grid-cols-[36px_minmax(0,1fr)] items-center" style={"top: #{topf * 100}%"}>
              <span class="text-right pr-2 text-[10px] text-gray-400">{lbl}</span>
              <div class="border-t border-dashed border-gray-100"></div>
            </div>
            <div class="absolute inset-y-0 left-9 right-0 flex items-end justify-around gap-3">
              <div :for={d <- @depts} class="flex-1 max-w-16 h-full flex flex-col-reverse rounded-lg overflow-hidden">
                <div
                  :for={{key, _label, color} <- @tier_segments}
                  :if={d.count > 0 and Map.get(d.tiers, key) > 0}
                  style={"height: #{Map.get(d.tiers, key) / d.count * 100}%; background-color: #{color};"}
                >
                </div>
              </div>
            </div>
          </div>
          <div class="grid grid-cols-[36px_minmax(0,1fr)] mt-2">
            <div></div>
            <div class="flex items-center justify-around gap-3">
              <span :for={d <- @depts} class="flex-1 max-w-16 text-center text-[11px] text-gray-500 truncate">{d.name}</span>
            </div>
          </div>

          <div class="flex flex-wrap justify-center gap-4 mt-5 pt-4 border-t border-gray-100">
            <div :for={{_key, label, color} <- @tier_segments} class="flex items-center gap-1.5">
              <span class="w-2.5 h-2.5 rounded-full" style={"background-color: #{color};"}></span>
              <span class="text-[11px] text-gray-500">{label}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp dept_summary({name, students}) do
    count = length(students)
    scores = Enum.map(students, &lb_num(Map.get(&1, :ai8_score)))
    scored = Enum.reject(students, &is_nil(Map.get(&1, :ai8_score)))
    scored_vals = Enum.map(scored, &lb_num(Map.get(&1, :ai8_score)))
    avg = if scored_vals != [], do: Float.round(Enum.sum(scored_vals) / length(scored_vals), 1), else: 0.0
    ready = Enum.count(scores, &(&1 >= 70))
    health_base = Enum.count(scores, &(&1 >= 60))
    health = if count > 0, do: round(health_base / count * 100), else: 0
    completion = if count > 0, do: round(Enum.sum(Enum.map(students, &completion_pct/1)) / count), else: 0

    tiers =
      Enum.reduce(students, %{elite: 0, high: 0, ready: 0, emerging: 0, developing: 0}, fn s, acc ->
        Map.update!(acc, tier_key(lb_num(Map.get(s, :ai8_score))), &(&1 + 1))
      end)

    topper =
      scored
      |> Enum.max_by(&lb_num(Map.get(&1, :ai8_score)), fn -> nil end)
      |> case do
        nil -> "—"
        s -> lb_name(s)
      end

    %{
      name: name,
      count: count,
      avg: avg,
      ready: ready,
      completion: completion,
      health: health,
      tiers: tiers,
      topper: topper
    }
  end

  defp tier_key(score) do
    cond do
      score >= 90 -> :elite
      score >= 75 -> :high
      score >= 60 -> :ready
      score >= 45 -> :emerging
      true -> :developing
    end
  end

  defp dept_band(health) when health >= 85, do: "Excellent"
  defp dept_band(health) when health >= 70, do: "Healthy"
  defp dept_band(_), do: "Watch"

  defp health_class(health) when health >= 85, do: "bg-emerald-100 text-emerald-700"
  defp health_class(health) when health >= 70, do: "bg-blue-100 text-blue-700"
  defp health_class(_), do: "bg-amber-100 text-amber-700"

  # ── Placement Readiness tab ─────────────────────────────────────────────
  defp placement_readiness_tab(assigns) do
    scored = assigns.scored_students
    total_all = assigns.overview_stats.total_all_students
    ready = Enum.count(scored, &(lb_num(Map.get(&1, :ai8_score)) >= 70))

    counts =
      Enum.reduce(scored, %{elite: 0, high: 0, ready: 0, emerging: 0, developing: 0}, fn s, acc ->
        Map.update!(acc, tier_key(lb_num(Map.get(s, :ai8_score))), &(&1 + 1))
      end)

    tier_total = max(Enum.sum(Map.values(counts)), 1)
    circ = 2 * :math.pi() * 60

    {donut, _} =
      Enum.map_reduce(@tier_segments, 0.0, fn {key, label, color}, offset ->
        c = Map.get(counts, key)
        seg = c / tier_total * circ
        dash = max(seg - 4.0, 0.1)

        {%{
           color: color,
           label: label,
           count: c,
           pct: round(c / tier_total * 100),
           dash: Float.round(dash, 2),
           gap: Float.round(circ - dash, 2),
           offset: Float.round(-offset, 2)
         }, offset + seg}
      end)

    funnel_stages = [
      {"Registered", total_all, "#EE6D18"},
      {"Profile Complete", assigns.overview_stats.profile_completed, "#F97316"},
      {"Assessment Completed", assigns.overview_stats.all_assessments_completed, "#3B82F6"},
      {"Placement Ready", ready, "#16A34A"}
    ]

    fbase = max(total_all, 1)
    fn_n = length(funnel_stages)
    band_h = 56.0 / fn_n
    fhw = fn c -> Float.round(max(c / fbase * 46, 5) * 1.0, 2) end

    funnel =
      funnel_stages
      |> Enum.with_index()
      |> Enum.map(fn {{label, count, color}, i} ->
        top = fhw.(count)
        bottom = if i < fn_n - 1, do: fhw.(elem(Enum.at(funnel_stages, i + 1), 1)), else: 4.0
        y0 = Float.round(i * band_h, 2)
        y1 = Float.round((i + 1) * band_h, 2)

        %{
          label: label,
          count: count,
          color: color,
          points: "#{50 - top},#{y0} #{50 + top},#{y0} #{50 + bottom},#{y1} #{50 - bottom},#{y1}"
        }
      end)

    depts =
      scored
      |> Enum.group_by(&(Map.get(&1, :specialization) || "Unknown"))
      |> Enum.map(&dept_summary/1)
      |> Enum.sort_by(& &1.avg, :desc)

    assigns =
      assign(assigns, donut: donut, funnel: funnel, total_all: total_all, depts: depts, tier_segments: @tier_segments)

    ~H"""
    <div class="px-4 sm:px-6 lg:px-10 pb-8">
      <div class="max-w-350 mx-auto w-full space-y-6">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- Funnel -->
          <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6">
            <h2 class="text-sm font-bold text-gray-900 mb-1">Placement funnel</h2>
            <p class="text-[11px] text-gray-400 mb-3">Registered → Placement Ready</p>
            <svg viewBox="0 0 100 56" class="w-full max-w-95 mx-auto" preserveAspectRatio="xMidYMid meet">
              <polygon :for={b <- @funnel} points={b.points} fill={b.color} />
            </svg>
            <div class="flex flex-wrap justify-center gap-x-4 gap-y-1.5 mt-4">
              <div :for={b <- @funnel} class="flex items-center gap-1.5">
                <span class="w-2.5 h-2.5 rounded-sm" style={"background-color: #{b.color};"}></span>
                <span class="text-[11px] text-gray-500">{b.label} · <span class="font-semibold text-gray-700">{b.count}</span></span>
              </div>
            </div>
          </div>

          <!-- Readiness distribution donut -->
          <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6">
            <h2 class="text-sm font-bold text-gray-900 mb-1">Readiness distribution</h2>
            <p class="text-[11px] text-gray-400 mb-4">By tier across cohort</p>
            <div class="flex items-center gap-6">
              <svg width="160" height="160" viewBox="0 0 160 160" class="shrink-0">
                <g transform="rotate(-90 80 80)">
                  <circle cx="80" cy="80" r="60" fill="none" stroke="#f3f4f6" stroke-width="18" />
                  <circle
                    :for={seg <- @donut}
                    :if={seg.count > 0}
                    cx="80" cy="80" r="60" fill="none" stroke={seg.color} stroke-width="18"
                    stroke-dasharray={"#{seg.dash} #{seg.gap}"} stroke-dashoffset={seg.offset}
                  />
                </g>
              </svg>
              <div class="flex-1 space-y-1.5">
                <div :for={seg <- @donut} class="flex items-center justify-between text-sm">
                  <span class="flex items-center gap-2">
                    <span class="w-2.5 h-2.5 rounded-full" style={"background-color: #{seg.color};"}></span>
                    <span class="text-gray-600">{seg.label}</span>
                  </span>
                  <span class="text-gray-500">{seg.pct}% · {seg.count}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Department readiness heatmap -->
        <div :if={@depts != []} class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6 overflow-x-auto">
          <h2 class="text-sm font-bold text-gray-900 mb-1">Department readiness heatmap</h2>
          <p class="text-[11px] text-gray-400 mb-4">% of cohort per tier, per department</p>
          <table class="w-full min-w-160 text-sm">
            <thead>
              <tr class="text-[10px] font-semibold uppercase tracking-wide text-gray-400">
                <th class="text-left py-2 pr-3">Department</th>
                <th :for={{_k, label, _c} <- @tier_segments} class="text-center py-2 px-2">{label}</th>
                <th class="text-center py-2 pl-2">Ready %</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={d <- @depts} class="border-t border-gray-50">
                <td class="py-2 pr-3 font-medium text-gray-800">{d.name}</td>
                <td :for={{key, _label, color} <- @tier_segments} class="text-center py-2 px-1">
                  <% pct = if d.count > 0, do: round(Map.get(d.tiers, key) / d.count * 100), else: 0 %>
                  <span class="inline-block w-full rounded-md py-1 text-[11px] font-semibold text-white" style={"background-color: #{color}; opacity: #{0.25 + pct / 100 * 0.75};"}>{pct}%</span>
                </td>
                <td class="text-center py-2 pl-2 font-bold text-[#F97316]">{d.health}%</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Render functions

  defp render_tenant_not_found_error(assigns) do
    ~H"""
    <!-- Tenant Not Found Error -->
    <div class="bg-red-50 border border-red-200 rounded-lg p-6 mb-6">
      <div class="flex">
        <div class="shrink-0">
          <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-red-400" />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-red-800">Tenant Not Found</h3>
          <div class="mt-2 text-sm text-red-700">
            <p>The tenant "<%= @tenant_alias %>" could not be found. Please check the URL and try again.</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:flash, type, message}, socket) do
    {:noreply, put_flash(socket, type, message)}
  end

  # Real-time dashboard updates: any student/assessment/ats/session change in
  # this tenant schedules a debounced reload. Multiple events collapse into one
  # reload so bulk writes don't spam the LiveView.
  # Roster changes (a student added or removed) alter the whole population, so
  # they still need a full reload.
  @impl true
  def handle_info({:dashboard_event, %{action: action}}, socket) when action in [:created, :deleted] do
    {:noreply, schedule_dashboard_reload(socket)}
  end

  # Everything else — a score landing, a profile edit — concerns ONE student, so
  # refresh just that row. Ids accumulate while the debounce window is open, so a
  # burst of 200 students finishing an exam collapses into one batched refresh.
  @impl true
  def handle_info({:dashboard_event, %{student_id: student_id}}, socket) when not is_nil(student_id) do
    {:noreply, schedule_student_refresh(socket, student_id)}
  end

  @impl true
  def handle_info({:dashboard_event, _payload}, socket) do
    {:noreply, schedule_dashboard_reload(socket)}
  end

  @impl true
  def handle_info(:reload_dashboard, socket) do
    {:noreply,
     socket
     |> assign(:reload_pending?, false)
     |> reload_dashboard_data()}
  end

  @impl true
  def handle_info(:flush_student_refresh, socket) do
    ids = socket.assigns[:pending_student_ids] || MapSet.new()

    {:noreply,
     socket
     |> assign(:pending_student_ids, MapSet.new())
     |> refresh_students(MapSet.to_list(ids))}
  end

  defp schedule_dashboard_reload(socket) do
    if Map.get(socket.assigns, :reload_pending?, false) do
      socket
    else
      Process.send_after(self(), :reload_dashboard, 300)
      assign(socket, :reload_pending?, true)
    end
  end

  defp schedule_student_refresh(socket, student_id) do
    pending = socket.assigns[:pending_student_ids] || MapSet.new()
    socket = assign(socket, :pending_student_ids, MapSet.put(pending, to_string(student_id)))

    # One timer per window; ids that arrive meanwhile ride along with it.
    if MapSet.size(pending) == 0, do: Process.send_after(self(), :flush_student_refresh, 500)

    socket
  end

  # Refresh the named students in place, then recompute every aggregate from the
  # in-memory lists. The stats functions are pure over the student list, so this
  # costs no extra queries beyond the handful per refreshed student.
  defp refresh_students(socket, []), do: socket

  defp refresh_students(socket, student_ids) do
    require Logger

    tenant_schema = socket.assigns[:tenant_schema]
    scored = socket.assigns[:scored_students] || []

    if is_nil(tenant_schema) or scored == [] do
      # Nothing loaded yet (or no tenant) — fall back to the full path.
      schedule_dashboard_reload(socket)
    else
      try do
        refreshed =
          student_ids
          |> Enum.map(&load_student_with_scores(&1, tenant_schema))
          |> Enum.reject(&is_nil/1)
          |> Map.new(&{to_string(&1.id), &1})

        if refreshed == %{} do
          socket
        else
          swap = fn list -> Enum.map(list, &Map.get(refreshed, to_string(&1.id), &1)) end

          scored_students = swap.(scored)
          raw_students = socket.assigns[:raw_students] || []

          socket
          |> assign(:students, swap.(socket.assigns[:students] || []))
          |> assign(:overview_stats, StudentRankings.get_full_overview_stats(raw_students, scored_students))
          |> assign(:alerts, StudentRankings.get_alerts(raw_students, scored_students))
          |> assign(:department_stats, StudentRankings.get_department_stats(scored_students))
          |> assign(:assessment_stats, StudentRankings.get_assessment_stats(scored_students))
          |> assign(:assessment_toppers, StudentRankings.get_assessment_toppers(scored_students, 5))
          |> assign(:low_performers, StudentRankings.get_low_performers(scored_students, 40))
          |> assign(:year_wise_stats, StudentRankings.get_year_wise_stats(scored_students))
          |> assign(:cgpa_data, StudentRankings.get_cgpa_correlation(scored_students))
          |> assign(:ats_distribution, StudentRankings.get_ats_distribution(scored_students))
          |> put_leaderboard_assigns(scored_students)
        end
      rescue
        e ->
          Logger.error("Targeted student refresh failed: #{Exception.message(e)}")
          socket
      end
    end
  end

  defp reload_dashboard_data(socket) do
    require Logger

    tenant_schema = socket.assigns.tenant_schema

    if is_nil(tenant_schema) do
      socket
    else
      try do
        all_raw_students = Students.list_students(tenant_schema)
        all_scored_students = load_all_students_with_scores(tenant_schema)

        students = load_students_by_filter(tenant_schema, socket.assigns.student_filter)

        socket
        |> assign(:students, students)
        |> assign(:raw_students, all_raw_students)
        |> assign(:student_year_options, unique_student_years(all_raw_students))
        |> assign(:overview_stats, StudentRankings.get_full_overview_stats(all_raw_students, all_scored_students))
        |> assign(:alerts, StudentRankings.get_alerts(all_raw_students, all_scored_students))
        |> assign(:department_stats, StudentRankings.get_department_stats(all_scored_students))
        |> assign(:assessment_stats, StudentRankings.get_assessment_stats(all_scored_students))
        |> assign(:assessment_toppers, StudentRankings.get_assessment_toppers(all_scored_students, 5))
        |> assign(:low_performers, StudentRankings.get_low_performers(all_scored_students, 40))
        |> assign(:year_wise_stats, StudentRankings.get_year_wise_stats(all_scored_students))
        |> assign(:cgpa_data, StudentRankings.get_cgpa_correlation(all_scored_students))
        |> assign(:ats_distribution, StudentRankings.get_ats_distribution(all_scored_students))
        |> put_leaderboard_assigns(all_scored_students)
      rescue
        e ->
          Logger.error("Tenant dashboard live reload failed: #{Exception.message(e)}")
          socket
      end
    end
  end

  # ---- Leaderboard helpers --------------------------------------------------

  defp put_leaderboard_assigns(socket, scored_students) do
    dept = socket.assigns[:leaderboard_department] || "all"
    spec = socket.assigns[:leaderboard_specialization] || "all"
    year = socket.assigns[:leaderboard_year] || "all"

    # If the previously selected dept/spec/year is no longer present in the
    # data (e.g. last student in that bucket was deleted), drop back to "all".
    available_departments = unique_departments(scored_students)
    dept = if dept == "all" or dept in available_departments, do: dept, else: "all"

    available_specializations = unique_specializations(scored_students, dept)
    spec = if spec == "all" or spec in available_specializations, do: spec, else: "all"

    available_years = unique_years(scored_students)
    year = if year == "all" or year in available_years, do: year, else: "all"

    filtered = filter_scored_students(scored_students, dept, spec, year)

    socket
    |> assign(:scored_students, scored_students)
    |> assign(:leaderboard_department, dept)
    |> assign(:leaderboard_specialization, spec)
    |> assign(:leaderboard_year, year)
    |> assign(:leaderboard_department_options, available_departments)
    |> assign(:leaderboard_specialization_options, available_specializations)
    |> assign(:leaderboard_year_options, available_years)
    |> assign(:top_rankers, StudentRankings.get_top_rankers(filtered, 10))
  end

  defp unique_departments(scored_students) do
    scored_students
    |> Enum.map(&Map.get(&1, :degree))
    |> Enum.reject(fn d -> is_nil(d) or d == "" end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp unique_specializations(scored_students, department) do
    scored_students
    |> Enum.filter(fn s -> department in [nil, "", "all"] or Map.get(s, :degree) == department end)
    |> Enum.map(&Map.get(&1, :specialization))
    |> Enum.reject(fn s -> is_nil(s) or s == "" end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp unique_years(scored_students) do
    scored_students
    |> Enum.map(&Map.get(&1, :year_of_passing))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  defp filter_scored_students(scored_students, dept, spec, year) do
    scored_students
    |> maybe_filter_field(:degree, dept)
    |> maybe_filter_field(:specialization, spec)
    |> maybe_filter_year(year)
  end

  defp maybe_filter_field(students, _field, value) when value in [nil, "", "all"], do: students

  defp maybe_filter_field(students, field, value),
    do: Enum.filter(students, fn s -> Map.get(s, field) == value end)

  defp maybe_filter_year(students, value) when value in [nil, "", "all"], do: students

  defp maybe_filter_year(students, value),
    do: Enum.filter(students, fn s -> to_string(Map.get(s, :year_of_passing)) == to_string(value) end)

  # Private functions

  defp load_students_by_filter(tenant_schema, filter) do
    require Logger
    Logger.info("🔍 Dashboard: Loading students by filter '#{filter}' in schema '#{tenant_schema}'")

    if tenant_schema do
      import VyaasaCampus.Types

      # Force fresh database query to avoid any caching issues
      try do
        _result = SQL.query!(Repo, "SELECT 1", [], prefix: tenant_schema)
      rescue
        _ -> :ok
      end

      all_students = Students.list_students(tenant_schema)
      Logger.info("📊 Dashboard: Found #{length(all_students)} total students")

      # Log all student statuses for debugging
      Enum.each(all_students, fn student ->
        Logger.info("👤 Student #{student.id} (#{student.first_name} #{student.last_name}): status='#{student.status}'")
      end)

      {target_status, filtered_students} =
        case filter do
          "unverified" ->
            status = student_status_unverified()
            students = Enum.filter(all_students, &(&1.status == status))
            {status, students}

          "verified" ->
            status = student_status_verified()
            students = Enum.filter(all_students, &(&1.status == status))
            {status, students}

          "all" ->
            {"all", all_students}

          _ ->
            # Default to unverified if filter is not recognized
            status = student_status_unverified()
            students = Enum.filter(all_students, &(&1.status == status))
            {status, students}
        end

      Logger.info("🎯 Dashboard: Filtering for status '#{target_status}'")

      Logger.info("✅ Dashboard: Filtered to #{length(filtered_students)} students with status '#{target_status}'")

      # Enhance students with ATS data (resume info)
      enhanced_students =
        filtered_students
        |> Enum.map(&enhance_student_with_ats_data(&1, tenant_schema))
        |> attach_ai8_scores(tenant_schema)

      Logger.info("🎨 Dashboard: Enhanced #{length(enhanced_students)} students with ATS data")

      enhanced_students
    else
      Logger.warning("⚠️  Dashboard: No tenant schema provided")
      []
    end
  end

  @doc false
  def enhance_student_with_ats_data(student, tenant_schema) do
    require Logger
    alias VyaasaCampus.Contexts.StudentAts

    Logger.debug("Dashboard: Enhancing student #{student.id} with ATS data")

    # Get ATS data for additional information with error handling
    ats_phase =
      try do
        StudentAts.get_by_student_id(student.id, tenant_schema)
      rescue
        e ->
          Logger.error("Failed to get ATS data for student #{student.id}: #{inspect(e)}")
          nil
      end

    # Student table doesn't have resume fields - get them from ATS phase
    resume_url = ats_phase && ats_phase.resume_url
    resume_filename = ats_phase && ats_phase.resume_url && Path.basename(ats_phase.resume_url)
    ats_score = ats_phase && ats_phase.ats_score
    preferred_role = ats_phase && ats_phase.preferred_role

    Logger.debug(
      "Dashboard: Student #{student.id} - ATS phase found: #{!is_nil(ats_phase)}, Resume URL: #{!is_nil(resume_url)}"
    )

    # Pull MCQ assessment proctoring flags for this student — read straight from
    # each attempt's metadata.violations, so violations surface even when the
    # attempt was force-closed at the strike limit or abandoned (the old path
    # only read the latest *submitted* attempt's computed evaluation_data flags).
    mcq_integrity_flags =
      try do
        VyaasaCampus.Contexts.Assessments.student_integrity_flags(student.id, tenant_schema)
      rescue
        e ->
          Logger.error("integrity_flags(MCQ) failed for #{student.id}: #{inspect(e)}")
          []
      end

    # Plus integrity flags from terminated interview sessions (content moderation).
    interview_integrity_flags =
      try do
        VyaasaCampus.Contexts.Interview.student_integrity_flags(student.id, tenant_schema)
      rescue
        _ -> []
      end

    # Plus proctoring violations logged during behavioral assessments.
    behavioral_integrity_flags =
      try do
        VyaasaCampus.Contexts.Behavioral.student_integrity_flags(student.id, tenant_schema)
      rescue
        _ -> []
      end

    # Plus response-validity + proctoring flags from psychometric assessments.
    psychometric_integrity_flags =
      try do
        VyaasaCampus.Contexts.Psychometric.student_integrity_flags(student.id, tenant_schema)
      rescue
        _ -> []
      end

    # Plus proctoring flags from case-study assessments.
    case_study_integrity_flags =
      try do
        VyaasaCampus.Contexts.CaseStudy.student_integrity_flags(student.id, tenant_schema)
      rescue
        _ -> []
      end

    # Plus proctoring flags from JAM sessions.
    jam_integrity_flags =
      try do
        VyaasaCampus.Contexts.Jam.student_integrity_flags(student.id, tenant_schema)
      rescue
        _ -> []
      end

    # Plus mini-project authenticity/forensics flags (file metadata + git + timing).
    mini_project_integrity_flags =
      try do
        VyaasaCampus.Contexts.MiniProject.student_integrity_flags(student.id, tenant_schema)
      rescue
        _ -> []
      end

    integrity_flags =
      mcq_integrity_flags ++
        interview_integrity_flags ++
        behavioral_integrity_flags ++
        psychometric_integrity_flags ++
        case_study_integrity_flags ++ jam_integrity_flags ++ mini_project_integrity_flags

    # Get assessment scores for this student
    score_summary =
      try do
        StudentRankings.get_student_score_summary(student.id, tenant_schema)
      rescue
        _ ->
          %{
            mcq_percentage: nil,
            behavioral_score: nil,
            jam_score: nil,
            interview_score: nil,
            psychometric_score: nil,
            case_study_score: nil,
            mini_project_score: nil,
            completed_assessments: 0
          }
      end

    # The composite AI8 score is attached in bulk by the caller (one query for the
    # whole list instead of three per student) — see attach_ai8_scores/2.

    # Safely merge student data
    try do
      Map.merge(student, %{
        resume_url: resume_url,
        resume_filename: resume_filename,
        ats_score: ats_score,
        preferred_role: preferred_role,
        integrity_flags: integrity_flags,
        mcq_percentage: score_summary.mcq_percentage,
        behavioral_score: score_summary.behavioral_score,
        jam_score: score_summary.jam_score,
        interview_score: score_summary.interview_score,
        psychometric_score: score_summary.psychometric_score,
        case_study_score: Map.get(score_summary, :case_study_score),
        mini_project_score: Map.get(score_summary, :mini_project_score),
        ai8_score: nil
      })
    rescue
      e ->
        Logger.error("Failed to enhance student #{student.id}: #{inspect(e)}")
        student
    end
  end

  @doc """
  Load ONE student fully enhanced (ATS, module scores, AI8) — the targeted
  counterpart of `load_all_students_with_scores/2`.

  Used by the live-update path: a score event names a single student, so we
  refresh that student's row (~7 queries, tens of ms) and splice it into the
  in-memory list rather than reloading the whole tenant, which costs seconds
  once a tenant has hundreds of students.
  """
  def load_student_with_scores(student_id, tenant_schema) do
    case Students.get_student(student_id, tenant_schema) do
      nil ->
        nil

      student ->
        student
        |> enhance_student_with_ats_data(tenant_schema)
        |> List.wrap()
        |> attach_ai8_scores(tenant_schema)
        |> List.first()
    end
  rescue
    e ->
      Logger.error("load_student_with_scores failed for #{student_id}: #{inspect(e)}")
      nil
  end

  @doc """
  Attach the composite AI8 score to a list of enhanced students.

  Uses `AI8.ai8_indexes/2` — a fixed three queries for the whole list — so the
  admin list, the PDF reports and the student's own AI8 Overview all read the same
  engine and can never disagree.
  """
  def attach_ai8_scores(students, tenant_schema) do
    profiles = VyaasaCampus.Contexts.AI8.ai8_indexes(Enum.map(students, & &1.id), tenant_schema)

    Enum.map(students, fn s ->
      card = StudentRankings.score_card(profiles[s.id])
      Map.merge(s, %{ai8_score: card.ai8_score, ai8_completed: card.completed_count, ai8_total: card.total_assessments})
    end)
  rescue
    e ->
      Logger.error("attach_ai8_scores failed for #{tenant_schema}: #{inspect(e)}")
      students
  end

  defp get_filter_display_name(filter) do
    case filter do
      "unverified" -> "unverified"
      "verified" -> "verified"
      "all" -> "total"
      _ -> "unknown"
    end
  end

  defp get_user_info(current_user) do
    require Logger

    case current_user do
      nil ->
        Logger.warning("Dashboard: current_user is nil")
        build_default_user_info()

      %{__struct__: _} = user ->
        # Handle Ecto structs
        extract_user_info_from_struct(user)

      user when is_map(user) ->
        # Handle plain maps
        extract_user_info_from_map(user)

      _ ->
        Logger.warning("Dashboard: current_user is not a map or struct: #{inspect(current_user)}")
        build_default_user_info()
    end
  end

  defp build_default_user_info do
    %{
      name: "Unknown User",
      email: "unknown@example.com",
      role: "Unknown",
      status: "Unknown",
      last_login: nil
    }
  end

  defp extract_user_info_from_struct(user) do
    require Logger

    email = user.email
    first_name = user.first_name || ""
    last_name = user.last_name || ""
    role = user.role || "Unknown"
    status = user.status || "Unknown"
    last_login_at = user.last_login_at

    name = build_user_name(first_name, last_name)
    last_login = format_last_login(last_login_at)

    Logger.info("Dashboard: Extracted user info from struct - name: #{name}, email: #{email}, role: #{role}")

    %{
      name: name,
      email: email || "unknown@example.com",
      role: role,
      status: status,
      last_login: last_login
    }
  end

  defp extract_user_info_from_map(user) do
    require Logger

    email = get_field_value(user, [:email, "email"])
    first_name = get_field_value(user, [:first_name, "first_name"]) || ""
    last_name = get_field_value(user, [:last_name, "last_name"]) || ""
    role = get_field_value(user, [:role, "role"]) || "Unknown"
    status = get_field_value(user, [:status, "status"]) || "Unknown"
    last_login_at = get_field_value(user, [:last_login_at, "last_login_at"])

    name = build_user_name(first_name, last_name)
    last_login = format_last_login(last_login_at)

    Logger.info("Dashboard: Extracted user info from map - name: #{name}, email: #{email}, role: #{role}")

    %{
      name: name,
      email: email || "unknown@example.com",
      role: role,
      status: status,
      last_login: last_login
    }
  end

  defp get_field_value(user, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(user, key)
    end)
  end

  defp build_user_name(first_name, last_name) do
    name = "#{first_name} #{last_name}" |> String.trim()
    if name == "", do: "Unknown User", else: name
  end

  defp format_last_login(nil), do: nil
  defp format_last_login(last_login_at), do: DateTimeFormatter.format_datetime(last_login_at)

  # Helper functions for route handling
  defp setup_initial_view(socket) do
    socket
    |> assign(:current_view, :student_list)
    |> assign(:show_add_student, false)
    |> assign(:add_student_form, nil)
    |> assign(:add_student_errors, [])
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:current_view, :student_list)
    |> assign(:show_add_student, false)
    |> assign(:add_student_form, nil)
    |> assign(:add_student_errors, [])
  end

  defp apply_action(socket, :add_student, _params) do
    alias VyaasaCampus.Schema.Students.Student

    # Create a changeset and then a form for the new student
    changeset = Student.form_validation_changeset(%Student{}, %{})
    form = to_form(changeset, as: :student)

    socket
    |> assign(:current_view, :add_student)
    |> assign(:show_add_student, true)
    |> assign(:add_student_form, form)
    |> assign(:add_student_errors, [])
  end

  defp apply_search_filter(students, search) when search == "", do: students

  defp apply_search_filter(students, search) do
    search_term = String.downcase(search)

    Enum.filter(students, fn student ->
      first_name = String.downcase(student.first_name || "")
      last_name = String.downcase(student.last_name || "")
      email = String.downcase(student.email || "")
      registration_id = String.downcase(student.registration_id || "")

      String.contains?(first_name, search_term) or
        String.contains?(last_name, search_term) or
        String.contains?(email, search_term) or
        String.contains?(registration_id, search_term)
    end)
  end

  defp apply_year_filter(students, year) when year in [nil, "", "all"], do: students

  defp apply_year_filter(students, year) do
    Enum.filter(students, fn student ->
      to_string(student.year_of_passing) == to_string(year)
    end)
  end

  defp unique_student_years(students) do
    students
    |> Enum.map(&Map.get(&1, :year_of_passing))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  defp load_job_roles(nil, _tenant_schema), do: []

  defp load_job_roles(tenant, tenant_schema) do
    JobProfiles.list_by_tenant(tenant.id, tenant_schema)
    |> Enum.map(& &1.role)
  rescue
    _ -> []
  end

  # Score display helpers

  defp safe_score_val(%Decimal{} = d), do: Decimal.to_float(d)
  defp safe_score_val(n) when is_number(n), do: n
  defp safe_score_val(_), do: 0

  defp safe_score_display(%Decimal{} = d), do: round(Decimal.to_float(d))
  defp safe_score_display(n) when is_number(n), do: round(n)
  defp safe_score_display(_), do: "-"

  # Load all verified students with full score data for stats
  @doc """
  Loads all verified/unverified students for the given tenant schema,
  enhancing each with ATS + assessment scores. Public so server-side PDF
  reports (`VyaasaCampus.Reports`) can regenerate leaderboard/specialization
  data from the same pipeline the LiveView uses.
  """
  @doc """
  Load students with their ATS-derived scores. `statuses` filters by status
  (default ["verified","unverified"] — students who have engaged, used by the
  dashboard/cross-tenant aggregations). Pass `:all` to include every student
  (pending/profile_incomplete/active too) — used by the admin Students roster.
  """
  def load_all_students_with_scores(tenant_schema, statuses \\ ["verified", "unverified"]) do
    try do
      Students.list_students(tenant_schema)
      |> filter_by_statuses(statuses)
      |> Enum.map(&enhance_student_with_ats_data(&1, tenant_schema))
      |> attach_ai8_scores(tenant_schema)
    rescue
      e ->
        # Don't silently blank the whole dashboard (and every integrity flag) —
        # surface why so it's diagnosable instead of just showing nothing.
        Logger.error("load_all_students_with_scores failed for #{tenant_schema}: #{inspect(e)}")
        []
    end
  end

  defp filter_by_statuses(list, :all), do: list
  defp filter_by_statuses(list, statuses) when is_list(statuses), do: Enum.filter(list, &(&1.status in statuses))

  defp sort_students(students, field, dir) do
    sorter = fn student ->
      val =
        case field do
          "ai8_score" -> Map.get(student, :ai8_score) || -1
          "ats_score" -> safe_score_val(Map.get(student, :ats_score)) || -1
          "mcq_percentage" -> Map.get(student, :mcq_percentage) || -1
          "behavioral_score" -> Map.get(student, :behavioral_score) || -1
          "jam_score" -> Map.get(student, :jam_score) || -1
          "interview_score" -> Map.get(student, :interview_score) || -1
          "psychometric_score" -> Map.get(student, :psychometric_score) || -1
          "name" -> "#{student.first_name} #{student.last_name}" |> String.downcase()
          _ -> Map.get(student, :ai8_score) || -1
        end

      val
    end

    order = if dir == "asc", do: :asc, else: :desc
    Enum.sort_by(students, sorter, order)
  end

  defp assign_degree_options(socket, tenant) do
    if tenant do
      {degree_opts, spec_opts} = VyaasaCampus.Contexts.Academics.get_tenant_degree_options(tenant.id)

      # Fall back to nil (component will use defaults) if tenant has no selections
      {degree_opts, spec_opts} =
        if length(degree_opts) <= 1 and length(spec_opts) <= 1 do
          {nil, nil}
        else
          {degree_opts, spec_opts}
        end

      socket
      |> assign(:degree_options, degree_opts)
      |> assign(:specialization_options, spec_opts)
    else
      socket
      |> assign(:degree_options, nil)
      |> assign(:specialization_options, nil)
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
end
