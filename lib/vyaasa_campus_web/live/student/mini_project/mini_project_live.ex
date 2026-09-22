defmodule VyaasaCampusWeb.Student.MiniProject.MiniProjectLive do
  @moduledoc """
  LiveView for the Domain Mini Project — a 7-phase AI-supervised internship simulation.
  """

  use VyaasaCampusWeb, :live_view

  require Logger

  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Contexts.StudentRankings
  alias VyaasaCampus.Contexts.MiniProject
  alias VyaasaCampus.Contexts.StudentAts
  alias VyaasaCampus.AI.MiniProjectEngine
  alias VyaasaCampus.AI.MiniProjectFileExtractor
  alias VyaasaCampus.AI.MiniProjectForensics
  alias VyaasaCampus.Schema.Students.StudentMiniProjectSession, as: MPSession
  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Student.MiniProject.Components

  # ── Mount ─────────────────────────────────────────────────────────────────

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
    tenant_schema = if tenant, do: tenant.schema_name, else: nil
    current_user = socket.assigns[:current_user]

    unless current_user do
      {:ok, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}
    else
      # Opik filter labels for every trace this LiveView (and its Tasks) emits.
      if connected?(socket),
        do: VyaasaCampus.AI.Tracing.put_metadata(%{student_id: current_user.id, module: "mini_project", tenant: tenant_schema})

      rankings =
        if tenant_schema,
          do: StudentRankings.get_student_scores_and_ranks(current_user.id, tenant_schema),
          else: %{}

      ats_fields = StudentAts.get_student_ats_fields(current_user.id, tenant_schema)

      user_info = %{
        name: "#{current_user.first_name} #{current_user.last_name}",
        email: current_user.email,
        profile_picture_url: ats_fields[:profile_picture_url]
      }

      # Pull profile data to pre-fill + auto-start scenario generation
      profile = load_student_profile(current_user, tenant_schema)

      socket =
        socket
        |> assign(:tenant_alias, tenant_alias)
        |> assign(:tenant_schema, tenant_schema)
        |> assign(:tenant_id, tenant && tenant.id)
        |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: tenant_alias))
        |> assign(:current_scope, :student)
        |> assign(:user_info, user_info)
        |> assign(:rankings, rankings)
        |> assign(:page_title, "Domain Mini Project")
        |> assign_initial_state()
        |> assign(:specialization_input, profile.specialization)
        |> assign(:jd_input, profile.preferred_role)
        |> assign(:skills_input, profile.skills_text)
        |> maybe_restore_session(current_user.id, tenant_schema)

      # If student already has a specialization, skip the start form and
      # auto-generate scenarios immediately.
      socket =
        if profile.specialization != "" and socket.assigns.phase == :start do
          auto_start_scenarios(socket, current_user, profile)
        else
          socket
        end

      {:ok, socket}
    end
  end

  # ── Handle Events — all clauses grouped together ──────────────────────────

  @impl true
  # Start screen field updates
  def handle_event("update_field", %{"field" => "specialization", "value" => v}, socket),
    do: {:noreply, assign(socket, :specialization_input, v)}

  def handle_event("update_field", %{"field" => "jd", "value" => v}, socket),
    do: {:noreply, assign(socket, :jd_input, v)}

  def handle_event("update_field", %{"field" => "skills", "value" => v}, socket),
    do: {:noreply, assign(socket, :skills_input, v)}

  def handle_event("start_project", _params, socket) do
    specialization = String.trim(socket.assigns.specialization_input)

    if specialization == "" do
      {:noreply, assign(socket, :error, "Please enter your domain or specialization.")}
    else
      socket = socket |> assign(:loading, :generating_scenarios) |> assign(:error, nil)
      lv = self()
      spec = socket.assigns.specialization_input
      jd = socket.assigns.jd_input
      skills = socket.assigns.skills_input

      Task.async(fn ->
        scenarios = MiniProjectEngine.generate_scenarios(spec, "", jd, skills)
        send(lv, {:scenarios_ready, scenarios, spec, nil})
      end)

      {:noreply, socket}
    end
  end

  # Phase 1 — choose scenario
  def handle_event("choose_scenario", %{"index" => idx_str}, socket) do
    index = String.to_integer(idx_str)
    candidates = socket.assigns.session.scenario_candidates || []
    chosen = Enum.at(candidates, index)

    if is_nil(chosen) do
      {:noreply, assign(socket, :error, "Invalid scenario choice.")}
    else
      prefix = socket.assigns.tenant_schema

      case MiniProject.choose_scenario(socket.assigns.session, chosen, prefix) do
        {:ok, updated} ->
          {:noreply, socket |> assign(:session, updated) |> assign(:phase, :discovery) |> assign(:error, nil)}

        {:error, _} ->
          {:noreply, assign(socket, :error, "Failed to save scenario choice.")}
      end
    end
  end

  # Phase 2 — discovery
  def handle_event("update_question", %{"value" => v}, socket),
    do: {:noreply, assign(socket, :question_input, v)}

  def handle_event("ask_question", _params, socket) do
    question = String.trim(socket.assigns.question_input)
    session = socket.assigns.session

    cond do
      question == "" ->
        {:noreply, assign(socket, :error, "Please type a question.")}

      not MiniProject.can_ask_discovery?(session) ->
        {:noreply, assign(socket, :error, "You've used all 5 discovery questions. Proceed to get your brief.")}

      true ->
        socket = socket |> assign(:loading, :asking) |> assign(:error, nil) |> assign(:question_input, "")
        lv = self()
        scenario = session.chosen_scenario
        messages = session.discovery_messages || []

        Task.async(fn ->
          # Opik: tag this short-lived Task with the session's thread id.
          VyaasaCampus.AI.Tracing.put_thread_id(session && session.id)

          case MiniProjectEngine.stakeholder_reply(scenario, question, messages) do
            {:ok, reply} -> send(lv, {:discovery_reply, question, reply})
            {:error, reason} -> send(lv, {:discovery_error, inspect(reason)})
          end
        end)

        {:noreply, socket}
    end
  end

  def handle_event("finish_discovery", _params, socket) do
    socket = assign(socket, :loading, :generating_brief)
    lv = self()
    session = socket.assigns.session

    Task.async(fn ->
      # Opik: tag this short-lived Task with the session's thread id.
      VyaasaCampus.AI.Tracing.put_thread_id(session && session.id)

      recap = MiniProjectEngine.discovery_recap(session.chosen_scenario, session.discovery_messages || [])
      {brief, submission_type} = MiniProjectEngine.generate_brief(session.chosen_scenario, recap)
      send(lv, {:brief_ready, recap, brief, submission_type})
    end)

    {:noreply, socket}
  end

  # Phase 3 — implementation
  def handle_event("download_brief", _params, socket) do
    content = socket.assigns.session.brief_markdown || ""
    filename = mini_project_download_filename(socket.assigns.current_user, ".md")

    {:noreply,
     push_event(socket, "download-file", %{
       content: content,
       filename: filename,
       mime: "text/markdown;charset=utf-8"
     })}
  end

  def handle_event("proceed_to_submission", _params, socket) do
    prefix = socket.assigns.tenant_schema

    case MiniProject.proceed_to_submission(socket.assigns.session, prefix) do
      {:ok, updated} -> {:noreply, socket |> assign(:session, updated) |> assign(:phase, :project_submission)}
      {:error, _} -> {:noreply, assign(socket, :error, "Failed to proceed.")}
    end
  end

  # Phase 4 — deliverable file upload (PDF / DOCX / PPTX / ZIP …)
  def handle_event("validate_upload", params, socket) do
    {:noreply, assign(socket, :github_url_input, params["github_url"] || socket.assigns.github_url_input)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :deliverable, ref)}

  def handle_event("finalize_submission", _params, socket) do
    cond do
      # Enforce the 24-hour window server-side (Vya-030): a submission arriving
      # after the deadline is rejected and the session is expired, regardless of
      # whether the client-side countdown fired.
      session_overdue?(socket.assigns.session) ->
        {:ok, updated} = MiniProject.expire_session(socket.assigns.session, socket.assigns.tenant_schema)

        {:noreply,
         socket
         |> assign(:session, updated)
         |> assign(:phase, :expired)
         |> assign(:loading, nil)}

      socket.assigns.uploads.deliverable.entries == [] and
          String.trim(socket.assigns.github_url_input || "") == "" ->
        {:noreply,
         assign(
           socket,
           :upload_error,
           "Attach at least one file (PDF, DOCX, PPTX, ZIP) or paste your GitHub repository URL."
         )}

      String.trim(socket.assigns.github_url_input || "") != "" and
          not String.contains?(socket.assigns.github_url_input, "github.com/") ->
        {:noreply,
         assign(
           socket,
           :upload_error,
           "That doesn't look like a GitHub repository URL (https://github.com/owner/repo)."
         )}

      true ->
        # Consume the uploads synchronously (read into memory), then extract text
        # off the request in a Task so pdftotext/pandoc shell-outs don't block.
        files =
          consume_uploaded_entries(socket, :deliverable, fn %{path: path}, entry ->
            {:ok, %{name: entry.client_name, binary: File.read!(path)}}
          end)

        repo_url = String.trim(socket.assigns.github_url_input || "")
        lv = self()
        socket = socket |> assign(:loading, :generating_viva) |> assign(:upload_error, nil)

        Task.async(fn ->
          file_artifacts = Enum.map(files, &build_file_artifact/1)
          repo_artifacts = if repo_url != "", do: [build_repo_artifact(repo_url)], else: []
          send(lv, {:artifacts_ready, file_artifacts ++ repo_artifacts})
        end)

        {:noreply, socket}
    end
  end

  # Phase 5 — viva
  def handle_event("update_viva_answer", %{"value" => v}, socket),
    do: {:noreply, assign(socket, :viva_answer_input, v)}

  def handle_event("submit_viva_answer", _params, socket) do
    answer = String.trim(socket.assigns.viva_answer_input)

    if answer == "" do
      {:noreply, assign(socket, :error, "Please type your answer before submitting.")}
    else
      session = socket.assigns.session
      pending = MPSession.pending_viva_turn(session)

      if is_nil(pending) do
        {:noreply, assign(socket, :error, "No open viva question.")}
      else
        socket = socket |> assign(:loading, :scoring_answer) |> assign(:error, nil) |> assign(:viva_answer_input, "")
        lv = self()
        answered_count = length(MPSession.answered_viva_turns(session))

        Task.async(fn ->
          # Opik: tag this short-lived Task with the session's thread id.
          VyaasaCampus.AI.Tracing.put_thread_id(session && session.id)

          score = MiniProjectEngine.score_viva_answer(pending["question"], pending["evidence"], answer)

          next_q =
            MiniProjectEngine.next_viva_question(
              session.chosen_scenario,
              session.artifacts,
              session.viva_turns,
              answered_count + 1
            )

          send(lv, {:viva_answer_scored, answer, score, next_q})
        end)

        {:noreply, socket}
      end
    end
  end

  # Phase 6 — reflection
  def handle_event("update_reflection", %{"field" => field, "value" => v}, socket) do
    updated = Map.put(socket.assigns.reflection_inputs, field, v)
    {:noreply, assign(socket, :reflection_inputs, updated)}
  end

  def handle_event("submit_reflection", _params, socket) do
    inputs = socket.assigns.reflection_inputs
    required = ["learned", "challenges", "improve", "confidence"]
    blanks = Enum.filter(required, fn k -> String.trim(inputs[k] || "") == "" end)

    if blanks != [] do
      {:noreply, assign(socket, :error, "Please fill in all four reflection fields.")}
    else
      socket = socket |> assign(:loading, :evaluating) |> assign(:error, nil)
      prefix = socket.assigns.tenant_schema
      session = socket.assigns.session
      lv = self()

      reflection_map = %{
        "learned" => inputs["learned"],
        "challenges" => inputs["challenges"],
        "improve" => inputs["improve"],
        "confidence" => inputs["confidence"]
      }

      Task.async(fn ->
        # Opik: tag this short-lived Task with the session's thread id.
        VyaasaCampus.AI.Tracing.put_thread_id(session && session.id)

        case MiniProject.save_reflection(session, reflection_map, prefix) do
          {:ok, updated} ->
            eval =
              MiniProjectEngine.evaluate(
                updated.chosen_scenario,
                updated.artifacts,
                updated.discovery_messages,
                updated.viva_turns,
                reflection_map
              )

            # Fold the viva authorship signal into the authenticity report.
            try do
              MiniProject.merge_viva_authorship(updated, prefix)
            rescue
              _ -> :ok
            end

            send(lv, {:evaluation_ready, eval})

          {:error, reason} ->
            send(lv, {:evaluation_error, inspect(reason)})
        end
      end)

      {:noreply, socket}
    end
  end

  # Navigation
  def handle_event("start_new", _params, socket) do
    current_user = socket.assigns.current_user
    tenant_schema = socket.assigns.tenant_schema
    profile = load_student_profile(current_user, tenant_schema)

    socket =
      socket
      |> assign(:session, nil)
      |> assign(:phase, :start)
      |> assign(:scenario_candidates, [])
      |> assign(:error, nil)
      |> assign(:error_title, "Something went wrong")
      |> assign(:upload_error, nil)
      |> assign(:github_url_input, "")
      |> assign(:loading, nil)
      |> assign(:specialization_input, profile.specialization)
      |> assign(:jd_input, profile.preferred_role)
      |> assign(:skills_input, profile.skills_text)
      |> assign(:reflection_inputs, %{"learned" => "", "challenges" => "", "improve" => "", "confidence" => ""})

    # Auto-generate again if profile data is still present
    socket =
      if profile.specialization != "" do
        auto_start_scenarios(socket, current_user, profile)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("resend_report", _params, socket) do
    case socket.assigns[:session] do
      %{id: id, phase: "completed"} ->
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(
          :mini_project,
          id,
          socket.assigns.tenant_schema
        )

        {:noreply, put_flash(socket, :info, "Your mini project report is on its way to your email ✉️")}

      _ ->
        {:noreply, put_flash(socket, :error, "No completed mini project to email yet.")}
    end
  end

  def handle_event("deadline_reached_client", _params, socket) do
    send(self(), :deadline_reached)
    {:noreply, socket}
  end

  def handle_event("dismiss_error", _params, socket),
    do: {:noreply, assign(socket, :error, nil)}

  def handle_event("back_to_dashboard", _params, socket),
    do: {:noreply, redirect(socket, to: "/student/#{socket.assigns.tenant_alias}/dashboard")}

  def handle_event("logout", _params, socket),
    do: {:noreply, redirect(socket, to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}

  # ── Handle Info — all clauses grouped together ────────────────────────────

  @impl true
  def handle_info({:scenarios_ready, scenarios, specialization, _user}, socket) do
    prefix = socket.assigns.tenant_schema
    student_id = socket.assigns.current_user.id
    tenant_id = socket.assigns.tenant_id

    attrs = %{
      student_id: student_id,
      tenant_id: tenant_id,
      archetype_key: "general",
      specialization_name: specialization
    }

    case MiniProject.create_session(attrs, prefix) do
      {:ok, session} ->
        case MiniProject.store_scenarios(session, scenarios, prefix) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:session, updated)
             |> assign(:phase, :role_assignment)
             |> assign(:scenario_candidates, scenarios)
             |> assign(:loading, nil)}

          {:error, _} ->
            {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Failed to save scenarios.")}
        end

      {:error, :attempt_limit_reached, _details} ->
        {:noreply,
         socket
         |> assign(:loading, nil)
         |> assign(:error_title, "Out of attempts")
         |> assign(
           :error,
           "You've used all your available mini project attempts. Please contact your college admin to request more."
         )}

      {:error, _} ->
        {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Failed to start session.")}
    end
  end

  def handle_info({:discovery_reply, question, reply}, socket) do
    prefix = socket.assigns.tenant_schema
    revealed = List.wrap(reply["revealed"])

    case MiniProject.add_discovery_message(socket.assigns.session, question, reply, revealed, prefix) do
      {:ok, updated} -> {:noreply, socket |> assign(:session, updated) |> assign(:loading, nil)}
      {:error, _} -> {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Failed to save reply.")}
    end
  end

  def handle_info({:discovery_error, reason}, socket) do
    Logger.error("Discovery reply error: #{reason}")
    {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Stakeholder is unavailable. Try again.")}
  end

  def handle_info({:brief_ready, recap, brief, submission_type}, socket) do
    prefix = socket.assigns.tenant_schema

    case MiniProject.finish_discovery(socket.assigns.session, recap, brief, prefix, submission_type) do
      {:ok, updated} ->
        socket =
          socket
          |> assign(:session, updated)
          |> assign(:phase, :implementation)
          |> assign(:loading, nil)
          |> maybe_schedule_deadline(updated, :implementation)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Failed to save brief.")}
    end
  end

  def handle_info({:artifacts_ready, artifacts}, socket) do
    prefix = socket.assigns.tenant_schema
    lv = self()

    result =
      Enum.reduce_while(artifacts, {:ok, socket.assigns.session}, fn artifact, {:ok, sess} ->
        case MiniProject.add_artifact(sess, artifact, prefix) do
          {:ok, updated} -> {:cont, {:ok, updated}}
          err -> {:halt, err}
        end
      end)

    case result do
      {:ok, updated_session} ->
        student_name =
          "#{socket.assigns.current_user.first_name} #{socket.assigns.current_user.last_name}"

        Task.async(fn ->
          # Opik: tag this short-lived Task with the session's thread id.
          VyaasaCampus.AI.Tracing.put_thread_id(updated_session && updated_session.id)

          # Authenticity forensics (file metadata + repo + timing) — off-process
          # since it may hit pdfinfo and the GitHub API. Never blocks the viva.
          try do
            report = build_authenticity_report(updated_session, student_name)
            MiniProject.store_authenticity(updated_session, report, prefix)
          rescue
            e -> Logger.warning("MiniProject forensics failed: #{Exception.message(e)}")
          end

          q = MiniProjectEngine.next_viva_question(updated_session.chosen_scenario, updated_session.artifacts, [], 0)
          send(lv, {:viva_question_ready, q})
        end)

        {:noreply, assign(socket, :session, updated_session)}

      {:error, _} ->
        {:noreply,
         socket |> assign(:loading, nil) |> assign(:upload_error, "Failed to save your submission. Please try again.")}
    end
  end

  def handle_info({:viva_question_ready, question}, socket) do
    prefix = socket.assigns.tenant_schema

    case MiniProject.finalize_submission(socket.assigns.session, question, prefix) do
      {:ok, updated} ->
        {:noreply, socket |> assign(:session, updated) |> assign(:phase, :viva) |> assign(:loading, nil)}

      {:error, _} ->
        {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Failed to start viva.")}
    end
  end

  def handle_info({:viva_answer_scored, answer, score, next_q}, socket) do
    prefix = socket.assigns.tenant_schema
    {result, viva_complete} = MiniProject.answer_viva(socket.assigns.session, answer, score, next_q, prefix)

    case result do
      {:ok, updated} ->
        phase = if viva_complete, do: :reflection, else: :viva

        {:noreply, socket |> assign(:session, updated) |> assign(:phase, phase) |> assign(:loading, nil)}

      {:error, _} ->
        {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Failed to save answer.")}
    end
  end

  def handle_info({:evaluation_ready, eval}, socket) do
    prefix = socket.assigns.tenant_schema

    case MiniProject.complete_session(socket.assigns.session, eval, prefix) do
      {:ok, updated} ->
        {:noreply, socket |> assign(:session, updated) |> assign(:phase, :completed) |> assign(:loading, nil)}

      {:error, _} ->
        {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Failed to save evaluation.")}
    end
  end

  def handle_info({:evaluation_error, reason}, socket) do
    Logger.error("Mini project evaluation error: #{reason}")
    {:noreply, socket |> assign(:loading, nil) |> assign(:error, "Evaluation failed. Please try again.")}
  end

  def handle_info(:deadline_reached, socket) do
    if socket.assigns.phase in [:implementation, :project_submission] do
      prefix = socket.assigns.tenant_schema

      case MiniProject.expire_session(socket.assigns.session, prefix) do
        {:ok, updated} ->
          {:noreply, socket |> assign(:session, updated) |> assign(:phase, :expired) |> assign(:loading, nil)}

        {:error, _} ->
          {:noreply, socket |> assign(:phase, :expired) |> assign(:loading, nil)}
      end
    else
      {:noreply, socket}
    end
  end

  # Catch-all for Task DOWN messages
  def handle_info({ref, _result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
    <div class="min-h-screen flex bg-[#FAF9F7] font-sans">
      <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar
        current_section="mini_project"
        tenant_alias={@tenant_alias}
        student_name={@user_info[:name]}
        rankings={@rankings}
      />

      <div class="flex-1 flex flex-col min-w-0">
        <.mini_project_header phase={@phase} session={@session} />

        <main class="flex-1 p-6 lg:p-8">
          <!-- Error banner -->
          <.error_card
            :if={@error}
            title={@error_title}
            error_message={@error}
            retry_event="dismiss_error"
            class="mb-5 max-w-6xl mx-auto"
          />

          <!-- Two-column layout: main content + right step panel -->
          <div class={[
            "mx-auto",
            if(@phase in [:start, :completed, :expired],
              do: "max-w-4xl",
              else: "max-w-6xl flex gap-8 items-start"
            )
          ]}>
            <!-- Main screen content -->
            <div class={if(@phase not in [:start, :completed, :expired], do: "flex-1 min-w-0", else: "")}>
              <%= case @phase do %>
                <% :start -> %>
                  <.start_screen
                    specialization={@specialization_input}
                    jd={@jd_input}
                    skills={@skills_input}
                    loading={@loading}
                  />
                <% :role_assignment -> %>
                  <.scenario_selection_screen session={@session} loading={@loading} />
                <% :discovery -> %>
                  <.discovery_screen
                    session={@session}
                    question_input={@question_input}
                    loading={@loading}
                  />
                <% :implementation -> %>
                  <.implementation_screen session={@session} />
                <% :project_submission -> %>
                  <.submission_screen
                    session={@session}
                    uploads={@uploads}
                    github_url={@github_url_input}
                    loading={@loading}
                    upload_error={@upload_error}
                  />
                <% :viva -> %>
                  <.viva_screen
                    session={@session}
                    answer_input={@viva_answer_input}
                    loading={@loading}
                  />
                <% :reflection -> %>
                  <.reflection_screen inputs={@reflection_inputs} loading={@loading} />
                <% :completed -> %>
                  <.report_screen session={@session} />
                <% :expired -> %>
                  <.expired_screen session={@session} />
                <% _ -> %>
                  <.start_screen
                    specialization={@specialization_input}
                    jd={@jd_input}
                    skills={@skills_input}
                    loading={@loading}
                  />
              <% end %>
            </div>

            <!-- Right sidebar step panel (all phases except start, report, expired) -->
            <%= if @phase not in [:start, :completed, :expired] do %>
              <div class="w-64 shrink-0">
                <.step_panel phase={@phase} session={@session} />
              </div>
            <% end %>
          </div>
        </main>
      </div>
    </div>
    </Layouts.app>
    """
  end

  # ── Private ───────────────────────────────────────────────────────────────

  # Turn one uploaded file into a scored artifact: extract its text (PDF/DOCX/
  # PPTX/ZIP/…) so the AI evaluates real content, not just a filename.
  # Combine per-file forensics + any submitted repo + timing into an
  # authenticity report for the admin.
  defp build_authenticity_report(session, student_name) do
    file_analyses =
      (session.artifacts || [])
      |> Enum.map(& &1["forensics"])
      |> Enum.filter(&is_map/1)

    repo_url =
      Enum.find_value(session.artifacts || [], fn a ->
        a["type"] in ["github", "repo"] && a["url"]
      end)

    repo_analysis = if is_binary(repo_url), do: MiniProjectForensics.analyze_repo(repo_url), else: nil

    MiniProjectForensics.authenticity_report(
      file_analyses,
      repo_analysis,
      to_dt(session.inserted_at),
      DateTime.utc_now(),
      student_name
    )
  end

  # A submitted GitHub repo becomes an artifact: fetch its text for scoring, and
  # tag it so the forensics pass runs commit-history analysis (Vya-025 dead-repo
  # handling comes from fetch_github_repo).
  defp build_repo_artifact(url) do
    {text, ok} =
      case MiniProjectEngine.fetch_github_repo(url) do
        {:ok, t} -> {t, true}
        {:error, reason} -> {"Student submitted GitHub repository: #{url} (#{inspect(reason)})", false}
      end

    %{
      "type" => "github",
      "filename" => "github_repository",
      "url" => url,
      "extract_ok" => ok,
      "extracted_text" => text,
      "size_bytes" => byte_size(text),
      "content_type" => "text/plain",
      "truncated" => false,
      "analysis" => nil,
      "injection_suspected" => false,
      "forensics" => nil
    }
  end

  defp to_dt(%DateTime{} = d), do: d
  defp to_dt(%NaiveDateTime{} = n), do: DateTime.from_naive!(n, "Etc/UTC")
  defp to_dt(_), do: nil

  defp build_file_artifact(%{name: name, binary: binary}) do
    {text, ok} =
      case MiniProjectFileExtractor.extract(name, binary) do
        {:ok, t} when byte_size(t) > 0 ->
          {t, true}

        {:ok, _} ->
          {"Uploaded file '#{name}' contained no readable text.", false}

        {:error, reason} ->
          Logger.warning("Mini-project file extract failed for #{name}: #{reason}")
          {"Uploaded file '#{name}' (text could not be extracted: #{reason}).", false}
      end

    %{
      "type" => "file",
      "filename" => name,
      "url" => nil,
      "extract_ok" => ok,
      "extracted_text" => text,
      "size_bytes" => byte_size(binary),
      "content_type" => "application/octet-stream",
      "truncated" => false,
      "analysis" => nil,
      "injection_suspected" => false,
      # Provenance forensics (created/author/modified) for authenticity checks.
      "forensics" => MiniProjectForensics.analyze_file(name, binary)
    }
  end

  defp assign_initial_state(socket) do
    socket
    |> assign(:session, nil)
    |> assign(:phase, :start)
    |> assign(:loading, nil)
    |> assign(:error, nil)
    |> assign(:error_title, "Something went wrong")
    |> assign(:specialization_input, "")
    |> assign(:jd_input, "")
    |> assign(:skills_input, "")
    |> assign(:scenario_candidates, [])
    |> assign(:question_input, "")
    |> assign(:upload_error, nil)
    |> assign(:github_url_input, "")
    |> assign(:viva_answer_input, "")
    |> assign(:reflection_inputs, %{"learned" => "", "challenges" => "", "improve" => "", "confidence" => ""})
    |> allow_upload(:deliverable,
      accept: ~w(.pdf .docx .doc .pptx .zip .txt .csv .json),
      max_entries: 5,
      max_file_size: 20 * 1024 * 1024,
      auto_upload: true
    )
  end

  defp maybe_restore_session(socket, student_id, prefix) do
    active = MiniProject.get_active_session(student_id, prefix)
    completed = MiniProject.get_latest_completed_session(student_id, prefix)

    cond do
      # A genuine in-progress attempt started after the last completed result
      # (e.g. a retake via "Start new") — resume it.
      active && attempt_newer_than?(active, completed) ->
        assign_session(socket, active)

      # Otherwise, if they've already completed the assessment, always land on
      # their result — never on the start page or a stale abandoned attempt.
      completed ->
        assign_session(socket, completed)

      # First attempt still in progress — resume it.
      active ->
        assign_session(socket, active)

      true ->
        socket
    end
  end

  defp attempt_newer_than?(_active, nil), do: true

  defp attempt_newer_than?(active, completed),
    do: DateTime.compare(active.inserted_at, completed.inserted_at) == :gt

  defp assign_session(socket, session) do
    phase =
      cond do
        session.time_expired -> :expired
        true -> String.to_atom(session.phase)
      end

    socket
    |> assign(:session, session)
    |> assign(:phase, phase)
    |> maybe_schedule_deadline(session, phase)
  end

  defp maybe_schedule_deadline(socket, session, phase)
       when phase in [:implementation, :project_submission] do
    case session.submission_deadline do
      nil ->
        socket

      deadline ->
        remaining_ms = DateTime.diff(deadline, DateTime.utc_now(), :millisecond)

        if remaining_ms <= 0 do
          send(self(), :deadline_reached)
        else
          Process.send_after(self(), :deadline_reached, remaining_ms)
        end

        socket
    end
  end

  defp maybe_schedule_deadline(socket, _session, _phase), do: socket

  # True once the 24-hour submission window has passed (Vya-030).
  defp session_overdue?(%{time_expired: true}), do: true

  defp session_overdue?(%{submission_deadline: %DateTime{} = deadline}),
    do: DateTime.compare(DateTime.utc_now(), deadline) == :gt

  defp session_overdue?(_), do: false

  # ── Profile loading ───────────────────────────────────────────────────────

  defp load_student_profile(current_user, tenant_schema) do
    # Academic specialization from student profile
    specialization = build_specialization_label(current_user)

    # Job role + skills from ATS phase (resume parsing result)
    ats = if tenant_schema, do: StudentAts.get_by_student_id(current_user.id, tenant_schema), else: nil

    preferred_role = (ats && ats.preferred_role) || ""

    skills_text =
      case ats && ats.skills do
        %{"technical_skills" => tech} when is_list(tech) and tech != [] ->
          tech |> Enum.take(10) |> Enum.join(", ")

        %{"skills_raw" => raw} when is_list(raw) and raw != [] ->
          raw |> Enum.take(10) |> Enum.join(", ")

        _ ->
          ""
      end

    %{specialization: specialization, preferred_role: preferred_role, skills_text: skills_text}
  end

  defp build_specialization_label(user) do
    parts =
      [user.specialization, user.degree]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    case parts do
      [] -> ""
      _ -> Enum.join(parts, " — ")
    end
  end

  defp auto_start_scenarios(socket, _current_user, profile) do
    lv = self()
    # Anchor the project on the student's target ROLE (from their resume/ATS) when
    # it's set — otherwise an experienced candidate (e.g. QA Engineer) gets a
    # generic task built from their academic degree ("B.Tech intern").
    spec =
      if String.trim(profile.preferred_role || "") != "",
        do: profile.preferred_role,
        else: profile.specialization

    jd = profile.preferred_role
    skills = profile.skills_text

    Task.async(fn ->
      scenarios = MiniProjectEngine.generate_scenarios(spec, "", jd, skills)
      send(lv, {:scenarios_ready, scenarios, spec, nil})
    end)

    socket
    |> assign(:loading, :generating_scenarios)
    |> assign(:error, nil)
  end

  defp mini_project_download_filename(student, extension) do
    "Vyaasa-mini-project-#{student_slug(student)}-#{Date.utc_today()}#{extension}"
  end

  defp student_slug(%{first_name: first_name, last_name: last_name}) do
    [first_name, last_name]
    |> Enum.reject(&(is_nil(&1) or String.trim(to_string(&1)) == ""))
    |> Enum.join("-")
    |> slugify("student")
  end

  defp student_slug(_), do: "student"

  defp slugify(value, fallback) do
    value
    |> to_string()
    |> String.replace(~r/[^\w\-]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> fallback
      slug -> slug
    end
  end

  # Closing the tab / navigating away mid-project must not leave the session
  # stuck non-terminal forever. Enqueues the same finalize job the
  # abandonment sweep uses, so both share one completion path
  # (MiniProject.force_complete/2, itself just an idempotency-guarded entry
  # point into the existing expire_session/2). Guarded on connected?/1 — the
  # disconnected static-render pass would otherwise fire this on every page
  # load.
  @impl true
  def terminate(_reason, socket) do
    with true <- connected?(socket),
         %{id: session_id} <- socket.assigns[:session],
         tenant_schema when is_binary(tenant_schema) <- socket.assigns[:tenant_schema] do
      VyaasaCampus.Jobs.AssessmentFinalizer.enqueue("mini_project", session_id, tenant_schema)
    end

    :ok
  end
end
