defmodule VyaasaCampusWeb.Student.MiniProject.MiniProjectV4Live do
  @moduledoc """
  V4 viva-driven Domain Mini Project.

  Flow: intro → scenario (pick 1 of 2) → submission (upload, timed) →
  viva (12 metric-tagged, timed questions) → completed (fusion feedback).

  Scoring is deterministic (`AI.MiniProject.Scoring`); AI orchestration is in
  `AI.MiniProject.EngineV4`; persistence in `Contexts.MiniProjectV4`.
  """
  use VyaasaCampusWeb, :live_view

  require Logger

  alias VyaasaCampus.Contexts.{Tenants, StudentAts, MiniProjectV4}
  alias VyaasaCampus.AI.MiniProject.{EngineV4, Metrics}
  alias VyaasaCampus.AI.MiniProjectFileExtractor

  import VyaasaCampusWeb.Components.UI

  @violation_limit 3
  @accept ~w(.pdf .docx .doc .pptx .zip .txt .csv .json)

  # ── Mount ───────────────────────────────────────────────────────────────────

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    tenant_schema = if tenant, do: tenant.schema_name, else: nil
    current_user = socket.assigns[:current_user]

    cond do
      is_nil(current_user) ->
        {:ok, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}

      is_nil(tenant_schema) ->
        {:ok, socket |> put_flash(:error, "College not found.") |> assign(base_assigns(tenant_alias, tenant, nil))}

      true ->
        # Opik filter labels for every trace this LiveView (and its Tasks) emits.
        if connected?(socket),
          do: VyaasaCampus.AI.Tracing.put_metadata(%{student_id: current_user.id, module: "mini_project", tenant: tenant_schema})

        v4_profile = build_v4_profile(current_user, tenant_schema)
        session = MiniProjectV4.get_active_session(current_user.id, tenant_schema)

        socket =
          socket
          |> assign(base_assigns(tenant_alias, tenant, tenant_schema))
          |> assign(:current_user, current_user)
          |> assign(:v4_profile, v4_profile)
          |> assign(:session, session)
          |> assign(:phase, if(session, do: session.phase, else: "intro"))
          |> assign(:loading, nil)
          |> assign(:error, nil)
          |> assign(:error_title, "Something went wrong")
          |> assign(:last_action, nil)
          |> assign(:violation_count, 0)
          |> assign(:viva_index, 0)
          |> assign(:viva_answer, "")
          |> assign(:viva_deadline, nil)
          |> allow_upload(:deliverable, accept: @accept, max_entries: 5, max_file_size: 20 * 1024 * 1024)

        {:ok, socket}
    end
  end

  defp base_assigns(tenant_alias, tenant, tenant_schema) do
    %{
      tenant_alias: tenant_alias,
      tenant_schema: tenant_schema,
      tenant_id: tenant && tenant.id,
      tenant_name: if(tenant, do: tenant.full_name, else: tenant_alias),
      current_scope: :student,
      page_title: "Domain Mini Project"
    }
  end

  # Build the V4 profile map from the student's ATS data (no extra LLM call).
  defp build_v4_profile(user, prefix) do
    ats = StudentAts.get_by_student_id(user.id, prefix)

    # StudentAtsPhase stores parsed résumé data in typed columns (skills, projects,
    # …) — there is no groq_data field. Read the real columns defensively.
    skills =
      case ats && ats.skills do
        %{"technical_skills" => t} when is_list(t) and t != [] -> Enum.take(t, 6)
        _ -> []
      end

    projects =
      ((ats && ats.projects) || [])
      |> Enum.map(fn p -> p["Project_Name"] || p["project_name"] end)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.take(3)

    %{
      "candidate_name" => "#{user.first_name} #{user.last_name}",
      "job_title" => (ats && ats.preferred_role) || "Professional",
      "experience_level" => "junior",
      "domain_cluster" => "other",
      "top_skills" => Enum.take(skills, 6),
      "existing_projects" => projects,
      "jd_tools" => [],
      "submission_format_hint" => "document"
    }
  end

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("start_assessment", _p, socket) do
    profile = socket.assigns.v4_profile

    case MiniProjectV4.create_session(
           socket.assigns.current_user.id,
           socket.assigns.tenant_id,
           profile,
           profile["job_title"],
           socket.assigns.tenant_schema
         ) do
      {:ok, session} ->
        async(socket, fn -> {:scenarios_ready, EngineV4.generate_scenarios(profile)} end)

        {:noreply,
         socket
         |> assign(:session, session)
         |> assign(:phase, "scenario")
         |> assign(:loading, :scenarios)
         |> assign(:last_action, "start_assessment")}

      {:error, :attempt_limit_reached, _details} ->
        {:noreply,
         socket
         |> assign(:error_title, "Out of attempts")
         |> assign(
           :error,
           "You've used all your available mini project attempts. Please contact your college admin to request more."
         )
         |> assign(:last_action, "start_assessment")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:error, "Could not start the project. Please try again.")
         |> assign(:last_action, "start_assessment")}
    end
  end

  def handle_event("choose_scenario", %{"index" => idx}, socket) do
    index = String.to_integer(idx)

    case MiniProjectV4.choose_scenario(socket.assigns.session, index, socket.assigns.tenant_schema) do
      {:ok, session} ->
        {:noreply, socket |> assign(:session, session) |> assign(:phase, "submission") |> assign(:error, nil)}

      _ ->
        {:noreply, assign(socket, :error, "Could not select that scenario.")}
    end
  end

  def handle_event("validate_upload", _p, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :deliverable, ref)}

  def handle_event("submit_project", _p, socket) do
    artifacts =
      consume_uploaded_entries(socket, :deliverable, fn %{path: path}, entry ->
        binary = File.read!(path)

        content =
          case MiniProjectFileExtractor.extract(entry.client_name, binary) do
            {:ok, text} -> text
            _ -> ""
          end

        {:ok, %{"filename" => entry.client_name, "content" => content, "extract_ok" => content != ""}}
      end)

    if artifacts == [] do
      {:noreply, assign(socket, :error, "Please upload at least one deliverable file.")}
    else
      session = socket.assigns.session
      prefix = socket.assigns.tenant_schema
      async(socket, fn -> {:submission_processed, MiniProjectV4.process_submission(session, artifacts, prefix)} end)

      {:noreply,
       socket
       |> assign(:loading, :submission)
       |> assign(:error, nil)
       |> assign(:last_action, "submit_project")}
    end
  end

  def handle_event("update_viva_answer", %{"value" => v}, socket),
    do: {:noreply, assign(socket, :viva_answer, v)}

  def handle_event("submit_viva_answer", _p, socket) do
    answer = String.trim(socket.assigns.viva_answer || "")

    if answer == "" do
      {:noreply, assign(socket, :error, "Please type your answer before submitting.")}
    else
      {:noreply,
       socket
       |> assign(:error, nil)
       |> assign(:last_action, "submit_viva_answer")
       |> advance_viva()}
    end
  end

  def handle_event("integrity_violation", %{"type" => type}, socket) do
    if socket.assigns.phase in ["scenario", "submission", "viva"] do
      count = socket.assigns.violation_count + 1

      if count >= @violation_limit do
        {:noreply,
         socket
         |> put_flash(:error, "Your assessment was closed after #{@violation_limit} full-screen exits / tab switches.")
         |> redirect(to: ~p"/student/#{socket.assigns.tenant_alias}/dashboard")}
      else
        {:noreply,
         socket
         |> assign(:violation_count, count)
         |> put_flash(:error, "Warning #{count}/#{@violation_limit}: stay in full screen (#{type}).")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("logout", _p, socket),
    do: {:noreply, redirect(socket, to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}

  def handle_event("back_to_dashboard", _p, socket),
    do: {:noreply, redirect(socket, to: "/student/#{socket.assigns.tenant_alias}/dashboard")}

  # ── Async replies ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:scenarios_ready, {:ok, raw}}, socket) do
    case MiniProjectV4.save_scenarios(socket.assigns.session, raw, socket.assigns.tenant_schema) do
      {:ok, session} -> {:noreply, socket |> assign(:session, session) |> assign(:loading, nil)}
      _ -> {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Could not generate scenarios. Please retry.")}
    end
  end

  def handle_info({:scenarios_ready, _err}, socket),
    do: {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Scenario generation failed. Please retry.")}

  def handle_info({:submission_processed, {:ok, session}}, socket) do
    {:noreply,
     socket
     |> assign(:session, session)
     |> assign(:phase, "viva")
     |> assign(:loading, nil)
     |> assign(:viva_index, 0)
     |> assign(:viva_answer, "")
     |> start_viva_timer(session, 0)}
  end

  def handle_info({:submission_processed, _err}, socket),
    do:
      {:noreply,
       socket |> assign(:loading, nil) |> assign(:error, "Could not process your submission. Please try again.")}

  def handle_info({:finalized, {:ok, session}}, socket),
    do: {:noreply, socket |> assign(:session, session) |> assign(:phase, "completed") |> assign(:loading, nil)}

  def handle_info({:finalized, _err}, socket),
    do: {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Could not finalize scoring. Please try again.")}

  def handle_info({:viva_time_up, index}, socket) do
    if socket.assigns.phase == "viva" and socket.assigns.viva_index == index do
      {:noreply, advance_viva(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Viva progression ─────────────────────────────────────────────────────────

  defp advance_viva(socket) do
    session = socket.assigns.session
    prefix = socket.assigns.tenant_schema
    index = socket.assigns.viva_index
    questions = session.viva_questions
    question = Enum.at(questions, index)

    answer = String.trim(socket.assigns.viva_answer || "")

    session =
      case question && MiniProjectV4.record_answer(session, question["id"], answer, nil, prefix) do
        {:ok, s} -> s
        _ -> session
      end

    next = index + 1

    if next >= length(questions) do
      # All answered — finalize (2 LLM calls) in the background.
      async(socket, fn -> {:finalized, MiniProjectV4.finalize(session, prefix)} end)
      socket |> assign(:session, session) |> assign(:loading, :finalizing)
    else
      socket
      |> assign(:session, session)
      |> assign(:viva_index, next)
      |> assign(:viva_answer, "")
      |> start_viva_timer(session, next)
    end
  end

  # Server-side per-question timer: auto-advance when the budget elapses.
  defp start_viva_timer(socket, session, index) do
    case Enum.at(session.viva_questions, index) do
      %{"time_seconds" => secs} when is_integer(secs) ->
        Process.send_after(self(), {:viva_time_up, index}, secs * 1000)
        assign(socket, :viva_deadline, System.system_time(:second) + secs)

      _ ->
        assign(socket, :viva_deadline, nil)
    end
  end

  # Run `fun` in a task and send its result back to this LiveView.
  defp async(socket, fun) do
    lv = self()
    _ = socket
    Task.Supervisor.start_child(VyaasaCampus.TaskSupervisor, fn -> send(lv, fun.()) end)
  end

  # ── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :require_fullscreen, assigns.phase in ["scenario", "submission", "viva"])

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="mpv4"
        phx-hook="AssessmentIntegrity"
        data-require-fullscreen={to_string(@require_fullscreen)}
        class="max-w-4xl mx-auto px-4 py-8"
      >
        <div
          :if={@require_fullscreen}
          id="fullscreen-gate"
          phx-update="ignore"
          class="fixed inset-0 z-[100] flex items-center justify-center bg-slate-900/95 text-center"
        >
          <div class="p-8">
            <p class="text-white text-lg mb-4">This assessment must run in full screen.</p>
            <button id="enter-fullscreen-btn" class="px-6 py-3 bg-orange-500 text-white rounded-lg font-semibold">Enter full screen</button>
            <div class="mt-4">
              <.link navigate={~p"/student/#{@tenant_alias}/dashboard"} data-confirm="Leave the assessment?" class="text-slate-300 text-sm underline">Exit assessment</.link>
            </div>
          </div>
        </div>

        <h1 class="text-2xl font-bold text-slate-800 mb-1">Domain Mini Project</h1>
        <p class="text-sm text-slate-500 mb-6">Viva-defended project assessment</p>

        <.error_card
          :if={@error}
          title={@error_title}
          error_message={@error}
          retry_event={@last_action || "start_assessment"}
          class="mb-4"
        />

        <%= case @phase do %>
          <% "intro" -> %>{intro(assigns)}
          <% "scenario" -> %>{scenario_step(assigns)}
          <% "submission" -> %>{submission_step(assigns)}
          <% "viva" -> %>{viva_step(assigns)}
          <% "completed" -> %>{feedback_step(assigns)}
          <% _ -> %>{intro(assigns)}
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp intro(assigns) do
    ~H"""
    <div class="rounded-xl border border-slate-200 bg-white p-6">
      <p class="text-slate-600 mb-4">
        You'll pick a realistic workplace scenario, build the deliverable, upload it, then defend it in a
        <strong>12-question viva</strong>. Your score reflects what you can <em>defend</em>, not just what you submit.
      </p>
      <div class="rounded-lg bg-slate-50 p-4 mb-4 text-sm text-slate-600">
        <p class="font-semibold text-slate-700 mb-1">Role: {@v4_profile["job_title"]}</p>
        <p :if={@v4_profile["top_skills"] != []}>Skills: {Enum.join(@v4_profile["top_skills"], ", ")}</p>
      </div>
      <p class="text-xs text-slate-400 mb-4">Once you start, stay in full screen. Leaving 3 times ends the assessment.</p>
      <button :if={!@error} phx-click="start_assessment" data-enter-fullscreen class="px-6 py-3 bg-orange-500 text-white rounded-lg font-semibold hover:bg-orange-600">
        Start Assessment
      </button>
    </div>
    """
  end

  defp scenario_step(assigns) do
    ~H"""
    <div :if={@loading == :scenarios} class="text-center py-12 text-slate-500">Generating your scenarios…</div>
    <div :if={@loading != :scenarios} class="grid gap-4 md:grid-cols-2">
      <div :for={{scn, idx} <- Enum.with_index(@session.scenario_candidates)} class="rounded-xl border border-slate-200 bg-white p-5 flex flex-col">
        <span class="text-[10px] font-semibold uppercase tracking-wide text-orange-600 mb-1">Option {["A", "B"] |> Enum.at(idx)}</span>
        <h3 class="font-semibold text-slate-800 mb-2">{scn["title"]}</h3>
        <p class="text-sm text-slate-600 flex-1 whitespace-pre-line">{String.slice(scn["scenario_text"] || "", 0, 600)}…</p>
        <p class="text-xs text-slate-400 mt-3">Est. {scn["estimated_minutes"] || 75} min</p>
        <button phx-click="choose_scenario" phx-value-index={idx} class="mt-3 px-4 py-2 bg-orange-500 text-white text-sm rounded-lg hover:bg-orange-600">Choose this</button>
      </div>
    </div>
    """
  end

  defp submission_step(assigns) do
    ~H"""
    <div :if={@loading == :submission} class="text-center py-12 text-slate-500">Reading your submission and preparing your viva…</div>
    <div :if={@loading != :submission} class="rounded-xl border border-slate-200 bg-white p-6">
      <h3 class="font-semibold text-slate-800 mb-2">{(@session.chosen_scenario || %{})["title"]}</h3>
      <p class="text-sm text-slate-600 whitespace-pre-line mb-4">{(@session.chosen_scenario || %{})["scenario_text"]}</p>
      <form phx-submit="submit_project" phx-change="validate_upload">
        <div class="rounded-lg border-2 border-dashed border-slate-300 p-6 text-center mb-4">
          <.live_file_input upload={@uploads.deliverable} class="text-sm" />
          <p class="text-xs text-slate-400 mt-2">PDF, DOCX, PPTX, ZIP, CSV, TXT — up to 5 files, 20 MB each.</p>
        </div>
        <div :for={entry <- @uploads.deliverable.entries} class="flex items-center justify-between text-sm py-1">
          <span>{entry.client_name}</span>
          <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="text-red-500 text-xs">remove</button>
        </div>
        <button type="submit" class="mt-4 px-6 py-3 bg-orange-500 text-white rounded-lg font-semibold hover:bg-orange-600">Submit & start viva</button>
      </form>
    </div>
    """
  end

  defp viva_step(assigns) do
    assigns =
      assigns
      |> assign(:question, Enum.at(assigns.session.viva_questions, assigns.viva_index))
      |> assign(:total, length(assigns.session.viva_questions))

    ~H"""
    <div :if={@loading == :finalizing} class="text-center py-12 text-slate-500">Scoring your defence…</div>
    <div :if={@loading != :finalizing && @question} class="rounded-xl border border-slate-200 bg-white p-6">
      <div class="flex items-center justify-between mb-3">
        <span class="text-xs font-semibold text-slate-500">Question {@viva_index + 1} of {@total}</span>
        <div class="flex items-center gap-2">
          <div
            id={"viva-timer-#{@viva_index}"}
            phx-hook="CountdownTimer"
            data-seconds={@question["time_seconds"]}
            data-total={@question["time_seconds"]}
            data-active="true"
            class="text-xs font-semibold text-slate-500 tabular-nums"
          >
            <span data-countdown-display>{format_secs(@question["time_seconds"])}</span> left
          </div>
          <span class="text-[10px] font-semibold uppercase tracking-wide px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">
            {Metrics.name(@question["metric"])}
          </span>
        </div>
      </div>
      <p class="text-slate-800 font-medium mb-4">{@question["question"]}</p>
      <form phx-submit="submit_viva_answer">
        <textarea
          name="value"
          phx-change="update_viva_answer"
          phx-debounce="300"
          rows="6"
          class="w-full rounded-lg border border-slate-300 p-3 text-sm"
          placeholder="Explain your actual decision and reasoning…"
        >{@viva_answer}</textarea>
        <div class="flex items-center justify-between mt-3">
          <span class="text-xs text-slate-400">Answer in your own words — specificity beats fluency.</span>
          <button type="submit" class="px-5 py-2 bg-orange-500 text-white text-sm rounded-lg hover:bg-orange-600">
            {if @viva_index + 1 >= @total, do: "Finish viva", else: "Next question"}
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp feedback_step(assigns) do
    assigns = assign(assigns, :s, assigns.session)

    ~H"""
    <div class="rounded-xl border border-slate-200 bg-white p-6">
      <div class="flex items-baseline gap-3 mb-2">
        <span class="text-4xl font-bold text-slate-800">{@s.final_score}</span>
        <span class="text-slate-400">/100</span>
        <span class="ml-2 px-3 py-1 rounded-full bg-orange-50 text-orange-700 text-sm font-semibold">{@s.grade_band}</span>
      </div>
      <p :if={@s.gate_note not in [nil, ""]} class="text-sm text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 mb-4">{@s.gate_note}</p>
      <p class="text-sm text-slate-500 mb-4">Authenticity: <strong>{@s.authenticity}</strong></p>

      <h4 class="font-semibold text-slate-700 mb-2 text-sm">Per-dimension (ceiling → viva → final)</h4>
      <div class="space-y-1 mb-5">
        <div :for={m <- Metrics.keys()} class="flex items-center justify-between text-sm border-b border-slate-100 py-1">
          <span class="text-slate-600">{Metrics.name(m)}</span>
          <span class="text-slate-500 tabular-nums">
            {get_in(@s.per_metric, [m, "artifact_ceiling"])} → {get_in(@s.per_metric, [m, "viva_score"])} → <strong>{get_in(@s.per_metric, [m, "fused"])}</strong>
          </span>
        </div>
      </div>

      <p :if={@s.feedback["overall_sentence"]} class="text-slate-700 mb-5">{@s.feedback["overall_sentence"]}</p>

      <div :if={is_list(@s.feedback["strengths"]) && @s.feedback["strengths"] != []} class="mb-5">
        <h4 class="font-semibold text-slate-700 mb-2 text-sm">Strengths</h4>
        <div :for={st <- @s.feedback["strengths"]} class="rounded-lg bg-green-50 border-l-4 border-green-500 px-3 py-2 mb-2">
          <p class="text-sm font-medium text-green-800">{st["title"]}</p>
          <p :if={st["evidence"]} class="text-xs text-green-700 mt-0.5">{st["evidence"]}</p>
        </div>
      </div>

      <div :if={is_map(@s.feedback["primary_gap"]) && @s.feedback["primary_gap"]["gap_sentence"]} class="mb-5">
        <h4 class="font-semibold text-slate-700 mb-2 text-sm">Primary gap</h4>
        <div class="rounded-lg bg-red-50 border-l-4 border-red-500 px-3 py-2">
          <p class="text-sm font-medium text-red-800">{@s.feedback["primary_gap"]["gap_sentence"]}</p>
          <p :if={@s.feedback["primary_gap"]["what_happened"]} class="text-xs text-red-700 mt-1">{@s.feedback["primary_gap"]["what_happened"]}</p>
          <p :if={@s.feedback["primary_gap"]["positive_flip"]} class="text-xs text-slate-600 mt-1">{@s.feedback["primary_gap"]["positive_flip"]}</p>
        </div>
      </div>

      <div :if={is_list(@s.feedback["actions"]) && @s.feedback["actions"] != []} class="mb-6">
        <h4 class="font-semibold text-slate-700 mb-2 text-sm">What to do next</h4>
        <div :for={a <- @s.feedback["actions"]} class="rounded-lg bg-orange-50 border-l-4 border-orange-400 px-3 py-2 mb-2">
          <p class="text-sm font-medium text-orange-800">
            <span class="text-[10px] uppercase tracking-wide mr-2 text-orange-500">{a["priority"]}</span>{a["title"]}
          </p>
          <p :if={a["how"]} class="text-xs text-orange-700 mt-0.5">{a["how"]}</p>
        </div>
      </div>

      <.link navigate={~p"/student/#{@tenant_alias}/dashboard"} class="inline-block px-5 py-2 bg-slate-800 text-white text-sm rounded-lg">Back to dashboard</.link>
    </div>
    """
  end

  # mm:ss for a seconds budget.
  defp format_secs(secs) when is_integer(secs),
    do: "#{div(secs, 60)}:#{String.pad_leading(Integer.to_string(rem(secs, 60)), 2, "0")}"

  defp format_secs(_), do: "4:00"

  # Closing the tab / navigating away mid-attempt must not leave the session
  # stuck non-terminal forever. Enqueues the same finalize job the
  # abandonment sweep uses, so both share one completion path
  # (MiniProjectV4.force_complete/2). Guarded on connected?/1 — the
  # disconnected static-render pass would otherwise fire this on every page
  # load.
  @impl true
  def terminate(_reason, socket) do
    with true <- connected?(socket),
         %{id: session_id} <- socket.assigns[:session],
         tenant_schema when is_binary(tenant_schema) <- socket.assigns[:tenant_schema] do
      VyaasaCampus.Jobs.AssessmentFinalizer.enqueue("mini_project_v4", session_id, tenant_schema)
    end

    :ok
  end
end
