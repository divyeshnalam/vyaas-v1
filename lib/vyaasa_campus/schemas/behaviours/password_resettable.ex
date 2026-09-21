defmodule VyaasaCampus.Schemas.Behaviours.PasswordResettable do
  @moduledoc """
  Behaviour for schemas that support password reset functionality.
  Ensures consistent interface across all user types (AdminUser, User, Student).
  """

  @doc """
  Generate a password reset token for the user.
  """
  @callback generate_password_reset_token(struct()) :: Ecto.Changeset.t()

  @doc """
  Clear the password reset token from the user.
  """
  @callback clear_password_reset_token(struct()) :: Ecto.Changeset.t()

  @doc """
  Check if the password reset token is valid (not expired).
  """
  @callback password_reset_token_valid?(struct()) :: boolean()

  @doc """
  Verify password using bcrypt.
  """
  @callback verify_password(struct(), String.t()) :: boolean()

  @doc """
  Update password with proper hashing.
  """
  @callback password_changeset(struct(), map()) :: Ecto.Changeset.t()

  @doc """
  Set temporary password for new users.
  """
  @callback set_temp_password(struct(), String.t()) :: Ecto.Changeset.t()

  @doc """
  Clear temporary password after first login.
  """
  @callback clear_temp_password(struct()) :: Ecto.Changeset.t()

  @doc """
  Generate a temporary password.
  """
  @callback generate_temp_password() :: String.t()
end
