defmodule VyaasaCampus.AI.Interview.Extractor do
  @moduledoc """
  Enriches an already-structured `%Profile{}` with JD-comparison fields via the
  LLM — strong/weak/missing areas, primary/secondary/claimed skill buckets, and
  domain — by comparing the candidate's resume (reconstructed from the structured
  profile) against the target job description.

  Port of the reference `agents/extractor.py`. Resume *extraction* is already
  done upstream (the ATS resume scorer), so this only adds the JD comparison: it
  KEEPS the authoritative name/email/projects/work_history/education from the
  input profile and only merges the comparison fields.

  On any LLM or parse failure, returns the input profile unchanged.
  """

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.Interview.{Profile, Sanitize, Specializations}

  require Logger

  # ── System Prompt (verbatim from EXTRACTOR_SYSTEM_PROMPT) ───────────────────
  @system_prompt """
  You are an expert resume analyst and talent assessor.
  Your job is to extract structured information from a resume and
  compare it against a job description.

  You must always respond with valid JSON only.
  No explanation, no markdown, no code blocks — raw JSON only.

  Be precise. Do not invent information not present in the resume.
  If something is unclear, make your best inference and note it.\
  """

  @model "openai/gpt-oss-120b"

  @doc """
  Enrich an already-structured profile with JD-comparison fields via the LLM.

  Returns an updated `%Profile{}`; on ANY failure returns the input profile
  unchanged.
  """
  @spec enrich(Profile.t(), String.t()) :: Profile.t()
  def enrich(%Profile{} = profile, jd_text) do
    resume_text = build_resume_text(profile)
    prompt = build_extraction_prompt(resume_text, jd_text || "")

    messages = [
      %{role: "system", content: @system_prompt <> "\n\n" <> Sanitize.injection_defense()},
      %{role: "user", content: prompt}
    ]

    opts = [
      model: @model,
      temperature: 0.1,
      max_tokens: 3500,
      timeout: 120_000,
      response_format: %{"type" => "json_object"}
    ]

    with {:ok, %{"content" => raw}} <- GroqClient.chat(messages, opts),
         {:ok, data} when is_map(data) <- GroqClient.extract_json(raw) do
      merge(profile, data)
    else
      {:error, reason} ->
        Logger.error("[Extractor] enrichment failed: #{inspect(reason)}")
        profile

      other ->
        Logger.error("[Extractor] unexpected response: #{inspect(other)}")
        profile
    end
  end

  # ── Merge LLM output onto the authoritative profile ─────────────────────────
  defp merge(%Profile{} = profile, data) do
    domain =
      case data["domain"] do
        d when is_binary(d) ->
          d = d |> String.downcase() |> String.trim()
          if d in Specializations.list_domains(), do: d, else: profile.domain

        _ ->
          profile.domain
      end

    %{
      profile
      | primary_skills: string_list(data["primary_skills"]),
        secondary_skills: string_list(data["secondary_skills"]),
        claimed_skills: string_list(data["claimed_skills"]),
        strong_areas: string_list(data["strong_areas"]),
        weak_areas: string_list(data["weak_areas"]),
        missing_skills: string_list(data["missing_skills"]),
        portfolio_urls: string_list(data["portfolio_urls"]),
        domain: domain,
        experience_years: clamp_years(data["experience_years"])
    }
  end

  defp string_list(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp string_list(_), do: []

  defp clamp_years(n) when is_number(n), do: n |> max(0.0) |> min(1.0) |> Kernel./(1)

  defp clamp_years(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> clamp_years(f)
      :error -> 0.0
    end
  end

  defp clamp_years(_), do: 0.0

  # ── Resume text reconstruction from the structured profile ──────────────────
  defp build_resume_text(%Profile{} = p) do
    [
      "Name: #{p.name || ""}",
      "Email: #{p.email || ""}",
      "",
      "Primary Skills: #{Enum.join(p.primary_skills, ", ")}",
      "Secondary Skills: #{Enum.join(p.secondary_skills, ", ")}",
      "Claimed Skills: #{Enum.join(p.claimed_skills, ", ")}",
      "",
      "Projects:",
      projects_text(p.projects),
      "",
      "Work History:",
      work_history_text(p.work_history),
      "",
      "Education:",
      education_text(p.education)
    ]
    |> Enum.join("\n")
    |> String.trim()
  end

  defp projects_text([]), do: "  (none)"

  defp projects_text(projects) do
    projects
    |> Enum.map(fn proj ->
      name = field(proj, :name)
      desc = field(proj, :description)
      techs = field_list(proj, :technologies)
      github = field(proj, :github_url)

      [
        "  - #{name}",
        "    Description: #{desc}",
        "    Technologies: #{Enum.join(techs, ", ")}",
        "    GitHub: #{github}"
      ]
      |> Enum.join("\n")
    end)
    |> Enum.join("\n")
  end

  defp work_history_text([]), do: "  (none)"

  defp work_history_text(history) do
    history
    |> Enum.map(fn w ->
      company = field(w, :company)
      role = field(w, :role)
      duration = field(w, :duration)
      techs = field_list(w, :technologies)
      resp = field_list(w, :responsibilities)

      [
        "  - #{company} — #{role} (#{duration})",
        "    Technologies: #{Enum.join(techs, ", ")}",
        "    Responsibilities: #{Enum.join(resp, "; ")}"
      ]
      |> Enum.join("\n")
    end)
    |> Enum.join("\n")
  end

  defp education_text([]), do: "  (none)"

  defp education_text(education) when is_list(education) do
    education
    |> Enum.map(fn
      e when is_binary(e) -> "  - #{e}"
      e when is_map(e) -> "  - #{Map.values(e) |> Enum.map_join(", ", &to_string/1)}"
      e -> "  - #{to_string(e)}"
    end)
    |> Enum.join("\n")
  end

  defp education_text(_), do: "  (none)"

  defp field(m, key) when is_map(m) do
    (Map.get(m, key) || Map.get(m, to_string(key)) || "") |> to_string()
  end

  defp field(_, _), do: ""

  defp field_list(m, key) when is_map(m) do
    (Map.get(m, key) || Map.get(m, to_string(key)) || []) |> List.wrap() |> Enum.map(&to_string/1)
  end

  defp field_list(_, _), do: []

  # ── Prompt builder (verbatim JSON schema from _build_extraction_prompt) ─────
  defp build_extraction_prompt(resume_text, jd_text) do
    """
    Extract structured information from the resume below and compare it with the job description.
    All candidates are freshers (students or 0-1 year experience).

    Return ONLY this JSON structure — no other text:

    {
      "name": "full name or null",
      "email": "email or null",
      "phone": "phone or null",
      "experience_years": 0.0,
      "domain": "backend | java_backend | go_backend | rust_backend | dotnet_backend | php_backend | frontend | fullstack | flutter_mobile | data_science | ml_ai | genai | data_engineering | devops | cybersecurity | mobile | qa | hr | marketing | sales | finance | operations | product | design | legal | other",
      "primary_skills": ["skills that directly match the JD"],
      "secondary_skills": ["other skills on resume not in JD"],
      "claimed_skills": ["every skill mentioned on resume"],
      "education": ["degree, institution, year"],
      "projects": [
        {
          "name": "project name",
          "description": "what it does",
          "technologies": ["tech used"],
          "github_url": "url or null",
          "highlights": ["key achievements or features claimed"]
        }
      ],
      "work_history": [
        {
          "company": "company or organisation name",
          "role": "job title or internship title",
          "duration": "e.g. 6 months or 1 year",
          "technologies": ["tools or tech used in this role"],
          "responsibilities": ["what they did — 2 to 3 specific items"],
          "highlights": ["key outcomes, achievements, or skills demonstrated"]
        }
      ],
      "github_urls": ["github profile or repo links found in resume"],
      "portfolio_urls": ["other links: portfolio, kaggle, huggingface, linkedin etc"],
      "strong_areas": ["areas where candidate is strong vs JD requirements"],
      "weak_areas": ["areas where candidate is weak vs JD requirements"],
      "missing_skills": ["skills JD requires that resume doesn't mention at all"]
    }

    Note: Only include entries in "work_history" where the candidate actually worked somewhere (internships, part-time jobs, full-time jobs). Do NOT include personal projects here — those go in "projects".

    --- RESUME ---
    #{Sanitize.wrap_untrusted(resume_text, "resume")}

    --- JOB DESCRIPTION ---
    #{Sanitize.wrap_untrusted(jd_text, "job description")}
    """
    |> String.trim()
  end
end
