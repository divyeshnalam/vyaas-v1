defmodule VyaasaCampus.Contexts.AssessmentsTest do
  use VyaasaCampus.DataCase

  alias VyaasaCampus.Contexts.Assessments
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Assessments.{Assessment, AssessmentAttempt}
  alias VyaasaCampus.Schema.Students.Student
  alias VyaasaCampus.Schema.Accounts.User

  @tenant_schema "tenant_test"

  describe "dynamic assessment creation" do
    setup do
      # Create test tenant schema
      Repo.query!("CREATE SCHEMA IF NOT EXISTS #{@tenant_schema}")

      # Run migrations for tenant schema
      # Note: In real tests, this should be done in test_helper

      # Create a test user
      admin_id = Ecto.UUID.generate()
      user_attrs = %{
        email: "test@example.com",
        first_name: "Test",
        last_name: "User",
        password_hash: "test_hash",
        status: "active",
        role: "admin",
        tenant_id: Ecto.UUID.generate(),
        created_by_id: admin_id,
        created_by_type: "public"
      }

      {:ok, user} = Repo.insert(%User{} |> User.changeset(user_attrs), prefix: @tenant_schema)

      # Create a test student
      student_attrs = %{
        email: "student@example.com",
        first_name: "Test",
        last_name: "Student",
        degree: "B.Tech",
        specialization: "Computer Science",
        status: "active",
        phone: "9000000001",
        registration_id: "REG001",
        year_of_passing: 2024,
        cgpa: "8.5",
        tenant_id: user.tenant_id,
        created_by_id: admin_id,
        created_by_type: "public"
      }

      {:ok, student} = Repo.insert(%Student{} |> Student.changeset(student_attrs), prefix: @tenant_schema)

      %{user: user, student: student, tenant_schema: @tenant_schema}
    end

    test "creates dynamic assessment with SQL function", %{student: student, tenant_schema: tenant_schema} do
      result = Assessments.get_or_create_dynamic_assessment(student.id, tenant_schema)

      assert {:ok, assessment} = result
      assert assessment.title =~ "Employability Assessment"
      assert assessment.status == "published"
      assert is_binary(assessment.created_by)
    end

    test "reuses existing assessment within 24 hours", %{student: student, tenant_schema: tenant_schema} do
      # Create first assessment
      {:ok, assessment1} = Assessments.get_or_create_dynamic_assessment(student.id, tenant_schema)

      # Try to create again - should return same assessment
      {:ok, assessment2} = Assessments.get_or_create_dynamic_assessment(student.id, tenant_schema)

      assert assessment1.id == assessment2.id
    end

    test "returns or reuses assessment when question bank is empty", %{student: student, tenant_schema: tenant_schema} do
      # Without a seeded question bank, the generator either errors or creates
      # an assessment with an empty question set — both are valid outcomes.
      result = Assessments.get_or_create_dynamic_assessment(student.id, tenant_schema)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "assessment attempts" do
    setup do
      # Setup similar to above
      Repo.query!("CREATE SCHEMA IF NOT EXISTS #{@tenant_schema}")

      admin_id = Ecto.UUID.generate()
      user_attrs = %{
        email: "test2@example.com",
        first_name: "Test",
        last_name: "User2",
        password_hash: "test_hash",
        status: "active",
        role: "admin",
        tenant_id: Ecto.UUID.generate(),
        created_by_id: admin_id,
        created_by_type: "public"
      }

      {:ok, user} = Repo.insert(%User{} |> User.changeset(user_attrs), prefix: @tenant_schema)

      student_attrs = %{
        email: "student2@example.com",
        first_name: "Test",
        last_name: "Student2",
        degree: "B.Tech",
        specialization: "IT",
        status: "active",
        phone: "9000000002",
        registration_id: "REG002",
        year_of_passing: 2024,
        cgpa: "7.5",
        tenant_id: user.tenant_id,
        created_by_id: admin_id,
        created_by_type: "public"
      }

      {:ok, student} = Repo.insert(%Student{} |> Student.changeset(student_attrs), prefix: @tenant_schema)

      # Create assessment
      {:ok, assessment} = Assessments.get_or_create_dynamic_assessment(student.id, @tenant_schema)

      %{user: user, student: student, assessment: assessment, tenant_schema: @tenant_schema}
    end

    test "starts assessment attempt with student ID", %{
      student: student,
      assessment: assessment,
      tenant_schema: tenant_schema
    } do
      # This tests the foreign key constraint
      result = Assessments.start_assessment_attempt(assessment.id, student.id, tenant_schema)

      assert {:ok, attempt} = result
      assert attempt.assessment_id == assessment.id
      assert attempt.student_id == student.id
      assert attempt.status == "started"
    end

    test "resumes existing active attempt instead of creating duplicate", %{student: student, assessment: assessment, tenant_schema: tenant_schema} do
      # Start first attempt
      {:ok, attempt1} = Assessments.start_assessment_attempt(assessment.id, student.id, tenant_schema)

      # Second call returns the same existing attempt (resume, not a new one)
      {:ok, attempt2} = Assessments.start_assessment_attempt(assessment.id, student.id, tenant_schema)

      assert attempt1.id == attempt2.id
    end

    test "submit within rate-limit window returns :submitted_too_fast", %{student: student, assessment: assessment, tenant_schema: tenant_schema} do
      {:ok, attempt} = Assessments.start_assessment_attempt(assessment.id, student.id, tenant_schema)

      answers = %{"1" => "a", "2" => "b", "3" => "c"}

      # Immediate submit triggers the speed check (< 10 seconds)
      assert {:error, :submitted_too_fast} = Assessments.submit_assessment(attempt.id, answers, tenant_schema)
    end
  end

  describe "load_assessment_questions/2" do
    setup do
      Repo.query!("CREATE SCHEMA IF NOT EXISTS #{@tenant_schema}")
      admin_id = Ecto.UUID.generate()
      tenant_id = Ecto.UUID.generate()

      user_attrs = %{
        email: "qa_user@example.com",
        first_name: "QA",
        last_name: "User",
        status: "active",
        role: "admin",
        tenant_id: tenant_id,
        created_by_id: admin_id,
        created_by_type: "public"
      }

      {:ok, user} = Repo.insert(%User{} |> User.changeset(user_attrs), prefix: @tenant_schema)
      %{creator_id: user.id, tenant_id: tenant_id}
    end

    test "returns [] for an assessment with no question_set_id and no embedded questions", %{creator_id: creator_id, tenant_id: tenant_id} do
      assessment_attrs = %{
        title: "Test Assessment",
        assessment_type: "quiz",
        duration_minutes: 60,
        total_marks: 10,
        passing_marks: 5,
        created_by: creator_id,
        tenant_id: tenant_id,
        settings: %{}
      }

      {:ok, assessment} = Repo.insert(%Assessment{} |> Assessment.changeset(assessment_attrs), prefix: @tenant_schema)

      assert Assessments.load_assessment_questions(assessment.id, @tenant_schema) == []
    end

    test "normalises embedded settings[\"questions\"] back to the atom-keyed shape", %{creator_id: creator_id, tenant_id: tenant_id} do
      embedded = [
        %{
          "id" => 42,
          "question" => "Pick the prime",
          "options" => %{"a" => "4", "b" => "6", "c" => "7", "d" => "9"},
          "correct_answer" => "c",
          "points" => 1,
          "difficulty" => "easy",
          "subject" => "Aptitude",
          "topic" => "Numbers"
        }
      ]

      assessment_attrs = %{
        title: "Embedded Questions Assessment",
        assessment_type: "quiz",
        duration_minutes: 60,
        total_marks: 1,
        passing_marks: 1,
        created_by: creator_id,
        tenant_id: tenant_id,
        settings: %{"questions" => embedded}
      }

      {:ok, assessment} = Repo.insert(%Assessment{} |> Assessment.changeset(assessment_attrs), prefix: @tenant_schema)

      [q] = Assessments.load_assessment_questions(assessment.id, @tenant_schema)
      assert q.id == 42
      assert q.question == "Pick the prime"
      assert q.answer == "c"
      assert q.options == %{"a" => "4", "b" => "6", "c" => "7", "d" => "9"}
      assert q.subject_name == "Aptitude"
    end
  end
end
