defmodule VyaasaCampus.Schema.QuestionBank.Branch do
  @moduledoc """
  Branch schema representing academic branches/specializations within a qualification.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :code,
             :qualification_id,
             :inserted_at,
             :updated_at
           ]}

  schema "branches" do
    field :name, :string
    field :code, :string

    belongs_to :qualification, VyaasaCampus.Schema.QuestionBank.Qualification
    has_many :curricula, VyaasaCampus.Schema.QuestionBank.Curriculum

    timestamps()
  end

  def changeset(branch, attrs) do
    branch
    |> cast(attrs, [:name, :code, :qualification_id])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_length(:code, max: 50)
    |> foreign_key_constraint(:qualification_id)
  end
end
