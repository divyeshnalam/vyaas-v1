defmodule VyaasaCampus.Repo.Migrations.CreateSqlFunctions do
  use Ecto.Migration

  def up do
    # Create the select_questions function
    execute """
    CREATE OR REPLACE FUNCTION select_questions(
        p_curricula_id integer,
        p_branch_id integer DEFAULT NULL,
        p_user_id integer DEFAULT NULL,
        p_subject_ids integer[] DEFAULT NULL,
        p_total_questions integer DEFAULT 20,
        p_beginner_pct numeric DEFAULT 0.40,
        p_intermediate_pct numeric DEFAULT 0.40,
        p_advanced_pct numeric DEFAULT 0.20,
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
        v_beginner_count INTEGER;
        v_intermediate_count INTEGER;
        v_advanced_count INTEGER;
    BEGIN
        -- Calculate difficulty distribution
        v_beginner_count := FLOOR(p_total_questions * p_beginner_pct);
        v_intermediate_count := FLOOR(p_total_questions * p_intermediate_pct);
        v_advanced_count := p_total_questions - v_beginner_count - v_intermediate_count;

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
                s.name AS subject_name,
                COALESCE(LOWER(qa.difficulty_level), 'beginner') AS norm_difficulty
            FROM qa
            INNER JOIN topics t ON qa.topic_id = t.id
            INNER JOIN subjects s ON t.subject_id = s.id
            INNER JOIN curricula_subjects cs ON s.id = cs.subject_id
            WHERE cs.curricula_id = p_curricula_id
                AND (p_branch_id IS NULL OR cs.branch_id = p_branch_id)
                AND (p_subject_ids IS NULL OR s.id = ANY(p_subject_ids))
        ),
        beginner_selections AS (
            SELECT
                qa_id, question, answer, options, difficulty_level, question_type,
                weightage, topic_id, topic_name, subject_id, subject_name,
                'BEGINNER' AS selection_reason,
                ROW_NUMBER() OVER (ORDER BY RANDOM()) AS rn
            FROM eligible_questions
            WHERE norm_difficulty IN ('beginner', 'easy', 'basic')
            LIMIT v_beginner_count
        ),
        intermediate_selections AS (
            SELECT
                qa_id, question, answer, options, difficulty_level, question_type,
                weightage, topic_id, topic_name, subject_id, subject_name,
                'INTERMEDIATE' AS selection_reason,
                ROW_NUMBER() OVER (ORDER BY RANDOM()) AS rn
            FROM eligible_questions
            WHERE norm_difficulty IN ('intermediate', 'medium', 'moderate')
                AND qa_id NOT IN (SELECT qa_id FROM beginner_selections)
            LIMIT v_intermediate_count
        ),
        advanced_selections AS (
            SELECT
                qa_id, question, answer, options, difficulty_level, question_type,
                weightage, topic_id, topic_name, subject_id, subject_name,
                'ADVANCED' AS selection_reason,
                ROW_NUMBER() OVER (ORDER BY RANDOM()) AS rn
            FROM eligible_questions
            WHERE norm_difficulty IN ('advanced', 'hard', 'difficult', 'expert')
                AND qa_id NOT IN (
                    SELECT qa_id FROM beginner_selections
                    UNION
                    SELECT qa_id FROM intermediate_selections
                )
            LIMIT v_advanced_count
        ),
        combined_selections AS (
            SELECT * FROM beginner_selections
            UNION ALL
            SELECT * FROM intermediate_selections
            UNION ALL
            SELECT * FROM advanced_selections
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

    # Create the create_question_set function
    execute """
    CREATE OR REPLACE FUNCTION create_question_set(
        p_name character varying,
        p_curricula_id integer,
        p_branch_id integer,
        p_user_id integer DEFAULT NULL,
        p_total_questions integer DEFAULT 20,
        p_easy_pct numeric DEFAULT 0.40,
        p_medium_pct numeric DEFAULT 0.40,
        p_hard_pct numeric DEFAULT 0.20,
        p_duration_minutes integer DEFAULT 60
    )
    RETURNS integer
    LANGUAGE plpgsql
    AS $$
    DECLARE
        v_question_set_id INTEGER;
        v_question RECORD;
    BEGIN
        -- Create question set
        INSERT INTO question_sets (
            name, curricula_id, branch_id, total_questions,
            easy_percentage, medium_percentage, hard_percentage, duration_minutes,
            inserted_at, updated_at
        ) VALUES (
            p_name, p_curricula_id, p_branch_id, p_total_questions,
            p_easy_pct, p_medium_pct, p_hard_pct, p_duration_minutes,
            NOW(), NOW()
        ) RETURNING id INTO v_question_set_id;

        -- Select and insert questions
        FOR v_question IN
            SELECT * FROM select_questions(
                p_curricula_id, p_branch_id, p_user_id, NULL, p_total_questions,
                p_easy_pct, p_medium_pct, p_hard_pct
            )
        LOOP
            INSERT INTO question_set_items (
                question_set_id, qa_id, display_order, marks,
                inserted_at, updated_at
            ) VALUES (
                v_question_set_id,
                v_question.ret_qa_id,
                v_question.ret_display_order,
                v_question.ret_weightage,
                NOW(), NOW()
            );
        END LOOP;

        RETURN v_question_set_id;
    END;
    $$;
    """
  end

  def down do
    execute "DROP FUNCTION IF EXISTS create_question_set(varchar, integer, integer, integer, integer, numeric, numeric, numeric, integer);"
    execute "DROP FUNCTION IF EXISTS select_questions(integer, integer, integer, integer[], integer, numeric, numeric, numeric, integer);"
  end
end
