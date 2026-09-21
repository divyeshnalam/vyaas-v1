defmodule VyaasaCampus.Repo.Migrations.AddTenantIndexes do
  use Ecto.Migration

  def up do
    # All index/constraint additions are wrapped to be safe on fresh tenant schemas
    # where some tables may not yet exist depending on migration order.
    execute """
    DO $$
    BEGIN
      -- Student indexes
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'students' AND table_schema = current_schema()) THEN
        CREATE INDEX IF NOT EXISTS students_status_index ON students (status);
        CREATE INDEX IF NOT EXISTS students_email_index ON students (email);
      END IF;

      -- Assessment attempt indexes
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'assessment_attempts' AND table_schema = current_schema()) THEN
        CREATE INDEX IF NOT EXISTS idx_attempts_student_status ON assessment_attempts (student_id, status);
      END IF;

      -- JAM sessions index
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'jam_sessions' AND table_schema = current_schema()) THEN
        CREATE INDEX IF NOT EXISTS idx_jam_student_status ON jam_sessions (student_id, status);
      END IF;

      -- Interview sessions index
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'interview_sessions' AND table_schema = current_schema()) THEN
        CREATE INDEX IF NOT EXISTS idx_interview_student_status ON interview_sessions (student_id, status);
      END IF;

      -- CHECK constraints on assessments
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'assessments' AND table_schema = current_schema()) THEN
        ALTER TABLE assessments ADD CONSTRAINT chk_assessment_status
          CHECK (status IN ('draft', 'published', 'active', 'completed', 'archived'));
      END IF;

      -- CHECK constraints on assessment_attempts
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'assessment_attempts' AND table_schema = current_schema()) THEN
        ALTER TABLE assessment_attempts ADD CONSTRAINT chk_attempt_status
          CHECK (status IN ('started', 'in_progress', 'submitted', 'evaluated', 'completed'));
      END IF;

    EXCEPTION WHEN duplicate_object THEN
      -- Constraints already exist, ignore
      NULL;
    END $$;
    """
  end

  def down do
    execute """
    DO $$
    BEGIN
      ALTER TABLE assessments DROP CONSTRAINT IF EXISTS chk_assessment_status;
      ALTER TABLE assessment_attempts DROP CONSTRAINT IF EXISTS chk_attempt_status;
    EXCEPTION WHEN undefined_table THEN NULL;
    END $$;
    """
  end
end
