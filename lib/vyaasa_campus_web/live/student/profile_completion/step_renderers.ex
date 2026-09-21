defmodule VyaasaCampusWeb.Student.ProfileCompletion.StepRenderers do
  @moduledoc """
  Step rendering functions for the profile completion LiveView.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  alias VyaasaCampusWeb.DateTimeFormatter

  alias VyaasaCampusWeb.Student.ProfileCompletion.{
    DocumentUploads,
    Verification
  }

  def render_step_1(assigns) do
    ~H"""
    <div>
      <!-- Step Header — only for re-analyze; the first-time flow shows the
           top-level "Student Profile Completion" stepper instead. -->
      <%= if @reanalyze_mode? do %>
        <div class="mb-8">
          <h2 class="text-2xl font-bold text-gray-900">Re-analyze Your Resume</h2>
          <p class="text-gray-600 mt-1">Upload your updated resume to check your new Resume Score.</p>
        </div>
      <% end %>

      <!-- Student Info Display -->
      <%= if @student do %>
        <div class="mb-8 bg-gray-50 rounded-lg p-6 border border-gray-200">
          <div class="flex items-center">
            <div class="w-16 h-16 bg-linear-to-br from-orange-400 to-orange-600 rounded-full flex items-center justify-center">
              <span class="text-white font-bold text-xl">
                <%= String.first(@student.first_name || "S") %>
              </span>
            </div>
            <div class="ml-4 flex-1">
              <h3 class="text-lg font-semibold text-gray-900">
                <%= "#{@student.first_name} #{@student.last_name}" %>
                <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                  <span class="w-1.5 h-1.5 bg-green-400 rounded-full mr-1"></span>
                  Active
                </span>
              </h3>
              <p class="text-sm text-gray-600"><%= @student.email %> - <%= @student.registration_id %></p>
            </div>
            <%!-- <div>
              <button class="inline-flex items-center px-3 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50">
                Request Edit Access
              </button>
            </div> --%>
          </div>
        </div>
      <% end %>

      <!-- Education Details (first-time flow only; already verified for reanalysis) -->
      <div class="mb-8" style={if(@reanalyze_mode?, do: "display: none;", else: "")}>
        <h3 class="text-lg font-medium text-orange-600 mb-6 flex items-center">
          <.icon name="hero-academic-cap" class="w-5 h-5 mr-2" />
          Education Details
        </h3>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div class="space-y-1">
            <label class="block text-sm font-medium text-gray-700">College Name</label>
            <div class="text-sm text-gray-900 font-medium">
              <%= (@student && @student.degree) || "Not Available" %>
            </div>
          </div>

          <div class="space-y-1">
            <label class="block text-sm font-medium text-gray-700">Year of Passing</label>
            <div class="text-sm text-gray-900 font-medium">
              <%= (@student && @student.year_of_passing) || "Not Available" %>
            </div>
          </div>

          <div class="space-y-1">
            <label class="block text-sm font-medium text-gray-700">Degree</label>
            <div class="text-sm text-gray-900 font-medium">
              <%= (@student && @student.specialization) || "Not Available" %>
            </div>
          </div>

          <div class="space-y-1">
            <label class="block text-sm font-medium text-gray-700">CGPA/Percentage</label>
            <div class="text-sm text-gray-900 font-medium">
              <%= if @student && @student.cgpa do %>
                <%= @student.cgpa %> CGPA
              <% else %>
                Not Available
              <% end %>
            </div>
          </div>

          <div class="md:col-span-2 space-y-1">
            <label class="block text-sm font-medium text-gray-700">Institution</label>
            <div class="text-sm text-gray-900 font-medium">
              <%= @tenant_alias %> Institute
            </div>
          </div>
        </div>
      </div>

      <!-- Documents Upload -->
      <DocumentUploads.render_documents_section
        uploads={@uploads}
        reanalyze_mode?={@reanalyze_mode? || false}
        photo_status={@photo_status}
      />

      <!-- Preferred Role -->
      <div class="bg-white border border-gray-200 rounded-xl p-6 mb-8 shadow-sm">
        <h3 class="text-lg font-bold text-gray-900 mb-4">Preferred Role</h3>
        <form phx-change="update_job_role">
          <div class="relative">
            <select
              name="job_role"
              class="w-full appearance-none px-4 py-3 pr-10 bg-white border border-gray-200 rounded-lg text-sm text-gray-800 focus:outline-none focus:ring-2 focus:ring-orange-400 focus:border-transparent"
            >
              <option value="" selected={@preferred_job_role in [nil, ""]}>Select your preferred role</option>
              <%= for {industry_name, roles} <- @job_roles do %>
                <optgroup label={industry_name}>
                  <%= for role <- roles do %>
                    <option value={role} selected={@preferred_job_role == role}>{role}</option>
                  <% end %>
                </optgroup>
              <% end %>
            </select>
            <.icon name="hero-chevron-down" class="w-4 h-4 text-gray-400 absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none" />
          </div>
          <p class="text-xs text-gray-500 mt-2">Used to align you with relevant placement opportunities.</p>
        </form>
      </div>

      <!-- Navigation -->
      <div class="flex justify-end pt-6 border-t border-gray-200">
        <button
          phx-click="next_step"
          class="inline-flex items-center px-6 py-3 bg-orange-500 text-white text-sm font-medium rounded-lg hover:bg-orange-600 transition-colors"
        >
          <%= if @reanalyze_mode?, do: "Analyze My Resume", else: "Next - Step 2" %>
          <.icon name="hero-arrow-right" class="w-4 h-4 ml-2" />
        </button>
      </div>
    </div>
    """
  end

  def render_step_2(assigns) do
    ats_phase = assigns[:ats_phase]
    ats_data = VyaasaCampusWeb.Components.Student.Dashboard.Helpers.convert_ats_data_to_simple_map(ats_phase)
    assigns = assign(assigns, VyaasaCampusWeb.Components.Student.ResumeDashboard.props(ats_data || %{}))

    ~H"""
    <nav class="navbar">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 py-3 flex items-center justify-between flex-wrap gap-3">
      <!-- Left: File name -->
      <div class="min-w-0">
        <p class="text-sm font-semibold text-gray-800 truncate">
          <%= if @ats_phase, do: Path.basename(@ats_phase.resume_url || "resume.pdf"), else: "resume.pdf" %>
        </p>
        <p class="text-xs text-gray-400">
          Last updated: <%= if @ats_phase, do: format_updated_at(@ats_phase.updated_at), else: "-" %>
        </p>
      </div>

      <!-- Center: Job Title (locked — analysis was run against this role) — Vya-032 -->
      <div class="order-last md:order-0 w-full md:w-auto flex-1 min-w-[160px] max-w-xs">
        <input type="text" value={@preferred_job_role} readonly
          title={@preferred_job_role}
          class="w-full px-4 py-2 text-sm bg-gray-100 border border-gray-200 rounded-lg text-gray-600 cursor-not-allowed focus:outline-none truncate"
          placeholder="Job Title">
      </div>

      <!-- Right: Actions -->
      <div class="flex items-center gap-2 sm:gap-3 shrink-0">
        <button phx-click="download_report" class="text-sm bg-orange-500 hover:bg-orange-600 text-white px-4 py-2 rounded-lg flex items-center gap-1.5 transition font-medium shadow-sm">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/></svg>
          <span class="hidden sm:inline">Download Report</span>
        </button>
      </div>
    </div>
    </nav>
    <div class="max-w-7xl mx-auto px-4 sm:px-6">
      <VyaasaCampusWeb.Components.Student.ResumeDashboard.dashboard
        score={@score}
        completeness={@completeness}
        relevance={@relevance}
        sanity={@sanity}
        completeness_feedback={@completeness_feedback}
        relevance_feedback={@relevance_feedback}
        sanity_feedback={@sanity_feedback}
        meta={@meta}
        improvement_items={@improvement_items}
        summary_text={@summary_text}
        total_experience={@total_experience}
        technical_skills={@technical_skills}
        non_technical_skills={@non_technical_skills}
        work_experience={@work_experience}
        education_list={@education_list}
        projects={@projects}
        ext_links={@ext_links}
      />

      <!-- Navigation -->
      <div class="flex justify-between pt-6 border-t border-gray-200">
        <button
          phx-click="prev_step"
          class="px-6 py-3 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors flex items-center gap-2 font-medium"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"></path>
          </svg>
          Back to Profile
        </button>
        <button
          phx-click="next_step"
          class="px-6 py-3 bg-orange-500 text-white rounded-lg hover:bg-orange-600 transition-colors flex items-center gap-2 font-medium shadow-md"
        >
          <%= if @reanalyze_mode?, do: "View Full Report", else: "Continue to Verification" %>
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
          </svg>
        </button>
      </div>
    </div>
    """
  end

  # Helper functions for extracting data from ats_data assigns

  defp get_ats_final_score(assigns) do
    score =
      get_in(assigns, [:ats_data, :ats_score]) ||
        get_in(assigns, [:ats_data, :ats_detail, "final_score"]) || 0

    case score do
      s when is_number(s) -> round(s)
      _ -> 0
    end
  end

  defp get_completeness_score(assigns) do
    # NEW: Try metadata first, then direct completeness
    score =
      get_in(assigns, [:ats_data, :metadata, "completeness_score"]) ||
        get_in(assigns, [:ats_data, :completeness, :score]) ||
        get_in(assigns, [:ats_data, :completeness, "score"]) || 0

    case score do
      s when is_number(s) -> round(s)
      _ -> 0
    end
  end

  defp get_relevance_score(assigns) do
    # NEW: Try metadata first, then direct relevance
    score =
      get_in(assigns, [:ats_data, :metadata, "relevance_score"]) ||
        get_in(assigns, [:ats_data, :relevance, :score]) ||
        get_in(assigns, [:ats_data, :relevance, "score"]) || 0

    case score do
      s when is_number(s) -> round(s)
      _ -> 0
    end
  end

  defp get_sanity_score(assigns) do
    # Python sanity key is "final_sanity_score"
    score =
      get_in(assigns, [:ats_data, :metadata, "sanity_score"]) ||
        get_in(assigns, [:ats_data, :sanity, "final_sanity_score"]) ||
        get_in(assigns, [:ats_data, :sanity, "score"]) ||
        get_in(assigns, [:ats_data, :sanity, "final_score"]) || 0

    case score do
      s when is_number(s) -> round(s)
      _ -> 0
    end
  end

  defp get_completeness_message(assigns) do
    # NEW: feedback is now in metadata or completeness
    feedback =
      get_in(assigns, [:ats_data, :metadata, "completeness_feedback"]) ||
        get_in(assigns, [:ats_data, :completeness, :feedback]) ||
        get_in(assigns, [:ats_data, :completeness, "feedback"]) || []

    if length(feedback) == 0 do
      "All major sections present"
    else
      "Some sections missing"
    end
  end

  defp get_relevance_message(assigns) do
    # NEW: justification is now in metadata
    justification =
      get_in(assigns, [:ats_data, :metadata, "relevance_justification"]) ||
        get_in(assigns, [:ats_data, :relevance, :details, :justification]) ||
        get_in(assigns, [:ats_data, :relevance, "details", "justification"]) ||
        get_in(assigns, [:ats_data, :relevance, :justification])

    if justification do
      String.split(justification, ".") |> List.first() || "Skills need better alignment"
    else
      "Skills need better alignment"
    end
  end

  defp get_sanity_message(assigns) do
    issues = get_sanity_issues(assigns)

    if length(issues) == 0 do
      "No major inconsistencies found"
    else
      "#{length(issues)} issue(s) found"
    end
  end

  defp get_areas_for_improvement(assigns) do
    feedback =
      get_in(assigns, [:ats_data, :metadata, "completeness_feedback"]) ||
        get_in(assigns, [:ats_data, :completeness, :feedback]) ||
        get_in(assigns, [:ats_data, :completeness, "feedback"]) || []

    feedback
  end

  defp has_areas_for_improvement?(assigns) do
    improvements = get_areas_for_improvement(assigns)
    length(improvements) > 0
  end

  defp get_professional_summary(assigns) do
    summary = get_in(assigns, [:ats_data, :ats_detail, "groq_data", "Professional_Summary"]) || []

    case summary do
      [first | _] when is_binary(first) -> first
      s when is_binary(s) -> s
      _ -> nil
    end
  end

  defp has_professional_summary?(assigns) do
    get_professional_summary(assigns) != nil
  end

  defp get_total_experience(assigns) do
    # Try to get from professional_summary field
    experience =
      get_in(assigns, [:ats_data, :professional_summary, "total_experience"]) ||
        get_in(assigns, [:ats_data, :professional_summary, :total_experience]) ||
        get_in(assigns, [:ats_data, :ats_detail, "groq_data", "Total_Experience"])

    case experience do
      exp when is_binary(exp) and exp != "" -> exp
      [exp | _] when is_binary(exp) -> exp
      _ -> nil
    end
  end

  defp has_total_experience?(assigns) do
    get_total_experience(assigns) != nil
  end

  defp get_technical_skills(assigns) do
    skills = get_in(assigns, [:ats_data, :skills])

    case skills do
      %{technical: tech} when is_list(tech) -> tech
      s when is_list(s) -> s
      s when is_map(s) -> Map.get(s, "technical_skills", []) ++ Map.get(s, :technical, [])
      _ -> []
    end
  end

  defp has_technical_skills?(assigns) do
    skills = get_technical_skills(assigns)
    is_list(skills) && length(skills) > 0
  end

  defp get_non_technical_skills(assigns) do
    skills = get_in(assigns, [:ats_data, :skills])

    case skills do
      %{non_technical: non_tech} when is_list(non_tech) -> non_tech
      s when is_map(s) -> Map.get(s, "non_technical_skills", []) ++ Map.get(s, :non_technical, [])
      _ -> []
    end
  end

  defp has_non_technical_skills?(assigns) do
    skills = get_non_technical_skills(assigns)
    is_list(skills) && length(skills) > 0
  end

  # Work experience helpers
  defp get_work_experience(assigns) do
    get_in(assigns, [:ats_data, :work_experience]) || []
  end

  defp has_work_experience?(assigns) do
    exp = get_work_experience(assigns)
    is_list(exp) && length(exp) > 0
  end

  # Education helpers
  defp get_education(assigns) do
    get_in(assigns, [:ats_data, :education]) || []
  end

  defp has_education?(assigns) do
    edu = get_education(assigns)
    is_list(edu) && length(edu) > 0
  end

  defp get_education_degree(edu) when is_map(edu) do
    Map.get(edu, "Degree") || Map.get(edu, "degree") || Map.get(edu, :degree) || "Degree"
  end

  defp get_education_degree(_edu), do: "Degree"

  defp get_education_institution(edu) when is_map(edu) do
    Map.get(edu, "Institution") || Map.get(edu, "institution") || Map.get(edu, :institution) || "Institution"
  end

  defp get_education_institution(_edu), do: "Institution"

  defp get_education_year(edu) when is_map(edu) do
    Map.get(edu, "Year") || Map.get(edu, "year") || Map.get(edu, :year)
  end

  defp get_education_year(_edu), do: nil

  # Projects helpers
  defp get_projects(assigns) do
    get_in(assigns, [:ats_data, :projects]) || []
  end

  defp has_projects?(assigns) do
    projects = get_projects(assigns)
    is_list(projects) && length(projects) > 0
  end

  defp get_project_name(project) when is_map(project) do
    Map.get(project, "Project_Name") || Map.get(project, "name") || Map.get(project, :name) || "Project"
  end

  defp get_project_name(_project), do: "Project"

  defp get_project_description(project) when is_map(project) do
    Map.get(project, "Description") || Map.get(project, "description") || Map.get(project, :description)
  end

  defp get_project_description(_project), do: nil

  defp get_project_technologies(project) when is_map(project) do
    tech = Map.get(project, "Technologies_Used") || Map.get(project, "technologies") || Map.get(project, :technologies)

    case tech do
      t when is_list(t) -> t
      t when is_binary(t) -> String.split(t, ",") |> Enum.map(&String.trim/1)
      _ -> nil
    end
  end

  defp get_project_technologies(_project), do: nil

  # Languages helpers
  defp get_languages(assigns) do
    langs = get_in(assigns, [:ats_data, :languages]) || []

    Enum.map(langs, fn
      %{"language" => lang} -> lang
      %{language: lang} -> lang
      lang when is_binary(lang) -> lang
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp has_languages?(assigns) do
    langs = get_languages(assigns)
    is_list(langs) && length(langs) > 0
  end

  # External links helpers
  defp has_external_links?(assigns) do
    links = get_in(assigns, [:ats_data, :external_links]) || %{}

    get_linkedin_link(assigns) != nil ||
      get_github_link(assigns) != nil ||
      get_portfolio_link(assigns) != nil ||
      (is_map(links) && map_size(links) > 0)
  end

  defp get_linkedin_link(assigns) do
    links = get_in(assigns, [:ats_data, :external_links]) || %{}
    link = Map.get(links, :linkedin) || Map.get(links, "linkedin")
    if link && link != "", do: link, else: nil
  end

  defp get_github_link(assigns) do
    links = get_in(assigns, [:ats_data, :external_links]) || %{}
    link = Map.get(links, :github) || Map.get(links, "github")
    if link && link != "", do: link, else: nil
  end

  defp get_portfolio_link(assigns) do
    links = get_in(assigns, [:ats_data, :external_links]) || %{}
    link = Map.get(links, :portfolio) || Map.get(links, "portfolio")
    if link && link != "", do: link, else: nil
  end

  # Rating helpers
  defp get_rating(score) when is_number(score) and score >= 85, do: "Excellent"
  defp get_rating(score) when is_number(score) and score >= 70, do: "Good"
  defp get_rating(score) when is_number(score) and score >= 50, do: "Fair"
  defp get_rating(_score), do: "Needs Work"

  defp get_rating_class(score) when is_number(score) and score >= 85, do: "bg-green-100 text-green-800"
  defp get_rating_class(score) when is_number(score) and score >= 70, do: "bg-yellow-100 text-yellow-800"
  defp get_rating_class(score) when is_number(score) and score >= 50, do: "bg-orange-100 text-orange-800"
  defp get_rating_class(_score), do: "bg-red-100 text-red-800"

  defp get_score_color(score) when is_number(score) and score >= 85, do: "text-green-600"
  defp get_score_color(score) when is_number(score) and score >= 70, do: "text-yellow-600"
  defp get_score_color(score) when is_number(score) and score >= 50, do: "text-orange-600"
  defp get_score_color(_score), do: "text-red-600"

  defp get_bar_color(score) when is_number(score) and score >= 85, do: "bg-green-600"
  defp get_bar_color(score) when is_number(score) and score >= 70, do: "bg-yellow-600"
  defp get_bar_color(score) when is_number(score) and score >= 50, do: "bg-orange-600"
  defp get_bar_color(_score), do: "bg-red-600"

  # Completeness feedback helpers
  defp has_completeness_feedback?(assigns) do
    feedback =
      get_in(assigns, [:ats_data, :metadata, "completeness_feedback"]) ||
        get_in(assigns, [:ats_data, :completeness, :feedback]) ||
        get_in(assigns, [:ats_data, :completeness, "feedback"]) || []

    is_list(feedback) && length(feedback) > 0
  end

  defp get_completeness_feedback(assigns) do
    get_in(assigns, [:ats_data, :metadata, "completeness_feedback"]) ||
      get_in(assigns, [:ats_data, :completeness, :feedback]) ||
      get_in(assigns, [:ats_data, :completeness, "feedback"]) || []
  end

  # Relevance feedback helpers
  defp has_relevance_feedback?(assigns) do
    get_relevance_justification(assigns) != nil ||
      has_matching_keywords?(assigns) ||
      has_missing_keywords?(assigns)
  end

  defp get_relevance_justification(assigns) do
    get_in(assigns, [:ats_data, :metadata, "relevance_justification"]) ||
      get_in(assigns, [:ats_data, :relevance, :details, :justification]) ||
      get_in(assigns, [:ats_data, :relevance, "details", "justification"]) ||
      get_in(assigns, [:ats_data, :relevance, :justification])
  end

  defp has_matching_keywords?(assigns) do
    keywords = get_matching_keywords(assigns)
    is_list(keywords) && length(keywords) > 0
  end

  defp get_matching_keywords(assigns) do
    get_in(assigns, [:ats_data, :metadata, "matching_keywords"]) ||
      get_in(assigns, [:ats_data, :relevance, :details, :matching_keywords]) ||
      get_in(assigns, [:ats_data, :relevance, "details", "matching_keywords"]) ||
      get_in(assigns, [:ats_data, :relevance, :matching_keywords]) || []
  end

  defp has_missing_keywords?(assigns) do
    keywords = get_missing_keywords(assigns)
    is_list(keywords) && length(keywords) > 0
  end

  defp get_missing_keywords(assigns) do
    get_in(assigns, [:ats_data, :metadata, "missing_keywords"]) ||
      get_in(assigns, [:ats_data, :relevance, :details, :missing_keywords]) ||
      get_in(assigns, [:ats_data, :relevance, "details", "missing_keywords"]) ||
      get_in(assigns, [:ats_data, :relevance, :missing_keywords]) || []
  end

  # Sanity check feedback helpers
  defp has_sanity_issues?(assigns) do
    issues = get_sanity_issues(assigns)
    length(issues) > 0
  end

  defp get_sanity_issues(assigns) do
    # Python sanity structure uses "breakdown" map, each category has "issues" list.
    # We store the flattened list in metadata["sanity_issues"].
    # Fall back to reading directly from the sanity object's breakdown.
    from_metadata = get_in(assigns, [:ats_data, :metadata, "sanity_issues"])

    from_breakdown =
      case get_in(assigns, [:ats_data, :sanity, "breakdown"]) do
        breakdown when is_map(breakdown) ->
          breakdown
          |> Enum.flat_map(fn {_cat, data} ->
            case data do
              %{"issues" => issues} when is_list(issues) -> issues
              _ -> []
            end
          end)
          |> Enum.reject(&(&1 == "" or is_nil(&1)))

        _ ->
          []
      end

    (from_metadata || from_breakdown) |> Enum.uniq()
  end

  def render_step_3(assigns) do
    ~H"""
    <Verification.render_verification_section assigns={assigns} />
    """
  end

  defp format_updated_at(value), do: DateTimeFormatter.format_relative(value)
end
