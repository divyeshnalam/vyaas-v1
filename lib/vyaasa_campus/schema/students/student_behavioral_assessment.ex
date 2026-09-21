defmodule VyaasaCampus.Schema.Students.StudentBehavioralAssessment do
  @moduledoc """
  Student Behavioral Assessment schema.

  Stores behavioral assessment results received from the Python DS API.
  Follows the same pattern as StudentAtsPhase for consistency.

  The data structure captures:
  - Competency scores (work ethics, teamwork, adaptability, leadership, communication)
  - Detailed reasoning per competency
  - Scenario questions and candidate responses
  - Candidate profile snapshot at assessment time
  - Raw report data for debugging/reprocessing
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :student_id,
             :tenant_id,
             :session_id,
             :status,
             :started_at,
             :completed_at,
             :overall_score,
             :work_ethics_score,
             :teamwork_score,
             :adaptability_score,
             :leadership_score,
             :communication_score,
             :ratings,
             :reasoning,
             :summary,
             :strengths,
             :areas_for_development,
             :completed_scenarios,
             :scenarios_completed_count,
             :candidate_profile,
             :attempt_number,
             :metadata,
             :inserted_at,
             :updated_at
           ]}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ["started", "interviewing", "completed", "failed", "terminated"]

  schema "student_behavioral_assessments" do
    # References
    field :student_id, :binary_id
    field :tenant_id, :binary_id

    # Associations
    belongs_to :student, VyaasaCampus.Schema.Students.Student,
      foreign_key: :student_id,
      define_field: false

    # Session Tracking
    field :session_id, :string
    field :status, :string, default: "started"

    # Timing
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    # Overall Score
    field :overall_score, :integer

    # Competency Ratings (individual columns for querying)
    field :work_ethics_score, :integer
    field :teamwork_score, :integer
    field :adaptability_score, :integer
    field :leadership_score, :integer
    field :communication_score, :integer

    # Detailed Analysis
    field :ratings, :map, default: %{}
    field :reasoning, :map, default: %{}
    field :summary, :string
    field :strengths, {:array, :string}, default: []
    field :areas_for_development, {:array, :string}, default: []

    # Scenario Responses
    field :completed_scenarios, {:array, :map}, default: []
    field :scenarios_completed_count, :integer, default: 0

    # Candidate Profile snapshot
    field :candidate_profile, :map, default: %{}

    # Raw Data
    field :raw_report, :string
    field :raw_response_json, :map, default: %{}

    # Attempt tracking
    field :attempt_number, :integer, default: 1

    # Future extensibility
    field :metadata, :map, default: %{}

    timestamps()
  end

  @doc """
  General changeset for behavioral assessment records.
  """
  def changeset(assessment, attrs) do
    assessment
    |> cast(attrs, [
      :student_id,
      :tenant_id,
      :session_id,
      :status,
      :started_at,
      :completed_at,
      :overall_score,
      :work_ethics_score,
      :teamwork_score,
      :adaptability_score,
      :leadership_score,
      :communication_score,
      :ratings,
      :reasoning,
      :summary,
      :strengths,
      :areas_for_development,
      :completed_scenarios,
      :scenarios_completed_count,
      :candidate_profile,
      :raw_report,
      :raw_response_json,
      :attempt_number,
      :metadata
    ])
    |> validate_required([:student_id, :tenant_id, :session_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:overall_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:work_ethics_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:teamwork_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:adaptability_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:leadership_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:communication_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:attempt_number, greater_than: 0)
    |> validate_number(:scenarios_completed_count, greater_than_or_equal_to: 0, less_than_or_equal_to: 3)
    |> unique_constraint([:session_id], name: :student_behavioral_assessments_session_id_index)
    |> unique_constraint([:student_id, :attempt_number],
      name: :student_behavioral_assessments_student_id_attempt_number_index
    )
    |> foreign_key_constraint(:student_id)
  end

  @doc """
  Changeset for creating a new session record when assessment starts.
  """
  def start_changeset(attrs) do
    %__MODULE__{}
    |> changeset(
      Map.merge(attrs, %{
        status: "started",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )
  end

  @doc """
  Changeset for saving the completed behavioral report.

  Accepts either:
    * the new native engine shape where `ratings` is a map of
      `%{"work_ethics_and_reliability" => %{"score" => 75, "reasoning" => "..."}}`, or
    * the legacy shape where each rating is a bare integer.
  """
  def complete_changeset(assessment, report_response) do
    report = report_response["report"] || report_response || %{}
    ratings = report["ratings"] || %{}

    attrs = %{
      status: "completed",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      overall_score: report["overall_score"] || 0,
      work_ethics_score: extract_score(ratings, "work_ethics_and_reliability"),
      teamwork_score: extract_score(ratings, "teamwork_and_collaboration"),
      adaptability_score: extract_score(ratings, "adaptability_and_learning"),
      leadership_score: extract_score(ratings, "leadership_potential"),
      communication_score: extract_score(ratings, "communication_skills"),
      ratings: ratings,
      reasoning: report["reasoning"] || extract_reasoning_map(ratings),
      summary: report["summary"] || "",
      strengths: report["strengths"] || [],
      areas_for_development: report["areas_for_development"] || [],
      completed_scenarios: report["completed_scenarios"] || [],
      scenarios_completed_count: length(report["completed_scenarios"] || []),
      candidate_profile: report_response["candidate_profile"] || %{},
      raw_report: report["raw_text"] || report_response["raw_report"],
      raw_response_json: report_response
    }

    changeset(assessment, attrs)
  end

  defp extract_score(ratings, key) do
    case Map.get(ratings, key) do
      %{"score" => s} when is_integer(s) -> s
      %{"score" => s} when is_number(s) -> round(s)
      n when is_integer(n) -> n
      n when is_number(n) -> round(n)
      _ -> 0
    end
  end

  defp extract_reasoning_map(ratings) when is_map(ratings) do
    ratings
    |> Enum.map(fn
      {k, %{"reasoning" => r}} -> {k, r}
      {k, _} -> {k, ""}
    end)
    |> Enum.into(%{})
  end

  defp extract_reasoning_map(_), do: %{}

  @doc """
  Changeset for updating status during assessment flow.
  """
  def status_changeset(assessment, status) when status in @valid_statuses do
    changeset(assessment, %{status: status})
  end

  # ------------------------------------------------------------------
  # Helper functions
  # ------------------------------------------------------------------

  def completed?(%__MODULE__{status: "completed"}), do: true
  def completed?(_), do: false

  def failed?(%__MODULE__{status: "failed"}), do: true
  def failed?(_), do: false

  def get_competency_scores(%__MODULE__{} = assessment) do
    %{
      work_ethics: assessment.work_ethics_score || 0,
      teamwork: assessment.teamwork_score || 0,
      adaptability: assessment.adaptability_score || 0,
      leadership: assessment.leadership_score || 0,
      communication: assessment.communication_score || 0
    }
  end

  def get_competency_scores(_), do: %{work_ethics: 0, teamwork: 0, adaptability: 0, leadership: 0, communication: 0}
end
