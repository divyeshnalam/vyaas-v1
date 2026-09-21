defmodule VyaasaCampus.Schema.Accounts.User do
  @moduledoc """
  User account schema and changeset functions.

  Defines the user entity for tenant-scoped user management including:
  - Authentication and authorization
  - Role-based access control
  - Password management and reset functionality
  - Multi-tenant user isolation
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset
  import VyaasaCampus.Types

  @behaviour VyaasaCampus.Schemas.Behaviours.PasswordResettable

  # Jason.Encoder derive for safe JSON serialization, including creator info
  @derive {Jason.Encoder,
           only: [
             :id,
             :email,
             :first_name,
             :middle_name,
             :last_name,
             :phone,
             :role,
             :status,
             :email_verified_at,
             :last_login_at,
             :metadata,
             :inserted_at,
             :updated_at,
             :created_by_id,
             :created_by_type,
             :tenant_id
           ]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :encrypted_password, :string
    field :password, :string, virtual: true
    field :first_name, :string
    field :middle_name, :string
    field :last_name, :string
    field :phone, :string
    field :role, :string
    field :status, :string, default: user_status_pending()
    field :email_verified_at, :utc_datetime
    field :last_login_at, :utc_datetime
    field :metadata, :map, default: %{}
    field :password_reset_token, :string
    field :password_reset_sent_at, :utc_datetime
    field :temp_password, :string
    field :temp_password_sent_at, :utc_datetime
    # Refresh token fields (store only hash and expiry)
    field :refresh_token_hash, :string
    field :current_session_id, :string
    field :refresh_token_expires_at, :utc_datetime
    # Tenant reference for proper isolation
    field :tenant_id, :binary_id
    # Polymorphic creator reference: can be public or tenant user
    field :created_by_id, :binary_id
    field :created_by_type, :string
    timestamps()
    has_many :user_roles, VyaasaCampus.Schema.Accounts.UserRole
    has_many :roles, through: [:user_roles, :role]
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :encrypted_password,
      :first_name,
      :middle_name,
      :last_name,
      :phone,
      :role,
      :status,
      :email_verified_at,
      :last_login_at,
      :metadata,
      :password_reset_token,
      :password_reset_sent_at,
      :temp_password,
      :temp_password_sent_at,
      :refresh_token_hash,
      :refresh_token_expires_at,
      :tenant_id,
      :created_by_id,
      :created_by_type
    ])
    |> validate_required([
      :email,
      :first_name,
      :last_name,
      :role,
      :tenant_id,
      :created_by_id,
      :created_by_type
    ])
    |> validate_inclusion(:status, valid_user_statuses())
    |> validate_inclusion(:role, valid_user_roles())
    |> validate_inclusion(:created_by_type, valid_creator_types())
    |> validate_length(:email, max: max_email_length())
    |> validate_length(:first_name, max: max_name_length())
    |> validate_length(:last_name, max: max_name_length())
    |> validate_length(:phone, max: max_phone_length())
    |> unique_constraint([:tenant_id, :email], name: :users_tenant_id_email_index)
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def generate_password_reset_token(user) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    user
    |> change(%{
      password_reset_token: token,
      password_reset_sent_at: now
    })
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def clear_password_reset_token(user) do
    user
    |> change(%{
      password_reset_token: nil,
      password_reset_sent_at: nil
    })
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def set_temp_password(user, temp_password) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    user
    |> change(%{
      temp_password: temp_password,
      temp_password_sent_at: now
    })
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def clear_temp_password(user) do
    user
    |> change(%{
      temp_password: nil,
      temp_password_sent_at: nil
    })
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def password_reset_token_valid?(user) do
    case user.password_reset_sent_at do
      nil ->
        false

      sent_at ->
        # Token expires after configured hours
        DateTime.diff(DateTime.utc_now(), sent_at, :hour) < password_reset_token_expiry()
    end
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def verify_password(user, password) do
    Bcrypt.verify_pass(password, user.encrypted_password)
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def password_changeset(user, attrs) do
    password = attrs[:password] || attrs["password"]

    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: min_password_length(), max: max_password_length())
    |> put_change(:encrypted_password, Bcrypt.hash_pwd_salt(password))
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def generate_temp_password do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
