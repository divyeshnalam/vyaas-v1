defmodule VyaasaCampus.AI8.Backfill do
  @moduledoc """
  Backfills `ai8_module_evaluations` from each module's existing (historical)
  assessment results, so students who completed assessments BEFORE AI8 publishing
  was added still show on the AI8 Overview.

  Run per tenant after deploy + `AI8.seed_config/0`:

      mix run -e "VyaasaCampus.AI8.Backfill.run_all()"          # every tenant
      mix run -e ~s|VyaasaCampus.AI8.Backfill.run("tenant_gbc")|  # one tenant

  Where a module stores real per-dimension scores (behavioral, psychometric,
  MCQ, resume) the backfill is exact. JAM and Interview pre-date their per-dim
  AI8 scoring, so their single overall score is applied to the dimensions the
  admin configured for that module (an approximation — flagged).
  """

  import Ecto.Query

  alias VyaasaCampus.Repo
  alias VyaasaCampus.Contexts.{AI8, Tenants}

  require Logger

  def run_all do
    Tenants.list_tenants()
    |> Enum.each(fn t -> run(t.schema_name) end)
  end

  def run(prefix) when is_binary(prefix) do
    Logger.info("AI8 backfill | tenant=#{prefix}")
    backfill_behavioral(prefix)
    backfill_psychometric(prefix)
    backfill_mcq(prefix)
    backfill_resume(prefix)
    backfill_jam(prefix)
    backfill_interview(prefix)
    :ok
  end

  # ── Behavioral (exact) ─────────────────────────────────────────────────────
  defp backfill_behavioral(prefix) do
    q =
      from(a in "student_behavioral_assessments",
        where: a.status == "completed",
        select: %{
          id: a.id, sid: a.student_id, tid: a.tenant_id,
          we: a.work_ethics_score, tw: a.teamwork_score, ad: a.adaptability_score,
          le: a.leadership_score, cf: a.communication_score
        }
      )

    each(q, prefix, fn r ->
      publish("behavioral", %{
        "work_ethics" => r.we, "collaboration" => r.tw, "adaptability" => r.ad,
        "leadership" => r.le, "cultural_fit" => r.cf
      }, r, "student_behavioral_assessment", prefix)
    end)
  end

  # ── Psychometric (exact composites) ─────────────────────────────────────────
  defp backfill_psychometric(prefix) do
    q =
      from(a in "student_psychometric_assessments",
        where: a.status == "completed",
        select: %{id: a.id, sid: a.student_id, tid: a.tenant_id,
          o: a.openness_score, c: a.conscientiousness_score,
          e: a.extraversion_score, ag: a.agreeableness_score, n: a.neuroticism_score}
      )

    # Composites MUST match Contexts.Psychometric.publish_ai8/2 so a backfilled
    # score equals what a fresh assessment would publish.
    #   work_ethics  = avg(Conscientiousness, Emotional Stability[n])
    #   adaptability = avg(Openness, Emotional Stability[n])
    #   cultural_fit = avg(Agreeableness, Extraversion)
    each(q, prefix, fn r ->
      publish("psychometric", %{
        "work_ethics" => composite([r.c, r.n]),
        "adaptability" => composite([r.o, r.n]),
        "cultural_fit" => composite([r.ag, r.e])
      }, r, "student_psychometric_assessment", prefix)
    end)
  end

  # ── MCQ (exact: percentage) ─────────────────────────────────────────────────
  defp backfill_mcq(prefix) do
    q =
      from(a in "assessment_attempts",
        where: a.status in ["submitted", "evaluated", "completed"] and not is_nil(a.percentage),
        select: %{id: a.id, sid: a.student_id, tid: nil, pct: a.percentage}
      )

    each(q, prefix, fn r ->
      pct = num(r.pct)
      publish("mcq", %{"domain_expertise" => pct, "problem_solving" => pct}, r, "assessment_attempt", prefix)
    end)
  end

  # ── Resume (exact: ATS score) ───────────────────────────────────────────────
  defp backfill_resume(prefix) do
    q =
      from(a in "student_ats_phases",
        where: not is_nil(a.ats_score),
        order_by: [asc: a.inserted_at],
        select: %{id: a.id, sid: a.student_id, tid: a.tenant_id, score: a.ats_score}
      )

    each(q, prefix, fn r ->
      publish("resume", %{"domain_expertise" => num(r.score)}, r, "student_ats_phase", prefix)
    end)
  end

  # ── JAM (approx: final_score → configured dims) ─────────────────────────────
  defp backfill_jam(prefix) do
    dims = AI8.weighted_dimensions("jam")

    q =
      from(a in "jam_sessions",
        where: a.status == "completed" and not is_nil(a.final_score),
        select: %{id: a.id, sid: a.student_id, tid: a.tenant_id, score: a.final_score}
      )

    each(q, prefix, fn r ->
      publish("jam", spread(dims, r.score), r, "jam_session", prefix)
    end)
  end

  # ── Interview (approx: overall_score → configured dims) ──────────────────────
  defp backfill_interview(prefix) do
    dims = AI8.weighted_dimensions("interview")

    q =
      from(a in "interview_sessions",
        where: a.status == "completed" and not is_nil(a.overall_score),
        select: %{id: a.id, sid: a.student_id, tid: a.tenant_id, score: a.overall_score}
      )

    each(q, prefix, fn r ->
      publish("interview", spread(dims, num(r.score)), r, "interview_session", prefix)
    end)
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────
  defp each(query, prefix, fun) do
    query |> Repo.all(prefix: prefix) |> Enum.each(fun)
  rescue
    e -> Logger.error("AI8 backfill query failed (#{prefix}): #{Exception.message(e)}")
  end

  defp publish(module, scores, row, source_type, prefix) do
    AI8.publish_module(
      module,
      scores,
      %{
        student_id: uuid(row.sid),
        tenant_id: uuid(Map.get(row, :tid)),
        source_type: source_type,
        source_id: uuid(row.id)
      },
      prefix
    )
  end

  # Spread a single overall score across the configured dimensions for a module.
  defp spread([], _score), do: %{}
  defp spread(dims, score), do: Map.new(dims, fn d -> {d, num(score)} end)

  defp composite(traits) do
    vals = Enum.map(traits, fn v -> if is_number(v), do: v, else: 3.0 end)
    avg = Enum.sum(vals) / length(vals)
    (avg / 5 * 100) |> round() |> min(100) |> max(0)
  end

  defp num(%Decimal{} = d), do: d |> Decimal.to_float() |> round()
  defp num(n) when is_number(n), do: round(n)
  defp num(_), do: 0

  # Schemaless queries return raw 16-byte uuids — load to string form for casting.
  defp uuid(nil), do: nil
  defp uuid(<<_::128>> = raw), do: Ecto.UUID.load!(raw)
  defp uuid(str) when is_binary(str), do: str
end
