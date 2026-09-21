defmodule VyaasaCampus.Guardian do
  @moduledoc """
  Guardian module for JWT authentication.
  Handles token creation, verification, and user authentication with caching.
  """

  use Guardian, otp_app: :vyaasa_campus
  require Logger

  alias VyaasaCampus.Auth.AuthServer
  alias VyaasaCampus.Schema.Accounts.User
  alias VyaasaCampus.Schema.Platform.AdminUser
  alias VyaasaCampus.Schema.Students.Student

  @doc """
  Create a token for any user type
  """
  def create_token(user) do
    # Use configured TTL from config (:vyaasa_campus, VyaasaCampus.Guardian)
    case encode_and_sign(user, %{}) do
      {:ok, token, claims} ->
        # Cache the user with the token for 1 hour
        AuthServer.cache_user(token, user, 3600)
        {:ok, token, claims}

      error ->
        error
    end
  end

  @doc """
  Create a token with custom claims
  """
  def create_token(user, claims) do
    # Use configured TTL from config
    case encode_and_sign(user, claims) do
      {:ok, token, full_claims} ->
        # Cache the user with the token for 1 hour
        AuthServer.cache_user(token, user, 3600)
        {:ok, token, full_claims}

      error ->
        error
    end
  end

  @doc """
  Get current user from token with caching
  """
  def current_user(token) do
    case AuthServer.get_user(token) do
      {:hit, user} ->
        {:ok, user}

      {:miss} ->
        handle_missed_cache(token)
    end
  end

  defp handle_missed_cache(token) do
    with {:ok, claims} <- decode_and_verify(token),
         {:ok, resource} <- resource_from_claims(claims) do
      {:ok, claims, resource}
    end
  end

  @doc """
  Logout user - remove from cache
  """
  def logout_user(token) do
    AuthServer.remove_user(token)
    :ok
  end

  @doc """
  Get user type from user struct
  """
  def get_user_type(%AdminUser{}), do: "admin"
  def get_user_type(%User{}), do: "user"
  def get_user_type(%Student{}), do: "student"
  def get_user_type(_), do: "unknown"

  @doc """
  Check if user is admin
  """
  def admin?(%AdminUser{}), do: true
  def admin?(_), do: false

  @doc """
  Check if user is tenant user
  """
  def tenant_user?(%User{}), do: true
  def tenant_user?(_), do: false

  @doc """
  Check if user is student
  """
  def student?(%Student{}), do: true
  def student?(_), do: false

  # Guardian callbacks
  def subject_for_token(user, _claims) do
    case user do
      %AdminUser{} -> {:ok, "AdminUser:#{user.id}"}
      %User{} -> {:ok, "User:#{user.id}"}
      %Student{} -> {:ok, "Student:#{user.id}"}
      _ -> {:error, "Unknown resource type"}
    end
  end

  def resource_from_claims(%{"sub" => "AdminUser:" <> id} = claims) do
    case VyaasaCampus.Repo.get(AdminUser, id, prefix: "public") do
      nil -> {:error, "AdminUser not found"}
      admin_user -> with_session_check(admin_user, claims)
    end
  end

  def resource_from_claims(%{"sub" => "User:" <> id} = claims) do
    tenant_schema = Map.get(claims, "tenant_schema", "public")

    case VyaasaCampus.Repo.get(User, id, prefix: tenant_schema) do
      nil -> {:error, "User not found"}
      user -> with_session_check(user, claims)
    end
  end

  def resource_from_claims(%{"sub" => "Student:" <> id} = claims) do
    tenant_schema = Map.get(claims, "tenant_schema", "public")

    case VyaasaCampus.Repo.get(Student, id, prefix: tenant_schema) do
      nil -> {:error, "Student not found"}
      student -> with_session_check(student, claims)
    end
  end

  def resource_from_claims(_), do: {:error, "Unknown resource type"}

  # Single active session: reject a token whose session id has been superseded by
  # a newer login on another device. Backward-compatible (see Auth.session_current?/2).
  defp with_session_check(user, claims) do
    if VyaasaCampus.Auth.session_current?(user.current_session_id, Map.get(claims, "sid")) do
      {:ok, user}
    else
      {:error, :session_superseded}
    end
  end
end
