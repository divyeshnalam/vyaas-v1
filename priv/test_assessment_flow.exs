# Test script to verify MCQ assessment flow
# Run with: mix run priv/test_assessment_flow.exs

alias VyaasaCampus.Repo
alias VyaasaCampus.Contexts.{Assessments, Students, Tenants}
alias VyaasaCampus.Schema.Students.Student
alias VyaasaCampus.Schema.Accounts.User

IO.puts("\n=== MCQ Assessment Flow Test ===\n")

# Step 1: Get a tenant
IO.puts("Step 1: Finding tenant...")
tenant = Tenants.list_tenants() |> List.first()

if is_nil(tenant) do
  IO.puts("❌ No tenants found. Please create a tenant first.")
  System.halt(1)
end

IO.puts("✅ Found tenant: #{tenant.full_name} (#{tenant.schema_name})")
tenant_schema = tenant.schema_name

# Step 2: Find or create a test student/user
IO.puts("\nStep 2: Finding test user...")

# Try to find an existing student
student =
  case Repo.all(Student, prefix: tenant_schema) |> List.first() do
    nil ->
      IO.puts("⚠️  No students found. Creating test student...")

      # Create test user first
      user_attrs = %{
        email: "test.mcq@example.com",
        first_name: "MCQ",
        last_name: "Tester",
        password_hash: Bcrypt.hash_pwd_salt("password123"),
        status: "active",
        tenant_id: tenant.id,
        role: "student"
      }

      {:ok, user} = %User{}
      |> User.changeset(user_attrs)
      |> Repo.insert(prefix: tenant_schema)

      # Create student linked to user
      student_attrs = %{
        email: "test.mcq@example.com",
        first_name: "MCQ",
        last_name: "Tester",
        degree: "B.Tech",
        specialization: "Computer Science",
        status: "active",
        tenant_id: tenant.id,
        year_of_passing: 2024
      }

      {:ok, student} = %Student{}
      |> Student.changeset(student_attrs)
      |> Repo.insert(prefix: tenant_schema)

      IO.puts("✅ Created test student: #{student.email}")
      student

    found_student ->
      IO.puts("✅ Found existing student: #{found_student.email}")
      found_student
  end

# Step 3: Find corresponding user
IO.puts("\nStep 3: Finding user for student...")
user = Repo.get_by(User, [email: student.email], prefix: tenant_schema)

user = if is_nil(user) do
  # If no user with student email, find any user in the tenant
  IO.puts("⚠️  No user found with student email. Finding first available user...")
  case Repo.all(User, prefix: tenant_schema) |> List.first() do
    nil ->
      IO.puts("❌ No users found in tenant. Please create a user first via web interface.")
      System.halt(1)
    found_user ->
      IO.puts("✅ Using user: #{found_user.email} (ID: #{found_user.id})")
      found_user
  end
else
  IO.puts("✅ Found user: #{user.email} (ID: #{user.id})")
  user
end

# Step 4: Test dynamic assessment creation
IO.puts("\nStep 4: Creating dynamic assessment...")

case Assessments.get_or_create_dynamic_assessment(user.id, tenant_schema) do
  {:ok, assessment} ->
    IO.puts("✅ Assessment created successfully!")
    IO.puts("   Title: #{assessment.title}")
    IO.puts("   Type: #{assessment.assessment_type}")
    IO.puts("   Duration: #{assessment.duration_minutes} minutes")
    IO.puts("   Total Marks: #{assessment.total_marks}")
    IO.puts("   Status: #{assessment.status}")
    IO.puts("   Created By: #{assessment.created_by}")

    # Step 5: Load questions
    IO.puts("\nStep 5: Loading assessment questions...")
    questions = Assessments.load_assessment_questions(assessment.id, tenant_schema)
    IO.puts("✅ Loaded #{length(questions)} questions")

    if length(questions) > 0 do
      first_q = List.first(questions)
      IO.puts("\n   Sample Question:")
      IO.puts("   Q: #{first_q.question}")
      IO.puts("   Difficulty: #{first_q.difficulty_level}")
      IO.puts("   Options: #{inspect(first_q.options)}")
    end

    # Step 6: Clean up any existing attempts for this test
    IO.puts("\nStep 6: Cleaning up any existing attempts...")
    {:ok, assessment_id_bin} = Ecto.UUID.dump(assessment.id)
    {:ok, student_id_bin} = Ecto.UUID.dump(student.id)
    Repo.query!("DELETE FROM #{tenant_schema}.assessment_attempts WHERE assessment_id = $1 AND student_id = $2",
                [assessment_id_bin, student_id_bin])
    IO.puts("✅ Cleaned up existing attempts")

    # Step 7: Test starting an attempt
    IO.puts("\nStep 7: Starting assessment attempt...")

    case Assessments.start_assessment_attempt(assessment.id, student.id, tenant_schema) do
      {:ok, attempt} ->
        IO.puts("✅ Attempt started successfully!")
        IO.puts("   Attempt ID: #{attempt.id}")
        IO.puts("   Status: #{attempt.status}")
        IO.puts("   Started At: #{attempt.started_at}")

        # Step 8: Test submitting answers
        IO.puts("\nStep 8: Submitting test answers...")

        test_answers = %{
          "1" => "b",
          "2" => "b",
          "3" => "b"
        }

        case Assessments.submit_assessment(attempt.id, test_answers, tenant_schema) do
          {:ok, submitted_attempt} ->
            IO.puts("✅ Assessment submitted successfully!")
            IO.puts("   Status: #{submitted_attempt.status}")
            IO.puts("   Score: #{submitted_attempt.score || 0}")
            IO.puts("   Percentage: #{submitted_attempt.percentage || 0}%")

            IO.puts("\n🎉 All tests passed! MCQ flow is working correctly.")

          {:error, reason} ->
            IO.puts("❌ Failed to submit assessment: #{inspect(reason)}")
        end

      {:error, :active_attempt_exists} ->
        IO.puts("⚠️  Active attempt already exists. This is expected if running test multiple times.")
        IO.puts("   To reset, delete existing attempts from the database.")

      {:error, reason} ->
        IO.puts("❌ Failed to start attempt: #{inspect(reason)}")
        IO.puts("   This might be a foreign key constraint error.")
        IO.puts("   Check that student.id (#{student.id}) exists in students table.")
    end

  {:error, reason} ->
    IO.puts("❌ Failed to create assessment: #{inspect(reason)}")
    IO.puts("\n   Possible issues:")
    IO.puts("   - created_by foreign key (user #{user.id} not in users table)")
    IO.puts("   - tenant_id foreign key")
    IO.puts("   - SQL function errors")
end

IO.puts("\n=== Test Complete ===\n")
