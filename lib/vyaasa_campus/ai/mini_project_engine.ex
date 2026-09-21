defmodule VyaasaCampus.AI.MiniProjectEngine do
  @moduledoc """
  AI engine for the Domain Mini Project. Ports the Python FastAPI service logic
  to native Elixir + Groq. Each public function handles one phase of the 7-phase
  internship simulation.
  """

  require Logger
  alias VyaasaCampus.AI.GroqClient

  @model "openai/gpt-oss-120b"
  @fast_model "openai/gpt-oss-20b"
  @discovery_max 5
  @viva_total 4

  # Rubric: {key, label, weight}. Weights sum to 100.
  @rubric [
    {"problem_understanding", "Problem Understanding", 15},
    {"domain_knowledge", "Domain Knowledge", 25},
    {"solution_quality", "Solution Quality", 20},
    {"critical_thinking", "Critical Thinking", 15},
    {"adaptability", "Adaptability to Changes", 10},
    {"viva_performance", "Viva Performance", 10},
    {"reflection", "Reflection & Learning", 5}
  ]

  @indexes [
    %{
      "key" => "domain_technical",
      "label" => "Domain Knowledge & Technical Skills",
      "weight" => 56,
      "criteria" => ["problem_understanding", "domain_knowledge", "solution_quality", "critical_thinking"]
    },
    %{
      "key" => "collaboration_teamwork",
      "label" => "Collaboration & Teamwork",
      "weight" => 22,
      "criteria" => ["viva_performance"]
    },
    %{
      "key" => "initiative_leadership",
      "label" => "Initiative & Leadership",
      "weight" => 22,
      "criteria" => ["adaptability", "reflection"]
    }
  ]

  @calibration """
  Calibrate for FINAL-YEAR STUDENTS and be GENEROUS to genuinely good work. A good, \
  competent performance that meets the brief should score 8–9 (which lands ~80–90+ overall), \
  and excellent work 9–10 — do NOT cap good work at 7. Reserve 5–6 for work with real gaps, \
  3–4 for weak work, and 0–2 only for absent/no-effort answers. When a response sits between \
  two bands choose the HIGHER one.
  """

  # ── Phase 1 — Scenario Generation ────────────────────────────────────────

  @doc """
  Generates 2 distinct project scenarios based on student skills and the job description.
  Returns a list of scenario maps or fallback mocks on error.
  """
  def generate_scenarios(specialization_name, resume_text \\ "", jd_text \\ "", extra_skills \\ "") do
    system = """
    You are the EMPLOYER in an AI-supervised internship simulation for FRESH GRADUATES.
    Design TWO DISTINCT, 24-hour-scoped mini-project scenarios tailored to the student.
    Rules:
    - Anchor on the job role from the JD — make tasks authentic to that role.
    - Derive the task from skills in both resume and JD. If thin, use the specialization.
    - 24-hour scope: completable by ONE fresher in about 24 hours.
    - If data is needed, student uses public datasets or synthetic data — no proprietary data.
    - Do NOT mandate a tech stack.
    - Make the two scenarios clearly distinct from each other.
    Respond ONLY with valid JSON.
    """

    user = """
    STUDENT'S DOMAIN/SPECIALIZATION: #{specialization_name}
    RESUME SKILLS (may be empty): #{resume_text || "(none provided)"}
    JOB DESCRIPTION: #{jd_text || "(none provided)"}
    EXTRA SKILLS: #{extra_skills || "(none)"}

    Generate 2 distinct, 24-hour-scoped project scenarios. Return JSON:
    {
      "scenarios": [
        {
          "org_name": "invented company name",
          "org_profile": "2-3 sentence profile",
          "role_title": "the student's intern job title",
          "business_context": "2-3 sentences describing one concrete problem",
          "objective": "one sentence: what must be built/delivered in ~24 hours",
          "constraints": ["24-hour delivery window", "may use any public or synthetic dataset", "other constraint"],
          "hidden_facts": {
            "fact_key_1": "value the stakeholder knows but didn't volunteer",
            "fact_key_2": "another hidden detail"
          }
        }
      ]
    }
    """

    case call_groq_json(system, user, temperature: 0.9) do
      {:ok, data} ->
        scenarios = (data["scenarios"] || []) |> Enum.take(2) |> Enum.map(&coerce_scenario/1)
        if length(scenarios) >= 2, do: scenarios, else: mock_scenarios(specialization_name)

      {:error, reason} ->
        Logger.warning("Mini project scenario generation failed: #{inspect(reason)}")
        mock_scenarios(specialization_name)
    end
  end

  # ── Phase 2 — Stakeholder Discovery Reply ────────────────────────────────

  @doc """
  Returns the AI stakeholder's reply to a student discovery question.
  Also returns which hidden_facts were revealed.
  """
  def stakeholder_reply(chosen_scenario, question, discovery_messages) do
    if word_count(question) < 3 do
      {:ok, %{
        "role" => "Project Manager",
        "content" => "Could you be more specific about what you'd like to know? A focused question will get you a more useful answer.",
        "quality" => "vague",
        "revealed" => []
      }}
    else
      system = """
      You are role-playing STAKEHOLDERS at a company in an internship simulation.
      Answer the intern's discovery questions realistically and in character.
      Rules:
      - Stay consistent with the scenario; answer as the appropriate stakeholder.
      - Reveal a hidden_fact ONLY when the question specifically targets it.
      - Push back on vague, one-word, or fishing questions — don't fabricate data.
      - Keep answers concise and realistic (2-5 sentences).
      Respond ONLY with valid JSON.
      """

      transcript =
        discovery_messages
        |> Enum.map(fn m ->
          sender = if m["sender"] == "student", do: "Intern", else: m["role"] || "Stakeholder"
          "#{sender}: #{m["content"]}"
        end)
        |> Enum.join("\n")

      user = """
      SCENARIO (with hidden facts — NEVER dump all of them at once):
      #{Jason.encode!(chosen_scenario, pretty: true)}

      CONVERSATION SO FAR:
      #{if transcript == "", do: "(no previous messages)", else: transcript}

      INTERN'S QUESTION:
      "#{question}"

      Return JSON:
      {
        "role": "which stakeholder is answering (e.g. Product Manager, Data Lead, CTO)",
        "content": "their realistic in-character answer",
        "quality": "good | vague | offtopic",
        "revealed": ["keys from hidden_facts that you disclosed this turn, or empty list"]
      }
      """

      case call_groq_json(system, user, model: @fast_model, temperature: 0.6) do
        {:ok, data} ->
          {:ok, %{
            "role" => data["role"] || "Stakeholder",
            "content" => data["content"] || "",
            "quality" => data["quality"] || "good",
            "revealed" => List.wrap(data["revealed"])
          }}

        {:error, reason} ->
          Logger.warning("Stakeholder reply failed: #{inspect(reason)}")
          {:ok, fallback_stakeholder_reply()}
      end
    end
  end

  # ── Phase 2 → 3 — Discovery Recap ────────────────────────────────────────

  @doc "Summarises what the student learned in discovery for use in the brief."
  def discovery_recap(chosen_scenario, discovery_messages) do
    transcript =
      discovery_messages
      |> Enum.map(fn m ->
        sender = if m["sender"] == "student", do: "Intern", else: m["role"] || "Stakeholder"
        "#{sender}: #{m["content"]}"
      end)
      |> Enum.join("\n")

    system = """
    You are a MENTOR summarising what the intern learned in discovery so they can carry it into
    their solution. Summarise ONLY what was established in the conversation; do not add new facts.
    Respond ONLY with valid JSON.
    """

    user = """
    SCENARIO: #{chosen_scenario["objective"] || ""}
    ORG: #{chosen_scenario["org_name"] || ""}

    DISCOVERY CONVERSATION:
    #{if transcript == "", do: "(the intern asked nothing)", else: transcript}

    Return JSON: { "recap": "3-5 bullet-style sentences of what is now known" }
    """

    case call_groq_json(system, user, model: @fast_model, temperature: 0.4) do
      {:ok, data} ->
        recap =
          case data["recap"] do
            s when is_binary(s) -> s
            list when is_list(list) -> Enum.join(list, "\n")
            _ -> nil
          end

        recap || default_recap()

      {:error, _} ->
        default_recap()
    end
  end

  # ── Phase 3 — Brief Generation ───────────────────────────────────────────

  @doc "Generates the downloadable project brief in Markdown."
  # Every role submits its finished deliverable as uploaded file(s) — PDF, DOCX,
  # PPTX, or a ZIP of the project (no GitHub URL / live link). Cf. Vya-005/035.

  def generate_brief(chosen_scenario, discovery_recap) do
    # Every role now submits the finished deliverable as uploaded file(s) — a
    # document, slide deck, or a ZIP of the project — regardless of role.
    submission_instruction = """
    The ONLY submission method is UPLOADING FILE(S) of the finished deliverable — a PDF,
    Word document (DOCX), PowerPoint (PPTX), or a ZIP archive of the project. The ## Submission
    section MUST instruct the student to upload their deliverable as file(s) (PDF/DOCX/PPTX/ZIP).
    Never ask for a GitHub URL, a live link, or any other online URL — the student uploads files.
    """

    submission_type = "files"

    system = """
    You write a clear, self-contained PROJECT BRIEF a fresh-graduate student downloads and uses
    to build their mini-project offline in ABOUT 24 HOURS, without further help.
    Be concrete and encouraging. Include practical hints but do NOT solve it for them.
    CRITICAL RULES — never break these:
    1. The 24-hour delivery window must be stated explicitly.
    2. If data is needed, the student may use any public dataset or generate synthetic data.
    3. The student may use ANY tech stack or tools.
    4. #{submission_instruction}
    Respond ONLY with valid JSON.
    """

    user = """
    SCENARIO:
    #{Jason.encode!(Map.take(chosen_scenario, ["org_name", "org_profile", "role_title", "business_context", "objective", "constraints"]), pretty: true)}

    WHAT THE STUDENT LEARNED IN DISCOVERY:
    #{discovery_recap || "(little was asked)"}

    Return JSON:
    {
      "brief_markdown": "A complete markdown brief. Use # for title, ## for each section. Required sections in order: ## Objective, ## Background and Key Facts, ## Deliverables, ## Steps and Hints (4-6 numbered steps), ## Timeline (24-hour window), ## Submission."
    }
    """

    case call_groq_json(system, user, temperature: 0.4) do
      {:ok, data} ->
        brief =
          case data["brief_markdown"] do
            s when is_binary(s) and s != "" -> String.trim(s)
            _ -> nil
          end

        {brief || fallback_brief(chosen_scenario), submission_type}

      {:error, _} ->
        {fallback_brief(chosen_scenario), submission_type}
    end
  end

  # ── Phase 4 — GitHub repo fetch + extract ────────────────────────────────

  @doc """
  Downloads a public GitHub repo ZIP and extracts readable content (README +
  key source files). Returns {:ok, extracted_text} or {:error, reason}.
  """
  def fetch_github_repo(url) do
    with {:ok, owner, repo} <- parse_github_url(url),
         {:ok, zip_bytes} <- download_repo_zip(owner, repo),
         {:ok, text} <- extract_zip_text(zip_bytes) do
      {:ok, text}
    end
  end

  @doc """
  Check that a GitHub repo actually resolves before we accept/score it (Vya-025).

  Returns:
    * `:ok` — repo exists and is reachable (public)
    * `{:error, :not_found}` — GitHub returned 404 (bad/dead link) → block
    * `{:error, :unreachable}` — network error, rate-limit, private, etc. →
      caller should *fail open* (don't block a student on a transient issue)
  """
  def repo_reachable?(url) do
    case parse_github_url(url) do
      {:ok, owner, repo} ->
        api = "https://api.github.com/repos/#{owner}/#{repo}"

        case Req.get(api, headers: github_headers(), receive_timeout: 10_000, max_redirects: 3) do
          {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
          {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
          # 451 (DMCA/legal takedown) means the repo is gone for our purposes too.
          {:ok, %Req.Response{status: 451}} -> {:error, :not_found}
          # 403/429 = API rate-limited (common when unauthenticated), or any
          # other status: don't trust it — fall back to the public web page,
          # which returns a real 404 for dead repos without the API rate limit.
          _ -> web_page_reachable?(owner, repo)
        end

      _ ->
        {:error, :not_found}
    end
  end

  # Fallback existence check via the repo's public HTML page. Not subject to the
  # GitHub API's 60-req/hr unauthenticated limit, so it reliably distinguishes a
  # nonexistent repo (404) from a transient/network problem (fail open).
  defp web_page_reachable?(owner, repo) do
    page = "https://github.com/#{owner}/#{repo}"

    case Req.get(page, headers: [{"user-agent", "VyaasaCampus"}], receive_timeout: 10_000, max_redirects: 3) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
      {:ok, %Req.Response{}} -> {:error, :unreachable}
      {:error, _} -> {:error, :unreachable}
    end
  end

  # Base GitHub API headers. Adds a bearer token when GITHUB_TOKEN/GH_TOKEN is
  # set — this lifts the rate limit from 60 req/hr (unauthenticated, per IP) to
  # 5000 req/hr, so reachability checks return a real 404 for dead repos instead
  # of hitting a 403/429 rate-limit and silently failing open (Vya-025).
  defp github_headers do
    base = [
      {"accept", "application/vnd.github+json"},
      {"user-agent", "VyaasaCampus"}
    ]

    case System.get_env("GITHUB_TOKEN") || System.get_env("GH_TOKEN") do
      token when is_binary(token) and token != "" ->
        [{"authorization", "Bearer #{token}"} | base]

      _ ->
        base
    end
  end

  defp parse_github_url(url) do
    case Regex.run(~r{github\.com[/:]([^/]+)/([^/?#\.]+)}i, url || "") do
      [_, owner, repo] -> {:ok, owner, repo}
      _ -> {:error, "Not a valid GitHub URL"}
    end
  end

  defp download_repo_zip(owner, repo) do
    Enum.reduce_while(["main", "master"], {:error, "Branch not found"}, fn branch, _acc ->
      url = "https://codeload.github.com/#{owner}/#{repo}/zip/refs/heads/#{branch}"

      case Req.get(url, receive_timeout: 30_000, max_redirects: 5) do
        {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) > 0 ->
          {:halt, {:ok, body}}

        _ ->
          {:cont, {:error, "Could not download repository (tried main and master)"}}
      end
    end)
  end

  @skip_dirs ~w(node_modules .git venv .venv __pycache__ dist build target vendor site-packages .mypy_cache)
  @code_exts ~w(.py .js .ts .jsx .tsx .java .c .cpp .go .rs .rb .php .sh .html .css .vue .md .txt .sql .ipynb .r)
  @zip_content_budget 60_000
  @zip_per_file 10_000

  defp extract_zip_text(zip_bytes) do
    case :zip.extract(zip_bytes, [:memory]) do
      {:ok, entries} ->
        all_names = for {name, _} <- entries, do: to_string(name)

        text = build_zip_digest(entries, all_names)
        {:ok, text}

      {:error, reason} ->
        {:error, "Could not read ZIP: #{inspect(reason)}"}
    end
  end

  defp build_zip_digest(entries, all_names) do
    filtered =
      all_names
      |> Enum.reject(&in_skip_dir?/1)

    ext_summary =
      filtered
      |> Enum.group_by(&Path.extname(&1))
      |> Enum.map(fn {ext, files} -> "#{ext}:#{length(files)}" end)
      |> Enum.join(", ")

    # README first, then source files
    readable =
      filtered
      |> Enum.filter(fn name ->
        ext = Path.extname(name)
        ext in @code_exts or
          String.downcase(Path.basename(name)) in ["readme", "makefile", "dockerfile", "requirements.txt"]
      end)
      |> Enum.sort_by(fn name ->
        # README-like files first
        if String.downcase(Path.basename(name)) =~ ~r/^readme/, do: 0, else: 1
      end)

    entry_map = Map.new(entries, fn {name, data} -> {to_string(name), data} end)

    header = [
      "CODE PROJECT: #{length(filtered)} files",
      "File types: #{ext_summary}",
      "File tree:",
      filtered |> Enum.sort() |> Enum.take(150) |> Enum.map(&"  #{&1}") |> Enum.join("\n"),
      "\n--- Key file contents ---"
    ]

    {file_sections, _} =
      Enum.reduce(readable, {[], @zip_content_budget}, fn name, {acc, budget} ->
        if budget <= 0 do
          {acc, budget}
        else
          case Map.get(entry_map, name) do
            nil -> {acc, budget}
            data ->
              content = data |> to_string() |> String.slice(0, min(@zip_per_file, budget))
              {acc ++ ["\n### #{name}\n#{content}"], budget - byte_size(content)}
          end
        end
      end)

    (header ++ file_sections) |> Enum.join("\n")
  end

  defp in_skip_dir?(path) do
    parts = String.split(path, "/")
    Enum.any?(parts, &(&1 in @skip_dirs))
  end

  # ── Phase 4 — Document Analysis ──────────────────────────────────────────

  @doc "Analyses a submitted document artifact against the project scenario."
  def analyze_document(chosen_scenario, filename, extracted_text) do
    system = """
    You are a TECHNICAL REVIEWER for an internship mini-project submission.
    Analyse the submitted document in the context of the project objective.
    Respond ONLY with valid JSON.
    """

    snippet = String.slice(extracted_text || "", 0, 8_000)

    user = """
    PROJECT OBJECTIVE: #{chosen_scenario["objective"] || ""}
    ORG: #{chosen_scenario["org_name"] || ""}
    FILENAME: #{filename}

    DOCUMENT CONTENT (excerpt):
    #{snippet}

    Return JSON:
    {
      "artifact_type": "e.g. report, presentation, analysis, code",
      "summary": "2-3 sentence summary of what this document contains",
      "key_points": ["main finding or contribution 1", "main finding 2"],
      "gaps_or_concerns": ["any obvious gap or missing element"],
      "viva_hooks": ["a specific claim or result worth probing in the viva"]
    }
    """

    case call_groq_json(system, user, model: @fast_model, temperature: 0.3) do
      {:ok, data} -> data
      {:error, _} -> %{"artifact_type" => "document", "summary" => "Submitted document.", "key_points" => [], "gaps_or_concerns" => [], "viva_hooks" => []}
    end
  end

  # ── Phase 5 — Viva Question Generation ───────────────────────────────────

  @doc """
  Generates the next adaptive viva question based on what was submitted.
  `turn_index` is 0-based.
  """
  def next_viva_question(chosen_scenario, artifacts, viva_turns, turn_index) do
    artifact_briefs =
      artifacts
      |> Enum.filter(& &1["extract_ok"])
      |> Enum.map(fn a ->
        analysis = a["analysis"] || %{}
        # Fall back to a snippet of the ACTUAL submitted content so questions can
        # cite specifics only the real author would know — key for authorship
        # verification on a take-home.
        snippet = a["extracted_text"] |> to_string() |> String.slice(0, 1200)

        "- #{a["filename"]}: #{analysis["summary"] || "submitted document"}" <>
          if(analysis["viva_hooks"], do: "\n  Hooks: #{Enum.join(analysis["viva_hooks"], "; ")}", else: "") <>
          if(snippet != "", do: "\n  Excerpt: #{snippet}", else: "")
      end)
      |> Enum.join("\n\n")

    previous_qa =
      viva_turns
      |> Enum.map(fn t ->
        if t["answer"],
          do: "Q#{t["index"] + 1}: #{t["question"]}\nA: #{t["answer"]}\n(score: #{t["answer_score"]}/10)",
          else: nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    system = """
    You are a TECHNICAL INTERVIEWER conducting an adaptive viva for an internship mini-project.
    This is ALSO an authorship check on a take-home: your questions must be ones only the person
    who actually did the work could answer. Cite a SPECIFIC detail from the submitted excerpt (a
    number, choice, method, or claim) and ask them to justify or explain it — e.g. "You chose X in
    your report; why not Y?", "Explain the trade-off behind <specific decision>." Avoid generic
    questions the student could answer without having done the work.
    Probe weak answers with follow-ups; probe strong areas for depth.
    This is question #{turn_index + 1} of #{@viva_total}.
    Respond ONLY with valid JSON.
    """

    user = """
    PROJECT OBJECTIVE: #{chosen_scenario["objective"] || ""}

    SUBMITTED ARTIFACTS:
    #{if artifact_briefs == "", do: "(no readable artifacts)", else: artifact_briefs}

    PREVIOUS VIVA Q&A:
    #{if previous_qa == "", do: "(first question)", else: previous_qa}

    Generate question #{turn_index + 1} of #{@viva_total}. Return JSON:
    {
      "question": "Your specific question about the submission (one question only, direct)",
      "asked_because": "brief internal note: why this question — what you're probing",
      "evidence": "the specific claim or artifact section this question targets"
    }
    """

    case call_groq_json(system, user, temperature: 0.5) do
      {:ok, data} ->
        %{
          "question" => data["question"] || "Walk me through the key decisions you made in this project.",
          "asked_because" => data["asked_because"] || "",
          "evidence" => data["evidence"] || ""
        }

      {:error, _} ->
        fallback_viva_question(turn_index)
    end
  end

  # ── Phase 5 — Viva Answer Scoring ────────────────────────────────────────

  @doc "Scores a single viva answer 0-10."
  def score_viva_answer(question, evidence, answer) do
    answer = to_string(answer)

    # Deterministic floor: empty / single-word / gibberish answers never reach the
    # (deliberately generous) LLM rubric — they cannot earn a passing score.
    if not substantive_answer?(answer) do
      %{"score" => 1, "note" => "Answer is empty or too short to assess.", "weak" => true}
    else
      system = """
      You are scoring a student's viva answer for an internship mini-project.
      Judge SUBSTANCE and CORRECTNESS before generosity:
      - Empty, single-word, gibberish or off-topic answers → 0-2.
      - On-topic but factually wrong, or showing no real understanding → 2-4.
      - Only a correct, specific, on-topic answer earns 7+.
      Do NOT inflate a weak or incorrect answer, and do NOT round an unclear
      answer up. Apply the calibration below only to answers that actually
      address the question. Respond ONLY with valid JSON.
      """

      user = """
      QUESTION: #{question}
      EVIDENCE THE QUESTION TARGETED: #{evidence || "(general question)"}
      STUDENT'S ANSWER: #{answer}

      #{@calibration}

      Return JSON:
      {
        "score": <integer 0-10>,
        "note": "1-2 sentence assessment of the answer",
        "weak": <true if the answer is incorrect, off-topic or significantly missed the mark, false otherwise>
      }
      """

      case call_groq_json(system, user, model: @fast_model, temperature: 0.2) do
        {:ok, data} ->
          %{
            "score" => clamp_score(data["score"]),
            "note" => data["note"] || "",
            "weak" => data["weak"] == true
          }

        {:error, _} ->
          # Don't reward an un-evaluated answer with a passing score.
          Logger.warning("MINI_PROJECT | viva scoring LLM failed — recording low provisional score")
          %{"score" => 3, "note" => "Answer could not be evaluated automatically.", "weak" => true}
      end
    end
  end

  # A viva answer must have some minimal substance to be scored by the LLM.
  # Guards against single-letter / one-word / empty / gibberish submissions
  # gaming the (generous) rubric. Requires at least 3 REAL words (letters + a
  # vowel, not UUIDs/hashes/numbers) and 12 non-space characters — so pasting
  # random UUIDs or hex blobs is treated as no answer.
  defp substantive_answer?(answer) do
    cleaned = String.trim(answer)

    real_words =
      cleaned
      |> String.split(~r/\s+/, trim: true)
      |> Enum.filter(&real_word?/1)

    String.length(cleaned) >= 12 and length(real_words) >= 3
  end

  # A "real" word contains letters AND a vowel, and is not a UUID / hex blob /
  # number. Random tokens like "a06a22e6-f63b-4147" contribute nothing.
  defp real_word?(token) do
    String.match?(token, ~r/[a-zA-Z]/) and
      String.match?(token, ~r/[aeiouAEIOU]/) and
      not String.match?(token, ~r/^[0-9a-fA-F]{6,}$/) and
      not String.match?(token, ~r/^[0-9a-fA-F-]{16,}$/)
  end

  # ── Phase 7 — Final Evaluation ────────────────────────────────────────────

  @doc """
  Runs the full evaluation: scores all 7 rubric criteria (3 passes, median),
  rolls up to 3 competency indexes, computes final score 0-100.
  """
  def evaluate(chosen_scenario, artifacts, discovery_messages, viva_turns, reflection) do
    dossier = build_dossier(chosen_scenario, artifacts, discovery_messages, viva_turns, reflection)

    # Viva performance is derived from per-answer scores, not a separate LLM pass.
    viva_score = compute_viva_score(viva_turns)

    # Score domain/collab/initiative criteria in focused passes (3x each for self-consistency).
    domain_runs = run_eval_pass("domain_technical", dossier, 3)
    initiative_runs = run_eval_pass("initiative_leadership", dossier, 3)

    criteria_scores =
      @rubric
      |> Enum.map(fn {key, label, weight} ->
        score =
          cond do
            key == "viva_performance" -> viva_score
            key in ["problem_understanding", "domain_knowledge", "solution_quality", "critical_thinking"] ->
              median_for(domain_runs, key)
            key in ["adaptability", "reflection"] ->
              median_for(initiative_runs, key)
            true -> 6
          end

        justification =
          cond do
            key == "viva_performance" ->
              "Aggregated from #{length(viva_turns)} viva answer scores."
            key in ["problem_understanding", "domain_knowledge", "solution_quality", "critical_thinking"] ->
              justification_for(domain_runs, key)
            key in ["adaptability", "reflection"] ->
              justification_for(initiative_runs, key)
            true -> ""
          end

        %{
          "key" => key,
          "label" => label,
          "weight" => weight,
          "score" => score,
          "justification" => justification,
          "weighted" => Float.round((score / 10) * weight, 2)
        }
      end)

    indexes = compute_indexes(criteria_scores)
    final_score = overall_from_indexes(indexes) |> apply_viva_defense_gate(viva_score)

    report = synthesize_report(dossier, criteria_scores, final_score)

    %{
      "criteria" => criteria_scores,
      "indexes" => indexes,
      "final_score" => final_score,
      "grade_band" => grade_band(final_score),
      "strengths" => report["strengths"] || [],
      "improvements" => report["improvements"] || [],
      "report_markdown" => report["report_markdown"] || mock_report(final_score)
    }
  end

  # Viva-defense gate: the SCORE IS DRIVEN BY THE ANSWERS, not the uploaded file.
  # A polished artifact the student cannot defend in the viva earns nothing —
  # random / gibberish / off-topic viva answers must score 0, no matter how good
  # the submitted document looks. `viva_score` is 0-10 (aggregated per-answer).
  # Genuine, defended work (viva >= 5) is never capped.
  defp apply_viva_defense_gate(final_score, viva_score) do
    cond do
      # No genuine defense (random tokens, UUIDs, gibberish, off-topic) → 0.
      viva_score <= 2 -> 0
      # Very weak defense — well below passing.
      viva_score <= 3 -> min(final_score, 20)
      # Weak defense — capped below the passing band.
      viva_score <= 4 -> min(final_score, 45)
      true -> final_score
    end
  end

  # ── Private: Evaluation helpers ───────────────────────────────────────────

  defp run_eval_pass(index_key, dossier, n) do
    idx = Enum.find(@indexes, &(&1["key"] == index_key))
    return_if_nil(idx, [])

    criteria_subset =
      @rubric
      |> Enum.filter(fn {key, _, _} -> key in idx["criteria"] end)
      |> Enum.map(fn {key, label, weight} -> %{key: key, label: label, weight: weight} end)

    if Enum.empty?(criteria_subset) do
      []
    else
      system = eval_system_prompt(idx["label"], criteria_subset)

      Enum.flat_map(1..n, fn _i ->
        case call_groq_json(system, dossier, temperature: 0.4) do
          {:ok, data} -> [data]
          {:error, _} -> []
        end
      end)
    end
  end

  defp eval_system_prompt(index_label, criteria_subset) do
    criteria_lines =
      Enum.map(criteria_subset, fn c ->
        "- #{c.key} (#{c.label}, weight #{c.weight}%)"
      end)
      |> Enum.join("\n")

    """
    You are an AI evaluator grading the #{index_label} dimension of a student internship project.
    Score each criterion 0-10. #{@calibration}

    SUBSTANCE FLOOR — apply BEFORE the calibration above: if the dossier shows
    little or no genuine work for a criterion (missing/empty deliverables, no real
    discovery, gibberish or single-word answers), score that criterion 0-3. Never
    award mid or high scores for absent or non-substantive work.

    RANDOM / NONSENSE ANSWERS → 0: if the student's answers are random tokens,
    UUIDs, hashes, keyboard-mashing, lorem ipsum, or text obviously unrelated to
    the question, score every affected criterion 0. The final grade is driven by
    the ANSWERS, not by the uploaded file — a good-looking document with random or
    non-answers must not earn points.

    RELEVANCE FLOOR — CRITICAL: score ONLY the deliverable's engagement with THIS
    project's scenario/task. If the submitted artifact does NOT address this
    specific brief — e.g. it is a résumé/CV, an unrelated document, generic notes,
    or content copied from elsewhere — score EVERY criterion 0-3, NO MATTER HOW
    technically impressive or polished the content is. Do NOT credit the student's
    background, résumé, or skills; credit ONLY work that solves THIS scenario. A
    strong résumé submitted as the deliverable is off-topic and earns 0-3.

    CRITERIA TO SCORE:
    #{criteria_lines}

    Return JSON with this exact shape:
    {
      "criteria": {
        "criterion_key": <score 0-10>,
        ...
      },
      "justifications": {
        "criterion_key": "2-3 sentence justification",
        ...
      }
    }
    Respond ONLY with valid JSON.
    """
  end

  defp median_for([], _key), do: 6

  defp median_for(runs, key) do
    scores =
      runs
      |> Enum.map(fn r -> r["criteria"][key] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&clamp_score/1)

    if Enum.empty?(scores), do: 6, else: median(scores)
  end

  defp justification_for([], _key), do: ""

  defp justification_for(runs, key) do
    medians = Enum.map(@rubric, fn {k, _, _} -> {k, median_for(runs, k)} end) |> Map.new()
    rep = representative_run(runs, medians)
    get_in(rep, ["justifications", key]) || ""
  end

  defp representative_run([], _medians), do: %{}

  defp representative_run([single], _medians), do: single

  defp representative_run(runs, medians) do
    Enum.min_by(runs, fn r ->
      criteria = r["criteria"] || %{}
      Enum.reduce(medians, 0.0, fn {k, m}, acc ->
        acc + abs(clamp_score(criteria[k]) - m)
      end)
    end)
  end

  defp compute_viva_score(viva_turns) do
    scores = viva_turns |> Enum.map(&(&1["answer_score"])) |> Enum.reject(&is_nil/1)
    # No viva answers at all → the student demonstrated nothing here, not "60%".
    if Enum.empty?(scores), do: 2, else: round(Enum.sum(scores) / length(scores))
  end

  defp compute_indexes(criteria_scores) do
    by_key = Map.new(criteria_scores, fn c -> {c["key"], c} end)

    Enum.map(@indexes, fn idx ->
      members = Enum.map(idx["criteria"], &by_key[&1]) |> Enum.reject(&is_nil/1)
      weight_sum = Enum.sum(Enum.map(members, & &1["weight"]))
      raw = Enum.sum(Enum.map(members, & &1["weighted"]))
      score100 = if weight_sum > 0, do: round(raw / weight_sum * 100), else: 0

      Map.merge(idx, %{"score" => score100, "criteria" => Enum.map(members, & &1["key"])})
    end)
  end

  defp overall_from_indexes(indexes) do
    weight_sum = Enum.sum(Enum.map(indexes, & &1["weight"]))
    if weight_sum == 0 do
      0
    else
      round(Enum.sum(Enum.map(indexes, fn i -> i["score"] * i["weight"] end)) / weight_sum)
    end
  end

  defp grade_band(score) when score >= 90, do: "Outstanding"
  defp grade_band(score) when score >= 80, do: "Excellent"
  defp grade_band(score) when score >= 70, do: "Good"
  defp grade_band(score) when score >= 60, do: "Satisfactory"
  defp grade_band(score) when score >= 50, do: "Pass"
  defp grade_band(_), do: "Needs Improvement"

  defp synthesize_report(dossier, criteria_scores, final_score) do
    summary =
      criteria_scores
      |> Enum.map(fn c -> "#{c["label"]}: #{c["score"]}/10" end)
      |> Enum.join(", ")

    system = """
    You write a final evaluation report for a student internship mini-project.
    Be encouraging but honest. Highlight genuine strengths; be specific about improvements.
    Respond ONLY with valid JSON.
    """

    user = """
    SCORES: #{summary} → overall #{final_score}/100

    FULL DOSSIER:
    #{dossier}

    Return JSON:
    {
      "strengths": ["strength 1", "strength 2", "strength 3"],
      "improvements": ["improvement 1", "improvement 2"],
      "report_markdown": "A markdown report. Use ## sections: ## What Went Well, ## Areas to Improve, ## Recommendations. Keep it encouraging and specific."
    }
    """

    case call_groq_json(system, user, temperature: 0.4) do
      {:ok, data} -> data
      {:error, _} -> %{"strengths" => [], "improvements" => [], "report_markdown" => mock_report(final_score)}
    end
  end

  defp build_dossier(chosen_scenario, artifacts, discovery_messages, viva_turns, reflection) do
    artifact_briefs =
      (artifacts || [])
      |> Enum.filter(& &1["extract_ok"])
      |> Enum.map(fn a ->
        analysis = a["analysis"] || %{}
        excerpt = String.slice(a["extracted_text"] || "", 0, 4_000)
        %{
          "filename" => a["filename"],
          "summary" => analysis["summary"],
          "key_points" => analysis["key_points"],
          "gaps" => analysis["gaps_or_concerns"],
          "excerpt" => excerpt
        }
      end)

    viva_qa =
      (viva_turns || [])
      |> Enum.filter(& &1["answer"])
      |> Enum.map(fn t ->
        %{"q" => t["question"], "a" => t["answer"], "score" => t["answer_score"]}
      end)

    Jason.encode!(%{
      "scenario" => Map.take(chosen_scenario || %{}, ["org_name", "role_title", "objective", "business_context", "constraints"]),
      "discovery_count" => Enum.count(discovery_messages || [], &(&1["sender"] == "student")),
      "artifacts" => artifact_briefs,
      "viva" => viva_qa,
      "reflection" => reflection
    }, pretty: true)
  end

  # ── Private: Groq call ────────────────────────────────────────────────────

  defp call_groq_json(system, user, opts \\ []) do
    model = Keyword.get(opts, :model, @model)
    temperature = Keyword.get(opts, :temperature, 0.5)

    messages = [
      %{role: "system", content: system},
      %{role: "user", content: user}
    ]

    case GroqClient.chat(messages,
           model: model,
           temperature: temperature,
           response_format: %{type: "json_object"},
           reasoning_effort: "low"
         ) do
      {:ok, %{"content" => raw}} ->
        raw |> GroqClient.strip_reasoning() |> GroqClient.extract_json()

      {:ok, raw} when is_binary(raw) ->
        raw |> GroqClient.strip_reasoning() |> GroqClient.extract_json()

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Private: Math helpers ─────────────────────────────────────────────────

  defp median([]), do: 0

  defp median(list) do
    sorted = Enum.sort(list)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 0 do
      round((Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2)
    else
      round(Enum.at(sorted, mid))
    end
  end

  defp clamp_score(nil), do: 6
  defp clamp_score(n) when is_number(n), do: max(0, min(10, round(n)))
  defp clamp_score(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> clamp_score(n)
      :error -> 6
    end
  end
  defp clamp_score(_), do: 6

  defp word_count(text) when is_binary(text) do
    text |> String.split(~r/\s+/, trim: true) |> length()
  end
  defp word_count(_), do: 0

  defp return_if_nil(nil, default), do: default
  defp return_if_nil(val, _), do: val

  # ── Fallbacks ─────────────────────────────────────────────────────────────

  defp mock_scenarios(specialization) do
    [
      %{
        "org_name" => "TechBridge Solutions",
        "org_profile" => "A mid-sized technology consultancy specialising in #{specialization} projects for enterprise clients.",
        "role_title" => "#{specialization} Intern",
        "business_context" => "The operations team tracks performance metrics manually using spreadsheets. Leadership wants a fresher to explore automation options.",
        "objective" => "Analyse the current process and build a prototype dashboard or report that makes the key metrics visible at a glance.",
        "constraints" => ["24-hour delivery window", "use any public or synthetic data", "any tools you prefer"],
        "hidden_facts" => %{"data_gap" => "Historical data exists for only 3 months.", "prior_attempt" => "A previous intern started something similar but left it incomplete."}
      },
      %{
        "org_name" => "Nexus Analytics",
        "org_profile" => "A fast-growing startup using #{specialization} to help retail clients understand customer behaviour.",
        "role_title" => "Junior #{specialization} Analyst",
        "business_context" => "The client-facing team struggles to explain technical outputs to non-technical stakeholders. They need clearer visualisations and summaries.",
        "objective" => "Create a concise presentation or report that makes one key #{specialization} insight easy to understand for a non-technical audience.",
        "constraints" => ["24-hour delivery window", "use public data or create synthetic examples", "no specific tool required"],
        "hidden_facts" => %{"audience" => "The end audience is C-suite executives who don't read code.", "format" => "A 5-slide max presentation is preferred."}
      }
    ]
  end

  defp coerce_scenario(data) do
    %{
      "org_name" => data["org_name"] || "Acme Corp",
      "org_profile" => data["org_profile"] || "",
      "role_title" => data["role_title"] || "Intern",
      "business_context" => data["business_context"] || "",
      "objective" => data["objective"] || "",
      "constraints" => List.wrap(data["constraints"]),
      "hidden_facts" => data["hidden_facts"] || %{}
    }
  end

  defp fallback_stakeholder_reply do
    %{
      "role" => "Project Manager",
      "content" => "Good question. Based on what we track internally, the issue tends to peak during high-load periods and we haven't formally measured the root cause yet. Happy to dig into specifics if you tell me what data you need.",
      "quality" => "good",
      "revealed" => []
    }
  end

  defp fallback_viva_question(index) do
    questions = [
      "Walk me through the key decisions you made in this project and why.",
      "What was the most challenging part of the project, and how did you approach it?",
      "If you had more time, what would you do differently or add?",
      "How does your solution address the original business problem stated in the brief?"
    ]

    %{
      "question" => Enum.at(questions, index) || questions |> List.last(),
      "asked_because" => "general project understanding",
      "evidence" => ""
    }
  end

  defp default_recap do
    "You gathered context on the project during discovery. Use what you learned to build your solution."
  end

  defp fallback_brief(chosen_scenario) do
    """
    # Project Brief — #{chosen_scenario["org_name"] || "Your Internship"}

    **Role:** #{chosen_scenario["role_title"] || "Intern"}

    ## Objective
    #{chosen_scenario["objective"] || "Complete the assigned project deliverable."}

    ## Background
    #{chosen_scenario["business_context"] || ""}

    ## Constraints
    #{(chosen_scenario["constraints"] || []) |> Enum.map(&"- #{&1}") |> Enum.join("\n")}

    ## Deliverables
    Build your solution and submit it using the method shown on the submission screen.

    ## Timeline
    Complete and submit within 24 hours.
    """
  end

  defp mock_report(score) do
    """
    # Internship Performance Report

    **Final score:** #{score}/100

    ## What Went Well
    You demonstrated effort in approaching the project brief and engaged with the viva questions.

    ## Areas to Improve
    Ground your decisions in deeper domain reasoning and quantify your trade-offs where possible.

    ## Recommendations
    Review the project brief feedback and consider how you would approach the objective differently with more preparation time.
    """
  end
end
