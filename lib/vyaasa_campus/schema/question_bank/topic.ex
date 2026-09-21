defmodule VyaasaCampus.Schema.QuestionBank.Topic do
  @moduledoc """
  Topic schema representing topics within a subject.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :type,
             :weightage,
             :subject_id,
             :chapter_id,
             :inserted_at,
             :updated_at
           ]}

  schema "topics" do
    field :name, :string
    field :type, :string
    field :weightage, :decimal, default: Decimal.new("0.0")

    belongs_to :subject, VyaasaCampus.Schema.QuestionBank.Subject
    belongs_to :chapter, VyaasaCampus.Schema.QuestionBank.Chapter
    has_many :questions, VyaasaCampus.Schema.QuestionBank.QA

    timestamps()
  end

  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [:name, :type, :weightage, :subject_id, :chapter_id])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_length(:type, max: 100)
    |> validate_number(:weightage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:subject_id)
    |> foreign_key_constraint(:chapter_id)
  end
end
