defmodule VyaasaCampus.Schema.Assessments.AssessmentQuestion do
  @moduledoc """
  Junction table linking assessments to questions from the question bank.
  Allows questions to be reused across multiple assessments.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "assessment_questions" do
    belongs_to :assessment, VyaasaCampus.Schema.Assessments.Assessment
    field :qa_id, :integer
    field :question_order, :integer
    field :marks, :integer, default: 1

    timestamps()
  end

  def changeset(assessment_question, attrs) do
    assessment_question
    |> cast(attrs, [:assessment_id, :qa_id, :question_order, :marks])
    |> validate_required([:assessment_id, :qa_id])
    |> validate_number(:marks, greater_than: 0)
    |> validate_number(:question_order, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:assessment_id)
    |> unique_constraint([:assessment_id, :qa_id])
  end
end
