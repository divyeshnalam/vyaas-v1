defmodule VyaasaCampusWeb.Student.ProfileLive do
  @moduledoc """
  Student's own profile page — reachable from the "Your Profile" link in the
  header dropdown. Shows profile summary + an edit form for the fields that
  live on the `Student` and `StudentAtsPhase` records, plus a lightweight
  confidence trend card, the Credentials section (employability card +
  certificate), and a settings list.

  The Settings rows are placeholders for now (`show_coming_soon`) — the
  underlying features aren't built yet. The employability card's "Email
  Card" button emails a 2-page front/back PDF mirror of the card (see
  `email_employability_card/3` + `Reports.load_employability_card_context/2`),
  matching the app-wide "reports are email-only" convention; the
  certificate's "Email Certificate" button follows the same pattern (see
  `email_certificate/3` + `Reports.load_certificate_context/2`).
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.{AI8, Jam, StudentAts, Students, StudentRankings, Tenants}
  alias VyaasaCampusWeb.Components.Student.Dashboard.Helpers, as: DH

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Student.CredentialsComponent

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Authentication required")
         |> redirect(to: "/auth/tenant/#{tenant_alias}/login")}

      user ->
        tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
        prefix = if tenant, do: tenant.schema_name, else: "public"

        student = Students.get_student(user.id, prefix)
        ats_data = StudentAts.get_by_student_id(user.id, prefix)
        rankings = StudentRankings.get_student_scores_and_ranks(user.id, prefix)
        ai8_profile = AI8.ai8_index(user.id, prefix)
        latest_jam = Jam.get_completed_jam_sessions(user.id, prefix) |> List.first()

        skills = if ats_data, do: ats_data.skills || %{}, else: %{}
        tags = DH.get_skills_list(skills, "technical_skills")

        {:ok,
         socket
         |> assign(:tenant_alias, tenant_alias)
         |> assign(:tenant, tenant)
         |> assign(:tenant_schema, prefix)
         |> assign(:current_scope, :student)
         |> assign(:page_title, "Your Profile")
         |> assign(:user_info, %{
           name: "#{user.first_name} #{user.last_name}",
           role: "Student",
           email: user.email,
           profile_picture_url: ats_data && ats_data.profile_picture_url
         })
         |> assign(:student, student)
         |> assign(:ats_data, ats_data)
         |> assign(:rankings, rankings)
         |> assign(:ai8_score, round(ai8_profile.index))
         |> assign(:latest_jam, latest_jam)
         |> assign(:tags, tags)
         |> assign(:editing?, false)
         |> assign(:active_tab, "none")
         |> assign(:card_flipped, false)
         |> assign(:form, build_form(student, ats_data, tenant))
         |> allow_upload(:avatar,
           accept: ~w(.jpg .jpeg .png .webp),
           max_entries: 1,
           max_file_size: 5_000_000
         )}
    end
  end

  defp build_form(student, ats_data, tenant) do
    to_form(
      %{
        "full_name" => full_name(student),
        "email" => student.email,
        "location" => location(ats_data),
        "degree" => student.degree,
        "year" => student.current_academic_year,
        "college" => tenant && tenant.full_name,
        "batch_year" => student.year_of_passing,
        "bio" => bio(ats_data)
      },
      as: :profile
    )
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Logged out successfully")
     |> redirect(to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}
  end

  def handle_event("show_coming_soon", _params, socket), do: {:noreply, put_flash(socket, :info, "Coming soon!")}

  def handle_event("toggle_edit", _params, socket) do
    socket =
      if socket.assigns.editing? do
        # Closing the edit panel — drop any photo the student picked but never saved.
        Enum.reduce(socket.assigns.uploads.avatar.entries, socket, fn entry, acc ->
          cancel_upload(acc, :avatar, entry.ref)
        end)
      else
        socket
      end

    {:noreply, assign(socket, :editing?, !socket.assigns.editing?)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_tab", %{"tab" => tab}, socket) do
    new_tab = if socket.assigns.active_tab == tab, do: "none", else: tab

    {:noreply,
     socket
     |> assign(:active_tab, new_tab)
     |> assign(:card_flipped, false)}
  end

  def handle_event("rotate_card", _params, socket), do: {:noreply, assign(socket, :card_flipped, !socket.assigns.card_flipped)}

  def handle_event("email_employability_card", _params, socket) do
    %{student: student, tenant_schema: tenant_schema} = socket.assigns
    VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:employability_card, student.id, tenant_schema)
    {:noreply, put_flash(socket, :info, "Your employability card is on its way to your email ✉️")}
  end

  def handle_event("email_certificate", _params, socket) do
    %{student: student, tenant_schema: tenant_schema} = socket.assigns
    VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:certificate, student.id, tenant_schema)
    {:noreply, put_flash(socket, :info, "Your certificate is on its way to your email ✉️")}
  end

  def handle_event("cancel_avatar", %{"ref" => ref}, socket), do: {:noreply, cancel_upload(socket, :avatar, ref)}

  def handle_event("add_tag", %{"value" => tag}, socket) do
    tag = String.trim(tag)

    tags =
      if tag != "" and tag not in socket.assigns.tags do
        socket.assigns.tags ++ [tag]
      else
        socket.assigns.tags
      end

    {:noreply, assign(socket, :tags, tags)}
  end

  def handle_event("remove_tag", %{"tag" => tag}, socket) do
    {:noreply, assign(socket, :tags, List.delete(socket.assigns.tags, tag))}
  end

  def handle_event("save_profile", %{"profile" => params}, socket) do
    %{student: student, ats_data: ats_data, tenant_schema: prefix, tenant: tenant, tags: tags} = socket.assigns

    {first_name, last_name} = split_name(params["full_name"])

    student_attrs = %{
      first_name: first_name,
      last_name: last_name,
      email: student.email,
      degree: String.trim(params["degree"] || ""),
      current_academic_year: String.trim(params["year"] || ""),
      year_of_passing: parse_year(params["batch_year"], student.year_of_passing)
    }

    old_photo_url = ats_data && ats_data.profile_picture_url

    photo_url =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        save_avatar(path, entry, student, old_photo_url)
      end)
      |> List.first()

    with {:ok, updated_student} <- Students.update_student(student.id, student_attrs, prefix) do
      updated_ats = save_ats_fields(student, ats_data, params, tags, photo_url, prefix)

      {:noreply,
       socket
       |> assign(:student, updated_student)
       |> assign(:ats_data, updated_ats)
       |> assign(:user_info, %{
         name: full_name(updated_student),
         role: "Student",
         email: updated_student.email,
         profile_picture_url: updated_ats && updated_ats.profile_picture_url
       })
       |> assign(:form, build_form(updated_student, updated_ats, tenant))
       |> assign(:editing?, false)
       |> put_flash(:info, "Profile updated successfully")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        require Logger
        Logger.error("Profile save failed for student #{student.id}: #{inspect(changeset.errors)}")
        {:noreply, put_flash(socket, :error, "Couldn't save: " <> changeset_error_summary(changeset))}

      {:error, reason} ->
        require Logger
        Logger.error("Profile save failed for student #{student.id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Couldn't save your profile — please try again")}
    end
  end

  defp changeset_error_summary(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
  end

  defp split_name(nil), do: {"", ""}

  defp split_name(full_name) do
    case String.split(String.trim(full_name), " ", trim: true) do
      [] -> {"", ""}
      [first] -> {first, ""}
      [first | rest] -> {first, Enum.join(rest, " ")}
    end
  end

  defp parse_year(nil, fallback), do: fallback

  defp parse_year(str, fallback) do
    case Integer.parse(String.trim(str)) do
      {year, _} -> year
      :error -> fallback
    end
  end

  defp save_ats_fields(student, ats_data, params, tags, photo_url, prefix) do
    with {:ok, ats_phase} <- StudentAts.ensure_profile_phase(student, prefix) do
      skills = Map.put(ats_phase.skills || %{}, "technical_skills", tags)

      personal_information =
        Map.put(ats_phase.personal_information || %{}, "location", String.trim(params["location"] || ""))

      professional_summary =
        Map.put(ats_phase.professional_summary || %{}, "summary", String.trim(params["bio"] || ""))

      attrs =
        %{skills: skills, personal_information: personal_information, professional_summary: professional_summary}
        |> maybe_put_photo(photo_url)

      case StudentAts.update_profile_fields(ats_phase, attrs, prefix) do
        {:ok, updated} -> updated
        {:error, _changeset} -> ats_data
      end
    else
      {:error, _changeset} -> ats_data
    end
  end

  defp maybe_put_photo(attrs, nil), do: attrs
  defp maybe_put_photo(attrs, url), do: Map.put(attrs, :profile_picture_url, url)

  defp save_avatar(tmp_path, entry, student, old_photo_url) do
    filename = "avatar_#{System.system_time(:second)}#{Path.extname(entry.client_name)}"
    # Must resolve via Application.app_dir/2, not a bare relative path — in a
    # compiled release the process cwd isn't the project root, so a literal
    # "priv/static/..." silently writes outside the directory Plug.Static
    # actually serves (`from: :vyaasa_campus` in endpoint.ex), and the photo
    # never shows up again after upload.
    dir = Application.app_dir(:vyaasa_campus, Path.join(["priv", "static", "uploads", student.tenant_id, "students", student.id]))
    File.mkdir_p!(dir)
    File.cp!(tmp_path, Path.join(dir, filename))
    delete_avatar_file(old_photo_url)
    {:ok, "/uploads/#{student.tenant_id}/students/#{student.id}/#{filename}"}
  end

  defp delete_avatar_file("/uploads/" <> _ = url) do
    path = Application.app_dir(:vyaasa_campus, Path.join(["priv", "static"] ++ String.split(url, "/", trim: true)))
    File.rm(path)
  end

  defp delete_avatar_file(_), do: :ok

  defp full_name(student), do: String.trim("#{student.first_name} #{student.last_name}")

  defp verified?(student), do: student.status in ["verified", "active"]

  defp bio(ats_data), do: get_in((ats_data && ats_data.professional_summary) || %{}, ["summary"]) || ""

  defp location(ats_data), do: get_in((ats_data && ats_data.personal_information) || %{}, ["location"]) || ""

  defp joined_on(%{inserted_at: %{} = dt}), do: Calendar.strftime(dt, "%b %Y")
  defp joined_on(_), do: "-"

  defp initials(name), do: VyaasaCampus.Reports.initials(name)

  defp upload_error_message(:too_large), do: "Image is too large (max 5MB)"
  defp upload_error_message(:not_accepted), do: "Please upload a JPG, PNG, or WEBP image"
  defp upload_error_message(:too_many_files), do: "Only one photo at a time"
  defp upload_error_message(_), do: "Couldn't upload that file"

  defp pct_bar_color(nil), do: "bg-gray-200"
  defp pct_bar_color(v) when v >= 80, do: "bg-green-500"
  defp pct_bar_color(v) when v >= 60, do: "bg-brand-500"
  defp pct_bar_color(_), do: "bg-orange-400"

  # Tier/cert id/QR are shared with the emailed PDF (`Reports.load_employability_card_context/2`)
  # so the on-screen card and the emailed one always agree.
  defp tier_info(score), do: VyaasaCampus.Reports.tier_info(score)

  defp cert_id(student_id), do: VyaasaCampus.Reports.cert_id(student_id)

  defp issued_on, do: Calendar.strftime(Date.utc_today(), "%d %B %Y")

  defp valid_until, do: Calendar.strftime(Date.add(Date.utc_today(), 365), "%d %B %Y")

  defp verify_qr_url(student_id, tenant_schema), do: VyaasaCampus.Reports.share_profile_qr_url(student_id, tenant_schema)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-[#FBFAF7] flex">
        <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar
          current_section="profile"
          tenant_alias={@tenant_alias}
          student_name={@user_info.name}
          rankings={@rankings}
        />
        <div class="flex-1 flex flex-col min-w-0">
          <VyaasaCampusWeb.Components.Student.HeaderComponent.header
            user_info={@user_info}
            tenant_alias={@tenant_alias}
            page_title="Your Profile"
          />
          <main class="flex-1 overflow-auto bg-white">
            <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-7xl mx-auto w-full space-y-6">
              <!-- Header card -->
              <div class="relative bg-white rounded-2xl border border-gray-200 shadow-card-soft overflow-hidden">
                <div class="h-32 relative overflow-hidden" style="background-color: rgba(238,109,24,0.12);">
                  <svg
                    class="absolute left-0 w-full"
                    style="top: 0px; height: 120px; filter: blur(13px);"
                    viewBox="0 0 1133 105"
                    preserveAspectRatio="none"
                  >
                    <path
                      d="M0.148775 -42.2898
                        L93.1142 6.93929
                        C140.91 32.249 194.658 44.1676 248.673 41.4336
                        L477.585 29.8471
                        C518.335 27.7845 559.076 34.0559 597.319 48.2778
                        L776.499 114.912
                        C838.107 137.823 905.534 139.866 968.417 120.728
                        L1127.36 72.3545"
                      stroke="#EE6D18"
                      stroke-width="8"
                      opacity="0.5"
                      filter="url(#glow)"
                      fill="none"
                    />
                    <path
                      d="M0.148775 -42.2898
                        L93.1142 6.93929
                        C140.91 32.249 194.658 44.1676 248.673 41.4336
                        L477.585 29.8471
                        C518.335 27.7845 559.076 34.0559 597.319 48.2778
                        L776.499 114.912
                        C838.107 137.823 905.534 139.866 968.417 120.728
                        L1127.36 72.3545"
                      stroke="#EE6D18"
                      stroke-width="6"
                      opacity="0.5"
                      filter="url(#glow)"
                      fill="none"
                    />
                  </svg>
                  <div
                    class="absolute rounded-full"
                    style="width: 216px; height: 216px; top: -108px; left: -20px; border: 3px solid rgba(238,109,24,0.33);"
                  >
                  </div>
                  <div
                    class="absolute rounded-full"
                    style="width: 289px; height: 289px; top: -94px; right: -25px; border: 3px solid rgba(238,109,24,0.33);"
                  >
                  </div>
                </div>
                <button
                  type="button"
                  phx-click="toggle_edit"
                  class="absolute top-4 right-4 inline-flex items-center gap-1.5 text-xs font-medium text-gray-700 bg-white/90 hover:bg-white px-3 py-1.5 rounded-lg border border-gray-200 transition"
                >
                  <.icon name={if @editing?, do: "hero-x-mark", else: "hero-pencil-square"} class="w-4 h-4" />
                  {if @editing?, do: "Close", else: "Edit profile"}
                </button>

                <div class="px-6 pb-6">
                  <div class="relative w-28 h-28 -mt-16">
                    <div class="w-28 h-28 rounded-full ring-4 ring-white bg-linear-to-br from-orange-400 to-orange-600 flex items-center justify-center text-white font-bold text-2xl overflow-hidden">
                      <img :if={@ats_data && @ats_data.profile_picture_url} src={@ats_data.profile_picture_url} class="w-full h-full object-cover" />
                      <span :if={!(@ats_data && @ats_data.profile_picture_url)}>{initials(full_name(@student))}</span>
                    </div>
                    <span class="absolute bottom-1 right-1 w-4 h-4 rounded-full bg-green-500 ring-2 ring-white"></span>
                  </div>

                  <div class="mt-4 flex items-center gap-2 flex-wrap">
                    <h1 class="text-xl font-bold text-gray-900">{full_name(@student)}</h1>
                    <span :if={verified?(@student)} class="text-xs font-semibold px-2.5 py-1 rounded-full bg-green-100 text-green-700">
                      Verified
                    </span>
                  </div>
                  <p class="text-sm text-gray-500 mt-0.5">
                    {@student.degree}<span :if={@student.specialization}>, {@student.specialization}</span>
                  </p>
                  <p :if={bio(@ats_data) != ""} class="text-sm text-gray-600 mt-3">{bio(@ats_data)}</p>

                  <div class="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-sm text-gray-500">
                    <span class="flex items-center gap-1.5"><.icon name="hero-envelope" class="w-4 h-4" />{@student.email}</span>
                    <span :if={location(@ats_data) != ""} class="flex items-center gap-1.5"><.icon name="hero-map-pin" class="w-4 h-4" />{location(@ats_data)}</span>
                    <span :if={@ats_data && @ats_data.preferred_role} class="flex items-center gap-1.5"><.icon name="hero-briefcase" class="w-4 h-4" />{@ats_data.preferred_role}</span>
                    <span :if={@tenant} class="flex items-center gap-1.5"><.icon name="hero-academic-cap" class="w-4 h-4" />{@tenant.full_name}<span :if={@student.year_of_passing}> · Class of {@student.year_of_passing}</span></span>
                    <span class="flex items-center gap-1.5"><.icon name="hero-calendar" class="w-4 h-4" />Joined {joined_on(@student)}</span>
                  </div>

                  <div :if={@tags != []} class="mt-4 flex flex-wrap gap-2">
                    <span :for={tag <- @tags} class="text-xs font-medium px-3 py-1 rounded-full bg-[#F6F5F1] text-[#6B727E]">{tag}</span>
                  </div>
                </div>
              </div>

              <!-- Credentials: employability card + certificate -->
              <.credentials
                active_tab={@active_tab}
                card_flipped={@card_flipped}
                student_name={full_name(@student)}
                role={@student.degree || "Student"}
                initials={initials(full_name(@student))}
                cert_id={cert_id(@student.id)}
                issued_on={issued_on()}
                valid_until={valid_until()}
                score={@ai8_score}
                tier={tier_info(@ai8_score)}
                qr_url={verify_qr_url(@student.id, @tenant_schema)}
              />

              <!-- Edit profile -->
              <div :if={@editing?} class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-6">
                <h2 class="text-base font-bold text-gray-900 mb-4">Edit Profile</h2>

                <.form for={@form} phx-change="validate" phx-submit="save_profile" class="space-y-6">
                  <div>
                    <div class="flex items-center gap-4">
                      <div class="w-14 h-14 rounded-full bg-linear-to-br from-orange-400 to-orange-600 flex items-center justify-center text-white font-bold shrink-0 overflow-hidden">
                        <.live_img_preview :for={entry <- @uploads.avatar.entries} entry={entry} class="w-full h-full object-cover" />
                        <img
                          :if={@uploads.avatar.entries == [] && @ats_data && @ats_data.profile_picture_url}
                          src={@ats_data.profile_picture_url}
                          class="w-full h-full object-cover"
                        />
                        <span :if={@uploads.avatar.entries == [] && !(@ats_data && @ats_data.profile_picture_url)}>
                          {initials(full_name(@student))}
                        </span>
                      </div>
                      <span class="text-sm text-gray-500 truncate flex items-center gap-1.5">
                        {cond do
                          @uploads.avatar.entries != [] -> List.first(@uploads.avatar.entries).client_name
                          @ats_data && @ats_data.profile_picture_url -> Path.basename(@ats_data.profile_picture_url)
                          true -> "No photo uploaded"
                        end}
                        <button
                          :for={entry <- @uploads.avatar.entries}
                          type="button"
                          phx-click="cancel_avatar"
                          phx-value-ref={entry.ref}
                          class="text-gray-400 hover:text-gray-600"
                        >
                          <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                        </button>
                      </span>
                      <label
                        for={@uploads.avatar.ref}
                        class="cursor-pointer text-sm font-semibold px-4 py-2 rounded-lg border border-gray-200 text-gray-700 hover:bg-gray-50 transition"
                      >
                        Replace
                      </label>
                      <.live_file_input upload={@uploads.avatar} class="hidden" />
                    </div>
                    <p :for={err <- upload_errors(@uploads.avatar)} class="text-xs text-red-600 mt-2">
                      {upload_error_message(err)}
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-semibold tracking-wide text-gray-400 mb-3">PERSONAL INFO</p>
                    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                      <.profile_input label="FULL NAME" field={@form[:full_name]} />
                      <.profile_input label="EMAIL ID" field={@form[:email]} type="email" disabled />
                      <.profile_input label="LOCATION" field={@form[:location]} />
                    </div>
                  </div>

                  <div>
                    <p class="text-xs font-semibold tracking-wide text-gray-400 mb-3">ACADEMIC INFO</p>
                    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                      <.profile_input label="DEGREE" field={@form[:degree]} />
                      <.profile_input label="YEAR" field={@form[:year]} />
                      <.profile_input label="COLLEGE" field={@form[:college]} disabled />
                    </div>
                    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mt-4">
                      <.profile_input label="BATCH (YEAR OF PASSING)" field={@form[:batch_year]} />
                    </div>
                  </div>

                  <div>
                    <p class="text-xs font-semibold tracking-wide text-gray-400 mb-3">ABOUT</p>
                    <label class="block">
                      <span class="text-xs text-gray-500">YOUR BIO</span>
                      <textarea
                        name={@form[:bio].name}
                        rows="2"
                        class="mt-1 w-full px-3 py-2 border border-gray-200 rounded-lg text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500"
                      >{@form[:bio].value}</textarea>
                    </label>

                    <%!-- <div class="mt-4">
                      <span class="text-xs text-gray-500">TAGS (PRESS ENTER TO ADD)</span>
                      <div class="mt-2 flex flex-wrap gap-2">
                        <span :for={tag <- @tags} class="inline-flex items-center gap-1.5 text-xs font-medium px-3 py-1 rounded-full bg-[#F3ECE7] text-[#6B727E]">
                          {tag}
                          <button type="button" phx-click="remove_tag" phx-value-tag={tag} class="text-gray-400 hover:text-gray-600">
                            <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                          </button>
                        </span>
                      </div>
                      <input
                        type="text"
                        id={"tag-input-#{Enum.count(@tags)}"}
                        phx-keydown="add_tag"
                        phx-key="Enter"
                        onkeydown="if (event.key === 'Enter') { event.preventDefault(); }"
                        placeholder="Add tags by typing and pressing Enter."
                        class="mt-4 w-full px-3 py-2 border border-gray-200 rounded-lg text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500"
                      />
                    </div> --%>
                  </div>

                  <div class="flex items-center justify-end gap-3 pt-2">
                    <button
                      type="button"
                      phx-click="toggle_edit"
                      class="px-4 py-2.5 rounded-lg text-sm font-semibold text-gray-600 border border-gray-200 hover:bg-gray-50 transition"
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      class="px-4 py-2.5 rounded-lg text-sm font-semibold text-white transition"
                      style="background-color: #FF8B00;"
                    >
                      Save Changes
                    </button>
                  </div>
                </.form>
              </div>

              <div class="grid grid-cols-1 gap-6">
                <!-- Confidence trend -->
                <div class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-6">
                  <h2 class="text-base font-bold text-gray-900 mb-4">Confidence trend</h2>
                  <div class="space-y-4">
                    <.trend_bar label="Overall confidence" value={@ai8_score} />
                    <.trend_bar label="Speaking" value={@rankings.jam.completed && @rankings.jam.score} />
                    <.trend_bar label="Clarity" value={@latest_jam && @latest_jam.clarity_score && @latest_jam.clarity_score * 10} />
                    <.trend_bar label="Structure" value={@latest_jam && @latest_jam.structure_score && @latest_jam.structure_score * 10} />
                  </div>
                </div>

                <%!--
                Achievements (static placeholder — wire up to real unlock data later)
                <div class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-6">
                  <div class="flex items-center justify-between mb-4">
                    <div class="flex items-center gap-2">
                      <h2 class="text-base font-bold text-gray-900">Achievements</h2>
                      <span class="inline-flex items-center text-xs font-semibold px-2.5 py-1 rounded-full bg-orange-50 text-orange-600">
                        🏆 6 of 12 unlocked
                      </span>
                    </div>
                    <button
                      type="button"
                      phx-click="show_coming_soon"
                      class="text-sm font-semibold text-brand-600 hover:text-brand-700"
                    >
                      View all
                    </button>
                  </div>
                  <div class="grid grid-cols-2 gap-3">
                    <.achievement_badge icon="hero-trophy" title="First Mock" description="Completed your first mock" />
                    <.achievement_badge icon="hero-trophy" title="Calm Voice" description="Steady tone in 3 JAMs" />
                    <.achievement_badge icon="hero-trophy" title="Sharp Writer" description="Clear written response" />
                    <.achievement_badge icon="hero-trophy" title="Steady JAM" description="5 JAMs in a week" />
                    <.achievement_badge icon="hero-lock-closed" title="Stretch Goal" description="Score 90+ overall" locked />
                    <.achievement_badge icon="hero-lock-closed" title="Marathon" description="30-day streak" locked />
                  </div>
                </div>
                --%>
              </div>

              <!-- Settings -->
              <%!-- <div class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-6">
                <h2 class="text-base font-bold text-black mb-4">Settings</h2>
                <div class="divide-y divide-gray-100 border border-gray-100 rounded-xl overflow-hidden">
                  <.settings_row icon="hero-clock" label="Recent Activities" />
                  <.settings_row icon="hero-bell" label="Notifications" />
                  <.settings_row icon="hero-lock-closed" label="Privacy & data" />
                  <.settings_row icon="hero-language" label="Language" />
                  <.settings_row icon="headset" label="Help & support" />
                </div>
              </div> --%>

              <!-- Footer -->
              <div class="text-center pt-2">
                <p class="text-sm text-gray-500">
                  Copyright © {Date.utc_today().year} BeamX. All Rights Reserved. Designed & Developed by Vyaasa.com
                </p>
              </div>
            </div>
          </main>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, default: "text"
  attr :disabled, :boolean, default: false

  defp profile_input(assigns) do
    ~H"""
    <label class="block">
      <span class="text-xs text-gray-500">{@label}</span>
      <input
        type={@type}
        name={@field.name}
        id={@field.id}
        value={@field.value}
        disabled={@disabled}
        class="mt-1 w-full px-3 py-2 border border-gray-200 rounded-lg text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:bg-gray-50 disabled:text-gray-400"
      />
    </label>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil

  defp trend_bar(assigns) do
    pct = if assigns.value, do: min(round(assigns.value), 100), else: nil
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div>
      <div class="flex items-center justify-between text-sm mb-1.5">
        <span class="text-gray-600">{@label}</span>
        <span class="font-semibold text-gray-900">{if @pct, do: "#{@pct}%", else: "-"}</span>
      </div>
      <div class="h-2 bg-gray-100 rounded-full overflow-hidden">
        <div class={["h-full rounded-full", pct_bar_color(@pct)]} style={"width: #{@pct || 0}%"}></div>
      </div>
    </div>
    """
  end

  # Unused while the Achievements card above is commented out.
  # attr :icon, :string, required: true
  # attr :title, :string, required: true
  # attr :description, :string, required: true
  # attr :locked, :boolean, default: false
  #
  # defp achievement_badge(assigns) do
  #   ~H"""
  #   <div class={["flex items-start gap-3 p-3 rounded-xl", if(@locked, do: "bg-gray-50", else: "bg-orange-50")]}>
  #     <div class={[
  #       "w-9 h-9 rounded-full flex items-center justify-center shrink-0",
  #       if(@locked, do: "bg-gray-200", else: "bg-orange-500")
  #     ]}>
  #       <.icon name={@icon} class={"w-4.5 h-4.5 " <> if(@locked, do: "text-gray-400", else: "text-white")} />
  #     </div>
  #     <div class="min-w-0">
  #       <p class={["text-sm font-semibold truncate", if(@locked, do: "text-gray-400", else: "text-gray-900")]}>{@title}</p>
  #       <p class="text-xs text-gray-500 truncate">{@description}</p>
  #     </div>
  #   </div>
  #   """
  # end

  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp settings_row(assigns) do
    ~H"""
    <button type="button" phx-click="show_coming_soon" class="w-full flex items-center justify-between px-4 py-3.5 text-sm text-gray-700 bg-[#FAFAF7] transition">
      <span class="flex items-center gap-3">
        <.headset_icon :if={@icon == "headset"} class="w-5 h-5 text-black" />
        <.icon :if={@icon != "headset"} name={@icon} class="w-5 h-5 text-black" />
        {@label}
      </span>
      <.icon name="hero-chevron-right" class="w-4 h-4 text-black" />
    </button>
    """
  end

  attr :class, :string, default: "w-5 h-5"

  defp headset_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={@class} aria-hidden="true">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M4 13v-1a8 8 0 1 1 16 0v1M4 13v4a2 2 0 0 0 2 2h1v-7H5a1 1 0 0 0-1 1Zm16 0v4a2 2 0 0 1-2 2h-1v-7h2a1 1 0 0 1 1 1Zm-5 6h-2a2 2 0 0 1-2-2"
      />
    </svg>
    """
  end
end
