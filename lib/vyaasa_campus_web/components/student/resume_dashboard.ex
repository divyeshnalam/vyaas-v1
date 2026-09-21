defmodule VyaasaCampusWeb.Components.Student.ResumeDashboard do
  @moduledoc """
  Shared "Resume Analysis Dashboard" presentation — the overall-score gauge,
  the three sub-score cards, areas for improvement, and the extracted resume
  sections (summary, skills, experience, education, projects, links).

  Rendered identically by the Resume Insights page and by the after-parse
  result in the profile-completion flow, so the two never drift. Callers own
  their surrounding chrome (sidebar/stepper) and footer action buttons.
  """
  use Phoenix.Component

  import VyaasaCampusWeb.Components.UI, only: [icon: 1]
  alias VyaasaCampusWeb.Components.Student.Dashboard.Helpers, as: DH

  @gauge_arc_length 251.33

  attr :score, :integer, default: 0
  attr :completeness, :integer, default: 0
  attr :relevance, :integer, default: 0
  attr :sanity, :integer, default: 0
  attr :completeness_feedback, :list, default: []
  attr :relevance_feedback, :list, default: []
  attr :sanity_feedback, :list, default: []
  attr :meta, :map, default: %{}
  attr :improvement_items, :list, default: []
  attr :summary_text, :string, default: nil
  attr :total_experience, :string, default: nil
  attr :technical_skills, :list, default: []
  attr :non_technical_skills, :list, default: []
  attr :work_experience, :list, default: []
  attr :education_list, :list, default: []
  attr :projects, :list, default: []
  attr :ext_links, :list, default: []

  def dashboard(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Page header -->
      <div>
        <h1 class="text-xl sm:text-2xl font-bold text-gray-900">Resume Analysis Dashboard</h1>
        <p class="text-xs sm:text-sm text-gray-500 mt-0.5">Complete profile analysis based on your resume</p>
      </div>

      <!-- Overall Resume Score (gauge) -->
      <div class="bg-white border border-gray-100 rounded-2xl p-6 sm:p-8">
        <h2 class="text-base sm:text-lg font-bold text-gray-900 mb-6 text-center">Overall Resume Score</h2>
        <div class="flex justify-center items-center">
          <div class="relative w-72 h-44">
            <svg viewBox="0 0 200 110" class="w-full h-full">
              <defs>
                <linearGradient id="resume-gauge-gradient" x1="0%" y1="0%" x2="100%" y2="0%">
                  <stop offset="0%" stop-color="#FF6B00" />
                  <stop offset="50%" stop-color="#FACC15" />
                  <stop offset="100%" stop-color="#22C55E" />
                </linearGradient>
              </defs>
              <path d="M 20 100 A 80 80 0 0 1 180 100" fill="none" stroke="#F4ECDD" stroke-width="14" stroke-linecap="round" />
              <path
                d="M 20 100 A 80 80 0 0 1 180 100"
                fill="none"
                stroke="url(#resume-gauge-gradient)"
                stroke-width="14"
                stroke-linecap="round"
                stroke-dasharray="251.33"
                stroke-dashoffset={"#{gauge_offset(@score)}"}
              />
            </svg>
            <div class="absolute inset-0 flex flex-col items-center justify-end pb-2">
              <span class="inline-block px-3 py-0.5 mb-1 bg-cream-100 text-gray-700 text-[11px] font-semibold rounded-full">{gauge_label(@score)}</span>
              <div class="text-5xl font-bold text-gray-900 leading-none">{@score}</div>
              <div class="text-xs text-gray-500 mt-1">Out of 100</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Info banner -->
      <div class="bg-blue-50 border border-blue-100 rounded-xl px-4 py-3 flex items-start gap-2">
        <.icon name="hero-information-circle" class="w-4 h-4 text-blue-500 shrink-0 mt-0.5" />
        <p class="text-xs text-blue-900">Your resume passed basic checks, but improvements are recommended for better matching.</p>
      </div>

      <!-- 3 sub-score cards -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.sub_score_card label="Completeness" score={@completeness} tier_label={DH.score_tier(@completeness).label} tier_text={DH.score_tier(@completeness).text} hint={completeness_hint(@completeness_feedback)} />
        <.sub_score_card label="Relevance" score={@relevance} tier_label={DH.score_tier(@relevance).label} tier_text={DH.score_tier(@relevance).text} hint={relevance_hint(@relevance_feedback, @meta)} />
        <.sub_score_card label="Sanity Check" score={@sanity} tier_label={DH.score_tier(@sanity).label} tier_text={DH.score_tier(@sanity).text} hint={sanity_hint(@sanity_feedback)} />
      </div>

      <!-- Areas for Improvement -->
      <div :if={@improvement_items != []} id="areas-for-improvement" class="bg-brand-50 border border-brand-200 rounded-xl p-5">
        <div class="flex items-center justify-between mb-3">
          <div class="flex items-center gap-2">
            <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-brand-600" />
            <h3 class="text-sm font-bold text-gray-900">Areas for Improvement</h3>
          </div>
          <span class="text-[10px] font-semibold px-2 py-0.5 bg-brand-100 text-brand-700 rounded-full">{length(@improvement_items)} items</span>
        </div>
        <ul class="space-y-1.5">
          <li :for={item <- @improvement_items} class="flex items-start gap-2 text-xs text-gray-700">
            <% {label, desc} = split_feedback(item) %>
            <span class="mt-1.5 w-1.5 h-1.5 bg-brand-500 rounded-full shrink-0"></span>
            <span>
              <span :if={label} class="font-semibold text-gray-900">{label} -</span>
              <span class="text-gray-600 ml-1">{desc}</span>
            </span>
          </li>
        </ul>
      </div>

      <!-- Professional Summary -->
      <div :if={@summary_text} class="bg-white border border-gray-100 rounded-xl p-5">
        <div class="flex items-start justify-between mb-3">
          <div class="flex items-center gap-2">
            <div class="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center">
              <.icon name="hero-user" class="w-4 h-4 text-brand-600" />
            </div>
            <div>
              <h3 class="text-sm font-bold text-gray-900">Professional Summary</h3>
              <p class="text-[11px] text-gray-500">Career overview extracted from your resume</p>
            </div>
          </div>
          <span :if={@total_experience} class="inline-flex items-center gap-1 text-[11px] text-brand-700 bg-brand-50 border border-brand-100 px-2 py-1 rounded-full">
            <.icon name="hero-clock" class="w-3 h-3" /> Experience: <span class="font-semibold">{@total_experience}</span>
          </span>
        </div>
        <div class="bg-cream-50 border border-cream-200 rounded-lg p-4">
          <p class="text-xs text-gray-700 leading-relaxed">{@summary_text}</p>
        </div>
      </div>

      <!-- Skills -->
      <div :if={@technical_skills != [] || @non_technical_skills != []} class="bg-white border border-gray-100 rounded-xl p-5">
        <div class="flex items-center gap-2 mb-1">
          <div class="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center">
            <.icon name="hero-light-bulb" class="w-4 h-4 text-brand-600" />
          </div>
          <div>
            <h3 class="text-sm font-bold text-gray-900">Skills</h3>
            <p class="text-[11px] text-gray-500">Technical and non-technical skills from your profile</p>
          </div>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-6 mt-4">
          <div>
            <p class="text-[10px] font-semibold text-gray-500 tracking-wider mb-2">TECHNICAL</p>
            <div class="flex flex-wrap gap-1.5">
              <span :for={skill <- @technical_skills} class="text-[11px] px-2 py-0.5 bg-blue-50 text-blue-700 border border-blue-100 rounded">{skill}</span>
            </div>
          </div>
          <div>
            <p class="text-[10px] font-semibold text-gray-500 tracking-wider mb-2">NON-TECHNICAL</p>
            <div class="flex flex-wrap gap-1.5">
              <span :for={skill <- @non_technical_skills} class="text-[11px] px-2 py-0.5 bg-blue-50 text-blue-700 border border-blue-100 rounded">{skill}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Work Experience -->
      <div :if={@work_experience != []} class="bg-white border border-gray-100 rounded-xl p-5">
        <div class="flex items-center gap-2 mb-4">
          <div class="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center">
            <.icon name="hero-briefcase" class="w-4 h-4 text-brand-600" />
          </div>
          <div>
            <h3 class="text-sm font-bold text-gray-900">Work Experience</h3>
            <p class="text-[11px] text-gray-500">Professional experience extracted from your resume</p>
          </div>
        </div>
        <div class="space-y-4">
          <div :for={exp <- @work_experience} class="border-t border-cream-200 pt-4 first:border-t-0 first:pt-0">
            <div class="flex items-start justify-between mb-1">
              <div class="min-w-0">
                <h4 class="text-sm font-bold text-gray-900">{exp["Job_Title"] || exp["job_title"] || "Position"}</h4>
                <p class="text-xs text-brand-600 font-semibold">{exp["Company_Name"] || exp["company_name"] || "Company"}</p>
              </div>
              <span :if={exp["start_date"] || exp["end_date"]} class="text-[11px] text-gray-500 whitespace-nowrap">{exp["start_date"] || "N/A"} – {exp["end_date"] || "Present"}</span>
            </div>
            <% resp = exp["Responsibilities"] || exp["responsibilities"] %>
            <%= cond do %>
              <% is_list(resp) -> %>
                <p class="text-xs text-gray-600 leading-relaxed mt-2">{Enum.join(resp, " ")}</p>
              <% is_binary(resp) and resp != "" -> %>
                <p class="text-xs text-gray-600 leading-relaxed mt-2">{resp}</p>
              <% true -> %>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Education -->
      <div :if={@education_list != []} class="bg-white border border-gray-100 rounded-xl p-5">
        <div class="flex items-center gap-2 mb-4">
          <div class="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center">
            <.icon name="hero-academic-cap" class="w-4 h-4 text-brand-600" />
          </div>
          <div>
            <h3 class="text-sm font-bold text-gray-900">Education</h3>
            <p class="text-[11px] text-gray-500">Academic qualifications from your resume</p>
          </div>
        </div>
        <div class="space-y-3">
          <div :for={edu <- @education_list} class="border-t border-cream-200 pt-3 first:border-t-0 first:pt-0 flex items-start justify-between gap-3">
            <div class="min-w-0">
              <h4 class="text-sm font-bold text-gray-900">{edu["Degree"] || edu["degree"] || "Degree"}</h4>
              <p class="text-xs text-brand-600 font-semibold">{edu["Institution"] || edu["institution"] || ""}</p>
            </div>
            <%= case education_score(edu) do %>
              <% {kind, value} -> %>
                <span class="text-xs text-gray-600 whitespace-nowrap">{kind}: <span class="font-semibold text-gray-900">{value}</span></span>
              <% _ -> %>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Projects -->
      <div :if={@projects != []} class="bg-white border border-gray-100 rounded-xl p-5">
        <div class="flex items-center gap-2 mb-4">
          <div class="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center">
            <.icon name="hero-square-3-stack-3d" class="w-4 h-4 text-brand-600" />
          </div>
          <div>
            <h3 class="text-sm font-bold text-gray-900">Projects</h3>
            <p class="text-[11px] text-gray-500">Notable projects from your resume</p>
          </div>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div :for={{project, idx} <- Enum.with_index(@projects, 1)} class="bg-cream-50 border border-cream-200 rounded-lg p-4">
            <div class="flex items-start justify-between mb-1.5">
              <h4 class="text-sm font-bold text-gray-900 min-w-0">{project["Project_Name"] || project["name"] || "Project"}</h4>
              <span class="text-[11px] text-gray-400 font-semibold ml-2">{String.pad_leading(Integer.to_string(idx), 2, "0")}</span>
            </div>
            <% desc = project["Description"] || project["description"] %>
            <%= cond do %>
              <% is_list(desc) -> %>
                <p class="text-[11px] text-gray-600 leading-relaxed">{Enum.join(desc, " ")}</p>
              <% is_binary(desc) and desc != "" -> %>
                <p class="text-[11px] text-gray-600 leading-relaxed">{desc}</p>
              <% true -> %>
            <% end %>
            <% repo = project["Github_Link"] || project["github_link"] %>
            <a
              :if={is_binary(repo) and repo != ""}
              href={VyaasaCampusWeb.Helpers.Url.absolute(repo)}
              target="_blank"
              rel="noopener"
              class="mt-2 inline-flex items-center gap-1 text-[11px] font-semibold text-gray-700 hover:text-gray-900"
            >
              <.icon name="hero-code-bracket" class="w-3.5 h-3.5" /> View Repository
            </a>
          </div>
        </div>
      </div>

      <!-- External Links -->
      <div class="bg-white border border-gray-100 rounded-xl p-5">
        <div class="flex items-center gap-2 mb-4">
          <div class="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center">
            <.icon name="hero-link" class="w-4 h-4 text-brand-600" />
          </div>
          <div>
            <h3 class="text-sm font-bold text-gray-900">External Links</h3>
            <p class="text-[11px] text-gray-500">Your online profiles and portfolio</p>
          </div>
        </div>
        <p :if={@ext_links == []} class="text-[11px] text-gray-400 italic">No external links found in your resume.</p>
        <div :if={@ext_links != []} class="space-y-2">
          <a :for={link <- @ext_links} href={link.url} target="_blank" rel="noopener" class="flex items-center gap-3 p-3 bg-cream-50 border border-cream-200 rounded-lg hover:border-brand-200 transition">
            <div class={"w-8 h-8 rounded flex items-center justify-center shrink-0 #{link_bg(link.type)}"}>
              <.icon name={link_icon(link.type)} class={"w-4 h-4 #{link_text(link.type)}"} />
            </div>
            <div class="min-w-0">
              <p class="text-xs font-bold text-gray-900">{link_label(link.type)}</p>
              <p class="text-[11px] text-gray-500 truncate">{link.url}</p>
            </div>
          </a>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :score, :integer, required: true
  attr :tier_label, :string, required: true
  attr :tier_text, :string, required: true
  attr :hint, :string, required: true

  defp sub_score_card(assigns) do
    ~H"""
    <div class="bg-white border border-gray-100 rounded-xl p-4">
      <div class="flex items-start justify-between mb-2">
        <span class="text-xs font-semibold text-gray-700">{@label}</span>
        <span class={"text-[11px] font-semibold #{@tier_text}"}>{@tier_label}</span>
      </div>
      <div class="flex items-baseline gap-1 mb-2">
        <span class="text-3xl font-bold text-gray-900">{@score}</span>
        <span class="text-xs text-gray-400">/100</span>
      </div>
      <div class="h-1.5 bg-cream-200 rounded-full overflow-hidden mb-2">
        <div class="h-full bg-brand-500 rounded-full" style={"width: #{@score}%"}></div>
      </div>
      <p class="text-[11px] text-gray-500 mb-2">{@hint}</p>
      <a href="#areas-for-improvement" class="text-[11px] text-gray-600 hover:text-brand-600 inline-flex items-center gap-1">
        View Detailed feedback
        <.icon name="hero-arrow-right" class="w-3 h-3" />
      </a>
    </div>
    """
  end

  # ── presentational helpers ────────────────────────────────────────────────

  defp gauge_label(score) when is_number(score) and score >= 85, do: "Excellent"
  defp gauge_label(score) when is_number(score) and score >= 70, do: "Good"
  defp gauge_label(score) when is_number(score) and score >= 50, do: "Average"
  defp gauge_label(score) when is_number(score) and score >= 30, do: "Below Average"
  defp gauge_label(_), do: "Poor"

  defp gauge_offset(score) when is_number(score),
    do: @gauge_arc_length * (1 - max(0, min(100, score)) / 100)

  defp gauge_offset(_), do: @gauge_arc_length

  defp education_score(edu) do
    raw = edu["CGPA_Percentage"] || edu["cgpa_percentage"] || edu["CGPA"] || edu["cgpa"] || edu["Percentage"] || edu["percentage"]

    case raw do
      nil -> nil
      "" -> nil
      val when is_binary(val) -> if String.contains?(val, "%"), do: {"Percentage", val}, else: {"CGPA", val}
      val -> {"Score", to_string(val)}
    end
  end

  defp split_feedback(item) when is_binary(item) do
    case String.split(item, " - ", parts: 2) do
      [label, desc] ->
        {label, desc}

      [whole] ->
        case String.split(whole, ": ", parts: 2) do
          [label, desc] -> {label, desc}
          [whole_again] -> {nil, whole_again}
        end
    end
  end

  defp split_feedback(item), do: {nil, to_string(item)}

  defp completeness_hint([]), do: "All sections present"
  defp completeness_hint(_), do: "Some sections are missing"

  defp relevance_hint(_, meta) do
    core = meta["relevance_core"] || "0/0"
    essential = meta["relevance_essential"] || "0/0"
    appreciated = meta["relevance_appreciated"] || "0/0"
    "Core: #{core} Essential: #{essential} Appreciated: #{appreciated}"
  end

  defp sanity_hint([]), do: "No issues found"
  defp sanity_hint(list) when is_list(list), do: "#{length(list)} issue#{if length(list) == 1, do: "", else: "s"} found"
  defp sanity_hint(_), do: "No issues found"

  defp link_label(:linkedin), do: "LinkedIn"
  defp link_label(:github), do: "GitHub"
  defp link_label(:github_repo), do: "GitHub Repo"
  defp link_label(_), do: "Portfolio"

  defp link_icon(:linkedin), do: "hero-link"
  defp link_icon(:github), do: "hero-code-bracket"
  defp link_icon(:github_repo), do: "hero-code-bracket"
  defp link_icon(_), do: "hero-globe-alt"

  defp link_bg(:linkedin), do: "bg-blue-100"
  defp link_bg(:github), do: "bg-gray-100"
  defp link_bg(:github_repo), do: "bg-gray-100"
  defp link_bg(_), do: "bg-cream-100"

  defp link_text(:linkedin), do: "text-blue-700"
  defp link_text(:github), do: "text-gray-700"
  defp link_text(:github_repo), do: "text-gray-700"
  defp link_text(_), do: "text-brand-700"

  # ── shared data builders (used by Insights + the after-parse result) ────────

  @doc """
  Compute every dashboard prop from a normalized `ats_data` simple map (the
  shape produced by `Dashboard.Helpers.convert_ats_data_to_simple_map/1`).
  Returns a map you can splat into `dashboard/1`.
  """
  def props(ats_data) when is_map(ats_data) do
    meta = Map.get(ats_data, :metadata) || %{}
    summary_map = Map.get(ats_data, :professional_summary) || %{}
    comp_fb = meta["completeness_feedback"] || []
    rel_fb = meta["relevance_feedback"] || []
    san_fb = meta["sanity_feedback"] || []

    %{
      score: round(Map.get(ats_data, :ats_score) || 0),
      meta: meta,
      completeness: DH.safe_score(meta["completeness_score"]),
      relevance: DH.safe_score(meta["relevance_score"]),
      sanity: DH.safe_score(meta["sanity_score"]),
      completeness_feedback: comp_fb,
      relevance_feedback: rel_fb,
      sanity_feedback: san_fb,
      technical_skills: DH.get_skills_list(Map.get(ats_data, :skills) || %{}, "technical_skills"),
      non_technical_skills: DH.get_skills_list(Map.get(ats_data, :skills) || %{}, "non_technical_skills"),
      work_experience: Map.get(ats_data, :work_experience) || [],
      education_list: Map.get(ats_data, :education) || [],
      projects: Map.get(ats_data, :projects) || [],
      ext_links: collect_links(ats_data),
      improvement_items: comp_fb ++ rel_fb ++ san_fb,
      summary_text: summary_value(summary_map["summary_text"] || summary_map["summary"] || summary_map["professional_summary"]),
      total_experience: summary_value(summary_map["total_experience"])
    }
  end

  def props(_), do: props(%{})

  @doc "Gather LinkedIn + GitHub profile links, other portfolio links, and per-project repos."
  def collect_links(ats) do
    pi =
      case ats[:personal_information] do
        m when is_map(m) and not is_struct(m) -> m
        _ -> %{}
      end

    other =
      case ats[:portfolio_and_links] do
        %{"other_links" => links} when is_list(links) -> links
        %{other_links: links} when is_list(links) -> links
        links when is_list(links) -> Enum.filter(links, &is_binary/1)
        _ -> []
      end

    project_repos =
      (ats[:projects] || [])
      |> Enum.flat_map(fn
        p when is_map(p) ->
          repo = p["Github_Link"] || p["github_link"]
          if is_binary(repo) and repo != "", do: [repo], else: []

        _ ->
          []
      end)

    [pi["linkedin_profile"], pi["github_profile"]]
    |> Enum.concat(List.wrap(other))
    |> Enum.concat(project_repos)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.uniq()
    |> external_links()
  end

  defp external_links(nil), do: []
  defp external_links([]), do: []

  defp external_links(links) when is_list(links) do
    Enum.flat_map(links, fn
      l when is_binary(l) ->
        href = VyaasaCampusWeb.Helpers.Url.absolute(l)
        [%{type: detect_link_type(href), url: href, label: l}]

      l when is_map(l) ->
        url = l["url"] || l["URL"] || l["link"] || l["Link"] || l["uri"] || l["URI"]

        if url do
          href = VyaasaCampusWeb.Helpers.Url.absolute(url)
          [%{type: detect_link_type(href), url: href, label: l["name"] || l["Name"] || l["text"] || url}]
        else
          []
        end

      _ ->
        []
    end)
  end

  defp external_links(_), do: []

  defp detect_link_type(url) do
    cond do
      String.contains?(url, "linkedin.com") -> :linkedin
      github_repo?(url) -> :github_repo
      String.contains?(url, "github.com") -> :github
      true -> :other
    end
  end

  defp github_repo?(url) do
    case Regex.run(~r{github\.com/([^/?#]+)(/[^/?#]+)?}i, url) do
      [_, _user, _repo] -> true
      _ -> false
    end
  end

  defp summary_value(value) do
    text =
      case value do
        list when is_list(list) -> list |> Enum.map_join(" ", &to_string/1) |> String.trim()
        s when is_binary(s) -> String.trim(s)
        _ -> ""
      end

    if text == "", do: nil, else: text
  end
end
