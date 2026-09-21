defmodule Mix.Tasks.Jd.Seed do
  @moduledoc """
  Pre-decompose a library of job descriptions into the shared `jd_decompositions`
  cache so relevance scoring can reuse a frozen requirement rubric.

  Accepts either a `.zip` of `.txt` JDs (organized in folders) or a directory of
  `.txt` files. Each JD is decomposed once via the LLM and stored keyed by a hash
  of its text; re-running is idempotent (existing entries are reused, not re-hit).

      mix jd.seed All_JDs.zip
      mix jd.seed path/to/jd_dir

  The row `source` is the JD's relative path (e.g. "Data_Science/Data_Scientist_JD.txt"),
  useful for inspection in the DB.
  """
  use Mix.Task

  alias VyaasaCampus.AI.Resume.Relevance

  @shortdoc "Decompose a JD library (zip or dir) into the jd_decompositions cache"

  @impl true
  def run(args) do
    source =
      case args do
        [path | _] -> path
        [] -> "All_JDs.zip"
      end

    unless File.exists?(source) do
      Mix.raise("JD source not found: #{source}")
    end

    Mix.Task.run("app.start")

    {dir, cleanup} = prepare_dir(source)

    jds = collect_jds(dir)

    if jds == [] do
      Mix.shell().info("No .txt JD files found under #{source}")
    else
      Mix.shell().info("Seeding #{length(jds)} JD(s) from #{source}...")

      Enum.each(jds, fn {rel, text} ->
        reqs = Relevance.cache_jd(text, rel)
        Mix.shell().info("  • #{rel} → #{length(reqs)} requirements")
      end)

      Mix.shell().info("Done. Cached #{length(jds)} JD decomposition(s).")
    end

    cleanup.()
  end

  # Zip → extract to a temp dir; plain dir → use as-is.
  defp prepare_dir(source) do
    if String.ends_with?(String.downcase(source), ".zip") do
      tmp = Path.join(System.tmp_dir!(), "jd_seed_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      {:ok, _} =
        :zip.unzip(String.to_charlist(source), [{:cwd, String.to_charlist(tmp)}])

      {tmp, fn -> File.rm_rf(tmp) end}
    else
      {source, fn -> :ok end}
    end
  end

  defp collect_jds(dir) do
    dir
    |> Path.join("**/*.txt")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      rel = Path.relative_to(path, dir)
      {rel, File.read!(path)}
    end)
    |> Enum.filter(fn {_rel, text} -> String.trim(text) != "" end)
  end
end
