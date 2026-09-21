defmodule VyaasaCampus.AI.CaseStudy.Questions do
  @moduledoc """
  The 7 universal case-study evaluation sections. Not tied to a specific
  scenario — they probe the rubric dimensions regardless of the case study.
  Ported from the `case_iq` service.
  """

  @questions [
    %{
      key: "problem_understanding",
      title: "Problem Understanding",
      prompt:
        "In your own words, what is the core problem in this scenario? Who is affected and why does it matter?"
    },
    %{
      key: "assumptions",
      title: "Assumptions",
      prompt:
        "What assumptions are you making about the users, the data, the team, or the constraints? List any missing information you're inferring."
    },
    %{
      key: "proposed_solution",
      title: "Proposed Solution",
      prompt:
        "At a high level, what's your approach to solve this? Describe the shape of your solution in a few sentences."
    },
    %{
      key: "step_by_step",
      title: "Step-by-Step Approach",
      prompt:
        "Break your solution into concrete steps, in the order you would carry them out. What happens first, second, third?"
    },
    %{
      key: "tools",
      title: "Tools / Technologies / Methods",
      prompt:
        "Which specific tools, libraries, frameworks, or methodologies would you use and why? Mention alternatives you considered."
    },
    %{
      key: "edge_cases",
      title: "Edge Cases / Risks",
      prompt:
        "What could go wrong? List failure modes, edge cases, and risks — and how you'd handle them."
    },
    %{
      key: "improvements",
      title: "Improvements / Future Enhancements",
      prompt:
        "If you had more time or resources, how would you improve or extend your solution? What's the V2?"
    }
  ]

  def all, do: @questions
  def keys, do: Enum.map(@questions, & &1.key)
  def empty_answers, do: Enum.into(@questions, %{}, fn %{key: k} -> {k, ""} end)
  def get(key), do: Enum.find(@questions, &(&1.key == key))
end
