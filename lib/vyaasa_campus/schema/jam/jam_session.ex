defmodule VyaasaCampus.Schema.Jam.JamSession do
  @moduledoc """
  JAM (Just A Minute) session schema and changeset functions.

  Defines the JAM session entity for speech assessment including:
  - Session lifecycle management (created → topic_generated → decision_phase → preparation → speaking → processing → completed)
  - Topic generation and decision workflow
  - Audio recording and speech processing
  - AI evaluation and scoring
  - Timing and performance tracking
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime, inserted_at: :created_at]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :student_id,
             :tenant_id,
             :session_token,
             :status,
             :topic_title,
             :topic_explanation,
             :topic_changed,
             :change_topic_available,
             :recording_file_path,
             :recording_duration_seconds,
             :recording_active,
             :transcript,
             :word_count,
             :speech_duration_seconds,
             :evaluation_data,
             :final_score,
             :clarity_score,
             :structure_score,
             :relevance_score,
             :impact_score,
             :confidence_score,
             :overall_summary,
             :decision_time_seconds,
             :preparation_time_seconds,
             :speech_time_seconds,
             :actual_decision_time_used,
             :actual_preparation_time_used,
             :actual_speech_time_used,
             :webrtc_connected,
             :audio_quality_score,
             :noise_level,
             :error_message,
             :retry_count,
             :created_at,
             :updated_at,
             :completed_at
           ]}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "jam_sessions" do
    # Primary identifiers
    field :student_id, :binary_id
    field :tenant_id, :binary_id

    # Session management
    field :session_token, :string
    field :status, :string, default: "created"

    # Topic information
    field :topic_title, :string
    field :topic_explanation, :string
    field :topic_changed, :boolean, default: false
    field :change_topic_available, :boolean, default: true

    # Audio and recording
    field :recording_file_path, :string
    field :recording_duration_seconds, :integer
    field :recording_active, :boolean, default: false

    # Speech processing
    field :transcript, :string
    field :word_count, :integer
    field :speech_duration_seconds, :integer

    # AI Evaluation (stored as JSON)
    field :evaluation_data, :map, default: %{}
    # Proctoring violations (tab/window/fullscreen) — log-only for JAM.
    field :metadata, :map, default: %{}
    field :final_score, :integer # 0-100
    field :clarity_score, :integer # 1-10
    field :structure_score, :integer # 1-10
    field :relevance_score, :integer # 1-10
    field :impact_score, :integer # 1-10
    field :confidence_score, :integer # 1-10
    field :overall_summary, :string

    # Timing information
    field :decision_time_seconds, :integer, default: 60
    field :preparation_time_seconds, :integer, default: 15
    field :speech_time_seconds, :integer, default: 60
    field :actual_decision_time_used, :integer
    field :actual_preparation_time_used, :integer
    field :actual_speech_time_used, :integer

    # WebRTC and technical
    field :webrtc_connected, :boolean, default: false
    field :audio_quality_score, :decimal
    field :noise_level, :decimal

    # Error handling
    field :error_message, :string
    field :retry_count, :integer, default: 0

    timestamps()
    field :completed_at, :utc_datetime
  end

  @doc """
  Changeset for creating a new JAM session
  """
  def changeset(jam_session, attrs) do
    jam_session
    |> cast(attrs, [
      :student_id,
      :tenant_id,
      :session_token,
      :status,
      :topic_title,
      :topic_explanation,
      :topic_changed,
      :change_topic_available,
      :recording_file_path,
      :recording_duration_seconds,
      :recording_active,
      :transcript,
      :word_count,
      :speech_duration_seconds,
      :evaluation_data,
      :final_score,
      :clarity_score,
      :structure_score,
      :relevance_score,
      :impact_score,
      :confidence_score,
      :overall_summary,
      :decision_time_seconds,
      :preparation_time_seconds,
      :speech_time_seconds,
      :actual_decision_time_used,
      :actual_preparation_time_used,
      :actual_speech_time_used,
      :webrtc_connected,
      :audio_quality_score,
      :noise_level,
      :error_message,
      :retry_count,
      :completed_at
    ])
    |> validate_required([:student_id, :tenant_id, :session_token])
    |> validate_inclusion(:status, valid_jam_statuses())
    |> validate_number(:final_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:clarity_score, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:structure_score, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:relevance_score, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:impact_score, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:confidence_score, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:decision_time_seconds, greater_than: 0)
    |> validate_number(:preparation_time_seconds, greater_than: 0)
    |> validate_number(:speech_time_seconds, greater_than: 0)
    |> validate_number(:retry_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:session_token)
  end

  @doc """
  Changeset for creating a new JAM session with generated token
  """
  def create_changeset(jam_session, attrs) do
    session_token = generate_session_token()

    jam_session
    |> changeset(Map.put(attrs, :session_token, session_token))
    |> put_change(:status, "created")
  end

  @doc """
  Changeset for updating session status
  """
  def status_changeset(jam_session, status) do
    jam_session
    |> cast(%{status: status}, [:status])
    |> validate_inclusion(:status, valid_jam_statuses())
  end

  @doc """
  Changeset for topic generation
  """
  def topic_generated_changeset(jam_session, topic_attrs) do
    jam_session
    |> cast(topic_attrs, [:topic_title, :topic_explanation, :change_topic_available])
    |> put_change(:status, "topic_generated")
    |> validate_required([:topic_title, :topic_explanation])
  end

  @doc """
  Changeset for topic decision
  """
  def topic_decision_changeset(jam_session, decision_attrs) do
    jam_session
    |> cast(decision_attrs, [:topic_changed, :actual_decision_time_used])
    |> put_change(:status, "decision_phase")
    |> validate_required([:actual_decision_time_used])
  end

  @doc """
  Changeset for starting preparation phase
  """
  def start_preparation_changeset(jam_session) do
    jam_session
    |> change()
    |> put_change(:status, "preparation")
    |> put_change(:webrtc_connected, true)
  end

  @doc """
  Changeset for starting speaking phase
  """
  def start_speaking_changeset(jam_session, preparation_time_used) do
    jam_session
    |> change()
    |> put_change(:status, "speaking")
    |> put_change(:actual_preparation_time_used, preparation_time_used)
    |> put_change(:recording_active, true)
  end

  @doc """
  Changeset for completing speaking phase
  """
  def complete_speaking_changeset(jam_session, speech_time_used, audio_data) do
    jam_session
    |> cast(audio_data, [:recording_file_path, :recording_duration_seconds, :audio_quality_score, :noise_level])
    |> put_change(:status, "processing")
    |> put_change(:actual_speech_time_used, speech_time_used)
    |> put_change(:recording_active, false)
  end

  @doc """
  Changeset for processing completion with evaluation results
  """
  def processing_complete_changeset(jam_session, evaluation_data) do
    jam_session
    |> cast(evaluation_data, [
      :transcript,
      :word_count,
      :speech_duration_seconds,
      :evaluation_data,
      :final_score,
      :clarity_score,
      :structure_score,
      :relevance_score,
      :impact_score,
      :confidence_score,
      :overall_summary
    ])
    |> put_change(:status, "completed")
    |> put_change(:completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> validate_required([:transcript, :final_score])
  end

  @doc """
  Changeset for processing failure
  """
  def processing_failed_changeset(jam_session, error_message) do
    jam_session
    |> change()
    |> put_change(:status, "failed")
    |> put_change(:error_message, error_message)
    |> put_change(:retry_count, (jam_session.retry_count || 0) + 1)
  end

  @doc """
  Changeset for retrying a failed session
  """
  def retry_changeset(jam_session) do
    jam_session
    |> change()
    |> put_change(:status, "created")
    |> put_change(:error_message, nil)
  end

  # Helper functions

  defp generate_session_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp valid_jam_statuses do
    [
      "created",
      "topic_generated",
      "decision_phase",
      "preparation",
      "speaking",
      "processing",
      "completed",
      "failed"
    ]
  end

  @doc """
  Check if session is in a terminal state
  """
  def terminal_status?(%__MODULE__{status: status}) do
    status in ["completed", "failed"]
  end

  @doc """
  Check if session can be retried
  """
  def can_retry?(%__MODULE__{status: "failed", retry_count: retry_count}) do
    retry_count < 3
  end
  def can_retry?(_), do: false

  @doc """
  Get session duration in seconds
  """
  def total_duration(%__MODULE__{} = session) do
    (session.actual_decision_time_used || 0) +
    (session.actual_preparation_time_used || 0) +
    (session.actual_speech_time_used || 0)
  end

  @doc """
  Check if session is active (not terminal)
  """
  def active?(%__MODULE__{status: status}) do
    status not in ["completed", "failed"]
  end
end
