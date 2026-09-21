defmodule VyaasaCampus.Repo.Migrations.CreateJdDecompositions do
  use Ecto.Migration

  # Public (shared) table. Caches the LLM decomposition of a job description into
  # discrete requirements so resume relevance scoring reuses the SAME decomposed
  # rubric every time instead of re-running the LLM (which is slow and produces
  # slightly different requirement sets each run → inconsistent scores).
  def change do
    create table(:jd_decompositions) do
      # sha256 over (model + normalized JD text) — identical JD ⇒ identical key.
      add :jd_hash, :string, null: false
      # First slice of the JD, for human debugging only.
      add :jd_preview, :text
      # Optional human label (role / file name) when seeded from the JD library.
      add :source, :string
      # The frozen decomposition: [{"text","criticality","type"}, ...].
      add :requirements, {:array, :map}, null: false, default: []
      # Model used to produce the decomposition (part of the cache key).
      add :model, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:jd_decompositions, [:jd_hash])
  end
end
