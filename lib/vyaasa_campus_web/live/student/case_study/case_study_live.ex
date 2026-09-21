defmodule VyaasaCampusWeb.Student.CaseStudy.CaseStudyLive do
  @moduledoc """
  Student AI-Generated Case Study assessment.

  Steps: intro → choose (1 of 2 generated scenarios) → workspace (7 sections) →
  review (+ confirm) → evaluating → results. Results publish into AI8 via
  `Contexts.CaseStudy`.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.{AttemptGuard, CaseStudy, StudentAts, Tenants}
  alias VyaasaCampus.AI.CaseStudy.Questions

  import VyaasaCampusWeb.Components.UI

  @impl true
  def mount(%{"tenant" => tenant_alias}, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok, redirect(socket, to: "/auth/tenant/#{tenant_alias}/login")}

      user ->
        tenant = Tenants.get_tenant_by_alias(String.upcase(tenant_alias))
        prefix = if tenant, do: tenant.schema_name, else: "public"

        # Opik filter labels for every trace this LiveView (and its Tasks) emits.
        if connected?(socket),
          do: VyaasaCampus.AI.Tracing.put_metadata(%{student_id: user.id, module: "case_study", tenant: prefix})

        # If the student already completed the assessment, land on their
        # results instead of the start page (Retake is still available there).
        {step, session} =
          case CaseStudy.get_latest(user.id, prefix) do
            nil -> {:intro, nil}
            completed -> {:results, completed}
          end

        {:ok,
         socket
         |> assign(:tenant_alias, tenant_alias)
         |> assign(:tenant_schema, prefix)
         |> assign(:current_scope, :student)
         |> assign(:user_info, %{
           name: "#{user.first_name} #{user.last_name}",
           role: "Student",
           email: user.email,
           profile_picture_url: StudentAts.get_student_ats_fields(user.id, prefix)[:profile_picture_url]
         })
         |> assign(:page_title, "Case Study")
         |> assign(:step, step)
         |> assign(:loading, nil)
         |> assign(:error, nil)
         |> assign(:error_title, "Something went wrong")
         |> assign(:last_action, nil)
         |> assign(:confirm_submit, false)
         # Specialization is the role the student selected during resume/ATS
         # processing (latest ATS phase's preferred_role); profile is the fallback.
         |> assign(:sub, resume_specialization(user, prefix))
         |> assign(:questions, Questions.all())
         |> assign(:expanded, hd(Questions.keys()))
         |> assign(:scenarios, [])
         |> assign(:selected_index, 0)
         |> assign(:session, session)
         |> assign(:answers, Questions.empty_answers())
         |> assign(:report, nil)
         |> assign(:async_ref, nil)
         # Proctoring: fullscreen + tab/blur/paste guard; auto-submit at 3
         # strikes (scores typed answers; terminates if all blank). No gate
         # when only viewing a completed result.
         |> assign(:require_fullscreen, step != :results)
         |> assign(:violation_count, 0)
         |> assign(:violation_limit, 3)
         |> assign(:show_integrity_warning, false)
         |> assign(:integrity_message, nil)}
    end
  end

  # ── Events ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("generate", _params, socket) do
    sub = socket.assigns.sub
    task = Task.async(fn -> CaseStudy.generate_scenarios(sub) end)

    {:noreply,
     socket
     |> assign(:loading, :generate)
     |> assign(:error, nil)
     |> assign(:last_action, "generate")
     |> assign(:async_ref, task.ref)}
  end

  def handle_event("select_scenario", %{"index" => i}, socket) do
    {:noreply, assign(socket, :selected_index, String.to_integer(i))}
  end

  def handle_event("continue", _params, socket) do
    user = socket.assigns.current_user
    scenario = Enum.at(socket.assigns.scenarios, socket.assigns.selected_index)
    prefix = socket.assigns.tenant_schema

    task =
      Task.async(fn ->
        CaseStudy.start_session(user.id, Map.get(user, :tenant_id), socket.assigns.sub, scenario, prefix)
      end)

    {:noreply,
     socket
     |> assign(:loading, :start)
     |> assign(:last_action, "continue")
     |> assign(:async_ref, task.ref)}
  end

  def handle_event("change_scenario", _params, socket), do: {:noreply, assign(socket, :step, :choose)}

  def handle_event("toggle_section", %{"key" => key}, socket) do
    expanded = if socket.assigns.expanded == key, do: nil, else: key
    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("update_answers", %{"answers" => answers}, socket) do
    {:noreply, assign(socket, :answers, Map.merge(socket.assigns.answers, answers))}
  end

  def handle_event("review", %{"answers" => answers}, socket) do
    {:noreply, socket |> assign(:answers, Map.merge(socket.assigns.answers, answers)) |> assign(:step, :review)}
  end

  def handle_event("back_to_edit", _params, socket), do: {:noreply, assign(socket, :step, :workspace)}
  def handle_event("request_submit", _params, socket), do: {:noreply, assign(socket, :confirm_submit, true)}
  def handle_event("cancel_submit", _params, socket), do: {:noreply, assign(socket, :confirm_submit, false)}

  def handle_event("submit", _params, socket) do
    session = socket.assigns.session
    answers = socket.assigns.answers
    prefix = socket.assigns.tenant_schema

    if all_answers_blank?(answers) do
      # Don't send an empty attempt for AI scoring — it inflates the AI8 index
      # off zero content (Vya-034). Keep the student on review with an error.
      {:noreply,
       socket
       |> assign(:confirm_submit, false)
       |> assign(:step, :review)
       |> assign(:error, "Please answer at least one prompt before submitting.")}
    else
      task = Task.async(fn -> CaseStudy.submit(session, answers, prefix) end)

      {:noreply,
       socket
       |> assign(:confirm_submit, false)
       |> assign(:step, :evaluating)
       |> assign(:loading, :submit)
       |> assign(:error, nil)
       |> assign(:last_action, "submit")
       |> assign(:async_ref, task.ref)}
    end
  end

  def handle_event("retake", _params, socket) do
    user = socket.assigns.current_user
    prefix = socket.assigns.tenant_schema

    case AttemptGuard.check(user.id, :case_study, Map.get(user, :tenant_id), prefix) do
      :ok ->
        {:noreply,
         socket
         |> assign(:step, :intro)
         |> assign(:scenarios, [])
         |> assign(:session, nil)
         |> assign(:answers, Questions.empty_answers())
         |> assign(:report, nil)
         |> assign(:error, nil)
         |> assign(:error_title, "Something went wrong")
         |> assign(:last_action, nil)}

      {:error, :attempt_limit_reached, _details} ->
        {:noreply,
         socket
         |> assign(:step, :results)
         |> assign(:loading, nil)
         |> assign(:async_ref, nil)
         |> assign(:last_action, "retake")
         |> assign(:error_title, "Out of attempts")
         |> assign(
           :error,
           "You've used all your available case study attempts. Please contact your college admin to request more."
         )}
    end
  end

  def handle_event("resend_report", _params, socket) do
    case socket.assigns[:session] do
      %{id: id} ->
        VyaasaCampus.Jobs.ReportGenerator.enqueue_safe(:case_study, id, socket.assigns.tenant_schema)
        {:noreply, put_flash(socket, :info, "Your case study report is on its way to your email ✉️")}

      _ ->
        {:noreply, put_flash(socket, :error, "No completed case study to email yet.")}
    end
  end

  def handle_event("back_to_dashboard", _params, socket) do
    {:noreply, redirect(socket, to: "/student/#{socket.assigns.tenant_alias}/dashboard")}
  end

  def handle_event("logout", _params, socket) do
    {:noreply, redirect(socket, to: "/auth/tenant/#{socket.assigns.tenant_alias}/logout")}
  end

  # Proctoring: enforced ONLY once the student is answering (workspace/review) —
  # violations before that are ignored. On the 3rd strike the assessment is
  # closed (terminated, no score) and the student is returned to the dashboard.
  def handle_event("integrity_violation", %{"type" => type}, socket) do
    if socket.assigns.step in [:workspace, :review] do
      count = persist_cs_violation(socket, type)
      limit = socket.assigns.violation_limit
      socket = socket |> assign(:violation_count, count) |> assign(:show_integrity_warning, true)

      if count >= limit do
        if socket.assigns.session, do: CaseStudy.terminate(socket.assigns.session, socket.assigns.tenant_schema)

        {:noreply,
         socket
         |> put_flash(:error, "Your assessment was closed after #{limit} full-screen exits / tab switches.")
         |> redirect(to: "/student/#{socket.assigns.tenant_alias}/dashboard")}
      else
        {:noreply, assign(socket, :integrity_message, cs_violation_message(type, limit - count))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss_integrity_warning", _params, socket) do
    {:noreply, assign(socket, :show_integrity_warning, false)}
  end

  # ── Async results ───────────────────────────────────────────────────────

  @impl true
  def handle_info({ref, result}, socket) when socket.assigns.async_ref == ref do
    Process.demonitor(ref, [:flush])

    case {socket.assigns.loading, result} do
      {:generate, {:ok, scenarios}} ->
        {:noreply,
         socket
         |> assign(:scenarios, Enum.map(scenarios, &stringify/1))
         |> assign(:selected_index, 0)
         |> assign(:step, :choose)
         |> assign(:loading, nil)
         |> assign(:async_ref, nil)}

      {:start, {:ok, session}} ->
        {:noreply,
         socket
         |> assign(:session, session)
         |> assign(:step, :workspace)
         |> assign(:loading, nil)
         |> assign(:async_ref, nil)}

      {:submit, {:ok, session}} ->
        {:noreply,
         socket
         |> assign(:session, session)
         |> assign(:report, session.report)
         |> assign(:step, :results)
         |> assign(:loading, nil)
         |> assign(:async_ref, nil)}

      {_, {:error, :attempt_limit_reached, _details}} ->
        prev = if socket.assigns.step == :evaluating, do: :review, else: socket.assigns.step

        {:noreply,
         socket
         |> assign(:step, prev)
         |> assign(:loading, nil)
         |> assign(:async_ref, nil)
         |> assign(:error_title, "Out of attempts")
         |> assign(
           :error,
           "You've used all your available case study attempts. Please contact your college admin to request more."
         )}

      {_, {:error, reason}} ->
        prev = if socket.assigns.step == :evaluating, do: :review, else: socket.assigns.step

        {:noreply,
         socket
         |> assign(:step, prev)
         |> assign(:loading, nil)
         |> assign(:async_ref, nil)
         |> assign(:error_title, "Something went wrong")
         |> assign(:error, "Something went wrong (#{inspect(reason)}). Please try again.")}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) when socket.assigns.async_ref == ref do
    {:noreply,
     socket |> assign(:loading, nil) |> assign(:async_ref, nil) |> assign(:error, "The task failed. Please try again.")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp persist_cs_violation(socket, type) do
    case socket.assigns.session do
      %{session_token: token} when is_binary(token) ->
        case CaseStudy.record_violation(token, type, socket.assigns.tenant_schema) do
          {:ok, n} -> n
          _ -> socket.assigns.violation_count + 1
        end

      _ ->
        socket.assigns.violation_count + 1
    end
  end

  defp cs_violation_message(type, remaining) do
    label =
      case type do
        "fullscreen_exit" -> "You left full-screen mode."
        "window_blur" -> "You switched away from the assessment window."
        _ -> "You switched tabs / left the assessment."
      end

    cond do
      remaining <= 0 -> "#{label} Ending your assessment."
      remaining == 1 -> "#{label} Final warning — one more and your answers are submitted automatically."
      true -> "#{label} This is recorded. #{remaining} warnings left before auto-submit."
    end
  end

  # ── Render ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    # Full screen is required only once the student is actually answering.
    assigns = assign(assigns, :require_fullscreen, assigns.step in [:workspace, :review])

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-[#FBFAF7] flex" id="case-study-container" phx-hook="AssessmentIntegrity"
        data-require-fullscreen={to_string(@require_fullscreen)}>
        <div :if={@require_fullscreen} id="fullscreen-gate" phx-update="ignore"
          class="fixed inset-0 z-[100] bg-gray-900/95 flex items-center justify-center p-6 text-center">
          <div class="max-w-md">
            <.icon name="hero-lock-closed" class="w-12 h-12 text-orange-400 mx-auto mb-4" />
            <h2 class="text-xl font-bold text-white mb-2">Secure full-screen mode</h2>
            <p class="text-sm text-gray-300 mb-6">
              This is a proctored assessment that runs in full screen. Leaving full screen, switching
              tabs, or pasting text is recorded — after {@violation_limit} warnings your answers are
              submitted automatically.
            </p>
            <button id="enter-fullscreen-btn" type="button"
              class="px-6 py-3 rounded-xl bg-orange-500 hover:bg-orange-600 text-white font-semibold">
              Enter full screen &amp; begin
            </button>
            <div class="mt-4">
              <.link navigate={"/student/#{@tenant_alias}/dashboard"}
                data-confirm="Leave the assessment? Your progress won't be submitted."
                class="text-sm text-gray-400 hover:text-gray-200 underline">
                Exit assessment
              </.link>
            </div>
          </div>
        </div>

        <VyaasaCampusWeb.Components.Student.SidebarComponent.sidebar
          current_section="case_studies"
          tenant_alias={@tenant_alias}
          student_name={@user_info.name}
        />
        <div class="flex-1 flex flex-col min-w-0">
          <VyaasaCampusWeb.Components.Student.HeaderComponent.header user_info={@user_info} tenant_alias={@tenant_alias} page_title="Case Study" exit_href={"/student/#{@tenant_alias}/dashboard"} />

          <div :if={@show_integrity_warning} class="bg-red-600 text-white px-6 py-3 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-exclamation-triangle" class="w-5 h-5 shrink-0" />
              <span class="text-sm font-medium">{@integrity_message} (Strike {@violation_count} of {@violation_limit}.)</span>
            </div>
            <button type="button" phx-click="dismiss_integrity_warning" class="text-white hover:text-red-100">
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <main class="flex-1 overflow-auto bg-white">
            <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-[1280px] mx-auto w-full">
              <.error_card
                :if={@error && @step != :results}
                title={@error_title}
                error_message={@error}
                retry_event={@last_action || "generate"}
                class="mb-4"
              />

              <%= case @step do %>
                <% :intro -> %>{intro(assigns)}
                <% :choose -> %>{choose(assigns)}
                <% :workspace -> %>{workspace(assigns)}
                <% :review -> %>{review(assigns)}
                <% :evaluating -> %>{evaluating(assigns)}
                <% :results -> %>{results(assigns)}
                <% :terminated -> %>
                  <div class="bg-white rounded-2xl border p-8 text-center max-w-lg mx-auto" style="border-color: #FECACA;">
                    <div class="w-14 h-14 rounded-full bg-red-50 flex items-center justify-center mx-auto mb-4">
                      <.icon name="hero-shield-exclamation" class="w-7 h-7 text-red-500" />
                    </div>
                    <h2 class="text-xl font-bold text-gray-900 mb-2">Assessment ended</h2>
                    <p class="text-sm text-gray-500 mb-6">
                      Your assessment was ended after repeated integrity violations, with no answers
                      to score. This has been shared with your evaluator.
                    </p>
                    <button phx-click="back_to_dashboard"
                      class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold"
                      style="background-color: #EE6D18;">
                      Back to dashboard
                    </button>
                  </div>
              <% end %>
            </div>
          </main>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Step: intro ──────────────────────────────────────────────────────────
  defp intro(assigns) do
    ~H"""
    <p class="text-[11px] font-semibold tracking-wide text-[#EE6D18] uppercase mb-1">AI8 · Case Study Assessment</p>
    <h1 class="text-2xl font-bold text-gray-900 mb-1">Solve a real-world challenge</h1>
    <p class="text-sm text-gray-500 mb-6">An AI-guided consulting simulation. Choose your scenario, think structurally, and let our evaluator surface recruiter-grade insights.</p>

    <div class="rounded-2xl border border-[#F8C095] bg-gradient-to-br from-[#FFF4E7] to-[#FBFAF7] p-6 mb-6">
      <span class="text-[11px] font-semibold text-[#EE6D18] bg-white/70 rounded-full px-3 py-1">AI-Powered Consulting Simulation</span>
      <h2 class="text-2xl font-bold text-gray-900 mt-3 mb-1">AI8 Case Study Assessment</h2>
      <p class="text-sm text-gray-600 max-w-2xl">Solve real-world business and technical scenarios using structured thinking. Text or voice — your choice. AI transcribes, recruiters read.</p>
      <div class="flex flex-wrap gap-2 mt-4">
        <span :for={f <- ["Text supported", "AI auto-transcription", "Recruiter-style evaluation", "Percentile ranking", "Detailed feedback"]}
          class="text-[11px] font-medium px-2.5 py-1 rounded-full bg-white text-gray-600 border border-[#F3E7DA]">{f}</span>
      </div>
    </div>

    <h3 class="text-sm font-bold text-gray-900 mb-3">What you'll be evaluated on</h3>
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
      <.eval_dim title="Problem Solving & Critical Thinking" desc="Structured thinking, decomposition, clarity of reasoning." />
      <.eval_dim title="Domain Expertise & Technical Skills" desc="Depth of technical knowledge and applied judgement." />
      <.eval_dim title="Initiative & Leadership Potential" desc="Ownership, prioritisation, stakeholder thinking." />
    </div>

    <h3 class="text-sm font-bold text-gray-900 mb-3">Answering framework <span class="text-xs font-normal text-gray-400">· all 7 sections mandatory</span></h3>
    <div class="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-3 mb-8">
      <div :for={{q, i} <- Enum.with_index(@questions, 1)} class="bg-white rounded-xl border border-gray-100 shadow-card-soft p-3">
        <span class="inline-flex w-6 h-6 rounded-full bg-[#FFF4E7] text-[#EE6D18] text-xs font-bold items-center justify-center mb-2">{i}</span>
        <p class="text-xs font-semibold text-gray-800 leading-tight">{q.title}</p>
      </div>
    </div>

    <div class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-5 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <p class="font-bold text-gray-900">Ready when you are.</p>
        <p class="text-sm text-gray-500">
          We'll generate two realistic scenarios tailored to your specialization —
          <span class="font-semibold text-[#EE6D18]">{@sub}</span>.
        </p>
      </div>
      <button :if={!@error} phx-click="generate" disabled={@loading == :generate} class="px-5 py-2.5 rounded-xl text-white text-sm font-semibold whitespace-nowrap disabled:opacity-50" style="background-color: #EE6D18;">
        <%= if @loading == :generate, do: "Generating…", else: "Generate scenarios →" %>
      </button>
    </div>
    """
  end

  # ── Step: choose ───────────────────────────────────────────────────────
  defp choose(assigns) do
    ~H"""
    <p class="text-[11px] font-semibold tracking-wide text-[#EE6D18] uppercase mb-1">Choose your scenario</p>
    <h1 class="text-2xl font-bold text-gray-900 mb-1">Pick the challenge that excites you</h1>
    <p class="text-sm text-gray-500 mb-6">Both scenarios test the same dimensions. Choose the one where you can think most clearly.</p>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-6">
      <button :for={{s, i} <- Enum.with_index(@scenarios)} type="button" phx-click="select_scenario" phx-value-index={i}
        class={["text-left rounded-2xl border-2 p-5 transition", if(i == @selected_index, do: "border-[#EE6D18] bg-[#FFF4E7] shadow-card-soft", else: "border-gray-200 bg-white hover:border-[#F8C095]")]}>
        <div class="flex items-center justify-between mb-2">
          <span class="text-[11px] font-medium text-gray-500">{s["domain_tag"]} · {s["difficulty"]}</span>
          <span :if={i == @selected_index} class="text-[11px] font-semibold text-[#EE6D18]">✓ Selected</span>
        </div>
        <h3 class="text-lg font-bold text-gray-900 mb-1">{s["title"]}</h3>
        <p class="text-sm text-gray-600 mb-3 line-clamp-3">{s["incident"]}</p>
        <div class="flex gap-6 text-xs text-gray-500 mb-3">
          <span><span class="block text-[10px] uppercase text-gray-400">Complexity</span>{s["complexity"]}</span>
          <span><span class="block text-[10px] uppercase text-gray-400">Duration</span>{s["duration"]}</span>
        </div>
        <div class="flex flex-wrap gap-1.5">
          <span :for={sk <- (s["skills_tested"] || [])} class="text-[10px] px-2 py-0.5 rounded-full bg-[#FFF4E7] text-gray-600 border border-[#F3E7DA]">{sk}</span>
        </div>
      </button>
    </div>

    <div class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-4 flex items-center justify-between">
      <div>
        <p class="text-[10px] uppercase text-gray-400">Selected scenario</p>
        <p class="font-semibold text-gray-900">{(Enum.at(@scenarios, @selected_index) || %{})["title"]}</p>
      </div>
      <button :if={!@error} phx-click="continue" data-enter-fullscreen disabled={@loading == :start} class="px-5 py-2.5 rounded-xl text-white text-sm font-semibold disabled:opacity-50" style="background-color: #EE6D18;">
        <%= if @loading == :start, do: "Preparing…", else: "Continue assessment →" %>
      </button>
    </div>
    """
  end

  # ── Step: workspace ──────────────────────────────────────────────────────
  defp workspace(assigns) do
    assigns = assign(assigns, :scenario, assigns.session.scenario)

    ~H"""
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-xl font-bold text-gray-900">{@scenario["title"]}</h1>
      <button phx-click="change_scenario" class="text-sm px-3 py-1.5 rounded-lg border border-gray-200 text-gray-600 hover:bg-white">‹ Change scenario</button>
    </div>

    <form phx-change="update_answers" phx-submit="review">
      <div class="grid grid-cols-1 lg:grid-cols-[280px_1fr_220px] gap-5">
        <!-- Scenario reference -->
        <aside class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-5 h-fit divide-y divide-gray-100">
          <div class="pb-3">
            <p class="text-[10px] font-semibold uppercase tracking-wide text-[#EE6D18] mb-1">Scenario reference</p>
            <h2 class="text-base font-bold text-gray-900 leading-snug">{@scenario["title"]}</h2>
          </div>
          <.ref_block :if={@scenario["company_background"] not in [nil, ""]} label="Company background">{@scenario["company_background"]}</.ref_block>
          <.ref_block :if={@scenario["specific_incident"] not in [nil, ""]} label="The incident">{@scenario["specific_incident"]}</.ref_block>
          <div :if={(@scenario["business_constraints"] || []) != []} class="py-3">
            <p class="text-[10px] font-semibold uppercase tracking-wide text-gray-400 mb-1.5">Business constraints</p>
            <ul class="space-y-1">
              <li :for={c <- @scenario["business_constraints"]} class="flex gap-2 text-[13px] text-gray-600 leading-relaxed">
                <span class="text-[#EE6D18] mt-1.5 w-1 h-1 rounded-full bg-[#EE6D18] shrink-0"></span>{c}
              </li>
            </ul>
          </div>
          <.ref_block :if={@scenario["technical_context"] not in [nil, ""]} label="Technical context">{@scenario["technical_context"]}</.ref_block>
          <div :if={(@scenario["key_stakeholders"] || []) != []} class="py-3">
            <p class="text-[10px] font-semibold uppercase tracking-wide text-gray-400 mb-1.5">Key stakeholders</p>
            <div class="flex flex-wrap gap-1.5">
              <span :for={s <- @scenario["key_stakeholders"]} class="text-[11px] px-2 py-0.5 rounded-full bg-[#FFF4E7] text-gray-700 border border-[#F3E7DA]">{s}</span>
            </div>
          </div>
        </aside>

        <!-- Sections (accordion) -->
        <div class="space-y-3">
          <div :for={{q, i} <- Enum.with_index(@questions, 1)} class={["bg-white rounded-2xl border shadow-card-soft overflow-hidden transition", if(@expanded == q.key, do: "border-[#EE6D18]", else: "border-gray-200")]}>
            <button type="button" phx-click="toggle_section" phx-value-key={q.key} class="w-full flex items-center gap-3 px-4 py-3.5 text-left">
              <span class={["inline-flex w-7 h-7 rounded-full text-xs font-bold items-center justify-center shrink-0", if(word_count(@answers[q.key]) > 0, do: "bg-[#EE6D18] text-white", else: "bg-[#FFF4E7] text-[#EE6D18]")]}>{i}</span>
              <span class="flex-1 min-w-0">
                <span class="block font-semibold text-gray-900 text-[15px]">{q.title}</span>
                <span class="block text-xs text-gray-500 truncate">{q.prompt}</span>
              </span>
              <span class="text-[11px] text-gray-400 shrink-0">{word_count(@answers[q.key])} words</span>
              <.icon name="hero-chevron-down" class={["w-4 h-4 text-gray-400 shrink-0 transition-transform", @expanded == q.key && "rotate-180"]} />
            </button>
            <div class={["px-4 pb-4", @expanded != q.key && "hidden"]}>
              <textarea name={"answers[#{q.key}]"} rows="5" phx-debounce="400"
                class="w-full border border-gray-300 rounded-lg px-3 py-2.5 text-sm text-gray-800 leading-relaxed focus:ring-[#EE6D18] focus:border-[#EE6D18]"
                placeholder="Type your thinking here…">{@answers[q.key]}</textarea>
            </div>
          </div>
        </div>

        <!-- Progress -->
        <aside class="h-fit space-y-4">
          <div class="bg-gradient-to-br from-[#EE6D18] to-[#F18A42] text-white rounded-2xl p-4">
            <p class="text-[10px] uppercase opacity-80">Completion</p>
            <p class="text-2xl font-bold">{filled_count(@answers)}/7</p>
            <p class="text-xs opacity-80">sections completed</p>
          </div>
          <div class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-3">
            <p class="text-[10px] uppercase text-gray-400 mb-2">Sections</p>
            <ul class="space-y-1">
              <li :for={{q, i} <- Enum.with_index(@questions, 1)} class="flex items-center gap-2 text-xs text-gray-600">
                <span class={["w-4 h-4 rounded-full text-[9px] flex items-center justify-center", if(word_count(@answers[q.key]) > 0, do: "bg-green-500 text-white", else: "bg-gray-200 text-gray-500")]}>{i}</span>
                {q.title}
              </li>
            </ul>
          </div>
          <button type="submit" class="w-full py-3 rounded-xl text-white font-semibold" style="background-color: #EE6D18;">Review &amp; submit →</button>
        </aside>
      </div>
    </form>
    """
  end

  # ── Step: review ───────────────────────────────────────────────────────
  defp review(assigns) do
    ~H"""
    <p class="text-[11px] font-semibold tracking-wide text-[#EE6D18] uppercase mb-1">Step 3 · Review</p>
    <h1 class="text-2xl font-bold text-gray-900 mb-1">Review your response</h1>
    <p class="text-sm text-gray-500 mb-6">Take one last look. Once submitted, our AI evaluator takes it from here.</p>

    <div class="grid grid-cols-1 lg:grid-cols-[1fr_240px] gap-5">
      <div class="space-y-3">
        <div :for={{q, i} <- Enum.with_index(@questions, 1)} class="bg-white rounded-xl border border-gray-200 shadow-card-soft p-4">
          <div class="flex items-center justify-between">
            <p class="font-semibold text-gray-900"><span class="text-[#EE6D18] mr-1">{i}</span>{q.title}</p>
            <span class="text-[11px] text-gray-400">{word_count(@answers[q.key])} words</span>
          </div>
          <p class="text-sm text-gray-600 mt-1 whitespace-pre-wrap">{blank_or(@answers[q.key])}</p>
        </div>
      </div>
      <aside class="h-fit space-y-4">
        <div class="bg-gradient-to-br from-[#EE6D18] to-[#F18A42] text-white rounded-2xl p-4">
          <p class="text-[10px] uppercase opacity-80">Coverage</p>
          <p class="text-2xl font-bold">{round(filled_count(@answers) / 7 * 100)}%</p>
          <p class="text-xs opacity-80">{filled_count(@answers)} of 7 sections complete</p>
        </div>
        <button phx-click="back_to_edit" class="w-full py-2.5 rounded-xl border border-gray-200 text-sm text-gray-700 hover:bg-white">‹ Back to edit</button>
        <button phx-click="request_submit" class="w-full py-3 rounded-xl text-white font-semibold" style="background-color: #EE6D18;">Submit assessment →</button>
      </aside>
    </div>

    <div :if={@confirm_submit} class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" phx-click="cancel_submit">
      <div class="bg-white rounded-2xl shadow-2xl max-w-md w-full mx-4 p-6" phx-click-away="cancel_submit">
        <h3 class="text-lg font-bold text-gray-900 mb-2">Submit assessment?</h3>
        <p class="text-sm text-gray-600 mb-5">Once submitted, your responses cannot be edited. Our AI evaluator will review your structured thinking, technical depth, and leadership signals.</p>
        <div class="flex justify-end gap-2">
          <button phx-click="cancel_submit" class="px-4 py-2 rounded-lg border border-gray-200 text-sm text-gray-700">Keep editing</button>
          <button phx-click="submit" class="px-4 py-2 rounded-lg text-white text-sm font-semibold" style="background-color: #EE6D18;">Submit assessment →</button>
        </div>
      </div>
    </div>
    """
  end

  # ── Step: evaluating ──────────────────────────────────────────────────────
  defp evaluating(assigns) do
    ~H"""
    <div class="flex items-center justify-center py-20">
      <div class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-10 max-w-md w-full text-center">
        <div class="w-16 h-16 rounded-2xl bg-[#FFF4E7] mx-auto mb-4 flex items-center justify-center">
          <.icon name="hero-cpu-chip" class="w-8 h-8 text-[#EE6D18]" />
        </div>
        <h2 class="text-xl font-bold text-gray-900 mb-1">Evaluating your case study</h2>
        <p class="text-sm text-gray-500 mb-5">Generating recruiter insights…</p>
        <div class="h-1.5 bg-[#F3E7DA] rounded-full overflow-hidden mb-5">
          <div class="h-full bg-[#EE6D18] rounded-full animate-pulse" style="width: 70%"></div>
        </div>
        <div class="flex justify-center gap-2 text-[11px] text-gray-500">
          <span class="px-2 py-1 rounded-full bg-[#FFF4E7]">Problem Solving</span>
          <span class="px-2 py-1 rounded-full bg-[#FFF4E7]">Domain Expertise</span>
          <span class="px-2 py-1 rounded-full bg-[#FFF4E7]">Initiative</span>
        </div>
      </div>
    </div>
    """
  end

  # ── Step: results ──────────────────────────────────────────────────────
  defp results(assigns) do
    assigns =
      assigns
      |> assign(:report, assigns.session.report || %{})
      |> assign(:scenario, assigns.session.scenario)

    ~H"""
    <p class="text-[11px] font-semibold tracking-wide text-[#EE6D18] uppercase mb-1">Your AI8 evaluation</p>
    <h1 class="text-2xl font-bold text-gray-900 mb-4">Your evaluation is ready</h1>

    <div class="rounded-2xl bg-gradient-to-br from-[#EE6D18] to-[#F18A42] text-white p-6 mb-6 flex items-center justify-between">
      <div>
        <p class="text-5xl font-bold">{@session.total_score}<span class="text-2xl opacity-80">/100</span></p>
        <p class="text-sm opacity-90 mt-1">{@report["overall_verdict"]}</p>
        <p class="text-sm opacity-80 max-w-xl mt-2">{@report["summary"]}</p>
      </div>
    </div>

    <h3 class="text-sm font-bold text-gray-900 mb-3">Skill breakdown</h3>
    <div class="space-y-3 mb-8">
      <.skill_bar label="Problem Solving & Critical Thinking" value={pct(@session.problem_solving_score, 30)} />
      <.skill_bar label="Domain Expertise & Technical Skills" value={pct(@session.domain_score, 40)} />
      <.skill_bar label="Initiative & Leadership Potential" value={pct(@session.leadership_score, 30)} />
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-8">
      <div :if={is_list(@report["strengths"]) and @report["strengths"] != []} class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-5">
        <h3 class="text-sm font-bold text-gray-900 mb-2">Strengths</h3>
        <ul class="list-disc ml-5 text-sm text-gray-600 space-y-1"><li :for={s <- @report["strengths"]}>{s}</li></ul>
      </div>
      <div :if={is_list(@report["improvements"]) and @report["improvements"] != []} class="bg-white rounded-2xl border border-gray-200 shadow-card-soft p-5">
        <h3 class="text-sm font-bold text-gray-900 mb-2">Areas to improve</h3>
        <ul class="list-disc ml-5 text-sm text-gray-600 space-y-1"><li :for={i <- @report["improvements"]}>{i}</li></ul>
      </div>
    </div>

    <h3 class="text-sm font-bold text-gray-900 mb-3">Detailed feedback</h3>
    <div class="space-y-2 mb-8">
      <.feedback_row label="Domain Expertise" text={@report["domain_feedback"]} />
      <.feedback_row label="Problem Solving" text={@report["problem_solving_feedback"]} />
      <.feedback_row label="Initiative & Leadership" text={@report["leadership_feedback"]} />
    </div>

    <.error_card
      :if={@error}
      title={@error_title}
      error_message={@error}
      retry_event={@last_action || "retake"}
      class="mb-4"
    />

    <VyaasaCampusWeb.Components.Student.AssessmentFooter.assessment_footer
      next_event="back_to_dashboard"
      restart_event="retake"
      restart_label="Retake Assessment"
      dashboard_event="back_to_dashboard"
    />
    """
  end

  # ── Sub-components ────────────────────────────────────────────────────────
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp ref_block(assigns) do
    ~H"""
    <div class="py-3">
      <p class="text-[10px] font-semibold uppercase tracking-wide text-gray-400 mb-1">{@label}</p>
      <p class="text-[13px] text-gray-600 leading-relaxed">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :desc, :string, required: true

  defp eval_dim(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 shadow-card-soft p-5">
      <div class="w-9 h-9 rounded-full bg-[#FFF4E7] flex items-center justify-center mb-3">
        <.icon name="hero-sparkles" class="w-4 h-4 text-[#EE6D18]" />
      </div>
      <h4 class="font-bold text-gray-900 text-sm mb-1">{@title}</h4>
      <p class="text-xs text-gray-500">{@desc}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp skill_bar(assigns) do
    ~H"""
    <div class="bg-white rounded-xl border border-gray-100 shadow-card-soft p-4">
      <div class="flex items-center justify-between mb-1.5">
        <span class="text-sm font-semibold text-gray-800">{@label}</span>
        <span class="text-sm font-bold text-[#EE6D18]">{@value}/100</span>
      </div>
      <div class="h-2 bg-[#F3E7DA] rounded-full overflow-hidden">
        <div class="h-full bg-[#EE6D18] rounded-full" style={"width: #{@value}%"}></div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :text, :string, default: nil

  defp feedback_row(assigns) do
    ~H"""
    <div :if={@text not in [nil, ""]} class="bg-white rounded-xl border border-gray-100 shadow-card-soft p-4">
      <p class="font-semibold text-gray-900 text-sm mb-1">{@label}</p>
      <p class="text-sm text-gray-600">{@text}</p>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────────
  # Prefer the role the student picked during resume/ATS processing — that's the
  # role they're being assessed for, stored as `preferred_role` on their latest
  # ATS phase. Falls back to the profile (specialization → degree → "General")
  # when there's no ATS phase yet (or no role on it).
  defp resume_specialization(user, tenant_schema) do
    ats_role =
      case StudentAts.get_by_student_id(user.id, tenant_schema) do
        %{preferred_role: role} -> String.trim(to_string(role))
        _ -> ""
      end

    if ats_role != "", do: ats_role, else: student_specialization(user)
  end

  # Specialization comes from the student's profile (specialization → degree → fallback).
  defp student_specialization(user) do
    [Map.get(user, :specialization), Map.get(user, :degree)]
    |> Enum.map(fn v -> v |> to_string() |> String.trim() end)
    |> Enum.find("General", &(&1 != ""))
  end

  defp word_count(nil), do: 0
  defp word_count(text) when is_binary(text), do: text |> String.split(~r/\s+/, trim: true) |> length()

  defp all_answers_blank?(answers) do
    Enum.all?(Questions.keys(), fn key -> word_count(Map.get(answers, key)) == 0 end)
  end

  defp filled_count(answers), do: Enum.count(Questions.keys(), fn k -> word_count(Map.get(answers, k)) > 0 end)

  defp blank_or(text) when is_binary(text), do: if(String.trim(text) == "", do: "No response yet.", else: text)
  defp blank_or(_), do: "No response yet."

  defp pct(nil, _max), do: 0
  defp pct(score, max) when is_integer(score) and max > 0, do: round(score / max * 100) |> min(100) |> max(0)
  defp pct(_, _), do: 0

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  # Closing the tab / navigating away mid-attempt must not leave the session
  # stuck non-terminal forever. Enqueues the same finalize job the
  # abandonment sweep uses, so both share one completion path
  # (CaseStudy.force_complete/2). Guarded on connected?/1 — the disconnected
  # static-render pass would otherwise fire this on every page load.
  @impl true
  def terminate(_reason, socket) do
    with true <- connected?(socket),
         %{session_token: token} <- socket.assigns[:session],
         tenant_schema when is_binary(tenant_schema) <- socket.assigns[:tenant_schema] do
      VyaasaCampus.Jobs.AssessmentFinalizer.enqueue("case_study", token, tenant_schema)
    end

    :ok
  end
end
