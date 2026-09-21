defmodule VyaasaCampusWeb.Components.Student.Dashboard.Helpers do
  @moduledoc """
  Shared helpers for student dashboard components.
  Consolidates score display, color coding, and data extraction utilities.
  """

  # Score tier thresholds — single source of truth for all color/label decisions
  @score_tiers [
    {85, %{label: "Excellent", badge: "bg-green-100 text-green-800", text: "text-green-600", bar: "bg-green-600"}},
    {70, %{label: "Good", badge: "bg-yellow-100 text-yellow-800", text: "text-yellow-600", bar: "bg-yellow-600"}},
    {50, %{label: "Fair", badge: "bg-orange-100 text-orange-800", text: "text-orange-600", bar: "bg-orange-600"}},
    {0, %{label: "Needs Work", badge: "bg-red-100 text-red-800", text: "text-red-600", bar: "bg-red-600"}}
  ]

  def score_tier(score) when is_number(score) do
    Enum.find_value(@score_tiers, fn {threshold, tier} ->
      if score >= threshold, do: tier
    end)
  end

  def score_tier(_), do: score_tier(0)

  def safe_score(nil), do: 0
  def safe_score(score) when is_number(score), do: round(score)
  def safe_score(_), do: 0

  def get_initials(name) when is_binary(name) do
    name
    |> String.split(" ")
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.map(&String.upcase/1)
    |> Enum.join("")
  end

  def get_initials(_), do: "S"

  def display_score(%{completed: true} = data, :percentage) do
    pct = data[:percentage] || data[:score]
    if pct, do: round(safe_to_number(pct)), else: "-"
  end

  def display_score(_, :percentage), do: "-"

  def display_score(%{completed: true, score: score}) when not is_nil(score), do: round(score)
  def display_score(_), do: "-"

  def get_skills_list(skills, key) when is_map(skills) do
    case Map.get(skills, key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  def get_skills_list(_, _), do: []

  def get_language_names(languages) when is_list(languages) do
    Enum.flat_map(languages, fn
      lang when is_binary(lang) -> [lang]
      lang when is_map(lang) -> [lang["name"] || lang["Name"] || lang["language"] || lang["Language"]] |> Enum.reject(&is_nil/1)
      _ -> []
    end)
  end

  def get_language_names(_), do: []

  def convert_decimal_to_float(nil), do: nil
  def convert_decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  def convert_decimal_to_float(val), do: val

  def safe_to_number(nil), do: nil
  def safe_to_number(%Decimal{} = d), do: Decimal.to_float(d)
  def safe_to_number(n) when is_number(n), do: n * 1.0
  def safe_to_number(_), do: nil

  # Assessment card configuration — single definition for all assessment types
  def assessment_cards do
    [
      %{key: :ats, label: "Resume Analysis", icon: "hero-document-text", bg: "bg-orange-100", text: "text-orange-500", bar: "bg-orange-500"},
      %{key: :behavioral, label: "Behavioral Assessment", icon: "hero-light-bulb", bg: "bg-purple-100", text: "text-purple-600", bar: "bg-purple-500"},
      %{key: :jam, label: "JAM Session", icon: "hero-chat-bubble-left-right", bg: "bg-blue-100", text: "text-blue-600", bar: "bg-blue-500"},
      %{key: :mcq, label: "Objective Evaluation", icon: "hero-code-bracket", bg: "bg-green-100", text: "text-green-600", bar: "bg-green-500"},
      %{key: :interview, label: "Interactive Session", icon: "hero-microphone", bg: "bg-indigo-100", text: "text-indigo-600", bar: "bg-indigo-500"},
      %{key: :psychometric, label: "Psychometric", icon: "hero-cpu-chip", bg: "bg-teal-100", text: "text-teal-600", bar: "bg-teal-500"}
    ]
  end

  # Attempt history type configuration
  def attempt_history_types do
    [
      %{key: :mcq, label: "Objective Evaluation (MCQ)", icon: "hero-code-bracket", bg: "bg-green-100", text: "text-green-600", bar: "bg-green-500", count_label: "attempt"},
      %{key: :behavioral, label: "Behavioral Assessment", icon: "hero-light-bulb", bg: "bg-purple-100", text: "text-purple-600", bar: "bg-purple-500", count_label: "attempt"},
      %{key: :jam, label: "JAM Session", icon: "hero-chat-bubble-left-right", bg: "bg-blue-100", text: "text-blue-600", bar: "bg-blue-500", count_label: "session"},
      %{key: :interview, label: "Interactive Session", icon: "hero-microphone", bg: "bg-indigo-100", text: "text-indigo-600", bar: "bg-indigo-500", count_label: "session"},
      %{key: :psychometric, label: "Psychometric Assessment", icon: "hero-puzzle-piece", bg: "bg-teal-100", text: "text-teal-600", bar: "bg-teal-500", count_label: "attempt"}
    ]
  end

  # Extract portfolio links from ATS data.
  # Always normalises to the map format %{"other_links" => [...]} so collect_links/1
  # in ResumeDashboard can reliably pattern-match on it.
  def extract_portfolio_links(nil), do: %{}
  def extract_portfolio_links(%{"other_links" => _} = m), do: m
  def extract_portfolio_links(%{other_links: links}), do: %{"other_links" => List.wrap(links)}
  def extract_portfolio_links(%{} = _empty), do: %{}
  def extract_portfolio_links(links) when is_list(links),
    do: %{"other_links" => Enum.filter(links, &is_binary/1)}
  def extract_portfolio_links(_), do: %{}

  # Convert ATS data to a simple map for template rendering
  def convert_ats_data_to_simple_map(nil), do: nil

  def convert_ats_data_to_simple_map(ats_data) do
    %{
      # Carry the record id through — the resume "Email Report" action needs it
      # (its `%{id: id}` match previously always failed because id was dropped).
      id: ats_data.id,
      ats_score: convert_decimal_to_float(ats_data.ats_score),
      resume_url: ats_data.resume_url,
      status: ats_data.status,
      metadata: ats_data.metadata || %{},
      skills: ats_data.skills || %{},
      personal_information: ats_data.personal_information || %{},
      professional_summary: ats_data.professional_summary || %{},
      education: ats_data.education || [],
      work_experience: ats_data.work_experience || [],
      projects: ats_data.projects || [],
      languages: ats_data.languages || [],
      certifications: ats_data.certifications || [],
      preferred_role: ats_data.preferred_role,
      portfolio_and_links: extract_portfolio_links(ats_data.portfolio_and_links),
      profile_picture_url: ats_data.profile_picture_url
    }
  end

  def convert_student_to_simple_map(student) do
    %{
      id: student.id,
      first_name: student.first_name,
      last_name: student.last_name,
      email: student.email,
      status: student.status,
      degree: student.degree,
      specialization: student.specialization,
      year_of_passing: student.year_of_passing,
      cgpa: if(student.cgpa, do: Decimal.to_float(student.cgpa), else: nil),
      phone: student.phone,
      tenant_id: student.tenant_id
    }
  end
end
