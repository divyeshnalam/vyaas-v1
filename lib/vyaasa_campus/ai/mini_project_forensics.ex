defmodule VyaasaCampus.AI.MiniProjectForensics do
  @moduledoc """
  Authenticity / provenance forensics for Mini Project submissions.

  Mini Project is a 24h take-home, so browser proctoring is useless — the real
  question is whether THIS student did THIS work DURING the window. We look at:

    * **File metadata** — created / modified / author embedded in PDF (pdfinfo)
      and OOXML docx/pptx/xlsx (docProps/core.xml).
    * **Git commits** — repo age + commit timeline via the GitHub API.

  Everything is advisory: it produces flags + an authenticity score (0-100,
  higher = more trustworthy) for admin review, and never auto-fails a student.
  Metadata can be stripped/spoofed, so absence of signal is not proof of guilt.
  """
  require Logger

  # created ≈ modified within this many seconds => likely downloaded, not authored
  @instant_edit_seconds 180

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Per-file provenance from embedded metadata. Returns a JSON-safe map with ISO
  string timestamps (or nil when the format carries no metadata).
  """
  def analyze_file(filename, binary) when is_binary(binary) do
    ext = filename |> Path.extname() |> String.downcase()

    base = %{
      "filename" => filename,
      "created" => nil,
      "modified" => nil,
      "author" => nil,
      "last_modified_by" => nil,
      "source" => "unsupported"
    }

    data =
      cond do
        ext == ".pdf" -> pdf_meta(binary)
        ext in [".docx", ".pptx", ".xlsx"] -> ooxml_meta(binary)
        true -> %{}
      end

    Map.merge(base, data)
  end

  @doc """
  Commit-history provenance for a GitHub repo via the API. Returns a JSON-safe
  map: repo age, commit count, first/last commit, single-dump?, committer names.
  Fails soft to `%{"source" => "unreachable"}` on any error.
  """
  def analyze_repo(url) do
    with {:ok, owner, repo} <- parse_github(url),
         {:ok, meta} <- gh_get("https://api.github.com/repos/#{owner}/#{repo}"),
         {:ok, commits} when is_list(commits) <-
           gh_get("https://api.github.com/repos/#{owner}/#{repo}/commits?per_page=100") do
      dates =
        commits
        |> Enum.map(&get_in(&1, ["commit", "author", "date"]))
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&iso/1)
        |> Enum.filter(& &1)
        |> Enum.sort()

      committers =
        commits
        |> Enum.map(&get_in(&1, ["commit", "author", "name"]))
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()

      %{
        "source" => "github_api",
        "repo_created" => iso(meta["created_at"]),
        "repo_pushed" => iso(meta["pushed_at"]),
        "commit_count" => length(commits),
        "first_commit" => List.first(dates),
        "last_commit" => List.last(dates),
        "committers" => committers
      }
    else
      _ -> %{"source" => "unreachable"}
    end
  end

  @doc """
  Combine file + repo provenance against the assessment window into an
  authenticity report: `%{"score" => 0..100, "flags" => [...], ...}`.
  `window_start` / `window_end` are DateTimes (session start .. submission).
  """
  def authenticity_report(file_analyses, repo_analysis, window_start, window_end, student_name) do
    file_flags = file_analyses |> Enum.flat_map(&file_flags(&1, window_start, student_name))
    repo_flags = repo_flags(repo_analysis, window_start)

    # Submitted almost immediately after starting a 24h take-home → likely
    # pre-made work pasted in.
    speed_flags =
      if window_start && window_end && DateTime.diff(window_end, window_start) in 0..600 do
        [%{weight: 20, text: "Submitted #{DateTime.diff(window_end, window_start)} s after starting — far too fast for real work"}]
      else
        []
      end

    flags = file_flags ++ repo_flags ++ speed_flags

    # Start at 100, subtract per flag (weighted), floor at 0.
    penalty = Enum.reduce(flags, 0, fn f, acc -> acc + f.weight end)
    score = max(0, 100 - penalty)

    %{
      "score" => score,
      "verdict" => verdict(score),
      "flags" => Enum.map(flags, & &1.text),
      "files" => file_analyses,
      "repo" => repo_analysis,
      "checked_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Authorship signal from the viva: if the student couldn't explain their own
  submission (low average answer score), that's a red flag on a take-home.
  Returns `{:flag, penalty, text}` or `:ok`.
  """
  def viva_authorship_flag(viva_turns) do
    scores =
      (viva_turns || [])
      |> Enum.map(& &1["answer_score"])
      |> Enum.filter(&is_number/1)

    if length(scores) >= 2 do
      avg = Enum.sum(scores) / length(scores)

      if avg < 4.0 do
        {:flag, 30,
         "Struggled to explain their own submission in the viva (avg #{Float.round(avg, 1)}/10) — possible authorship concern"}
      else
        :ok
      end
    else
      :ok
    end
  end

  @doc "Merge a new flag + penalty into an existing authenticity report."
  def add_report_flag(%{} = report, penalty, text) do
    flags = (report["flags"] || []) ++ [text]
    score = max(0, (report["score"] || 100) - penalty)

    report
    |> Map.put("flags", flags)
    |> Map.put("score", score)
    |> Map.put("verdict", verdict(score))
  end

  def add_report_flag(_report, _penalty, _text), do: nil

  @doc "Readable admin flags from a stored authenticity report."
  def admin_flags(%{"flags" => flags, "score" => score}) when is_list(flags) and flags != [] do
    ["Mini Project — authenticity #{score}/100: " <> Enum.join(flags, "; ")]
  end

  def admin_flags(_), do: []

  # ── File flags ──────────────────────────────────────────────────────────────

  defp file_flags(a, window_start, student_name) do
    created = parse(a["created"])
    modified = parse(a["modified"])
    author = a["author"] || a["last_modified_by"]

    []
    |> add_flag(
      created && window_start && DateTime.compare(created, window_start) == :lt,
      35,
      "\"#{a["filename"]}\" was created #{ago(created, window_start)} BEFORE the assessment started"
    )
    |> add_flag(
      author && student_name && name_mismatch?(author, student_name),
      25,
      "\"#{a["filename"]}\" author is \"#{author}\", not the student"
    )
    |> add_flag(
      created && modified && DateTime.diff(modified, created) <= @instant_edit_seconds and
        DateTime.diff(modified, created) >= 0,
      20,
      "\"#{a["filename"]}\" was created and last-saved within #{@instant_edit_seconds} s (likely downloaded, not authored)"
    )
  end

  # ── Repo flags ──────────────────────────────────────────────────────────────

  defp repo_flags(%{"source" => "github_api"} = r, window_start) do
    created = parse(r["repo_created"])
    first = parse(r["first_commit"])
    last = parse(r["last_commit"])
    count = r["commit_count"] || 0

    []
    |> add_flag(
      created && window_start && DateTime.compare(created, window_start) == :lt,
      30,
      "GitHub repo was created BEFORE the assessment started (#{r["repo_created"]})"
    )
    |> add_flag(
      first && window_start && DateTime.compare(first, window_start) == :lt,
      35,
      "First commit predates the assessment (#{r["first_commit"]}) — likely a pre-existing project"
    )
    |> add_flag(
      count == 1,
      25,
      "Only 1 commit — the whole project was pushed as a single dump, not built incrementally"
    )
    |> add_flag(
      count > 1 && first && last && DateTime.diff(last, first) <= 300,
      20,
      "All #{count} commits landed within 5 minutes — pushed in one sitting, not developed over time"
    )
    |> add_flag(
      length(r["committers"] || []) > 3,
      15,
      "#{length(r["committers"])} distinct commit authors — shared/forked work?"
    )
  end

  defp repo_flags(_, _), do: []

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp add_flag(flags, true, weight, text), do: [%{weight: weight, text: text} | flags]
  defp add_flag(flags, _false, _weight, _text), do: flags

  defp verdict(s) when s >= 80, do: "looks authentic"
  defp verdict(s) when s >= 50, do: "review recommended"
  defp verdict(_), do: "high risk — review"

  defp name_mismatch?(author, student) do
    a = normalize(author)
    s = normalize(student)
    a != "" and s != "" and not (String.contains?(a, s) or String.contains?(s, a))
  end

  defp normalize(str), do: str |> to_string() |> String.downcase() |> String.replace(~r/[^a-z]/, "")

  defp ago(nil, _), do: ""
  defp ago(_, nil), do: ""

  defp ago(created, ref) do
    hours = DateTime.diff(ref, created, :second) / 3600

    cond do
      hours >= 48 -> "#{round(hours / 24)} days"
      hours >= 1 -> "#{round(hours)} h"
      true -> "minutes"
    end
  end

  # PDF via pdfinfo -rawdates (dates look like "D:20260715103045Z").
  defp pdf_meta(binary) do
    path = System.tmp_dir!() |> Path.join("mpf_#{:rand.uniform(999_999)}.pdf")

    try do
      File.write!(path, binary)

      case System.cmd("pdfinfo", ["-rawdates", path], stderr_to_stdout: false) do
        {out, 0} ->
          %{
            "created" => parse_pdf_date(field(out, "CreationDate")),
            "modified" => parse_pdf_date(field(out, "ModDate")),
            "author" => blank_nil(field(out, "Author")),
            "source" => "pdfinfo"
          }

        _ ->
          %{"source" => "pdfinfo_failed"}
      end
    after
      File.rm(path)
    end
  rescue
    e ->
      Logger.warning("MPF pdf_meta failed: #{Exception.message(e)}")
      %{"source" => "pdf_error"}
  end

  # OOXML: read docProps/core.xml straight out of the zip container.
  defp ooxml_meta(binary) do
    case :zip.extract(binary, [:memory, {:file_list, [~c"docProps/core.xml"]}]) do
      {:ok, [{_name, xml}]} ->
        xml = to_string(xml)

        %{
          "created" => iso(tag(xml, "dcterms:created")),
          "modified" => iso(tag(xml, "dcterms:modified")),
          "author" => blank_nil(tag(xml, "dc:creator")),
          "last_modified_by" => blank_nil(tag(xml, "cp:lastModifiedBy")),
          "source" => "ooxml_core"
        }

      _ ->
        %{"source" => "ooxml_no_core"}
    end
  rescue
    _ -> %{"source" => "ooxml_error"}
  end

  defp field(text, key) do
    case Regex.run(~r/^#{Regex.escape(key)}:\s*(.+)$/m, text) do
      [_, v] -> String.trim(v)
      _ -> nil
    end
  end

  defp tag(xml, name) do
    case Regex.run(~r/<#{Regex.escape(name)}[^>]*>([^<]*)<\/#{Regex.escape(name)}>/, xml) do
      [_, v] -> String.trim(v)
      _ -> nil
    end
  end

  defp parse_pdf_date(nil), do: nil

  defp parse_pdf_date(raw) do
    case Regex.run(~r/D:(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/, raw) do
      [_, y, mo, d, h, mi, s] ->
        [y, mo, d, h, mi, s] = Enum.map([y, mo, d, h, mi, s], &String.to_integer/1)

        case DateTime.new(Date.new!(y, mo, d), Time.new!(h, mi, s), "Etc/UTC") do
          {:ok, dt} -> DateTime.to_iso8601(dt)
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp iso(nil), do: nil

  defp iso(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.to_iso8601(dt)
      _ -> nil
    end
  end

  defp parse(nil), do: nil

  defp parse(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp blank_nil(nil), do: nil
  defp blank_nil(""), do: nil
  defp blank_nil(s), do: String.trim(s) |> then(&if(&1 == "", do: nil, else: &1))

  defp parse_github(url) do
    case Regex.run(~r{github\.com[/:]([^/]+)/([^/?#\.]+)}i, url || "") do
      [_, owner, repo] -> {:ok, owner, repo}
      _ -> {:error, :not_github}
    end
  end

  defp gh_get(api) do
    headers =
      [{"accept", "application/vnd.github+json"}, {"user-agent", "VyaasaCampus"}] ++
        case System.get_env("GITHUB_TOKEN") || System.get_env("GH_TOKEN") do
          t when is_binary(t) and t != "" -> [{"authorization", "Bearer #{t}"}]
          _ -> []
        end

    case Req.get(api, headers: headers, receive_timeout: 12_000, max_redirects: 3) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      _ -> {:error, :unreachable}
    end
  rescue
    _ -> {:error, :unreachable}
  end
end
