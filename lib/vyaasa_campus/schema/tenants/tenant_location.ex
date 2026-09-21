defmodule VyaasaCampus.Schema.Tenants.TenantLocation do
  @moduledoc """
  Tenant location schema and changeset functions.

  Defines physical locations associated with tenant organizations including:
  - Address and contact information
  - Primary location designation
  - Geographic and operational details
  - Multi-location tenant support
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  # Same here as well, basically where we are using the tenant_id and trying to do through JSON
  # we need to use @derive {Jason.Encoder} and specify the fields we want to encode
  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :address,
             :city,
             :state,
             :pincode,
             :is_primary,
             :tenant_id,
             :inserted_at,
             :updated_at
           ]}

  schema "tenant_locations" do
    field :name, :string
    field :address, :string
    field :city, :string
    field :state, :string
    field :pincode, :string
    field :is_primary, :boolean, default: false

    belongs_to :tenant, VyaasaCampus.Schema.Tenants.Tenant, type: :binary_id
    timestamps()
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :address, :city, :state, :pincode, :is_primary, :tenant_id])
    |> validate_required([:name, :tenant_id])
    |> validate_format(:pincode, ~r/^\d{6}$/, message: "must be exactly 6 digits")
  end
end
