defmodule VyaasaCampus.Schema.Assessments.Assessment do
  @moduledoc """
  Assessment schema and changeset functions.

  Defines the assessment entity supporting various assessment types including:
  - Quizzes, exams, assignments, projects, and practice tests
  - Multi-status workflow (draft, published, active, completed, archived)
  - Tenant-scoped assessment management
  - Time-based and scored assessments
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset
  import VyaasaCampus.Types

  @derive {Jason.Encoder,
           only: [
             :id,
             :title,
             :description,
             :assessment_type,
             :duration_minutes,
             :total_marks,
             :weightage,
             :passing_marks,
             :status,
             :time_period,
             :settings,
             :created_by,
             :tenant_id,
             :inserted_at,
             :updated_at
           ]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "assessments" do
    # Basic Assessment Info
    field :title, :string
    field :description, :string
    field :assessment_type, :string

    # Scoring & Weightage
    field :total_marks, :integer
    # Percentage weightage in overall grade
    field :weightage, :decimal
    field :passing_marks, :integer

    # Timing
    field :duration_minutes, :integer
    # start_date, end_date, timezone
    field :time_period, :map, default: %{}

    # Status & Workflow
    # draft -> published -> active -> completed -> archived
    field :status, :string, default: assessment_status_draft()

    # Creator & System Fields
    field :created_by, :binary_id
    # Assessment-specific configuration
    field :settings, :map, default: %{}
    field :tenant_id, :binary_id

    timestamps()
  end

  def changeset(assessment, attrs) do
    assessment
    |> cast(attrs, [
      :title,
      :description,
      :assessment_type,
      :duration_minutes,
      :total_marks,
      :weightage,
      :passing_marks,
      :status,
      :time_period,
      :created_by,
      :settings,
      :tenant_id
    ])
    |> validate_required([
      :title,
      :assessment_type,
      :duration_minutes,
      :total_marks,
      :passing_marks,
      :created_by,
      :tenant_id
    ])
    |> validate_inclusion(:status, valid_assessment_statuses())
    |> validate_inclusion(:assessment_type, valid_assessment_types())
    |> validate_number(:duration_minutes, greater_than: 0)
    |> validate_number(:total_marks, greater_than: 0)
    |> validate_number(:passing_marks, greater_than_or_equal_to: 0)
    |> validate_number(:weightage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_length(:title, max: max_title_length())
    |> validate_length(:description, max: max_description_length())
    |> validate_passing_marks_not_greater_than_total()
    |> validate_time_period()
  end

  @doc """
  Changeset for publishing an assessment
  """
  def publish_changeset(assessment, attrs) do
    assessment
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, [assessment_status_published(), assessment_status_active()])
    |> validate_time_period_required()
  end

  @doc """
  Changeset for completing an assessment
  """
  def complete_changeset(assessment, attrs) do
    assessment
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, [assessment_status_completed(), assessment_status_archived()])
  end

  defp validate_passing_marks_not_greater_than_total(changeset) do
    total_marks = get_field(changeset, :total_marks)
    passing_marks = get_field(changeset, :passing_marks)

    if total_marks && passing_marks && passing_marks > total_marks do
      add_error(changeset, :passing_marks, "cannot be greater than total marks")
    else
      changeset
    end
  end

  defp validate_time_period(changeset) do
    time_period = get_field(changeset, :time_period)

    if time_period && map_size(time_period) > 0 do
      validate_time_period_structure(changeset, time_period)
    else
      changeset
    end
  end

  defp validate_time_period_structure(changeset, time_period) do
    start_date = Map.get(time_period, "start_date") || Map.get(time_period, :start_date)
    end_date = Map.get(time_period, "end_date") || Map.get(time_period, :end_date)

    if start_date && end_date && start_date >= end_date do
      add_error(changeset, :time_period, "start_date must be before end_date")
    else
      changeset
    end
  end

  defp validate_time_period_required(changeset) do
    time_period = get_field(changeset, :time_period)

    if is_nil(time_period) || map_size(time_period) == 0 do
      add_error(changeset, :time_period, "is required for published assessments")
    else
      changeset
    end
  end
end
