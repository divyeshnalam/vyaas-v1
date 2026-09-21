defmodule VyaasaCampus.Schema.Platform.ResumeScoreCacheEntry do
  @moduledoc """
  Cached full scoring result for a resume (public schema, shared across tenants).

  Keyed by a hash of the scorer version + resume bytes + job profile + JD, so an
  identical resume scored against the same role always returns the same result.
  See `VyaasaCampus.Contexts.ResumeScoreCache`.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  schema "resume_score_cache" do
    field :input_hash, :string
    field :scorer_version, :string
    field :result, :map

    timestamps()
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:input_hash, :scorer_version, :result])
    |> validate_required([:input_hash, :scorer_version, :result])
    |> unique_constraint(:input_hash)
  end
end
