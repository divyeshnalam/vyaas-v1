defmodule VyaasaCampus.AI.Resume.DomainConfig do
  @moduledoc """
  Per-domain scoring configuration. Port of domain_config.py.

  Every domain-specific assumption (which sections matter, their weights, rubric
  headings for relevance, page limits, sanity budget split) lives here. The scoring
  engines (Completeness, Relevance, Sanity) read from this config and contain no
  domain logic of their own.

  Families: tech | healthcare | finance | law | education | design | trades | default
  """

  defstruct [
    :family,
    :sections,
    :min_skill_count,
    :rubric_headings,
    :structural_budget,
    :linguistic_budget,
    :penalize_grammar_style,
    :max_pages_fresher,
    :max_pages_senior
  ]

  defmodule Section do
    @moduledoc false
    defstruct [:key, :label, :weight, :required]
  end

  @doc "Return the DomainConfig for a family string. Unknown or nil falls back to default."
  def get_profile(nil), do: default()
  def get_profile(""), do: default()

  def get_profile(family) when is_binary(family) do
    case family |> String.trim() |> String.downcase() do
      "tech" -> tech()
      "healthcare" -> healthcare()
      "finance" -> finance()
      "law" -> law()
      "education" -> education()
      "design" -> design()
      "trades" -> trades()
      _ -> default()
    end
  end

  def get_profile(_), do: default()

  @doc """
  Reweight sections for fresher vs experienced.
  Fresher  → education/projects/portfolio +25%, experience -30%.
  Senior   → experience +20%, projects -20%.
  """
  def with_seniority(%__MODULE__{} = profile, true = _fresher?) do
    sections =
      Enum.map(profile.sections, fn s ->
        w =
          case s.key do
            k when k in ["Education", "Projects", "Portfolio"] -> round(s.weight * 1.25)
            "Work_Experience" -> round(s.weight * 0.70)
            _ -> s.weight
          end

        %{s | weight: w}
      end)

    %{profile | sections: sections}
  end

  def with_seniority(%__MODULE__{} = profile, false = _fresher?) do
    sections =
      Enum.map(profile.sections, fn s ->
        w =
          case s.key do
            "Work_Experience" -> round(s.weight * 1.20)
            "Projects" -> round(s.weight * 0.80)
            _ -> s.weight
          end

        %{s | weight: w}
      end)

    %{profile | sections: sections}
  end

  # ---------------------------------------------------------------------------
  # Families
  # ---------------------------------------------------------------------------

  defp default_sections do
    [
      %Section{key: "Full_Name",            label: "Name",                   weight: 4,  required: true},
      %Section{key: "contact",              label: "Contact info",            weight: 8,  required: true},
      %Section{key: "Professional_Summary", label: "Summary",                 weight: 6,  required: false},
      %Section{key: "Education",            label: "Education",               weight: 16, required: true},
      %Section{key: "Skills",               label: "Skills/Competencies",     weight: 16, required: true},
      %Section{key: "Work_Experience",      label: "Experience",              weight: 20, required: false},
      %Section{key: "Projects",             label: "Projects/Work samples",   weight: 10, required: false},
      %Section{key: "Certifications",       label: "Certifications/Licenses", weight: 8,  required: false},
      %Section{key: "Achievements",         label: "Achievements",            weight: 6,  required: false},
      %Section{key: "Languages_Spoken",     label: "Languages",               weight: 3,  required: false},
      %Section{key: "Volunteer_Or_Extra",   label: "Volunteer/Extra",         weight: 3,  required: false}
    ]
  end

  def default do
    %__MODULE__{
      family: "default",
      sections: default_sections(),
      min_skill_count: 6,
      rubric_headings: %{
        core: "Core Competencies",
        essential: "Methods & Tools",
        appreciated: "Specialized Knowledge"
      },
      structural_budget: 75,
      linguistic_budget: 25,
      penalize_grammar_style: false,
      max_pages_fresher: 2,
      max_pages_senior: 4
    }
  end

  defp tech do
    %{
      default()
      | family: "tech",
        sections:
          default_sections() ++
            [%Section{key: "Portfolio", label: "Portfolio/GitHub", weight: 11, required: false}],
        min_skill_count: 8,
        rubric_headings: %{
          core: "Core Technical Skills",
          essential: "Essential Tools & Frameworks",
          appreciated: "Appreciated Skills & Knowledge"
        }
    }
  end

  defp healthcare do
    %__MODULE__{
      family: "healthcare",
      sections: [
        %Section{key: "Full_Name",            label: "Name",                       weight: 4,  required: true},
        %Section{key: "contact",              label: "Contact info",               weight: 8,  required: true},
        %Section{key: "Professional_Summary", label: "Summary",                    weight: 6,  required: false},
        %Section{key: "Education",            label: "Education",                  weight: 16, required: true},
        %Section{key: "Certifications",       label: "Licensure & Certifications", weight: 16, required: true},
        %Section{key: "Work_Experience",      label: "Clinical / Work experience", weight: 22, required: false},
        %Section{key: "Skills",               label: "Clinical competencies",      weight: 14, required: true},
        %Section{key: "Achievements",         label: "Publications/Achievements",  weight: 8,  required: false},
        %Section{key: "Languages_Spoken",     label: "Languages",                  weight: 3,  required: false},
        %Section{key: "Volunteer_Or_Extra",   label: "Volunteer/Camps",            weight: 3,  required: false}
      ],
      min_skill_count: 6,
      rubric_headings: %{
        core: "Core Clinical Competencies",
        essential: "Procedures & Equipment",
        appreciated: "Specializations & Sub-specialties"
      },
      structural_budget: 80,
      linguistic_budget: 20,
      penalize_grammar_style: false,
      max_pages_fresher: 3,
      max_pages_senior: nil
    }
  end

  defp finance do
    %{
      default()
      | family: "finance",
        rubric_headings: %{
          core: "Core Finance Competencies",
          essential: "Standards, Tools & Systems",
          appreciated: "Specialized Knowledge"
        }
    }
  end

  defp law do
    %__MODULE__{
      family: "law",
      sections: [
        %Section{key: "Full_Name",            label: "Name",                            weight: 4,  required: true},
        %Section{key: "contact",              label: "Contact info",                    weight: 8,  required: true},
        %Section{key: "Professional_Summary", label: "Summary",                         weight: 6,  required: false},
        %Section{key: "Education",            label: "Education",                       weight: 16, required: true},
        %Section{key: "Certifications",       label: "Bar admission & Certifications",  weight: 14, required: true},
        %Section{key: "Work_Experience",      label: "Practice / Work experience",      weight: 22, required: false},
        %Section{key: "Skills",               label: "Practice areas & Skills",         weight: 16, required: true},
        %Section{key: "Achievements",         label: "Publications/Moots/Achievements", weight: 8,  required: false},
        %Section{key: "Languages_Spoken",     label: "Languages",                       weight: 3,  required: false}
      ],
      min_skill_count: 6,
      rubric_headings: %{
        core: "Core Practice Areas",
        essential: "Legal Skills & Tools",
        appreciated: "Specialized Knowledge"
      },
      structural_budget: 75,
      linguistic_budget: 25,
      penalize_grammar_style: false,
      max_pages_fresher: 2,
      max_pages_senior: nil
    }
  end

  defp education do
    %{
      default()
      | family: "education",
        rubric_headings: %{
          core: "Core Teaching Competencies",
          essential: "Pedagogy & Tools",
          appreciated: "Specialized Knowledge"
        },
        max_pages_senior: nil
    }
  end

  defp design do
    %{
      default()
      | family: "design",
        sections:
          default_sections() ++
            [%Section{key: "Portfolio", label: "Portfolio", weight: 14, required: true}],
        rubric_headings: %{
          core: "Core Design Competencies",
          essential: "Tools & Software",
          appreciated: "Specialized Knowledge"
        }
    }
  end

  defp trades do
    %{
      default()
      | family: "trades",
        min_skill_count: 4,
        rubric_headings: %{
          core: "Core Trade Skills",
          essential: "Equipment & Techniques",
          appreciated: "Certifications & Safety"
        },
        structural_budget: 85,
        linguistic_budget: 15
    }
  end
end
