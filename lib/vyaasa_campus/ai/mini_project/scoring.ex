defmodule VyaasaCampus.AI.MiniProject.Scoring do
  @moduledoc """
  Viva-driven scoring engine (deterministic). Port of the V4 `scoring.py`.

  The LLM supplies only raw inputs — per-metric artifact ceilings (0–10) and
  per-question viva scores (0–10). This module does the fusion math so the score
  is consistent and auditable.

  Fusion rule (per metric):

      ratio = viva / 10
      if viva >= artifact  -> artifact + 0.5 * (viva - artifact)   # defends MORE than written
      else                 -> artifact * ratio                     # cannot defend what was written

  See moduledoc of the reference for the noise floor and authenticity gate.
  """

  alias VyaasaCampus.AI.MiniProject.Metrics

  @doc "Option-4 asymmetric fusion for a single metric. Returns 0.0–10.0."
  def fuse_metric(artifact, viva) do
    a = clamp10(to_f(artifact))
    v = clamp10(to_f(viva))

    final =
      if v >= a do
        a + 0.5 * (v - a)
      else
        a * (v / 10.0)
      end

    Float.round(clamp10(final), 2)
  end

  @doc """
  Don't let a metric's viva score fall below 2 unless at least two of its
  questions independently scored low (<= 3) — protects a nervous-but-genuine
  candidate from one bad answer tanking a metric.
  """
  def apply_noise_floor(viva_score, question_scores) do
    if viva_score >= 2 do
      viva_score
    else
      low_count = Enum.count(question_scores, &(&1 <= 3))
      if low_count >= 2, do: viva_score, else: 2.0
    end
  end

  @doc """
  Average per-question viva scores within each metric (applying the noise floor).
  `question_results` is a list of `%{"metric" => m, "score" => s}` (string or
  atom keys accepted). Returns `%{metric => viva_score}` for all metrics.
  """
  def aggregate_viva_per_metric(question_results) do
    by_metric =
      Enum.reduce(question_results, Map.new(Metrics.keys(), &{&1, []}), fn q, acc ->
        m = field(q, "metric")

        if Map.has_key?(acc, m) do
          Map.update!(acc, m, &[to_f(field(q, "score")) | &1])
        else
          acc
        end
      end)

    Map.new(by_metric, fn
      {m, []} ->
        {m, 0.0}

      {m, scores} ->
        avg = Enum.sum(scores) / length(scores)
        {m, Float.round(apply_noise_floor(avg, scores), 2)}
    end)
  end

  @doc """
  Authenticity verdict from the pattern of artifact→viva gaps.
  Returns one of: "genuine" | "minor_gaps" | "clustered_gaps" | "broad_gaps" | "contradicts".
  """
  def compute_authenticity_gate(ceilings, viva_scores, contradiction_flag) do
    if contradiction_flag do
      "contradicts"
    else
      # D5 has no artifact, so no gap to measure.
      gaps =
        for m <- Metrics.artifact_keys() do
          c = to_f(field(ceilings, m))
          v = to_f(field(viva_scores, m))
          max(0.0, c - v)
        end

      weak = Enum.count(gaps, &(&1 >= 3.5))

      cond do
        weak == 0 and Enum.all?(gaps, &(&1 <= 1.5)) -> "genuine"
        weak == 0 -> "minor_gaps"
        weak == 1 -> "clustered_gaps"
        true -> "broad_gaps"
      end
    end
  end

  @doc """
  Full pipeline: fuse each metric, weight into a 0–100 composite, apply the
  authenticity gate, assign a band. Returns a map with everything the feedback
  report needs (string keys, matching the V4 shape).
  """
  def compute_final_score(ceilings, viva_scores, contradiction_flag \\ false) do
    per_metric =
      Map.new(Metrics.keys(), fn m ->
        c = to_f(field(ceilings, m))
        v = to_f(field(viva_scores, m))

        {fused, ceiling} =
          if m == "D5" do
            # D5 has no artifact — scored purely on the viva answer.
            {Float.round(clamp10(v), 2), v}
          else
            {fuse_metric(c, v), c}
          end

        {m,
         %{
           "artifact_ceiling" => Float.round(ceiling, 2),
           "viva_score" => Float.round(v, 2),
           "fused" => fused,
           "weight" => Metrics.weight(m),
           "gap" => Float.round(max(0.0, ceiling - v), 2)
         }}
      end)

    composite_10 =
      Enum.reduce(Metrics.keys(), 0.0, fn m, acc ->
        acc + per_metric[m]["fused"] * Metrics.weight(m)
      end) / 100.0

    composite_100 = round(composite_10 * 10)

    verdict = compute_authenticity_gate(ceilings, viva_scores, contradiction_flag)

    {gated_score, gate_note} =
      case verdict do
        "broad_gaps" ->
          {min(composite_100, 54),
           "Composite capped: the candidate could not defend most of the artifact in the viva, so the artifact likely is not their own work."}

        "contradicts" ->
          {min(composite_100, 39),
           "Flagged for human review: viva answers contradict the submitted artifact."}

        "clustered_gaps" ->
          {composite_100,
           "One competency could not be defended in the viva; the score for that metric reflects what was demonstrated live."}

        _ ->
          {composite_100, ""}
      end

    %{
      "per_metric" => per_metric,
      "composite_raw" => composite_100,
      "final_score" => round(gated_score),
      "authenticity" => verdict,
      "gate_note" => gate_note,
      "band" => score_to_band(gated_score)
    }
  end

  @doc "Map a 0–100 score to its band label."
  def score_to_band(score) do
    {label, _min} = Enum.find(Metrics.bands(), {"Not ready", 0}, fn {_l, m} -> score >= m end)
    label
  end

  @doc """
  Fold project completion timing into the result.

  Soft mode (default): records timing; a suspiciously fast submission reinforces
  an existing broad-gaps authenticity concern but never lowers a viva-supported
  score; an over-estimate submission is informational only.

  Hard mode: an "over" submission caps the final score at the overtime cap.

  `timing_flag` is `"fast" | "over" | "on_time" | nil`.
  """
  def apply_timing_to_result(result, timing_flag, elapsed_min, estimate_min) do
    result =
      Map.put(result, "timing", %{
        "flag" => timing_flag,
        "elapsed_min" => elapsed_min,
        "estimate_min" => estimate_min,
        "mode" => Metrics.project_timer_mode()
      })

    cond do
      is_nil(timing_flag) ->
        result

      Metrics.project_timer_mode() == "hard" and timing_flag == "over" ->
        capped = min(result["final_score"], Metrics.project_overtime_cap())

        result
        |> Map.put("final_score", round(capped))
        |> Map.put("band", score_to_band(capped))
        |> Map.put(
          "timing_note",
          "HARD timer mode: submitted in #{elapsed_min} min vs a #{estimate_min} min estimate, so the score was capped at #{Metrics.project_overtime_cap()}."
        )

      timing_flag == "fast" ->
        note =
          "Submitted in #{elapsed_min} min against a #{estimate_min} min estimate — unusually fast. This is a flag to consider alongside the viva, not an automatic penalty."

        result = Map.put(result, "timing_note", note)

        if result["authenticity"] == "broad_gaps" do
          Map.put(
            result,
            "gate_note",
            String.trim("#{result["gate_note"]} The unusually fast submission reinforces this concern.")
          )
        else
          result
        end

      timing_flag == "over" ->
        Map.put(
          result,
          "timing_note",
          "Submitted in #{elapsed_min} min against a #{estimate_min} min estimate. Over the estimate, but this is informational only and did not affect the score."
        )

      true ->
        Map.put(
          result,
          "timing_note",
          "Submitted in #{elapsed_min} min, within the #{estimate_min} min estimate."
        )
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────────
  defp clamp10(n), do: max(0.0, min(10.0, n))

  defp to_f(n) when is_float(n), do: n
  defp to_f(n) when is_integer(n), do: n * 1.0

  defp to_f(n) when is_binary(n) do
    case Float.parse(n) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_f(_), do: 0.0

  # Read a key that may be a string or atom.
  defp field(map, key) when is_map(map), do: map[key] || map[String.to_atom(key)]
  defp field(_, _), do: nil
end
