defmodule VyaasaCampus.Repo.Migrations.CreateMiniProjectSessions do
  use Ecto.Migration

  @moduledoc """
  Per-tenant table for Domain Mini Project sessions. One row per student attempt.
  Sub-entities (discovery messages, artifacts, viva turns, reflection, evaluation)
  are stored as JSONB arrays to keep querying simple — we always need the full
  session in memory anyway.
  """

  def change do
    create table(:mini_project_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :student_id, :binary_id, null: false
      add :tenant_id, :binary_id

      add :session_token, :string, null: false
      add :attempt_number, :integer, null: false, default: 1

      # ── Phase state machine ──────────────────────────────────────────────
      # Values: role_assignment | discovery | implementation |
      #         project_submission | viva | reflection | completed
      add :phase, :string, null: false, default: "role_assignment"

      # ── Scenario ─────────────────────────────────────────────────────────
      add :archetype_key, :string
      add :specialization_name, :string
      add :scenario_candidates, {:array, :map}, default: []
      add :chosen_scenario, :map, default: %{}

      # ── Discovery ────────────────────────────────────────────────────────
      add :discovery_messages, {:array, :map}, default: []
      add :uncovered_facts, {:array, :string}, default: []
      add :discovery_recap, :text

      # ── Brief ────────────────────────────────────────────────────────────
      add :brief_markdown, :text
      add :brief_generated_at, :utc_datetime

      # ── Submission ───────────────────────────────────────────────────────
      # Each element: %{filename, content_type, size_bytes, extract_ok,
      #                 extracted_text, analysis, truncated, injection_suspected}
      add :artifacts, {:array, :map}, default: []

      # ── Viva ─────────────────────────────────────────────────────────────
      # Each element: %{index, question, asked_because, evidence, answer,
      #                 answer_score, answer_note, answer_weak}
      add :viva_turns, {:array, :map}, default: []

      # ── Reflection ───────────────────────────────────────────────────────
      # %{learned, challenges, improve, confidence}
      add :reflection, :map

      # ── Evaluation ───────────────────────────────────────────────────────
      add :criteria, {:array, :map}, default: []
      add :indexes, {:array, :map}, default: []
      add :domain_index, :integer
      add :collaboration_index, :integer
      add :initiative_index, :integer
      add :final_score, :integer
      add :grade_band, :string
      add :strengths, {:array, :string}, default: []
      add :improvements, {:array, :string}, default: []
      add :report_markdown, :text

      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:mini_project_sessions, [:session_token])
    create index(:mini_project_sessions, [:student_id])
    create index(:mini_project_sessions, [:phase])
    create index(:mini_project_sessions, [:student_id, :attempt_number])
  end
end
