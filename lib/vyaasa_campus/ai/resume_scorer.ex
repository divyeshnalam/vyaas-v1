defmodule VyaasaCampus.AI.ResumeScorer do
  @moduledoc """
  Native Elixir resume scoring pipeline.

  Replaces the Python LangGraph pipeline (`/score-resume/` FastAPI endpoint).
  All inference runs in-process: file extraction via shell-out to `pdftotext`,
  parsing via Groq LLM, semantic matching via Bumblebee `Nx.Serving`.

  Returns a map matching the shape `AtsUpload.build_processing_result_attrs/1`
  expects, so no callback-controller / context changes are needed downstream.

  Pipeline:

      extract → llm_validate_and_parse → completeness → relevance → sanity → aggregate
  """

  alias VyaasaCampus.AI.Resume.{Completeness, DomainConfig, Experience, Extractor, LlmParser, Relevance, Sanity}
  alias VyaasaCampus.Contexts.ResumeScoreCache

  require Logger

  # Bump to invalidate all cached scores after a scoring-logic change.
  @scorer_version "1"

  @doc """
  Run the pipeline on a resume binary.

  ## Required
    * `binary` — raw file bytes (PDF / DOCX / TXT)
    * `filename` — used to detect format

  ## Options
    * `:job_description` — raw JD text (default `""`)
    * `:job_profile` — structured profile with `**Core Technical Skills:**` headings (default `""`)
    * `:desired_role` — short role label (default `""`)

  Returns:
    * `{:ok, service_response}` — same shape Python sent over the callback
    * `{:error, reason}` — extractor or LLM failure
  """
  def run(binary, filename, opts \\ []) when is_binary(binary) and is_binary(filename) do
    job_description = Keyword.get(opts, :job_description, "")
    job_profile = Keyword.get(opts, :job_profile, "")

    # Freeze the result per (resume bytes + role inputs): identical uploads always
    # return the identical score, sidestepping residual LLM non-determinism.
    ResumeScoreCache.get_or_score(
      [binary, job_profile, job_description],
      @scorer_version,
      fn -> run_uncached(binary, filename, job_description, job_profile) end
    )
  end

  defp run_uncached(binary, filename, job_description, job_profile) do
    VyaasaCampus.AI.Tracing.span("resume.analyze", fn ->
      do_run_uncached(binary, filename, job_description, job_profile)
    end)
  end

  defp do_run_uncached(binary, filename, job_description, job_profile) do
    with {:ok, %{text: text, links: links, page_count: pages}} <-
           Extractor.extract(binary, filename),
         :ok <- ensure_text(text),
         {:ok, %{is_resume: true, parsed: parsed, sanity_hints: hints, inferred_domain_family: domain_family}} <-
           LlmParser.validate_and_parse(text) do
      build_response(parsed, hints, text, links, pages, job_description, job_profile, domain_family)
    else
      {:ok, %{is_resume: false, rejection_reason: reason}} ->
        {:error, "Not a valid resume: #{reason}"}

      {:error, reason} ->
        Logger.error("RESUME_SCORER | failed | reason=#{inspect(reason)}")
        {:error, to_string(reason)}
    end
  end

  @doc "Same as `run/3` but reads the file from disk first."
  def run_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, bin} -> run(bin, path, opts)
      {:error, reason} -> {:error, "Failed to read #{path}: #{inspect(reason)}"}
    end
  end

  # ----------------------------------------------------------------------
  # Response builder
  # ----------------------------------------------------------------------

  defp build_response(parsed, hints, raw_text, links, pages, jd, profile_text, domain_family) do
    exp_years = Experience.calculate(parsed["Work_Experience"] || [])
    fresher? = Experience.fresher?(exp_years)

    domain_profile =
      domain_family
      |> DomainConfig.get_profile()
      |> DomainConfig.with_seniority(fresher?)

    completeness = Completeness.score(parsed, links, domain_profile)

    enriched_parsed =
      parsed
      |> Map.put("LinkedIn_Profile", completeness.corrected_links["linkedin"])
      |> Map.put("GitHub_Profile", completeness.corrected_links["github"])
      |> Map.put("Total_Experience", Experience.format_experience(exp_years))
      |> rekey_skills_for_legacy_consumers()

    relevance = Relevance.score(enriched_parsed, raw_text, profile_text, jd)
    sanity = Sanity.score(raw_text, pages, fresher?, hints, domain_profile)

    final_score = compute_final_score(completeness.score, relevance.score, sanity.score)

    {:ok,
     %{
       "final_score" => final_score,
       "completeness" => to_string_keys_completeness(completeness),
       "relevance" => to_string_keys_relevance(relevance),
       "sanity_check" => to_string_keys_sanity(sanity),
       "groq_data" => enriched_parsed
     }}
  end

  defp ensure_text(text) do
    if String.trim(text) == "" do
      {:error, "Could not extract readable text from the file."}
    else
      :ok
    end
  end

  # `extract_skills_from_groq/1` in AtsUpload reads the legacy "Non-Technical"
  # key. The LLM normalises to "Non_Technical" — write both so downstream code
  # keeps working without modification.
  defp rekey_skills_for_legacy_consumers(%{"Skills" => skills} = parsed) when is_map(skills) do
    skills =
      cond do
        Map.has_key?(skills, "Non_Technical") and not Map.has_key?(skills, "Non-Technical") ->
          Map.put(skills, "Non-Technical", skills["Non_Technical"])

        true ->
          skills
      end

    Map.put(parsed, "Skills", skills)
  end

  defp rekey_skills_for_legacy_consumers(parsed), do: parsed

  # Weighted final: 35% completeness, 50% relevance, 15% sanity (matches Python engine.py).
  defp compute_final_score(c, r, s), do: round(c * 0.35 + r * 0.50 + s * 0.15)

  # ----------------------------------------------------------------------
  # Shape conversion (atom/list keys → string keys for cross-language compat)
  # ----------------------------------------------------------------------

  defp to_string_keys_completeness(c) do
    %{
      "score" => c.score,
      "raw_score" => c.raw_score,
      "max_raw" => c.max_raw,
      "feedback" => c.feedback,
      "sections" => atomic_keys_to_strings(c.sections),
      "corrected_links" => c.corrected_links,
      "other_links" => c.corrected_links["other"] || []
    }
  end

  defp to_string_keys_relevance(r) do
    tier_scores =
      (r.tier_scores || %{})
      |> Enum.map(fn {k, v} ->
        key = if is_atom(k), do: Atom.to_string(k), else: k
        {key, atomic_keys_to_strings(v)}
      end)
      |> Map.new()

    %{
      "score" => r.score,
      "requirement_score" => r[:requirement_score],
      "skills_match_score" => r[:skills_match_score],
      "num_requirements" => r[:num_requirements] || 0,
      "jd_similarity" => r.jd_similarity,
      "jd_similarity_raw" => r.jd_similarity_raw,
      "tier_scores" => tier_scores,
      "matched_skills" => r.matched_skills,
      "missing_skills" => r.missing_skills,
      "requirement_details" => r[:requirement_details] || [],
      "details" => %{
        "matching_keywords" => r.matched_skills,
        "missing_keywords" => r.missing_skills,
        "justification" => relevance_justification(r)
      }
    }
  end

  defp relevance_justification(r) do
    "Tier matches — Core: #{tier_label(r.tier_scores, :core)}, " <>
      "Essential: #{tier_label(r.tier_scores, :essential)}, " <>
      "Appreciated: #{tier_label(r.tier_scores, :appreciated)}. " <>
      "Overall JD similarity: #{r.jd_similarity}%."
  end

  defp tier_label(tiers, key) do
    case Map.get(tiers, key) do
      %{matched_count: m, required_count: req} -> "#{m}/#{req}"
      _ -> "0/0"
    end
  end

  defp to_string_keys_sanity(s) do
    structural = s.structural
    linguistic = s.linguistic

    %{
      "score" => s.score,
      "final_sanity_score" => s.score,
      "final_score" => s.score,
      "status" => s.status,
      "total_penalty" => structural.total_penalty + linguistic.total_penalty,
      "breakdown" => sanity_breakdown(structural, linguistic),
      "structural_report" => %{
        "score" => structural.score,
        "max" => structural[:max] || 75,
        "total_penalty" => structural.total_penalty,
        "findings" => Enum.map(structural.penalties, &penalty_to_map/1)
      },
      "linguistic_report" => %{
        "score" => linguistic.score,
        "max" => linguistic.max,
        "total_penalty" => linguistic.total_penalty,
        "feedback" => Enum.map(linguistic.penalties, &penalty_to_map/1),
        "typos" => linguistic.typos,
        "weak_verbs" => linguistic.weak_verbs,
        "repetitive_verbs" => linguistic.repetitive_verbs,
        "informal_phrases" => linguistic.informal_phrases,
        "grammar_issues" => linguistic.grammar_issues
      }
    }
  end

  # Map our penalty buckets onto the legacy 5-category breakdown shape so the
  # existing `extract_sanity_issues/1` flatten logic in AtsUpload keeps working.
  defp sanity_breakdown(structural, linguistic) do
    professional = linguistic.weak_verbs ++ linguistic.informal_phrases ++ linguistic.grammar_issues

    %{
      "professional_language" => bucket(professional),
      "spelling" => bucket(linguistic.typos),
      "consistent_formatting" => bucket_from_structural(structural, "Section missing"),
      "consistent_date_format" => bucket_from_structural(structural, "Date format"),
      "page_count" => bucket_from_structural(structural, "Page count")
    }
  end

  defp bucket(items) when is_list(items) do
    %{"score" => length(items), "issues" => Enum.map(items, &to_string/1)}
  end

  defp bucket_from_structural(structural, prefix) do
    matching =
      Enum.filter(structural.penalties, fn p ->
        is_binary(p.rule) and String.contains?(p.rule, prefix)
      end)

    issues = Enum.map(matching, & &1.detail)
    %{"score" => length(issues), "issues" => issues}
  end

  defp penalty_to_map(p) do
    base = %{
      "rule" => p.rule,
      "penalty" => p.penalty
    }

    case p do
      %{detail: d} when is_binary(d) -> Map.put(base, "detail", d)
      %{instances: i} when is_list(i) -> Map.put(base, "instances", i)
      _ -> base
    end
  end

  defp atomic_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), atomic_keys_to_strings(v)}
      {k, v} -> {k, atomic_keys_to_strings(v)}
    end)
  end

  defp atomic_keys_to_strings(other), do: other
end