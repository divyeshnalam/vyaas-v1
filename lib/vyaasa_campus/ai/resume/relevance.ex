defmodule VyaasaCampus.AI.Resume.Relevance do
  @moduledoc """
  Relevance scoring. Port of relevance.py + jd_similarity.py.

  When a job description is available, uses the three-step LLM approach:
    1. decompose_jd/1   — break JD into discrete requirements with criticality
                          (must / should / nice). One Groq call per JD.
    2. judge_requirements/2 — judge each requirement against the resume blob
                          (met / partial / no + evidence location). One Groq call.
    3. aggregate/2      — deterministic weighted aggregation with criticality and
                          evidence-location multipliers.

  Final score blends three signals (65 / 25 / 10):
    - requirement-by-requirement (LLM)         65%
    - skills-set semantic breadth (Bumblebee)  25%
    - whole-document JD similarity (Bumblebee) 10%

  Signals not available (e.g. embedding errors) are dropped and weights
  renormalised, so the scorer never crashes.

  Fallback: when job_description is blank, uses the original tier-based
  embedding approach (Core / Essential / Appreciated from job_profile text)
  so tenants without a JD still get a meaningful score.
  """

  alias VyaasaCampus.AI.EmbeddingServer
  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.Contexts.JdDecompositions

  require Logger

  @model "openai/gpt-oss-120b"

  # LLM relevance blend weights (must sum to 1.0)
  @w_requirement 0.65
  @w_skills_sem 0.25
  @w_jd_sim 0.10

  # Criticality → base weight
  @crit_weight %{"must" => 1.0, "should" => 0.6, "nice" => 0.3}
  # Status → fraction of requirement's weight earned
  @status_credit %{"met" => 1.0, "partial" => 0.5, "no" => 0.0}
  # Evidence location → multiplier (demonstrated > merely listed)
  @evidence_mult %{
    "experience" => 1.0,
    "projects" => 0.9,
    "skills" => 0.7,
    "education" => 0.6,
    "none" => 0.0
  }

  # Embedding fallback constants
  @tier_final_weights %{core: 0.50, essential: 0.30, appreciated: 0.20}
  @tier_headings %{
    core: "Core Technical Skills",
    essential: "Essential Tools",
    appreciated: "Appreciated Skills & Knowledge"
  }
  @semantic_threshold 0.40
  @jd_sim_min 0.15
  @jd_sim_max 0.75

  # ---------------------------------------------------------------------------
  # Public entry point
  # ---------------------------------------------------------------------------

  @doc """
  Score relevance.

  `job_description` is the raw JD / structured profile text. When non-empty,
  the LLM approach is used. When empty, falls back to embedding tier matching.
  `job_profile` is the tier-headed profile text used only in the fallback path.

  Returns a map with at least: `score`, `matched_skills`, `missing_skills`,
  `jd_similarity`, `jd_similarity_raw`, `tier_scores`.
  """
  def score(parsed, resume_text, job_profile, job_description) do
    if String.trim(to_string(job_description)) != "" do
      llm_score(parsed, resume_text, job_description)
    else
      embedding_score(parsed, resume_text, job_profile, job_description)
    end
  end

  # ---------------------------------------------------------------------------
  # LLM path
  # ---------------------------------------------------------------------------

  defp llm_score(parsed, resume_text, jd_text) do
    skills = parsed["Skills"] || %{}
    candidate = collect_candidate_skills(skills)
    project_skills = collect_project_skills(parsed)
    full_blob = build_blob(parsed, resume_text, candidate)

    requirements = decompose_jd(jd_text)

    {req_score, details, matched_reqs, missing_reqs} =
      if requirements == [] do
        {0, [], [], []}
      else
        judgments = judge_requirements(requirements, parsed)
        agg = aggregate(requirements, judgments)

        matched =
          agg.details
          |> Enum.filter(&(&1.status == "met"))
          |> Enum.map(& &1.requirement)
          |> Enum.take(15)

        missing =
          agg.details
          |> Enum.filter(&(&1.status == "no"))
          |> Enum.map(& &1.requirement)
          |> Enum.take(15)

        {agg.score, agg.details, matched, missing}
      end

    skill_terms =
      requirements
      |> Enum.filter(&(&1["type"] in ["skill", "certification"]))
      |> Enum.map(& &1["text"])

    candidate_embs = embed_unique(candidate ++ project_skills)

    skills_score =
      if skill_terms != [] and map_size(candidate_embs) > 0 do
        skills_semantic_score(skill_terms, candidate_embs, full_blob)
      else
        nil
      end

    {jd_sim, jd_sim_raw} = jd_similarity(full_blob, jd_text, "")

    final = blend(req_score, skills_score, if(jd_sim > 0, do: jd_sim, else: nil))

    %{
      score: final,
      requirement_score: req_score,
      skills_match_score: skills_score,
      jd_similarity: jd_sim,
      jd_similarity_raw: Float.round(jd_sim_raw, 4),
      tier_scores: %{},
      matched_skills: matched_reqs,
      missing_skills: missing_reqs,
      requirement_details: details,
      num_requirements: length(requirements)
    }
  end

  defp blend(req_score, skills_score, jd_sim_score) do
    parts =
      [{req_score, @w_requirement}]
      |> then(fn p -> if skills_score, do: [{skills_score, @w_skills_sem} | p], else: p end)
      |> then(fn p -> if jd_sim_score, do: [{jd_sim_score, @w_jd_sim} | p], else: p end)

    total_w = Enum.reduce(parts, 0.0, fn {_, w}, acc -> acc + w end)
    raw = Enum.reduce(parts, 0.0, fn {s, w}, acc -> acc + s * w end)
    if total_w > 0, do: round(raw / total_w), else: req_score
  end

  # ---------------------------------------------------------------------------
  # Step 1 — Decompose JD
  # ---------------------------------------------------------------------------

  # Decompose the JD into requirements, reusing a stored decomposition when one
  # exists for this exact JD (see VyaasaCampus.Contexts.JdDecompositions). This
  # freezes the requirement rubric so identical inputs always score identically;
  # the LLM only runs on a cache miss.
  defp decompose_jd(jd_text) do
    JdDecompositions.get_or_decompose(jd_text, &decompose_jd_llm/1, model: @model)
  end

  @doc """
  Decompose `jd_text` and persist it to the shared cache, tagging the row with
  `source` (e.g. the JD file/role name). Reuses an existing entry on a hit.
  Used by the `jd.seed` task to pre-warm a JD library. Returns the requirements.
  """
  def cache_jd(jd_text, source \\ nil) do
    JdDecompositions.get_or_decompose(jd_text, &decompose_jd_llm/1, model: @model, source: source)
  end

  defp decompose_jd_llm(jd_text) do
    system = "You convert a job description into a structured list of discrete, atomic requirements. Output strictly valid JSON only."

    prompt = """
    Break this job description into a SHORT list of CONSOLIDATED requirements (NOT an
    atomic skill-by-skill list). Output ONLY JSON:
    {"requirements": [
      {"text": "short requirement", "criticality": "must|should|nice", "type": "skill|experience|education|certification|responsibility"}
    ]}

    Consolidation rules (apply to ANY domain — tech, healthcare, finance, law, trades, etc.):
    - Merge ALTERNATIVES joined by "or" / "such as" / "e.g." into ONE requirement.
    - GROUP closely related items into one requirement instead of listing each separately.
    - AIM FOR 10–20 requirements TOTAL. Never produce a long flat list of individual tools/skills.

    Criticality:
    - "must" for required/mandatory/'X years'; "should" for important; "nice" for
      preferred/bonus/'a plus'/'familiarity with'/long optional tool lists.

    Other rules:
    - Do NOT invent requirements not in the text.
    - Ignore boilerplate (company blurb, EEO statements, perks).

    JOB DESCRIPTION:
    \"\"\"
    #{String.slice(jd_text, 0, 8000)}
    \"\"\"
    """

    case GroqClient.chat(
           [
             %{role: "system", content: system},
             %{role: "user", content: prompt}
           ],
           model: @model,
           temperature: 0.0,
           max_tokens: 2000,
           response_format: %{"type" => "json_object"},
           reasoning_effort: "low",
           timeout: 60_000
         ) do
      {:ok, %{"content" => raw}} ->
        case raw |> GroqClient.strip_reasoning() |> GroqClient.extract_json() do
          {:ok, %{"requirements" => reqs}} when is_list(reqs) ->
            reqs
            |> Enum.filter(fn r -> is_map(r) and is_binary(r["text"]) and r["text"] != "" end)
            |> Enum.map(fn r ->
              %{
                "text" => String.trim(r["text"]),
                "criticality" =>
                  if(r["criticality"] in ["must", "should", "nice"],
                    do: r["criticality"],
                    else: "should"
                  ),
                "type" => r["type"] || "skill"
              }
            end)

          _ ->
            Logger.warning("RESUME_REL | decompose_jd: bad JSON shape")
            []
        end

      {:error, reason} ->
        Logger.warning("RESUME_REL | decompose_jd failed: #{inspect(reason)}")
        []
    end
  end

  # ---------------------------------------------------------------------------
  # Step 2 — Judge requirements
  # ---------------------------------------------------------------------------

  defp judge_requirements(requirements, parsed) do
    blob = resume_blob(parsed)
    req_lines = Enum.with_index(requirements, 0) |> Enum.map(fn {r, i} -> "#{i}. #{r["text"]}" end) |> Enum.join("\n")

    system = "You assess whether a resume satisfies each given requirement. Report facts and evidence only — never a numeric score. Output strictly valid JSON only."

    prompt = """
    For EACH numbered requirement, decide whether the RESUME satisfies it.
    Output ONLY JSON: {"judgments": [
      {"index": 0, "status": "met|partial|no", "evidence_location": "experience|projects|skills|education|none", "evidence": "short quote or phrase from the resume, or empty"}
    ]}

    Rules:
    - "met": clearly demonstrated OR clearly listed in skills/competencies.
    - "partial": only related/adjacent/transferable, or a weak/indirect mention.
    - "no": absent.
    - For a SKILL requirement, a clear listing counts as "met" — do NOT downgrade to
      "partial" just because it appears in a skills list rather than in experience.
    - For an EXPERIENCE requirement, prefer evidence in experience/projects; a bare
      skills mention is at most "partial".
    - evidence_location: where the proof is (experience|projects|skills|education|none).
    - evidence: copy a short supporting phrase (<=15 words) or "".
    - One judgment per requirement, same index.

    REQUIREMENTS:
    #{req_lines}

    RESUME:
    \"\"\"
    #{String.slice(blob, 0, 10_000)}
    \"\"\"
    """

    case GroqClient.chat(
           [
             %{role: "system", content: system},
             %{role: "user", content: prompt}
           ],
           model: @model,
           temperature: 0.0,
           max_tokens: 3000,
           response_format: %{"type" => "json_object"},
           reasoning_effort: "low",
           timeout: 90_000
         ) do
      {:ok, %{"content" => raw}} ->
        case raw |> GroqClient.strip_reasoning() |> GroqClient.extract_json() do
          {:ok, %{"judgments" => js}} when is_list(js) ->
            by_idx =
              js
              |> Enum.filter(&(is_map(&1) and is_integer(&1["index"])))
              |> Map.new(&{&1["index"], &1})

            Enum.with_index(requirements, 0)
            |> Enum.map(fn {_req, i} ->
              j = Map.get(by_idx, i, %{})
              status = if j["status"] in ["met", "partial", "no"], do: j["status"], else: "no"
              loc = if j["evidence_location"] in Map.keys(@evidence_mult), do: j["evidence_location"], else: "none"
              %{status: status, evidence_location: loc, evidence: to_string(j["evidence"] || "") |> String.slice(0, 160)}
            end)

          _ ->
            Logger.warning("RESUME_REL | judge_requirements: bad JSON shape")
            Enum.map(requirements, fn _ -> %{status: "no", evidence_location: "none", evidence: ""} end)
        end

      {:error, reason} ->
        Logger.warning("RESUME_REL | judge_requirements failed: #{inspect(reason)}")
        Enum.map(requirements, fn _ -> %{status: "no", evidence_location: "none", evidence: ""} end)
    end
  end

  # ---------------------------------------------------------------------------
  # Step 3 — Deterministic aggregation
  # ---------------------------------------------------------------------------

  def aggregate(requirements, judgments) do
    if requirements == [] do
      %{score: 0, details: [], matched: 0, total: 0}
    else
      {core_w, core_earned, nice_w, nice_earned, details, matched} =
        Enum.zip(requirements, judgments)
        |> Enum.reduce({0.0, 0.0, 0.0, 0.0, [], 0}, fn {req, j},
                                                         {cw, ce, nw, ne, dets, m} ->
          crit = req["criticality"] || "should"
          rtype = req["type"] || "skill"
          base_w = Map.get(@crit_weight, crit, 0.6)
          credit = Map.get(@status_credit, j.status, 0.0)
          ev_mult = Map.get(@evidence_mult, j.evidence_location, 0.0)

          eff =
            if credit > 0 do
              if rtype in ["skill", "certification"] and j.status == "met" do
                credit
              else
                credit * if(ev_mult > 0, do: ev_mult, else: 0.7)
              end
            else
              0.0
            end

          new_m = if j.status == "met", do: m + 1, else: m

          detail = %{
            requirement: req["text"],
            criticality: crit,
            status: j.status,
            evidence_location: j.evidence_location,
            evidence: j.evidence,
            weight: Float.round(base_w, 2),
            earned: Float.round(base_w * eff, 3)
          }

          if crit == "nice" do
            {cw, ce, nw + base_w, ne + base_w * eff, [detail | dets], new_m}
          else
            {cw + base_w, ce + base_w * eff, nw, ne, [detail | dets], new_m}
          end
        end)

      core_score = if core_w > 0, do: core_earned / core_w, else: 0.0
      nice_frac = if nice_w > 0, do: nice_earned / nice_w, else: 0.0
      bonus = nice_frac * 10.0
      base = if core_w > 0, do: core_score * 100, else: nice_frac * 100
      score = min(100, round(base + if(core_w > 0, do: bonus, else: 0.0)))

      %{
        score: score,
        details: Enum.reverse(details),
        matched: matched,
        total: length(requirements)
      }
    end
  end

  # ---------------------------------------------------------------------------
  # Resume blob (structured, for LLM judge)
  # ---------------------------------------------------------------------------

  defp resume_blob(parsed) do
    skills = parsed["Skills"] || %{}
    tech = (skills["Technical"] || []) |> Enum.map(&to_string/1) |> Enum.join(", ")
    soft = (skills["Non_Technical"] || skills["Non-Technical"] || []) |> Enum.map(&to_string/1) |> Enum.join(", ")

    exp_parts =
      (parsed["Work_Experience"] || [])
      |> Enum.map(fn j ->
        resps =
          case j["Responsibilities"] do
            r when is_list(r) -> Enum.join(r, "; ")
            r when is_binary(r) -> r
            _ -> ""
          end

        "EXPERIENCE: #{j["Job_Title"] || ""} — #{resps}"
      end)

    proj_parts =
      (parsed["Projects"] || [])
      |> Enum.map(fn p ->
        desc =
          case p["Description"] do
            d when is_list(d) -> Enum.join(d, "; ")
            d when is_binary(d) -> d
            _ -> ""
          end

        techs = (p["Technologies_Used"] || []) |> Enum.join(", ")
        "PROJECT: #{p["Project_Name"] || ""} — #{desc} [#{techs}]"
      end)

    edu_parts =
      (parsed["Education"] || [])
      |> Enum.map(fn e -> "EDUCATION: #{e["Degree"] || ""} #{e["Specialization"] || ""}" end)

    certs = (parsed["Certifications"] || []) |> Enum.join(", ")

    (["SKILLS: #{tech}, #{soft}"] ++ exp_parts ++ proj_parts ++ edu_parts ++ ["CERTIFICATIONS: #{certs}"])
    |> Enum.reject(&(String.trim(&1) =~ ~r/^(SKILLS|CERTIFICATIONS): *,? *$/))
    |> Enum.join("\n")
  end

  # ---------------------------------------------------------------------------
  # Skills semantic score (Bumblebee, for the 25% signal)
  # ---------------------------------------------------------------------------

  defp skills_semantic_score(skill_terms, candidate_embs, full_blob) do
    blob_lower = String.downcase(full_blob)
    blob_norm = normalise_for_regex(blob_lower)
    candidate_pool = Map.values(candidate_embs)

    req_embs = embed_unique(skill_terms)

    if map_size(req_embs) == 0 do
      nil
    else
      matched =
        Enum.count(skill_terms, fn term ->
          contextual_hit?(term, blob_lower, blob_norm) or sem_hit?(term, req_embs, candidate_pool)
        end)

      round(matched / length(skill_terms) * 100)
    end
  end

  # ---------------------------------------------------------------------------
  # Embedding fallback path (original tier-based approach)
  # ---------------------------------------------------------------------------

  defp embedding_score(parsed, resume_text, job_profile, job_description) do
    skills = parsed["Skills"] || %{}
    candidate = collect_candidate_skills(skills)
    full_blob = build_blob(parsed, resume_text, candidate)
    candidate_embs = embed_unique(candidate ++ collect_project_skills(parsed))

    {tier_scores, all_required, all_matched} =
      Enum.reduce(@tier_headings, {%{}, MapSet.new(), MapSet.new()}, fn {tier_key, heading},
                                                                        {acc, req_acc, matched_acc} ->
        required = extract_section_skills(job_profile, heading)
        req_embs = embed_unique(required)

        sem_rate = semantic_match_rate(required, req_embs, candidate_embs)
        ctx_rate = contextual_match_rate(required, full_blob)

        raw_match = sem_rate * 0.60 + ctx_rate * 0.40
        tier_raw = if raw_match > 0, do: Float.round(100 * :math.pow(raw_match, 0.7), 1), else: 0.0

        matched_here = matched_required(required, req_embs, candidate_embs, full_blob)

        tier_data = %{
          heading: heading,
          required_count: length(required),
          matched_count: length(matched_here),
          semantic_rate: Float.round(sem_rate * 100, 1),
          contextual_rate: Float.round(ctx_rate * 100, 1),
          tier_score: tier_raw
        }

        {Map.put(acc, tier_key, tier_data),
         MapSet.union(req_acc, MapSet.new(required)),
         MapSet.union(matched_acc, MapSet.new(matched_here))}
      end)

    tier_weighted =
      Enum.reduce(@tier_final_weights, 0.0, fn {k, w}, acc ->
        acc + Map.get(tier_scores, k, %{tier_score: 0.0}).tier_score * w
      end)

    {jd_sim, jd_sim_raw} = jd_similarity(full_blob, job_description, job_profile)
    final = round(tier_weighted * 0.85 + jd_sim * 0.15)
    final = max(0, min(100, final))

    missing = MapSet.difference(all_required, all_matched) |> MapSet.to_list() |> Enum.sort() |> Enum.take(15)
    matched = all_matched |> MapSet.to_list() |> Enum.sort() |> Enum.take(15)

    %{
      score: final,
      requirement_score: nil,
      skills_match_score: nil,
      jd_similarity: jd_sim,
      jd_similarity_raw: Float.round(jd_sim_raw, 4),
      tier_scores: tier_scores,
      matched_skills: matched,
      missing_skills: missing,
      requirement_details: [],
      num_requirements: 0
    }
  end

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  defp collect_candidate_skills(skills) do
    tech = (skills["Technical"] || []) |> filter_lower()
    soft = (skills["Non_Technical"] || skills["Non-Technical"] || []) |> filter_lower()
    tech ++ soft
  end

  defp collect_project_skills(parsed) do
    (parsed["Projects"] || [])
    |> Enum.flat_map(fn p -> p["Technologies_Used"] || [] end)
    |> filter_lower()
  end

  defp build_blob(parsed, resume_text, candidate_skills) do
    exp_text =
      (parsed["Work_Experience"] || [])
      |> Enum.map(fn j ->
        resps =
          case j["Responsibilities"] do
            r when is_list(r) -> Enum.join(r, " ")
            r when is_binary(r) -> r
            _ -> ""
          end

        resps <> " " <> to_string(j["Job_Title"] || "")
      end)
      |> Enum.join(" ")

    proj_text =
      (parsed["Projects"] || [])
      |> Enum.map(fn p ->
        desc =
          case p["Description"] do
            d when is_list(d) -> Enum.join(d, " ")
            d when is_binary(d) -> d
            _ -> ""
          end

        techs = (p["Technologies_Used"] || []) |> Enum.join(" ")
        desc <> " " <> techs
      end)
      |> Enum.join(" ")

    [resume_text, exp_text, proj_text, Enum.join(candidate_skills, " ")]
    |> Enum.join(" ")
  end

  defp embed_unique([]), do: %{}

  defp embed_unique(strings) do
    strings
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn s, acc ->
      case EmbeddingServer.embed(s) do
        {:ok, vec} -> Map.put(acc, s, vec)
        {:error, _} -> acc
      end
    end)
  end

  defp semantic_match_rate([], _, _), do: 0.0
  defp semantic_match_rate(_, _, embs) when map_size(embs) == 0, do: 0.0

  defp semantic_match_rate(required, req_embs, candidate_embs) do
    pool = Map.values(candidate_embs)

    matched =
      Enum.count(required, fn r ->
        case Map.get(req_embs, r) do
          nil -> false
          v -> EmbeddingServer.max_similarity(v, pool) >= @semantic_threshold
        end
      end)

    matched / length(required)
  end

  defp contextual_match_rate([], _), do: 0.0

  defp contextual_match_rate(required, blob) do
    blob_lower = String.downcase(blob)
    blob_norm = normalise_for_regex(blob_lower)
    found = Enum.count(required, &contextual_hit?(&1, blob_lower, blob_norm))
    found / length(required)
  end

  defp contextual_hit?(skill, blob_lower, blob_norm) do
    pattern = ~r/\b#{Regex.escape(skill)}s?\b/

    if Regex.match?(pattern, blob_lower) do
      true
    else
      norm = normalise_for_regex(skill)
      norm != "" and Regex.match?(~r/\b#{Regex.escape(norm)}s?\b/, blob_norm)
    end
  end

  defp matched_required(required, req_embs, candidate_embs, blob) do
    blob_lower = String.downcase(blob)
    blob_norm = normalise_for_regex(blob_lower)
    candidate_pool = Map.values(candidate_embs)

    Enum.filter(required, fn r ->
      contextual_hit?(r, blob_lower, blob_norm) or sem_hit?(r, req_embs, candidate_pool)
    end)
  end

  defp sem_hit?(_, _, []), do: false

  defp sem_hit?(r, req_embs, candidate_pool) do
    case Map.get(req_embs, r) do
      nil -> false
      v -> EmbeddingServer.max_similarity(v, candidate_pool) >= @semantic_threshold
    end
  end

  defp jd_similarity(blob, jd, profile) do
    combined = String.slice(jd <> "\n" <> profile, 0, 3000)
    blob_truncated = String.slice(blob, 0, 3000)

    if String.trim(combined) == "" or String.trim(blob_truncated) == "" do
      {0.0, 0.0}
    else
      with {:ok, v1} <- EmbeddingServer.embed(blob_truncated),
           {:ok, v2} <- EmbeddingServer.embed(combined) do
        raw = EmbeddingServer.cosine_similarity(v1, v2)
        clipped = max(@jd_sim_min, min(@jd_sim_max, raw))
        scaled = (clipped - @jd_sim_min) / (@jd_sim_max - @jd_sim_min) * 100
        {Float.round(scaled, 1), raw}
      else
        _ -> {0.0, 0.0}
      end
    end
  end

  @doc false
  def extract_section_skills(profile_text, heading)
      when is_binary(profile_text) and is_binary(heading) do
    pattern = ~r/\*\*#{Regex.escape(heading)}[:\*]*\*\*(.*?)(?=\n\n|\n\*\*|\z)/is

    case Regex.run(pattern, profile_text, capture: :all_but_first) do
      [raw] ->
        raw
        |> String.replace(~r/\*+/, "")
        |> String.split(~r/[,\n]/)
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.downcase/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  def extract_section_skills(_, _), do: []

  defp normalise_for_regex(s) do
    s
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9 ]+/, " ")
    |> String.trim()
  end

  defp filter_lower(list) when is_list(list) do
    list
    |> Enum.map(fn s -> s |> to_string() |> String.downcase() end)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp filter_lower(_), do: []
end
