defmodule VyaasaCampus.AI.CaseStudy.Specializations do
  @moduledoc """
  Specialization groups and their sub-specializations for case studies.
  Ported from the `case_iq` service. The (group, sub) pair drives scenario
  generation and the evaluation rubric.
  """

  @data %{
    "Software & Data" => [
      "Software/Web Dev",
      "Data Science/ML",
      "Generative AI",
      "Data Engineering"
    ],
    "Infrastructure & Security" => [
      "DevOps/Cloud",
      "Software Testing & QA",
      "Cybersecurity",
      "Blockchain & Web3"
    ],
    "Embedded & Mobile" => [
      "IoT",
      "Embedded Systems",
      "Mobile App Development",
      "Robotics & Automation"
    ],
    "Engineering Disciplines" => [
      "Mechanical",
      "Electrical",
      "Civil",
      "Chemical",
      "Aerospace",
      "Automobile",
      "Biomedical/Biotech",
      "Mechatronics",
      "Environmental Eng",
      "Industrial & Production Eng"
    ],
    "Commerce Specializations" => [
      "Finance & Investment",
      "Accounting & Taxation",
      "Marketing & Advertising",
      "Human Resource Management (HRM)",
      "International Business"
    ],
    "Arts & Humanities" => [
      "Psychology & Counseling",
      "Media & Journalism",
      "Law & Corporate Compliance",
      "Sociology & Public Policy",
      "Hospitality & Tourism"
    ]
  }

  @group_order [
    "Software & Data",
    "Infrastructure & Security",
    "Embedded & Mobile",
    "Engineering Disciplines",
    "Commerce Specializations",
    "Arts & Humanities"
  ]

  def all, do: @data
  def groups, do: @group_order
  def subs_for(group), do: Map.get(@data, group, [])

  @doc "Find the group a sub-specialization belongs to (or nil)."
  def group_for(sub) do
    Enum.find_value(@data, fn {group, subs} -> if sub in subs, do: group end)
  end
end
