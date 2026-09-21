defmodule VyaasaCampus.Schema.QuestionBank.Curriculum do
  @moduledoc """
  Curriculum schema representing academic curricula within a branch.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :code,
             :branch_id,
             :specialization_id,
             :inserted_at,
             :updated_at
           ]}

  schema "curricula" do
    field :name, :string
    field :code, :string

    belongs_to :branch, VyaasaCampus.Schema.QuestionBank.Branch
    # Bridge to the academics system: links curriculum to a specialization
    field :specialization_id, :binary_id
    many_to_many :subjects, VyaasaCampus.Schema.QuestionBank.Subject, join_through: "curricula_subjects"

    timestamps()
  end

  def changeset(curriculum, attrs) do
    curriculum
    |> cast(attrs, [:name, :code, :branch_id, :specialization_id])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_length(:code, max: 50)
    |> foreign_key_constraint(:branch_id)
  end
end
