defmodule VyaasaCampus.Schema.QuestionBank.Chapter do
  @moduledoc """
  Chapter schema representing chapters/units within a subject.
  Sits between Subject and Topic in the hierarchy:
  Degree → Specialization → Subject → Chapter → Topic → Question
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :code,
             :subject_id,
             :inserted_at,
             :updated_at
           ]}

  schema "chapters" do
    field :name, :string
    field :code, :string

    belongs_to :subject, VyaasaCampus.Schema.QuestionBank.Subject
    has_many :topics, VyaasaCampus.Schema.QuestionBank.Topic

    timestamps()
  end

  def changeset(chapter, attrs) do
    chapter
    |> cast(attrs, [:name, :code, :subject_id])
    |> validate_required([:name, :subject_id])
    |> validate_length(:name, max: 255)
    |> validate_length(:code, max: 50)
    |> foreign_key_constraint(:subject_id)
    |> unique_constraint([:name, :subject_id])
  end
end
