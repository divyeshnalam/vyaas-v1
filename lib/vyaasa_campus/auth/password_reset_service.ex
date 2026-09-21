defmodule VyaasaCampus.Auth.PasswordResetService do
  @moduledoc """
  Unified password reset service for VyaasaCampus application.

  This module consolidates all password reset functionality across different user types
  (Platform Admin, Tenant User, Student) into a single, well-organized service.

  Following Phoenix 1.8 best practices for service organization and eliminating
  code duplication across contexts.
  """

  require Logger
  import Ecto.Query, warn: false

  alias VyaasaCampus.Mail.EmailOrchestrator
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Accounts.User
  alias VyaasaCampus.Schema.Platform.AdminUser
  alias VyaasaCampus.Schema.Students.Student
  import VyaasaCampus.Types, only: [student_status_verified: 0, student_status_active: 0]

  # ============================================================================
  # PUBLIC API - UNIFIED PASSWORD RESET OPERATIONS
  # ============================================================================

  @doc """
  Request password reset for any user type.
  Automatically detects user type and handles accordingly.

  ## Parameters
  - email: User's email address
  - tenant_alias: Optional tenant alias for tenant users/students
  - schema_prefix: Database schema prefix (defaults to "public")

  ## Returns
  - {:ok, user} - Password reset email sent successfully
  - {:error, :user_not_found} - No user found with the email
  - {:error, :student_not_verified} - Student has not been verified by an admin
  - {:error, changeset} - Database error during token generation
  """
  def request_password_reset(email, tenant_alias \\ nil, schema_prefix \\ "public") do
    with {:ok, user} <- find_user_by_email(email, tenant_alias, schema_prefix),
         :ok <- ensure_password_reset_allowed(user),
         {:ok, updated_user, _raw_token} <- generate_reset_token(user, tenant_alias, schema_prefix) do
      # Send password reset email
      case EmailOrchestrator.send_password_reset_email(updated_user, tenant_alias) do
        {:ok, _} ->
          Logger.info("Password reset email sent to: #{email}")
          {:ok, updated_user}

        {:error, reason} ->
          Logger.error("Failed to send password reset email to #{email}: #{inspect(reason)}")
          {:error, :email_send_failed}
      end
    end
  end

  @doc """
  Reset password using token for any user type.
  Automatically detects user type from token lookup.

  ## Parameters
  - token: Password reset token
  - new_password: New password to set
  - tenant_alias: Optional tenant alias
  - schema_prefix: Database schema prefix (defaults to "public")

  ## Returns
  - {:ok, user} - Password reset successfully
  - {:error, :invalid_token} - Token not found or invalid
  - {:error, :token_expired} - Token has expired
  - {:error, :student_not_verified} - Student has not been verified by an admin
  - {:error, changeset} - Database error during password update
  """
  def reset_password_with_token(token, new_password, tenant_alias \\ nil, schema_prefix \\ "public") do
    with {:ok, user} <- find_user_by_token(token, tenant_alias, schema_prefix),
         :ok <- ensure_password_reset_allowed(user),
         :ok <- validate_token(user) do
      update_password(user, new_password, tenant_alias, schema_prefix)
    end
  end

  @doc """
  Clear temporary password for a user by ID.

  ## Parameters
  - user_id: User ID
  - tenant_alias: Optional tenant alias
  - schema_prefix: Database schema prefix (defaults to "public")

  ## Returns
  - {:ok, user} - Temporary password cleared successfully
  - {:error, :user_not_found} - User not found
  - {:error, changeset} - Database error during update
  """
  def clear_temp_password(user_id, tenant_alias \\ nil, schema_prefix \\ "public") do
    with {:ok, user} <- find_user_by_id(user_id, tenant_alias, schema_prefix) do
      case user do
        %AdminUser{} ->
          # AdminUser doesn't have temp_password field
          {:ok, user}

        %User{} ->
          user
          |> User.clear_temp_password()
          |> Repo.update(prefix: schema_prefix)

        %Student{} ->
          user
          |> Student.clear_temp_password()
          |> Repo.update(prefix: schema_prefix)
      end
    end
  end

  @doc """
  Reset password in auto mode (for users with temporary passwords).
  Updates password and clears temporary password field.

  ## Parameters
  - user: User struct
  - new_password: New password to set
  - tenant_alias: Optional tenant alias
  - schema_prefix: Database schema prefix (defaults to "public")

  ## Returns
  - {:ok, user} - Password updated successfully
  - {:error, changeset} - Database error during update
  """
  def reset_password_auto_mode(user, new_password, _tenant_alias \\ nil, schema_prefix \\ "public") do
    case user do
      %AdminUser{} ->
        user
        |> AdminUser.password_changeset(%{password: new_password})
        |> Repo.update(prefix: schema_prefix)

      %User{} ->
        user
        |> User.password_changeset(%{password: new_password})
        |> User.clear_temp_password()
        |> Repo.update(prefix: schema_prefix)

      %Student{} ->
        user
        |> Student.password_changeset(%{password: new_password})
        |> Student.clear_temp_password()
        |> Repo.update(prefix: schema_prefix)
    end
  end

  @doc """
  Change password for an authenticated user (any type).
  Verifies the current password before updating.

  ## Parameters
  - user: User struct (%AdminUser{}, %User{}, or %Student{})
  - current_password: Current password for verification
  - new_password: New password to set
  - schema_prefix: Database schema prefix (defaults to "public")

  ## Returns
  - {:ok, user} - Password changed successfully
  - {:error, :invalid_current_password} - Current password is wrong
  - {:error, changeset} - Validation/database error
  """
  def change_password(user, current_password, new_password, schema_prefix \\ "public") do
    verified? =
      case user do
        %AdminUser{} -> AdminUser.verify_password(user, current_password)
        %User{} -> User.verify_password(user, current_password)
        %Student{} -> Student.verify_password(user, current_password)
      end

    if verified? do
      case user do
        %AdminUser{} ->
          user
          |> AdminUser.password_changeset(%{password: new_password})
          |> Repo.update(prefix: "public")

        %User{} ->
          user
          |> User.password_changeset(%{password: new_password})
          |> Repo.update(prefix: schema_prefix)

        %Student{} ->
          user
          |> Student.password_changeset(%{password: new_password})
          |> Repo.update(prefix: schema_prefix)
      end
    else
      {:error, :invalid_current_password}
    end
  end

  # ============================================================================
  # PRIVATE HELPER FUNCTIONS
  # ============================================================================

  defp find_user_by_email(email, tenant_alias, schema_prefix) do
    if is_nil(tenant_alias) and schema_prefix == "public" do
      find_admin_user_by_email(email)
    else
      find_tenant_user_by_email(email, schema_prefix)
    end
  end

  defp find_admin_user_by_email(email) do
    case Repo.get_by(AdminUser, [email: email], prefix: "public") do
      nil -> {:error, :user_not_found}
      admin_user -> {:ok, admin_user}
    end
  end

  defp find_tenant_user_by_email(email, schema_prefix) do
    case Repo.get_by(User, [email: email], prefix: schema_prefix) do
      nil -> find_student_by_email(email, schema_prefix)
      user -> {:ok, user}
    end
  end

  defp find_student_by_email(email, schema_prefix) do
    case Repo.get_by(Student, [email: email], prefix: schema_prefix) do
      nil -> {:error, :user_not_found}
      student -> {:ok, student}
    end
  end

  defp find_user_by_id(user_id, tenant_alias, schema_prefix) do
    if is_nil(tenant_alias) and schema_prefix == "public" do
      find_admin_user_by_id(user_id)
    else
      find_tenant_user_by_id(user_id, schema_prefix)
    end
  end

  defp find_admin_user_by_id(user_id) do
    case Repo.get(AdminUser, user_id, prefix: "public") do
      nil -> {:error, :user_not_found}
      admin_user -> {:ok, admin_user}
    end
  end

  defp find_tenant_user_by_id(user_id, schema_prefix) do
    case Repo.get(User, user_id, prefix: schema_prefix) do
      nil -> find_student_by_id(user_id, schema_prefix)
      user -> {:ok, user}
    end
  end

  defp find_student_by_id(user_id, schema_prefix) do
    case Repo.get(Student, user_id, prefix: schema_prefix) do
      nil -> {:error, :user_not_found}
      student -> {:ok, student}
    end
  end

  defp find_user_by_token(token, tenant_alias, schema_prefix) do
    if is_nil(tenant_alias) and schema_prefix == "public" do
      find_admin_user_by_token(token)
    else
      find_tenant_user_by_token(token, schema_prefix)
    end
  end

  defp find_admin_user_by_token(token) do
    case AdminUser
         |> where(password_reset_token: ^token)
         |> Repo.one(prefix: "public") do
      nil -> {:error, :invalid_token}
      admin_user -> {:ok, admin_user}
    end
  end

  defp find_tenant_user_by_token(token, schema_prefix) do
    case User
         |> where(password_reset_token: ^token)
         |> Repo.one(prefix: schema_prefix) do
      nil -> find_student_by_token(token, schema_prefix)
      user -> {:ok, user}
    end
  end

  defp find_student_by_token(token, schema_prefix) do
    case Student
         |> where(password_reset_token: ^token)
         |> Repo.one(prefix: schema_prefix) do
      nil -> {:error, :invalid_token}
      student -> {:ok, student}
    end
  end

  defp generate_reset_token(user, _tenant_alias, schema_prefix) do
    case user do
      %AdminUser{} -> generate_admin_reset_token(user)
      %User{} -> generate_user_reset_token(user, schema_prefix)
      %Student{} -> generate_student_reset_token(user, schema_prefix)
    end
  end

  defp ensure_password_reset_allowed(%Student{status: status}) do
    if status in [student_status_verified(), student_status_active()] do
      :ok
    else
      {:error, :student_not_verified}
    end
  end

  defp ensure_password_reset_allowed(_user), do: :ok

  defp generate_admin_reset_token(user) do
    case user
         |> AdminUser.generate_password_reset_token()
         |> Repo.update(prefix: "public") do
      {:ok, updated_user} -> {:ok, updated_user, updated_user.password_reset_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp generate_user_reset_token(user, schema_prefix) do
    case user
         |> User.generate_password_reset_token()
         |> Repo.update(prefix: schema_prefix) do
      {:ok, updated_user} -> {:ok, updated_user, updated_user.password_reset_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp generate_student_reset_token(user, schema_prefix) do
    case user
         |> Student.generate_password_reset_token()
         |> Repo.update(prefix: schema_prefix) do
      {:ok, updated_user} -> {:ok, updated_user, updated_user.password_reset_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp validate_token(user) do
    case user do
      %AdminUser{} ->
        if AdminUser.password_reset_token_valid?(user), do: :ok, else: {:error, :token_expired}

      %User{} ->
        if User.password_reset_token_valid?(user), do: :ok, else: {:error, :token_expired}

      %Student{} ->
        if Student.password_reset_token_valid?(user), do: :ok, else: {:error, :token_expired}
    end
  end

  defp update_password(user, new_password, _tenant_alias, schema_prefix) do
    case user do
      %AdminUser{} ->
        user
        |> AdminUser.password_changeset(%{password: new_password})
        |> AdminUser.clear_password_reset_token()
        |> Repo.update(prefix: "public")

      %User{} ->
        user
        |> User.password_changeset(%{password: new_password})
        |> User.clear_password_reset_token()
        |> Repo.update(prefix: schema_prefix)

      %Student{} ->
        user
        |> Student.password_changeset(%{password: new_password})
        |> Student.clear_password_reset_token()
        |> Repo.update(prefix: schema_prefix)
    end
  end
end
