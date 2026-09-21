defmodule VyaasaCampus.Schema.QuestionBank.QA do
  @moduledoc """
  QA (Question & Answer) schema representing MCQ questions.

  Supports multiple question types:
  - multiple_choice: Single correct answer from options
  - multiple_select: Multiple correct answers
  - true_false: Boolean questions
  - fill_in_blank: Text-based answers
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :question,
             :answer,
             :difficulty_level,
             :options,
             :type,
             :weightage,
             :topic_id,
             :inserted_at,
             :updated_at
           ]}

  schema "qa" do
    field :question, :string
    field :answer, :string
    field :difficulty_level, :string
    field :options, :map, default: %{}
    field :type, :string, default: "multiple_choice"
    field :weightage, :decimal, default: Decimal.new("1.0")

    belongs_to :topic, VyaasaCampus.Schema.QuestionBank.Topic

    timestamps()
  end

  @valid_types ["multiple_choice", "multiple_select", "true_false", "fill_in_blank", "short_answer"]
  @valid_difficulty_levels ["easy", "medium", "hard"]

  def changeset(qa, attrs) do
    qa
    |> cast(attrs, [:question, :answer, :difficulty_level, :options, :type, :weightage, :topic_id])
    |> validate_required([:question, :type])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:difficulty_level, @valid_difficulty_levels,
      message: "must be one of: #{Enum.join(@valid_difficulty_levels, ", ")}"
    )
    |> validate_length(:question, min: 10, max: 5000)
    |> validate_number(:weightage, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_options()
    |> foreign_key_constraint(:topic_id)
  end

  defp validate_options(changeset) do
    type = get_field(changeset, :type)
    options = get_field(changeset, :options)

    case type do
      "multiple_choice" -> validate_multiple_choice_options(changeset, options)
      "multiple_select" -> validate_multiple_select_options(changeset, options)
      "true_false" -> validate_true_false_options(changeset, options)
      _ -> changeset
    end
  end

  defp validate_multiple_choice_options(changeset, options) when is_map(options) do
    cond do
      !Map.has_key?(options, "options") and !Map.has_key?(options, :options) ->
        add_error(changeset, :options, "must contain 'options' array for multiple choice questions")

      !Map.has_key?(options, "correct_answer") and !Map.has_key?(options, :correct_answer) ->
        add_error(changeset, :options, "must contain 'correct_answer' for multiple choice questions")

      true ->
        opts = options["options"] || options[:options] || []

        if length(opts) < 2 do
          add_error(changeset, :options, "must have at least 2 options")
        else
          changeset
        end
    end
  end

  defp validate_multiple_choice_options(changeset, _), do: changeset

  defp validate_multiple_select_options(changeset, options) when is_map(options) do
    cond do
      !Map.has_key?(options, "options") and !Map.has_key?(options, :options) ->
        add_error(changeset, :options, "must contain 'options' array for multiple select questions")

      !Map.has_key?(options, "correct_answers") and !Map.has_key?(options, :correct_answers) ->
        add_error(changeset, :options, "must contain 'correct_answers' array for multiple select questions")

      true ->
        changeset
    end
  end

  defp validate_multiple_select_options(changeset, _), do: changeset

  defp validate_true_false_options(changeset, options) when is_map(options) do
    if !Map.has_key?(options, "correct_answer") and !Map.has_key?(options, :correct_answer) do
      add_error(changeset, :options, "must contain 'correct_answer' (true/false) for true/false questions")
    else
      changeset
    end
  end

  defp validate_true_false_options(changeset, _), do: changeset

  @doc """
  Returns list of valid question types
  """
  def valid_types, do: @valid_types

  @doc """
  Returns list of valid difficulty levels
  """
  def valid_difficulty_levels, do: @valid_difficulty_levels
end
