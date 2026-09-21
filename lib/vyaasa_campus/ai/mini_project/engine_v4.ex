defmodule VyaasaCampus.AI.MiniProject.EngineV4 do
  @moduledoc """
  V4 viva-driven mini-project engine. Orchestrates the six LLM calls
  (profile → scenarios → artifact ceilings → 12 viva questions → per-answer
  scores → feedback) and defers all score math to
  `VyaasaCampus.AI.MiniProject.Scoring`.

  This is the assessment core; the LiveView flow (a later phase) drives it.
  """

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.MiniProject.{Metrics, Prompts, Scoring}

  require Logger

  @model "openai/gpt-oss-120b"

  @doc "Resume + JD -> structured candidate profile."
  def parse_profile(resume, jd) do
    Prompts.profile(resume, jd) |> call()
  end

  @doc "Two contrasting scenarios for the profile."
  def generate_scenarios(profile) do
    Prompts.scenario(profile) |> call()
  end

  @doc "Read the artifact, set D1–D4 ceilings (0–10)."
  def artifact_ceilings(scenario, submission_summary) do
    Prompts.ceiling(scenario, submission_summary) |> call()
  end

  @doc "Generate the 12 metric-tagged, time-budgeted viva questions."
  def viva_questions(scenario, submission_summary) do
    case Prompts.viva_questions(scenario, submission_summary) |> call() do
      {:ok, %{"questions" => qs}} when is_list(qs) -> {:ok, normalize_questions(qs)}
      {:ok, _} -> {:error, :bad_shape}
      err -> err
    end
  end

  @doc "Score the 12 answers 0–10 and detect contradictions. `qa_pairs` carry id/metric/question/answer."
  def score_viva_answers(scenario, submission_summary, qa_pairs) do
    Prompts.viva_answer_scores(scenario, submission_summary, qa_pairs) |> call()
  end

  @doc """
  Deterministically fuse ceilings + per-question viva scores into the final
  result (see `Scoring`). `ceilings` is `%{"D1"=>..,"D4"=>..}`; `question_scores`
  is the list from `score_viva_answers/3`; `contradiction` is a boolean.
  Optionally folds in timing via `apply_timing_to_result/4`.
  """
  def evaluate(ceilings, question_scores, contradiction, timing \\ nil) do
    viva_scores = Scoring.aggregate_viva_per_metric(question_scores)
    result = Scoring.compute_final_score(ceilings, viva_scores, contradiction == true)

    case timing do
      %{flag: flag, elapsed_min: e, estimate_min: est} ->
        Scoring.apply_timing_to_result(result, flag, e, est)

      _ ->
        result
    end
  end

  @doc "Narrative feedback after scoring."
  def feedback(scenario, profile, score_result, qa_pairs) do
    Prompts.feedback(scenario, profile, score_result, qa_pairs) |> call()
  end

  # ── internals ──────────────────────────────────────────────────────────────

  # Ensure each question has a valid metric and a clamped time budget.
  defp normalize_questions(qs) do
    qs
    |> Enum.filter(fn q -> is_map(q) and q["metric"] in Metrics.keys() end)
    |> Enum.map(fn q ->
      Map.put(q, "time_seconds", clamp_time(q["time_seconds"]))
    end)
  end

  defp clamp_time(n) when is_integer(n),
    do: max(Metrics.viva_min_seconds(), min(Metrics.viva_max_seconds(), n))

  defp clamp_time(_), do: Metrics.viva_default_seconds()

  defp call({system, user}) do
    messages = [
      %{role: "system", content: system},
      %{role: "user", content: user}
    ]

    case GroqClient.chat(messages,
           model: @model,
           temperature: 0.3,
           response_format: %{type: "json_object"},
           reasoning_effort: "low"
         ) do
      {:ok, %{"content" => raw}} -> raw |> GroqClient.strip_reasoning() |> GroqClient.extract_json()
      {:ok, raw} when is_binary(raw) -> raw |> GroqClient.strip_reasoning() |> GroqClient.extract_json()
      {:error, reason} -> {:error, reason}
    end
  end
end
