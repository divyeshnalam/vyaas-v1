defmodule VyaasaCampus.Repo.Migrations.FixSelectQuestionsRandomization do
  @moduledoc """
  Phase 1 correctness fixes for the select_questions() SQL function,
  building on the normalised easy/medium/hard schema from 20260403100000.

  Changes vs. 20260403100000:
    1. Each difficulty CTE now uses `ORDER BY RANDOM() LIMIT n` directly.
       The previous version computed `ROW_NUMBER() OVER (ORDER BY RANDOM())`
       in the SELECT list but applied `LIMIT` with no ORDER BY, which by
       Postgres' rules returns an unpredictable subset rather than a random one.
    2. Adds a top-up pass: if any difficulty bucket is short of its quota
       (e.g. only 3 hard questions exist but 12 are requested), the remaining
       slots are filled randomly from any leftover eligible question so the
       paper always reaches p_total_questions when supply allows, instead of
       silently returning short. Top-up rows are tagged 'TOPUP' so this is
       visible in admin tooling.
    3. Accepts branch-agnostic curricula_subjects rows (`branch_id IS NULL`)
       when a branch filter is supplied, matching the intent of the Elixir
       wrapper in select_questions_excluding_subject/4.
    4. `MATERIALIZED` hints prevent Postgres 12+ from inlining CTEs and
       re-rolling RANDOM() during NOT IN sub-queries.

  Signature, parameter names/defaults, and RETURNS TABLE shape are unchanged
  from 20260403100000, so CREATE OR REPLACE works without DROP and existing
  callers (`create_question_set`, Elixir `select_questions_by_subject/7`)
  continue to work without modification.
  """

  use Ecto.Migration

  def up do
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
        v_easy_count := FLOOR(p_total_questions * p_easy_pct);
        v_medium_count := FLOOR(p_total_questions * p_medium_pct);
        v_hard_count := p_total_questions - v_easy_count - v_medium_count;

        RETURN QUERY
        WITH eligible_questions AS MATERIALIZED (
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
                AND (p_branch_id IS NULL OR cs.branch_id = p_branch_id OR cs.branch_id IS NULL)
                AND (p_subject_ids IS NULL OR s.id = ANY(p_subject_ids))
        ),
        easy_selections AS MATERIALIZED (
            SELECT
                qa_id, question, answer, options, difficulty_level, question_type,
                weightage, topic_id, topic_name, subject_id, subject_name,
                'EASY'::VARCHAR AS selection_reason
            FROM eligible_questions
            WHERE difficulty_level = 'easy'
            ORDER BY RANDOM()
            LIMIT v_easy_count
        ),
        medium_selections AS MATERIALIZED (
            SELECT
                qa_id, question, answer, options, difficulty_level, question_type,
                weightage, topic_id, topic_name, subject_id, subject_name,
                'MEDIUM'::VARCHAR AS selection_reason
            FROM eligible_questions
            WHERE difficulty_level = 'medium'
                AND qa_id NOT IN (SELECT qa_id FROM easy_selections)
            ORDER BY RANDOM()
            LIMIT v_medium_count
        ),
        hard_selections AS MATERIALIZED (
            SELECT
                qa_id, question, answer, options, difficulty_level, question_type,
                weightage, topic_id, topic_name, subject_id, subject_name,
                'HARD'::VARCHAR AS selection_reason
            FROM eligible_questions
            WHERE difficulty_level = 'hard'
                AND qa_id NOT IN (SELECT qa_id FROM easy_selections)
                AND qa_id NOT IN (SELECT qa_id FROM medium_selections)
            ORDER BY RANDOM()
            LIMIT v_hard_count
        ),
        primary_selections AS MATERIALIZED (
            SELECT * FROM easy_selections
            UNION ALL
            SELECT * FROM medium_selections
            UNION ALL
            SELECT * FROM hard_selections
        ),
        topup_selections AS MATERIALIZED (
            SELECT
                qa_id, question, answer, options, difficulty_level, question_type,
                weightage, topic_id, topic_name, subject_id, subject_name,
                'TOPUP'::VARCHAR AS selection_reason
            FROM eligible_questions
            WHERE qa_id NOT IN (SELECT qa_id FROM primary_selections)
            ORDER BY RANDOM()
            LIMIT GREATEST(
                p_total_questions - (SELECT COUNT(*)::int FROM primary_selections),
                0
            )
        ),
        combined_selections AS (
            SELECT * FROM primary_selections
            UNION ALL
            SELECT * FROM topup_selections
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
        FROM combined_selections cs;
    END;
    $$;
    """
  end

  def down do
    # Restore the definition from 20260403100000_normalize_difficulty_levels.
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
  end
end
