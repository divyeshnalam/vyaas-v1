defmodule VyaasaCampus.AI.Resume.ScoringTest do
  @moduledoc """
  Pure-function tests for the resume scoring pipeline.

  Skips embedding / LLM tests — those need the EmbeddingServer running and a
  live Groq key. Run those separately with `mix test --only integration`.
  """

  use ExUnit.Case, async: true

  alias VyaasaCampus.AI.Resume.{Completeness, DomainConfig, Experience, Sanity}

  @default_profile DomainConfig.default()

  # ----------------------------------------------------------------------
  # Experience
  # ----------------------------------------------------------------------

  describe "Experience.calculate/1" do
    test "returns 0.0 for empty list" do
      assert Experience.calculate([]) == 0.0
    end

    test "computes single interval in years" do
      jobs = [%{"start_date" => "01/2020", "end_date" => "01/2022"}]
      assert Experience.calculate(jobs) == 2.0
    end

    test "merges overlapping intervals so concurrent jobs don't double-count" do
      jobs = [
        %{"start_date" => "01/2020", "end_date" => "01/2022"},
        %{"start_date" => "06/2021", "end_date" => "06/2023"}
      ]

      # 01/2020 → 06/2023 = 41 months / 12 = 3.42 years
      assert Experience.calculate(jobs) == 3.42
    end

    test "handles 'present' end date" do
      jobs = [%{"start_date" => "01/2024", "end_date" => "Present"}]
      result = Experience.calculate(jobs)
      assert result > 0.0
    end

    test "ignores entries with unparseable dates" do
      jobs = [
        %{"start_date" => "garbage", "end_date" => "more garbage"},
        %{"start_date" => "01/2020", "end_date" => "01/2021"}
      ]

      assert Experience.calculate(jobs) == 1.0
    end
  end

  describe "Experience.format_experience/1" do
    test "formats years and months" do
      assert Experience.format_experience(2.5) == "2 years, 6 months"
    end

    test "handles zero" do
      assert Experience.format_experience(0) == "No experience"
    end

    test "handles single year" do
      assert Experience.format_experience(1.0) == "1 year"
    end
  end

  describe "Experience.fresher?/1" do
    test "true for under 2 years" do
      assert Experience.fresher?(0.5)
      assert Experience.fresher?(1.99)
    end

    test "false at or above 2 years" do
      refute Experience.fresher?(2.0)
      refute Experience.fresher?(5.0)
    end
  end

  # ----------------------------------------------------------------------
  # Completeness
  # ----------------------------------------------------------------------

  describe "Completeness.score/3" do
    test "empty parsed → near-zero score with feedback" do
      result = Completeness.score(%{}, [], @default_profile)
      assert result.score < 10
      assert is_list(result.feedback)
      assert length(result.feedback) >= 4
    end

    test "fully populated parsed → high score" do
      parsed = sample_parsed()
      links = [%{uri: "https://linkedin.com/in/example"}, %{uri: "https://github.com/example"}]

      result = Completeness.score(parsed, links, @default_profile)
      assert result.score >= 75
      assert result.corrected_links["linkedin"] =~ "linkedin.com"
      assert result.corrected_links["github"] =~ "github.com"
    end

    test "section breakdown includes all expected keys" do
      result = Completeness.score(sample_parsed(), [], @default_profile)
      keys = Map.keys(result.sections)

      for key <- ["Full_Name", "contact", "Professional_Summary", "Education", "Skills",
                  "Work_Experience", "Projects", "Certifications", "Achievements",
                  "Languages_Spoken", "Volunteer_Or_Extra"] do
        assert key in keys, "expected section key #{inspect(key)} in #{inspect(keys)}"
      end
    end
  end

  # ----------------------------------------------------------------------
  # Sanity (structural — pure)
  # ----------------------------------------------------------------------

  describe "Sanity.structural_score/4" do
    test "no penalties for clean fresher resume" do
      text = "John Doe\njohn@example.com\n+1 555 123 4567\nExperience\nEducation\nSkills"
      result = Sanity.structural_score(text, 1, true, @default_profile)
      assert result.score == @default_profile.structural_budget
      assert result.penalties == []
    end

    test "penalises missing email" do
      text = "John Doe\nNo email here\nExperience Education Skills"
      result = Sanity.structural_score(text, 1, true, @default_profile)
      assert Enum.any?(result.penalties, &(&1.rule == "Email missing"))
    end

    test "penalises fresher with too many pages" do
      text = "anything Experience Education Skills j@x.com +1234567"
      result = Sanity.structural_score(text, 4, true, @default_profile)
      assert Enum.any?(result.penalties, &(&1.rule == "Page count"))
    end

    test "penalises mixed date formats" do
      text = "Worked Jan 2020. Other role 06/2021. Experience Education Skills j@x.com +1234567"
      result = Sanity.structural_score(text, 1, false, @default_profile)
      assert Enum.any?(result.penalties, &(&1.rule == "Date format inconsistency"))
    end
  end

  describe "Sanity.linguistic_score/2" do
    test "max score with no hints" do
      result = Sanity.linguistic_score(%{}, @default_profile)
      assert result.score == @default_profile.linguistic_budget
    end

    test "penalises typos" do
      result = Sanity.linguistic_score(%{"typos" => ["recieve", "managment"]}, @default_profile)
      assert result.score < @default_profile.linguistic_budget
      assert Enum.any?(result.penalties, &(&1.rule == "Typos / Spelling"))
    end

    test "caps typo penalty" do
      typos = Enum.map(1..50, fn i -> "typo#{i}" end)
      result = Sanity.linguistic_score(%{"typos" => typos}, @default_profile)
      [penalty] = Enum.filter(result.penalties, &(&1.rule == "Typos / Spelling"))
      # cap = round(20 * linguistic_budget / 50)
      expected_cap = round(20 * @default_profile.linguistic_budget / 50)
      assert penalty.penalty == expected_cap
    end
  end

  describe "Sanity.score/5 combined" do
    test "returns Pass status when total >= 70" do
      result = Sanity.score(
        "j@x.com +12345 Experience Education Skills",
        1,
        true,
        %{},
        @default_profile
      )

      assert result.status == "Pass"
      assert result.score >= 70
    end
  end

  # ----------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------

  defp sample_parsed do
    %{
      "Full_Name" => "Jane Doe",
      "Email_Address" => "jane@example.com",
      "Contact_Number" => "+91 9000000000",
      "Location" => "Hyderabad",
      "LinkedIn_Profile" => "https://linkedin.com/in/jane",
      "GitHub_Profile" => "https://github.com/jane",
      "Professional_Summary" => ["Software engineer with 3 years of experience."],
      "Skills" => %{
        "Technical" => ["Elixir", "Phoenix", "Ecto", "PostgreSQL", "Docker"],
        "Non_Technical" => ["Communication", "Teamwork", "Leadership"]
      },
      "Education" => [
        %{
          "Degree" => "B.Tech",
          "Institution" => "KL University",
          "Years" => "2018-2022",
          "Specialization" => "CSE",
          "CGPA_Percentage" => "8.5"
        },
        %{
          "Degree" => "Intermediate",
          "Institution" => "Narayana Junior College",
          "Years" => "2016-2018",
          "CGPA_Percentage" => "95%"
        }
      ],
      "Work_Experience" => [
        %{
          "Company_Name" => "Acme",
          "Job_Title" => "Engineer",
          "start_date" => "01/2022",
          "end_date" => "Present",
          "Responsibilities" => ["Built APIs"]
        },
        %{
          "Company_Name" => "Beta Corp",
          "Job_Title" => "Junior Developer",
          "start_date" => "06/2020",
          "end_date" => "12/2021",
          "Responsibilities" => ["Frontend dev"]
        }
      ],
      "Projects" => [
        %{
          "Project_Name" => "Resume Scorer",
          "Technologies_Used" => ["Elixir", "Bumblebee"],
          "Description" => ["A native scoring pipeline"]
        },
        %{
          "Project_Name" => "Dashboard",
          "Technologies_Used" => ["Phoenix", "LiveView"],
          "Description" => ["Real-time analytics"]
        }
      ],
      "Certifications" => ["AWS Cloud Practitioner", "GCP Associate"],
      "Languages_Spoken" => ["English", "Telugu"],
      "Achievements" => ["Hackathon winner"],
      "Volunteer_Or_Extra" => []
    }
  end
end
