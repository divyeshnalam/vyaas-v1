defmodule VyaasaCampusWeb.Admin.JobsLive do
  @moduledoc """
  Super admin LiveView for managing industries and job roles.
  These are global (public schema) and shared across all tenants.
  Students select from these job roles during resume upload.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Jobs

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Admin.SuperAdminShell

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    user_info =
      case current_user do
        nil ->
          %{name: "Super Admin", role: "Platform Admin"}

        u ->
          name = String.trim("#{u.first_name} #{u.last_name}")
          name = if name == "", do: "Super Admin", else: name
          %{name: name, email: u.email, role: "Platform Admin"}
      end

    {:ok,
     socket
     |> assign(:user_info, user_info)
     |> assign(:page_title, "Industries & Job Roles")
     |> assign(:industries, Jobs.industry_stats())
     |> assign(:selected_industry, nil)
     |> assign(:job_roles, [])
     |> assign(:all_roles, Jobs.list_all_roles_with_industry())
     |> assign(:role_counts, Jobs.role_subject_counts())
     |> assign(:role_search, "")
     |> assign(:show_industry_form, false)
     |> assign(:show_role_form, false)
     |> assign(:industry_form, to_form(%{}, as: :industry))
     |> assign(:role_form, to_form(%{}, as: :role))
     |> assign(:editing_industry, nil)
     |> assign(:editing_role, nil)
     |> assign(:subjects_role, nil)
     |> assign(:blueprint, [])
     |> assign(:total_questions, 20)
     |> assign(:qb_degrees, [])
     |> assign(:qb_branches, [])
     |> assign(:qb_curricula, [])
     |> assign(:qb_subjects, [])
     |> assign(:sel_degree, nil)
     |> assign(:sel_branch, nil)
     |> assign(:sel_curriculum, nil)
     |> assign(:sel_subject, nil)
     |> assign(:deg_text, "")
     |> assign(:br_text, "")
     |> assign(:cur_text, "")
     |> assign(:sub_text, "")
     |> assign(:open_combo, nil)}
  end

  # ============================================================================
  # INDUSTRY EVENTS
  # ============================================================================

  @impl true
  def handle_event("show_industry_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_industry_form, true)
     |> assign(:editing_industry, nil)
     |> assign(:industry_form, to_form(%{}, as: :industry))}
  end

  def handle_event("close_industry_form", _params, socket) do
    {:noreply, assign(socket, :show_industry_form, false)}
  end

  def handle_event("save_industry", %{"industry" => params}, socket) do
    case socket.assigns.editing_industry do
      nil ->
        case Jobs.create_industry(params) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:industries, Jobs.industry_stats())
             |> reload_data()
             |> assign(:show_industry_form, false)
             |> put_flash(:info, "Industry created!")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, format_errors(changeset))}
        end

      industry ->
        case Jobs.update_industry(industry, params) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:industries, Jobs.industry_stats())
             |> reload_data()
             |> assign(:show_industry_form, false)
             |> assign(:editing_industry, nil)
             |> put_flash(:info, "Industry updated!")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, format_errors(changeset))}
        end
    end
  end

  def handle_event("edit_industry", %{"id" => id}, socket) do
    industry = Jobs.get_industry!(id)

    {:noreply,
     socket
     |> assign(:show_industry_form, true)
     |> assign(:editing_industry, industry)
     |> assign(:industry_form, to_form(%{"name" => industry.name, "code" => industry.code, "description" => industry.description || ""}, as: :industry))}
  end

  def handle_event("delete_industry", %{"id" => id}, socket) do
    industry = Jobs.get_industry!(id)

    case Jobs.delete_industry(industry) do
      {:ok, _} ->
        selected =
          if socket.assigns.selected_industry && socket.assigns.selected_industry.id == industry.id,
            do: nil,
            else: socket.assigns.selected_industry

        {:noreply,
         socket
         |> assign(:industries, Jobs.industry_stats())
         |> reload_data()
         |> assign(:selected_industry, selected)
         |> assign(:job_roles, if(is_nil(selected), do: [], else: socket.assigns.job_roles))
         |> put_flash(:info, "Industry deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete industry.")}
    end
  end

  def handle_event("toggle_industry", %{"id" => id}, socket) do
    industry = Jobs.get_industry!(id)

    case Jobs.update_industry(industry, %{is_active: !industry.is_active}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:industries, Jobs.industry_stats())
         |> reload_data()
         |> put_flash(:info, "Industry #{if industry.is_active, do: "deactivated", else: "activated"}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update.")}
    end
  end

  # ============================================================================
  # JOB ROLE EVENTS
  # ============================================================================

  def handle_event("select_industry", %{"id" => id}, socket) do
    {id_int, _} = Integer.parse(id)
    industry = Jobs.get_industry!(id_int)
    roles = Jobs.list_job_roles_by_industry(id_int)

    {:noreply,
     socket
     |> assign(:selected_industry, industry)
     |> assign(:job_roles, roles)
     |> assign(:show_role_form, false)}
  end

  # Card view: filter role cards by industry (nil = all) and by search text.
  def handle_event("filter_industry", %{"id" => ""}, socket) do
    {:noreply, socket |> assign(:selected_industry, nil) |> assign(:show_role_form, false)}
  end

  def handle_event("filter_industry", %{"id" => id}, socket) do
    industry = Jobs.get_industry!(String.to_integer(id))
    {:noreply, socket |> assign(:selected_industry, industry) |> assign(:show_role_form, false)}
  end

  def handle_event("search_roles", %{"value" => term}, socket) do
    {:noreply, assign(socket, :role_search, term)}
  end

  def handle_event("show_role_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_role_form, true)
     |> assign(:editing_role, nil)
     |> assign(:role_form, to_form(%{}, as: :role))}
  end

  def handle_event("close_role_form", _params, socket) do
    {:noreply, assign(socket, :show_role_form, false)}
  end

  # ── Role → subject blueprint (MCQ), via Degree→Branch→Curriculum→Subject ───
  def handle_event("manage_subjects", %{"id" => id}, socket) do
    role = Jobs.get_job_role!(String.to_integer(id))

    existing =
      role.id
      |> Jobs.get_role_subjects()
      |> Enum.map(fn jrs ->
        %{subject_id: jrs.subject_id, subject_name: jrs.subject.name, question_count: jrs.question_count}
      end)

    total =
      case Enum.sum(Enum.map(existing, & &1.question_count)) do
        n when n > 0 -> n
        _ -> 20
      end

    blueprint =
      existing
      |> Enum.map(fn item -> Map.put(item, :percentage, round(item.question_count * 100 / total)) end)
      |> Enum.sort_by(& &1.subject_name)
      |> allocate_counts(total)

    {:noreply,
     socket
     |> assign(:subjects_role, role)
     |> assign(:blueprint, blueprint)
     |> assign(:total_questions, total)
     |> assign(:qb_degrees, Jobs.qb_degrees())
     |> reset_cascade()}
  end

  def handle_event("close_subjects", _params, socket) do
    {:noreply, assign(socket, :subjects_role, nil)}
  end

  # Typeahead: typing filters the suggestion list (open_combo tracks which
  # dropdown is showing); clicking a suggestion resolves it, loads the next
  # level, and clears the levels below.
  def handle_event("type_degree", %{"v" => t}, s),
    do: {:noreply, s |> assign(:deg_text, t) |> assign(:open_combo, :degree)}

  def handle_event("type_branch", %{"v" => t}, s),
    do: {:noreply, s |> assign(:br_text, t) |> assign(:open_combo, :branch)}

  def handle_event("type_curriculum", %{"v" => t}, s),
    do: {:noreply, s |> assign(:cur_text, t) |> assign(:open_combo, :curriculum)}

  def handle_event("type_subject", %{"v" => t}, s),
    do: {:noreply, s |> assign(:sub_text, t) |> assign(:open_combo, :subject)}

  def handle_event("open_combo", %{"field" => f}, s),
    do: {:noreply, assign(s, :open_combo, safe_field(f))}

  def handle_event("close_combo", _p, s), do: {:noreply, assign(s, :open_combo, nil)}

  def handle_event("select_degree", %{"id" => id, "name" => name}, s) do
    id = String.to_integer(id)

    {:noreply,
     s
     |> assign(:deg_text, name)
     |> assign(:sel_degree, %{id: id, name: name})
     |> assign(:qb_branches, Jobs.qb_branches(id))
     |> assign(:br_text, "")
     |> assign(:sel_branch, nil)
     |> assign(:qb_curricula, [])
     |> assign(:cur_text, "")
     |> assign(:sel_curriculum, nil)
     |> assign(:qb_subjects, [])
     |> assign(:sub_text, "")
     |> assign(:sel_subject, nil)
     |> assign(:open_combo, nil)}
  end

  def handle_event("select_branch", %{"id" => id, "name" => name}, s) do
    id = String.to_integer(id)

    {:noreply,
     s
     |> assign(:br_text, name)
     |> assign(:sel_branch, %{id: id, name: name})
     |> assign(:qb_curricula, Jobs.qb_curricula(id))
     |> assign(:cur_text, "")
     |> assign(:sel_curriculum, nil)
     |> assign(:qb_subjects, [])
     |> assign(:sub_text, "")
     |> assign(:sel_subject, nil)
     |> assign(:open_combo, nil)}
  end

  def handle_event("select_curriculum", %{"id" => id, "name" => name}, s) do
    id = String.to_integer(id)

    {:noreply,
     s
     |> assign(:cur_text, name)
     |> assign(:sel_curriculum, %{id: id, name: name})
     |> assign(:qb_subjects, Jobs.qb_subjects(id))
     |> assign(:sub_text, "")
     |> assign(:sel_subject, nil)
     |> assign(:open_combo, nil)}
  end

  def handle_event("select_subject", %{"id" => id, "name" => name}, s) do
    {:noreply,
     s
     |> assign(:sub_text, name)
     |> assign(:sel_subject, %{id: String.to_integer(id), name: name})
     |> assign(:open_combo, nil)}
  end

  def handle_event("add_subject", _params, socket) do
    case socket.assigns.sel_subject do
      %{id: sid, name: sname} ->
        others = Enum.reject(socket.assigns.blueprint, &(&1.subject_id == sid))
        n = length(others) + 1
        even_pct = div(100, n)

        blueprint =
          (Enum.map(others, &Map.put(&1, :percentage, even_pct)) ++
             [%{subject_id: sid, subject_name: sname, percentage: even_pct}])
          |> Enum.sort_by(& &1.subject_name)
          |> allocate_counts(socket.assigns.total_questions)

        {:noreply,
         socket
         |> assign(:blueprint, blueprint)
         |> assign(:sub_text, "")
         |> assign(:sel_subject, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_subject", %{"id" => id}, socket) do
    sid = String.to_integer(id)

    blueprint =
      socket.assigns.blueprint
      |> Enum.reject(&(&1.subject_id == sid))
      |> allocate_counts(socket.assigns.total_questions)

    {:noreply, assign(socket, :blueprint, blueprint)}
  end

  def handle_event("update_percentage", %{"_id" => id, "value" => raw}, socket) do
    sid = String.to_integer(id)
    pct = raw |> parse_count() |> min(100)

    blueprint =
      socket.assigns.blueprint
      |> Enum.map(fn item -> if item.subject_id == sid, do: Map.put(item, :percentage, pct), else: item end)
      |> allocate_counts(socket.assigns.total_questions)

    {:noreply, assign(socket, :blueprint, blueprint)}
  end

  def handle_event("update_total", %{"value" => raw}, socket) do
    total = raw |> parse_count() |> max(1)

    {:noreply,
     socket
     |> assign(:total_questions, total)
     |> assign(:blueprint, allocate_counts(socket.assigns.blueprint, total))}
  end

  def handle_event("save_subjects", _params, socket) do
    role = socket.assigns.subjects_role
    entries = Enum.map(socket.assigns.blueprint, &Map.take(&1, [:subject_id, :question_count]))
    Jobs.set_role_subjects(role.id, entries)

    {:noreply,
     socket
     |> assign(:subjects_role, nil)
     |> reload_data()
     |> put_flash(:info, "Saved #{length(entries)} subject(s) for #{role.title}.")}
  end

  def handle_event("save_role", %{"role" => params}, socket) do
    industry = socket.assigns.selected_industry
    params = Map.put(params, "industry_id", industry.id)

    # Parse skills from comma-separated string
    params =
      case params["skills_text"] do
        nil -> params
        "" -> Map.put(params, "skills", [])
        text ->
          skills = text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
          Map.put(params, "skills", skills)
      end

    case socket.assigns.editing_role do
      nil ->
        case Jobs.create_job_role(params) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:job_roles, Jobs.list_job_roles_by_industry(industry.id))
             |> reload_data()
             |> assign(:industries, Jobs.industry_stats())
             |> reload_data()
             |> assign(:show_role_form, false)
             |> put_flash(:info, "Job role created!")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, format_errors(changeset))}
        end

      role ->
        case Jobs.update_job_role(role, params) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:job_roles, Jobs.list_job_roles_by_industry(industry.id))
             |> reload_data()
             |> assign(:industries, Jobs.industry_stats())
             |> reload_data()
             |> assign(:show_role_form, false)
             |> assign(:editing_role, nil)
             |> put_flash(:info, "Job role updated!")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, format_errors(changeset))}
        end
    end
  end

  def handle_event("edit_role", %{"id" => id}, socket) do
    {id_int, _} = Integer.parse(id)
    role = Jobs.get_job_role!(id_int)

    {:noreply,
     socket
     |> assign(:show_role_form, true)
     |> assign(:selected_industry, role.industry)
     |> assign(:editing_role, role)
     |> assign(:role_form, to_form(%{
       "title" => role.title,
       "code" => role.code,
       "description" => role.description || "",
       "job_description" => role.job_description || "",
       "skills_text" => Enum.join(role.skills || [], ", "),
       "experience_level" => role.experience_level || "entry"
     }, as: :role))}
  end

  def handle_event("delete_role", %{"id" => id}, socket) do
    {id_int, _} = Integer.parse(id)
    role = Jobs.get_job_role!(id_int)
    industry = socket.assigns.selected_industry

    case Jobs.delete_job_role(role) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:job_roles, Jobs.list_job_roles_by_industry(industry.id))
         |> reload_data()
         |> assign(:industries, Jobs.industry_stats())
         |> reload_data()
         |> put_flash(:info, "Job role deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete.")}
    end
  end

  def handle_event("toggle_role", %{"id" => id}, socket) do
    {id_int, _} = Integer.parse(id)
    role = Jobs.get_job_role!(id_int)
    industry = socket.assigns.selected_industry

    case Jobs.update_job_role(role, %{is_active: !role.is_active}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:job_roles, Jobs.list_job_roles_by_industry(industry.id))
         |> put_flash(:info, "Role #{if role.is_active, do: "deactivated", else: "activated"}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update.")}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  # ============================================================================
  # RENDER
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={:super_admin}>
      <!-- MCQ subjects blueprint for a role -->
      <div :if={@subjects_role} class="fixed inset-0 z-50 flex items-center justify-center p-4" phx-window-keydown="close_subjects" phx-key="Escape">
        <div class="absolute inset-0 bg-gray-900/60" phx-click="close_subjects"></div>
        <div class="relative bg-white rounded-2xl shadow-2xl w-full max-w-2xl max-h-[85vh] flex flex-col overflow-hidden">
          <div class="flex items-start justify-between px-6 py-4 border-b border-gray-100">
            <div class="flex items-start gap-3">
              <span class="shrink-0 h-9 w-9 rounded-xl bg-orange-50 text-orange-500 flex items-center justify-center">
                <.icon name="hero-rectangle-stack-solid" class="h-4 w-4" />
              </span>
              <div>
                <h3 class="text-base font-bold text-gray-900">MCQ subjects — {@subjects_role.title}</h3>
                <p class="text-[11px] text-gray-400 mt-0.5">Set each subject's share of the test as a percentage — one subject gets 100%, two split 50/50 by default. Total questions drives the Objective test for students who pick this role.</p>
              </div>
            </div>
            <button type="button" phx-click="close_subjects" class="text-gray-400 hover:text-gray-600" aria-label="Close">
              <.icon name="hero-x-mark" class="w-6 h-6" />
            </button>
          </div>
          <div class="flex-1 flex flex-col min-h-0">
            <!-- Cascading, searchable picker: Degree → Branch → Curriculum → Subject -->
            <div class="px-6 py-4 border-b border-gray-100 bg-gray-50/50 space-y-3">
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3" phx-click-away="close_combo">
                <.qb_combo id="deg" field="degree" label="Degree" type_event="type_degree" select_event="select_degree" options={@qb_degrees} value={@deg_text} resolved={@sel_degree != nil} open={@open_combo == :degree} placeholder="Type to search degree…" />
                <.qb_combo id="br" field="branch" label="Branch" type_event="type_branch" select_event="select_branch" options={@qb_branches} value={@br_text} resolved={@sel_branch != nil} open={@open_combo == :branch} placeholder={if @sel_degree, do: "Type to search branch…", else: "Pick a degree first"} disabled={@sel_degree == nil} />
                <.qb_combo id="cur" field="curriculum" label="Curriculum" type_event="type_curriculum" select_event="select_curriculum" options={@qb_curricula} value={@cur_text} resolved={@sel_curriculum != nil} open={@open_combo == :curriculum} placeholder={if @sel_branch, do: "Type to search curriculum…", else: "Pick a branch first"} disabled={@sel_branch == nil} />
                <.qb_combo id="sub" field="subject" label="Subject" type_event="type_subject" select_event="select_subject" options={@qb_subjects} value={@sub_text} resolved={@sel_subject != nil} open={@open_combo == :subject} placeholder={if @sel_curriculum, do: "Type to search subject…", else: "Pick a curriculum first"} disabled={@sel_curriculum == nil} />
              </div>
              <div class="flex items-end justify-between gap-2">
                <button type="button" phx-click="add_subject" disabled={@sel_subject == nil} class="inline-flex items-center gap-1 px-4 py-1.5 text-sm font-semibold text-white bg-orange-500 hover:bg-orange-600 rounded-lg disabled:opacity-40 disabled:cursor-not-allowed">
                  <.icon name="hero-plus" class="h-4 w-4" /> Add {if @sel_subject, do: "\"#{@sel_subject.name}\"", else: "subject"}
                </button>
                <form phx-change="update_total">
                  <label class="block text-[11px] font-semibold text-gray-500 mb-1">Total questions</label>
                  <input type="number" name="value" min="1" value={@total_questions} class="w-24 px-2 py-1.5 text-sm text-center border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-400" />
                </form>
              </div>
            </div>

            <!-- Current blueprint -->
            <div class="flex-1 overflow-y-auto px-6 py-3">
              <% total_pct = @blueprint |> Enum.map(& &1.percentage) |> Enum.sum() %>
              <p class="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-2">
                Blueprint · {total_pct}%
                <span :if={@blueprint != [] and total_pct != 100} class="text-red-400 normal-case font-medium">(should total 100%)</span>
                · {@total_questions} questions total
              </p>
              <div :if={@blueprint == []} class="py-8 text-center text-sm text-gray-400">
                No subjects added yet. Use the pickers above to add subjects for this role.
              </div>
              <div :for={item <- @blueprint} class="flex items-center justify-between py-2.5 border-b border-gray-50 gap-4">
                <p class="text-sm font-medium text-gray-800 truncate">{item.subject_name}</p>
                <div class="flex items-center gap-3 shrink-0">
                  <span class="text-xs text-gray-400">{item.question_count} Qs</span>
                  <form phx-change="update_percentage" class="flex items-center gap-1">
                    <input type="hidden" name="_id" value={item.subject_id} />
                    <input type="number" name="value" min="0" max="100" value={item.percentage} class="w-16 px-2 py-1 text-sm text-center border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-400" />
                    <span class="text-sm font-semibold text-orange-600">%</span>
                  </form>
                  <button type="button" phx-click="remove_subject" phx-value-id={item.subject_id} class="text-gray-300 hover:text-red-500" aria-label="Remove">
                    <.icon name="hero-x-mark" class="w-4 h-4" />
                  </button>
                </div>
              </div>
            </div>

            <div class="flex items-center justify-end gap-2 px-6 py-3 border-t border-gray-100">
              <button type="button" phx-click="close_subjects" class="px-4 py-2 text-sm text-gray-600 rounded-lg hover:bg-gray-100">Cancel</button>
              <button type="button" phx-click="save_subjects" class="px-4 py-2 text-sm font-semibold text-white bg-orange-500 hover:bg-orange-600 rounded-lg">Save blueprint</button>
            </div>
          </div>
        </div>
      </div>

      <.admin_layout user_info={@user_info} current_section="jobs">
        <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-[1400px] mx-auto w-full space-y-6">
          <!-- Header -->
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p class="text-[11px] font-bold uppercase tracking-[0.14em] text-orange-500 mb-1">Platform Config</p>
              <h1 class="text-2xl font-bold text-gray-900">Industries & Job Roles</h1>
              <p class="text-sm text-gray-500 mt-0.5">Manage job roles and their MCQ subject blueprints.</p>
            </div>
            <div class="flex items-center gap-2">
              <button phx-click="show_industry_form" class="inline-flex items-center gap-1 px-3 py-2 rounded-lg border border-gray-200 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50">
                <.icon name="hero-plus" class="h-4 w-4" /> Industry
              </button>
              <button phx-click="show_role_form" disabled={@selected_industry == nil} title={if @selected_industry, do: "", else: "Pick an industry filter first"} class="inline-flex items-center gap-1 px-3 py-2 rounded-lg bg-orange-500 hover:bg-orange-600 text-white text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed">
                <.icon name="hero-plus" class="h-4 w-4" /> Role
              </button>
            </div>
          </div>

          <!-- Industry form -->
          <%= if @show_industry_form do %>
            <div class="bg-white rounded-2xl border border-orange-100 p-5">
              <.form for={@industry_form} phx-submit="save_industry" class="space-y-3">
                <div class="flex flex-wrap items-end gap-3">
                  <div class="flex-1 min-w-[200px]">
                    <.input field={@industry_form[:name]} type="text" label="Industry Name" placeholder="e.g. Information Technology" required />
                  </div>
                  <div class="w-28"><.input field={@industry_form[:code]} type="text" label="Code" placeholder="IT" /></div>
                  <div class="flex-1 min-w-[200px]"><.input field={@industry_form[:description]} type="text" label="Description (optional)" /></div>
                </div>
                <div class="flex gap-2">
                  <button type="submit" class="px-4 py-2 bg-orange-500 text-white text-sm rounded-lg hover:bg-orange-600">{if @editing_industry, do: "Update", else: "Add"}</button>
                  <button type="button" phx-click="close_industry_form" class="px-4 py-2 bg-gray-100 text-gray-700 text-sm rounded-lg hover:bg-gray-200">Cancel</button>
                </div>
              </.form>
            </div>
          <% end %>

          <!-- Role form -->
          <%= if @show_role_form && @selected_industry do %>
            <div class="bg-white rounded-2xl border border-orange-100 p-5">
              <p class="text-xs font-semibold text-gray-500 mb-3">New role in <span class="text-gray-800">{@selected_industry.name}</span></p>
              <.form for={@role_form} phx-submit="save_role" class="space-y-3">
                <div class="flex flex-wrap items-end gap-3">
                  <div class="flex-1 min-w-[200px]"><.input field={@role_form[:title]} type="text" label="Job Title" placeholder="e.g. Software Engineer" required /></div>
                  <div class="w-28"><.input field={@role_form[:code]} type="text" label="Code" placeholder="SWE" /></div>
                  <div class="w-48"><.input field={@role_form[:experience_level]} type="select" label="Experience" options={[{"Entry Level", "entry"}, {"Mid Level", "mid"}, {"Senior", "senior"}, {"Lead", "lead"}]} /></div>
                </div>
                <.input field={@role_form[:description]} type="text" label="Description (optional)" />
                <.input field={@role_form[:skills_text]} type="text" label="Skills (comma-separated)" placeholder="Python, React, SQL" />
                <.input
                  field={@role_form[:job_description]}
                  type="textarea"
                  rows="8"
                  label="Job Description (used as the résumé-scoring rubric)"
                  placeholder="Paste the full JD. When set, résumés for this role are scored against this JD's requirements — consistently across all colleges."
                />
                <p class="text-[11px] text-gray-400 -mt-2">Decomposed into scored requirements once and reused, so the same résumé always gets the same score.</p>
                <div class="flex gap-2">
                  <button type="submit" class="px-4 py-2 bg-orange-500 text-white text-sm rounded-lg hover:bg-orange-600">{if @editing_role, do: "Update", else: "Add"}</button>
                  <button type="button" phx-click="close_role_form" class="px-4 py-2 bg-gray-100 text-gray-700 text-sm rounded-lg hover:bg-gray-200">Cancel</button>
                </div>
              </.form>
            </div>
          <% end %>

          <!-- Search -->
          <form phx-change="search_roles" class="relative max-w-md">
            <.icon name="hero-magnifying-glass" class="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2" />
            <input name="value" value={@role_search} phx-debounce="150" autocomplete="off" placeholder="Search roles…"
              class="w-full pl-9 pr-3 py-2 text-sm border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-orange-400" />
          </form>

          <!-- Industry filter chips -->
          <div class="flex flex-wrap gap-2">
            <button phx-click="filter_industry" phx-value-id="" class={["px-3 py-1.5 rounded-full text-xs font-semibold border transition", if(@selected_industry == nil, do: "bg-orange-500 text-white border-orange-500", else: "bg-white text-gray-600 border-gray-200 hover:border-orange-300")]}>
              All <span class="opacity-70">· {length(@all_roles)}</span>
            </button>
            <button :for={ind <- @industries} phx-click="filter_industry" phx-value-id={ind.id}
              class={["px-3 py-1.5 rounded-full text-xs font-semibold border transition inline-flex items-center gap-1.5", if(@selected_industry && @selected_industry.id == ind.id, do: "bg-orange-500 text-white border-orange-500", else: "bg-white text-gray-600 border-gray-200 hover:border-orange-300")]}>
              {ind.name} <span class="opacity-70">· {ind.role_count}</span>
              <span :if={!ind.is_active} class="text-[9px] uppercase opacity-70">off</span>
            </button>
          </div>

          <!-- Selected-industry manage bar -->
          <div :if={@selected_industry} class="flex items-center gap-3 text-xs text-gray-500">
            <span>Managing <span class="font-semibold text-gray-700">{@selected_industry.name}</span>:</span>
            <button phx-click="edit_industry" phx-value-id={@selected_industry.id} class="text-orange-600 hover:underline">Edit</button>
            <button phx-click="toggle_industry" phx-value-id={@selected_industry.id} class="text-gray-600 hover:underline">{if @selected_industry.is_active, do: "Deactivate", else: "Activate"}</button>
            <button phx-click="delete_industry" phx-value-id={@selected_industry.id} data-confirm="Delete this industry and all its job roles?" class="text-red-600 hover:underline">Delete</button>
          </div>

          <!-- Role cards -->
          <% roles = visible_roles(assigns) %>
          <div :if={roles == []} class="bg-white rounded-2xl border border-gray-100 p-12 text-center">
            <.icon name="hero-briefcase" class="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <p class="text-sm text-gray-500">No job roles match. {if @selected_industry, do: "Add one with + Role.", else: "Adjust the filter or search."}</p>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div :for={role <- roles} class={["group bg-white rounded-2xl border shadow-sm hover:shadow-md hover:border-orange-200 transition p-5 flex flex-col", if(role.is_active, do: "border-gray-100", else: "border-gray-100 opacity-70")]}>
              <div class="flex items-start justify-between gap-3">
                <div class="flex items-start gap-3 min-w-0">
                  <span class="shrink-0 h-9 w-9 rounded-xl bg-orange-50 text-orange-500 flex items-center justify-center">
                    <.icon name="hero-briefcase-solid" class="h-4 w-4" />
                  </span>
                  <div class="min-w-0">
                    <div class="flex items-center gap-1.5">
                      <p class="text-sm font-bold text-gray-900 truncate">{role.title}</p>
                      <span :if={!role.is_active} class="text-[9px] px-1.5 py-0.5 bg-gray-200 text-gray-500 rounded uppercase tracking-wide">off</span>
                    </div>
                    <p class="text-[11px] text-gray-400 truncate flex items-center gap-1">
                      <.icon name="hero-building-office-2" class="h-3 w-3" /> {role.industry && role.industry.name}
                    </p>
                  </div>
                </div>
                <div class="flex items-center gap-1 shrink-0">
                  <span
                    :if={role.job_description && String.trim(role.job_description) != ""}
                    class="text-[10px] font-medium px-2 py-0.5 rounded-full bg-green-50 text-green-700 inline-flex items-center gap-1"
                    title="Résumé-scoring JD authored"
                  >
                    <.icon name="hero-document-check" class="w-3 h-3" /> JD
                  </span>
                  <span class={"text-[10px] font-medium px-2 py-0.5 rounded-full " <> experience_level_class(role.experience_level)}>
                    {String.capitalize(role.experience_level || "entry")}
                  </span>
                </div>
              </div>

              <p :if={role.description && role.description != ""} class="text-xs text-gray-500 mt-3 line-clamp-2">{role.description}</p>

              <div :if={role.skills != []} class="flex flex-wrap gap-1 mt-3">
                <span :for={skill <- Enum.take(role.skills || [], 4)} class="text-[10px] px-2 py-0.5 bg-orange-50 text-orange-600 rounded-full">{skill}</span>
                <span :if={length(role.skills || []) > 4} class="text-[10px] px-2 py-0.5 bg-gray-100 text-gray-500 rounded-full">+{length(role.skills) - 4}</span>
              </div>

              <div class="flex items-center justify-between mt-4 pt-3 border-t border-gray-100">
                <span class={["text-[11px] font-semibold inline-flex items-center gap-1", if(Map.get(@role_counts, role.id, 0) > 0, do: "text-orange-600", else: "text-gray-400")]}>
                  <.icon name="hero-rectangle-stack" class="w-3.5 h-3.5" /> {Map.get(@role_counts, role.id, 0)} subjects
                </span>
                <div class="flex items-center gap-0.5">
                  <button phx-click="manage_subjects" phx-value-id={role.id} class="p-1.5 rounded-lg text-gray-400 hover:text-orange-600 hover:bg-orange-50" title="MCQ subjects">
                    <.icon name="hero-adjustments-horizontal" class="h-4 w-4" />
                  </button>
                  <button phx-click="edit_role" phx-value-id={role.id} class="p-1.5 rounded-lg text-gray-400 hover:text-orange-600 hover:bg-orange-50" title="Edit">
                    <.icon name="hero-pencil-square" class="h-4 w-4" />
                  </button>
                  <button phx-click="toggle_role" phx-value-id={role.id} class={"p-1.5 rounded-lg hover:bg-gray-100 " <> if(role.is_active, do: "text-green-500", else: "text-gray-400")} title={if role.is_active, do: "Deactivate", else: "Activate"}>
                    <.icon name={if role.is_active, do: "hero-eye", else: "hero-eye-slash"} class="h-4 w-4" />
                  </button>
                  <button phx-click="delete_role" phx-value-id={role.id} data-confirm={"Delete \"#{role.title}\"?"} class="p-1.5 rounded-lg text-gray-400 hover:text-red-600 hover:bg-red-50" title="Delete">
                    <.icon name="hero-trash" class="h-4 w-4" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </.admin_layout>
    </Layouts.app>
    """
  end

  # Searchable dropdown backed by a native <datalist> (type to filter). The
  # enclosing <form phx-change> resolves the typed/selected name to a row.
  attr :id, :string, required: true
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :type_event, :string, required: true
  attr :select_event, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, default: ""
  attr :resolved, :boolean, default: false
  attr :open, :boolean, default: false
  attr :placeholder, :string, default: ""
  attr :disabled, :boolean, default: false

  defp qb_combo(assigns) do
    assigns = assign(assigns, :matches, filter_options(assigns.options, assigns.value))

    ~H"""
    <div class="relative">
      <label class="block text-[11px] font-semibold text-gray-500 mb-1">{@label}</label>
      <form phx-change={@type_event} autocomplete="off">
        <div class="relative">
          <input
            name="v"
            value={@value}
            phx-focus="open_combo"
            phx-value-field={@field}
            placeholder={@placeholder}
            disabled={@disabled}
            autocomplete="off"
            class={[
              "w-full px-3 py-1.5 text-sm border rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-400 disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed",
              if(@resolved, do: "border-green-300 bg-green-50/40", else: "border-gray-200")
            ]}
          />
          <.icon :if={@resolved} name="hero-check-circle-solid" class="w-4 h-4 text-green-500 absolute right-2.5 top-1/2 -translate-y-1/2" />
        </div>
      </form>
      <div
        :if={@open and not @disabled}
        class="absolute left-0 right-0 mt-1 z-30 max-h-56 overflow-y-auto bg-white border border-gray-200 rounded-lg shadow-lg"
      >
        <button
          :for={o <- @matches}
          type="button"
          phx-click={@select_event}
          phx-value-id={o.id}
          phx-value-name={o.name}
          class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-orange-50 hover:text-orange-700"
        >
          {o.name}
        </button>
        <div :if={@matches == []} class="px-3 py-2 text-sm text-gray-400">No matches</div>
      </div>
    </div>
    """
  end

  defp experience_level_class("entry"), do: "bg-gray-100 text-gray-600"
  defp experience_level_class("mid"), do: "bg-amber-50 text-amber-700"
  defp experience_level_class("senior"), do: "bg-orange-100 text-orange-700"
  defp experience_level_class("lead"), do: "bg-orange-500 text-white"
  defp experience_level_class(_), do: "bg-gray-100 text-gray-600"

  defp parse_count(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} when n >= 0 -> n
      _ -> 0
    end
  end

  defp parse_count(_), do: 0

  # Converts each item's :percentage into a :question_count out of `total`,
  # using largest-remainder rounding so the counts always sum to `total`
  # (plain rounding of each share independently can over/undershoot it).
  defp allocate_counts([], _total), do: []

  defp allocate_counts(items, total) when total <= 0 do
    Enum.map(items, &Map.put(&1, :question_count, 0))
  end

  defp allocate_counts(items, total) do
    shares = Enum.map(items, fn item -> total * item.percentage / 100 end)
    bases = Enum.map(shares, &trunc/1)
    remainder = total - Enum.sum(bases)

    remainder_ids =
      items
      |> Enum.zip(shares)
      |> Enum.sort_by(fn {_item, share} -> -(share - trunc(share)) end)
      |> Enum.take(remainder)
      |> Enum.map(fn {item, _share} -> item.subject_id end)
      |> MapSet.new()

    items
    |> Enum.zip(bases)
    |> Enum.map(fn {item, base} ->
      count = if MapSet.member?(remainder_ids, item.subject_id), do: base + 1, else: base
      Map.put(item, :question_count, count)
    end)
  end

  defp reset_cascade(socket) do
    socket
    |> assign(:qb_branches, [])
    |> assign(:qb_curricula, [])
    |> assign(:qb_subjects, [])
    |> assign(:sel_degree, nil)
    |> assign(:sel_branch, nil)
    |> assign(:sel_curriculum, nil)
    |> assign(:sel_subject, nil)
    |> assign(:deg_text, "")
    |> assign(:br_text, "")
    |> assign(:cur_text, "")
    |> assign(:sub_text, "")
    |> assign(:open_combo, nil)
  end

  defp safe_field("degree"), do: :degree
  defp safe_field("branch"), do: :branch
  defp safe_field("curriculum"), do: :curriculum
  defp safe_field("subject"), do: :subject
  defp safe_field(_), do: nil

  defp filter_options(options, text) do
    t = String.downcase(String.trim(text || ""))

    options
    |> Enum.filter(fn %{name: n} -> t == "" or String.contains?(String.downcase(n), t) end)
    |> Enum.take(50)
  end

  # Role cards filtered by the active industry chip + search box.
  defp visible_roles(assigns) do
    term = String.downcase(String.trim(assigns.role_search || ""))
    ind = assigns.selected_industry

    Enum.filter(assigns.all_roles, fn r ->
      (is_nil(ind) or r.industry_id == ind.id) and
        (term == "" or
           String.contains?(String.downcase(r.title || ""), term) or
           String.contains?(String.downcase((r.industry && r.industry.name) || ""), term))
    end)
  end

  defp reload_data(socket) do
    socket
    |> assign(:all_roles, Jobs.list_all_roles_with_industry())
    |> assign(:role_counts, Jobs.role_subject_counts())
    |> assign(:industries, Jobs.industry_stats())
  end
end
