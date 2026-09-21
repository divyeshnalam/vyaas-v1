defmodule VyaasaCampus.AI.Interview.Profile do
  @moduledoc """
  Candidate profile for the (rebuilt) interview, adapted from the already-parsed
  resume / ATS phase. Mirrors the dev `CandidateProfile`: projects (with GitHub
  links), work history, skills, GitHub URLs, inferred domain + experience level.

  Resume *extraction* is upstream now (the ATS resume scorer) — this only adapts
  that structured output into the shape the planner/interviewer consume.
  """

  defstruct name: nil,
            email: nil,
            phone: nil,
            target_role: "",
            domain: "other",
            experience_years: 0.0,
            experience_level: "fresher",
            primary_skills: [],
            secondary_skills: [],
            claimed_skills: [],
            projects: [],
            work_history: [],
            github_urls: [],
            portfolio_urls: [],
            education: [],
            # Strengths/gaps vs the JD — filled by the Extractor agent.
            strong_areas: [],
            weak_areas: [],
            missing_skills: [],
            # Job description for the target role, as defined by the super-admin
            # on the global job_roles screen (skills + free-text description).
            jd_skills: [],
            jd_text: ""

  @type project :: %{name: String.t(), technologies: [String.t()], description: String.t(), github_url: String.t() | nil}

  @doc "Build a profile from a `StudentAtsPhase` struct (or any map with the same keys)."
  def from_ats_phase(ats) do
    pi = get(ats, :personal_information) || %{}
    summary = get(ats, :professional_summary) || %{}
    skills = get(ats, :skills) || %{}

    projects = adapt_projects(get(ats, :projects) || [])
    project_github = projects |> Enum.map(& &1.github_url) |> Enum.reject(&blank?/1)

    # Older resumes were parsed before project repo links were preserved, so
    # their repos live only in the extractor's link set (portfolio_and_links).
    # Harvest any github.com URLs from there too, so the interviewer can ground
    # ownership questions in real repos for already-parsed resumes as well.
    extracted_github = extracted_github_urls(ats)

    github_urls =
      ([pi["github_profile"]] ++ project_github ++ extracted_github)
      |> Enum.reject(&blank?/1)
      |> Enum.uniq()

    technical = skills_list(skills, "technical_skills") ++ skills_list(skills, "Technical")
    exp_years = parse_years(summary["total_experience"])

    %__MODULE__{
      name: pi["full_name"] || nil,
      email: pi["email_address"] || nil,
      target_role: to_string(get(ats, :preferred_role) || ""),
      domain: infer_domain(technical, to_string(get(ats, :preferred_role) || "")),
      experience_years: exp_years,
      experience_level: if(exp_years >= 1.0, do: "experienced", else: "fresher"),
      primary_skills: Enum.uniq(technical),
      projects: projects,
      work_history: adapt_experience(get(ats, :work_experience) || []),
      github_urls: github_urls,
      education: get(ats, :education) || []
    }
  end

  @doc """
  Attach the target role's job description (super-admin defined skills + free
  text) to the profile. No-op-safe: nil/blank inputs leave the profile usable.
  """
  def put_jd(%__MODULE__{} = profile, skills, text) do
    %{
      profile
      | jd_skills: skills |> List.wrap() |> Enum.map(&to_string/1) |> Enum.reject(&(String.trim(&1) == "")),
        jd_text: (text || "") |> to_string() |> String.trim()
    }
  end

  # ── adapters ────────────────────────────────────────────────────────────────

  # Pull github.com URLs out of the extractor's stored link set. Handles the
  # %{"other_links" => [...]} map, a bare list, and both %{"uri"} / %{"url"} /
  # string link shapes.
  defp extracted_github_urls(ats) do
    case get(ats, :portfolio_and_links) do
      %{"other_links" => links} -> links
      links when is_list(links) -> links
      _ -> []
    end
    |> List.wrap()
    |> Enum.map(fn
      l when is_binary(l) -> l
      l when is_map(l) -> l["uri"] || l["url"] || l["URI"] || l["URL"] || l["link"] || ""
      _ -> ""
    end)
    |> Enum.filter(&(is_binary(&1) and String.contains?(String.downcase(&1), "github.com")))
  end

  defp adapt_projects(list) when is_list(list) do
    Enum.map(list, fn p ->
      %{
        name: (p["Project_Name"] || p["name"] || "") |> to_string() |> String.trim(),
        technologies: List.wrap(p["Technologies_Used"] || p["technologies"] || []),
        description: (p["Description"] || p["description"] || "") |> to_string(),
        github_url: blankify(p["Github_Link"] || p["github_url"]),
        highlights: List.wrap(p["highlights"] || [])
      }
    end)
    |> Enum.reject(&(&1.name == ""))
  end

  defp adapt_projects(_), do: []

  defp adapt_experience(list) when is_list(list) do
    Enum.map(list, fn e ->
      %{
        company: (e["Company"] || e["company"] || "") |> to_string(),
        role: (e["Role"] || e["role"] || e["Title"] || "") |> to_string(),
        duration: (e["Duration"] || e["duration"] || "") |> to_string(),
        technologies: List.wrap(e["Technologies_Used"] || e["technologies"] || []),
        responsibilities: List.wrap(e["Responsibilities"] || e["responsibilities"] || []),
        highlights: List.wrap(e["highlights"] || [])
      }
    end)
    |> Enum.reject(&(&1.company == "" and &1.role == ""))
  end

  defp adapt_experience(_), do: []

  # ── helpers ───────────────────────────────────────────────────────────────
  defp get(m, key) when is_map(m), do: Map.get(m, key) || Map.get(m, to_string(key))
  defp get(_, _), do: nil

  defp skills_list(skills, key) when is_map(skills) do
    case skills[key] do
      list when is_list(list) ->
        Enum.map(list, fn
          s when is_binary(s) -> s
          m when is_map(m) -> m["name"] || m["skill"] || ""
          o -> to_string(o)
        end)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  defp skills_list(_, _), do: []

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false

  defp blankify(v), do: if(blank?(v), do: nil, else: String.trim(to_string(v)))

  defp parse_years(nil), do: 0.0
  defp parse_years(n) when is_number(n), do: n / 1

  defp parse_years(s) when is_binary(s) do
    case Regex.run(~r/(\d+(?:\.\d+)?)/, s) do
      [_, num] -> String.to_float(if String.contains?(num, "."), do: num, else: num <> ".0")
      _ -> 0.0
    end
  end

  defp parse_years(_), do: 0.0

  # Lightweight keyword domain inference (port of extractor.infer_domain).
  @domain_keywords %{
    "ml_ai" => ~w(machine learning tensorflow pytorch model nlp neural deep learning),
    "data_science" => ~w(pandas numpy data analysis visualization statistics jupyter),
    "frontend" => ~w(react vue angular css html tailwind frontend ui),
    "backend" => ~w(api server database sql node express django flask backend),
    "fullstack" => ~w(fullstack full-stack mern mean),
    "devops" => ~w(docker kubernetes ci cd aws terraform devops),
    "mobile" => ~w(android ios flutter react native kotlin swift mobile)
  }

  defp infer_domain(skills, role) do
    blob = (Enum.join(skills, " ") <> " " <> role) |> String.downcase()

    @domain_keywords
    |> Enum.map(fn {dom, kws} -> {dom, Enum.count(kws, &String.contains?(blob, &1))} end)
    |> Enum.max_by(fn {_d, n} -> n end, fn -> {"other", 0} end)
    |> case do
      {_d, 0} -> "other"
      {d, _} -> d
    end
  end
end
