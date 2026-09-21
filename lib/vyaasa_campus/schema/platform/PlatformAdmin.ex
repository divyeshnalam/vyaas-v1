defmodule VyaasaCampus.Schema.Platform.AdminUser do
  @moduledoc """
  Platform administrator schema and changeset functions.

  Defines the platform admin entity with capabilities to:
  - Manage multiple tenants across the platform
  - Create and configure tenant organizations
  - Access system-wide administrative functions
  - Oversee platform-level operations and settings
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset
  import VyaasaCampus.Types

  @derive {Jason.Encoder,
           only: [
             :id,
             :email,
             :first_name,
             :last_name,
             :role,
             :status,
             :last_login_at,
             :inserted_at,
             :updated_at
           ]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "platform_admins" do
    field :email, :string
    field :encrypted_password, :string
    field :password, :string, virtual: true
    field :first_name, :string
    field :last_name, :string
    field :role, :string
    field :status, :string, default: user_status_active()
    field :last_login_at, :utc_datetime
    field :password_reset_token, :string
    field :password_reset_sent_at, :utc_datetime
    field :metadata, :map, default: %{}
    # Refresh token fields (store only hash and expiry)
    field :refresh_token_hash, :string
    field :current_session_id, :string
    field :refresh_token_expires_at, :utc_datetime

    timestamps()
  end

  def changeset(admin_user, attrs) do
    admin_user
    |> cast(attrs, [
      :email,
      :encrypted_password,
      :first_name,
      :last_name,
      :role,
      :status,
      :last_login_at,
      :metadata,
      :refresh_token_hash,
      :refresh_token_expires_at
    ])
    |> validate_required([:email, :first_name, :last_name, :role])
    |> validate_inclusion(:status, valid_user_statuses())
    |> validate_inclusion(:role, valid_user_roles())
    |> validate_length(:email, max: max_email_length())
    |> validate_length(:first_name, max: max_name_length())
    |> validate_length(:last_name, max: max_name_length())
    |> unique_constraint(:email)
  end

  def create_changeset(admin_user, attrs) do
    admin_user
    |> cast(attrs, [
      :email,
      :password,
      :first_name,
      :last_name,
      :role,
      :status,
      :metadata,
      :refresh_token_hash,
      :refresh_token_expires_at
    ])
    |> validate_required([:email, :password, :first_name, :last_name, :role])
    |> validate_inclusion(:status, valid_user_statuses())
    |> validate_inclusion(:role, valid_user_roles())
    |> validate_length(:email, max: max_email_length())
    |> validate_length(:first_name, max: max_name_length())
    |> validate_length(:last_name, max: max_name_length())
    |> validate_length(:password, min: min_password_length(), max: max_password_length())
    # Always superadmin
    |> put_change(:role, role_superadmin())
    |> put_change(:encrypted_password, Bcrypt.hash_pwd_salt(attrs.password))
    |> unique_constraint(:email)
  end

  def verify_password(admin_user, password) do
    Bcrypt.verify_pass(password, admin_user.encrypted_password)
  end

  @doc """
  Generate password reset token for platform admin
  """
  def generate_password_reset_token(admin_user) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    admin_user
    |> change(%{
      password_reset_token: token,
      password_reset_sent_at: now
    })
  end

  @doc """
  Clear password reset token for platform admin
  """
  def clear_password_reset_token(admin_user) do
    admin_user
    |> change(%{
      password_reset_token: nil,
      password_reset_sent_at: nil
    })
  end

  @doc """
  Check if password reset token is valid for platform admin
  """
  def password_reset_token_valid?(admin_user) do
    case admin_user.password_reset_sent_at do
      nil ->
        false

      sent_at ->
        # Token expires after configured hours
        DateTime.diff(DateTime.utc_now(), sent_at, :hour) < password_reset_token_expiry()
    end
  end

  @doc """
  Password changeset for platform admin
  """
  def password_changeset(admin_user, attrs) do
    password = attrs[:password] || attrs["password"]

    admin_user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: min_password_length(), max: max_password_length())
    |> put_change(:encrypted_password, Bcrypt.hash_pwd_salt(password))
  end
end
