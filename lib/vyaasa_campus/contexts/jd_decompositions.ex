defmodule VyaasaCampus.Contexts.JdDecompositions do
  @moduledoc """
  Cache of decomposed job descriptions (public schema).

  Resume relevance scoring must judge every resume against the SAME set of JD
  requirements to produce reproducible scores. Re-running the LLM decomposition
  on each score is slow and non-deterministic, so we decompose a JD once, store
  the requirement list, and hand back the stored copy on every subsequent call.
  """

  import Ecto.Query, warn: false
  require Logger

  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Platform.JdDecomposition

  @doc """
  Return the frozen requirement list for `jd_text`, decomposing (and persisting)
  it once on a cache miss.

  `decompose_fun` is a 1-arity function that takes the JD text and returns the
  requirement list (`[%{"text" => ..., "criticality" => ..., "type" => ...}]`).
  It is only invoked on a miss.

  Never raises: on any DB error it falls back to calling `decompose_fun` so
  scoring keeps working even if the cache is unavailable.

  Options:
    * `:model`  — model tag folded into the cache key (default: `"default"`).
    * `:source` — optional human label stored on first insert (role / filename).
  """
  def get_or_decompose(jd_text, decompose_fun, opts \\ [])
      when is_binary(jd_text) and is_function(decompose_fun, 1) do
    model = Keyword.get(opts, :model, "default")
    hash = cache_key(jd_text, model)

    case safe_get(hash) do
      %JdDecomposition{requirements: reqs} when is_list(reqs) and reqs != [] ->
        Logger.info("JD_CACHE | hit | hash=#{String.slice(hash, 0, 12)} | reqs=#{length(reqs)}")
        reqs

      _miss ->
        reqs = decompose_fun.(jd_text)

        if is_list(reqs) and reqs != [] do
          store(hash, jd_text, reqs, model, Keyword.get(opts, :source))
          Logger.info("JD_CACHE | miss→stored | hash=#{String.slice(hash, 0, 12)} | reqs=#{length(reqs)}")
        end

        reqs
    end
  end

  @doc "Insert or update a decomposition for pre-seeding a JD library."
  def upsert(jd_text, requirements, opts \\ []) when is_binary(jd_text) and is_list(requirements) do
    model = Keyword.get(opts, :model, "default")
    store(cache_key(jd_text, model), jd_text, requirements, model, Keyword.get(opts, :source))
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  # Normalize so trivial whitespace / case differences still hit the same cache
  # entry, then hash together with the model tag (a model change re-decomposes).
  defp cache_key(jd_text, model) do
    normalized =
      jd_text
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/u, " ")

    :crypto.hash(:sha256, model <> "\n" <> normalized) |> Base.encode16(case: :lower)
  end

  defp safe_get(hash) do
    Repo.get_by(JdDecomposition, jd_hash: hash)
  rescue
    e ->
      Logger.warning("JD_CACHE | lookup failed: #{Exception.message(e)}")
      nil
  end

  defp store(hash, jd_text, requirements, model, source) do
    attrs = %{
      jd_hash: hash,
      jd_preview: String.slice(jd_text, 0, 500),
      source: source,
      requirements: requirements,
      model: model
    }

    %JdDecomposition{}
    |> JdDecomposition.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:requirements, :jd_preview, :source, :model, :updated_at]},
      conflict_target: :jd_hash
    )
  rescue
    e ->
      Logger.warning("JD_CACHE | store failed: #{Exception.message(e)}")
      {:error, :store_failed}
  end
end
