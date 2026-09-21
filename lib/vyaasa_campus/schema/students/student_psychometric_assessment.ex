defmodule VyaasaCampus.Schema.Students.StudentPsychometricAssessment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ["started", "processing", "completed", "failed"]

  @derive {Jason.Encoder,
           only: [
             :id,
             :student_id,
             :tenant_id,
             :session_id,
             :request_id,
             :status,
             :attempt_number,
             :started_at,
             :completed_at,
             :openness_score,
             :conscientiousness_score,
             :extraversion_score,
             :agreeableness_score,
             :neuroticism_score,
             :overall_summary,
             :factor_reports,
             :strengths,
             :development_areas,
             :suggestions,
             :factor_scores,
             :inserted_at,
             :updated_at
           ]}

  schema "student_psychometric_assessments" do
    field :student_id, :binary_id
    field :tenant_id, :binary_id
    field :session_id, :string
    field :request_id, :string
    field :status, :string, default: "started"
    field :attempt_number, :integer, default: 1

    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    # Big Five Factor Scores (1.0 - 5.0)
    field :openness_score, :float
    field :conscientiousness_score, :float
    field :extraversion_score, :float
    field :agreeableness_score, :float
    field :neuroticism_score, :float

    # AI Report
    field :overall_summary, :string
    field :factor_reports, :map
    field :strengths, {:array, :string}, default: []
    field :development_areas, {:array, :string}, default: []
    field :suggestions, {:array, :string}, default: []

    # Raw data
    field :factor_scores, :map
    field :raw_report_json, :map
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for general updates."
  def changeset(assessment, attrs) do
    assessment
    |> cast(attrs, [
      :student_id,
      :tenant_id,
      :session_id,
      :request_id,
      :status,
      :attempt_number,
      :started_at,
      :completed_at,
      :openness_score,
      :conscientiousness_score,
      :extraversion_score,
      :agreeableness_score,
      :neuroticism_score,
      :overall_summary,
      :factor_reports,
      :strengths,
      :development_areas,
      :suggestions,
      :factor_scores,
      :raw_report_json,
      :metadata
    ])
    |> validate_required([:student_id, :tenant_id, :session_id, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:attempt_number, greater_than: 0)
    |> validate_score(:openness_score)
    |> validate_score(:conscientiousness_score)
    |> validate_score(:extraversion_score)
    |> validate_score(:agreeableness_score)
    |> validate_score(:neuroticism_score)
    |> unique_constraint(:session_id)
    |> unique_constraint([:student_id, :attempt_number])
    |> foreign_key_constraint(:student_id)
  end

  @doc "Changeset for starting a new session."
  def start_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:student_id, :tenant_id, :session_id, :request_id, :attempt_number])
    |> validate_required([:student_id, :tenant_id, :session_id])
    |> put_change(:status, "started")
    |> put_change(:started_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> validate_number(:attempt_number, greater_than: 0)
    |> unique_constraint(:session_id)
    |> unique_constraint([:student_id, :attempt_number])
    |> foreign_key_constraint(:student_id)
  end

  @doc "Changeset for saving the completed report from Python callback."
  def complete_changeset(assessment, attrs) do
    assessment
    |> cast(attrs, [
      :openness_score,
      :conscientiousness_score,
      :extraversion_score,
      :agreeableness_score,
      :neuroticism_score,
      :overall_summary,
      :factor_reports,
      :strengths,
      :development_areas,
      :suggestions,
      :factor_scores,
      :raw_report_json
    ])
    |> put_change(:status, "completed")
    |> put_change(:completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc "Changeset for status-only updates."
  def status_changeset(assessment, status) do
    assessment
    |> cast(%{status: status}, [:status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def completed?(%__MODULE__{status: "completed"}), do: true
  def completed?(_), do: false

  def failed?(%__MODULE__{status: "failed"}), do: true
  def failed?(_), do: false

  def get_factor_scores(%__MODULE__{} = assessment) do
    %{
      openness: assessment.openness_score,
      conscientiousness: assessment.conscientiousness_score,
      extraversion: assessment.extraversion_score,
      agreeableness: assessment.agreeableness_score,
      neuroticism: assessment.neuroticism_score
    }
  end

  # Private helpers

  defp validate_score(changeset, field) do
    validate_number(changeset, field,
      greater_than_or_equal_to: 1.0,
      less_than_or_equal_to: 5.0
    )
  end
end
