defmodule VyaasaCampus.Repo.Migrations.CreateResumeScoreCache do
  use Ecto.Migration

  # Public (shared) table. Caches the FULL scored result for a resume so that
  # re-uploading the identical resume against the same role always returns the
  # exact same score. The scoring pipeline makes several LLM calls that are not
  # bit-for-bit deterministic even at temperature 0 (MoE routing / batching /
  # GPU float non-associativity), so freezing the first result is the only way
  # to guarantee reproducibility.
  def change do
    create table(:resume_score_cache) do
      # sha256 over (scorer_version + resume bytes + job_profile + job_description).
      add :input_hash, :string, null: false
      # Scorer version tag (bumping it invalidates all prior cache entries).
      add :scorer_version, :string, null: false
      # The full ResumeScorer.run/3 success payload (service_response).
      add :result, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:resume_score_cache, [:input_hash])
  end
end
