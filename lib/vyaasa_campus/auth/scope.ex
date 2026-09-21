defmodule VyaasaCampus.Auth.Scope do
  @moduledoc """
  Request scope derived at runtime containing tenant and user context for authorization.

  This struct is meant to be assigned on the connection (`conn.assigns[:scope]`) or
  on a LiveView socket, and may include minimal fields required by downstream policies.
  """

  @derive {Jason.Encoder,
           only: [
             :user_id,
             :user_type,
             :tenant_schema,
             :tenant_id,
             :roles,
             :permissions,
             :user_status,
             :tenant_status,
             :issued_at,
             :expires_at
           ]}
  @enforce_keys [:user_id, :user_type]
  defstruct [
    :user_id,
    # "admin" | "user" | "student"
    :user_type,
    # nil for platform admin
    :tenant_schema,
    # public tenant id for admin? usually nil for admin
    :tenant_id,
    # list of role names or structs for tenant users
    :roles,
    # flattened permissions if applicable
    :permissions,
    # active/pending, etc.
    :user_status,
    # active/inactive for tenant
    :tenant_status,
    :issued_at,
    :expires_at
  ]
end
