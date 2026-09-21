defmodule VyaasaCampus.Repo.Migrations.FixBrokenTenantIndexesMigration do
  use Ecto.Migration

  @moduledoc """
  Supersedes `20260403100004_add_tenant_indexes.exs`, which has silently
  been a no-op in every tenant schema since it was written — it detects the
  tenant via raw `execute("... current_schema() ...")` SQL, which doesn't
  observe the migration's `prefix:` the way the Ecto DSL does (see
  `20260822120000_add_abandonment_sweep_indexes.exs` for the full
  explanation). Verified against tenant_test: none of its three named
  indexes or two CHECK constraints exist despite it showing as applied.

  Of what it was trying to add, most turned out to already be redundant —
  `student_id` and `status` already have standalone indexes on
  jam_sessions/interview_sessions/assessment_attempts from their original
  CREATE TABLE migrations, so Postgres can already combine them via a
  bitmap index scan for a query filtering on both. `idx_attempts_student_status`
  specifically was fully redundant (assessment_attempts already has that
  exact composite). Only two things were genuinely missing and worth
  re-adding here:

  - The `(student_id, status)` composite on jam_sessions/interview_sessions
    — a real, if modest, improvement over two separate index scans for the
    lookups force_complete/2 and friends do.
  - The two CHECK constraints — assessments.status and
    assessment_attempts.status currently have ZERO database-level
    protection; only the Ecto changeset's `validate_inclusion` guards them,
    which does nothing against a raw SQL update, a bad future migration, or
    direct DB access.
  """

  def change do
    create_if_not_exists index(:jam_sessions, [:student_id, :status], name: :idx_jam_student_status)
    create_if_not_exists index(:interview_sessions, [:student_id, :status], name: :idx_interview_student_status)

    create constraint(:assessments, :chk_assessment_status,
             check: "status IN ('draft', 'published', 'active', 'completed', 'archived')"
           )

    create constraint(:assessment_attempts, :chk_attempt_status,
             check: "status IN ('started', 'in_progress', 'submitted', 'evaluated', 'completed')"
           )
  end
end
