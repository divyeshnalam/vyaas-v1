defmodule VyaasaCampus.Contexts.StudentRankingsCaseStudyMiniProjectTest do
  @moduledoc """
  Case Study and Mini Project were the two assessment types missing from the
  shared student-profile card (it only rendered 5 of the platform's 8 types).
  Covers the new `get_case_study_rank/2` / `get_mini_project_rank/2`, mirrored
  off the existing `get_jam_rank/2` shape (single numeric best-score field),
  including Mini Project's quirk of tracking completion via `phase`, not
  `status` like every other assessment type.
  """
  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.StudentRankings
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.CaseStudy.CaseStudySession
  alias VyaasaCampus.Schema.Students.StudentMiniProjectSession

  @tenant_schema "tenant_test"

  defp insert_case_study!(attrs) do
    defaults = %{
      student_id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      session_token: "cs-tok-#{System.unique_integer([:positive])}",
      specialization_sub: "backend"
    }

    {:ok, session} =
      %CaseStudySession{}
      |> CaseStudySession.create_changeset(Map.merge(defaults, attrs))
      |> Repo.insert(prefix: @tenant_schema)

    session
  end

  defp complete_case_study!(session, total_score) do
    session
    |> CaseStudySession.complete_changeset(%{status: "completed", total_score: total_score})
    |> Repo.update!(prefix: @tenant_schema)
  end

  defp insert_mini_project!(attrs) do
    defaults = %{
      student_id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      session_token: "mp-tok-#{System.unique_integer([:positive])}"
    }

    {:ok, session} =
      defaults
      |> Map.merge(attrs)
      |> StudentMiniProjectSession.create_changeset()
      |> Repo.insert(prefix: @tenant_schema)

    session
  end

  defp complete_mini_project!(session, final_score) do
    session
    |> Ecto.Changeset.change(%{phase: "completed", final_score: final_score})
    |> Repo.update!(prefix: @tenant_schema)
  end

  describe "get_case_study_rank/2" do
    test "a student with no completed session gets a nil score and false completed" do
      result = StudentRankings.get_case_study_rank(Ecto.UUID.generate(), @tenant_schema)

      assert result.score == nil
      assert result.rank == nil
      assert result.completed == false
    end

    test "ranks a student against other students' best completed scores" do
      student = insert_case_study!(%{})
      complete_case_study!(student, 70)

      other1 = insert_case_study!(%{})
      complete_case_study!(other1, 90)

      other2 = insert_case_study!(%{})
      complete_case_study!(other2, 50)

      result = StudentRankings.get_case_study_rank(student.student_id, @tenant_schema)

      assert result.score == 70
      assert result.rank == 2
      assert result.total == 3
      assert result.completed == true
    end

    test "an in-progress session isn't counted as completed" do
      session = insert_case_study!(%{})

      result = StudentRankings.get_case_study_rank(session.student_id, @tenant_schema)

      assert result.completed == false
    end
  end

  describe "get_mini_project_rank/2" do
    test "a student with no completed session gets a nil score and false completed" do
      result = StudentRankings.get_mini_project_rank(Ecto.UUID.generate(), @tenant_schema)

      assert result.score == nil
      assert result.rank == nil
      assert result.completed == false
    end

    test "ranks a student against other students' best completed scores" do
      student = insert_mini_project!(%{})
      complete_mini_project!(student, 80)

      other1 = insert_mini_project!(%{})
      complete_mini_project!(other1, 95)

      result = StudentRankings.get_mini_project_rank(student.student_id, @tenant_schema)

      assert result.score == 80
      assert result.rank == 2
      assert result.total == 2
      assert result.completed == true
    end

    test "tracks completion via phase, not status" do
      session = insert_mini_project!(%{})
      complete_mini_project!(session, 60)

      result = StudentRankings.get_mini_project_rank(session.student_id, @tenant_schema)

      assert result.completed == true
      assert result.score == 60
    end
  end
end
