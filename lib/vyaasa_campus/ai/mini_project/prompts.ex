defmodule VyaasaCampus.AI.MiniProject.Prompts do
  @moduledoc """
  All LLM prompts for the V4 viva-driven mini-project. Port of `prompts.py`.

  Each builder returns `{system, user}`. The evaluator prompts return only RAW
  inputs (artifact ceilings, per-question viva scores) — the final score is
  computed deterministically in `VyaasaCampus.AI.MiniProject.Scoring`.
  """

  @doc "1. Resume + JD -> structured candidate profile."
  def profile(resume, jd) do
    system =
      "You are a professional profile extractor for a skills assessment platform. " <>
        "Extract structured information from a resume and job description. " <>
        "Return ONLY valid JSON. No text outside the JSON object."

    user = """
    Extract a structured candidate profile from the resume and JD below.

    RESUME:
    #{slice(resume, 3000)}

    JOB DESCRIPTION:
    #{slice(jd, 2000)}

    Return ONLY this JSON:
    {
      "candidate_name": "name or Candidate",
      "job_title": "target role from JD",
      "domain_cluster": "engineering | data_analytics | product_design | business_strategy | commercial_sales | hr_people | operations | creative_content | finance | healthcare | other",
      "experience_level": "fresher | junior | mid",
      "top_skills": ["skill1","skill2","skill3","skill4","skill5"],
      "existing_projects": ["project1","project2"],
      "is_career_switch": false,
      "prior_domain": null,
      "jd_tools": ["tool1","tool2","tool3"],
      "is_technical_role": true,
      "submission_format_hint": "document | code_and_doc | presentation | mixed"
    }
    """

    {system, user}
  end

  @doc "2. Generate two contrasting project scenarios."
  def scenario(profile) do
    system =
      "You are a senior assessment designer creating realistic workplace project " <>
        "scenarios. Write as a real hiring manager, never as a test platform. " <>
        "Every scenario must be completable using ONLY publicly available information " <>
        "and the candidate's own knowledge — no proprietary data, no large datasets, " <>
        "no API keys. Return ONLY valid JSON. No text outside the JSON object."

    skills = profile |> get_list("top_skills", 5) |> join_or("their stated skills")
    tools = profile |> get_list("jd_tools", 4) |> join_or("none specified")
    avoid = profile |> get_list("existing_projects", 3) |> join_or("none listed")

    user = """
    Design exactly 2 realistic workplace project scenarios for this candidate.

    CANDIDATE: #{field(profile, "job_title", "professional")} · #{field(profile, "experience_level", "junior")} level · domain: #{field(profile, "domain_cluster", "general")}
    SKILLS TO EXERCISE: #{skills}
    TOOLS FROM THE JD: #{tools}
    DO NOT re-use these existing projects: #{avoid}

    RULES:
    - Completable with ONLY public information + the candidate's own knowledge and stated assumptions. No proprietary data. If data is needed, the candidate CREATES a small sample (10-50 rows) with a documented schema — never a large file.
    - The two scenarios MUST contrast: A = an ARTEFACT produced by ANALYSIS; B = a RECOMMENDATION produced by SYNTHESIS.
    - Each scenario hides exactly ONE ambiguity. Never name it in scenario_text; describe it only in ambiguity_embedded (evaluator-only).
    - scenario_text is a 220-300 word brief containing, in order: (a) 3 sentences of context — fictional company, a named stakeholder, the situation; (b) the task as "Produce X so that [stakeholder] can [decision]"; (c) resources — public sources, stated assumptions, sample data only; (d) exactly 3 constraints, one of which IS the hidden ambiguity (unlabelled); (e) the expected ZIP structure; (f) 2 reflection questions starting "Walk me through your decision to...".

    Return ONLY a single JSON OBJECT (not an array, no text before or after) with EXACTLY these keys:
    {
      "scenario_a": {"title":"<=8 words","deliverable_type":"artefact","format_type":"document","cognitive_demand":"analysis","primary_skill_tested":"","scenario_text":"220-300 word brief","company_name":"","stakeholder_name":"name and role","decision_enabled":"","acceptance_criteria":["","",""],"estimated_minutes":75,"time_range":"60-90 minutes","time_rationale":"","ambiguity_type":"missing_constraint","ambiguity_embedded":"evaluator-only: the gap, its type, and a strong resolution","reflection_questions":["Walk me through your decision to...","Walk me through your decision to..."]},
      "scenario_b": {"title":"<=8 words","deliverable_type":"recommendation","format_type":"code_and_doc","cognitive_demand":"synthesis","primary_skill_tested":"","scenario_text":"220-300 word brief","company_name":"","stakeholder_name":"name and role","decision_enabled":"","acceptance_criteria":["","",""],"estimated_minutes":90,"time_range":"75-105 minutes","time_rationale":"","ambiguity_type":"conflicting_requirement","ambiguity_embedded":"evaluator-only","reflection_questions":["Walk me through your decision to...","Walk me through your decision to..."]},
      "contrast_check": {"contrast_sentence":"how A and B test different skills"}
    }
    """

    {system, user}
  end

  @doc "3. Read the artifact, set the D1–D4 ceilings."
  def ceiling(scenario, submission_summary) do
    system =
      "You are an assessment evaluator. You read a candidate's submitted artifact " <>
        "and rate, on its face value, the maximum competence it could demonstrate " <>
        "on four thinking dimensions. This sets a CEILING — the candidate cannot " <>
        "score above this in the viva, but may score below if they cannot defend it. " <>
        "Be conservative: rate what is genuinely present, not length or polish. " <>
        "Return ONLY valid JSON."

    user = """
    Read this submitted artifact and set the CEILING score (0-10) for each dimension.

    SCENARIO:
    Title: #{field(scenario, "title", "")}
    Task: #{slice(field(scenario, "scenario_text", ""), 500)}
    Acceptance criteria: #{json(get_list(scenario, "acceptance_criteria", 99))}
    Injected ambiguity (evaluator-only): #{field(scenario, "ambiguity_embedded", "")}

    SUBMITTED ARTIFACT:
    #{slice(submission_summary, 2800)}

    Rate the MAXIMUM each dimension could be, based ONLY on what the artifact shows:

    D1 Problem comprehension: does the artifact show correct understanding of the
       task, recipient, and decision enabled?
    D2 Reasoning ownership: does the artifact explain WHY decisions were made, with
       trade-offs named (not just what was done)?
    D3 Depth of analysis: does the artifact show real analytical mechanics, or just
       surface outputs?
    D4 Constraint handling: does the artifact address the injected ambiguity with a
       stated, defended assumption?

    Be conservative. A polished but shallow artifact gets a LOW D3 ceiling.
    A short but deeply reasoned artifact gets a HIGH D2 ceiling.

    Return ONLY this JSON:
    {
      "D1": 7,
      "D2": 8,
      "D3": 6,
      "D4": 9,
      "ceiling_notes": {
        "D1": "one sentence citing what in the artifact justifies this ceiling",
        "D2": "one sentence",
        "D3": "one sentence",
        "D4": "one sentence"
      }
    }
    """

    {system, user}
  end

  @doc "4. Generate the 12 viva questions (2 D1, 3 D2, 3 D3, 2 D4, 2 D5)."
  def viva_questions(scenario, submission_summary) do
    system =
      "You are an assessment integrity specialist generating viva (oral defence) " <>
        "questions. Each question must be answerable ONLY by someone who personally " <>
        "did the work — it must reference specific content, numbers, or decisions in " <>
        "THIS artifact. Generic questions answerable from the brief alone are useless. " <>
        "Return ONLY valid JSON."

    user = """
    Generate exactly 12 viva questions to test whether the candidate truly did this work.

    SCENARIO:
    Title: #{field(scenario, "title", "")}
    Primary skill: #{field(scenario, "primary_skill_tested", "")}
    Acceptance criteria: #{json(get_list(scenario, "acceptance_criteria", 99))}
    Injected ambiguity (evaluator-only): #{field(scenario, "ambiguity_embedded", "")}

    SUBMITTED ARTIFACT:
    #{slice(submission_summary, 2800)}

    Generate EXACTLY 12 questions distributed across 5 metrics:

    D1 Problem comprehension — 2 questions: probe whether they understood the real
       problem, the recipient, and the scope ambiguity.
    D2 Reasoning ownership — 3 questions: probe WHY specific decisions were made.
       Reference actual decisions visible in the artifact. Ask what they rejected.
    D3 Depth of analysis — 3 questions: probe the mechanics. Reference a SPECIFIC
       number, method, or output in the artifact and ask what it means / what would
       change it. These expose whether they understand their own analysis.
    D4 Constraint handling — 2 questions: probe how they handled the unstated gap in
       the brief (without revealing it was deliberate) and what happens if their
       assumption is wrong.
    D5 Adaptive reasoning — 2 questions: pose a CHANGE of circumstance ("suppose the
       budget is now zero" / "suppose the timeline halved") and ask them to re-reason.
       These cannot be pre-prepared. Base the change on their own stated assumptions.

    Every question must reference something SPECIFIC in the artifact.
    No generic questions answerable from the brief alone.

    For EACH question, assign a "time_seconds" budget between 180 (simple recall
    or single-decision questions) and 300 (multi-part reasoning, depth mechanics,
    or adaptive re-reasoning). Harder questions get more time. D3 (depth) and D5
    (adaptive) questions usually warrant 240-300; D1 usually 180-240.

    Return ONLY this JSON (exactly 12 objects, in metric order D1,D1,D2,D2,D2,D3,D3,D3,D4,D4,D5,D5):
    {
      "questions": [
        {"id":1,"metric":"D1","question":"...","references":"what artifact content this points to","time_seconds":200},
        {"id":2,"metric":"D1","question":"...","references":"...","time_seconds":180},
        {"id":3,"metric":"D2","question":"...","references":"...","time_seconds":240},
        {"id":4,"metric":"D2","question":"...","references":"...","time_seconds":240},
        {"id":5,"metric":"D2","question":"...","references":"...","time_seconds":240},
        {"id":6,"metric":"D3","question":"...","references":"...","time_seconds":300},
        {"id":7,"metric":"D3","question":"...","references":"...","time_seconds":270},
        {"id":8,"metric":"D3","question":"...","references":"...","time_seconds":270},
        {"id":9,"metric":"D4","question":"...","references":"...","time_seconds":240},
        {"id":10,"metric":"D4","question":"...","references":"...","time_seconds":240},
        {"id":11,"metric":"D5","question":"...","references":"...","time_seconds":300},
        {"id":12,"metric":"D5","question":"...","references":"...","time_seconds":300}
      ]
    }
    """

    {system, user}
  end

  @doc "5. Score each viva answer 0–10 + detect contradictions. `qa_pairs` are maps with id/metric/question/answer."
  def viva_answer_scores(scenario, submission_summary, qa_pairs) do
    system =
      "You are an assessment evaluator scoring a candidate's viva answers. " <>
        "Score each answer 0-10 on SPECIFICITY and CORRECTNESS relative to their own " <>
        "artifact — NOT on fluency. A specific, correct answer that explains THEIR " <>
        "actual choice scores high. A smooth but generic answer that could apply to " <>
        "any project scores low. A nervous but specific answer still scores well. " <>
        "Also detect if any answer CONTRADICTS the artifact. Return ONLY valid JSON."

    qa_text =
      qa_pairs
      |> Enum.map_join("\n", fn q ->
        "Q#{field(q, "id", "")} [#{field(q, "metric", "")}]: #{field(q, "question", "")}\nANSWER: #{field(q, "answer", "")}\n"
      end)

    user = """
    Score each viva answer 0-10 based on specificity and correctness vs the artifact.

    ARTIFACT (ground truth to check answers against):
    #{slice(submission_summary, 2400)}

    SCENARIO injected ambiguity (for D4 answers): #{field(scenario, "ambiguity_embedded", "")}

    VIVA QUESTIONS AND ANSWERS:
    #{qa_text}

    SCORING GUIDE (per answer, 0-10):
      9-10 = specific, correct, explains THEIR actual choice with reasoning
      6-8  = mostly specific, explains the decision but some gaps
      3-5  = generic; could apply to any project; describes what not why
      0-2  = cannot explain; vague; or contradicts the artifact

    For D5 (adaptive) answers: score how well they RE-REASON to the changed
    circumstance, not whether they recall the original.

    CONTRADICTION CHECK: if any answer directly contradicts the artifact (e.g. claims
    a method they did not use, or cannot identify something plainly in their own work),
    set contradiction=true and name it.

    Return ONLY this JSON (one score per question id, all 12):
    {
      "question_scores": [
        {"id":1,"metric":"D1","score":7,"note":"why this score — cite specifics"}
      ],
      "contradiction": false,
      "contradiction_detail": ""
    }
    """

    {system, user}
  end

  @doc "6. Feedback narrative — after Scoring computes the numbers."
  def feedback(scenario, profile, score_result, qa_pairs) do
    alias VyaasaCampus.AI.MiniProject.Metrics

    system =
      "You are a senior assessor writing feedback to a candidate after a viva. " <>
        "Write as a thoughtful senior colleague. Reference both the artifact and how " <>
        "they defended it in the viva. Be specific and honest. Never generic. " <>
        "Return ONLY valid JSON."

    pm = score_result["per_metric"] || %{}

    metric_lines =
      Metrics.keys()
      |> Enum.map_join("\n", fn m ->
        d = pm[m] || %{}
        "#{m} (#{Metrics.name(m)}): artifact ceiling #{d["artifact_ceiling"]}, viva #{d["viva_score"]}, final #{d["fused"]}"
      end)

    qa_text =
      qa_pairs
      |> Enum.map_join("\n", fn q ->
        "Q#{field(q, "id", "")} [#{field(q, "metric", "")}]: #{field(q, "question", "")}\nANSWER: #{slice(field(q, "answer", ""), 300)}"
      end)

    user = """
    Write feedback for this candidate based on their artifact AND viva defence.

    CANDIDATE: #{field(profile, "candidate_name", "Candidate")} — #{field(profile, "job_title", "")}, #{field(profile, "experience_level", "")} level
    PROJECT: #{field(scenario, "title", "")}

    SCORES (computed — do not recompute):
    Final: #{score_result["final_score"]}/100 — band #{score_result["band"]}
    Authenticity verdict: #{score_result["authenticity"]}
    #{metric_lines}

    VIVA Q&A:
    #{qa_text}

    Write feedback that:
    - References how they defended (or failed to defend) their work in the viva
    - Names where artifact quality and viva performance diverged, if they did
    - Is specific to THIS candidate's answers, never generic
    - Primary gap uses "rather than" framing
    - Each action has what / how / why (role-relevant)

    Return ONLY this JSON:
    {
      "overall_sentence": "one sentence defining this candidate's performance",
      "strengths": [
        {"title":"name","evidence":"cite a specific viva answer or artifact element","why":"role relevance"}
      ],
      "primary_gap": {
        "metric":"D_",
        "gap_sentence":"direct statement of the gap",
        "what_happened":"what they did vs stronger response using 'rather than'",
        "viva_vs_artifact":"how their viva defence compared to their artifact on this metric",
        "positive_flip":"how this gap closes"
      },
      "metric_notes": {
        "D1":"one sentence on artifact vs viva for D1",
        "D2":"one sentence","D3":"one sentence","D4":"one sentence","D5":"one sentence"
      },
      "actions": [
        {"priority":"Do first","title":"name","what":"skill","how":"concrete activity","why":"role link"},
        {"priority":"Do next","title":"name","what":"skill","how":"concrete activity","why":"role link"},
        {"priority":"Do later","title":"name","what":"skill","how":"concrete activity","why":"role link"}
      ]
    }
    """

    {system, user}
  end

  # ── helpers ────────────────────────────────────────────────────────────────
  defp slice(nil, _), do: ""
  defp slice(s, n) when is_binary(s), do: String.slice(s, 0, n)
  defp slice(s, n), do: slice(to_string(s), n)

  defp field(map, key, default) when is_map(map) do
    case map[key] || map[safe_atom(key)] do
      nil -> default
      "" -> default
      v -> v
    end
  end

  defp field(_, _, default), do: default

  defp get_list(map, key, take) when is_map(map) do
    case map[key] || map[safe_atom(key)] do
      list when is_list(list) -> Enum.take(list, take)
      _ -> []
    end
  end

  defp get_list(_, _, _), do: []

  defp join_or([], fallback), do: fallback
  defp join_or(list, fallback), do: list |> Enum.join(", ") |> blank_to(fallback)

  defp blank_to("", fallback), do: fallback
  defp blank_to(s, _), do: s

  defp json(term), do: Jason.encode!(term)

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> :"#{key}"
  end
end
