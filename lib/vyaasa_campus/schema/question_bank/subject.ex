defmodule VyaasaCampus.Schema.QuestionBank.Subject do
  @moduledoc """
  Subject schema representing academic subjects.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :code,
             :credits,
             :specialization_id,
             :inserted_at,
             :updated_at
           ]}

  schema "subjects" do
    field :name, :string
    field :code, :string
    field :credits, :integer, default: 0
    field :specialization_id, :binary_id

    many_to_many :curricula, VyaasaCampus.Schema.QuestionBank.Curriculum, join_through: "curricula_subjects"
    has_many :chapters, VyaasaCampus.Schema.QuestionBank.Chapter
    has_many :topics, VyaasaCampus.Schema.QuestionBank.Topic

    timestamps()
  end

  def changeset(subject, attrs) do
    subject
    |> cast(attrs, [:name, :code, :credits, :specialization_id])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_length(:code, max: 50)
    |> validate_number(:credits, greater_than_or_equal_to: 0)
  end
end
