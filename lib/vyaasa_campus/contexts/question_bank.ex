defmodule VyaasaCampus.Contexts.QuestionBank do
  @moduledoc """
  Context for managing question bank including qualifications, branches, curricula, subjects, topics and questions.
  """

  import Ecto.Query, warn: false
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.QuestionBank.{Qualification, Branch, Curriculum, Subject, Topic, QA}

  # ============================================================================
  # QUALIFICATIONS
  # ============================================================================

  def list_qualifications do
    Repo.all(Qualification)
  end

  def get_qualification!(id) do
    Repo.get!(Qualification, id)
  end

  def create_qualification(attrs) do
    %Qualification{}
    |> Qualification.changeset(attrs)
    |> Repo.insert()
  end

  def update_qualification(%Qualification{} = qualification, attrs) do
    qualification
    |> Qualification.changeset(attrs)
    |> Repo.update()
  end

  def delete_qualification(%Qualification{} = qualification) do
    Repo.delete(qualification)
  end

  # ============================================================================
  # BRANCHES
  # ============================================================================

  def list_branches do
    Repo.all(Branch) |> Repo.preload(:qualification)
  end

  def list_branches_by_qualification(qualification_id) do
    Branch
    |> where([b], b.qualification_id == ^qualification_id)
    |> Repo.all()
  end

  def get_branch!(id) do
    Repo.get!(Branch, id) |> Repo.preload(:qualification)
  end

  def create_branch(attrs) do
    %Branch{}
    |> Branch.changeset(attrs)
    |> Repo.insert()
  end

  def update_branch(%Branch{} = branch, attrs) do
    branch
    |> Branch.changeset(attrs)
    |> Repo.update()
  end

  def delete_branch(%Branch{} = branch) do
    Repo.delete(branch)
  end

  # ============================================================================
  # CURRICULA
  # ============================================================================

  def list_curricula do
    Repo.all(Curriculum) |> Repo.preload(:branch)
  end

  def list_curricula_by_branch(branch_id) do
    Curriculum
    |> where([c], c.branch_id == ^branch_id)
    |> Repo.all()
  end

  def get_curriculum!(id) do
    Repo.get!(Curriculum, id) |> Repo.preload([:branch, :subjects])
  end

  def create_curriculum(attrs) do
    %Curriculum{}
    |> Curriculum.changeset(attrs)
    |> Repo.insert()
  end

  def update_curriculum(%Curriculum{} = curriculum, attrs) do
    curriculum
    |> Curriculum.changeset(attrs)
    |> Repo.update()
  end

  def delete_curriculum(%Curriculum{} = curriculum) do
    Repo.delete(curriculum)
  end

  # ============================================================================
  # SUBJECTS
  # ============================================================================

  def list_subjects do
    Repo.all(Subject)
  end

  def get_subject!(id) do
    Repo.get!(Subject, id) |> Repo.preload(:topics)
  end

  def create_subject(attrs) do
    %Subject{}
    |> Subject.changeset(attrs)
    |> Repo.insert()
  end

  def update_subject(%Subject{} = subject, attrs) do
    subject
    |> Subject.changeset(attrs)
    |> Repo.update()
  end

  def delete_subject(%Subject{} = subject) do
    Repo.delete(subject)
  end

  # ============================================================================
  # TOPICS
  # ============================================================================

  def list_topics do
    Repo.all(Topic) |> Repo.preload(:subject)
  end

  def list_topics_by_subject(subject_id) do
    Topic
    |> where([t], t.subject_id == ^subject_id)
    |> Repo.all()
  end

  def get_topic!(id) do
    Repo.get!(Topic, id) |> Repo.preload([:subject, :questions])
  end

  def create_topic(attrs) do
    %Topic{}
    |> Topic.changeset(attrs)
    |> Repo.insert()
  end

  def update_topic(%Topic{} = topic, attrs) do
    topic
    |> Topic.changeset(attrs)
    |> Repo.update()
  end

  def delete_topic(%Topic{} = topic) do
    Repo.delete(topic)
  end

  # ============================================================================
  # QUESTIONS (QA)
  # ============================================================================

  def list_questions do
    Repo.all(QA) |> Repo.preload(:topic)
  end

  def list_questions_by_topic(topic_id) do
    QA
    |> where([q], q.topic_id == ^topic_id)
    |> Repo.all()
  end

  def list_questions_by_difficulty(difficulty_level) do
    QA
    |> where([q], q.difficulty_level == ^difficulty_level)
    |> Repo.all()
    |> Repo.preload(:topic)
  end

  def list_questions_by_type(type) do
    QA
    |> where([q], q.type == ^type)
    |> Repo.all()
    |> Repo.preload(:topic)
  end

  def get_question!(id) do
    Repo.get!(QA, id) |> Repo.preload(:topic)
  end

  def create_question(attrs) do
    %QA{}
    |> QA.changeset(attrs)
    |> Repo.insert()
  end

  def update_question(%QA{} = question, attrs) do
    question
    |> QA.changeset(attrs)
    |> Repo.update()
  end

  def delete_question(%QA{} = question) do
    Repo.delete(question)
  end

  @doc """
  Search questions by filters
  """
  def search_questions(filters \\ %{}) do
    QA
    |> apply_question_filters(filters)
    |> Repo.all()
    |> Repo.preload(:topic)
  end

  defp apply_question_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:topic_id, topic_id}, query when not is_nil(topic_id) ->
        where(query, [q], q.topic_id == ^topic_id)

      {:difficulty_level, level}, query when not is_nil(level) ->
        where(query, [q], q.difficulty_level == ^level)

      {:type, type}, query when not is_nil(type) ->
        where(query, [q], q.type == ^type)

      {:search, search_term}, query when not is_nil(search_term) and search_term != "" ->
        search_pattern = "%#{search_term}%"
        where(query, [q], ilike(q.question, ^search_pattern))

      _, query ->
        query
    end)
  end

  @doc """
  Get random questions by criteria for assessment generation
  """
  def get_random_questions(count, filters \\ %{}) do
    QA
    |> apply_question_filters(filters)
    |> order_by(fragment("RANDOM()"))
    |> limit(^count)
    |> Repo.all()
    |> Repo.preload(:topic)
  end

  @doc """
  Bulk import questions from CSV/JSON
  """
  def bulk_import_questions(questions_data) when is_list(questions_data) do
    Enum.reduce_while(questions_data, {:ok, []}, fn question_attrs, {:ok, acc} ->
      case create_question(question_attrs) do
        {:ok, question} -> {:cont, {:ok, [question | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, questions} -> {:ok, Enum.reverse(questions)}
      error -> error
    end
  end
end
