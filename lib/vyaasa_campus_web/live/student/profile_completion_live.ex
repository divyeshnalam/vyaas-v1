defmodule VyaasaCampusWeb.Student.ProfileCompletionLive do
  @moduledoc """
  Multi-step student profile completion LiveView.

  This handles the complete student onboarding flow:
  1. Profile Creation - Basic info and document uploads
  2. ATS Analysis - Resume analysis with interactive score feedback
  3. Verification - Final admin verification
  """

  use VyaasaCampusWeb, :live_view

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Student.ProfileCompletion.StepRenderers

  import Phoenix.LiveView,
    only: [
      consume_uploaded_entries: 3,
      uploaded_entries: 2,
      cancel_upload: 3,
      allow_upload: 3,
      put_flash: 3,
      push_navigate: 2,
      redirect: 2
    ]

  alias VyaasaCampus.Contexts.{Students, Tenant.JobProfiles, Tenants, StudentAts, Jobs}
  alias VyaasaCampusWeb.Student.ProfileCompletion.{AtsDataHelpers, LoadingState, AtsService}
  alias VyaasaCampusWeb.Student.Reanalyze.ReanalyzeService

  # 5MB max file size
  @max_file_size 5_000_000

  @impl true
  def mount(%{"profile_token" => profile_token} = params, _session, socket) do
    tenant_alias = params["tenant"] || "KLEF"

    socket = base_assigns(socket, tenant_alias, reanalyze: false)
    socket = assign(socket, :profile_token, profile_token)

    # Load student data via profile_token verification
    socket = load_student_data(socket)

    if socket.assigns.student do
      Phoenix.PubSub.subscribe(VyaasaCampus.PubSub, "student:#{socket.assigns.student.id}:ats_processing")
    end

    {:ok, socket}
  end

  # Authenticated re-analysis mount — uses current_user instead of profile_token.
  # Accessible via /student/:tenant/resume/reanalyze after login.
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    current_user = socket.assigns[:current_user]

    case current_user do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Authentication required")
         |> push_navigate(to: "/auth/tenant/#{tenant_alias}/login")}

      user ->
        socket = base_assigns(socket, tenant_alias, reanalyze: true)
        socket = load_authenticated_student_data(socket, user)

        if socket.assigns.student do
          Phoenix.PubSub.subscribe(
            VyaasaCampus.PubSub,
            "student:#{socket.assigns.student.id}:ats_processing"
          )
        end

        {:ok, socket}
    end
  end

  defp base_assigns(socket, tenant_alias, opts) do
    reanalyze? = Keyword.get(opts, :reanalyze, false)

    socket
    |> assign(:profile_token, nil)
    |> assign(:current_step, 1)
    |> assign(:max_steps, 3)
    |> assign(:completion_percentage, 10)
    |> assign(:student, nil)
    |> assign(:tenant_alias, tenant_alias)
    |> assign(:loading?, true)
    |> assign(:error_message, nil)
    |> assign(:current_scope, if(reanalyze?, do: :student, else: :student_profile_completion))
    |> assign(:page_title, if(reanalyze?, do: "Re-analyze Resume", else: "Complete Your Profile"))
    |> assign(:processing_timeout, false)
    |> assign(:profile_form, to_form(%{}, as: :profile))
    |> assign(:skills_form, to_form(%{}, as: :skills))
    |> assign(:selected_skills, [])
    |> assign(:work_experiences, [
      %{job_title: "", company_name: "", start_date: "", end_date: "", responsibilities: ""}
    ])
    |> assign(:languages, [])
    |> assign(:external_links, %{})
    |> assign(:preferred_job_role, "")
    |> assign(:job_roles, [])
    |> assign(:ats_data, nil)
    |> assign(:ats_phase, nil)
    |> assign(:processing_after_step1?, false)
    |> assign(:processing_request_id, nil)
    |> assign(:reanalyze_mode?, reanalyze?)
    |> assign(:ats_score, nil)
    |> assign(:ats_feedback, [])
    |> assign(:ats_processing?, false)
    |> assign(:education, [])
    |> assign(:projects, [])
    |> assign(:show_completeness_feedback, false)
    |> assign(:show_relevance_feedback, false)
    |> assign(:show_sanity_feedback, false)
    |> assign(:user_info, nil)
    |> assign(:photo_status, nil)
    |> allow_upload(:resume,
      accept: ~w(.pdf .docx),
      max_entries: 1,
      max_file_size: @max_file_size,
      auto_upload: true
    )
    |> allow_upload(:id_card,
      accept: ~w(.jpg .jpeg .png .pdf),
      max_entries: 1,
      max_file_size: @max_file_size,
      auto_upload: true
    )
    |> allow_upload(:profile_photo,
      accept: ~w(.jpg .jpeg .png),
      max_entries: 1,
      max_file_size: @max_file_size,
      auto_upload: true,
      progress: &handle_progress/3
    )
    |> allow_upload(:certification,
      accept: ~w(.pdf .jpg .jpeg .png),
      max_entries: 1,
      max_file_size: @max_file_size,
      auto_upload: true
    )
  end

  defp load_authenticated_student_data(socket, user) do
    tenant_alias = socket.assigns.tenant_alias
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    tenant_schema = tenant && tenant.schema_name

    student_record = tenant_schema && Students.get_student(user.id, tenant_schema)

    if student_record do
      # Build a student-like map matching what load_student_data produces
      student_data = %{
        id: student_record.id,
        first_name: student_record.first_name,
        last_name: student_record.last_name,
        email: student_record.email,
        registration_id: Map.get(student_record, :registration_id),
        degree: Map.get(student_record, :degree),
        specialization: Map.get(student_record, :specialization),
        year_of_passing: Map.get(student_record, :year_of_passing),
        cgpa: Map.get(student_record, :cgpa),
        tenant_id: student_record.tenant_id,
        profile_token: Map.get(student_record, :profile_token)
      }

      ats_data = AtsDataHelpers.load_ats_data(student_data.id, tenant_alias)
      ats_phase = load_ats_phase_for_student(student_data.id, tenant_alias)
      job_roles = load_job_roles(tenant_alias)

      user_info = %{
        name: "#{student_record.first_name} #{student_record.last_name}",
        role: "Student",
        email: student_record.email,
        profile_picture_url: ats_phase && ats_phase.profile_picture_url
      }

      socket
      |> assign(:student, student_data)
      |> assign(:ats_data, ats_data)
      |> assign(:ats_phase, ats_phase)
      |> assign(:job_roles, job_roles)
      |> assign(:preferred_job_role, (ats_phase && ats_phase.preferred_role) || "")
      |> assign(:user_info, user_info)
      |> assign(:loading?, false)
      |> AtsDataHelpers.populate_form_data_from_ats(ats_data)
    else
      socket
      |> assign(:loading?, false)
      |> assign(:error_message, "Student record not found in this tenant.")
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Preserve reanalyze_mode? set by mount (true for authenticated route,
    # false for profile_token route). Only flip to true if URL explicitly
    # requests it via ?mode=reanalyze — never flip back to false here.
    socket =
      if params["mode"] == "reanalyze" do
        assign(socket, :reanalyze_mode?, true)
      else
        socket
      end

    case params["step"] do
      step when step in ["2", "3"] ->
        step_num = String.to_integer(step)
        completion = calculate_completion(step_num, socket.assigns.max_steps)

        {:noreply,
         socket
         |> assign(:current_step, step_num)
         |> assign(:completion_percentage, completion)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_step", _params, socket) do
    require Logger
    current_step = socket.assigns.current_step
    max_steps = socket.assigns.max_steps

    Logger.info("NEXT_STEP - Current step: #{current_step}, Max steps: #{max_steps}")

    cond do
      current_step == 1 ->
        Logger.info("NEXT_STEP - Step 1, checking required data...")
        # After step 1, check if we have required data and trigger Python processing
        if has_required_data_for_processing?(socket) do
          Logger.info("NEXT_STEP - Required data check passed, starting processing...")

          socket =
            socket
            |> assign(:processing_after_step1?, true)
            |> trigger_python_processing()

          {:noreply, socket}
        else
          Logger.info("NEXT_STEP - Required data check failed")
          msg =
            if socket.assigns[:reanalyze_mode?] do
              "Please upload a new resume and select a job role to re-analyze."
            else
              "Please upload resume, ID card and select a job role to continue."
            end
          {:noreply, put_flash(socket, :error, msg)}
        end

      current_step == 2 and socket.assigns[:reanalyze_mode?] and socket.assigns.ats_data ->
        # Re-analysis doesn't go through admin verification — send the
        # student straight to their (already updated) insights page instead
        # of the first-time-signup "awaiting admin verification" step.
        {:noreply,
         push_navigate(socket, to: ~p"/student/#{socket.assigns.tenant_alias}/resume/insights")}

      current_step < max_steps and socket.assigns.ats_data ->
        # Leaving step 2 ("Continue to Verification") is the one moment the
        # profile_token is invalidated — the student has now explicitly
        # confirmed submission, so it's safe for the link to stop working.
        # Doing this any earlier (e.g. right after scoring) meant a refresh
        # or dropped connection while still reviewing the score would wrongly
        # show "already submitted" before the student ever clicked anything.
        if current_step == 2 do
          finalize_profile_submission(socket)
        end

        new_step = current_step + 1
        completion_percentage = calculate_completion(new_step, max_steps)

        socket =
          socket
          |> assign(:current_step, new_step)
          |> assign(:completion_percentage, completion_percentage)

        {:noreply, socket}

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("prev_step", _params, socket) do
    current_step = socket.assigns.current_step

    if current_step > 1 do
      new_step = current_step - 1
      completion_percentage = calculate_completion(new_step, socket.assigns.max_steps)

      socket =
        socket
        |> assign(:current_step, new_step)
        |> assign(:completion_percentage, completion_percentage)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_skill", %{"skill" => skill}, socket) do
    if skill != "" and skill not in socket.assigns.selected_skills do
      updated_skills = [skill | socket.assigns.selected_skills]
      {:noreply, assign(socket, :selected_skills, updated_skills)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_skill", %{"skill" => skill}, socket) do
    updated_skills = List.delete(socket.assigns.selected_skills, skill)
    {:noreply, assign(socket, :selected_skills, updated_skills)}
  end

  @impl true
  def handle_event("add_work_experience", _params, socket) do
    new_experience = %{job_title: "", company_name: "", start_date: "", end_date: "", responsibilities: ""}
    updated_experiences = socket.assigns.work_experiences ++ [new_experience]
    {:noreply, assign(socket, :work_experiences, updated_experiences)}
  end

  @impl true
  def handle_event("add_language", %{"language" => language}, socket) do
    if language != "" and language not in socket.assigns.languages do
      updated_languages = [language | socket.assigns.languages]
      {:noreply, assign(socket, :languages, updated_languages)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_job_role", %{"job_role" => job_role}, socket) do
    {:noreply, assign(socket, :preferred_job_role, job_role)}
  end

  @impl true
  def handle_event("toggle_feedback", %{"section" => section}, socket) do
    # Only one section open at a time — clicking an open section closes it,
    # clicking a different section closes the current one and opens the new one
    case section do
      "completeness" ->
        current = socket.assigns.show_completeness_feedback

        {:noreply,
         socket
         |> assign(:show_completeness_feedback, !current)
         |> assign(:show_relevance_feedback, false)
         |> assign(:show_sanity_feedback, false)}

      "relevance" ->
        current = socket.assigns.show_relevance_feedback

        {:noreply,
         socket
         |> assign(:show_relevance_feedback, !current)
         |> assign(:show_completeness_feedback, false)
         |> assign(:show_sanity_feedback, false)}

      "sanity" ->
        current = socket.assigns.show_sanity_feedback

        {:noreply,
         socket
         |> assign(:show_sanity_feedback, !current)
         |> assign(:show_completeness_feedback, false)
         |> assign(:show_relevance_feedback, false)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("retry_verification", _params, socket) do
    socket =
      socket
      |> assign(:loading?, true)
      |> assign(:error_message, nil)
      |> load_student_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_profile", %{"profile" => _profile_params}, socket) do
    # Handle profile form validation
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_skills", %{"skills" => _skills_params}, socket) do
    # Handle skills form validation
    {:noreply, socket}
  end

  # File upload handlers
  @impl true
  def handle_event("validate_resume", _params, socket) do
    require Logger
    resume_entries = uploaded_entries(socket, :resume)
    Logger.info("VALIDATE_RESUME - Resume entries: #{inspect(resume_entries)}")

    # Check if any resume files are done
    done_count =
      resume_entries
      |> elem(0)
      |> Enum.count(fn entry -> entry.done? end)

    Logger.info("VALIDATE_RESUME - Done count: #{done_count}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_id_card", _params, socket) do
    require Logger
    id_card_entries = uploaded_entries(socket, :id_card)
    Logger.info("VALIDATE_ID_CARD - ID card entries: #{inspect(id_card_entries)}")

    # Check if any ID card files are done
    done_count =
      id_card_entries
      |> elem(0)
      |> Enum.count(fn entry -> entry.done? end)

    Logger.info("VALIDATE_ID_CARD - Done count: #{done_count}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_profile_photo", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_resume", _params, socket) do
    require Logger
    Logger.info("UPLOAD_RESUME - Resume upload submitted")

    # Consume uploaded entries to mark them as done
    uploaded_files =
      consume_uploaded_entries(socket, :resume, fn %{path: path}, entry ->
        Logger.info("UPLOAD_RESUME - Consuming file: #{entry.client_name} from #{path}")
        {:ok, %{filename: entry.client_name, path: path}}
      end)

    Logger.info("UPLOAD_RESUME - Consumed files: #{length(uploaded_files)}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_id_card", _params, socket) do
    require Logger
    Logger.info("UPLOAD_ID_CARD - ID card upload submitted")

    # Consume uploaded entries to mark them as done
    uploaded_files =
      consume_uploaded_entries(socket, :id_card, fn %{path: path}, entry ->
        Logger.info("UPLOAD_ID_CARD - Consuming file: #{entry.client_name} from #{path}")
        {:ok, %{filename: entry.client_name, path: path}}
      end)

    Logger.info("UPLOAD_ID_CARD - Consumed files: #{length(uploaded_files)}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_profile_photo", _params, socket) do
    {:noreply, elem(persist_profile_photo(socket), 1)}
  end

  @impl true
  # The photo is already persisted by the time its "x" is clickable (see
  # handle_progress/3 below — it only shows once uploading finishes), so
  # unlike cancel_upload/2 (which drops a staged entry) this has to clear the
  # saved record too, otherwise the stale photo would resurface on refresh.
  def handle_event("remove_profile_photo", _params, socket) do
    require Logger
    %{student: student, tenant_alias: tenant_alias} = socket.assigns

    socket =
      case Tenants.get_tenant_by_alias(String.upcase(tenant_alias)) do
        nil ->
          socket

        tenant ->
          with {:ok, ats_phase} <- StudentAts.ensure_profile_phase(student, tenant.schema_name),
               {:ok, updated} <-
                 StudentAts.update_profile_fields(ats_phase, %{profile_picture_url: nil}, tenant.schema_name) do
            assign(socket, :ats_phase, updated)
          else
            {:error, changeset} ->
              Logger.error(
                "REMOVE_PROFILE_PHOTO - Failed to clear profile photo for student #{student.id}: #{inspect(changeset.errors)}"
              )

              put_flash(socket, :error, "Couldn't remove your photo — please try again")
          end
      end

    {:noreply, assign(socket, :photo_status, nil)}
  end

  # `profile_photo` is allow_upload'd with auto_upload: true and its upload
  # form (VyaasaCampusWeb.Student.ProfileCompletion.DocumentUploads) has no
  # submit button — the file streams to the server as soon as it's picked,
  # but nothing ever fires a phx-submit to persist it. handle_progress/3 is
  # the callback LiveView actually invokes as the entry finishes streaming,
  # so that's where the photo must be saved for it to end up on the student's
  # record at all.
  defp handle_progress(:profile_photo, entry, socket) do
    if entry.done? do
      {status, socket} = persist_profile_photo(socket)
      state = if status == :ok, do: :saved, else: :error
      {:noreply, assign(socket, :photo_status, %{state: state, filename: entry.client_name})}
    else
      {:noreply, assign(socket, :photo_status, %{state: :uploading, filename: entry.client_name})}
    end
  end

  defp persist_profile_photo(socket) do
    require Logger
    %{student: student, tenant_alias: tenant_alias} = socket.assigns

    [url] =
      consume_uploaded_entries(socket, :profile_photo, fn %{path: path}, entry ->
        save_profile_photo(path, entry, student.tenant_id, student.id)
      end)

    case Tenants.get_tenant_by_alias(String.upcase(tenant_alias)) do
      nil ->
        Logger.error("UPLOAD_PROFILE_PHOTO - Unknown tenant alias #{tenant_alias}")
        {:error, put_flash(socket, :error, "Couldn't save your photo — please try again")}

      tenant ->
        with {:ok, ats_phase} <- StudentAts.ensure_profile_phase(student, tenant.schema_name),
             {:ok, updated} <-
               StudentAts.update_profile_fields(ats_phase, %{profile_picture_url: url}, tenant.schema_name) do
          Logger.info("UPLOAD_PROFILE_PHOTO - Saved profile photo for student #{student.id}")
          {:ok, assign(socket, :ats_phase, updated)}
        else
          {:error, changeset} ->
            Logger.error(
              "UPLOAD_PROFILE_PHOTO - Failed to persist profile photo for student #{student.id}: #{inspect(changeset.errors)}"
            )

            {:error, put_flash(socket, :error, "Couldn't save your photo — please try again")}
        end
    end
  end

  @impl true
  # Generate the resume/ATS analysis PDF and download it in the browser (Vya-031:
  # the button previously had no handler and did nothing).
  def handle_event("download_report", _params, socket) do
    with %{id: phase_id} <- socket.assigns[:ats_phase],
         %{schema_name: schema} <-
           Tenants.get_tenant_by_alias(String.upcase(socket.assigns.tenant_alias || "")),
         {:ok, pdf} <- VyaasaCampus.Reports.generate_pdf(:resume, phase_id, schema) do
      {:noreply,
       Phoenix.LiveView.push_event(socket, "download-file", %{
         content: Base.encode64(pdf),
         base64: true,
         filename: "Resume-Analysis-Report.pdf",
         mime: "application/pdf"
       })}
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, "Couldn't generate the report just yet — please try again in a moment.")}
    end
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref, "type" => type}, socket) do
    # Only cancel from the specific upload type, not all of them
    upload_key =
      case type do
        "resume" -> :resume
        "id_card" -> :id_card
        "profile_photo" -> :profile_photo
        "certification" -> :certification
        _ -> nil
      end

    socket =
      if upload_key do
        cancel_upload(socket, upload_key, ref)
      else
        socket
      end

    {:noreply, socket}
  end

  # Fallback for older clients that don't send :type — safer to no-op than
  # to blow away every upload as the old behavior did.
  def handle_event("cancel_upload", %{"ref" => _ref}, socket) do
    {:noreply, socket}
  end

  # The re-analyze view renders the student sidebar, whose Logout button pushes
  # this event. Without a clause for it the LiveView crashed on the unmatched
  # event and silently reconnected, so the button looked dead.
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
      <!-- Toast Container -->
      <div id="toast-container" phx-hook="ToastContainer" class="fixed top-4 right-4 z-50 space-y-2"></div>

      <%= if @reanalyze_mode? do %>
        <!-- Authenticated re-analysis: show sidebar + header chrome -->
        <div class="min-h-screen bg-gray-100 flex">
          <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar
            current_section="dashboard"
            tenant_alias={@tenant_alias}
          />

          <div class="flex-1 flex flex-col">
            <VyaasaCampusWeb.Components.Student.HeaderComponent.header
              user_info={@user_info || %{name: "Student", role: "Student", email: ""}}
              tenant_alias={@tenant_alias}
              page_title="Re-analyze Resume"
            />

            <main class="flex-1 bg-gray-50 overflow-auto">
              <div class="max-w-7xl mx-auto px-4 py-6">
                <!-- Back to Dashboard -->
                <div class="mb-4">
                  <.link
                    navigate={~p"/student/#{@tenant_alias}/dashboard"}
                    class="inline-flex items-center gap-2 text-sm text-gray-600 hover:text-gray-900"
                  >
                    <.icon name="hero-arrow-left" class="w-4 h-4" />
                    Back to Dashboard
                  </.link>
                </div>

                <.reanalyze_content {assigns} />
              </div>
            </main>
          </div>
        </div>
      <% else %>
        <!-- First-time profile completion (email link) — original standalone layout -->
        <.profile_completion_container {assigns} />
      <% end %>
    </Layouts.app>
    """
  end

  # First-time profile completion (email link). Standalone (unauthenticated)
  # page matching the Figma: an orange top rule, a centered "Student Profile
  # Completion" title + "vyaasa | {tenant}" subtitle, a horizontal 3-step
  # stepper (Profile Creation → Resume Analysis → Verification), then the step
  # content and a copyright footer.
  defp profile_completion_container(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 flex flex-col border-t-4 border-orange-500">
      <main class="flex-1">
        <div class="max-w-5xl mx-auto px-4 py-8">
          <!-- Title -->
          <div class="text-center mb-6">
            <h1 class="text-2xl md:text-3xl font-bold text-gray-900">Student Profile Completion</h1>
            <p class="text-sm text-gray-500 mt-1">vyaasa | {@tenant_alias}</p>
          </div>

          <!-- Horizontal 3-step stepper -->
          <.flow_stepper current_step={@current_step} :if={!@error_message} />

          <div class="mt-8">
            <%= if @loading? do %>
              <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-6 md:p-8 text-center py-12">
                <div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-orange-600"></div>
                <p class="mt-4 text-gray-600">Loading your profile information...</p>
              </div>
            <% else %>
              <%= if @error_message do %>
                <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-6 md:p-8 text-center py-12">
                  <div class="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
                    <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-red-600" />
                  </div>
                  <h3 class="text-lg font-semibold text-gray-900 mb-2">Token Verification Failed</h3>
                  <p class="text-gray-600 mb-4">{@error_message}</p>
                  <button
                    phx-click="retry_verification"
                    class="inline-flex items-center px-4 py-2 bg-orange-600 text-white text-sm font-medium rounded-lg hover:bg-orange-700 transition-colors"
                  >
                    Try Again
                  </button>
                </div>
              <% else %>
                <%= if @processing_after_step1? do %>
                  <LoadingState.render_loading_state {assigns} />
                <% else %>
                  <%= case @current_step do %>
                    <% 1 -> %><.render_step_1 {assigns} />
                    <% 2 -> %><.render_step_2 {assigns} />
                    <% 3 -> %><.render_step_3 {assigns} />
                  <% end %>
                <% end %>
              <% end %>
            <% end %>
          </div>

          <p class="text-center mt-8 text-sm text-gray-400">
            Copyrights © {Date.utc_today().year} BeamX. All Rights Reserved. Designed &amp; Developed by Vyaasa.com
          </p>
        </div>
      </main>
    </div>
    """
  end

  # Horizontal 3-step progress stepper (Figma): numbered circles joined by
  # connector lines, the active/completed steps in orange. `current_step` is 1..3.
  attr :current_step, :integer, required: true

  defp flow_stepper(assigns) do
    assigns = assign(assigns, :steps, [{1, "Profile Creation"}, {2, "Resume Analysis"}, {3, "Verification"}])

    ~H"""
    <div class="flex items-center justify-center max-w-2xl mx-auto px-2">
      <%= for {{n, label}, idx} <- Enum.with_index(@steps) do %>
        <%= if idx > 0 do %>
          <div class={[
            "flex-1 h-0.5 mx-1 sm:mx-2 transition-colors",
            if(@current_step >= n, do: "bg-orange-500", else: "bg-gray-200")
          ]}>
          </div>
        <% end %>
        <div class="flex flex-col items-center shrink-0">
          <div class={[
            "w-8 h-8 rounded-full flex items-center justify-center text-xs font-semibold transition-colors",
            if(@current_step >= n,
              do: "bg-orange-500 text-white",
              else: "bg-gray-100 text-gray-400 border border-gray-200")
          ]}>
            <%= if @current_step > n do %>
              <.icon name="hero-check" class="w-4 h-4" />
            <% else %>
              {n}
            <% end %>
          </div>
          <span class={[
            "mt-2 text-[10px] sm:text-xs font-semibold uppercase tracking-wide whitespace-nowrap",
            if(@current_step == n, do: "text-orange-600", else: "text-gray-400")
          ]}>
            {label}
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  # Reanalyze content — same step 1/2 renderers, without the outer header card
  # and progress stepper (shown inline by the step renderer itself).
  defp reanalyze_content(assigns) do
    ~H"""
    <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-6 md:p-8">
      <%= if @loading? do %>
        <div class="text-center py-12">
          <div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-orange-600"></div>
          <p class="mt-4 text-gray-600">Loading your profile information...</p>
        </div>
      <% else %>
        <%= if @error_message do %>
          <div class="text-center py-12">
            <div class="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
              <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-red-600" />
            </div>
            <h3 class="text-lg font-semibold text-gray-900 mb-2">Something went wrong</h3>
            <p class="text-gray-600 mb-4">{@error_message}</p>
          </div>
        <% else %>
          <%= if @processing_after_step1? do %>
            <LoadingState.render_loading_state {assigns} />
          <% else %>
            <%= case @current_step do %>
              <% 1 -> %><.render_step_1 {assigns} />
              <% 2 -> %><.render_step_2 {assigns} />
              <% 3 -> %><.render_step_3 {assigns} />
            <% end %>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Helper functions
  defp calculate_completion(step, max_steps) do
    base_percentage = trunc((step - 1) / max_steps * 100)

    case step do
      1 -> 10
      2 -> 60
      3 -> 100
      _ -> base_percentage
    end
  end

  defp has_required_data_for_processing?(socket) do
    require Logger
    resume_entries = socket.assigns.uploads.resume.entries
    id_card_entries = socket.assigns.uploads.id_card.entries
    preferred_role = socket.assigns.preferred_job_role
    reanalyze? = socket.assigns[:reanalyze_mode?] || false

    has_resume = length(resume_entries) > 0
    has_id_card = length(id_card_entries) > 0
    has_job_role = preferred_role != ""
    resume_done = resume_entries |> Enum.any?(fn entry -> entry.done? end)
    id_card_done = id_card_entries |> Enum.any?(fn entry -> entry.done? end)

    Logger.info("REQUIRED_DATA_CHECK - reanalyze_mode=#{reanalyze?} | resume=#{has_resume}/#{resume_done} | id_card=#{has_id_card}/#{id_card_done} | job_role='#{preferred_role}'")

    if reanalyze? do
      # Re-analysis: only a new resume + job role needed (ID already verified)
      has_resume and has_job_role and resume_done
    else
      # First-time verification: all documents required
      has_resume and has_id_card and has_job_role and resume_done and id_card_done
    end
  end

  defp trigger_python_processing(socket) do
    require Logger
    Logger.info("TRIGGER_PYTHON_PROCESSING - Sending process_with_python message")
    # Send resume, ID card and job role to Python service
    send(self(), :process_with_python)
    socket
  end

  @impl true
  def handle_info(:process_with_python, socket) do
    require Logger
    Logger.info("=== CALLING PYTHON SERVICE ===")
    Logger.info("Student ID: #{socket.assigns.student.id}")
    Logger.info("Job role: #{socket.assigns.preferred_job_role}")
    Logger.info("Resume files: #{length(socket.assigns.uploads.resume.entries)}")
    Logger.info("ID card files: #{length(socket.assigns.uploads.id_card.entries)}")

    # Re-analysis uses a dedicated service that creates a NEW ATS phase
    # (incremented attempt_number) instead of overwriting the existing one,
    # so score history is preserved.
    result =
      if socket.assigns[:reanalyze_mode?] do
        ReanalyzeService.process_reanalysis(socket)
      else
        AtsService.process_resume_and_documents(socket)
      end

    case result do
      {:ok, request_id} ->
        Logger.info("ATS processing started, request_id: #{request_id}")
        Process.send_after(self(), :check_ats_processing, 3000)
        Process.send_after(self(), :processing_timeout, 180_000)
        {:noreply, assign(socket, :processing_request_id, request_id)}

      {:error, {:attempt_limit_reached, meta}} ->
        Logger.warning("ATS processing blocked by attempt limit: #{inspect(meta)}")

        {:noreply,
         socket
         |> assign(:processing_after_step1?, false)
         |> put_flash(
           :error,
           "You've used all #{meta.limit} resume attempts allowed for this college. Contact your admin for more."
         )}

      {:error, reason} ->
        Logger.warning("ATS processing failed: #{inspect(reason)}")
        Process.send_after(self(), :ats_processing_done, 1000)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:ats_processing_complete, data}, socket) do
    require Logger
    Logger.info("🎉 Received ATS processing completion broadcast: #{inspect(data)}")

    # Cancel any pending polling or timeout
    # Processing is complete via PubSub, load the data immediately
    send(self(), :ats_processing_done)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:ats_processing_done, socket) do
    # Simulate receiving processed data from Python service
    # Load actual ATS data
    ats_data = AtsDataHelpers.load_ats_data(socket.assigns.student.id, socket.assigns.tenant_alias)
    ats_phase = load_ats_phase(socket)

    socket =
      socket
      |> assign(:processing_after_step1?, false)
      |> assign(:current_step, 2)
      |> assign(:completion_percentage, 60)
      |> assign(:ats_phase, ats_phase)
      |> assign(:ats_data, ats_data || simulate_ats_data(socket))
      |> AtsDataHelpers.populate_form_data_from_ats(ats_data || simulate_ats_data(socket))

    {:noreply, socket}
  end

  @impl true
  def handle_info(:check_ats_processing, socket) do
    require Logger
    Logger.info("Checking ATS processing status...")
    # Check if processing is complete
    if AtsService.processing_complete?(socket.assigns.student.id, socket.assigns.tenant_alias) do
      Logger.info("✅ ATS processing complete!")
      send(self(), :ats_processing_done)
      {:noreply, socket}
    else
      Logger.info("⏳ ATS processing still in progress, checking again in 3 seconds...")
      # Continue polling every 3 seconds
      Process.send_after(self(), :check_ats_processing, 3000)
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:processing_timeout, socket) do
    require Logger
    Logger.warning("⏰ ATS processing timed out after 2 minutes, checking DB for latest status...")

    # Even on timeout, try to load whatever data is available in the DB
    ats_data = AtsDataHelpers.load_ats_data(socket.assigns.student.id, socket.assigns.tenant_alias)
    ats_phase = load_ats_phase(socket)

    socket =
      socket
      |> assign(:processing_after_step1?, false)
      |> assign(:processing_timeout, true)
      |> assign(:current_step, 2)
      |> assign(:completion_percentage, 60)
      |> assign(:ats_phase, ats_phase)
      |> assign(:ats_data, ats_data)
      |> AtsDataHelpers.populate_form_data_from_ats(ats_data)

    {:noreply, socket}
  end

  defp simulate_ats_data(socket) do
    # Fallback simulation if no real ATS data available
    %{
      ats_score: 75,
      preferred_role: socket.assigns.preferred_job_role,
      skills: ["Python", "JavaScript", "React", "PostgreSQL"],
      work_experience: [
        %{
          job_title: "Software Developer",
          company_name: "Tech Corp",
          start_date: "2022-01-01",
          end_date: "2024-01-01",
          responsibilities: "Developed web applications using modern technologies"
        }
      ],
      languages: ["English", "Hindi"],
      external_links: %{
        linkedin: "",
        github: "",
        portfolio: "",
        other: ""
      },
      areas_for_improvement: %{
        "missing_certifications" => "Consider adding relevant certifications",
        "portfolio_links" => "Add portfolio links to showcase your work"
      }
    }
  end

  defp finalize_profile_submission(socket) do
    require Logger
    tenant_alias = socket.assigns.tenant_alias
    student = socket.assigns.student

    case Tenants.get_tenant_by_alias(String.upcase(tenant_alias)) do
      nil ->
        Logger.error("FINALIZE_SUBMISSION - Unknown tenant alias #{tenant_alias}")

      tenant ->
        case Students.finalize_profile_submission(student.id, tenant.schema_name) do
          {:ok, _} ->
            Logger.info("Profile finalized for student #{student.id} — awaiting admin verification")

          {:error, changeset} ->
            Logger.error("Failed to finalize profile submission for student #{student.id}: #{inspect(changeset.errors)}")
        end
    end
  end

  defp load_student_data(socket) do
    profile_token = socket.assigns.profile_token
    tenant_alias = socket.assigns.tenant_alias

    # Make API call to verify token and get student data
    case make_token_verification_request(profile_token, tenant_alias) do
      {:ok, student_data} ->
        # Load ATS data if available
        ats_data = AtsDataHelpers.load_ats_data(student_data.id, tenant_alias)
        ats_phase = load_ats_phase_for_student(student_data.id, tenant_alias)

        # Load job roles from database
        job_roles = load_job_roles(tenant_alias)

        # Persist progress across refresh (Vya-026): if the resume analysis has
        # already run, restore the wizard to the results step instead of
        # resetting to Step 1 with the uploaded files cleared.
        restored_step = if ats_data && ats_data[:ats_score], do: 2, else: 1

        socket
        |> assign(:student, student_data)
        |> assign(:ats_data, ats_data)
        |> assign(:ats_phase, ats_phase)
        |> assign(:current_step, restored_step)
        |> assign(:job_roles, job_roles)
        |> assign(:loading?, false)
        |> assign(:error_message, nil)
        |> AtsDataHelpers.populate_form_data_from_ats(ats_data)

      {:error, error_message} ->
        socket
        |> assign(:student, nil)
        |> assign(:ats_data, nil)
        |> assign(:loading?, false)
        |> assign(:error_message, error_message)
    end
  end

  defp load_ats_phase(socket) do
    load_ats_phase_for_student(socket.assigns.student.id, socket.assigns.tenant_alias)
  end

  defp load_ats_phase_for_student(student_id, tenant_alias) do
    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil -> nil
      tenant -> StudentAts.get_by_student_id(student_id, tenant.schema_name)
    end
  end

  defp save_profile_photo(tmp_path, entry, tenant_id, student_id) do
    filename = "avatar_#{System.system_time(:second)}#{Path.extname(entry.client_name)}"
    # Must resolve via Application.app_dir/2, not a bare relative path — in a
    # compiled release the process cwd isn't the project root, so a literal
    # "priv/static/..." silently writes outside the directory Plug.Static
    # actually serves (`from: :vyaasa_campus` in endpoint.ex), and the photo
    # never shows up again after upload.
    dir = Application.app_dir(:vyaasa_campus, Path.join(["priv", "static", "uploads", tenant_id, "students", student_id]))
    File.mkdir_p!(dir)
    File.cp!(tmp_path, Path.join(dir, filename))
    {:ok, "/uploads/#{tenant_id}/students/#{student_id}/#{filename}"}
  end

  defp load_job_roles(tenant_alias) do
    require Logger
    Logger.info("Loading job roles for tenant: #{tenant_alias}")

    try do
      # Primary: load from public schema industries/job_roles (shared across all tenants)
      grouped_roles = Jobs.list_active_roles_for_picker()

      if grouped_roles != [] do
        Logger.info("Loaded #{Enum.sum(Enum.map(grouped_roles, fn {_, roles} -> length(roles) end))} job roles from public schema")
        grouped_roles
      else
        # Fallback: load from tenant-scoped job_profiles
        case Tenants.get_tenant_by_alias(tenant_alias) do
          nil ->
            []

          tenant ->
            job_profiles = JobProfiles.list_by_tenant(tenant.id, tenant.schema_name)
            roles = Enum.map(job_profiles, & &1.role)

            if roles != [] do
              Logger.info("Loaded #{length(roles)} job roles from tenant job_profiles")
              [{"General", roles}]
            else
              []
            end
        end
      end
    rescue
      error ->
        Logger.error("Error loading job roles: #{inspect(error)}")
        []
    end
  end

  defp make_token_verification_request(profile_token, tenant_alias) do
    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil ->
        {:error, "Invalid tenant. Please check your link."}

      tenant ->
        case Students.verify_profile_token(profile_token, tenant.schema_name) do
          {:ok, student} ->
            {:ok,
             %{
               id: student.id,
               first_name: student.first_name,
               last_name: student.last_name,
               email: student.email,
               registration_id: student.registration_id,
               degree: student.degree,
               specialization: student.specialization,
               year_of_passing: student.year_of_passing,
               cgpa: student.cgpa,
               tenant_id: student.tenant_id
             }}

          {:error, :invalid_token} ->
            {:error, "Invalid or expired token"}

          {:error, :token_expired} ->
            {:error, "Token has expired. Please contact your administrator for a new link."}

          {:error, :profile_already_submitted} ->
            {:error,
             "Your profile has already been submitted and is awaiting verification. This link can no longer be used."}
        end
    end
  end
end
