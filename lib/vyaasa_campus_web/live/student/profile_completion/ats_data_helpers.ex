defmodule VyaasaCampusWeb.Student.ProfileCompletion.AtsDataHelpers do
  @moduledoc """
  Helper functions for loading and processing ATS data.
  """

  alias VyaasaCampus.Contexts.{StudentAts, Tenants}

  def load_ats_data(student_id, tenant_alias) do
    require Logger
    Logger.info("🔍 LOAD_ATS_DATA - Loading ATS data for student: #{student_id}, tenant: #{tenant_alias}")

    with {:ok, tenant} <- get_tenant(tenant_alias),
         {:ok, ats_phase} <- get_ats_phase(student_id, tenant.schema_name),
         true <- StudentAts.ats_completed?(student_id, tenant.schema_name) do
      Logger.info("✅ LOAD_ATS_DATA - ATS phase found and completed, building data...")
      Logger.info("🔍 LOAD_ATS_DATA - ATS phase status: #{ats_phase.status}")
      Logger.info("🔍 LOAD_ATS_DATA - ATS phase skills: #{inspect(ats_phase.skills)}")
      Logger.info("🔍 LOAD_ATS_DATA - ATS phase work_experience: #{inspect(ats_phase.work_experience)}")

      result = build_ats_data(ats_phase, student_id, tenant.schema_name)
      Logger.info("🔍 LOAD_ATS_DATA - Built ATS data: #{inspect(result)}")
      result
    else
      error ->
        Logger.warning("❌ LOAD_ATS_DATA - Failed to load ATS data: #{inspect(error)}")
        nil
    end
  rescue
    exception ->
      require Logger
      Logger.error("💥 LOAD_ATS_DATA - Exception: #{inspect(exception)}")
      nil
  end

  defp get_tenant(tenant_alias) do
    case Tenants.get_tenant_by_alias(tenant_alias) do
      nil -> {:error, :not_found}
      tenant -> {:ok, tenant}
    end
  end

  defp get_ats_phase(student_id, schema_name) do
    case StudentAts.get_by_student_id(student_id, schema_name) do
      nil -> {:error, :not_found}
      ats_phase -> {:ok, ats_phase}
    end
  end

  defp build_ats_data(ats_phase, student_id, schema_name) do
    require Logger
    Logger.info("🔍 BUILD_ATS_DATA - Building ATS data for student: #{student_id}")

    final_score = determine_ats_score(ats_phase, student_id, schema_name)
    completeness_data = extract_completeness_from_ats(ats_phase)
    relevance_data = extract_relevance_from_ats(ats_phase)

    %{
      ats_score: final_score,
      preferred_role: ats_phase.preferred_role,
      skills: extract_skills_from_ats(ats_phase),
      work_experience: extract_work_experience_from_ats(ats_phase),
      languages: extract_languages_from_ats(ats_phase),
      external_links: extract_external_links_from_ats(ats_phase),
      areas_for_improvement: StudentAts.get_areas_for_improvement(student_id, schema_name),
      education: ats_phase.education,
      projects: ats_phase.projects,
      completeness: completeness_data,
      relevance: relevance_data,
      sanity: ats_phase.sanity_check,
      ats_detail: ats_phase.raw_result_json
    }
  end

  defp extract_relevance_from_ats(ats_phase) do
    case ats_phase.raw_result_json do
      %{"relevance" => relevance} ->
        %{
          score: Map.get(relevance, "score"),
          matching_keywords: get_in(relevance, ["details", "matching_keywords"]),
          missing_keywords: get_in(relevance, ["details", "missing_keywords"]),
          justification: get_in(relevance, ["details", "justification"])
        }

      _ ->
        nil
    end
  end

  defp extract_completeness_from_ats(ats_phase) do
    case ats_phase.raw_result_json do
      %{"completeness" => completeness} ->
        %{
          score: Map.get(completeness, "score"),
          feedback: Map.get(completeness, "feedback"),
          other_links: Map.get(completeness, "other_links")
        }

      _ ->
        nil
    end
  end

  defp determine_ats_score(ats_phase, student_id, schema_name) do
    ats_score = StudentAts.get_student_ats_score(student_id, schema_name)
    direct_score = extract_direct_score(ats_phase.ats_score)
    metadata_score = extract_metadata_score(ats_phase.metadata)

    cond do
      direct_score && direct_score > 0 -> direct_score
      metadata_score && metadata_score > 0 -> metadata_score
      ats_score && ats_score > 0 -> ats_score
      true -> calculate_mock_ats_score(ats_phase)
    end
  end

  defp extract_direct_score(ats_score) do
    case ats_score do
      nil ->
        nil

      score when is_number(score) ->
        score

      score when is_binary(score) ->
        case Float.parse(score) do
          {float_score, _} -> float_score
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_metadata_score(metadata) do
    case metadata do
      %{"ts_score" => score} when is_number(score) -> score
      %{"ats_score" => score} when is_number(score) -> score
      _ -> nil
    end
  end

  def populate_form_data_from_ats(socket, nil) do
    require Logger
    Logger.info("🔍 POPULATE_FORM_DATA - No ATS data provided")
    socket
  end

  def populate_form_data_from_ats(socket, ats_data) do
    require Logger
    Logger.info("🔍 POPULATE_FORM_DATA - Populating form with ATS data: #{inspect(ats_data)}")

    socket =
      socket
      |> Phoenix.Component.assign(:preferred_job_role, ats_data.preferred_role || "")
      |> Phoenix.Component.assign(:selected_skills, ats_data.skills || [])
      |> Phoenix.Component.assign(
        :work_experiences,
        if(length(ats_data.work_experience || []) > 0,
          do: ats_data.work_experience,
          else: [%{job_title: "", company_name: "", start_date: "", end_date: "", responsibilities: ""}]
        )
      )
      |> Phoenix.Component.assign(:languages, ats_data.languages || [])
      |> Phoenix.Component.assign(:external_links, ats_data.external_links || %{})
      |> Phoenix.Component.assign(:ats_score, ats_data.ats_score)
      |> Phoenix.Component.assign(:ats_feedback, format_ats_feedback(ats_data.areas_for_improvement))
      |> Phoenix.Component.assign(:education, ats_data.education || [])
      |> Phoenix.Component.assign(:projects, ats_data.projects || [])

    Logger.info("✅ POPULATE_FORM_DATA - Form data populated successfully")
    socket
  end

  defp extract_skills_from_ats(ats_phase) do
    case ats_phase.skills do
      nil ->
        []

      skills when is_map(skills) ->
        # Extract from various possible skill structures
        skills
        |> Map.values()
        |> List.flatten()
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()

      skills when is_list(skills) ->
        skills

      _ ->
        []
    end
  end

  defp extract_work_experience_from_ats(ats_phase) do
    case ats_phase.work_experience do
      nil ->
        []

      experiences when is_list(experiences) ->
        Enum.map(experiences, &normalize_work_experience/1)

      _ ->
        []
    end
  end

  defp normalize_work_experience(exp) do
    %{
      job_title: get_field_value(exp, ["Job_Title", "title", "job_title"]),
      company_name: get_field_value(exp, ["Company_Name", "company", "company_name"]),
      start_date: exp["start_date"] || "",
      end_date: exp["end_date"] || "",
      responsibilities: get_field_value(exp, ["Responsibilities", "description", "responsibilities"])
    }
  end

  defp get_field_value(map, keys) do
    Enum.find_value(keys, "", fn key ->
      case map[key] do
        nil -> nil
        value when is_list(value) -> Enum.join(value, ", ")
        value -> value
      end
    end)
  end

  defp extract_languages_from_ats(ats_phase) do
    case ats_phase.languages do
      nil -> []
      languages when is_list(languages) -> languages
      languages when is_map(languages) -> Map.values(languages) |> List.flatten()
      _ -> []
    end
  end

  defp extract_external_links_from_ats(ats_phase) do
    case ats_phase.portfolio_and_links do
      nil -> %{}
      links when is_map(links) -> normalize_external_links(links)
      _ -> %{}
    end
  end

  defp normalize_external_links(links) do
    other_links = links["other_links"] || []
    {linkedin, github, portfolio, other} = categorize_links(other_links)

    %{
      linkedin: absolute_url(linkedin),
      github: absolute_url(github),
      portfolio: absolute_url(portfolio),
      other: Enum.join(other, ", ")
    }
  end

  # Keep blank values blank (templates gate on != ""); force a scheme otherwise
  # so the link doesn't resolve relative to our own origin.
  defp absolute_url(""), do: ""
  defp absolute_url(url), do: VyaasaCampusWeb.Helpers.Url.absolute(url)

  defp categorize_links(other_links) do
    Enum.reduce(other_links, {"", "", "", []}, &categorize_single_link/2)
  end

  defp categorize_single_link(link, {linkedin_acc, github_acc, portfolio_acc, other_acc}) do
    uri = link["uri"] || ""
    text = link["text"] || ""

    cond do
      linkedin_link?(uri, text) -> {uri, github_acc, portfolio_acc, other_acc}
      github_link?(uri, text) -> {linkedin_acc, uri, portfolio_acc, other_acc}
      portfolio_link?(uri, text) -> {linkedin_acc, github_acc, uri, other_acc}
      true -> {linkedin_acc, github_acc, portfolio_acc, [uri | other_acc]}
    end
  end

  defp linkedin_link?(uri, text) do
    String.contains?(String.downcase(uri), "linkedin") or String.contains?(String.downcase(text), "linkedin")
  end

  defp github_link?(uri, text) do
    String.contains?(String.downcase(uri), "github") or String.contains?(String.downcase(text), "github")
  end

  defp portfolio_link?(uri, text) do
    String.contains?(String.downcase(uri), "vercel") or
      String.contains?(String.downcase(uri), "portfolio") or
      String.contains?(String.downcase(text), "portfolio")
  end

  defp format_ats_feedback(areas_for_improvement) when is_map(areas_for_improvement) do
    areas_for_improvement
    |> Enum.map(fn {key, value} -> "#{key |> String.replace("_", " ") |> String.capitalize()}: #{value}" end)
  end

  defp format_ats_feedback(_), do: []

  # Calculate a mock ATS score based on available data
  # Simplified: No mock calculation, just safe extraction
  defp calculate_mock_ats_score(ats_phase) do
    require Logger
    raw_score = ats_phase.ats_score

    final_score =
      cond do
        # 1. Handle Ecto Decimal (Most likely scenario)
        is_struct(raw_score, Decimal) ->
          Decimal.to_integer(raw_score)

        # 2. Handle Standard Numbers
        is_integer(raw_score) ->
          raw_score

        is_float(raw_score) ->
          round(raw_score)

        # 3. Handle Strings (e.g. "85.50")
        is_binary(raw_score) ->
          case Float.parse(raw_score) do
            {num, _} -> round(num)
            :error -> 0
          end

        # 4. If nil or unknown, return 0
        true ->
          0
      end

    Logger.info("🔍 ATS SCORE - Raw: #{inspect(raw_score)} | Final: #{final_score}")

    final_score
  end

  defp calculate_skills_score(skills) do
    skills_count =
      case skills do
        %{"technical_skills" => skills_list} when is_list(skills_list) -> length(skills_list)
        _ -> 0
      end

    min(skills_count * 2, 20)
  end

  defp calculate_work_experience_score(work_experience) do
    work_exp_count =
      case work_experience do
        experiences when is_list(experiences) -> length(experiences)
        _ -> 0
      end

    min(work_exp_count * 10, 20)
    end

  defp calculate_projects_score(projects) do
    projects_count =
      case projects do
        projects_list when is_list(projects_list) -> length(projects_list)
        _ -> 0
      end

    min(projects_count * 5, 15)
  end

  defp calculate_education_score(education) do
    case education do
      education_list when is_list(education_list) and length(education_list) > 0 -> 10
      _ -> 0
    end
  end

  defp calculate_links_score(portfolio_and_links) do
    case portfolio_and_links do
      %{"other_links" => links} when is_list(links) ->
        min(length(links) * 2, 10)

      _ ->
        0
    end
  end
end
