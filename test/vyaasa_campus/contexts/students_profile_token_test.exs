defmodule VyaasaCampus.Contexts.StudentsProfileTokenTest do
  @moduledoc """
  Covers the profile-completion link being single-use for onboarding:
  `Students.verify_profile_token/2` must reject a token once the student has
  submitted their profile (status `unverified` = ready for verification) or is
  already `verified`/`active`, so documents can't be uploaded again.
  """
  use VyaasaCampus.DataCase

  alias VyaasaCampus.Contexts.Students
  alias VyaasaCampus.Schema.Students.Student

  @tenant_schema "test"

  setup do
    # No FK is enforced on tenant_id in the test schema (mirrors the existing
    # assessments test), so a random tenant id is enough for these inserts.
    %{tenant: %{id: Ecto.UUID.generate()}}
  end

  # Insert a student in `status` that holds a *valid* (non-expired) profile
  # token. The token + status combination is intentionally constructed to
  # exercise the status guard directly.
  defp student_with_token(tenant, status) do
    tenant
    |> insert_student()
    |> Student.generate_profile_token_changeset()
    |> put_change(:status, status)
    |> Repo.update!(prefix: @tenant_schema)
  end

  describe "name normalization" do
    test "normalizes first and last names to capitalized format regardless of input case" do
      attrs = %{
        email: "test.student@example.com",
        first_name: "jOHN",
        last_name: "sMITH",
        phone: "9876543210",
        registration_id: "REG123",
        degree: "B.Tech",
        specialization: "Computer Science",
        year_of_passing: 2026,
        cgpa: 8.7,
        tenant_id: Ecto.UUID.generate(),
        created_by_id: Ecto.UUID.generate(),
        created_by_type: "admin"
      }

      changeset = Student.changeset(%Student{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :first_name) == "John"
      assert Ecto.Changeset.get_change(changeset, :last_name) == "Smith"
    end
  end

  describe "verify_profile_token/2 status guard" do
    test "allows a freshly invited (pending) student with a valid token", %{tenant: tenant} do
      student = student_with_token(tenant, "pending")

      assert {:ok, verified} =
               Students.verify_profile_token(student.profile_token, @tenant_schema)

      assert verified.id == student.id
    end

    test "allows a profile_incomplete student (admin asked them to resubmit)", %{tenant: tenant} do
      student = student_with_token(tenant, "profile_incomplete")

      assert {:ok, _} = Students.verify_profile_token(student.profile_token, @tenant_schema)
    end

    test "rejects once submitted (unverified / ready for verification)", %{tenant: tenant} do
      student = student_with_token(tenant, "unverified")

      assert {:error, :profile_already_submitted} =
               Students.verify_profile_token(student.profile_token, @tenant_schema)
    end

    test "rejects verified and active students", %{tenant: tenant} do
      for status <- ["verified", "active"] do
        student = student_with_token(tenant, status)

        assert {:error, :profile_already_submitted} =
                 Students.verify_profile_token(student.profile_token, @tenant_schema)
      end
    end

    test "returns invalid_token for a token that was cleared on submit", %{tenant: _tenant} do
      assert {:error, :invalid_token} =
               Students.verify_profile_token("no-such-token", @tenant_schema)
    end
  end
end
