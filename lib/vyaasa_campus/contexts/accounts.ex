defmodule VyaasaCampus.Contexts.Accounts do
  @moduledoc """
  The Accounts context for managing users, roles, and permissions within a tenant.
  All creation/assignment functions require both *_by_id and *_by_type for auditability.
  *_by_type must be either "public" or "tenant".
  excpect for student creation we are using the Students context
  """

  import Ecto.Query, warn: false
  import VyaasaCampus.Types
  require Logger
  alias VyaasaCampus.Auth.PasswordResetService
  alias VyaasaCampus.Mail.EmailOrchestrator
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Accounts.{Role, User, UserRole}
  alias VyaasaCampus.Schema.Platform.AdminUser

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  @doc """
  List all users in a tenant
  """
  def list_users(prefix) do
    User
    |> Repo.all(prefix: prefix)
    |> Repo.preload([:roles], prefix: prefix)
  end

  @doc """
  Get a user by id in a tenant
  """
  def get_user!(id, prefix) do
    User
    |> Repo.get!(id, prefix: prefix)
    |> Repo.preload([:roles], prefix: prefix)
  end

  @doc """
  Create a user with password in a tenant. Requires password in attrs.
  """
  def create_user_with_password(attrs, prefix) do
    safe_attrs = safe_atom_conversion(attrs)

    case %User{}
         |> User.changeset(safe_attrs)
         |> User.password_changeset(safe_attrs)
         |> Repo.insert(prefix: prefix) do
      {:ok, user} ->
        Logger.info("User created with password: #{user.email}")
        {:ok, user}

      {:error, changeset} ->
        Logger.error("Failed to create user with password: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Create a user with temporary password (welcome email will be sent when role is assigned)
  """
  def create_user_with_temp_password(attrs, _tenant_alias, prefix) do
    safe_attrs = safe_atom_conversion(attrs)
    temp_password = User.generate_temp_password()

    case %User{}
         |> User.changeset(safe_attrs)
         |> User.password_changeset(%{password: temp_password})
         |> User.set_temp_password(temp_password)
         |> Repo.insert(prefix: prefix) do
      {:ok, user} ->
        Logger.info("User created with temp password: #{user.email}")
        # Welcome email will be sent when role is assigned
        {:ok, user}

      {:error, changeset} ->
        Logger.error("Failed to create user with temp password: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # ============================================================================
  # ROLE MANAGEMENT
  # ============================================================================

  @doc """
  Create a role in a tenant. Requires created_by_id and created_by_type in attrs.
  """
  def create_role(attrs, prefix) do
    safe_attrs = safe_atom_conversion(attrs)

    case %Role{}
         |> Role.changeset(safe_attrs)
         |> Repo.insert(prefix: prefix) do
      {:ok, role} ->
        Logger.info("Role created: #{role.name}")
        {:ok, role}

      {:error, changeset} ->
        Logger.error("Failed to create role: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  List all roles in a tenant
  """
  def list_roles(prefix) do
    Role
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Get a role by id in a tenant
  """
  def get_role!(id, prefix) do
    Role
    |> Repo.get!(id, prefix: prefix)
  end

  # ============================================================================
  # USER-ROLE ASSIGNMENT
  # ============================================================================

  @doc """
  List all user-role assignments in a tenant
  """
  def list_user_roles(prefix) do
    UserRole
    |> Repo.all(prefix: prefix)
    |> Repo.preload([:user, :role], prefix: prefix)
  end

  @doc """
  Assign a role to a user in a tenant. Requires assigned_by_id and assigned_by_type.
  """
  def assign_role(user_id, role_id, assigned_by_id, assigned_by_type, prefix, tenant_alias \\ nil) do
    attrs_before_conversion = %{
      user_id: user_id,
      role_id: role_id,
      assigned_by_id: assigned_by_id,
      assigned_by_type: assigned_by_type,
      assigned_at: DateTime.utc_now()
    }

    with {:ok, user_role} <- create_user_role_assignment(attrs_before_conversion, prefix),
         :ok <- handle_welcome_email(user_id, role_id, assigned_by_id, assigned_by_type, tenant_alias, prefix) do
      {:ok, user_role}
    else
      {:error, changeset} when is_map(changeset) ->
        Logger.error("Failed to assign role: #{inspect(changeset.errors)}")
        {:error, changeset}

      error ->
        error
    end
  end

  defp handle_welcome_email(user_id, role_id, assigned_by_id, assigned_by_type, tenant_alias, prefix) do
    case get_user_for_welcome_email(user_id, prefix) do
      {:ok, user} ->
        case send_welcome_email_after_assignment(
               user,
               role_id,
               assigned_by_id,
               assigned_by_type,
               tenant_alias,
               prefix
             ) do
          {:ok, _} -> :ok
        end

      {:error, :user_not_found} ->
        Logger.warning("User not found for welcome email, but role assignment successful")
        :ok
    end
  end

  defp create_user_role_assignment(attrs, prefix) do
    %UserRole{}
    |> UserRole.changeset(attrs)
    |> Repo.insert(prefix: prefix)
    |> case do
      {:ok, user_role} ->
        Logger.info("Role assigned: user_id=#{attrs.user_id}, role_id=#{attrs.role_id}")
        {:ok, user_role}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp get_user_for_welcome_email(user_id, prefix) do
    case get_user!(user_id, prefix) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp send_welcome_email_after_assignment(user, role_id, assigned_by_id, assigned_by_type, tenant_alias, prefix) do
    role = get_role!(role_id, prefix)
    assigner = get_assigner_details(assigned_by_id, assigned_by_type, prefix)

    Logger.info("About to send welcome email with role to: #{user.email}")
    Logger.info("Role: #{inspect(role)}")
    Logger.info("Assigner: #{inspect(assigner)}")
    Logger.info("Tenant alias: #{inspect(tenant_alias)}")
    Logger.info("User temp_password: #{inspect(user.temp_password)}")

    case EmailOrchestrator.send_welcome_email_with_role(user, role, assigner, tenant_alias) do
      {:ok, :email_sent} ->
        Logger.info("Welcome email sent successfully to: #{user.email}")
        {:ok, :email_sent}

      {:error, reason} ->
        Logger.error("Failed to send welcome email: #{inspect(reason)}")
        # Still return success since role assignment succeeded
        {:ok, :email_failed}
    end
  end

  # ============================================================================
  # PASSWORD RESET FUNCTIONS
  # ============================================================================

  @doc """
  Get user by email in a tenant
  """
  def get_user_by_email(email, prefix) do
    import Ecto.Query

    User
    |> where(email: ^email)
    |> Repo.one(prefix: prefix)
  end

  @doc """
  Request password reset for a user.
  Delegates to the unified PasswordResetService.
  """
  def request_password_reset(email, tenant_alias, prefix) do
    PasswordResetService.request_password_reset(email, tenant_alias, prefix)
  end

  @doc """
  Reset user password using token.
  Delegates to the unified PasswordResetService.
  """
  def reset_password_with_token(token, new_password, prefix) do
    PasswordResetService.reset_password_with_token(token, new_password, nil, prefix)
  end

  @doc """
  Clear temporary password after first login
  """
  def clear_temp_password(user_id, prefix) do
    case Repo.get(User, user_id, prefix: prefix) do
      nil ->
        {:error, :user_not_found}

      user ->
        user
        |> User.clear_temp_password()
        |> Repo.update(prefix: prefix)
        |> case do
          {:ok, updated_user} ->
            Logger.info("Temporary password cleared for user: #{updated_user.email}")
            {:ok, updated_user}

          {:error, changeset} ->
            Logger.error("Failed to clear temp password: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end

  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================

  defp get_assigner_details(assigner_id, assigner_type, prefix) do
    case assigner_type do
      "public" ->
        # Platform admin
        case Repo.get(AdminUser, assigner_id) do
          nil -> %{name: "Unknown Admin", email: "unknown@vyaasa.com"}
          admin -> %{name: "#{admin.first_name} #{admin.last_name}", email: admin.email}
        end

      "tenant" ->
        # Tenant user - need to use the correct schema prefix
        case Repo.get(User, assigner_id, prefix: prefix) do
          nil -> %{name: "Unknown User", email: "unknown@tenant.com"}
          user -> %{name: "#{user.first_name} #{user.last_name}", email: user.email}
        end

      _ ->
        %{name: "Unknown", email: "unknown@vyaasa.com"}
    end
  end

  # ============================================================================
  # USER UPDATE FUNCTIONS
  # ============================================================================

  @doc """
  Update a user's profile
  """
  def update_user(id, attrs, prefix) do
    case get_user!(id, prefix) do
      nil ->
        {:error, :user_not_found}

      user ->
        safe_attrs = safe_atom_conversion(attrs)

        user
        |> User.changeset(safe_attrs)
        |> Repo.update(prefix: prefix)
        |> case do
          {:ok, updated_user} ->
            Logger.info("User updated: #{updated_user.email}")
            {:ok, updated_user}

          {:error, changeset} ->
            Logger.error("Failed to update user: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end

  @doc """
  Delete a user
  """
  def delete_user(id, prefix) do
    case get_user!(id, prefix) do
      nil ->
        {:error, :user_not_found}

      user ->
        Repo.delete(user, prefix: prefix)
        |> case do
          {:ok, deleted_user} ->
            Logger.info("User deleted: #{deleted_user.email}")
            {:ok, deleted_user}

          {:error, changeset} ->
            Logger.error("Failed to delete user: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end
end
