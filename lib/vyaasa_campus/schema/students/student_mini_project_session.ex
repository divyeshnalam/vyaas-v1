defmodule VyaasaCampus.Schema.Students.StudentMiniProjectSession do
  @moduledoc """
  Domain Mini Project session — tracks a student's progress through all 7 phases
  of the AI-supervised internship simulation.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  # Legacy (7-phase) + V4 (5-step viva-driven) phases share one table.
  @phases ~w(role_assignment discovery implementation project_submission viva reflection completed
             profile scenario submission feedback)

  @phase_order %{
    "role_assignment" => 1,
    "discovery" => 2,
    "implementation" => 3,
    "project_submission" => 4,
    "viva" => 5,
    "reflection" => 6,
    "completed" => 7,
    # V4 flow
    "profile" => 1,
    "scenario" => 2,
    "submission" => 3,
    "feedback" => 5
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mini_project_sessions" do
    field :student_id, :binary_id
    field :tenant_id, :binary_id
    field :session_token, :string
    field :attempt_number, :integer, default: 1
    field :phase, :string, default: "role_assignment"

    field :archetype_key, :string
    field :specialization_name, :string
    field :scenario_candidates, {:array, :map}, default: []
    field :chosen_scenario, :map, default: %{}

    field :discovery_messages, {:array, :map}, default: []
    field :uncovered_facts, {:array, :string}, default: []
    field :discovery_recap, :string

    field :brief_markdown, :string
    field :brief_generated_at, :utc_datetime
    field :submission_deadline, :utc_datetime
    # Authenticity/forensics report (file metadata + git commits + viva).
    field :metadata, :map, default: %{}
    field :time_expired, :boolean, default: false
    field :submission_type, :string, default: "github"

    field :artifacts, {:array, :map}, default: []
    field :viva_turns, {:array, :map}, default: []
    field :reflection, :map

    field :criteria, {:array, :map}, default: []
    field :indexes, {:array, :map}, default: []
    field :domain_index, :integer
    field :collaboration_index, :integer
    field :initiative_index, :integer
    field :final_score, :integer
    field :grade_band, :string
    field :strengths, {:array, :string}, default: []
    field :improvements, {:array, :string}, default: []
    field :report_markdown, :string

    # ── V4 viva-driven engine ────────────────────────────────────────────────
    field :engine_version, :string, default: "legacy"
    field :profile, :map, default: %{}
    field :artifact_ceilings, :map, default: %{}
    field :viva_questions, {:array, :map}, default: []
    field :question_scores, {:array, :map}, default: []
    field :viva_metric_scores, :map, default: %{}
    field :per_metric, :map, default: %{}
    field :authenticity, :string
    field :gate_note, :string
    field :contradiction, :boolean, default: false
    field :contradiction_detail, :string
    field :timing, :map, default: %{}
    field :feedback, :map, default: %{}
    field :composite_raw, :integer

    field :completed_at, :utc_datetime

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:student_id, :tenant_id, :session_token, :attempt_number,
                    :archetype_key, :specialization_name])
    |> validate_required([:student_id, :tenant_id, :session_token])
    |> put_change(:phase, "role_assignment")
  end

  @doc "Create a V4 viva-driven session (starts at the profile step)."
  def create_changeset_v4(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:student_id, :tenant_id, :session_token, :attempt_number,
                    :specialization_name, :profile])
    |> validate_required([:student_id, :tenant_id, :session_token])
    |> put_change(:engine_version, "v4")
    |> put_change(:phase, "profile")
  end

  @v4_fields ~w(engine_version profile artifact_ceilings viva_questions question_scores
                viva_metric_scores per_metric authenticity gate_note contradiction
                contradiction_detail timing feedback composite_raw)a

  def update_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :phase, :archetype_key, :specialization_name,
      :scenario_candidates, :chosen_scenario,
      :discovery_messages, :uncovered_facts, :discovery_recap,
      :brief_markdown, :brief_generated_at, :submission_deadline, :time_expired, :submission_type,
      :artifacts, :viva_turns, :reflection,
      :criteria, :indexes, :domain_index, :collaboration_index, :initiative_index,
      :final_score, :grade_band, :strengths, :improvements, :report_markdown,
      :completed_at
      | @v4_fields
    ])
    |> validate_inclusion(:phase, @phases)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  def completed?(%__MODULE__{phase: "completed"}), do: true
  def completed?(_), do: false

  def phase_index(phase) when is_binary(phase), do: Map.get(@phase_order, phase, 0)

  def questions_asked(%__MODULE__{discovery_messages: msgs}),
    do: Enum.count(msgs, &(&1["sender"] == "student"))

  def readable_artifacts(%__MODULE__{artifacts: arts}),
    do: Enum.filter(arts, &(&1["extract_ok"] == true))

  def answered_viva_turns(%__MODULE__{viva_turns: turns}),
    do: Enum.filter(turns, &is_binary(&1["answer"]))

  def pending_viva_turn(%__MODULE__{viva_turns: turns}),
    do: Enum.find(turns, &is_nil(&1["answer"]))
end
