defmodule VyaasaCampus.Schema.Platform.JdDecomposition do
  @moduledoc """
  Cached decomposition of a job description into discrete requirements.
  Lives in the public schema, shared across all tenants.

  A JD is decomposed by the LLM exactly ONCE (keyed by a hash of the model +
  normalized JD text). Resume relevance scoring then reuses this frozen
  requirement set on every run so identical inputs always produce identical
  requirements — and therefore stable, reproducible scores.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [:id, :jd_hash, :jd_preview, :source, :requirements, :model, :inserted_at]}

  schema "jd_decompositions" do
    field :jd_hash, :string
    field :jd_preview, :string
    field :source, :string
    field :requirements, {:array, :map}, default: []
    field :model, :string

    timestamps()
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:jd_hash, :jd_preview, :source, :requirements, :model])
    |> validate_required([:jd_hash, :requirements, :model])
    |> unique_constraint(:jd_hash)
  end
end
