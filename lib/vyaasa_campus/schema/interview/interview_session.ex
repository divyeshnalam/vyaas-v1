defmodule VyaasaCampus.Schema.Interview.InterviewSession do
  @moduledoc """
  Interview session schema for the AI-Led Resume Interview.

  Manages the lifecycle:
  created -> resume_indexed -> initialized -> interviewing -> completing -> completed
  Any state can transition to -> failed
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime, inserted_at: :created_at]
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           only: [
             :id,
             :student_id,
             :tenant_id,
             :session_token,
             :status,
             :python_session_id,
             :resume_url,
             :candidate_name,
             :max_questions,
             :max_duration_minutes,
             :questions_data,
             :overall_score,
             :final_report,
             :session_summary,
             :strengths,
             :improvements,
             :current_question_number,
             :questions_completed,
             :error_message,
             :retry_count,
             :created_at,
             :updated_at,
             :completed_at,
             :started_at
           ]}

  @valid_statuses ~w(created resume_indexed initialized interviewing completing completed failed terminated)

  schema "interview_sessions" do
    field :student_id, :binary_id
    field :tenant_id, :binary_id
    field :session_token, :string
    field :status, :string, default: "created"

    # Python service reference
    field :python_session_id, :string
    field :resume_url, :string
    field :resume_file_path, :string
    field :candidate_name, :string

    # Configuration
    field :max_questions, :integer, default: 5
    field :max_duration_minutes, :integer, default: 10

    # Questions and answers (JSON)
    field :questions_data, :map, default: %{"questions" => []}

    # Results
    field :overall_score, :decimal
    field :final_report, :string
    field :session_summary, :map
    # Proctoring violations (tab/window/fullscreen) — log-only.
    field :metadata, :map, default: %{}
    field :strengths, {:array, :string}, default: []
    field :improvements, {:array, :string}, default: []

    # Progress
    field :current_question_number, :integer, default: 0
    field :questions_completed, :integer, default: 0
    field :remaining_time_seconds, :integer

    # Error handling
    field :error_message, :string
    field :retry_count, :integer, default: 0

    timestamps()
    field :completed_at, :utc_datetime
    field :started_at, :utc_datetime
  end

  # ── Changesets ──────────────────────────────────────────────────────

  def create_changeset(session, attrs) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    session
    |> cast(attrs, [:student_id, :tenant_id, :resume_url, :resume_file_path])
    |> put_change(:session_token, token)
    |> put_change(:status, "created")
    |> validate_required([:student_id, :tenant_id, :session_token])
    |> unique_constraint(:session_token)
  end

  def resume_indexed_changeset(session, attrs) do
    session
    |> cast(attrs, [:python_session_id, :candidate_name])
    |> put_change(:status, "resume_indexed")
    |> validate_required([:python_session_id])
  end

  def initialized_changeset(session, attrs) do
    session
    |> cast(attrs, [:max_questions, :max_duration_minutes])
    |> put_change(:status, "initialized")
  end

  def start_interview_changeset(session) do
    session
    |> change()
    |> put_change(:status, "interviewing")
    |> put_change(:started_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def add_question_changeset(session, question_data) do
    current_questions = get_in(session.questions_data, ["questions"]) || []
    updated = current_questions ++ [question_data]
    q_num = question_data["question_number"] || question_data[:question_number]

    session
    |> change()
    |> put_change(:questions_data, %{"questions" => updated})
    |> put_change(:current_question_number, q_num)
  end

  def update_question_answer_changeset(session, question_number, answer_data) do
    current_questions = get_in(session.questions_data, ["questions"]) || []

    updated =
      Enum.map(current_questions, fn q ->
        if (q["question_number"] || q[:question_number]) == question_number do
          Map.merge(q, answer_data)
        else
          q
        end
      end)

    answered_count = Enum.count(updated, fn q -> q["score"] || q[:score] end)

    session
    |> change()
    |> put_change(:questions_data, %{"questions" => updated})
    |> put_change(:questions_completed, answered_count)
  end

  def complete_changeset(session, attrs) do
    session
    |> cast(attrs, [:overall_score, :final_report, :session_summary, :strengths, :improvements])
    |> put_change(:status, "completed")
    |> put_change(:completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Append content-moderation integrity flag(s) to `session_summary` without
  changing status — used for the first (warning) violation so it's audited too.
  """
  def add_integrity_flags_changeset(session, flags) when is_list(flags) do
    session
    |> change()
    |> put_change(:session_summary, append_integrity_flags(session, flags))
  end

  @doc """
  Mark a session terminated for a content-moderation violation. Appends the
  integrity flag(s) into `session_summary` (preserving any earlier warning
  flags) so the tenant-admin dashboard can surface them. Left unscored.
  """
  def terminate_changeset(session, flags) when is_list(flags) do
    session
    |> change()
    |> put_change(:status, "terminated")
    |> put_change(:session_summary, append_integrity_flags(session, flags))
    |> put_change(:completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp append_integrity_flags(session, flags) do
    summary = session.session_summary || %{}
    existing = Map.get(summary, "integrity_flags", [])
    Map.put(summary, "integrity_flags", (existing ++ flags) |> Enum.uniq())
  end

  def fail_changeset(session, error_message) do
    session
    |> change()
    |> put_change(:status, "failed")
    |> put_change(:error_message, error_message)
    |> put_change(:retry_count, (session.retry_count || 0) + 1)
  end

  def retry_changeset(session) do
    session
    |> change()
    |> put_change(:status, "created")
    |> put_change(:error_message, nil)
    |> put_change(:questions_data, %{"questions" => []})
    |> put_change(:current_question_number, 0)
    |> put_change(:questions_completed, 0)
    |> put_change(:overall_score, nil)
    |> put_change(:final_report, nil)
    |> put_change(:session_summary, nil)
    |> put_change(:strengths, [])
    |> put_change(:improvements, [])
    |> put_change(:started_at, nil)
    |> put_change(:completed_at, nil)
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  def valid_statuses, do: @valid_statuses

  def terminal_status?(%__MODULE__{status: status}), do: status in ["completed", "failed"]

  def can_retry?(%__MODULE__{status: "failed", retry_count: count}), do: count < 3
  def can_retry?(_), do: false

  def active?(%__MODULE__{status: status}), do: status not in ["completed", "failed"]
end
