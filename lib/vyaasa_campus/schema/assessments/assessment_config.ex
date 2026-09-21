defmodule VyaasaCampus.Schema.Assessments.AssessmentConfig do
  @moduledoc """
  Schema for per-tenant MCQ assessment configuration.
  Stores settings like question counts, aptitude/technical split,
  difficulty distribution, duration, and negative marking.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           only: [
             :id,
             :tenant_id,
             :total_questions,
             :aptitude_percentage,
             :technical_percentage,
             :duration_minutes,
             :negative_marking,
             :easy_percentage,
             :medium_percentage,
             :hard_percentage,
             :passing_percentage,
             :is_active,
             :inserted_at,
             :updated_at
           ]}

  schema "assessment_configs" do
    field :tenant_id, :binary_id
    field :total_questions, :integer, default: 60
    field :aptitude_percentage, :integer, default: 40
    field :technical_percentage, :integer, default: 60
    field :duration_minutes, :integer, default: 90
    field :negative_marking, :decimal, default: Decimal.new("0.25")
    field :easy_percentage, :integer, default: 40
    field :medium_percentage, :integer, default: 40
    field :hard_percentage, :integer, default: 20
    field :passing_percentage, :integer, default: 50
    field :is_active, :boolean, default: true
    field :created_by, :binary_id

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :tenant_id,
      :total_questions,
      :aptitude_percentage,
      :technical_percentage,
      :duration_minutes,
      :negative_marking,
      :easy_percentage,
      :medium_percentage,
      :hard_percentage,
      :passing_percentage,
      :is_active,
      :created_by
    ])
    |> validate_required([
      :tenant_id,
      :total_questions,
      :aptitude_percentage,
      :technical_percentage,
      :duration_minutes,
      :negative_marking,
      :easy_percentage,
      :medium_percentage,
      :hard_percentage,
      :passing_percentage
    ])
    |> validate_number(:total_questions, greater_than: 0, less_than_or_equal_to: 200)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 300)
    |> validate_number(:aptitude_percentage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:technical_percentage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:easy_percentage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:medium_percentage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:hard_percentage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:passing_percentage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:negative_marking, greater_than_or_equal_to: Decimal.new("0"), less_than_or_equal_to: Decimal.new("1"))
    |> validate_percentage_sum(:aptitude_percentage, :technical_percentage, "Aptitude + Technical must equal 100")
    |> validate_percentage_sum_3(:easy_percentage, :medium_percentage, :hard_percentage, "Easy + Medium + Hard must equal 100")
    |> unique_constraint(:tenant_id)
  end

  defp validate_percentage_sum(changeset, field1, field2, message) do
    v1 = get_field(changeset, field1) || 0
    v2 = get_field(changeset, field2) || 0

    if v1 + v2 != 100 do
      add_error(changeset, field1, message)
    else
      changeset
    end
  end

  defp validate_percentage_sum_3(changeset, f1, f2, f3, message) do
    v1 = get_field(changeset, f1) || 0
    v2 = get_field(changeset, f2) || 0
    v3 = get_field(changeset, f3) || 0

    if v1 + v2 + v3 != 100 do
      add_error(changeset, f1, message)
    else
      changeset
    end
  end
end
