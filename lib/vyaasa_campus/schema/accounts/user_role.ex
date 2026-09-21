defmodule VyaasaCampus.Schema.Accounts.UserRole do
  @moduledoc """
  User role association schema and changeset functions.

  Defines the many-to-many relationship between users and roles including:
  - Role assignment and management
  - Tenant-scoped role associations
  - Permission inheritance and access control
  - Dynamic role-based authorization
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset
  # we needed to use Jason.Encoder to encode the user_role schema to json
  @derive {Jason.Encoder,
           only: [
             :id,
             :user_id,
             :role_id,
             :assigned_by_id,
             :assigned_by_type,
             :assigned_at,
             :inserted_at,
             :updated_at
           ]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_roles" do
    field :user_id, :binary_id
    field :role_id, :binary_id
    # Polymorphic assigner reference: can be public or tenant user
    field :assigned_by_id, :binary_id
    field :assigned_by_type, :string
    field :assigned_at, :utc_datetime
    timestamps()

    # Add associations for preloading (they will use the existing fields)
    belongs_to :user, VyaasaCampus.Schema.Accounts.User,
      foreign_key: :user_id,
      define_field: false

    belongs_to :role, VyaasaCampus.Schema.Accounts.Role,
      foreign_key: :role_id,
      define_field: false
  end

  def changeset(user_role, attrs) do
    user_role
    |> cast(attrs, [
      :user_id,
      :role_id,
      :assigned_by_id,
      :assigned_by_type,
      :assigned_at
    ])
    |> validate_required([:user_id, :role_id, :assigned_by_id, :assigned_by_type])
    |> unique_constraint([:user_id, :role_id], name: :user_roles_user_id_role_id_index)
  end
end
