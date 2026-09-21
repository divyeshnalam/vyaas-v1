defmodule VyaasaCampus.Schema.Tenants.Tenant do
  @moduledoc """
  Tenant organization schema and changeset functions.

  Defines the tenant entity representing organizations in the multi-tenant system including:
  - Organization identity and configuration
  - Schema isolation and database separation
  - Status management and lifecycle
  - Settings and customization options
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset
  import VyaasaCampus.Types

  @primary_key {:id, :binary_id, autogenerate: true}
  # We are using @derive since we are using the `Jason` library for JSON encoding and normally
  # it won't encode the schema fields automatically so we need to explicitly tell it which fields to encode
  # this is useful when we want to return the tenant data in JSON format
  # we needed to use Jason.Encoder to encode the tenant schema to JSON
  @derive {Jason.Encoder,
           only: [
             :id,
             :full_name,
             :short_name,
             :alias,
             :schema_name,
             :affiliation_type,
             :email,
             :phone,
             :website_url,
             :logo_url,
             :status,
             :settings,
             :created_by,
             :inserted_at,
             :updated_at
           ]}
  schema "tenants" do
    field :full_name, :string
    field :short_name, :string
    field :alias, :string
    field :schema_name, :string
    field :affiliation_type, :string
    field :email, :string
    field :phone, :string
    field :website_url, :string
    field :logo_url, :string
    field :status, :string
    field :settings, :map

    belongs_to :creator, VyaasaCampus.Schema.Platform.AdminUser,
      foreign_key: :created_by,
      type: :binary_id

    has_many :locations, VyaasaCampus.Schema.Tenants.TenantLocation

    timestamps()
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [
      :full_name,
      :short_name,
      :alias,
      :schema_name,
      :affiliation_type,
      :email,
      :phone,
      :website_url,
      :logo_url,
      :status,
      :settings,
      :created_by
    ])
    |> validate_required([
      :full_name,
      :short_name,
      :alias,
      :schema_name,
      :affiliation_type,
      :email,
      :created_by
    ])
    |> validate_inclusion(:affiliation_type, valid_affiliation_types())
    |> unique_constraint(:alias)
    |> unique_constraint(:schema_name)
  end
end
