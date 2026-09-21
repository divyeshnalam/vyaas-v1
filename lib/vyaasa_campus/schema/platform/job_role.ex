defmodule VyaasaCampus.Schema.Platform.JobRole do
  @moduledoc """
  JobRole schema for predefined job roles within industries.
  Lives in public schema, shared across all tenants.
  Students select from these when uploading their resume.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :title, :code, :description, :job_description, :skills, :experience_level, :is_active, :industry_id, :inserted_at, :updated_at]}

  @valid_experience_levels ["entry", "mid", "senior", "lead"]

  schema "job_roles" do
    field :title, :string
    field :code, :string
    field :description, :string
    field :job_description, :string
    field :skills, {:array, :string}, default: []
    field :experience_level, :string, default: "entry"
    field :is_active, :boolean, default: true

    belongs_to :industry, VyaasaCampus.Schema.Platform.Industry

    timestamps()
  end

  def changeset(job_role, attrs) do
    job_role
    |> cast(attrs, [:title, :code, :description, :job_description, :skills, :experience_level, :is_active, :industry_id])
    |> validate_required([:title, :industry_id])
    |> validate_length(:title, max: 255)
    |> validate_length(:code, max: 50)
    |> validate_inclusion(:experience_level, @valid_experience_levels)
    |> generate_code_if_blank()
    |> foreign_key_constraint(:industry_id)
    |> unique_constraint([:title, :industry_id])
  end

  def valid_experience_levels, do: @valid_experience_levels

  defp generate_code_if_blank(changeset) do
    case get_field(changeset, :code) do
      nil -> put_change(changeset, :code, generate_code(get_field(changeset, :title)))
      "" -> put_change(changeset, :code, generate_code(get_field(changeset, :title)))
      _ -> changeset
    end
  end

  defp generate_code(nil), do: "JR#{:rand.uniform(999)}"
  defp generate_code(title) do
    title
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/, "")
    |> String.slice(0, 10)
  end
end
