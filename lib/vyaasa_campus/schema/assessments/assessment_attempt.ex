defmodule VyaasaCampus.Schema.Assessments.AssessmentAttempt do
  @moduledoc """
  Assessment attempt schema and changeset functions.

  Defines student assessment attempts including:
  - Attempt lifecycle (started, in_progress, submitted, evaluated, completed)
  - Answer storage and scoring
  - Time tracking and submission management
  - Student performance analytics
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset
  import VyaasaCampus.Types

  @derive {Jason.Encoder,
           only: [
             :id,
             :assessment_id,
             :student_id,
             :started_at,
             :submitted_at,
             :completed_at,
             :score,
             :percentage,
             :status,
             :answers,
             :attempt_number,
             :inserted_at,
             :updated_at
           ]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "assessment_attempts" do
    # Assessment and Student References
    field :assessment_id, :binary_id
    field :student_id, :binary_id

    # Timing
    field :started_at, :utc_datetime
    field :submitted_at, :utc_datetime
    field :completed_at, :utc_datetime

    # Scoring
    field :obtained_marks, :integer
    field :total_marks, :integer
    field :score, :decimal
    field :percentage, :decimal

    # Status & Workflow
    # started -> in_progress -> submitted -> evaluated -> completed
    field :status, :string, default: attempt_status_started()

    # Content
    # Student's answers
    field :answers, :map, default: %{}
    field :evaluation_data, :map, default: %{}
    # Which attempt this is
    field :attempt_number, :integer, default: 1
    field :metadata, :map, default: %{}

    timestamps()
  end

  def changeset(assessment_attempt, attrs) do
    assessment_attempt
    |> cast(attrs, [
      :assessment_id,
      :student_id,
      :started_at,
      :submitted_at,
      :completed_at,
      :obtained_marks,
      :total_marks,
      :score,
      :percentage,
      :status,
      :answers,
      :evaluation_data,
      :attempt_number,
      :metadata
    ])
    |> validate_required([:assessment_id, :student_id])
    |> validate_inclusion(:status, valid_attempt_statuses())
    |> validate_number(:score, greater_than_or_equal_to: 0)
    |> validate_number(:percentage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:attempt_number, greater_than: 0)
  end

  @doc """
  Changeset for starting an assessment attempt
  """
  def start_attempt_changeset(assessment_attempt) do
    assessment_attempt
    |> put_change(:started_at, DateTime.utc_now())
    |> put_change(:status, attempt_status_started())
    |> put_change(:attempt_number, get_field(assessment_attempt, :attempt_number) || 1)
  end

  @doc """
  Changeset for submitting an assessment attempt
  """
  def submit_attempt_changeset(assessment_attempt, answers, score \\ nil, percentage \\ nil) do
    attrs = %{
      submitted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      status: attempt_status_submitted(),
      answers: answers
    }

    attrs = if score, do: Map.put(attrs, :score, score), else: attrs
    attrs = if percentage, do: Map.put(attrs, :percentage, Decimal.new(to_string(percentage))), else: attrs

    assessment_attempt
    |> changeset(attrs)
  end

  @doc """
  Changeset for completing an assessment attempt with score
  """
  def complete_attempt_changeset(assessment_attempt, score, percentage) do
    assessment_attempt
    |> changeset(%{
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      status: attempt_status_completed(),
      score: score,
      percentage: Decimal.round(Decimal.new(to_string(percentage)), 2)
    })
  end
end
