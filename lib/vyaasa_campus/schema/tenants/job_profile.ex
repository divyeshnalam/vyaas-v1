defmodule VyaasaCampus.Schema.Tenants.JobProfile do
  @moduledoc """
  Job Profile schema for storing predefined job role descriptions.

  This schema stores comprehensive job profile information including role summaries,
  technical skills, responsibilities, tools, and educational requirements. These
  profiles are used by the ATS system to match student resumes against specific
  job roles and provide targeted feedback.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :role,
             :profile_text,
             :tenant_id,
             :created_by_id,
             :created_by_type,
             :inserted_at,
             :updated_at
           ]}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "job_profiles" do
    # Basic Profile Information
    field :role, :string
    field :profile_text, :string

    # Tenant isolation
    field :tenant_id, :binary_id

    # Polymorphic creator reference
    field :created_by_id, :binary_id
    field :created_by_type, :string

    timestamps()
  end

  @doc """
  Changeset for creating or updating a job profile.
  """
  def changeset(job_profile, attrs) do
    job_profile
    |> cast(attrs, [
      :role,
      :profile_text,
      :tenant_id,
      :created_by_id,
      :created_by_type
    ])
    |> validate_required([:role, :profile_text, :tenant_id])
    |> validate_length(:role, min: 1, max: 255)
    |> validate_length(:profile_text, min: 10, max: 10_000)
    |> unique_constraint([:tenant_id, :role], name: :job_profiles_tenant_id_role_index)
  end

  @doc """
  Changeset for creating a new job profile with creator information.
  """
  def create_changeset(job_profile, attrs, created_by_id, created_by_type) do
    attrs
    |> Map.merge(%{
      created_by_id: created_by_id,
      created_by_type: created_by_type
    })
    |> then(&changeset(job_profile, &1))
  end

  @doc """
  Extract core technical skills from profile text.
  """
  def extract_core_skills(%__MODULE__{profile_text: profile_text}) when is_binary(profile_text) do
    # Extract skills from the **Core Technical Skills:** section
    case Regex.run(~r/\*\*Core Technical Skills:\*\*\s*\n(.*?)(\n\*\*|$)/s, profile_text) do
      [_, skills_text, _] ->
        skills_text
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  def extract_core_skills(_), do: []

  @doc """
  Extract key responsibilities from profile text.
  """
  def extract_key_responsibilities(%__MODULE__{profile_text: profile_text}) when is_binary(profile_text) do
    # Extract responsibilities from the **Key Responsibilities & Experience:** section
    case Regex.run(~r/\*\*Key Responsibilities & Experience:\*\*\s*\n(.*?)(\n\*\*|$)/s, profile_text) do
      [_, responsibilities_text, _] ->
        responsibilities_text
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  def extract_key_responsibilities(_), do: []

  @doc """
  Extract essential tools from profile text.
  """
  def extract_essential_tools(%__MODULE__{profile_text: profile_text}) when is_binary(profile_text) do
    # Extract tools from the **Essential Tools:** section
    case Regex.run(~r/\*\*Essential Tools:\*\*\s*\n(.*?)(\n\*\*|$)/s, profile_text) do
      [_, tools_text, _] ->
        tools_text
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  def extract_essential_tools(_), do: []

  @doc """
  Extract educational background from profile text.
  """
  def extract_educational_background(%__MODULE__{profile_text: profile_text}) when is_binary(profile_text) do
    # Extract education from the **Educational Background:** section
    case Regex.run(~r/\*\*Educational Background:\*\*\s*\n(.*?)(\n\*\*|$)/s, profile_text) do
      [_, education_text, _] ->
        education_text
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  def extract_educational_background(_), do: []

  @doc """
  Get role summary from profile text.
  """
  def get_role_summary(%__MODULE__{profile_text: profile_text}) when is_binary(profile_text) do
    # Extract summary from the **Role Summary:** section
    case Regex.run(~r/\*\*Role Summary:\*\*\s*\n(.*?)\n\*\*/s, profile_text) do
      [_, summary_text, _] ->
        String.trim(summary_text)

      _ ->
        ""
    end
  end

  def get_role_summary(_), do: ""

  @doc """
  Check if profile belongs to a specific tenant.
  """
  def belongs_to_tenant?(%__MODULE__{tenant_id: profile_tenant_id}, tenant_id) do
    profile_tenant_id == tenant_id
  end

  def belongs_to_tenant?(_, _), do: false
end
