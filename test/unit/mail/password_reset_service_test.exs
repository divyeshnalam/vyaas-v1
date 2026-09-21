defmodule VyaasaCampus.Auth.PasswordResetServiceTest do
  @moduledoc """
  Tests for the password reset service functionality.
  """

  use VyaasaCampus.DataCase, async: false
  alias VyaasaCampus.Auth.PasswordResetService
  alias VyaasaCampus.Schema.Students.Student

  # ============================================================================
  # PASSWORD RESET SERVICE TESTS
  # ============================================================================

  describe "password reset service" do
    @tag :shared_data
    test "request_reset/3 for admin user" do
      # Create an admin user using helper
      admin = insert_admin_user(%{email: "admin@test.com"})

      # Test password reset request
      assert {:ok, _} = PasswordResetService.request_password_reset("admin@test.com", nil, "public")

      # Verify token was set
      updated_admin = VyaasaCampus.Repo.get(VyaasaCampus.Schema.Platform.AdminUser, admin.id, prefix: "public")
      assert updated_admin.password_reset_token != nil
      assert updated_admin.password_reset_sent_at != nil
    end

    @tag :shared_data
    test "request_reset/3 for tenant user" do
      # Create tenant first
      tenant = insert_tenant()

      # Create a tenant user using helper
      user = insert_user(tenant, %{email: "user@test.com"})

      # Test password reset request
      assert {:ok, _} = PasswordResetService.request_password_reset("user@test.com", "test", "test")

      # Verify token was set
      updated_user = VyaasaCampus.Repo.get(VyaasaCampus.Schema.Accounts.User, user.id, prefix: "test")
      assert updated_user.password_reset_token != nil
      assert updated_user.password_reset_sent_at != nil
    end

    @tag :shared_data
    test "request_reset/3 for student" do
      # Create tenant first
      tenant = insert_tenant()

      # Create a verified student using helper
      student = insert_active_student(tenant, %{email: "student@test.com"})

      # Test password reset request
      assert {:ok, _} = PasswordResetService.request_password_reset("student@test.com", "test", "test")

      # Verify token was set
      updated_student = VyaasaCampus.Repo.get(VyaasaCampus.Schema.Students.Student, student.id, prefix: "test")
      assert updated_student.password_reset_token != nil
      assert updated_student.password_reset_sent_at != nil
    end

    @tag :shared_data
    test "reset_password/4 for admin user" do
      # Create an admin user using helper
      admin = insert_admin_user(%{email: "admin@test.com"})

      token = "test_token_123"

      _admin2 =
        Ecto.Changeset.change(admin, %{
          password_reset_token: token,
          password_reset_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!(prefix: "public")

      # Test password reset
      assert {:ok, updated_admin} =
               PasswordResetService.reset_password_with_token(
                 "test_token_123",
                 "newpassword123",
                 nil,
                 "public"
               )

      assert updated_admin.password_reset_token == nil
      assert updated_admin.password_reset_sent_at == nil
    end

    @tag :shared_data
    test "reset_password/4 for tenant user" do
      # Create tenant first
      tenant = insert_tenant()

      # Create a tenant user using helper
      user = insert_user(tenant, %{email: "user@test.com"})

      token = "test_token_123"

      _user2 =
        Ecto.Changeset.change(user, %{
          password_reset_token: token,
          password_reset_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!(prefix: "test")

      # Test password reset
      assert {:ok, updated_user} =
               PasswordResetService.reset_password_with_token(
                 "test_token_123",
                 "newpassword123",
                 "test",
                 "test"
               )

      assert updated_user.password_reset_token == nil
      assert updated_user.password_reset_sent_at == nil
    end

    @tag :shared_data
    test "reset_password/4 for student" do
      # Create tenant first
      tenant = insert_tenant()

      # Create a verified student using helper
      student = insert_active_student(tenant, %{email: "student@test.com"})

      token = "test_token_123"

      _student2 =
        Ecto.Changeset.change(student, %{
          password_reset_token: token,
          password_reset_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!(prefix: "test")

      # Test password reset
      assert {:ok, updated_student} =
               PasswordResetService.reset_password_with_token(
                 "test_token_123",
                 "newpassword123",
                 "test",
                 "test"
               )

      assert updated_student.password_reset_token == nil
      assert updated_student.password_reset_sent_at == nil
    end

    @tag :shared_data
    test "request_reset/3 does not send reset token for unverified student" do
      tenant = insert_tenant()
      student = insert_student(tenant, %{email: "unverified_student@test.com", status: "unverified"})

      assert {:error, :student_not_verified} =
               PasswordResetService.request_password_reset(
                 "unverified_student@test.com",
                 "test",
                 "test"
               )

      updated_student = Repo.get(Student, student.id, prefix: "test")
      assert updated_student.password_reset_token == nil
      assert updated_student.password_reset_sent_at == nil
    end

    @tag :shared_data
    test "reset_password/4 rejects existing token for unverified student" do
      tenant = insert_tenant()
      student = insert_student(tenant, %{email: "unverified_token_student@test.com", status: "unverified"})

      token = "test_token_123"

      _student2 =
        Ecto.Changeset.change(student, %{
          password_reset_token: token,
          password_reset_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!(prefix: "test")

      assert {:error, :student_not_verified} =
               PasswordResetService.reset_password_with_token(
                 token,
                 "newpassword123",
                 "test",
                 "test"
               )

      updated_student = Repo.get(Student, student.id, prefix: "test")
      assert updated_student.password_reset_token == token
      assert updated_student.password_reset_sent_at != nil
    end

    @tag :shared_data
    test "password reset service returns error for invalid token" do
      # Create tenant first
      _tenant = insert_tenant()

      assert {:error, :invalid_token} =
               PasswordResetService.reset_password_with_token(
                 "invalid_token",
                 "newpassword123",
                 "test",
                 "test"
               )
    end

    @tag :shared_data
    test "password reset service returns error for non-existent user" do
      # Create tenant first
      _tenant = insert_tenant()

      assert {:error, :user_not_found} =
               PasswordResetService.request_password_reset("nonexistent@test.com", "test", "test")
    end
  end
end
