defmodule VyaasaCampus.Contexts.Platform do
  @moduledoc """
  Platform-level operations for superadmins managing tenants.
  """
  import Ecto.Query, warn: false
  alias VyaasaCampus.Auth.PasswordResetService
  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Platform.AdminUser
  alias VyaasaCampus.Schema.Tenants.Tenant

  # ------------------- Admin User Management -------------------
  def list_admin_users do
    Repo.all(AdminUser, prefix: "public")
  end

  def get_admin_user!(id) do
    Repo.get!(AdminUser, id, prefix: "public")
  end

  def create_admin_user(attrs) do
    %AdminUser{}
    |> AdminUser.create_changeset(attrs)
    |> Repo.insert(prefix: "public")
  end

  def update_admin_user(%AdminUser{} = admin_user, attrs) do
    admin_user
    |> AdminUser.changeset(attrs)
    |> Repo.update(prefix: "public")
  end

  # ------------------- Tenant Management (with created_by tracking) -------------------
  def create_tenant_with_admin(tenant_attrs, admin_user_id) do
    enhanced_attrs = Map.put(tenant_attrs, :created_by, admin_user_id)

    Tenants.create_tenant(enhanced_attrs)
  end

  def list_tenants_by_admin(admin_user_id) do
    from(t in Tenant, where: t.created_by == ^admin_user_id)
    |> Repo.all(prefix: "public")
  end

  # ------------------- Platform Admin Password Reset Functions -------------------

  @doc """
  Get platform admin by email (public schema)
  """
  def get_admin_user_by_email(email) do
    AdminUser
    |> where(email: ^email)
    |> Repo.one(prefix: "public")
  end

  @doc """
  Request password reset for platform admin.
  Delegates to the unified PasswordResetService.
  """
  def request_admin_password_reset(email) do
    PasswordResetService.request_password_reset(email, nil, "public")
  end

  @doc """
  Reset platform admin password using token.
  Delegates to the unified PasswordResetService.
  """
  def reset_admin_password_with_token(token, new_password) do
    PasswordResetService.reset_password_with_token(token, new_password, nil, "public")
  end
end
