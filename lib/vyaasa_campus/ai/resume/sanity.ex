defmodule VyaasaCampus.AI.Resume.Sanity do
  @moduledoc """
  Two-part sanity score (structural + linguistic) that sums to 100.

  The budget split between the two parts is domain-specific: for trades/vocational
  roles, English-phrasing matters less (linguistic_budget=15); for most domains,
  structural carries more weight (structural_budget=75, linguistic_budget=25).
  Healthcare resumes get a slightly higher structural budget (80).

  Accepts a `DomainConfig` profile so the budgets vary per domain. Pass
  `DomainConfig.default()` when no domain profile is available.

  Penalties are expressed on a 50-pt reference scale and rescaled to the actual
  budget, so the ratio of penalties to each other is preserved across domains.

  Structural checks (deterministic regex):
    - email, phone
    - date-format consistency across parsed Work_Experience dates
    - required section headings present in raw text

  Linguistic checks (from LLM parser's `sanity_hints`):
    - typos, weak verbs, repetitive verbs, informal phrases, grammar issues
  """

  alias VyaasaCampus.AI.Resume.DomainConfig

  @heading_checks [
    {"Experience / Work", ~r/\b(experience|employment|work history)\b/i},
    {"Education", ~r/\b(education|qualification|degree|university|college)\b/i},
    {"Skills", ~r/\b(skills|competencies|technologies|tools)\b/i}
  ]

  @doc "Returns `%{score, status, structural, linguistic}`."
  def score(raw_text, page_count, fresher?, sanity_hints, %DomainConfig{} = profile) do
    structural = structural_score(raw_text, page_count, fresher?, profile)
    linguistic = linguistic_score(sanity_hints || %{}, profile)
    combine(structural, linguistic)
  end

  # ---------------------------------------------------------------------------
  # Structural
  # ---------------------------------------------------------------------------

  def structural_score(raw_text, page_count, fresher?, %DomainConfig{} = profile) do
    budget = profile.structural_budget
    penalties = []
    penalties = check_page_count(penalties, page_count, fresher?, profile, budget)
    penalties = check_email(penalties, raw_text, budget)
    penalties = check_date_consistency(penalties, raw_text, budget)
    penalties = check_phone(penalties, raw_text, budget)
    penalties = check_headings(penalties, raw_text, budget)

    total = Enum.reduce(penalties, 0, fn p, acc -> acc + p.penalty end)
    %{score: max(0, budget - total), max: budget, penalties: Enum.reverse(penalties), total_penalty: total}
  end

  defp check_page_count(penalties, page_count, is_fresher, profile, budget) do
    limit = if is_fresher, do: profile.max_pages_fresher, else: profile.max_pages_senior

    cond do
      is_nil(limit) ->
        penalties

      is_fresher and page_count > limit ->
        p = min(round(budget * 0.33), (page_count - limit) * round(budget * 0.13))
        [%{rule: "Page count", penalty: p, detail: "Fresher resume is #{page_count} pages (max #{limit})."} | penalties]

      not is_fresher and page_count > limit ->
        p = min(round(budget * 0.20), (page_count - limit) * round(budget * 0.07))
        [%{rule: "Page count", penalty: p, detail: "Resume is #{page_count} pages (max #{limit} for this domain)."} | penalties]

      true ->
        penalties
    end
  end

  defp check_email(penalties, text, budget) do
    if Regex.match?(~r/[\w\.\-]+@[\w\.\-]+\.\w+/, text) do
      penalties
    else
      p = round(budget * 0.20)
      [%{rule: "Email missing", penalty: p, detail: "No valid email address detected."} | penalties]
    end
  end

  defp check_date_consistency(penalties, text, budget) do
    numeric? = Regex.match?(~r/\b\d{1,2}\/\d{4}\b/, text)
    textual? = Regex.match?(~r/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{4}\b/i, text)

    if numeric? and textual? do
      p = round(budget * 0.13)
      [%{rule: "Date format inconsistency", penalty: p, detail: "Mixed date formats detected (MM/YYYY and Month YYYY)."} | penalties]
    else
      penalties
    end
  end

  defp check_phone(penalties, text, budget) do
    if Regex.match?(~r/[\+\d][\d\s\-\(\)]{7,}/, text) do
      penalties
    else
      p = round(budget * 0.07)
      [%{rule: "Phone missing", penalty: p, detail: "No phone number detected."} | penalties]
    end
  end

  defp check_headings(penalties, text, budget) do
    Enum.reduce(@heading_checks, penalties, fn {label, pattern}, acc ->
      if Regex.match?(pattern, text) do
        acc
      else
        p = round(budget * 0.04)
        [%{rule: "Section missing: #{label}", penalty: p, detail: "No '#{label}' section heading detected."} | acc]
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Linguistic (from LLM hints, scaled to the domain's linguistic budget)
  # ---------------------------------------------------------------------------

  def linguistic_score(hints, %DomainConfig{} = profile) do
    budget = profile.linguistic_budget
    typos = listify(hints["typos"])
    weak = listify(hints["weak_verbs"])
    rep = listify(hints["repetitive_verbs"])
    informal = listify(hints["informal_phrases"])
    grammar = listify(hints["grammar_issues"])

    # Penalty caps expressed on a 50-pt reference budget, then scaled.
    scale = budget / 50

    penalties =
      []
      |> add_penalty("Typos / Spelling", typos, round(4 * scale), round(20 * scale))
      |> add_penalty("Weak action verbs", weak, round(3 * scale), round(10 * scale))
      |> add_penalty("Repetitive verbs", rep, round(2 * scale), round(8 * scale))
      |> add_penalty("Informal language", informal, round(2 * scale), round(8 * scale))
      |> then(fn p ->
        if profile.penalize_grammar_style do
          add_penalty(p, "Grammar issues", grammar, round(2 * scale), round(8 * scale))
        else
          p
        end
      end)

    total = Enum.reduce(penalties, 0, fn p, acc -> acc + p.penalty end)

    %{
      score: max(0, budget - total),
      max: budget,
      penalties: Enum.reverse(penalties),
      total_penalty: total,
      typos: typos,
      weak_verbs: weak,
      repetitive_verbs: rep,
      informal_phrases: informal,
      grammar_issues: grammar
    }
  end

  defp add_penalty(acc, _rule, [], _per, _cap), do: acc

  defp add_penalty(acc, rule, instances, per, cap) do
    penalty = min(cap, length(instances) * per)
    [%{rule: rule, penalty: penalty, instances: instances} | acc]
  end

  defp listify(nil), do: []
  defp listify(list) when is_list(list), do: list
  defp listify(_), do: []

  # ---------------------------------------------------------------------------
  # Combine
  # ---------------------------------------------------------------------------

  def combine(structural, linguistic) do
    total = structural.score + linguistic.score
    status = if total >= 70, do: "Pass", else: "Needs Improvement"
    %{score: total, status: status, structural: structural, linguistic: linguistic}
  end
end
