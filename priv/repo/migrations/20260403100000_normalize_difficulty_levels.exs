defmodule VyaasaCampus.Repo.Migrations.NormalizeDifficultyLevels do
  use Ecto.Migration

  def up do
    # 1. Normalize all difficulty_level values in qa table to: easy, medium, hard
    execute """
    UPDATE public.qa SET difficulty_level = CASE
      WHEN LOWER(difficulty_level) IN ('beginner', 'basic') THEN 'easy'
      WHEN LOWER(difficulty_level) IN ('intermediate', 'moderate') THEN 'medium'
      WHEN LOWER(difficulty_level) IN ('advanced', 'difficult', 'expert') THEN 'hard'
      WHEN difficulty_level IS NULL THEN 'medium'
      WHEN LOWER(difficulty_level) IN ('easy', 'medium', 'hard') THEN LOWER(difficulty_level)
      ELSE 'medium'
    END
    """

    # 2. Add CHECK constraint to enforce valid difficulty levels going forward
    execute """
    ALTER TABLE public.qa
    ADD CONSTRAINT chk_qa_difficulty_level
    CHECK (difficulty_level IN ('easy', 'medium', 'hard'))
    """

    # 3. Add CHECK constraint for question type
    execute """
    ALTER TABLE public.qa
    ADD CONSTRAINT chk_qa_type
    CHECK (type IN ('multiple_choice', 'multiple_select', 'true_false', 'fill_in_blank', 'short_answer'))
    """

    # 4. Drop old select_questions() and recreate with standardized parameter names
    execute "DROP FUNCTION IF EXISTS select_questions(integer, integer, integer, integer[], integer, numeric, numeric, numeric, integer)"

    execute """
    CREATE OR REPLACE FUNCTION select_questions(
        p_curricula_id integer,
        p_branch_id integer DEFAULT NULL,
        p_user_id integer DEFAULT NULL,
        p_subject_ids integer[] DEFAULT NULL,
        p_total_questions integer DEFAULT 20,
        p_easy_pct numeric DEFAULT 0.40,
        p_medium_pct numeric DEFAULT 0.40,
        p_hard_pct numeric DEFAULT 0.20,
        p_exclude_recent_days integer DEFAULT 30
    )
    RETURNS TABLE(
        ret_qa_id integer,
        ret_question text,
        ret_answer text,
        ret_options jsonb,
        ret_difficulty_level character varying,
        ret_question_type character varying,
        ret_weightage numeric,
        ret_topic_id integer,
        ret_topic_name character varying,
        ret_subject_id integer,
        ret_subject_name character varying,
        ret_selection_reason character varying,
        ret_display_order integer
    )
    LANGUAGE plpgsql
    AS $$
    DECLARE
        v_easy_count INTEGER;
        v_medium_count INTEGER;
        v_hard_count INTEGER;
    BEGIN
        -- Calculate difficulty distribution
        v_easy_count := FLOOR(p_total_questions * p_easy_pct);
        v_medium_count := FLOOR(p_total_questions * p_medium_pct);
        v_hard_count := p_total_questions - v_easy_count - v_medium_count;

        RETURN QUERY
        WITH eligible_questions AS (
            SELECT
                qa.id AS qa_id,
                qa.question,
                qa.answer,
                qa.options,
                qa.difficulty_level,
                qa.type AS question_type,
                qa.weightage,
                t.id AS topic_id,
                t.name AS topic_name,
                s.id AS subject_id,
                s.name AS subject_name
            FROM qa
            INNER JOIN topics t ON qa.topic_id = t.id
            INNER JOIN subjects s ON t.subject_id = s.id
            INNER JOIN curricula_subjects cs ON s.id = cs.subject_id
            WHERE cs.curricula_id = p_curricula_id
                AND (p_branch_id IS NULL OR cs.branch_id = p_branch_id)
                AND (p_subject_ids IS NULL OR s.id = ANY(p_subject_ids))
        ),
        easy_selections AS (
            SELECT
                qa_id, question, answer, options, difficulty_level, question_type,
                weightage, topic_id, topic_name, subject_id, subject_name,
                'EASY'::VARCHAR AS selection_reason,
                ROW_NUMBER() OVER (ORDER BY RANDOM()) AS rn
            FROM eligible_questions
            WHERE difficulty_level = 'easy'
            LIMIT v_easy_count
        ),
        medium_selections AS (
            SELECT
                qa_id, question, answer, options, difficulty_level, question_type,
                weightage, topic_id, topic_name, subject_id, subject_name,
                'MEDIUM'::VARCHAR AS selection_reason,
                ROW_NUMBER() OVER (ORDER BY RANDOM()) AS rn
            FROM eligible_questions
            WHERE difficulty_level = 'medium'
                AND qa_id NOT IN (SELECT qa_id FROM easy_selections)
            LIMIT v_medium_count
        ),
        hard_selections AS (
            SELECT
                qa_id, question, answer, options, difficulty_level, question_type,
                weightage, topic_id, topic_name, subject_id, subject_name,
                'HARD'::VARCHAR AS selection_reason,
                ROW_NUMBER() OVER (ORDER BY RANDOM()) AS rn
            FROM eligible_questions
            WHERE difficulty_level = 'hard'
                AND qa_id NOT IN (
                    SELECT qa_id FROM easy_selections
                    UNION
                    SELECT qa_id FROM medium_selections
                )
            LIMIT v_hard_count
        ),
        combined_selections AS (
            SELECT * FROM easy_selections
            UNION ALL
            SELECT * FROM medium_selections
            UNION ALL
            SELECT * FROM hard_selections
        )
        SELECT
            cs.qa_id::INTEGER,
            cs.question::TEXT,
            cs.answer::TEXT,
            cs.options::JSONB,
            cs.difficulty_level::VARCHAR,
            cs.question_type::VARCHAR,
            cs.weightage::NUMERIC,
            cs.topic_id::INTEGER,
            cs.topic_name::VARCHAR,
            cs.subject_id::INTEGER,
            cs.subject_name::VARCHAR,
            cs.selection_reason::VARCHAR,
            ROW_NUMBER() OVER (ORDER BY RANDOM())::INTEGER AS display_order
        FROM combined_selections cs
        LIMIT p_total_questions;
    END;
    $$;
    """

    # 5. Add composite index for common query pattern
    create_if_not_exists index(:qa, [:topic_id, :difficulty_level], name: :idx_qa_topic_difficulty)
  end

  def down do
    execute "ALTER TABLE public.qa DROP CONSTRAINT IF EXISTS chk_qa_difficulty_level"
    execute "ALTER TABLE public.qa DROP CONSTRAINT IF EXISTS chk_qa_type"
    execute "DROP INDEX IF EXISTS idx_qa_topic_difficulty"

    # Revert SQL function not necessary - the old one still works with normalized values
  end
end
