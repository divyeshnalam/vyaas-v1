defmodule VyaasaCampus.Schema.Students.SharedProfileLink do
  @moduledoc """
  Maps a short, public slug to a (tenant_schema, student_id) pair, so a
  shared profile URL doesn't need to embed a signed token. Lives in the
  public schema — the slug alone must resolve both the tenant and the
  student, since the shared URL deliberately carries no tenant segment.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "shared_profile_links" do
    field :slug, :string
    field :student_id, :binary_id
    field :tenant_schema, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:slug, :student_id, :tenant_schema])
    |> validate_required([:slug, :student_id, :tenant_schema])
    |> unique_constraint(:slug)
    |> unique_constraint([:tenant_schema, :student_id])
  end
end
