defmodule VyaasaCampus.AI.Interview.Planner do
  @moduledoc """
  Builds the interview plan. LLM-driven (qwen3-32b) section selection from the
  domain's specialization menu — port of the reference `agents/planner.py` —
  with a deterministic spec-based fallback when the LLM fails.

  After section selection, project/experience sections + topics are injected
  programmatically (rotation-friendly), cultural-fit is always appended last,
  and the tech budget is capped at 9 (+1 cultural-fit = 10).
  """

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.Interview.{Profile, Sanitize, Specializations}

  require Logger

  @tech_budget 9
  @max_per_section 3
  @total_questions 10
  @model "openai/gpt-oss-120b"

  # Section → default question types (port of SECTION_QUESTION_TYPES).
  @section_question_types %{
    "resume_verification" => ["technical", "ownership_verify"],
    "project_deep_dive" => ["project_deep", "ownership_verify"],
    "core_concepts" => ["technical", "challenge"],
    "system_design" => ["technical", "scenario"],
    "problem_solving" => ["technical", "scenario"],
    "scenario_reasoning" => ["situational", "scenario"],
    "behavioral" => ["behavioral"],
    "communication_assessment" => ["behavioral", "situational"],
    "portfolio_deep_dive" => ["situational", "behavioral"],
    "experience_deep_dive" => ["ownership_verify", "technical"],
    "cultural_fit" => ["cultural_fit"]
  }

  @planner_system """
  You are a senior technical interview designer.
  Your job is to build a precise, adaptive interview plan
  based on a fresher candidate's profile and the job they are applying for.

  CRITICAL CONSTRAINTS:
  1. You have a STRICT budget of EXACTLY #{@tech_budget} questions to allocate.
  2. Allocate a maximum of 3 questions per topic/section.
  3. Do NOT include a cultural fit section (the system handles this automatically).

  The plan must be:
  - Targeted to their actual skills and projects
  - Structured in logical sections
  - Appropriate for a student / 0-1 year experience candidate
  - Friendly to start, increasing in depth gradually

  Respond with valid JSON only. No markdown, no explanation.
  """

  @doc """
  Returns %{candidate_name, target_role, domain, experience_level, sections,
  total_questions, difficulty_curve, focus_areas, avoid_topics,
  jd_matched_skills, jd_text}.
  """
  def build_plan(%Profile{} = p) do
    spec = Specializations.get(p.domain)
    {sections, meta} = llm_or_fallback(p, spec)

    sections =
      sections
      |> inject_project_topics(p)
      |> drop_portfolio_if_no_projects(p)
      |> inject_experience(p)
      |> cap_per_section()
      |> elevate()
      |> take_within_budget(@tech_budget)

    sections = sections ++ [cultural_fit_section()]
    jd_matched = jd_matched(p, meta[:jd_matched_skills])

    %{
      candidate_name: p.name,
      target_role: meta[:target_role] || p.target_role,
      domain: p.domain,
      experience_level: p.experience_level,
      sections: sections,
      total_questions: min(@total_questions, total_count(sections)),
      difficulty_curve: meta[:difficulty_curve] || "easy_to_moderate",
      focus_areas: (jd_matched ++ p.primary_skills) |> Enum.uniq() |> Enum.take(6),
      avoid_topics: meta[:avoid_topics] || [],
      jd_matched_skills: jd_matched,
      jd_text: p.jd_text
    }
  end

  @doc "Candidate's own skills that the target role's JD requires (case-insensitive)."
  def jd_matched_skills(%Profile{jd_skills: jd, primary_skills: skills}) do
    wanted = MapSet.new(jd, &String.downcase(String.trim(&1)))
    Enum.filter(skills, &MapSet.member?(wanted, String.downcase(String.trim(&1))))
  end

  defp jd_matched(p, from_llm) do
    cond do
      is_list(from_llm) and from_llm != [] -> Enum.map(from_llm, &to_string/1)
      (m = jd_matched_skills(p)) != [] -> m
      true -> Enum.take(p.primary_skills, 6)
    end
  end

  # ── LLM plan, falling back to a deterministic spec-based plan ────────────────
  defp llm_or_fallback(%Profile{} = p, spec) do
    case llm_sections(p, spec) do
      {:ok, sections, meta} when sections != [] -> {sections, meta}
      _ -> {fallback_sections(p, spec), %{}}
    end
  end

  defp llm_sections(%Profile{} = p, spec) do
    prompt = build_planner_prompt(p, spec) <> "\n/no_think"
    system = @planner_system <> "\n\n" <> Sanitize.injection_defense()

    with {:ok, %{"content" => raw}} <-
           GroqClient.chat([%{role: "system", content: system}, %{role: "user", content: prompt}],
             model: @model,
             temperature: 0.5,
             max_tokens: 3000,
             reasoning_effort: "low",
             timeout: 120_000
           ),
         {:ok, data} <- GroqClient.extract_json(GroqClient.strip_reasoning(raw)) do
      valid = MapSet.new(spec.sections)

      sections =
        (data["sections"] || [])
        |> Enum.filter(&(is_map(&1) and Map.get(&1, "name") in spec.sections))
        |> Enum.with_index()
        |> Enum.map(fn {s, i} ->
          name = s["name"]

          %{
            name: name,
            purpose: to_string(s["purpose"] || ""),
            topics: List.wrap(s["topics"] || []) |> Enum.map(&to_string/1),
            question_count: min(to_int(s["question_count"], @max_per_section), @max_per_section),
            question_types: Map.get(@section_question_types, name, ["technical"]),
            priority: to_int(s["priority"], i + 1),
            project_name: nil,
            experience_name: nil,
            github_url: nil
          }
        end)

      _ = valid

      {:ok, sections,
       %{
         target_role: data["target_role"],
         difficulty_curve: data["difficulty_curve"],
         focus_areas: data["focus_areas"],
         avoid_topics: data["avoid_topics"],
         jd_matched_skills: data["jd_matched_skills"]
       }}
    else
      other ->
        Logger.info("INTERVIEW_PLANNER | LLM plan failed, using fallback: #{inspect(other)}")
        :error
    end
  end

  # ── Planner prompt (port of _build_planner_prompt) ───────────────────────────
  defp build_planner_prompt(%Profile{} = p, spec) do
    projects_summary =
      case p.projects do
        [] ->
          "  None listed"

        list ->
          Enum.map_join(list, "\n", fn proj ->
            "  - #{proj.name}: #{Enum.join(proj.technologies, ", ")}"
          end)
      end

    """
    Build an interview plan for this fresher candidate.

    --- CANDIDATE PROFILE ---
    Name              : #{p.name || "Unknown"}
    Domain            : #{p.domain}
    Experience        : #{p.experience_years} years (fresher)
    Primary Skills    : #{Enum.join(p.primary_skills, ", ")}
    Secondary Skills  : #{Enum.join(p.secondary_skills, ", ")}
    Strong Areas      : #{Enum.join(p.strong_areas, ", ")}
    Weak Areas        : #{Enum.join(p.weak_areas, ", ")}
    Missing Skills    : #{Enum.join(p.missing_skills, ", ")}

    Projects:
    #{projects_summary}

    --- SPECIALIZATION REQUIREMENTS ---
    Sections to cover    : #{Enum.join(spec.sections, ", ")}
    Core topics          : #{Enum.join(spec.core_topics, ", ")}
    Evaluation focus     : #{Enum.join(spec.evaluation_focus, ", ")}
    Depth trigger topics : #{Enum.join(spec.depth_triggers, ", ")}
    Red flag topics      : #{Enum.join(spec.red_flags, ", ")}

    --- INTERVIEW CONSTRAINTS ---
    Total questions      : #{@tech_budget}   (9 technical/project/behavioral questions)
    Max questions per section: #{@max_per_section}
    Candidate level      : fresher (student / 0-1 yr) — keep questions conceptual and project-focused, not production-ops heavy
    NOTE: Do NOT include a cultural_fit section — it is added automatically as the 10th question.

    --- JOB DESCRIPTION ---
    #{Sanitize.wrap_untrusted(p.jd_text, "job description")}

    Return ONLY this JSON:

    {
      "target_role": "inferred role title",
      "difficulty_curve": "easy_to_moderate",
      "focus_areas": ["top 3-4 areas to focus on given profile vs JD"],
      "avoid_topics": ["topics too advanced for a fresher — skip these"],
      "jd_matched_skills": ["skills from Primary Skills list that the interview MUST cover to verify JD alignment"],
      "sections": [
        {
          "name": "section name",
          "purpose": "why this section for this candidate",
          "topics": ["specific topics to cover in this section"],
          "question_count": #{@max_per_section},
          "priority": 1
        }
      ]
    }

    Rules:
    - Sections must come from: #{Enum.join(spec.sections, ", ")}
    - Topics must be specific to this candidate (use their actual skills/projects)
    - purpose must explain WHY this section matters for THIS candidate
    - priority 1 = most important; order sections by priority
    - jd_matched_skills must be a subset of Primary Skills
    - For project_deep_dive topics: use the EXACT project name as the topic value.
      Each project must appear as its own topic so questions rotate across all projects.
      Do NOT use generic strings like "project architecture" as the topic.
    """
  end

  # ── Deterministic fallback (port of _fallback_plan) ──────────────────────────
  defp fallback_sections(%Profile{} = p, spec) do
    spec.sections
    |> Enum.take(4)
    |> Enum.with_index()
    |> Enum.map(fn {name, i} ->
      %{
        name: name,
        purpose: "Assess candidate on #{String.replace(name, "_", " ")}",
        topics: Enum.take(spec.core_topics, 3),
        question_count: @max_per_section,
        question_types: Map.get(@section_question_types, name, ["technical"]),
        priority: i + 3,
        project_name: nil,
        experience_name: nil,
        github_url: nil
      }
    end)
  end

  # ── Programmatic injection ───────────────────────────────────────────────────
  @project_sections ["project_deep_dive", "portfolio_deep_dive", "resume_verification"]
  @pure_project_sections ["project_deep_dive", "portfolio_deep_dive"]

  defp inject_project_topics(sections, %Profile{projects: []}), do: sections

  defp inject_project_topics(sections, %Profile{} = p) do
    names = p.projects |> Enum.map(& &1.name) |> Enum.reject(&(&1 in [nil, ""]))

    sections =
      Enum.map(sections, fn s ->
        cond do
          s.name in @pure_project_sections -> %{s | topics: names}
          s.name == "resume_verification" -> %{s | topics: Enum.uniq(names ++ s.topics)}
          true -> s
        end
      end)

    # No project/portfolio section at all → add one anchored to the projects.
    if Enum.any?(sections, &(&1.name in @pure_project_sections)) do
      sections
    else
      added =
        if Specializations.it_domain?(p.domain) do
          new_section(
            "project_deep_dive",
            "Dive into the projects the candidate built; verify ownership",
            names,
            scale_count(length(names)),
            1
          )
        else
          new_section(
            "portfolio_deep_dive",
            "Explore the candidate's projects and initiatives",
            names,
            min(length(names), @max_per_section),
            2
          )
        end

      sections ++ [added]
    end
  end

  defp drop_portfolio_if_no_projects(sections, %Profile{projects: projects, portfolio_urls: urls})
       when projects == [] and urls == [] do
    Enum.reject(sections, &(&1.name == "portfolio_deep_dive"))
  end

  defp drop_portfolio_if_no_projects(sections, _p), do: sections

  defp inject_experience(sections, %Profile{work_history: []}), do: sections

  defp inject_experience(sections, %Profile{} = p) do
    labels = p.work_history |> Enum.map(&String.trim("#{&1.role} #{&1.company}")) |> Enum.reject(&(&1 == ""))
    sections = Enum.reject(sections, &(&1.name == "experience_deep_dive"))

    if labels == [] do
      sections
    else
      exp =
        %{
          new_section(
            "experience_deep_dive",
            "Verify professional experience and skills applied in real work",
            labels,
            scale_count(length(labels)),
            2
          )
          | question_types: ["ownership_verify", "technical"]
        }

      sections ++ [exp]
    end
  end

  defp elevate(sections) do
    sections
    |> Enum.map(fn s ->
      cond do
        s.name in @pure_project_sections -> %{s | priority: 1}
        s.name == "experience_deep_dive" -> %{s | priority: 2}
        true -> s
      end
    end)
    |> Enum.sort_by(& &1.priority)
  end

  defp cap_per_section(sections) do
    Enum.map(sections, &%{&1 | question_count: min(&1.question_count, @max_per_section)})
  end

  # Stop once the tech budget is filled, trimming the last section to land exactly on budget.
  defp take_within_budget(sections, budget) do
    {kept, _used} =
      Enum.reduce(sections, {[], 0}, fn s, {acc, used} ->
        remaining = budget - used

        cond do
          remaining <= 0 -> {acc, used}
          s.question_count <= remaining -> {acc ++ [s], used + s.question_count}
          true -> {acc ++ [%{s | question_count: remaining}], budget}
        end
      end)

    kept
  end

  defp cultural_fit_section do
    %{
      name: "cultural_fit",
      purpose: "Assess cultural alignment, emotional intelligence, and interpersonal values",
      topics: ["work values", "collaboration"],
      question_count: 1,
      question_types: ["cultural_fit"],
      priority: 9999,
      project_name: nil,
      experience_name: nil,
      github_url: nil
    }
  end

  # ── helpers ───────────────────────────────────────────────────────────────
  defp new_section(name, purpose, topics, count, priority) do
    %{
      name: name,
      purpose: purpose,
      topics: topics,
      question_count: count,
      question_types: Map.get(@section_question_types, name, ["technical"]),
      priority: priority,
      project_name: nil,
      experience_name: nil,
      github_url: nil
    }
  end

  defp total_count(sections), do: sections |> Enum.map(& &1.question_count) |> Enum.sum()

  # A single project/role gets 2 (two angles); multiple get one each, capped.
  defp scale_count(1), do: 2
  defp scale_count(n), do: min(n, @max_per_section)

  defp to_int(v, _default) when is_integer(v), do: v

  defp to_int(v, default) when is_binary(v),
    do:
      (case Integer.parse(v) do
         {n, _} -> n
         _ -> default
       end)

  defp to_int(_, default), do: default

  @doc false
  def budget, do: @tech_budget
end
