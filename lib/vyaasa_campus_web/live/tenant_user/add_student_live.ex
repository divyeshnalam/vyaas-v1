defmodule VyaasaCampusWeb.TenantUser.AddStudentLive do
  @moduledoc """
  LiveView for adding students in tenant dashboard.
  Connects to backend student creation API and handles form validation.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.{Academics, Students, Tenants}
  alias VyaasaCampus.Schema.Students.Student
  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.TenantAdmin.AdminShell

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    require Logger

    Logger.info("AddStudentLive mount - tenant_alias: #{tenant_alias}")

    # Get tenant information
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    current_user = socket.assigns[:current_user]

    if tenant && current_user do
      # Initialize form with empty student changeset
      changeset = Student.changeset(%Student{}, %{})
      form = to_form(changeset)

      socket =
        socket
        |> assign(:tenant_alias, tenant_alias)
        |> assign(:tenant, tenant)
        |> assign(:current_scope, :tenant_admin)
        |> assign(:current_section, "students")
        |> assign(:user_info, get_user_info(current_user))
        |> assign(:form, form)
        |> assign(:changeset, changeset)
        |> assign(load_degree_options(tenant.id))
        |> assign(:specialization_options, [{"Select specialization", ""}])
        |> assign(:specializations_by_degree, load_specializations_by_degree(tenant.id))
        |> assign(:errors, [])
        |> assign(:loading, false)
        |> assign(:page_title, "Add Student - #{tenant.full_name}")

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "Tenant not found or unauthorized access")
       |> redirect(to: ~p"/auth/tenant/#{tenant_alias}/login")}
    end
  end

  @impl true
  def handle_event("validate_student", %{"student" => student_params}, socket) do
    changeset =
      %Student{}
      |> Student.changeset(student_params)
      |> Map.put(:action, :validate)

    form = to_form(changeset)

    specialization_options =
      specialization_options_for(socket.assigns.specializations_by_degree, student_params["degree"])

    {:noreply,
     socket
     |> assign(form: form, changeset: changeset)
     |> assign(:specialization_options, specialization_options)}
  end

  @impl true
  def handle_event("save_student", %{"student" => student_params}, socket) do
    socket = assign(socket, :loading, true)

    # Add tenant_id to student params
    tenant_id = socket.assigns.tenant.id
    student_params_with_tenant = Map.put(student_params, "tenant_id", tenant_id)

    case create_student_via_context(student_params_with_tenant, socket) do
      {:ok, _student} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:info, "Student created successfully! Profile completion email sent.")
         |> push_navigate(to: ~p"/user/#{socket.assigns.tenant_alias}/dashboard/students")}

      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(changeset)
        errors = extract_changeset_errors(changeset)

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:form, form)
         |> assign(:changeset, changeset)
         |> assign(:errors, errors)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:errors, [reason])
         |> put_flash(:error, "Failed to create student: #{reason}")}
    end
  end

  @impl true
  def handle_event("upload_resume", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("show_coming_soon", _params, socket) do
    {:noreply, put_flash(socket, :info, "Coming soon!")}
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Logged out successfully")
     |> redirect(to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.admin_layout
        tenant_alias={@tenant_alias}
        tenant_name={@tenant.full_name}
        current_section={@current_section}
        user_info={@user_info}
      >
        <.form for={@form} phx-change="validate_student" phx-submit="save_student" id="add-student-form">
          <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-[1100px] mx-auto w-full">
            <!-- Heading + actions -->
            <div class="flex flex-wrap items-start justify-between gap-4 mb-6">
              <div>
                <p class="text-[11px] font-bold uppercase tracking-[0.14em] text-[#F97316] mb-1">Students</p>
                <div class="flex items-center gap-2">
                  <.link navigate={~p"/user/#{@tenant_alias}/dashboard/students"} class="text-gray-400 hover:text-gray-700">
                    <.icon name="hero-arrow-left" class="w-5 h-5" />
                  </.link>
                  <h1 class="text-2xl font-bold text-gray-900">Add Student</h1>
                </div>
                <p class="text-sm text-gray-500 mt-0.5">Onboard a student and auto-assign their assessments.</p>
              </div>
              <div class="flex items-center gap-2">
                <.link navigate={~p"/user/#{@tenant_alias}/dashboard/students"} class="px-4 py-2 rounded-lg text-sm font-medium text-gray-600 hover:bg-gray-50 transition">
                  Cancel
                </.link>
                <button type="button" phx-click="show_coming_soon" class="px-4 py-2 rounded-lg border border-gray-200 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50 transition">
                  Save Draft
                </button>
                <button type="submit" disabled={@loading} class="inline-flex items-center gap-1.5 px-5 py-2 rounded-lg text-sm font-semibold text-white transition disabled:opacity-60" style="background-color: #F97316;">
                  {if @loading, do: "Creating…", else: "Create Student"}
                </button>
              </div>
            </div>

            <div :if={@errors != []} class="mb-5 rounded-lg p-3 text-sm bg-red-50 border border-red-200 text-red-700">
              <p :for={e <- @errors}>{e}</p>
            </div>

            <!-- Personal details -->
            <.form_card title="Personal Details">
              <.admin_input
                field={@form[:first_name]}
                label="First Name"
                placeholder="Anya"
                pattern="[A-Za-z\s]+"
                title="Only letters are allowed"
                phx_hook="LettersOnly"
              />
              <.admin_input field={@form[:middle_name]} label="Middle Name" placeholder="—" optional />
              <.admin_input
                field={@form[:last_name]}
                label="Last Name"
                placeholder="Forger"
                pattern="[A-Za-z\s]+"
                title="Only letters are allowed"
                phx_hook="LettersOnly"
              />
              <.admin_input field={@form[:email]} label="Email" type="email" placeholder="anya07@college.edu" />
              <.admin_input
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
              <.admin_input
                field={@form[:registration_id]}
                label="Registration Number"
                placeholder="105"
                pattern="[A-Za-z0-9].*"
                title="Registration number must start with a letter or number"
              />
            </.form_card>

            <!-- Academic details -->
            <.form_card title="Academic Details">
              <.admin_select field={@form[:degree]} label="Department" options={@degree_options} />
              <.admin_select field={@form[:specialization]} label="Specialization" options={@specialization_options} />
              <.admin_input field={@form[:cgpa]} label="CGPA" placeholder="8.7" />
              <.admin_input field={@form[:year_of_passing]} label="Year of Passing" type="number" placeholder="2026" />
            </.form_card>
          </div>
        </.form>
      </.admin_layout>
    </Layouts.app>
    """
  end

  # ── Form pieces ────────────────────────────────────────────────────────────
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp form_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6 mb-5">
      <h3 class="text-[11px] font-bold uppercase tracking-[0.12em] text-gray-500 mb-4">{@title}</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, default: ""
  attr :type, :string, default: "text"
  attr :optional, :boolean, default: false
  attr :pattern, :string, default: nil
  attr :title, :string, default: nil
  attr :inputmode, :string, default: nil
  attr :maxlength, :string, default: nil
  attr :phx_hook, :string, default: nil

  defp admin_input(assigns) do
    ~H"""
    <div>
      <label for={@field.id} class="block text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 mb-1.5">
        {@label}<span :if={@optional} class="normal-case text-gray-300"> (Optional)</span>
      </label>
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
        class="w-full px-3 py-2 rounded-lg bg-white border border-gray-200 text-sm text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-100 focus:border-[#F97316]"
      />
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :options, :list, default: []

  defp admin_select(assigns) do
    ~H"""
    <div>
      <label for={@field.id} class="block text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 mb-1.5">{@label}</label>
      <select
        name={@field.name}
        id={@field.id}
        class="w-full px-3 py-2 rounded-lg bg-white border border-gray-200 text-sm text-gray-800 focus:outline-none focus:ring-2 focus:ring-orange-100 focus:border-[#F97316]"
      >
        <option :for={{label, value} <- @options} value={value} selected={to_string(@field.value) == to_string(value)}>{label}</option>
      </select>
    </div>
    """
  end

  # Private functions

  # Tenant's selected degrees + specializations as form dropdown options
  # ({label, value} lists with a leading placeholder). Degrades to a single
  # placeholder option if academics aren't configured.
  defp load_degree_options(tenant_id) do
    {degrees, specializations} = Academics.get_tenant_degree_options(tenant_id)
    %{degree_options: degrees, specialization_options: specializations}
  rescue
    _ -> %{degree_options: [{"Select degree", ""}], specialization_options: [{"Select specialization", ""}]}
  end

  defp load_specializations_by_degree(tenant_id) do
    Academics.get_tenant_specializations_by_degree(tenant_id)
  rescue
    _ -> %{}
  end

  # Specialization options scoped to the chosen department, so this dropdown
  # never shows specializations (or duplicate names) from other degrees.
  # No department selected yet → just the placeholder.
  defp specialization_options_for(specializations_by_degree, degree_name) do
    case Map.get(specializations_by_degree, degree_name) do
      nil -> [{"Select specialization", ""}]
      specs -> [{"Select specialization", ""} | specs]
    end
  end

  defp get_user_info(nil), do: %{name: "User", email: "", role: ""}

  defp get_user_info(user) do
    %{
      name: "#{user.first_name} #{user.last_name}" |> String.trim(),
      email: user.email || "",
      role: user.role || ""
    }
  end

  defp create_student_via_context(student_params, socket) do
    # Prepare params for the context call
    context_params = prepare_context_params(student_params, socket)

    # Call the Students context to create the student
    tenant_schema = socket.assigns.tenant.schema_name
    tenant_alias = socket.assigns.tenant_alias

    case Students.create_student(context_params, tenant_alias, tenant_schema) do
      {:ok, student} ->
        {:ok, student}

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        {:error, changeset}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      _ ->
        {:error, "Unknown error occurred"}
    end
  end

  defp prepare_context_params(student_params, socket) do
    tenant_id = socket.assigns.tenant.id
    current_user = socket.assigns[:current_user]

    student_params
    |> Map.put("tenant_id", tenant_id)
    |> Map.put("created_by_id", current_user.id)
    |> Map.put("created_by_type", "tenant")
    |> clean_empty_values()
  end

  defp clean_empty_values(params) do
    params
    |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)
    |> Map.new()
  end

  defp extract_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{Phoenix.Naming.humanize(field)}: #{Enum.join(errors, ", ")}"
    end)
  end
end
