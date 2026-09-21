defmodule VyaasaCampus.AI.Interview.Github do
  @moduledoc """
  GitHub repo analysis + ownership-verification questions for the interview.

  Fetches a candidate's repo (description, language, topics, README) from the
  public GitHub API, then generates project-specific questions that only someone
  who actually built the project could answer — grounded in the README, not the
  generic tech stack. Port of the dev `github/analyzer.py` + `verifier.py`.

  Set `GITHUB_TOKEN` for higher API rate limits (optional; public repos work
  unauthenticated). All network/LLM failures degrade to `[]` so the interview
  never stalls.
  """

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.Interview.Profile

  require Logger

  @api "https://api.github.com"
  @model "openai/gpt-oss-120b"
  @max_repos 3
  @questions_per_repo 2
  @max_github_questions 3

  @doc "Parse a GitHub URL → `{owner, repo}` or `nil` (profile-only URLs return nil)."
  def parse_url(url) when is_binary(url) do
    cleaned =
      url
      |> String.trim()
      |> String.trim_trailing("/")
      |> String.replace(~r/^https?:\/\//, "")
      |> String.replace(".git", "")

    case String.split(cleaned, "/") do
      [host | rest] ->
        if String.contains?(host, "github.com") and length(rest) >= 2 do
          [owner, repo | _] = rest
          {owner, repo}
        else
          nil
        end

      _ ->
        nil
    end
  end

  def parse_url(_), do: nil

  @doc "Extract a bare profile username from `github.com/<user>` (no repo segment), else nil."
  def parse_profile_username(url) when is_binary(url) do
    cleaned =
      url
      |> String.trim()
      |> String.trim_trailing("/")
      |> String.replace(~r/^https?:\/\//, "")
      |> String.replace(".git", "")

    case String.split(cleaned, "/") do
      [host, user] -> if String.contains?(host, "github.com") and user != "", do: user, else: nil
      _ -> nil
    end
  end

  def parse_profile_username(_), do: nil

  @doc """
  Resolve the candidate's best repo and generate ONE ownership-verification
  question grounded in it. Priority (port of `analyze_candidate_repos`):

    1. direct repo URLs (project links + any profile-listed repo URLs), then
    2. if none, the candidate's GitHub *profile* username → its top repos
       (sorted by stars).

  Repos not under a username the candidate claims (or forks) are flagged so the
  question probes what they actually contributed instead of assuming authorship.
  Returns an interviewer-compatible question map or `nil`.
  """
  def ownership_question_for_profile(%Profile{} = profile) do
    case candidate_repos(profile) do
      [analysis | _] ->
        case ownership_questions(analysis, repo_label(analysis, profile), 1) do
          [q | _] -> q
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Build the full ownership-question pool: #{@questions_per_repo} questions per
  resolved repo, capped at #{@max_github_questions} total (reference
  GITHUB_QUESTIONS_PER_REPO / MAX_GITHUB_QUESTIONS). Returns a list of
  interviewer-compatible question maps (possibly empty).
  """
  def ownership_questions_pool(%Profile{} = profile) do
    profile
    |> candidate_repos()
    |> Enum.flat_map(&ownership_questions(&1, repo_label(&1, profile), @questions_per_repo))
    |> Enum.take(@max_github_questions)
  end

  @doc """
  Analyze the candidate's GitHub repos in priority order — direct repo URLs
  first, falling back to the profile username's top repos. Returns a list of
  analysis maps (each `found: true`, tagged with `:ownership_unverified`).
  """
  def candidate_repos(%Profile{} = profile) do
    usernames = candidate_usernames(profile)

    project_urls = profile.projects |> Enum.map(& &1.github_url) |> Enum.reject(&blank?/1)
    all_urls = (profile.github_urls ++ project_urls) |> Enum.reject(&blank?/1) |> Enum.uniq()

    {repo_urls, profile_urls} =
      Enum.reduce(all_urls, {[], []}, fn url, {repos, profiles} ->
        case parse_url(url) do
          {owner, repo} -> {repos ++ [{owner, repo}], profiles}
          nil -> {repos, profiles ++ [url]}
        end
      end)

    cond do
      repo_urls != [] ->
        repo_urls
        |> Enum.take(@max_repos)
        |> Enum.map(fn {owner, repo} ->
          case analyze_repo(owner, repo) do
            {:ok, %{found: true} = a} ->
              Map.put(a, :ownership_unverified, unverified?(usernames, owner))

            _ ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      true ->
        profile_urls
        |> Enum.map(&parse_profile_username/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.flat_map(&top_repos(&1, @max_repos))
    end
  end

  @doc """
  Fetch a profile's top public repos (by stars, from the most-recently-pushed
  set) and analyze each. Port of `get_repos_from_profile`. Forks are included
  but flagged so the question can probe original contribution.
  """
  def top_repos(username, max \\ @max_repos) do
    fetch_n = min(max * 3, 30)

    case get("/users/#{username}/repos?sort=pushed&per_page=#{fetch_n}") do
      {:ok, repos} when is_list(repos) ->
        repos
        |> Enum.sort_by(&(&1["stargazers_count"] || 0), :desc)
        |> Enum.take(max)
        |> Enum.map(fn r ->
          owner = get_in(r, ["owner", "login"]) || username
          name = r["name"]

          case analyze_repo(owner, name) do
            {:ok, %{found: true} = a} ->
              # The candidate owns the profile, so authorship is presumed — but a
              # fork still warrants a "what did you change?" angle.
              %{a | is_fork: r["fork"] == true} |> Map.put(:ownership_unverified, false)

            _ ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        Logger.info("INTERVIEW_GH | no public repos for profile #{username}")
        []
    end
  end

  @doc "Fetch + analyze a repo. Returns `{:ok, analysis_map}` (with `found:`) or `{:error, reason}`."
  def analyze_repo(owner, repo) do
    base = %{
      owner: owner,
      repo: repo,
      url: "https://github.com/#{owner}/#{repo}",
      found: false,
      description: "",
      language: "",
      stars: 0,
      topics: [],
      is_fork: false,
      ownership_unverified: false,
      readme: "",
      technologies: []
    }

    case get("/repos/#{owner}/#{repo}") do
      {:ok, %{} = data} ->
        readme = fetch_readme(owner, repo)

        {:ok,
         %{
           base
           | found: true,
             description: data["description"] || "",
             language: data["language"] || "",
             stars: data["stargazers_count"] || 0,
             topics: data["topics"] || [],
             is_fork: data["fork"] == true,
             readme: readme || (data["description"] || ""),
             technologies: Enum.uniq([data["language"]] ++ (data["topics"] || [])) |> Enum.reject(&is_nil/1)
         }}

      {:error, reason} ->
        Logger.info("INTERVIEW_GH | repo not analyzed #{owner}/#{repo}: #{inspect(reason)}")
        {:ok, base}
    end
  end

  # Usernames the candidate claims as their own (bare profile links).
  defp candidate_usernames(%Profile{} = profile) do
    profile.github_urls
    |> Enum.map(&parse_profile_username/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
    |> MapSet.new()
  end

  defp unverified?(usernames, owner) do
    MapSet.size(usernames) > 0 and not MapSet.member?(usernames, String.downcase(owner))
  end

  # Prefer the candidate's own project name for this repo; else the repo name.
  defp repo_label(analysis, %Profile{} = profile) do
    match =
      Enum.find(profile.projects, fn p ->
        is_binary(p.github_url) and parse_url(p.github_url) == {analysis.owner, analysis.repo}
      end)

    cond do
      match -> match.name
      is_binary(analysis.repo) and analysis.repo != "" -> analysis.repo
      true -> "your project"
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false

  # ── Ownership questions (LLM, grounded in the repo) ─────────────────────────
  defp ownership_questions(analysis, project_name, count) do
    readme = analysis.readme |> to_string() |> String.slice(0, 4000)

    # When the repo isn't clearly the candidate's own (a fork, or owned by a
    # different account), don't assume authorship — probe their actual contribution.
    presumed_own? = not (analysis[:ownership_unverified] || analysis[:is_fork])

    goal =
      if presumed_own? do
        "Generate #{count} interview question(s) that ONLY someone who actually built " <>
          "THIS project could answer confidently — grounded in README specifics (modules, " <>
          "design decisions, data flow, trade-offs), NOT generic tech-stack questions."
      else
        "This repo is a fork or not under the candidate's own account, so do NOT assume " <>
          "they built it. Generate #{count} question(s) that probe what THEY specifically " <>
          "contributed or changed, how THEY would extend or debug it, and their understanding " <>
          "of a specific part described in the README — never assume sole authorship."
      end

    prompt = """
    PROJECT: #{project_name} (#{analysis.url})
    Primary language: #{analysis.language}. Topics: #{Enum.join(analysis.topics, ", ")}.
    README (verbatim, may be truncated):
    #{readme}

    #{goal} Conversational, one sentence each.

    JSON only: {"questions": ["...", "..."]}
    """

    case GroqClient.chat(
           [
             %{role: "system", content: "You verify project ownership in interviews. Output valid JSON only."},
             %{role: "user", content: prompt <> "\n/no_think"}
           ],
           model: @model,
           temperature: 0.9,
           max_tokens: 3500,
           reasoning_effort: "low",
           timeout: 90_000
         ) do
      {:ok, %{"content" => raw}} ->
        case GroqClient.extract_json(GroqClient.strip_reasoning(raw)) do
          {:ok, %{"questions" => qs}} when is_list(qs) ->
            qs
            |> Enum.map(&to_string/1)
            |> Enum.reject(&(String.trim(&1) == ""))
            |> Enum.take(count)
            |> Enum.map(fn text ->
              %{
                text: String.trim(text),
                type: "ownership_verify",
                section: "project_deep_dive",
                topic: project_name,
                project_name: project_name,
                experience_name: nil,
                github_url: analysis.url,
                difficulty: 2,
                follow_up_of: nil,
                expected_signals: []
              }
            end)

          _ ->
            []
        end

      _ ->
        []
    end
  end

  # ── GitHub API ──────────────────────────────────────────────────────────────
  defp fetch_readme(owner, repo) do
    case get("/repos/#{owner}/#{repo}/readme") do
      {:ok, %{"content" => content, "encoding" => "base64"}} when is_binary(content) ->
        content
        |> String.replace("\n", "")
        |> Base.decode64()
        |> case do
          {:ok, decoded} -> decoded
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp get(path) do
    headers =
      [{"accept", "application/vnd.github.v3+json"}, {"user-agent", "vyaasa-campus"}] ++
        case System.get_env("GITHUB_TOKEN") do
          nil -> []
          "" -> []
          token -> [{"authorization", "Bearer #{token}"}]
        end

    case Req.get(@api <> path, headers: headers, retry: false, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, {:exception, Exception.message(e)}}
  end
end
