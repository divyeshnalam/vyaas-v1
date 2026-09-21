defmodule VyaasaCampus.AI.Resume.Completeness do
  @moduledoc """
  Domain-aware completeness scoring on a 0–100 scale. Port of completeness.py.

  Section weights and requirements come from a `DomainConfig` profile, so a
  healthcare student is not penalised for lacking a Portfolio section, and a
  tech student is not graded on clinical certifications.

  Per-section credit (three levels, not binary):
    absent        → 0.0
    present, thin → 0.5  (single-item list, short string, only email OR phone)
    present, rich → 1.0  (multiple items, long text, email AND phone)

  Skills section: proportional to `profile.min_skill_count`.

  Returns `%{score, raw_score, max_raw, sections, feedback, corrected_links}`.
  `corrected_links` carries the best LinkedIn/GitHub/other URLs recovered from
  the document's hyperlinks — used by ResumeScorer to enrich the parsed map.
  """

  alias VyaasaCampus.AI.Resume.DomainConfig
  alias VyaasaCampus.AI.Resume.DomainConfig.Section

  @doc """
  Score completeness given a parsed resume, extracted hyperlink list, and domain
  profile.  `all_links` is the list of `%{uri: ...}` maps from `Extractor`.
  """
  def score(parsed, all_links, %DomainConfig{} = profile) when is_map(parsed) and is_list(all_links) do
    uris = Enum.map(all_links, &(&1[:uri] || &1["uri"] || ""))
    {linkedin, github, other} = correct_links(parsed, uris)
    corrected = %{"linkedin" => linkedin, "github" => github, "other" => other}

    parsed_enriched = Map.merge(parsed, %{"_linkedin" => linkedin, "_github" => github})

    total_w = profile.sections |> Enum.map(& &1.weight) |> Enum.sum()

    {earned, sections, feedback} =
      Enum.reduce(profile.sections, {0.0, %{}, []}, fn sec, {earn_acc, secs, fb} ->
        {credit, fb_entry} = section_credit(sec, parsed_enriched, profile)
        new_earn = earn_acc + credit * sec.weight

        section_data = %{
          earned: Float.round(credit * sec.weight, 1),
          max: sec.weight,
          credit: Float.round(credit, 2)
        }

        new_secs = Map.put(secs, sec.key, section_data)
        new_fb = if fb_entry, do: [fb_entry | fb], else: fb
        {new_earn, new_secs, new_fb}
      end)

    final = if total_w > 0, do: min(100, round(earned * 100 / total_w)), else: 0

    %{
      score: final,
      raw_score: Float.round(earned, 2),
      max_raw: total_w,
      sections: sections,
      feedback: Enum.reverse(feedback),
      corrected_links: corrected
    }
  end

  # ---------------------------------------------------------------------------
  # Section credit
  # ---------------------------------------------------------------------------

  # Skills: proportional to min_skill_count
  defp section_credit(%Section{key: "Skills"} = sec, parsed, profile) do
    skills = parsed["Skills"] || %{}
    tech = skills["Technical"] || []
    soft = skills["Non_Technical"] || skills["Non-Technical"] || []
    n = Enum.count(tech ++ soft, &present?/1)

    credit =
      if profile.min_skill_count > 0,
        do: min(1.0, n / profile.min_skill_count),
        else: if(n > 0, do: 1.0, else: 0.0)

    fb =
      cond do
        n == 0 and sec.required -> "Missing required section: #{sec.label}"
        n == 0 -> nil
        credit < 1.0 -> "#{sec.label}: only #{n} found — aim for #{profile.min_skill_count}+."
        true -> nil
      end

    {credit, fb}
  end

  # Contact: present = email OR phone; rich = email AND phone
  defp section_credit(%Section{key: "contact"} = sec, parsed, _profile) do
    has_email = present?(parsed["Email_Address"])
    has_phone = present?(parsed["Contact_Number"])
    present = has_email or has_phone
    rich = has_email and has_phone
    credit_and_feedback(sec, present, rich)
  end

  # Portfolio: any GitHub/LinkedIn/Portfolio URL
  defp section_credit(%Section{key: "Portfolio"} = sec, parsed, _profile) do
    has =
      present?(parsed["_github"]) or
        present?(parsed["_linkedin"]) or
        present?(parsed["GitHub_Profile"]) or
        present?(parsed["Portfolio"])

    fb =
      if not has and sec.required,
        do: "Missing required section: #{sec.label}",
        else: if(not has, do: "#{sec.label}: no GitHub or portfolio URL found.", else: nil)

    {if(has, do: 1.0, else: 0.0), fb}
  end

  # All other sections: generic thin/rich detection
  defp section_credit(%Section{} = sec, parsed, _profile) do
    {present, rich} = field_has(parsed[sec.key])
    credit_and_feedback(sec, present, rich)
  end

  defp credit_and_feedback(sec, present, rich) do
    credit =
      cond do
        rich -> 1.0
        present -> 0.5
        true -> 0.0
      end

    fb =
      cond do
        not present and sec.required -> "Missing required section: #{sec.label}"
        not present -> nil
        not rich -> "#{sec.label}: present but thin — add more detail."
        true -> nil
      end

    {credit, fb}
  end

  # ---------------------------------------------------------------------------
  # Thin/rich detection per field shape
  # ---------------------------------------------------------------------------

  defp field_has(nil), do: {false, false}
  defp field_has(""), do: {false, false}

  defp field_has(s) when is_binary(s) do
    t = String.trim(s)
    {t != "", String.length(t) > 40}
  end

  defp field_has(list) when is_list(list) do
    non_empty = Enum.filter(list, fn
      m when is_map(m) -> map_size(m) > 0
      s -> present?(s)
    end)
    n = length(non_empty)
    {n > 0, n >= 2}
  end

  defp field_has(map) when is_map(map) do
    n =
      map
      |> Map.values()
      |> Enum.filter(&is_list/1)
      |> Enum.map(&length/1)
      |> Enum.sum()

    {n > 0, n >= 2}
  end

  defp field_has(_), do: {false, false}

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(s) when is_binary(s), do: String.trim(s) != ""
  defp present?(_), do: false

  # ---------------------------------------------------------------------------
  # Link recovery (unchanged from prior version — used by ResumeScorer)
  # ---------------------------------------------------------------------------

  defp correct_links(parsed, uris) do
    linkedin =
      case parsed["LinkedIn_Profile"] do
        l when is_binary(l) and l != "" ->
          if String.contains?(l, ".com"), do: l, else: find_first(uris, "linkedin.com/in/")
        _ ->
          find_first(uris, "linkedin.com/in/")
      end

    github =
      case parsed["GitHub_Profile"] do
        g when is_binary(g) and g != "" ->
          if String.contains?(g, ".com"), do: g, else: find_first_github(uris)
        _ ->
          find_first_github(uris)
      end

    other =
      uris
      |> Enum.reject(&(&1 == linkedin or &1 == github or &1 == ""))
      |> Enum.filter(
        &Regex.match?(~r/behance|portfolio|dribbble|kaggle|medium|substack|personal/i, &1)
      )

    {linkedin || "", github || "", other}
  end

  defp find_first(uris, needle) do
    Enum.find(uris, fn u -> is_binary(u) and String.contains?(String.downcase(u), needle) end)
  end

  defp find_first_github(uris) do
    Enum.find(uris, fn u ->
      is_binary(u) and String.contains?(String.downcase(u), "github.com/") and
        not String.contains?(u, "/gist/")
    end)
  end
end
