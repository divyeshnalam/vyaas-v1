defmodule VyaasaCampus.AI.CaseStudyEngine do
  @moduledoc """
  Native Elixir case-study engine (ported from the `case_iq` service).

  Two operations, both via `VyaasaCampus.AI.GroqClient`:

    * `generate_scenario/2` — invents a fresh, randomized incident scenario for a
      given sub-specialization (5 prose fields).
    * `evaluate/4` — scores the candidate's 7-section answers on three dimensions:
      Domain Knowledge (0–40), Problem-Solving (0–30), Initiative/Leadership
      (0–30) → total 0–100, plus per-dimension feedback.

  Diversity (industry / region / failure / timeframe + a nonce + high
  temperature) keeps scenarios from repeating.
  """

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.CaseStudy.Questions

  require Logger

  @scenario_model "openai/gpt-oss-120b"
  @report_model "openai/gpt-oss-120b"

  @prose_keys [:company_background, :incident, :your_task, :specific_incident, :your_objective, :technical_context]
  @list_keys [:skills_tested, :business_constraints, :key_stakeholders]
  @string_keys [:title, :domain_tag, :difficulty, :complexity, :duration]

  @industries [
    "online retail banking", "stock-trading / discount brokerage",
    "mobile-wallet / UPI payments", "buy-now-pay-later lender",
    "telecom / mobile network operator", "ride-hailing platform",
    "food-delivery aggregator", "horizontal e-commerce marketplace",
    "vertical e-commerce (fashion / electronics / grocery)",
    "video-streaming / OTT service", "music-streaming app",
    "online gaming / real-money gaming", "edtech / online learning platform",
    "healthtech / tele-consultation", "diagnostic-lab aggregator",
    "health-insurance claims platform", "logistics & last-mile delivery",
    "cloud SaaS / team collaboration tool",
    "social media / user-generated content platform",
    "government digital service (tax / ID / welfare)",
    "agritech / commodity exchange", "online travel / hotel-booking aggregator",
    "ad-tech / programmatic advertising network", "B2B fintech / payments rails",
    "IoT / connected vehicles / fleet telematics", "supply-chain visibility platform",
    "creator economy / live-commerce app", "online matrimony / dating",
    "co-working / hot-desk booking platform", "EV charging-network operator"
  ]

  @regions [
    "India", "Southeast Asia (Indonesia / Vietnam / Philippines)",
    "Latin America (Brazil / Mexico / Colombia)", "the Middle East (UAE / Saudi Arabia)",
    "Sub-Saharan Africa (Nigeria / Kenya / South Africa)",
    "Eastern Europe (Poland / Romania)", "the Nordics", "Australia / New Zealand",
    "Japan / South Korea", "the United Kingdom",
    "continental Europe (Germany / France)", "North America"
  ]

  # Kept deliberately relatable for a final-year student / fresher — everyday
  # product/business failures they can reason about from coursework and projects,
  # NOT production-infra / SRE / security-expert incidents.
  @failure_archetypes [
    "a bug introduced during a routine update that caused some saved data to show up wrong for users",
    "a third-party login/OTP provider going down for a few hours during peak usage, blocking sign-ins",
    "a misconfigured setting that accidentally showed paid premium features to free users for a few days",
    "a popular discount code leaking on social media and being used far more than intended, hurting margins",
    "a sudden surge of users during a sale that made the app slow and unresponsive for a few hours",
    "a regulator raising concerns about how the company stores and retains its users' personal data",
    "a phishing email tricking an employee, which led to a partial leak of customer data",
    "a payment-processing delay that left thousands of orders stuck in a 'paid but not confirmed' state",
    "a recommendation feature that occasionally surfaced inappropriate content to younger users",
    "an app update that accidentally logged users out and blocked new sign-ups until it was fixed",
    "a billing error that overcharged a small group of users for two months in a row",
    "a checkout glitch that caused some online orders to be placed or shipped twice",
    "an API key accidentally committed to a public code repository and misused before it was noticed",
    "a data-sync issue that briefly showed some users an outdated account balance or order status",
    "the team underestimating traffic for a TV-advertised campaign, causing slowdowns at the worst time",
    "a delivery mix-up that sent some orders to the wrong addresses during a peak sale",
    "a feature launched without enough testing that started showing wrong prices on some products"
  ]

  @timeframes [
    "during the year-end festive sales window",
    "in the middle of a quarterly earnings reporting period",
    "two weeks after a major platform migration",
    "during a regulator-mandated compliance audit",
    "right after onboarding a large enterprise client",
    "on the first day of a major new product launch",
    "during a national holiday with reduced on-call coverage",
    "while the platform team was halfway through switching cloud vendors",
    "during a flash-sale campaign promoted on national television"
  ]

  # ----------------------------------------------------------------------
  # Scenario generation
  # ----------------------------------------------------------------------

  @doc """
  Generate `count` distinct scenarios for `sub` (for the "choose your scenario"
  step). Returns `{:ok, [scenario, ...]}` or `{:error, reason}`.
  """
  def generate_scenarios(sub, count \\ 2) when is_binary(sub) do
    VyaasaCampus.AI.Tracing.span("case_study.generate_scenarios", fn -> do_generate_scenarios(sub, count) end)
  end

  defp do_generate_scenarios(sub, count) do
    results = Enum.map(1..count, fn variant -> generate_scenario(sub, variant) end)

    case Enum.filter(results, &match?({:ok, _}, &1)) do
      [] -> {:error, "Could not generate scenarios"}
      oks -> {:ok, Enum.map(oks, fn {:ok, s} -> s end)}
    end
  end

  @doc """
  Generate one case-study scenario for `sub`. Returns `{:ok, scenario_map}` with
  metadata (title, domain_tag, difficulty, complexity, duration, skills_tested)
  plus the prose/reference fields, or `{:error, reason}`.
  """
  def generate_scenario(sub, variant \\ 1) when is_binary(sub) do
    industry = Enum.random(@industries)
    region = Enum.random(@regions)
    failure = Enum.random(@failure_archetypes)
    timeframe = Enum.random(@timeframes)
    nonce = :crypto.strong_rand_bytes(4) |> Base.encode16()

    system = build_scenario_prompt(sub, variant, industry, region, failure, timeframe, nonce)

    case GroqClient.chat([%{role: "system", content: system}],
           model: @scenario_model,
           temperature: 0.95,
           max_tokens: 1500,
           response_format: %{"type" => "json_object"},
           reasoning_effort: "low",
           timeout: 60_000
         ) do
      {:ok, %{"content" => content}} ->
        case GroqClient.extract_json(content) do
          {:ok, map} when is_map(map) -> {:ok, normalize_scenario(map)}
          _ -> {:error, "Failed to parse scenario JSON"}
        end

      {:error, reason} ->
        Logger.error("CASE_STUDY | scenario generation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Render a scenario map as readable plain text (for the evaluation prompt)."
  def to_text(%{} = s) do
    constraints = get(s, :business_constraints) || []
    stakeholders = get(s, :key_stakeholders) || []

    """
    TITLE: #{get(s, :title)}

    COMPANY BACKGROUND
    #{get(s, :company_background)}

    INCIDENT
    #{get(s, :incident)}

    SPECIFIC INCIDENT
    #{get(s, :specific_incident)}

    BUSINESS CONSTRAINTS
    #{Enum.map_join(List.wrap(constraints), "\n", &"- #{&1}")}

    TECHNICAL CONTEXT
    #{get(s, :technical_context)}

    KEY STAKEHOLDERS
    #{Enum.join(List.wrap(stakeholders), ", ")}

    YOUR TASK
    #{get(s, :your_task)}

    YOUR OBJECTIVE
    #{get(s, :your_objective)}
    """
    |> String.trim()
  end

  def to_text(text) when is_binary(text), do: text

  # ----------------------------------------------------------------------
  # Evaluation
  # ----------------------------------------------------------------------

  @doc """
  Evaluate the candidate's `answers` (map keyed by question key) against the
  `scenario` for the (group, sub). Returns `{:ok, report}` where report has
  `domain_score` (0-40), `problem_solving_score` (0-30), `leadership_score`
  (0-30), `total_score` (0-100), feedback, strengths, improvements, etc.
  """
  def evaluate(scenario, answers, group, sub) when is_map(answers) do
    prompt = evaluation_prompt(to_text(scenario), answers, group, sub)

    case GroqClient.chat([%{role: "user", content: prompt}],
           model: @report_model,
           temperature: 0.2,
           max_tokens: 2000,
           response_format: %{"type" => "json_object"},
           reasoning_effort: "low",
           timeout: 90_000
         ) do
      {:ok, %{"content" => content}} ->
        case GroqClient.extract_json(content) do
          {:ok, map} when is_map(map) -> {:ok, map}
          _ -> {:error, "Failed to parse evaluation JSON"}
        end

      {:error, reason} ->
        Logger.error("CASE_STUDY | evaluation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ----------------------------------------------------------------------
  # Prompts
  # ----------------------------------------------------------------------

  defp normalize_scenario(m) do
    prose = Map.new(@prose_keys, fn k -> {k, get(m, k) |> to_string() |> String.trim()} end)
    strings = Map.new(@string_keys, fn k -> {k, get(m, k) |> to_string() |> String.trim()} end)

    lists =
      Map.new(@list_keys, fn k ->
        v = get(m, k)
        {k, if(is_list(v), do: Enum.map(v, &to_string/1), else: [])}
      end)

    prose |> Map.merge(strings) |> Map.merge(lists)
  end

  defp get(m, key), do: Map.get(m, key) || Map.get(m, Atom.to_string(key))

  defp build_scenario_prompt(sub, variant, industry, region, failure, timeframe, nonce) do
    company_type =
      case variant do
        1 -> "an established mid-to-large company"
        2 -> "a growing startup"
        _ -> "a mid-sized regional company"
      end

    """
    You are an expert technical assessor designing a case study for a #{sub} candidate.

    UNIQUE GENERATION ID: #{nonce}
    Treat this ID as a signal that this request is independent of any earlier
    request. The scenario MUST NOT repeat the structure, company name, numbers,
    or specific failure of any scenario you have generated before. Make it fresh.

    YOUR TASK:
    1. Invent ONE specific incident, drawing on real-world failure patterns but with details YOU make up.
       DO NOT use Amazon, Zomato, Meta, Airbnb, or Google. Invent a plausible fictional company name.
    2. Frame the company as #{company_type} operating primarily in #{region}, in the #{industry} space.
    3. Anchor the incident around this failure archetype: "#{failure}". Rewrite it in your own words with company-specific specifics.
    4. Place the incident #{timeframe}.
    5. Include concrete, distinctive numbers — users affected, downtime, revenue impact, fines, team size — invented but plausible for #{company_type}.
    6. Make it engaging and specific to a #{sub} candidate, but keep the CORE PROBLEM simple enough for a final-year student to reason about without any prior industry experience.

    DIFFICULTY CALIBRATION — IMPORTANT:
    This candidate is a FINAL-YEAR UNDERGRADUATE / FRESHER with NO industry
    experience. Keep the scenario EASY and APPROACHABLE:
    - The incident must be understandable from general coursework, common sense,
      and student projects — NOT from production, DevOps, SRE, security, or
      distributed-systems expertise they have never had.
    - Avoid deep technical jargon (e.g. cache eviction, TLS handshakes, read
      replicas, auto-scaling internals, race conditions). If a concept is
      unavoidable, explain it in one plain sentence.
    - The candidate should be able to reason about likely causes, business impact,
      and a sensible plan WITHOUT specialist tooling knowledge. Reward clear
      thinking, not insider expertise.
    - Keep numbers modest and easy to grasp; do not pile on many constraints.
    - Frame the incident around what USERS and the BUSINESS experienced (wrong
      prices, double charges, a slow app, stuck/late orders, a leaked discount),
      NOT around internal engineering mechanics.
    - DO NOT build the incident around: authentication/session tokens,
      encryption or cryptographic signatures, database migrations / schema /
      backfills, API / caching / server / infrastructure internals, or
      code-level race conditions. If a cause is needed, state it in ONE simple
      everyday sentence (e.g. "a settings mistake", "a bug in a software update").

    OUTPUT FORMAT — respond with ONLY a single JSON object. No prose, no markdown, no code fences.
    Use EXACTLY these keys:

    {
      "title": "A short, punchy scenario name (3–6 words, e.g. 'Logistics Data Compliance Crisis').",
      "domain_tag": "Two-part tag like 'Supply Chain · SaaS' or 'EdTech · Consumer'.",
      "difficulty": "Easy (strongly preferred) or at most Medium — never Hard.",
      "complexity": "Low (strongly preferred) or at most Medium — never High.",
      "duration": "An estimate like '30–40 min'.",
      "skills_tested": ["3 short skill phrases, e.g. 'Risk analysis'", "...", "..."],
      "company_background": "What the fictional company does and its scale (3–6 sentences).",
      "incident": "The high-level business consequences in plain prose.",
      "specific_incident": "What went wrong, in simple everyday terms — what users saw and what broke for the business — not internal engineering mechanics.",
      "business_constraints": ["3–5 short constraint bullets, e.g. 'Cannot fully roll back — marketing announced it'"],
      "technical_context": "1–2 sentences of light, plain-language context a student would grasp (how the product/process normally works). No deep engineering detail.",
      "key_stakeholders": ["3–5 stakeholders, e.g. 'CEO', 'Head of Product', 'Parents'"],
      "your_task": "The role the candidate plays and what's expected of them.",
      "your_objective": "Exactly what they need to analyse and propose."
    }
    """
  end

  defp evaluation_prompt(case_study, answers, group, sub) do
    extra =
      if group in ["Commerce Specializations", "Arts & Humanities"] do
        """

        For this Arts/Commerce domain, additionally evaluate:
        - Empathy & Ethics (part of Problem-Solving score): empathy, ethical reasoning, stakeholder awareness
        - Commercial Viability (part of Domain Expertise): practical business sense, revenue/cost awareness
        - Risk Management (part of Problem-Solving): what could go wrong, mitigation strategies
        """
      else
        ""
      end

    qa_block =
      Questions.all()
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {%{key: key, title: title, prompt: prompt}, idx} ->
        raw = answers |> Map.get(key, "") |> to_string() |> String.trim()
        body = if raw == "", do: "(no answer provided)", else: raw
        "Q#{idx}. #{title}\nPrompt: #{prompt}\nCandidate's answer: #{body}"
      end)

    present =
      Questions.all()
      |> Enum.filter(fn %{key: k} -> String.trim(to_string(Map.get(answers, k, ""))) != "" end)
      |> Enum.map(& &1.title)

    missing = (Questions.all() |> Enum.map(& &1.title)) -- present

    # `group` is unknown when the role isn't an exact catalog entry (e.g. a tenant
    # job-profile role like "AI Engineer"). Drop the domain phrase rather than
    # render an awkward "in the  domain".
    domain_phrase =
      if is_binary(group) and String.trim(group) != "", do: " in the #{group} domain", else: ""

    """
    You are a senior hiring assessor evaluating a FINAL-YEAR UNDERGRADUATE or FRESHER candidate for a #{sub} role#{domain_phrase}.

    This candidate has NO industry experience. Assess their ability to think clearly and apply what they have studied — not knowledge of enterprise tools. Reward clear thinking, honest reasoning, and genuine engagement. Do not penalise unfamiliarity with professional conventions they have never seen.

    CASE STUDY (what the candidate was given)
    #{case_study}

    CANDIDATE'S ANSWERS (7 sections)
    #{qa_block}

    Sections attempted: #{inspect(present)}
    Sections not attempted: #{inspect(missing)}

    SCORING RUBRIC — score each dimension independently before computing the total.
    1. DOMAIN KNOWLEDGE & CONCEPTUAL UNDERSTANDING — max 40. Correct use of #{sub} concepts, justified tools/methods, domain awareness. Deduct for factual errors or ignoring the domain.
    2. PROBLEM-SOLVING & STRUCTURED THINKING — max 30. Identifying the right problem, logical steps, trade-offs, constraints, risk awareness.
    3. INITIATIVE & FORWARD THINKING — max 30. Improvements beyond the immediate fix, scalability/cost awareness, realistic V2, stakeholder awareness.#{extra}

    MISSING SECTION POLICY: 1 missing → deduct 8 from the most relevant dimension; 2 → deduct 16; 3 → deduct 24; 4+ → total cannot exceed 45. Completion is part of the evaluation.

    RANDOM / NON-ANSWER RULE (apply BEFORE the rubric): if the submission is gibberish, random or filler text, UUIDs / hashes / IDs / numbers, single words/letters, copied text unrelated to the case (e.g. a pasted report/PDF), or otherwise does not genuinely engage the actual problem, score EVERY dimension 0 (at most 10, total ≤ 30) NO MATTER HOW LONG it is. Filling the fields with text that does not address the case earns NO marks. Only real, on-topic engagement earns rubric marks.

    CALIBRATION (freshers, not professionals): a candidate who attempts all 7 sections sincerely, identifies the core problem, proposes a reasonable approach, and names a few relevant tools should score 78–85 — a genuinely good submission. Reserve below 60 for genuinely vague/incomplete answers.

    OUTPUT — respond ONLY with this exact JSON. No markdown, no code fences, no prose.

    {
      "domain_score": <integer 0-40>,
      "problem_solving_score": <integer 0-30>,
      "leadership_score": <integer 0-30>,
      "total_score": <integer 0-100, equal to the sum of the three above>,
      "domain_feedback": "<2-3 sentences referencing specific sections>",
      "problem_solving_feedback": "<2-3 sentences on reasoning, structure, trade-offs>",
      "leadership_feedback": "<2-3 sentences on forward-thinking and initiative>",
      "strengths": ["<strength 1>", "<strength 2>", "<strength 3>"],
      "improvements": ["<actionable improvement 1>", "<improvement 2>", "<improvement 3>"],
      "overall_verdict": "Excellent | Good | Satisfactory | Needs Improvement",
      "summary": "<2-3 sentences addressed to a hiring manager>"
    }
    """
  end
end