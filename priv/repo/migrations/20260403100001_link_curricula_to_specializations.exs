defmodule VyaasaCampus.Repo.Migrations.LinkCurriculaToSpecializations do
  use Ecto.Migration

  def up do
    # Add specialization_id FK to curricula table, bridging the two systems.
    # This allows curricula to be resolved directly from degrees/specializations
    # without going through the legacy qualifications/branches path.
    alter table(:curricula) do
      add :specialization_id, references(:specializations, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:curricula, [:specialization_id])

    # Populate specialization_id by matching branch.code to specialization.code
    # This auto-links existing curricula to specializations where codes match
    execute """
    UPDATE curricula c
    SET specialization_id = s.id
    FROM branches b, specializations s
    WHERE c.branch_id = b.id
      AND LOWER(b.code) = LOWER(s.code)
      AND s.is_active = true
    """

    # Also try matching by name for branches without matching codes
    execute """
    UPDATE curricula c
    SET specialization_id = s.id
    FROM branches b, specializations s
    WHERE c.branch_id = b.id
      AND c.specialization_id IS NULL
      AND LOWER(b.name) = LOWER(s.name)
      AND s.is_active = true
    """
  end

  def down do
    alter table(:curricula) do
      remove :specialization_id
    end
  end
end
