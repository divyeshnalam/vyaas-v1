defmodule VyaasaCampus.Contexts.MiniProject do
  @moduledoc """
  Context for Domain Mini Project sessions. Handles all Ecto operations;
  phase-transition logic lives in the engine.
  """

  import Ecto.Query, warn: false
  require Logger

  alias VyaasaCampus.AI.MiniProjectEngine
  alias VyaasaCampus.Contexts.AI8
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.StudentMiniProjectSession, as: Session

  @viva_total 4
  @discovery_max 5
  @submission_seconds 86_400

  # ── Queries ───────────────────────────────────────────────────────────────

  def get_session(id, prefix), do: Repo.get(Session, id, prefix: prefix)

  @doc "Persist the authenticity/forensics report to the session's metadata."
  def store_authenticity(%Session{} = session, report, prefix) do
    meta = Map.put(session.metadata || %{}, "authenticity", report)
    session |> Ecto.Changeset.change(metadata: meta) |> Repo.update(prefix: prefix)
  end

  @doc "Fold the viva authorship signal into the session's stored authenticity report."
  def merge_viva_authorship(%Session{} = session, prefix) do
    fresh = get_session(session.id, prefix)
    report = (fresh && fresh.metadata || %{})["authenticity"]

    with true <- is_map(report),
         {:flag, penalty, text} <-
           VyaasaCampus.AI.MiniProjectForensics.viva_authorship_flag(fresh.viva_turns) do
      updated = VyaasaCampus.AI.MiniProjectForensics.add_report_flag(report, penalty, text)
      store_authenticity(fresh, updated, prefix)
    else
      _ -> {:ok, session}
    end
  end

  @doc "Readable authenticity flags across a student's mini-project sessions, for the admin panel."
  def student_integrity_flags(student_id, prefix) do
    list_sessions(student_id, prefix)
    |> Enum.flat_map(fn s ->
      VyaasaCampus.AI.MiniProjectForensics.admin_flags((s.metadata || %{})["authenticity"] || %{})
    end)
    |> Enum.uniq()
  end

  def get_active_session(student_id, prefix) do
    Session
    |> where(student_id: ^student_id)
    |> where([s], s.phase != "completed")
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one(prefix: prefix)
  end

  def get_latest_session(student_id, prefix) do
    Session
    |> where(student_id: ^student_id)
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one(prefix: prefix)
  end

  @doc "Most recent completed session for a student (their latest result), if any."
  def get_latest_completed_session(student_id, prefix) do
    Session
    |> where(student_id: ^student_id)
    |> where([s], s.phase == "completed")
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one(prefix: prefix)
  end

  def list_sessions(student_id, prefix) do
    Session
    |> where(student_id: ^student_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all(prefix: prefix)
  end

  def attempt_count(student_id, prefix) do
    Session
    |> where(student_id: ^student_id)
    |> Repo.aggregate(:count, prefix: prefix)
  end

  # ── Phase 1 — create session & store generated scenarios ──────────────────

  def create_session(attrs, prefix) do
    student_id = attrs[:student_id] || attrs["student_id"]

    with :ok <- VyaasaCampus.Contexts.AttemptGuard.check(student_id, :mini_project, prefix) do
      do_create_session(attrs, prefix)
    end
  end

  defp do_create_session(attrs, prefix) do
    token = generate_token()
    attempt = (attempt_count(attrs[:student_id] || attrs["student_id"], prefix) || 0) + 1

    full_attrs = Map.merge(attrs, %{session_token: token, attempt_number: attempt})

    case Session.create_changeset(full_attrs) |> Repo.insert(prefix: prefix) do
      {:ok, session} ->
        Logger.info("Mini project session created: #{session.session_token}")
        {:ok, session}

      {:error, changeset} ->
        Logger.error("Failed to create mini project session: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def store_scenarios(session, candidates, prefix) do
    do_update(session, %{scenario_candidates: candidates}, prefix)
  end

  # ── Phase 1 → 2 — choose scenario ────────────────────────────────────────

  def choose_scenario(session, scenario, prefix) do
    do_update(session, %{
      chosen_scenario: scenario,
      phase: "discovery"
    }, prefix)
  end

  # ── Phase 2 — discovery messages ─────────────────────────────────────────

  def can_ask_discovery?(%Session{} = s),
    do: Session.questions_asked(s) < @discovery_max

  def add_discovery_message(session, student_question, ai_reply, revealed_keys, prefix) do
    student_msg = %{
      "sender" => "student",
      "content" => student_question,
      "inserted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    ai_msg = %{
      "sender" => "stakeholder",
      "role" => ai_reply["role"],
      "content" => ai_reply["content"],
      "quality" => ai_reply["quality"],
      "inserted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    existing = session.discovery_messages || []
    existing_uncovered = session.uncovered_facts || []
    new_uncovered = Enum.uniq(existing_uncovered ++ revealed_keys)

    do_update(session, %{
      discovery_messages: existing ++ [student_msg, ai_msg],
      uncovered_facts: new_uncovered
    }, prefix)
  end

  # ── Phase 2 → 3 — finish discovery, store recap + brief ──────────────────

  def finish_discovery(session, recap, brief_markdown, prefix, submission_type \\ "files") do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    deadline = DateTime.add(now, @submission_seconds, :second)

    do_update(session, %{
      discovery_recap: recap,
      brief_markdown: brief_markdown,
      brief_generated_at: now,
      submission_deadline: deadline,
      submission_type: submission_type,
      phase: "implementation"
    }, prefix)
  end

  @doc """
  Ends a session before natural completion — either the 24h submission
  deadline passed (existing call sites: `finalize_submission`'s overdue
  check, the connected `:deadline_reached` timer) or the session was
  force-completed after being abandoned (`force_complete/2` below, via a
  closed tab or the safety-net sweep).

  Reuses the same evaluation function a normal reflection-submit uses
  (`MiniProjectEngine.evaluate/5`) whenever there's a real defended viva
  answer to score — the engine's own viva-defense gate already forces
  `final_score` to 0 when viva quality is <= 2, so a session that never got
  past discovery/implementation naturally lands at 0 without a special case
  here. Skips the LLM entirely (6 rubric passes) when there are zero
  answered viva turns, since the gate guarantees 0 regardless — there is
  nothing yet to defend, so nothing worth spending the LLM calls on.
  """
  def expire_session(session, prefix) do
    # Opik: scope the session's thread id around the (unchanged) body so the
    # evaluation LLM calls join the session thread. Result passes through as-is.
    VyaasaCampus.AI.Tracing.with_thread_id(session && session.id, fn ->
      do_expire_session(session, prefix)
    end)
  end

  defp do_expire_session(session, prefix) do
    answered_viva = Enum.count(session.viva_turns || [], &is_binary(&1["answer"]))

    if answered_viva > 0 do
      eval =
        MiniProjectEngine.evaluate(
          session.chosen_scenario,
          session.artifacts || [],
          session.discovery_messages || [],
          session.viva_turns || [],
          session.reflection || %{}
        )

      complete_session(session, eval, prefix, %{time_expired: true})
    else
      # Routed through complete_session/4 too (not a separate do_update) so
      # this gets the exact same side effects a real evaluation would —
      # AI8 publish, report email — rather than a silently different path
      # for the zero-content case.
      zero_eval = %{
        "indexes" => [],
        "criteria" => [],
        "final_score" => 0,
        "grade_band" => "Needs Improvement",
        "strengths" => [],
        "improvements" => [],
        "report_markdown" => "This mini project session expired before a viva defense was completed."
      }

      complete_session(session, zero_eval, prefix, %{time_expired: true})
    end
  end

  @doc """
  Force-completes a session abandoned mid-attempt (tab closed / crashed).
  Idempotent: a session already at phase "completed" is left untouched.
  Just an idempotency-guarded entry point into the same `expire_session/2`
  every deadline-based expiry already uses — not a second completion path.
  """
  def force_complete(session_id, prefix) do
    case get_session(session_id, prefix) do
      nil -> {:error, :not_found}
      %{phase: "completed"} -> {:ok, :already_terminal}

      session ->
        # Opik filter labels for the evaluation trace (runs in the finalizer job, no LiveView).
        VyaasaCampus.AI.Tracing.put_metadata(%{student_id: session.student_id, module: "mini_project", tenant: prefix})
        expire_session(session, prefix)
    end
  end

  # ── Phase 3 → 4 — proceed to submission ──────────────────────────────────

  def proceed_to_submission(session, prefix),
    do: do_update(session, %{phase: "project_submission"}, prefix)

  # ── Phase 4 — file artifacts ──────────────────────────────────────────────

  def add_artifact(session, artifact_map, prefix) do
    existing = session.artifacts || []
    do_update(session, %{artifacts: existing ++ [artifact_map]}, prefix)
  end

  def remove_artifact(session, filename, prefix) do
    updated = Enum.reject(session.artifacts || [], &(&1["filename"] == filename))
    do_update(session, %{artifacts: updated}, prefix)
  end

  # ── Phase 4 → 5 — finalize submission, add first viva question ───────────

  def finalize_submission(session, first_viva_question, prefix) do
    turn = %{
      "index" => 0,
      "question" => first_viva_question["question"],
      "asked_because" => first_viva_question["asked_because"],
      "evidence" => first_viva_question["evidence"] || "",
      "answer" => nil,
      "answer_score" => nil,
      "answer_note" => nil,
      "answer_weak" => nil
    }
    do_update(session, %{phase: "viva", viva_turns: [turn]}, prefix)
  end

  # ── Phase 5 — viva answers ────────────────────────────────────────────────

  def answer_viva(session, answer_text, score_result, next_question, prefix) do
    turns = session.viva_turns || []
    pending_idx = Enum.find_index(turns, &is_nil(&1["answer"]))

    updated_turns =
      List.update_at(turns, pending_idx, fn t ->
        Map.merge(t, %{
          "answer" => answer_text,
          "answer_score" => score_result["score"],
          "answer_note" => score_result["note"],
          "answer_weak" => score_result["weak"]
        })
      end)

    answered_count = Enum.count(updated_turns, &is_binary(&1["answer"]))
    viva_complete = answered_count >= @viva_total

    {new_phase, final_turns} =
      if viva_complete do
        {"reflection", updated_turns}
      else
        new_turn = %{
          "index" => answered_count,
          "question" => next_question["question"],
          "asked_because" => next_question["asked_because"],
          "evidence" => next_question["evidence"] || "",
          "answer" => nil,
          "answer_score" => nil,
          "answer_note" => nil,
          "answer_weak" => nil
        }
        {"viva", updated_turns ++ [new_turn]}
      end

    result = do_update(session, %{phase: new_phase, viva_turns: final_turns}, prefix)
    {result, viva_complete}
  end

  # ── Phase 6 — reflection ──────────────────────────────────────────────────

  def save_reflection(session, reflection_map, prefix) do
    do_update(session, %{reflection: reflection_map}, prefix)
  end

  # ── Phase 6 → 7 — save evaluation, complete ──────────────────────────────

  def complete_session(session, eval_result, prefix, extra_attrs \\ %{}) do
    indexes = eval_result["indexes"] || []

    domain_idx = find_index_score(indexes, "domain_technical")
    collab_idx = find_index_score(indexes, "collaboration_teamwork")
    init_idx = find_index_score(indexes, "initiative_leadership")

    attrs =
      Map.merge(extra_attrs, %{
        criteria: eval_result["criteria"] || [],
        indexes: indexes,
        domain_index: domain_idx,
        collaboration_index: collab_idx,
        initiative_index: init_idx,
        final_score: eval_result["final_score"],
        grade_band: eval_result["grade_band"],
        strengths: eval_result["strengths"] || [],
        improvements: eval_result["improvements"] || [],
        report_markdown: eval_result["report_markdown"],
        phase: "completed",
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    do_update(session, attrs, prefix)
    |> case do
      {:ok, completed} = ok ->
        # Email the PDF report, mirroring the other assessments. Best-effort:
        # never let a mail/enqueue hiccup fail the completion.
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:mini_project, completed.id, prefix)
        publish_ai8(completed, prefix)
        ok

      other ->
        other
    end
  end

  # Moved here from the LiveView (previously only called from the connected,
  # live evaluation-ready handler) so every path that reaches
  # complete_session/4 — a normal finish, the pre-existing deadline expiry,
  # or force_complete/2 — publishes the same way. publish_evaluation/2
  # upserts on (student_id, module, attempt_number), so this is safe even if
  # something else also calls it for the same session.
  defp publish_ai8(%{final_score: nil}, _prefix), do: :ok

  defp publish_ai8(session, prefix) do
    AI8.publish_module(
      "mini_project",
      %{
        "domain_expertise" => session.domain_index || session.final_score,
        "collaboration" => session.collaboration_index || session.final_score,
        "leadership" => session.initiative_index || session.final_score
      },
      %{
        student_id: session.student_id,
        tenant_id: session.tenant_id,
        source_type: "mini_project_session",
        source_id: session.id
      },
      prefix
    )
  rescue
    e -> Logger.warning("AI8 publish failed for mini project: #{Exception.message(e)}")
  end

  # ── Admin queries ─────────────────────────────────────────────────────────

  def average_score(prefix) do
    Session
    |> where([s], s.phase == "completed")
    |> Repo.aggregate(:avg, :final_score, prefix: prefix)
  end

  def completion_count(prefix) do
    Session
    |> where([s], s.phase == "completed")
    |> Repo.aggregate(:count, prefix: prefix)
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp do_update(session, attrs, prefix) do
    case Session.update_changeset(session, attrs) |> Repo.update(prefix: prefix) do
      {:ok, updated} -> {:ok, updated}
      {:error, cs} ->
        Logger.error("Mini project update failed: #{inspect(cs.errors)}")
        {:error, cs}
    end
  end

  defp find_index_score(indexes, key) do
    case Enum.find(indexes, &(&1["key"] == key)) do
      %{"score" => s} -> s
      _ -> nil
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
