defmodule VyaasaCampus.Schema.QuestionBank.Qualification do
  @moduledoc """
  Qualification schema representing educational qualifications (e.g., Bachelor's, Master's).
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :graduation_level,
             :field_of_study,
             :inserted_at,
             :updated_at
           ]}

  schema "qualifications" do
    field :name, :string
    field :graduation_level, :string
    field :field_of_study, :string

    has_many :branches, VyaasaCampus.Schema.QuestionBank.Branch

    timestamps()
  end

  def changeset(qualification, attrs) do
    qualification
    |> cast(attrs, [:name, :graduation_level, :field_of_study])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_length(:graduation_level, max: 100)
    |> validate_length(:field_of_study, max: 255)
    |> unique_constraint(:name)
  end
end
