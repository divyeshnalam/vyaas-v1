defmodule VyaasaCampus.Schema.CaseStudy.CaseStudySession do
  @moduledoc """
  A student's AI-generated case-study attempt (per tenant schema). Stores the
  generated scenario, the 7-section answers, the three dimension scores
  (domain 0–40, problem-solving 0–30, leadership 0–30) and the report.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "case_study_sessions" do
    field :student_id, :binary_id
    field :tenant_id, :binary_id

    field :session_token, :string
    field :status, :string, default: "in_progress"
    field :attempt_number, :integer, default: 1

    field :specialization_group, :string
    field :specialization_sub, :string

    field :scenario, :map, default: %{}
    field :answers, :map, default: %{}

    field :domain_score, :integer
    field :problem_solving_score, :integer
    field :leadership_score, :integer
    field :total_score, :integer
    field :report, :map, default: %{}
    field :metadata, :map, default: %{}

    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(in_progress processing completed failed terminated)

  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :student_id,
      :tenant_id,
      :session_token,
      :attempt_number,
      :specialization_group,
      :specialization_sub,
      :scenario,
      :status
    ])
    |> validate_required([:student_id, :session_token, :specialization_sub])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:session_token)
  end

  def complete_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :answers,
      :domain_score,
      :problem_solving_score,
      :leadership_score,
      :total_score,
      :report,
      :status,
      :completed_at
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:total_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
