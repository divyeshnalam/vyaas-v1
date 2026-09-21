defmodule VyaasaCampus.Contexts.ResumeScoreCache do
  @moduledoc """
  Cache of full resume scoring results (public schema).

  Guarantees that re-scoring an identical resume against the same role yields the
  identical result, by freezing the first successful `ResumeScorer.run/3` payload
  and returning it on every subsequent run with the same inputs. This sidesteps
  the residual non-determinism of the LLM steps in the pipeline.
  """

  import Ecto.Query, warn: false
  require Logger

  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Platform.ResumeScoreCacheEntry

  @doc """
  Return the cached result for these inputs, or run `score_fun` on a miss and
  cache its `{:ok, result}` payload.

  `score_fun` is a 0-arity function returning `{:ok, map}` or `{:error, reason}`.
  Only successful results are cached; errors pass through uncached. Never raises:
  on any DB error it falls back to running `score_fun` directly.

  ## Params
    * `parts`   — list of binaries that identify the input (resume bytes, job
      profile, JD, ...). Order matters.
    * `version` — scorer version tag folded into the key.
  """
  def get_or_score(parts, version, score_fun)
      when is_list(parts) and is_binary(version) and is_function(score_fun, 0) do
    hash = cache_key(parts, version)

    case safe_get(hash) do
      %ResumeScoreCacheEntry{result: result} when is_map(result) ->
        Logger.info("RESUME_CACHE | hit | hash=#{String.slice(hash, 0, 12)}")
        {:ok, result}

      _miss ->
        case score_fun.() do
          {:ok, result} = ok when is_map(result) ->
            store(hash, version, result)
            Logger.info("RESUME_CACHE | miss→stored | hash=#{String.slice(hash, 0, 12)}")
            ok

          other ->
            other
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp cache_key(parts, version) do
    payload = Enum.map_join([version | parts], "\0", &to_string/1)
    :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
  end

  defp safe_get(hash) do
    Repo.get_by(ResumeScoreCacheEntry, input_hash: hash)
  rescue
    e ->
      Logger.warning("RESUME_CACHE | lookup failed: #{Exception.message(e)}")
      nil
  end

  defp store(hash, version, result) do
    %ResumeScoreCacheEntry{}
    |> ResumeScoreCacheEntry.changeset(%{
      input_hash: hash,
      scorer_version: version,
      result: result
    })
    |> Repo.insert(
      on_conflict: {:replace, [:result, :scorer_version, :updated_at]},
      conflict_target: :input_hash
    )
  rescue
    e ->
      Logger.warning("RESUME_CACHE | store failed: #{Exception.message(e)}")
      {:error, :store_failed}
  end
end
