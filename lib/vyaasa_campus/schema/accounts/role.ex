defmodule VyaasaCampus.Schema.Accounts.Role do
  @moduledoc """
  Role schema and changeset functions.

  Defines roles for the role-based access control system including:
  - Admin, instructor, student, and superadmin roles
  - Tenant-scoped role definitions
  - Permission management and authorization
  - Hierarchical role structures
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :display_name,
             :description,
             :permissions,
             :is_system_role,
             :tenant_id,
             :created_by_id,
             :created_by_type,
             :inserted_at,
             :updated_at
           ]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "roles" do
    field :name, :string
    field :display_name, :string
    field :description, :string
    field :permissions, {:array, :string}, default: []
    field :is_system_role, :boolean, default: false
    # Tenant reference for proper isolation
    field :tenant_id, :binary_id
    # Polymorphic creator reference: can be public or tenant user
    field :created_by_id, :binary_id
    field :created_by_type, :string
    timestamps()
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [
      :name,
      :display_name,
      :description,
      :permissions,
      :is_system_role,
      :tenant_id,
      :created_by_id,
      :created_by_type
    ])
    |> validate_required([:name, :display_name, :tenant_id, :created_by_id, :created_by_type])
    |> unique_constraint([:tenant_id, :name], name: :roles_tenant_id_name_index)
  end
end
