defmodule VyaasaCampus.AI.MiniProject.Metrics do
  @moduledoc """
  The five viva-defensible metrics (D1–D5), their weights, score bands, and
  timing constants for the V4 viva-driven mini-project assessment.

  Ported from the V4 reference (`config.py`). D1–D4 have an artifact ceiling;
  D5 (adaptive reasoning) is generated live in the viva and has no artifact.
  """

  # {key => %{name, weight (%), questions, description}}. Weights sum to 100.
  @metrics %{
    "D1" => %{name: "Problem comprehension", weight: 22, questions: 2,
              description: "Did they understand the actual problem, including the scope ambiguity, and who the output is for?"},
    "D2" => %{name: "Reasoning ownership", weight: 26, questions: 3,
              description: "Can they explain WHY each decision was made, unprompted, consistent with the artifact?"},
    "D3" => %{name: "Depth of analysis", weight: 22, questions: 3,
              description: "Do they understand the mechanics of their own analysis, not just its outputs?"},
    "D4" => %{name: "Constraint handling", weight: 16, questions: 2,
              description: "Did they notice and resolve the embedded ambiguity, and can they defend the resolution?"},
    "D5" => %{name: "Adaptive reasoning", weight: 14, questions: 2,
              description: "When a constraint changes mid-viva, can they re-reason in real time?"}
  }

  # Metric order used across prompts/questions (D1,D1,D2,D2,D2,D3,D3,D3,D4,D4,D5,D5).
  @order ~w(D1 D2 D3 D4 D5)

  # D5 has no submitted artifact — it is scored purely on the live viva answer.
  @artifact_metrics ~w(D1 D2 D3 D4)

  # Score bands: {label, min_inclusive}.
  @bands [
    {"Outstanding", 85},
    {"Strong", 70},
    {"Developing", 55},
    {"Insufficient", 40},
    {"Not ready", 0}
  ]

  # ── Timing (seconds / minutes / fractions) ────────────────────────────────
  @project_timer_mode "soft"
  @project_overtime_cap 0
  @project_grace_minutes 10
  @fast_submit_fraction 0.25
  @viva_min_seconds 180
  @viva_max_seconds 300
  @viva_default_seconds 240

  def all, do: @metrics
  def keys, do: @order
  def artifact_keys, do: @artifact_metrics
  def bands, do: @bands

  def meta(key), do: Map.get(@metrics, key)
  def name(key), do: get_in(@metrics, [key, :name])
  def weight(key), do: get_in(@metrics, [key, :weight])
  def question_count(key), do: get_in(@metrics, [key, :questions])
  def artifact_metric?(key), do: key in @artifact_metrics

  def project_timer_mode, do: @project_timer_mode
  def project_overtime_cap, do: @project_overtime_cap
  def project_grace_minutes, do: @project_grace_minutes
  def fast_submit_fraction, do: @fast_submit_fraction
  def viva_min_seconds, do: @viva_min_seconds
  def viva_max_seconds, do: @viva_max_seconds
  def viva_default_seconds, do: @viva_default_seconds
end
