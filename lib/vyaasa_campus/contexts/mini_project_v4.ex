defmodule VyaasaCampus.Contexts.MiniProjectV4 do
  @moduledoc """
  Session lifecycle + scoring orchestration for the V4 viva-driven mini-project.

  The LiveView (a thin driver) calls these functions; all AI orchestration goes
  through `VyaasaCampus.AI.MiniProject.EngineV4` and all score math through
  `VyaasaCampus.AI.MiniProject.Scoring`.

  Flow: profile → scenario → submission → viva → feedback (completed).
  """

  import Ecto.Query, warn: false
  require Logger

  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.StudentMiniProjectSession, as: Session
  alias VyaasaCampus.AI.MiniProject.{EngineV4, Metrics}

  # ── Lookup ──────────────────────────────────────────────────────────────────

  def get_session(id, prefix), do: Repo.get(Session, id, prefix: prefix)

  @doc "The student's in-progress V4 session (not yet at feedback/completed), if any."
  def get_active_session(student_id, prefix) do
    Session
    |> where([s], s.student_id == ^student_id and s.engine_version == "v4")
    |> where([s], s.phase not in ["feedback", "completed"])
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one(prefix: prefix)
  end

  @doc "The student's most recent V4 session in any state."
  def get_latest_session(student_id, prefix) do
    Session
    |> where([s], s.student_id == ^student_id and s.engine_version == "v4")
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one(prefix: prefix)
  end

  defp attempt_count(student_id, prefix) do
    Session
    |> where([s], s.student_id == ^student_id and s.engine_version == "v4")
    |> Repo.aggregate(:count, prefix: prefix) || 0
  end

  # ── Create ──────────────────────────────────────────────────────────────────

  def create_session(student_id, tenant_id, profile, specialization, prefix) do
    with :ok <- VyaasaCampus.Contexts.AttemptGuard.check(student_id, :mini_project, tenant_id, prefix) do
      do_create_session(student_id, tenant_id, profile, specialization, prefix)
    end
  end

  defp do_create_session(student_id, tenant_id, profile, specialization, prefix) do
    attrs = %{
      student_id: student_id,
      tenant_id: tenant_id,
      session_token: generate_token(),
      attempt_number: attempt_count(student_id, prefix) + 1,
      profile: profile,
      specialization_name: specialization
    }

    Session.create_changeset_v4(attrs) |> Repo.insert(prefix: prefix)
  end

  # ── Step transitions ────────────────────────────────────────────────────────

  @doc "Store the generated scenario pair and move to the scenario-selection step."
  def save_scenarios(%Session{} = session, raw, prefix) do
    candidates = [raw["scenario_a"], raw["scenario_b"]] |> Enum.reject(&is_nil/1)
    do_update(session, %{scenario_candidates: candidates, phase: "scenario"}, prefix)
  end

  @doc "Pick scenario A (0) or B (1), set the deadline, and move to submission."
  def choose_scenario(%Session{} = session, index, prefix) when index in [0, 1] do
    scenario = Enum.at(session.scenario_candidates, index)

    if is_map(scenario) do
      est = scenario["estimated_minutes"] || 75
      deadline = DateTime.add(now(), (est + Metrics.project_grace_minutes()) * 60, :second)

      do_update(
        session,
        %{
          chosen_scenario: scenario,
          submission_deadline: deadline,
          brief_generated_at: now(),
          phase: "submission"
        },
        prefix
      )
    else
      {:error, :no_scenario}
    end
  end

  @doc """
  Persist the submitted artifacts, then (synchronously) generate the artifact
  ceilings and 12 viva questions and move to the viva step. Intended to run
  inside a Task from the LiveView.
  """
  def process_submission(%Session{} = session, artifacts, prefix) do
    summary = submission_summary(artifacts)
    scenario = session.chosen_scenario || %{}

    with {:ok, ceilings} <- EngineV4.artifact_ceilings(scenario, summary),
         {:ok, questions} <- EngineV4.viva_questions(scenario, summary),
         true <- questions != [] || {:error, :no_questions} do
      do_update(
        session,
        %{
          artifacts: artifacts,
          artifact_ceilings: ceilings,
          viva_questions: questions,
          phase: "viva"
        },
        prefix
      )
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :submission_failed}
    end
  end

  @doc "Record a viva answer (with elapsed seconds) against a question id."
  def record_answer(%Session{} = session, question_id, answer, elapsed_seconds, prefix) do
    updated =
      Enum.map(session.viva_questions, fn q ->
        if q["id"] == question_id do
          Map.merge(q, %{"answer" => answer, "elapsed_seconds" => elapsed_seconds})
        else
          q
        end
      end)

    do_update(session, %{viva_questions: updated}, prefix)
  end

  @doc "True once every viva question has an answer."
  def all_answered?(%Session{viva_questions: qs}),
    do: qs != [] and Enum.all?(qs, &is_binary(&1["answer"]))

  @doc """
  Score the viva answers, fuse them with the artifact ceilings, apply the
  authenticity gate + timing, generate feedback, and complete the session.
  Runs the two closing LLM calls; intended to run inside a Task.
  """
  def finalize(%Session{} = session, prefix) do
    summary = submission_summary(session.artifacts)
    scenario = session.chosen_scenario || %{}
    qa_pairs = Enum.filter(session.viva_questions, &is_binary(&1["answer"]))

    with {:ok, scored} <- EngineV4.score_viva_answers(scenario, summary, qa_pairs) do
      question_scores = List.wrap(scored["question_scores"]) |> Enum.filter(&is_map/1)
      contradiction = truthy?(scored["contradiction"])

      timing = timing_for(session)
      result = EngineV4.evaluate(session.artifact_ceilings, question_scores, contradiction, timing)

      feedback =
        case EngineV4.feedback(scenario, session.profile, result, qa_pairs) do
          {:ok, fb} -> fb
          _ -> %{}
        end

      updated =
        do_update(
          session,
          %{
            question_scores: question_scores,
            viva_metric_scores: viva_scores_map(result),
            per_metric: result["per_metric"],
            composite_raw: result["composite_raw"],
            final_score: result["final_score"],
            grade_band: result["band"],
            authenticity: result["authenticity"],
            gate_note: result["gate_note"],
            contradiction: contradiction,
            contradiction_detail: scored["contradiction_detail"],
            timing: result["timing"],
            feedback: feedback,
            phase: "completed",
            completed_at: now()
          },
          prefix
        )

      # Feed the mini-project score into the AI8 aggregate (best-effort).
      with {:ok, done} <- updated, do: publish_ai8(done, prefix)

      updated
    end
  end

  # Publish the mini-project result into the AI8 aggregate. mini_project's AI8
  # dimensions are domain_expertise / collaboration / leadership; V4 produces one
  # holistic final score, so all three carry it (the module's own weights then
  # roll them back to final_score). Never raises.
  defp publish_ai8(%Session{final_score: score} = session, prefix) when is_integer(score) do
    VyaasaCampus.Contexts.AI8.publish_module(
      "mini_project",
      %{"domain_expertise" => score, "collaboration" => score, "leadership" => score},
      %{
        student_id: session.student_id,
        tenant_id: session.tenant_id,
        source_type: "mini_project_session",
        source_id: session.id
      },
      prefix
    )
  rescue
    e -> Logger.warning("AI8 publish (mini_project v4) failed: #{Exception.message(e)}")
  end

  defp publish_ai8(_session, _prefix), do: :ok

  @terminal_phases ~w(completed)

  @doc """
  Force-completes a session abandoned mid-attempt (tab closed / crashed, or
  the submission_deadline set by choose_scenario/3 passed with nobody
  reading it — this is what finally wires that field up: the safety-net
  sweep treats a non-terminal V4 session past its deadline the same as a
  closed tab, both routing through here).

  Any answered viva question exists -> reuses `finalize/2` directly (the
  same two closing LLM calls a normal viva completion runs), so a partial
  attempt still gets a real fused score from whatever was answered.

  Zero answered viva questions -> short-circuits to a direct terminal write
  with the lowest band ("Not ready") and a zero score — nothing was
  defended, so there's nothing for `finalize/2`'s LLM calls to score.

  Idempotent: a session already at phase "completed" is left untouched.
  """
  def force_complete(session_id, prefix) do
    case get_session(session_id, prefix) do
      nil ->
        {:error, :not_found}

      %{phase: phase} when phase in @terminal_phases ->
        {:ok, :already_terminal}

      %{viva_questions: questions} = session ->
        if Enum.any?(questions || [], &is_binary(&1["answer"])) do
          finalize(session, prefix)
        else
          abandon_without_answers(session, prefix)
        end
    end
  end

  defp abandon_without_answers(session, prefix) do
    updated =
      do_update(
        session,
        %{
          final_score: 0,
          grade_band: "Not ready",
          gate_note: "Abandoned before any viva question was answered.",
          time_expired: true,
          phase: "completed",
          completed_at: now()
        },
        prefix
      )

    with {:ok, done} <- updated, do: publish_ai8(done, prefix)

    updated
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  @doc "Concatenate readable artifact text into one summary blob for the LLM."
  def submission_summary(artifacts) when is_list(artifacts) do
    artifacts
    |> Enum.map_join("\n\n---\n\n", fn a ->
      name = a["filename"] || a["name"] || "file"
      body = a["content"] || a["text"] || ""
      "FILE: #{name}\n#{body}"
    end)
    |> String.slice(0, 12_000)
  end

  def submission_summary(_), do: ""

  # Per-metric viva score map extracted from the fused result (for display).
  defp viva_scores_map(result) do
    (result["per_metric"] || %{})
    |> Map.new(fn {m, d} -> {m, d["viva_score"]} end)
  end

  # fast | over | on_time based on elapsed vs the scenario estimate + grace.
  defp timing_for(%Session{brief_generated_at: nil}), do: nil

  defp timing_for(%Session{} = session) do
    est = (session.chosen_scenario || %{})["estimated_minutes"] || 75
    elapsed_min = max(0, div(DateTime.diff(now(), session.brief_generated_at, :second), 60))

    flag =
      cond do
        elapsed_min < est * Metrics.fast_submit_fraction() -> "fast"
        elapsed_min > est + Metrics.project_grace_minutes() -> "over"
        true -> "on_time"
      end

    %{flag: flag, elapsed_min: elapsed_min, estimate_min: est}
  end

  defp do_update(%Session{} = session, attrs, prefix) do
    session |> Session.update_changeset(attrs) |> Repo.update(prefix: prefix)
  end

  # Groq may return the contradiction flag as a bool or a string.
  defp truthy?(true), do: true
  defp truthy?(v) when is_binary(v), do: String.downcase(String.trim(v)) in ~w(true yes 1)
  defp truthy?(_), do: false

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp generate_token, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
