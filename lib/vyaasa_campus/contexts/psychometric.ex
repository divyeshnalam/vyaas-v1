defmodule VyaasaCampus.Contexts.Psychometric do
  @moduledoc """
  Context for adaptive Big Five (OCEAN) psychometric assessments.

  Owns persistence of the adaptive engine's state (in the existing
  `student_psychometric_assessments.metadata` JSON column) so the engine
  itself can stay pure / stateless. No DB schema changes — the existing
  per-trait float columns are populated at completion time by mapping
  the engine's trait averages.
  """

  import Ecto.Query
  alias VyaasaCampus.AI.PsychometricEngine
  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.StudentPsychometricAssessment

  require Logger

  # ============================================================================
  # SESSION LIFECYCLE
  # ============================================================================

  @doc """
  Start an adaptive assessment for a student.

  Creates the DB row (status = "started"), runs the engine to generate
  the first question, persists the engine state in `metadata`, and
  returns `{:ok, %{assessment, question}}`.
  """
  def start_adaptive(student_id, tenant_id, tenant_schema) do
    with :ok <- VyaasaCampus.Contexts.AttemptGuard.check(student_id, :psychometric, tenant_id, tenant_schema) do
      do_start_adaptive(student_id, tenant_id, tenant_schema)
    end
  end

  defp do_start_adaptive(student_id, tenant_id, tenant_schema) do
    session_id = Ecto.UUID.generate()
    request_id = Ecto.UUID.generate()

    next_attempt =
      from(a in StudentPsychometricAssessment,
        where: a.student_id == ^student_id,
        select: coalesce(max(a.attempt_number), 0)
      )
      |> Repo.one(prefix: tenant_schema)
      |> Kernel.+(1)

    case PsychometricEngine.start_assessment() do
      {:ok, %{state: state, question: question}} ->
        attrs = %{
          student_id: student_id,
          tenant_id: tenant_id,
          session_id: session_id,
          request_id: request_id,
          attempt_number: next_attempt,
          metadata: %{"engine_state" => state, "engine" => "adaptive"}
        }

        case StudentPsychometricAssessment.start_changeset(attrs)
             |> put_metadata(%{"engine_state" => state, "engine" => "adaptive"})
             |> Repo.insert(prefix: tenant_schema) do
          {:ok, assessment} ->
            Logger.info("PSYCH | Started adaptive session=#{session_id} student=#{student_id}")
            {:ok, %{assessment: assessment, question: question}}

          {:error, changeset} ->
            Logger.error("PSYCH | Failed to insert assessment: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      {:error, reason} ->
        Logger.error("PSYCH | Engine failed to start: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Submit a Likert answer (e.g. "Strongly Agree") for the current question.

  Loads engine state from DB, runs the engine, persists updated state.
  Returns one of:
    * `{:ok, %{assessment, question}}` — next question ready
    * `{:ok, %{assessment, complete: true}}` — assessment finished
    * `{:error, reason}`
  """
  def submit_answer(session_id, answer, tenant_schema) do
    # Opik: scope this assessment's thread id around the (unchanged) body so the
    # LLM follow-up call joins the session thread. Result passes through as-is.
    VyaasaCampus.AI.Tracing.with_thread_id(session_id, fn ->
      do_submit_answer(session_id, answer, tenant_schema)
    end)
  end

  defp do_submit_answer(session_id, answer, tenant_schema) do
    case get_assessment_by_session(session_id, tenant_schema) do
      nil ->
        {:error, :not_found}

      %{status: status} when status in ["completed", "failed"] ->
        {:error, :already_finalised}

      assessment ->
        state = load_state(assessment)

        case PsychometricEngine.submit_answer(state, answer) do
          {:ok, %{state: new_state, status: :complete}} ->
            persist_complete_state(assessment, new_state, tenant_schema)

          {:ok, %{state: new_state, status: :continue, question: question}} ->
            case persist_state(assessment, new_state, tenant_schema) do
              {:ok, updated} -> {:ok, %{assessment: updated, question: question}}
              err -> err
            end

          {:error, reason} ->
            Logger.error("PSYCH | submit_answer engine error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Generate the final report for a completed assessment.

  Reads engine state, calls the LLM for the interpretation report,
  populates per-trait score columns, and marks the assessment completed.
  """
  def finalize_report(session_id, tenant_schema) do
    # Opik: same scoped thread id for the report LLM call (also reached from
    # force_complete in the finalizer job). Result passes through as-is.
    VyaasaCampus.AI.Tracing.with_thread_id(session_id, fn ->
      do_finalize_report(session_id, tenant_schema)
    end)
  end

  defp do_finalize_report(session_id, tenant_schema) do
    case get_assessment_by_session(session_id, tenant_schema) do
      nil ->
        {:error, :not_found}

      %{status: "completed"} = a ->
        {:ok, a}

      assessment ->
        state = load_state(assessment)

        case PsychometricEngine.generate_report(state) do
          {:ok, %{report: report, trait_scores: trait_scores}} ->
            save_report_columns(assessment, report, trait_scores, tenant_schema)

          {:error, reason} ->
            Logger.error("PSYCH | Report failed: #{inspect(reason)}")
            mark_failed(assessment, "report_failed: #{inspect(reason)}", tenant_schema)
            {:error, reason}
        end
    end
  end

  # ============================================================================
  # PERSISTENCE HELPERS
  # ============================================================================

  defp put_metadata(changeset, metadata) do
    Ecto.Changeset.put_change(changeset, :metadata, metadata)
  end

  defp load_state(assessment) do
    case assessment.metadata do
      %{"engine_state" => state} when is_map(state) -> state
      _ -> PsychometricEngine.init_state()
    end
  end

  defp persist_state(assessment, new_state, tenant_schema) do
    metadata = Map.put(assessment.metadata || %{}, "engine_state", new_state)

    assessment
    |> StudentPsychometricAssessment.changeset(%{metadata: metadata})
    |> Repo.update(prefix: tenant_schema)
  end

  defp persist_complete_state(assessment, new_state, tenant_schema) do
    metadata = Map.put(assessment.metadata || %{}, "engine_state", new_state)

    case assessment
         |> StudentPsychometricAssessment.changeset(%{metadata: metadata, status: "processing"})
         |> Repo.update(prefix: tenant_schema) do
      {:ok, updated} -> {:ok, %{assessment: updated, complete: true}}
      err -> err
    end
  end

  # Parse the reference markdown report (## Overall Summary / ## Strengths /
  # ## Development Areas) into {overall_summary, strengths[], development_areas[]}.
  defp parse_markdown_report(md) when is_binary(md) do
    sections =
      md
      |> String.split(~r/^\s*#+\s*/m, trim: true)
      |> Enum.reduce(%{}, fn chunk, acc ->
        case String.split(chunk, "\n", parts: 2) do
          [header, body] -> Map.put(acc, header |> String.trim() |> String.downcase(), body)
          [header] -> Map.put(acc, header |> String.trim() |> String.downcase(), "")
        end
      end)

    %{
      overall_summary: sections |> Map.get("overall summary", "") |> String.trim(),
      strengths: sections |> Map.get("strengths", "") |> bullets(),
      development_areas: sections |> Map.get("development areas", "") |> bullets()
    }
  end

  defp parse_markdown_report(_), do: %{overall_summary: "", strengths: [], development_areas: []}

  defp bullets(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.replace(&1, ~r/^\s*[-*·•]\s*/, ""))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
  end

  # Save the AI report + per-trait score columns. Marks status = completed.
  defp save_report_columns(assessment, report, trait_scores, tenant_schema) do
    score_attrs =
      trait_scores
      |> Enum.reduce(%{}, fn {trait, value}, acc ->
        case PsychometricEngine.trait_to_schema_column(trait) do
          nil -> acc
          _col when value in [nil, "N/A"] -> acc
          col -> Map.put(acc, col, value)
        end
      end)

    # The engine now returns the reference markdown report (## Overall Summary /
    # ## Strengths / ## Development Areas). Parse it into the structured fields
    # the UI + report email already consume.
    parsed = parse_markdown_report(report)

    full_attrs =
      Map.merge(score_attrs, %{
        overall_summary: parsed.overall_summary,
        factor_reports: %{
          "overall_summary" => parsed.overall_summary,
          "strengths" => parsed.strengths,
          "development_areas" => parsed.development_areas,
          "factor_reports" => []
        },
        strengths: parsed.strengths,
        development_areas: parsed.development_areas,
        suggestions: [],
        factor_scores: trait_scores,
        raw_report_json: %{"report" => report, "trait_scores" => trait_scores}
      })

    case assessment
         |> StudentPsychometricAssessment.complete_changeset(full_attrs)
         |> Repo.update(prefix: tenant_schema) do
      {:ok, updated} ->
        finalize_side_effects(updated, tenant_schema)
        {:ok, updated}

      {:error, changeset} ->
        Logger.error("PSYCH | save_report changeset error: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp finalize_side_effects(assessment, tenant_schema) do
    DashboardEvents.broadcast_session_event(:psychometric, :completed, tenant_schema, assessment.student_id)
    publish_ai8(assessment, tenant_schema)
    VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:psychometric, assessment.id, tenant_schema)
  end

  # Map the Big Five traits onto the AI8 dimensions CONFIGURED for psychometric
  # (adaptability / work_ethics / cultural_fit). The old mapping emitted
  # collaboration/leadership, which aren't psychometric's AI8 dimensions, so they
  # were silently dropped and two of the three dimensions got no input at all.
  #   work_ethics  = avg(Conscientiousness, Emotional Stability)
  #   adaptability = avg(Openness, Emotional Stability)   (open to change + resilient)
  #   cultural_fit = avg(Agreeableness, Extraversion)     (gets along + engages)
  # Each composite is the average of its source traits (1–5) scaled by /5*100.
  # NOTE: our `neuroticism_score` column stores Emotional Stability (high = stable).
  defp publish_ai8(a, tenant_schema) do
    scores = %{
      "work_ethics" => composite([a.conscientiousness_score, a.neuroticism_score]),
      "adaptability" => composite([a.openness_score, a.neuroticism_score]),
      "cultural_fit" => composite([a.agreeableness_score, a.extraversion_score])
    }

    AI8.publish_module(
      "psychometric",
      scores,
      %{
        student_id: a.student_id,
        tenant_id: a.tenant_id,
        source_type: "student_psychometric_assessment",
        source_id: a.id
      },
      tenant_schema
    )
  end

  # Average the source Big Five trait scores (1–5; missing → 3.0 neutral) and
  # scale to 0–100, matching the psychometric service's _build_trait_scores.
  defp composite(traits) do
    vals = Enum.map(traits, fn v -> if is_number(v), do: v, else: 3.0 end)
    avg = Enum.sum(vals) / length(vals)
    (avg / 5 * 100) |> round() |> min(100) |> max(0)
  end

  defp mark_failed(assessment, error_message, tenant_schema) do
    metadata = Map.put(assessment.metadata || %{}, "last_error", error_message)

    assessment
    |> StudentPsychometricAssessment.changeset(%{status: "failed", metadata: metadata})
    |> Repo.update(prefix: tenant_schema)
  end

  @terminal_statuses ~w(completed failed)

  @doc """
  Force-completes an assessment abandoned mid-session (tab closed / crashed).

  NOTE: this reverses a prior deliberate decision documented on
  `PsychometricLive` — a partial adaptive attempt (e.g. 2 of ~20 items
  answered) used to be left as a stale "started" row and simply abandoned on
  return, on the reasoning that a composite from that little signal is noise,
  not a real personality score. That decision predates the abandoned-session
  standardization applied across all 8 assessment types: every closed tab
  now reaches a terminal record instead of staying stuck forever. Kept here
  as the one flagged exception to "just reuse the normal completion path" —
  see the two branches below.

  Any answered questions exist -> reuses `finalize_report/2` directly (the
  exact function a normal finish calls), so a partial attempt still gets a
  real interpretation from whatever signal exists, same as every other type.

  Zero answered questions -> short-circuits to a direct terminal write with
  trait score columns left `nil` rather than fabricated (`complete_changeset/2`
  doesn't require them) — there is no signal to interpret, so skip the LLM
  call entirely rather than asking it to produce a report from nothing.

  Idempotent: a session already in a terminal status is left untouched.
  """
  def force_complete(session_id, tenant_schema) do
    case get_assessment_by_session(session_id, tenant_schema) do
      nil ->
        {:error, :not_found}

      %{status: status} when status in @terminal_statuses ->
        {:ok, :already_terminal}

      assessment ->
        # Opik filter labels for the report trace (runs in the finalizer job, no LiveView).
        VyaasaCampus.AI.Tracing.put_metadata(%{
          student_id: assessment.student_id,
          module: "psychometric",
          tenant: tenant_schema
        })

        if any_answers?(assessment) do
          finalize_report(session_id, tenant_schema)
        else
          abandon_without_answers(assessment, tenant_schema)
        end
    end
  end

  defp any_answers?(assessment) do
    assessment
    |> load_state()
    |> Map.get("trait_scores", %{})
    |> Enum.any?(fn {_trait, scores} -> scores != [] end)
  end

  defp abandon_without_answers(assessment, tenant_schema) do
    attrs = %{
      overall_summary: "This psychometric assessment was abandoned before any questions were answered.",
      factor_reports: %{},
      strengths: [],
      development_areas: [],
      suggestions: [],
      factor_scores: %{},
      raw_report_json: %{}
    }

    case assessment
         |> StudentPsychometricAssessment.complete_changeset(attrs)
         |> Repo.update(prefix: tenant_schema) do
      {:ok, updated} ->
        finalize_side_effects(updated, tenant_schema)
        {:ok, updated}

      {:error, changeset} ->
        Logger.error("PSYCH | force_complete direct-write changeset error: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # ============================================================================
  # READ HELPERS
  # ============================================================================

  def get_assessment_by_session(session_id, tenant_schema) do
    from(a in StudentPsychometricAssessment, where: a.session_id == ^session_id)
    |> Repo.one(prefix: tenant_schema)
  end

  @doc "Log a proctoring violation (fullscreen exit / tab / blur). Log-only."
  def record_violation(session_id, type, tenant_schema) do
    case get_assessment_by_session(session_id, tenant_schema) do
      nil ->
        {:error, :not_found}

      a ->
        meta = a.metadata || %{}
        entry = %{"type" => type, "at" => DateTime.utc_now() |> DateTime.to_iso8601()}
        violations = (meta["violations"] || []) ++ [entry]
        count = length(violations)
        meta = meta |> Map.put("violations", violations) |> Map.put("violation_count", count)

        case a |> StudentPsychometricAssessment.changeset(%{metadata: meta}) |> Repo.update(prefix: tenant_schema) do
          {:ok, _} -> {:ok, count}
          {:error, _} = err -> err
        end
    end
  end

  @doc """
  Store response-validity stats for the completed assessment. `validity` is a
  map with "straight_lining_pct", "median_ms" and "n" — used to flag careless
  responding (the real integrity risk for a personality test).
  """
  def record_validity(session_id, validity, tenant_schema) do
    case get_assessment_by_session(session_id, tenant_schema) do
      nil ->
        {:error, :not_found}

      a ->
        meta = Map.put(a.metadata || %{}, "validity", validity)
        a |> StudentPsychometricAssessment.changeset(%{metadata: meta}) |> Repo.update(prefix: tenant_schema)
    end
  end

  @doc "Readable integrity flags (proctoring + response validity) for the admin panel."
  def student_integrity_flags(student_id, prefix) do
    StudentPsychometricAssessment
    |> where(student_id: ^student_id)
    |> Repo.all(prefix: prefix)
    |> Enum.flat_map(fn a -> psychometric_flags(a.metadata || %{}) end)
    |> Enum.uniq()
  end

  defp psychometric_flags(meta) do
    proctor =
      case meta["violation_count"] || 0 do
        c when c >= 2 -> ["Psychometric — proctoring: #{c} focus losses"]
        _ -> []
      end

    validity = meta["validity"] || %{}
    sl = validity["straight_lining_pct"]
    med = validity["median_ms"]

    sl_flag =
      if is_number(sl) and sl >= 0.85,
        do: ["Psychometric — possible straight-lining (#{round(sl * 100)}% identical)"],
        else: []

    fast_flag =
      if is_number(med) and med > 0 and med < 2000,
        do: ["Psychometric — very rapid answers (median #{Float.round(med / 1000, 1)}s)"],
        else: []

    proctor ++ sl_flag ++ fast_flag
  end

  def get_latest_assessment(student_id, tenant_schema) do
    from(a in StudentPsychometricAssessment,
      where: a.student_id == ^student_id,
      order_by: [desc: a.attempt_number],
      limit: 1
    )
    |> Repo.one(prefix: tenant_schema)
  end

  def list_student_assessments(student_id, tenant_schema) do
    from(a in StudentPsychometricAssessment,
      where: a.student_id == ^student_id,
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all(prefix: tenant_schema)
  end

  def assessment_completed?(student_id, tenant_schema) do
    from(a in StudentPsychometricAssessment,
      where: a.student_id == ^student_id and a.status == "completed",
      select: count(a.id)
    )
    |> Repo.one(prefix: tenant_schema)
    |> Kernel.>(0)
  end

  @doc """
  Reset a session — wipes an *incomplete* (non-completed) session so the
  student can start over. A genuinely completed assessment is preserved and
  never deleted; resetting in that case is a no-op so existing results stay
  intact.
  """
  def reset_assessment(student_id, tenant_schema) do
    case get_latest_assessment(student_id, tenant_schema) do
      nil ->
        :ok

      %{status: "completed"} ->
        :ok

      assessment ->
        Repo.delete(assessment, prefix: tenant_schema)
    end
  end
end
