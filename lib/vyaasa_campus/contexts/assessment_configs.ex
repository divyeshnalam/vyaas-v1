defmodule VyaasaCampus.Contexts.AssessmentConfigs do
  @moduledoc """
  Context for managing per-tenant assessment configurations.
  Stores in public schema since it's managed by super admin.
  """

  import Ecto.Query, warn: false
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Assessments.AssessmentConfig

  @defaults %{
    total_questions: 60,
    aptitude_percentage: 40,
    technical_percentage: 60,
    duration_minutes: 90,
    negative_marking: Decimal.new("0.25"),
    easy_percentage: 40,
    medium_percentage: 40,
    hard_percentage: 20,
    passing_percentage: 50,
    is_active: true
  }

  def defaults, do: @defaults

  def list_configs do
    Repo.all(AssessmentConfig, prefix: "public")
  end

  def get_config!(id) do
    Repo.get!(AssessmentConfig, id, prefix: "public")
  end

  def get_config_for_tenant(tenant_id) do
    Repo.get_by(AssessmentConfig, [tenant_id: tenant_id], prefix: "public")
  end

  def get_or_default_config_for_tenant(tenant_id) do
    case get_config_for_tenant(tenant_id) do
      nil -> struct(AssessmentConfig, Map.put(@defaults, :tenant_id, tenant_id))
      config -> config
    end
  end

  def create_config(attrs) do
    %AssessmentConfig{}
    |> AssessmentConfig.changeset(attrs)
    |> Repo.insert(prefix: "public")
  end

  def update_config(%AssessmentConfig{} = config, attrs) do
    config
    |> AssessmentConfig.changeset(attrs)
    |> Repo.update(prefix: "public")
  end

  def upsert_config_for_tenant(tenant_id, attrs) do
    attrs = Map.put(attrs, "tenant_id", tenant_id)

    case get_config_for_tenant(tenant_id) do
      nil -> create_config(attrs)
      existing -> update_config(existing, attrs)
    end
  end

  def delete_config(%AssessmentConfig{} = config) do
    Repo.delete(config, prefix: "public")
  end
end
