defmodule VyaasaCampus.Repo.Migrations.AddAbandonmentSweepIndexes do
  use Ecto.Migration

  @moduledoc """
  AssessmentAbandonmentSweep (see lib/vyaasa_campus/jobs/assessment_abandonment_sweep.ex)
  queries every one of these tables with `WHERE status NOT IN (...) AND
  updated_at < cutoff` (or `phase !=` for mini_project_sessions), every 15
  minutes, across every tenant schema. None of them had any index covering
  updated_at — every run was a full sequential scan. At meaningful row counts
  (many completed historical sessions accumulating over terms), that scan
  competes with live exam traffic for the same tables during the exact
  window it's least affordable. Also fills two smaller pre-existing gaps the
  same audit found: case_study_sessions had no index on tenant_id at all
  (every sibling table has one), and mini_project_sessions.engine_version
  (used to split v1 vs v4 sessions) had none either.

  Uses the Ecto migration DSL (not raw `execute("current_schema() ...")`
  SQL) deliberately — raw SQL run via `execute/1` does NOT pick up the
  migration's `prefix:` schema the way `create index(...)` does, so a
  `current_schema()`-based existence check silently evaluates against
  `public` instead of the tenant schema and never actually creates
  anything. Confirmed this is exactly what happened to the older
  `20260403100004_add_tenant_indexes.exs` migration — its custom-named
  indexes are absent from every tenant schema checked despite that
  migration being recorded as applied. Left as-is here (fixing it isn't
  this migration's job); this file just doesn't repeat the mistake.
  """

  def change do
    create_if_not_exists index(:jam_sessions, [:status, :updated_at], name: :idx_jam_status_updated)
    create_if_not_exists index(:interview_sessions, [:status, :updated_at], name: :idx_interview_status_updated)

    create_if_not_exists index(:student_behavioral_assessments, [:status, :updated_at],
                           name: :idx_behavioral_status_updated
                         )

    create_if_not_exists index(:student_psychometric_assessments, [:status, :updated_at],
                           name: :idx_psychometric_status_updated
                         )

    create_if_not_exists index(:case_study_sessions, [:status, :updated_at], name: :idx_case_study_status_updated)
    create_if_not_exists index(:case_study_sessions, [:tenant_id], name: :idx_case_study_tenant)

    create_if_not_exists index(:mini_project_sessions, [:phase, :updated_at],
                           name: :idx_mini_project_phase_updated
                         )

    create_if_not_exists index(:mini_project_sessions, [:engine_version], name: :idx_mini_project_engine_version)
  end
end
