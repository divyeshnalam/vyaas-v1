defmodule VyaasaCampus.Schema.Platform.JobRoleSubject do
  @moduledoc """
  Maps a job role to the subjects it is tested on in the Objective/MCQ
  assessment, with a per-subject question quota. This is the "role blueprint"
  that makes MCQ selection role-aware instead of degree-based (Vya-036).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "job_role_subjects" do
    field :question_count, :integer, default: 0
    belongs_to :job_role, VyaasaCampus.Schema.Platform.JobRole
    belongs_to :subject, VyaasaCampus.Schema.QuestionBank.Subject
    timestamps()
  end

  def changeset(job_role_subject, attrs) do
    job_role_subject
    |> cast(attrs, [:job_role_id, :subject_id, :question_count])
    |> validate_required([:job_role_id, :subject_id])
    |> validate_number(:question_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:job_role_id, :subject_id])
  end
end
