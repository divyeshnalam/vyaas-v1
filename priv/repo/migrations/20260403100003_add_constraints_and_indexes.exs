defmodule VyaasaCampus.Repo.Migrations.AddConstraintsAndIndexes do
  use Ecto.Migration

  def up do
    # ====================================================================
    # CHECK CONSTRAINTS on assessment_configs
    # ====================================================================

    execute """
    ALTER TABLE public.assessment_configs
    ADD CONSTRAINT chk_difficulty_pct_sum
    CHECK (easy_percentage + medium_percentage + hard_percentage = 100)
    """

    execute """
    ALTER TABLE public.assessment_configs
    ADD CONSTRAINT chk_aptitude_technical_sum
    CHECK (aptitude_percentage + technical_percentage = 100)
    """

    execute """
    ALTER TABLE public.assessment_configs
    ADD CONSTRAINT chk_passing_percentage_range
    CHECK (passing_percentage >= 0 AND passing_percentage <= 100)
    """

    execute """
    ALTER TABLE public.assessment_configs
    ADD CONSTRAINT chk_negative_marking_range
    CHECK (negative_marking >= 0 AND negative_marking <= 1)
    """

    # ====================================================================
    # DROP redundant column: branches.specialization (text field)
    # The specializations table serves this purpose properly.
    # ====================================================================

    alter table(:branches) do
      remove :specialization
    end

    # ====================================================================
    # MISSING INDEXES on public schema tables
    # ====================================================================

    # Subjects: name lookups for question bank admin
    create_if_not_exists index(:subjects, [:name])

    # Topics: name + subject compound lookups
    create_if_not_exists index(:topics, [:subject_id, :name], name: :idx_topics_subject_name)

    # Degrees: code lookups
    create_if_not_exists index(:degrees, [:is_active])

    # Specializations: degree + active filtering
    create_if_not_exists index(:specializations, [:degree_id, :is_active], name: :idx_specs_degree_active)
  end

  def down do
    alter table(:branches) do
      add :specialization, :string, size: 255
    end

    execute "ALTER TABLE public.assessment_configs DROP CONSTRAINT IF EXISTS chk_difficulty_pct_sum"
    execute "ALTER TABLE public.assessment_configs DROP CONSTRAINT IF EXISTS chk_aptitude_technical_sum"
    execute "ALTER TABLE public.assessment_configs DROP CONSTRAINT IF EXISTS chk_passing_percentage_range"
    execute "ALTER TABLE public.assessment_configs DROP CONSTRAINT IF EXISTS chk_negative_marking_range"

    drop_if_exists index(:subjects, [:name])
    drop_if_exists index(:topics, [:subject_id, :name], name: :idx_topics_subject_name)
    drop_if_exists index(:degrees, [:is_active])
    drop_if_exists index(:specializations, [:degree_id, :is_active], name: :idx_specs_degree_active)
  end
end
