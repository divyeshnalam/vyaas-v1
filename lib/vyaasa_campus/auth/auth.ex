defmodule VyaasaCampus.Auth do
  @moduledoc """
  Centralized authentication context for handling login and user management.
  Supports PlatformAdmin, User (tenant), and Student authentication.
  Only students can register - platform admins and tenant users are created by administrators.
  """

  alias Ecto.Changeset
  alias VyaasaCampus.Auth.AuthServer
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Accounts.User
  alias VyaasaCampus.Schema.Platform.AdminUser
  alias VyaasaCampus.Schema.Students.Student
  import VyaasaCampus.Types, only: [student_status_verified: 0, student_status_active: 0]

  @doc "A fresh, opaque session id for single-active-session enforcement."
  def new_session_id, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

  @doc """
  Record `sid` as the user's single active session (call on LOGIN only, not on
  token refresh) and evict that user's other cached tokens, so every other device
  is logged out. Returns `sid`.
  """
  def establish_session(user, sid, tenant_schema \\ "public")

  def establish_session(%AdminUser{} = user, sid, _tenant_schema) do
    user |> Changeset.change(%{current_session_id: sid}) |> Repo.update()
    AuthServer.invalidate_user(user)
    sid
  end

  def establish_session(user, sid, tenant_schema)
      when is_struct(user, User) or is_struct(user, Student) do
    user |> Changeset.change(%{current_session_id: sid}) |> Repo.update(prefix: tenant_schema)
    AuthServer.invalidate_user(user)
    sid
  end

  @doc """
  True unless the token's session id has been superseded by a newer login. Lenient
  for backward compatibility: a nil stored session id (pre-rollout account) or a
  token without a `sid` claim is allowed; only a present-and-different pair fails.
  """
  def session_current?(user_session_id, token_sid) do
    is_nil(user_session_id) or is_nil(token_sid) or user_session_id == token_sid
  end

  # Authenticate platform admin by email and password
  def authenticate_admin(email, password) do
    case Repo.get_by(AdminUser, email: email) do
      nil ->
        {:error, :not_found}

      admin_user ->
        if AdminUser.verify_password(admin_user, password) do
          {:ok, admin_user}
        else
          {:error, :invalid_password}
        end
    end
  end

  # Authenticate tenant user by email and password in a specific tenant schema
  def authenticate_user(email, password, tenant_schema \\ "public") do
    with {:ok, _} <- validate_tenant_schema(tenant_schema),
         {:ok, user} <- find_user_by_email(email, tenant_schema),
         {:ok, _} <- verify_user_password(user, password) do
      {:ok, user}
    end
  end

  # Authenticate student by email and password in a specific tenant schema
  def authenticate_student(email, password, tenant_schema \\ "public") do
    with {:ok, _} <- validate_tenant_schema(tenant_schema),
         {:ok, student} <- find_student_by_email(email, tenant_schema),
         :ok <- ensure_student_verified(student),
         {:ok, student} <- verify_student_password(student, password) do
      # Transparently upgrade legacy high-cost hashes on successful login.
      {:ok, maybe_upgrade_student_hash(student, password, tenant_schema)}
    end
  end

  # Private helper functions for authentication
  defp validate_tenant_schema("public"), do: {:error, :invalid_schema}
  defp validate_tenant_schema(_), do: {:ok, :valid}

  defp find_user_by_email(email, tenant_schema) do
    case Repo.get_by(User, [email: email], prefix: tenant_schema) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp find_student_by_email(email, tenant_schema) do
    case Repo.get_by(Student, [email: email], prefix: tenant_schema) do
      nil -> {:error, :not_found}
      student -> {:ok, student}
    end
  end

  defp ensure_student_verified(%Student{status: status}) do
    if status in [student_status_verified(), student_status_active()] do
      :ok
    else
      {:error, :student_not_verified}
    end
  end

  defp verify_user_password(user, password) do
    if User.verify_password(user, password) do
      {:ok, user}
    else
      {:error, :invalid_password}
    end
  end

  defp verify_student_password(student, password) do
    if Student.verify_password(student, password) do
      {:ok, student}
    else
      {:error, :invalid_password}
    end
  end

  # Re-hash the student's password at the currently-configured bcrypt cost when
  # the stored hash uses a different cost. Best-effort: a failed update just
  # leaves the old hash in place (login still succeeds). See PasswordUpgrade.
  defp maybe_upgrade_student_hash(student, password, tenant_schema) do
    case VyaasaCampus.Auth.PasswordUpgrade.maybe_rehash(student.encrypted_password, password) do
      {:rehash, new_hash} ->
        student
        |> Changeset.change(%{encrypted_password: new_hash})
        |> Repo.update(prefix: tenant_schema)
        |> case do
          {:ok, updated} -> updated
          _ -> student
        end

      :keep ->
        student
    end
  end

  @doc """
  Register a new student (creates student record with all user fields)
  """
  def register_student(attrs, tenant_schema \\ "public") do
    %Student{}
    |> Student.create_changeset(attrs)
    |> Repo.insert(prefix: tenant_schema)
  end

  # Update user's last login timestamp
  def update_last_login(user, tenant_schema \\ "public") do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case user do
      %AdminUser{} ->
        user
        |> Ecto.Changeset.change(%{last_login_at: now})
        |> Repo.update()

      %User{} ->
        user
        |> Ecto.Changeset.change(%{last_login_at: now})
        |> Repo.update(prefix: tenant_schema)

      %Student{} ->
        # For students, update the student's last_login_at directly
        user
        |> Ecto.Changeset.change(%{last_login_at: now})
        |> Repo.update(prefix: tenant_schema)
    end
  end

  # =============================
  # Refresh Token Helpers (per-user table fields)
  # =============================

  def issue_refresh_token(%AdminUser{} = user) do
    ttl_days = String.to_integer(System.get_env("REFRESH_TOKEN_TTL_DAYS") || "30")
    raw = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    hash = hash_refresh_token(raw)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, ttl_days * 24 * 3600, :second)

    {:ok, _} =
      user
      |> Changeset.change(%{refresh_token_hash: hash, refresh_token_expires_at: expires_at})
      |> Repo.update()

    {:ok, raw, expires_at}
  end

  def issue_refresh_token(%User{} = user, tenant_schema) do
    ttl_days = String.to_integer(System.get_env("REFRESH_TOKEN_TTL_DAYS") || "30")
    raw = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    hash = hash_refresh_token(raw)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, ttl_days * 24 * 3600, :second)

    {:ok, _} =
      user
      |> Changeset.change(%{refresh_token_hash: hash, refresh_token_expires_at: expires_at})
      |> Repo.update(prefix: tenant_schema)

    {:ok, raw, expires_at}
  end

  def issue_refresh_token(%Student{} = user, tenant_schema) do
    ttl_days = String.to_integer(System.get_env("REFRESH_TOKEN_TTL_DAYS") || "30")
    raw = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    hash = hash_refresh_token(raw)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, ttl_days * 24 * 3600, :second)

    {:ok, _} =
      user
      |> Changeset.change(%{refresh_token_hash: hash, refresh_token_expires_at: expires_at})
      |> Repo.update(prefix: tenant_schema)

    {:ok, raw, expires_at}
  end

  def verify_and_rotate_refresh_token(%AdminUser{} = user, raw) do
    with true <-
           valid_refresh_token?(user.refresh_token_hash, user.refresh_token_expires_at, raw),
         {:ok, new_raw, exp} <- issue_refresh_token(user) do
      {:ok, new_raw, exp}
    else
      _ -> {:error, :invalid_refresh_token}
    end
  end

  def verify_and_rotate_refresh_token(%User{} = user, raw, tenant_schema) do
    with true <-
           valid_refresh_token?(user.refresh_token_hash, user.refresh_token_expires_at, raw),
         {:ok, new_raw, exp} <- issue_refresh_token(user, tenant_schema) do
      {:ok, new_raw, exp}
    else
      _ -> {:error, :invalid_refresh_token}
    end
  end

  def verify_and_rotate_refresh_token(%Student{} = user, raw, tenant_schema) do
    with true <-
           valid_refresh_token?(user.refresh_token_hash, user.refresh_token_expires_at, raw),
         {:ok, new_raw, exp} <- issue_refresh_token(user, tenant_schema) do
      {:ok, new_raw, exp}
    else
      _ -> {:error, :invalid_refresh_token}
    end
  end

  def revoke_refresh_token(%AdminUser{} = user) do
    user
    |> Changeset.change(%{refresh_token_hash: nil, refresh_token_expires_at: nil})
    |> Repo.update()
  end

  def revoke_refresh_token(%User{} = user, tenant_schema) do
    user
    |> Changeset.change(%{refresh_token_hash: nil, refresh_token_expires_at: nil})
    |> Repo.update(prefix: tenant_schema)
  end

  def revoke_refresh_token(%Student{} = user, tenant_schema) do
    user
    |> Changeset.change(%{refresh_token_hash: nil, refresh_token_expires_at: nil})
    |> Repo.update(prefix: tenant_schema)
  end

  defp valid_refresh_token?(stored_hash, expires_at, raw)
       when is_binary(stored_hash) and not is_nil(expires_at) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt and
      stored_hash == hash_refresh_token(raw)
  end

  defp valid_refresh_token?(_, _, _), do: false

  def hash_refresh_token(raw) do
    salt = System.get_env("REFRESH_TOKEN_SALT") || "dev-refresh-salt"
    :crypto.hash(:sha256, salt <> ":" <> raw) |> Base.encode16(case: :lower)
  end

  # Get user by ID and type
  def get_user_by_id_and_type(id, user_type, tenant_schema \\ "public")
  def get_user_by_id_and_type(id, "admin", _tenant_schema), do: Repo.get(AdminUser, id)

  def get_user_by_id_and_type(id, "user", tenant_schema),
    do: Repo.get(User, id, prefix: tenant_schema)

  def get_user_by_id_and_type(id, "student", tenant_schema),
    do: Repo.get(Student, id, prefix: tenant_schema)

  def get_user_by_id_and_type(_, _, _), do: nil

  # Check if user exists by email
  def user_exists?(email, tenant_schema \\ "public") do
    case tenant_schema do
      "public" ->
        Repo.get_by(AdminUser, email: email) != nil

      _ ->
        Repo.get_by(User, email: email, prefix: tenant_schema) != nil
    end
  end
end
