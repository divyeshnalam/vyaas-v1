defmodule VyaasaCampus.Repo.Migrations.AddStudentDegreeSpecializationFks do
  use Ecto.Migration

  def up do
    # Add FK columns to students table alongside existing free-text fields.
    # The text fields (degree, specialization) are kept for backward compatibility
    # and will be populated automatically from the FK lookups.
    alter table(:students) do
      add :degree_id, :binary_id
      add :specialization_id, :binary_id
    end

    # Note: These reference public schema tables, but since this runs in tenant schemas,
    # we can't use Ecto's references() macro. We add the FK at raw SQL level.
    # Cross-schema FK constraints are valid in PostgreSQL.
    execute """
    DO $$
    DECLARE
      current_schema TEXT;
    BEGIN
      SELECT current_schema() INTO current_schema;

      -- Only add FKs if we're in a tenant schema (not public)
      IF current_schema != 'public' THEN
        -- degree_id FK to public.degrees
        BEGIN
          EXECUTE format(
            'ALTER TABLE %I.students ADD CONSTRAINT fk_students_degree_id FOREIGN KEY (degree_id) REFERENCES public.degrees(id) ON DELETE SET NULL',
            current_schema
          );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;

        -- specialization_id FK to public.specializations
        BEGIN
          EXECUTE format(
            'ALTER TABLE %I.students ADD CONSTRAINT fk_students_specialization_id FOREIGN KEY (specialization_id) REFERENCES public.specializations(id) ON DELETE SET NULL',
            current_schema
          );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
      END IF;
    END $$;
    """

    create index(:students, [:degree_id])
    create index(:students, [:specialization_id])

    # Populate degree_id/specialization_id from existing free-text fields.
    # Wrapped in DO block so it's safe on fresh schemas with no data.
    execute """
    DO $$
    BEGIN
      -- Match degree by name
      UPDATE students s
      SET degree_id = d.id
      FROM public.degrees d
      WHERE LOWER(TRIM(s.degree)) = LOWER(TRIM(d.name))
        AND d.is_active = true
        AND s.degree IS NOT NULL
        AND s.degree_id IS NULL;

      -- Match degree by code
      UPDATE students s
      SET degree_id = d.id
      FROM public.degrees d
      WHERE LOWER(TRIM(s.degree)) = LOWER(TRIM(d.code))
        AND d.is_active = true
        AND s.degree IS NOT NULL
        AND s.degree_id IS NULL;

      -- Match specialization by name
      UPDATE students s
      SET specialization_id = sp.id
      FROM public.specializations sp
      WHERE LOWER(TRIM(s.specialization)) = LOWER(TRIM(sp.name))
        AND sp.is_active = true
        AND s.specialization IS NOT NULL
        AND s.specialization_id IS NULL;

      -- Match specialization by code
      UPDATE students s
      SET specialization_id = sp.id
      FROM public.specializations sp
      WHERE LOWER(TRIM(s.specialization)) = LOWER(TRIM(sp.code))
        AND sp.is_active = true
        AND s.specialization IS NOT NULL
        AND s.specialization_id IS NULL;
    EXCEPTION WHEN undefined_table THEN
      -- Fresh tenant schema, students table may not exist yet — skip silently
      NULL;
    END $$;
    """

    # Add index on status (frequently filtered)
    create_if_not_exists index(:students, [:status])
  end

  def down do
    execute "ALTER TABLE students DROP CONSTRAINT IF EXISTS fk_students_degree_id"
    execute "ALTER TABLE students DROP CONSTRAINT IF EXISTS fk_students_specialization_id"

    alter table(:students) do
      remove :degree_id
      remove :specialization_id
    end
  end
end
