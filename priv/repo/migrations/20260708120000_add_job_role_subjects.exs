defmodule VyaasaCampus.Repo.Migrations.AddJobRoleSubjects do
  use Ecto.Migration

  @moduledoc """
  Role-aware Objective/MCQ selection (Vya-036, MBA→CS default).

  Adds a `job_role_subjects` blueprint mapping each job role to the subjects it
  is tested on (+ a per-subject question quota), and a `select_questions_by_subjects`
  function that draws questions straight from those subjects — independent of the
  student's degree/curriculum, so the assessment follows the chosen job role.
  """

  def up do
    create table(:job_role_subjects) do
      add :job_role_id, references(:job_roles, on_delete: :delete_all), null: false
      add :subject_id, references(:subjects, on_delete: :delete_all), null: false
      # How many questions to draw from this subject for this role.
      add :question_count, :integer, null: false, default: 0
      timestamps()
    end

    create index(:job_role_subjects, [:job_role_id])
    create index(:job_role_subjects, [:subject_id])
    create unique_index(:job_role_subjects, [:job_role_id, :subject_id])

    execute """
    CREATE OR REPLACE FUNCTION select_questions_by_subjects(
        p_subject_ids integer[],
        p_total_questions integer DEFAULT 20,
        p_easy_pct numeric DEFAULT 0.40,
        p_medium_pct numeric DEFAULT 0.40,
        p_hard_pct numeric DEFAULT 0.20
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
    AS $func$
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
                qa.id AS qa_id, qa.question, qa.answer, qa.options,
                qa.difficulty_level, qa.type AS question_type, qa.weightage,
                t.id AS topic_id, t.name AS topic_name,
                s.id AS subject_id, s.name AS subject_name
            FROM qa
            INNER JOIN topics t ON qa.topic_id = t.id
            INNER JOIN subjects s ON t.subject_id = s.id
            WHERE s.id = ANY(p_subject_ids)
        ),
        easy_selections AS MATERIALIZED (
            SELECT qa_id, question, answer, options, difficulty_level, question_type,
                   weightage, topic_id, topic_name, subject_id, subject_name,
                   'EASY'::VARCHAR AS selection_reason
            FROM eligible_questions WHERE difficulty_level = 'easy'
            ORDER BY RANDOM() LIMIT v_easy_count
        ),
        medium_selections AS MATERIALIZED (
            SELECT qa_id, question, answer, options, difficulty_level, question_type,
                   weightage, topic_id, topic_name, subject_id, subject_name,
                   'MEDIUM'::VARCHAR AS selection_reason
            FROM eligible_questions
            WHERE difficulty_level = 'medium'
              AND qa_id NOT IN (SELECT qa_id FROM easy_selections)
            ORDER BY RANDOM() LIMIT v_medium_count
        ),
        hard_selections AS MATERIALIZED (
            SELECT qa_id, question, answer, options, difficulty_level, question_type,
                   weightage, topic_id, topic_name, subject_id, subject_name,
                   'HARD'::VARCHAR AS selection_reason
            FROM eligible_questions
            WHERE difficulty_level = 'hard'
              AND qa_id NOT IN (SELECT qa_id FROM easy_selections)
              AND qa_id NOT IN (SELECT qa_id FROM medium_selections)
            ORDER BY RANDOM() LIMIT v_hard_count
        ),
        primary_selections AS MATERIALIZED (
            SELECT * FROM easy_selections
            UNION ALL SELECT * FROM medium_selections
            UNION ALL SELECT * FROM hard_selections
        ),
        topup_selections AS MATERIALIZED (
            SELECT qa_id, question, answer, options, difficulty_level, question_type,
                   weightage, topic_id, topic_name, subject_id, subject_name,
                   'TOPUP'::VARCHAR AS selection_reason
            FROM eligible_questions
            WHERE qa_id NOT IN (SELECT qa_id FROM primary_selections)
            ORDER BY RANDOM()
            LIMIT GREATEST(p_total_questions - (SELECT COUNT(*)::int FROM primary_selections), 0)
        ),
        combined_selections AS (
            SELECT * FROM primary_selections
            UNION ALL SELECT * FROM topup_selections
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
            (ROW_NUMBER() OVER (ORDER BY RANDOM()))::INTEGER AS display_order
        FROM combined_selections cs;
    END;
    $func$;
    """
  end

  def down do
    execute "DROP FUNCTION IF EXISTS select_questions_by_subjects(integer[], integer, numeric, numeric, numeric)"
    drop table(:job_role_subjects)
  end
end
