defmodule VyaasaCampus.Schema.Platform.Industry do
  @moduledoc """
  Industry schema for categorizing job roles.
  Lives in public schema, shared across all tenants.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :name, :code, :description, :icon, :is_active, :inserted_at, :updated_at]}

  schema "industries" do
    field :name, :string
    field :code, :string
    field :description, :string
    field :icon, :string
    field :is_active, :boolean, default: true

    has_many :job_roles, VyaasaCampus.Schema.Platform.JobRole

    timestamps()
  end

  def changeset(industry, attrs) do
    industry
    |> cast(attrs, [:name, :code, :description, :icon, :is_active])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_length(:code, max: 50)
    |> generate_code_if_blank()
    |> unique_constraint(:name)
    |> unique_constraint(:code)
  end

  defp generate_code_if_blank(changeset) do
    case get_field(changeset, :code) do
      nil -> put_change(changeset, :code, generate_code(get_field(changeset, :name)))
      "" -> put_change(changeset, :code, generate_code(get_field(changeset, :name)))
      _ -> changeset
    end
  end

  defp generate_code(nil), do: "IND#{:rand.uniform(999)}"
  defp generate_code(name) do
    name
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/, "")
    |> String.slice(0, 10)
  end
end
