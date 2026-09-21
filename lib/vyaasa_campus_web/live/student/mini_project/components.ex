defmodule VyaasaCampusWeb.Student.MiniProject.Components do
  @moduledoc """
  UI components for the Domain Mini Project LiveView — one component per phase.
  All screens match the Figma screens in /screens/.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  @phase_labels %{
    "role_assignment" => "Scenario",
    "discovery" => "Discovery",
    "implementation" => "Implementation",
    "project_submission" => "Submission",
    "viva" => "Viva",
    "reflection" => "Reflection",
    "completed" => "Report"
  }

  @phase_order ~w(role_assignment discovery implementation project_submission viva reflection completed)

  # ── Page header — breadcrumb + title + numbered stepper ───────────────────

  attr :phase, :atom, required: true
  attr :session, :any, default: nil

  def mini_project_header(assigns) do
    assigns =
      assigns
      |> assign(:phase_order, @phase_order)
      |> assign(:phase_labels, @phase_labels)

    ~H"""
    <div class="bg-white border-b border-gray-100">
      <!-- Breadcrumb + title row -->
      <div class="flex items-start justify-between gap-6 px-8 pt-6 pb-5">
        <div>
          <p class="text-[10px] font-bold tracking-[0.2em] text-orange-500 uppercase mb-1.5">
            AI8 · Applied Employability Assessment
          </p>
          <h1 class="text-[1.65rem] font-black text-gray-900 leading-tight tracking-tight">
            Domain Mini Project
          </h1>
          <p class="text-sm text-gray-500 mt-1.5 max-w-xl leading-relaxed">
            Complete a real-world industry simulation, defend your decisions,
            and turn your work into recruiter-ready evidence.
          </p>
        </div>
      </div>

      <!-- Numbered stepper (hidden on start screen) -->
      <%= if @phase not in [:start] do %>
        <% current_idx = Enum.find_index(@phase_order, &(&1 == to_string(@phase))) || 0 %>
        <div class="border-t border-gray-100 bg-gray-50/60 px-8 py-3 flex items-center overflow-x-auto">
          <%= for {step, idx} <- Enum.with_index(@phase_order) do %>
            <% is_done = idx < current_idx %>
            <% is_active = idx == current_idx %>
            <div class="flex items-center shrink-0">
              <!-- Circle + label -->
              <div class="flex items-center gap-1.5">
                <%= if is_done do %>
                  <div class="w-5.5 h-5.5 rounded-full bg-green-500 flex items-center justify-center shrink-0">
                    <.icon name="hero-check" class="w-3 h-3 text-white" />
                  </div>
                <% else %>
                  <div class={[
                    "w-5.5 h-5.5 rounded-full flex items-center justify-center shrink-0 text-[10px] font-bold",
                    is_active && "bg-orange-500 text-white",
                    not is_active && "bg-white border border-gray-300 text-gray-400"
                  ]}>
                    {idx + 1}
                  </div>
                <% end %>
                <span class={[
                  "text-[11px] font-semibold whitespace-nowrap",
                  is_active && "text-gray-900",
                  is_done && "text-gray-500",
                  not is_active and not is_done && "text-gray-400"
                ]}>
                  {Map.get(@phase_labels, step, step)}
                </span>
              </div>
              <!-- Connector line (not after last step) -->
              <%= if idx < length(@phase_order) - 1 do %>
                <div class={[
                  "mx-2.5 h-px shrink-0 w-5",
                  if(is_done, do: "bg-green-400", else: "bg-gray-200")
                ]} />
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Right-sidebar panel — step progress + active project ─────────────────

  attr :phase, :atom, required: true
  attr :session, :any, default: nil

  def step_panel(assigns) do
    phase_order_list = ~w(role_assignment discovery implementation project_submission viva reflection completed)

    phase_name_map = %{
      "role_assignment" => "Scenario",
      "discovery" => "Discovery",
      "implementation" => "Implementation",
      "project_submission" => "Submission",
      "viva" => "Viva",
      "reflection" => "Reflection",
      "completed" => "Report"
    }

    phase_str = to_string(assigns.phase)
    step_idx = (Enum.find_index(phase_order_list, &(&1 == phase_str)) || 0) + 1
    step_name = Map.get(phase_name_map, phase_str, "Getting Started")
    progress_pct = min(round(step_idx / 7 * 100), 100)

    show_countdown =
      assigns.phase in [:implementation, :project_submission] and
        assigns.session != nil and
        assigns.session.submission_deadline != nil

    deadline_ms =
      if show_countdown,
        do: DateTime.to_unix(assigns.session.submission_deadline, :millisecond),
        else: nil

    assigns =
      assigns
      |> assign(:step_idx, step_idx)
      |> assign(:step_name, step_name)
      |> assign(:progress_pct, progress_pct)
      |> assign(:show_countdown, show_countdown)
      |> assign(:deadline_ms, deadline_ms)

    ~H"""
    <div class="space-y-4 sticky top-6">
      <!-- Step progress card -->
      <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
        <div class="flex items-center justify-between mb-2">
          <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">
            Step {@step_idx} of 7
          </p>
          <p class="text-sm font-bold text-orange-500">{@progress_pct}%</p>
        </div>
        <div class="w-full bg-gray-100 rounded-full h-1.5 mb-3">
          <div
            class="bg-orange-500 h-1.5 rounded-full transition-all duration-500"
            style={"width: #{@progress_pct}%"}
          />
        </div>
        <p class="text-sm font-bold text-gray-900">{@step_name}</p>
        <p class="text-xs text-gray-400 mt-0.5">All changes saved · Autosave enabled</p>
      </div>

      <!-- Countdown timer (implementation + submission phases) -->
      <%= if @show_countdown do %>
        <div class="bg-white rounded-2xl border border-orange-100 shadow-sm p-5">
          <div class="flex items-center gap-2 mb-3">
            <.icon name="hero-clock" class="w-4 h-4 text-orange-400 shrink-0" />
            <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Time Remaining</p>
          </div>
          <span
            id="mini-project-countdown"
            phx-hook="DeadlineTimer"
            data-deadline={@deadline_ms}
            class="text-2xl font-black tabular-nums text-gray-800"
          >--:--:--</span>
          <p class="text-[10px] text-gray-400 mt-1.5">Submit before time runs out</p>
        </div>
      <% end %>

      <!-- Active project card (once scenario chosen) -->
      <%= if @session && @session.chosen_scenario do %>
        <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
          <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-2.5">
            Active Project
          </p>
          <p class="text-sm font-bold text-gray-900 leading-snug">
            {get_in(@session.chosen_scenario, ["org_name"]) || "Untitled Project"}
          </p>
          <p class="text-xs text-gray-500 mt-1 leading-relaxed">
            {get_in(@session.chosen_scenario, ["role_title"]) || ""}
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Start screen — collect specialization + JD ────────────────────────────

  attr :specialization, :string, required: true
  attr :jd, :string, required: true
  attr :skills, :string, required: true
  attr :loading, :any, default: nil

  def start_screen(assigns) do
    profile_detected = assigns.specialization != "" or assigns.jd != "" or assigns.skills != ""
    assigns = assign(assigns, :profile_detected, profile_detected)

    ~H"""
    <div class="max-w-2xl mx-auto py-10 space-y-8">
      <div class="text-center space-y-3">
        <div class="w-16 h-16 rounded-2xl bg-orange-50 flex items-center justify-center mx-auto">
          <.icon name="hero-wrench-screwdriver" class="w-8 h-8 text-orange-500" />
        </div>
        <h1 class="text-3xl font-black text-gray-900">Domain Mini Project</h1>
        <p class="text-gray-500 max-w-sm mx-auto text-sm leading-relaxed">
          A 24-hour AI-supervised internship simulation. You'll receive a project brief,
          build a solution, and be evaluated via viva and reflection.
        </p>
      </div>

      <%= if @profile_detected do %>
        <div class="bg-green-50 border border-green-200 rounded-2xl px-5 py-4 flex items-start gap-3">
          <.icon name="hero-check-circle" class="w-5 h-5 text-green-500 shrink-0 mt-0.5" />
          <div class="text-sm text-green-800">
            <p class="font-semibold">Profile detected — fields pre-filled from your profile</p>
            <p class="text-green-700 mt-0.5">Review and adjust if needed, then generate your scenarios.</p>
          </div>
        </div>
      <% end %>

      <div class="bg-white rounded-3xl border border-gray-100 shadow-sm p-8 space-y-6">
        <div>
          <label class="block text-sm font-semibold text-gray-700 mb-2">
            Your Domain / Specialization <span class="text-orange-500">*</span>
          </label>
          <input
            type="text"
            value={@specialization}
            phx-change="update_field"
            phx-value-field="specialization"
            placeholder="e.g. Data Science, Marketing Analytics, Finance, Software Engineering"
            class="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
          />
        </div>

        <div>
          <label class="block text-sm font-semibold text-gray-700 mb-2">
            Target Job Role
            <span class="text-gray-400 font-normal">(from your resume — improves scenario quality)</span>
          </label>
          <input
            type="text"
            value={@jd}
            phx-change="update_field"
            phx-value-field="jd"
            placeholder="e.g. Data Analyst, Software Engineer, Marketing Executive"
            class="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
          />
        </div>

        <div>
          <label class="block text-sm font-semibold text-gray-700 mb-2">
            Key Skills
            <span class="text-gray-400 font-normal">(from your resume)</span>
          </label>
          <input
            type="text"
            value={@skills}
            phx-change="update_field"
            phx-value-field="skills"
            placeholder="e.g. Python, SQL, Power BI, Excel"
            class="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
          />
        </div>

        <button
          phx-click="start_project"
          disabled={@loading == :generating_scenarios}
          class="w-full py-4 bg-orange-500 hover:bg-orange-600 disabled:opacity-60 text-white font-bold rounded-2xl transition-all shadow-lg shadow-orange-200 flex items-center justify-center gap-2"
        >
          <%= if @loading == :generating_scenarios do %>
            <span class="animate-spin inline-block w-5 h-5 border-2 border-white border-t-transparent rounded-full" />
            Generating your scenarios…
          <% else %>
            <.icon name="hero-arrow-right" class="w-5 h-5" />
            Generate My Project Scenarios
          <% end %>
        </button>
      </div>

      <div class="grid grid-cols-3 gap-4 text-center">
        <div class="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm">
          <p class="text-2xl font-black text-orange-500">7</p>
          <p class="text-xs text-gray-500 mt-1">Phases</p>
        </div>
        <div class="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm">
          <p class="text-2xl font-black text-orange-500">24h</p>
          <p class="text-xs text-gray-500 mt-1">Build Window</p>
        </div>
        <div class="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm">
          <p class="text-2xl font-black text-orange-500">AI</p>
          <p class="text-xs text-gray-500 mt-1">Evaluated</p>
        </div>
      </div>
    </div>
    """
  end

  # ── Phase 1 — Scenario selection ──────────────────────────────────────────

  attr :session, :any, required: true
  attr :loading, :any, default: nil

  def scenario_selection_screen(assigns) do
    ~H"""
    <div class="space-y-6 py-4">
      <!-- Step label -->
      <div>
        <p class="text-[10px] font-bold text-orange-500 uppercase tracking-[0.18em] mb-1">
          Step 1 · Scenario Selection
        </p>
        <h2 class="text-2xl font-black text-gray-900">Choose Your Mini Project</h2>
        <p class="text-sm text-gray-500 mt-1.5">
          Two scenarios have been generated based on your domain. Pick the one that excites you most.
        </p>
      </div>

      <div class="grid gap-6 sm:grid-cols-2">
        <%= for {scenario, idx} <- Enum.with_index(@session.scenario_candidates || []) do %>
          <div class="bg-white rounded-3xl border border-gray-100 shadow-sm hover:border-orange-300 hover:shadow-orange-100/60 transition-all p-7 flex flex-col gap-4">
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="text-[10px] font-bold text-orange-500 tracking-widest uppercase mb-1">
                  {scenario["org_name"]}
                </p>
                <h3 class="text-lg font-black text-gray-900 leading-tight">{scenario["role_title"]}</h3>
              </div>
              <div class="w-10 h-10 rounded-xl bg-orange-50 flex items-center justify-center shrink-0">
                <span class="text-orange-500 font-black text-sm">{idx + 1}</span>
              </div>
            </div>

            <p class="text-sm text-gray-600 leading-relaxed">{scenario["business_context"]}</p>

            <div class="bg-orange-50 rounded-2xl p-4">
              <p class="text-[10px] font-bold text-gray-700 mb-1 uppercase tracking-widest">Your Mission</p>
              <p class="text-sm text-gray-800">{scenario["objective"]}</p>
            </div>

            <div class="flex flex-wrap gap-2">
              <%= for constraint <- (scenario["constraints"] || []) |> Enum.take(3) do %>
                <span class="px-2.5 py-1 bg-gray-50 border border-gray-100 rounded-full text-[11px] text-gray-600">
                  {constraint}
                </span>
              <% end %>
            </div>

            <button
              phx-click="choose_scenario"
              phx-value-index={idx}
              disabled={@loading != nil}
              class="mt-auto w-full py-3 bg-gray-900 hover:bg-orange-500 disabled:opacity-50 text-white font-bold rounded-2xl transition-all text-sm"
            >
              Choose This Scenario
            </button>
          </div>
        <% end %>
      </div>

      <div class="bg-amber-50 border border-amber-200 rounded-2xl p-4 text-sm text-amber-800 flex gap-3">
        <.icon name="hero-information-circle" class="w-5 h-5 shrink-0 text-amber-500 mt-0.5" />
        <span>
          Once you choose a scenario, you'll enter discovery where you can ask the AI stakeholder
          up to 5 questions before getting your project brief.
        </span>
      </div>
    </div>
    """
  end

  # ── Phase 2 — Discovery chat ──────────────────────────────────────────────

  attr :session, :any, required: true
  attr :question_input, :string, required: true
  attr :loading, :any, default: nil

  def discovery_screen(assigns) do
    ~H"""
    <div class="space-y-5 py-4">
      <!-- Step label -->
      <div>
        <p class="text-[10px] font-bold text-orange-500 uppercase tracking-[0.18em] mb-1">
          Step 2 · Guided Discovery
        </p>
        <h2 class="text-xl font-black text-gray-900">Understand the problem with your AI mentor</h2>
        <p class="text-sm text-gray-500 mt-1">
          Ask the AI stakeholder up to 5 questions to uncover what you need to know.
          Good questions unlock hidden project details.
        </p>
      </div>

      <!-- Question counter -->
      <div class="flex items-center justify-between bg-white rounded-2xl border border-gray-100 shadow-sm px-5 py-3">
        <div class="flex items-center gap-2">
          <div class="w-8 h-8 rounded-full bg-orange-500 flex items-center justify-center shrink-0">
            <.icon name="hero-chat-bubble-left-right" class="w-4 h-4 text-white" />
          </div>
          <div>
            <p class="text-xs font-bold text-gray-700">VYAASA Project Mentor</p>
            <p class="text-[10px] text-gray-400">Guiding your discovery</p>
          </div>
        </div>
        <div class="text-right">
          <p class="text-sm font-black text-orange-500">
            Question {question_number(@session)} of 5
          </p>
        </div>
      </div>

      <!-- Scenario context card -->
      <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
        <p class="text-[10px] font-bold text-orange-500 tracking-widest uppercase mb-2">Your Scenario</p>
        <p class="font-bold text-gray-900">
          {get_in(@session.chosen_scenario, ["org_name"])} — {get_in(@session.chosen_scenario, ["role_title"])}
        </p>
        <p class="text-sm text-gray-600 mt-1">{get_in(@session.chosen_scenario, ["objective"])}</p>
      </div>

      <!-- Chat thread -->
      <div class="space-y-3 max-h-80 overflow-y-auto bg-white rounded-2xl border border-gray-100 shadow-sm p-4">
        <%= if Enum.empty?(@session.discovery_messages || []) do %>
          <div class="flex justify-start">
            <div class="bg-gray-50 border border-gray-100 rounded-2xl px-4 py-3 text-sm text-gray-600 max-w-[85%] rounded-bl-sm">
              <p class="text-[10px] font-bold text-orange-500 mb-1">Stakeholder</p>
              <p>Let's understand the business problem. What challenge are you trying to solve?</p>
            </div>
          </div>
        <% end %>
        <%= for msg <- @session.discovery_messages || [] do %>
          <.discovery_bubble message={msg} />
        <% end %>
        <%= if @loading == :asking do %>
          <div class="flex justify-start">
            <div class="bg-gray-50 border border-gray-100 rounded-2xl px-4 py-3 flex gap-1.5 items-center">
              <span class="animate-bounce inline-block w-1.5 h-1.5 bg-gray-400 rounded-full" />
              <span class="animate-bounce inline-block w-1.5 h-1.5 bg-gray-400 rounded-full [animation-delay:0.1s]" />
              <span class="animate-bounce inline-block w-1.5 h-1.5 bg-gray-400 rounded-full [animation-delay:0.2s]" />
            </div>
          </div>
        <% end %>
      </div>

      <!-- Input -->
      <%= if question_number(@session) < 5 do %>
        <form phx-change="update_question" phx-submit="ask_question" class="bg-white rounded-2xl border border-gray-200 shadow-sm p-4 flex gap-3">
          <input
            type="text"
            name="value"
            value={@question_input}
            placeholder="Type your response…"
            disabled={@loading != nil}
            class="flex-1 text-sm focus:outline-none bg-transparent placeholder-gray-400"
          />
          <button
            type="submit"
            disabled={@loading != nil or String.trim(@question_input) == ""}
            class="px-4 py-2 bg-orange-500 hover:bg-orange-600 disabled:opacity-50 text-white font-bold rounded-xl transition-all text-sm"
          >
            Ask
          </button>
        </form>
      <% end %>

      <!-- Finish discovery -->
      <button
        phx-click="finish_discovery"
        disabled={@loading != nil}
        class="w-full py-4 bg-gray-900 hover:bg-orange-500 disabled:opacity-60 text-white font-bold rounded-2xl transition-all shadow-sm flex items-center justify-center gap-2"
      >
        <%= if @loading == :generating_brief do %>
          <span class="animate-spin inline-block w-5 h-5 border-2 border-white border-t-transparent rounded-full" />
          Generating your project brief…
        <% else %>
          <.icon name="hero-document-arrow-down" class="w-5 h-5" />
          I'm Done — Get My Project Brief
        <% end %>
      </button>
    </div>
    """
  end

  attr :message, :map, required: true

  defp discovery_bubble(assigns) do
    is_student = assigns.message["sender"] == "student"
    assigns = assign(assigns, :is_student, is_student)

    ~H"""
    <div class={["flex", if(@is_student, do: "justify-end", else: "justify-start")]}>
      <div class={[
        "max-w-[85%] rounded-2xl px-4 py-3 text-sm",
        if(@is_student,
          do: "bg-orange-500 text-white rounded-br-sm",
          else: "bg-gray-50 border border-gray-100 text-gray-800 rounded-bl-sm"
        )
      ]}>
        <%= unless @is_student do %>
          <p class="text-[10px] font-bold text-orange-500 mb-1">{@message["role"] || "Stakeholder"}</p>
        <% end %>
        <p class="leading-relaxed">{@message["content"]}</p>
      </div>
    </div>
    """
  end

  defp question_number(session),
    do: Enum.count(session.discovery_messages || [], &(&1["sender"] == "student"))

  # ── Phase 3 — Implementation (download brief) ─────────────────────────────

  attr :session, :any, required: true

  def implementation_screen(assigns) do
    ~H"""
    <div class="space-y-8 py-4">
      <!-- Step label -->
      <div>
        <p class="text-[10px] font-bold text-orange-500 uppercase tracking-[0.18em] mb-1">
          Step 3 · Project Brief
        </p>
        <h2 class="text-2xl font-black text-gray-900">Your Industry Project Brief</h2>
        <p class="text-sm text-gray-500 mt-1.5">
          Read the full brief, build your solution offline, and come back to submit within 24 hours.
        </p>
      </div>

      <!-- Project header card -->
      <div class="bg-gray-900 rounded-3xl p-7 text-white">
        <p class="text-[10px] font-bold text-orange-400 uppercase tracking-widest mb-2">
          {get_in(@session.chosen_scenario, ["org_name"])}
        </p>
        <h3 class="text-xl font-black leading-snug">
          {get_in(@session.chosen_scenario, ["role_title"])}
        </h3>
        <p class="text-sm text-gray-300 mt-2 leading-relaxed">
          {get_in(@session.chosen_scenario, ["business_context"])}
        </p>
      </div>

      <!-- Brief content -->
      <div class="bg-white rounded-3xl border border-gray-100 shadow-sm p-8">
        <pre class="whitespace-pre-wrap text-sm text-gray-700 font-sans leading-relaxed">{@session.brief_markdown}</pre>
      </div>

      <!-- Actions -->
      <div class="flex flex-col sm:flex-row gap-4">
        <button
          phx-click="download_brief"
          class="flex-1 py-3.5 border-2 border-orange-500 text-orange-500 hover:bg-orange-50 font-bold rounded-2xl transition-all text-center text-sm flex items-center justify-center gap-2"
        >
          <.icon name="hero-arrow-down-tray" class="w-5 h-5" />
          Download Brief
        </button>

        <button
          phx-click="proceed_to_submission"
          class="flex-1 py-3.5 bg-orange-500 hover:bg-orange-600 text-white font-bold rounded-2xl transition-all shadow-lg shadow-orange-200/50 text-sm flex items-center justify-center gap-2"
        >
          <.icon name="hero-arrow-right" class="w-5 h-5" />
          I've Built It — Submit My Project
        </button>
      </div>

      <div class="bg-blue-50 border border-blue-100 rounded-2xl p-4 text-sm text-blue-700 flex gap-3">
        <.icon name="hero-clock" class="w-5 h-5 shrink-0 text-blue-400 mt-0.5" />
        <span>You have 24 hours to build and submit. You can leave and come back — your session is saved.</span>
      </div>
    </div>
    """
  end

  # ── Phase 4 — Project Submission (document / ZIP upload) ─────────────────

  attr :session, :any, required: true
  attr :uploads, :any, required: true
  attr :github_url, :string, default: ""
  attr :loading, :any, default: nil
  attr :upload_error, :string, default: nil

  def submission_screen(assigns) do
    entries = assigns.uploads.deliverable.entries
    has_repo = String.trim(assigns.github_url || "") != ""
    assigns = assign(assigns, entries: entries, has_files: entries != [], has_repo: has_repo, ready: entries != [] or has_repo)

    ~H"""
    <div class="space-y-6 py-4">
      <!-- Step label -->
      <div>
        <p class="text-[10px] font-bold text-orange-500 uppercase tracking-[0.18em] mb-1">
          Step 4 · Submit Your Evidence
        </p>
        <h2 class="text-2xl font-black text-gray-900">Project Submission</h2>
        <p class="text-sm text-gray-500 mt-1.5">
          Upload your finished work as files — PDF, Word (DOCX), PowerPoint (PPTX), or a ZIP of your project. You can attach up to 5 files (20&nbsp;MB each).
        </p>
      </div>

      <%= if @upload_error do %>
        <div class="bg-red-50 border border-red-200 rounded-2xl px-4 py-3 text-sm text-red-700">
          {@upload_error}
        </div>
      <% end %>

      <!-- Project context -->
      <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
        <p class="text-[10px] font-bold text-gray-400 uppercase tracking-widest mb-1">Your Project</p>
        <p class="text-base font-black text-gray-900">
          {get_in(@session.chosen_scenario, ["org_name"]) || "Your Project"}
        </p>
        <p class="text-sm text-gray-500 mt-0.5">
          {get_in(@session.chosen_scenario, ["role_title"]) || ""}
        </p>
      </div>

      <!-- File upload -->
      <form id="mp-upload-form" phx-change="validate_upload" phx-submit="finalize_submission"
            class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6 space-y-4">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-xl flex items-center justify-center shrink-0 bg-orange-500">
            <.icon name="hero-document-arrow-up" class="w-5 h-5 text-white" />
          </div>
          <div>
            <p class="text-sm font-bold text-gray-900">Deliverable Files</p>
            <p class="text-xs text-gray-500">PDF, DOCX, PPTX, ZIP, or text/code files</p>
          </div>
        </div>

        <!-- Dropzone -->
        <label
          phx-drop-target={@uploads.deliverable.ref}
          class="flex flex-col items-center justify-center gap-1 border-2 border-dashed border-gray-200 rounded-xl px-4 py-8 text-center cursor-pointer hover:border-orange-300 hover:bg-orange-50/30 transition"
        >
          <.icon name="hero-arrow-up-tray" class="w-7 h-7 text-gray-400" />
          <p class="text-sm text-gray-600 font-medium">Click to choose files or drag &amp; drop</p>
          <p class="text-xs text-gray-400">Up to 5 files · 20 MB each</p>
          <.live_file_input upload={@uploads.deliverable} class="hidden" />
        </label>

        <!-- Selected files -->
        <div :if={@entries != []} class="space-y-2">
          <div :for={entry <- @entries} class="rounded-xl border border-gray-100 bg-gray-50/60 px-4 py-3">
            <div class="flex items-center justify-between gap-3">
              <div class="flex items-center gap-2 min-w-0">
                <.icon name="hero-document" class="w-4 h-4 text-gray-400 shrink-0" />
                <span class="text-sm text-gray-800 truncate">{entry.client_name}</span>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <span class="text-xs font-semibold text-orange-500 tabular-nums">{entry.progress}%</span>
                <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref}
                  class="text-gray-400 hover:text-red-500" aria-label="Remove">
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
            </div>
            <div class="mt-2 w-full bg-gray-200 rounded-full h-1">
              <div class="bg-orange-500 h-1 rounded-full transition-all" style={"width: #{entry.progress}%"} />
            </div>
            <p :for={err <- upload_errors(@uploads.deliverable, entry)} class="mt-1 text-xs text-red-600">
              {upload_error_text(err)}
            </p>
          </div>
        </div>

        <p :for={err <- upload_errors(@uploads.deliverable)} class="text-xs text-red-600 flex items-center gap-1.5">
          <.icon name="hero-exclamation-circle" class="w-3.5 h-3.5" />{upload_error_text(err)}
        </p>

        <!-- Optional: GitHub repo (enables commit-history authenticity checks) -->
        <div class="pt-2 border-t border-gray-100">
          <label class="flex items-center gap-2 text-sm font-semibold text-gray-700 mb-1.5">
            <.icon name="hero-code-bracket" class="w-4 h-4 text-gray-400" /> GitHub repository
            <span class="text-xs font-normal text-gray-400">(optional — for code projects)</span>
          </label>
          <input type="url" name="github_url" value={@github_url}
            placeholder="https://github.com/your-username/your-project"
            class="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          <p class="text-[11px] text-gray-400 mt-1">Linking a repo lets us verify your commit history — build it incrementally, don't paste a finished project.</p>
        </div>

        <!-- Readiness bar -->
        <div class="pt-1">
          <div class="flex items-center justify-between mb-2">
            <div class="flex items-center gap-2">
              <.icon name="hero-shield-check" class="w-4 h-4 text-gray-400" />
              <p class="text-sm font-semibold text-gray-700">Submission Readiness</p>
            </div>
            <p class="text-sm font-bold text-orange-500">{if @ready, do: "100%", else: "0%"}</p>
          </div>
          <div class="w-full bg-gray-100 rounded-full h-1.5">
            <div class="bg-orange-500 rounded-full h-1.5 transition-all" style={if @ready, do: "width: 100%", else: "width: 0%"} />
          </div>
          <p class="text-xs text-gray-400 mt-2">
            {cond do
              @has_files and @has_repo -> "#{length(@entries)} file(s) + repo attached — ready to submit"
              @has_files -> "#{length(@entries)} file(s) attached — ready to submit"
              @has_repo -> "Repo linked — ready to submit"
              true -> "Attach a file or link a repo to proceed"
            end}
          </p>
        </div>

        <button
          type="submit"
          disabled={@loading != nil or not @ready}
          class="w-full py-4 bg-orange-500 hover:bg-orange-600 disabled:opacity-50 disabled:cursor-not-allowed text-white font-bold rounded-2xl transition-all shadow-lg shadow-orange-200/50 flex items-center justify-center gap-2"
        >
          <%= if @loading == :generating_viva do %>
            <span class="animate-spin inline-block w-5 h-5 border-2 border-white border-t-transparent rounded-full" />
            Uploading &amp; preparing your viva…
          <% else %>
            Submit for evaluation →
          <% end %>
        </button>
      </form>
    </div>
    """
  end

  defp upload_error_text(:too_large), do: "File is too large (max 20 MB)."
  defp upload_error_text(:too_many_files), do: "Too many files (max 5)."
  defp upload_error_text(:not_accepted), do: "Unsupported file type (use PDF, DOCX, PPTX, ZIP, or text/code)."
  defp upload_error_text(other), do: "Upload error: #{inspect(other)}"

  # ── Phase 5 — Viva ───────────────────────────────────────────────────────

  attr :session, :any, required: true
  attr :answer_input, :string, required: true
  attr :loading, :any, default: nil

  def viva_screen(assigns) do
    answered = Enum.filter(assigns.session.viva_turns || [], &is_binary(&1["answer"]))
    pending = Enum.find(assigns.session.viva_turns || [], &is_nil(&1["answer"]))
    current_num = length(answered) + 1

    assigns =
      assigns
      |> assign(:answered_turns, answered)
      |> assign(:pending_turn, pending)
      |> assign(:current_num, current_num)

    ~H"""
    <div class="space-y-6 py-4">
      <!-- Step label -->
      <div>
        <p class="text-[10px] font-bold text-orange-500 uppercase tracking-[0.18em] mb-1">
          Step 5 · Project Defence
        </p>
        <h2 class="text-2xl font-black text-gray-900">Viva</h2>
        <p class="text-sm text-gray-500 mt-1.5">
          Questions are generated from your project to assess ownership, decisions, tradeoffs, and future thinking.
        </p>
      </div>

      <!-- Question counter pill -->
      <div class="flex items-center justify-between">
        <div class="inline-flex items-center gap-2 bg-orange-50 border border-orange-200 rounded-full px-4 py-2">
          <span class="text-xs font-bold text-orange-600">
            Question {@current_num} of 5
          </span>
        </div>
        <p class="text-xs text-gray-400">AI-generated from your project</p>
      </div>

      <!-- Progress bar -->
      <div class="w-full bg-gray-100 rounded-full h-1.5">
        <div
          class="bg-orange-500 rounded-full h-1.5 transition-all"
          style={"width: #{(@current_num - 1) * 20}%"}
        />
      </div>

      <!-- Previous Q&A (collapsed) -->
      <%= for turn <- @answered_turns do %>
        <div class="bg-gray-50 rounded-2xl border border-gray-100 p-5 space-y-3">
          <div class="flex items-start gap-3">
            <span class="shrink-0 w-5 h-5 rounded-full bg-green-500 flex items-center justify-center">
              <.icon name="hero-check" class="w-3 h-3 text-white" />
            </span>
            <p class="text-sm text-gray-700 font-medium">{turn["question"]}</p>
          </div>
          <div class="ml-8 bg-white rounded-xl p-3 border border-gray-100">
            <p class="text-sm text-gray-600">{turn["answer"]}</p>
            <div class="flex items-center gap-2 mt-2">
              <span class={[
                "text-xs font-bold px-2 py-0.5 rounded-full",
                score_color_class(turn["answer_score"])
              ]}>
                {turn["answer_score"]}/10
              </span>
              <span class="text-xs text-gray-400">{turn["answer_note"]}</span>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Current question -->
      <%= if @pending_turn do %>
        <div class="bg-white rounded-3xl border border-orange-100 shadow-sm p-8 space-y-5">
          <p class="text-xl font-black text-gray-900 leading-snug">{@pending_turn["question"]}</p>

          <form phx-change="update_viva_answer">
            <textarea
              name="value"
              placeholder="Type your answer here… Be specific and refer to what you actually built."
              rows="5"
              disabled={@loading != nil}
              class="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 resize-none"
            >{@answer_input}</textarea>
          </form>

          <div class="flex items-center justify-between">
            <button class="text-sm text-gray-400 hover:text-gray-600 flex items-center gap-1.5">
              <.icon name="hero-microphone" class="w-4 h-4" />
              Voice answer
            </button>

            <div class="flex items-center gap-3">
              <%!-- <%= if length(@answered_turns) > 0 do %>
                <button class="text-sm text-gray-500 hover:text-gray-700">← Previous</button>
              <% end %> --%>
              <button
                phx-click="submit_viva_answer"
                disabled={@loading != nil or String.trim(@answer_input) == ""}
                class="px-6 py-2.5 bg-orange-500 hover:bg-orange-600 disabled:opacity-50 text-white font-bold rounded-xl transition-all text-sm flex items-center gap-1.5"
              >
                <%= if @loading == :scoring_answer do %>
                  <span class="animate-spin inline-block w-4 h-4 border-2 border-white border-t-transparent rounded-full" />
                  Saving…
                <% else %>
                  Next →
                <% end %>
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp score_color_class(score) when is_integer(score) and score >= 8, do: "bg-green-100 text-green-700"
  defp score_color_class(score) when is_integer(score) and score >= 6, do: "bg-yellow-100 text-yellow-700"
  defp score_color_class(_), do: "bg-red-100 text-red-700"

  # ── Phase 6 — Reflection ──────────────────────────────────────────────────

  attr :inputs, :map, required: true
  attr :loading, :any, default: nil

  def reflection_screen(assigns) do
    ~H"""
    <div class="space-y-6 py-4">
      <!-- Step label -->
      <div>
        <p class="text-[10px] font-bold text-orange-500 uppercase tracking-[0.18em] mb-1">
          Step 6 · Growth Reflection
        </p>
        <h2 class="text-2xl font-black text-gray-900">Reflect on the experience</h2>
        <p class="text-sm text-gray-500 mt-1.5">
          Capture what changed in your thinking. Your responses help translate project work into career growth.
        </p>
      </div>

      <!-- 2x2 reflection grid -->
      <div class="grid sm:grid-cols-2 gap-4">
        <.reflection_field
          label="What did you learn?"
          field="learned"
          value={@inputs["learned"]}
          placeholder="Share a specific insight…"
        />
        <.reflection_field
          label="What was your biggest challenge?"
          field="challenges"
          value={@inputs["challenges"]}
          placeholder="Share a specific insight…"
        />
        <.reflection_field
          label="What would you improve?"
          field="improve"
          value={@inputs["improve"]}
          placeholder="Share a specific insight…"
        />
        <.reflection_field
          label="How has your confidence changed?"
          field="confidence"
          value={@inputs["confidence"]}
          placeholder="Share a specific insight…"
        />
      </div>

      <p class="text-xs text-gray-400">Auto save enabled</p>

      <button
        phx-click="submit_reflection"
        disabled={@loading != nil}
        class="w-full py-4 bg-orange-500 hover:bg-orange-600 disabled:opacity-60 text-white font-bold rounded-2xl transition-all shadow-lg shadow-orange-200/50 flex items-center justify-center gap-2"
      >
        <%= if @loading == :evaluating do %>
          <span class="animate-spin inline-block w-5 h-5 border-2 border-white border-t-transparent rounded-full" />
          AI is evaluating your project…
        <% else %>
          Generate report →
        <% end %>
      </button>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, required: true
  attr :placeholder, :string, default: ""

  defp reflection_field(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
      <label class="block text-sm font-semibold text-gray-800 mb-3">{@label}</label>
      <form phx-change="update_reflection" phx-value-field={@field}>
        <textarea
          name="value"
          placeholder={@placeholder}
          rows="4"
          class="w-full text-sm text-gray-700 placeholder-gray-300 bg-transparent focus:outline-none resize-none"
        >{@value}</textarea>
      </form>
    </div>
    """
  end

  # ── Time Expired screen ───────────────────────────────────────────────────

  attr :session, :any, required: true

  def expired_screen(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-16 text-center space-y-8">
      <!-- Icon -->
      <div class="w-24 h-24 rounded-full bg-red-50 flex items-center justify-center mx-auto">
        <.icon name="hero-clock" class="w-12 h-12 text-red-400" />
      </div>

      <!-- Heading -->
      <div class="space-y-2">
        <h2 class="text-3xl font-black text-gray-900">Time's Up</h2>
        <p class="text-gray-500 text-base leading-relaxed max-w-sm mx-auto">
          The 24-hour submission window for this project has closed.
          Your session has been recorded.
        </p>
      </div>

      <!-- What they were working on -->
      <%= if @session && @session.chosen_scenario do %>
        <div class="bg-gray-50 border border-gray-100 rounded-2xl p-6 text-left space-y-3 max-w-md mx-auto">
          <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Your Project</p>
          <p class="text-base font-bold text-gray-900">
            {get_in(@session.chosen_scenario, ["role_title"]) || "Project"}
          </p>
          <p class="text-sm text-gray-500">
            {get_in(@session.chosen_scenario, ["org_name"]) || ""}
          </p>
        </div>
      <% end %>

      <!-- Note -->
      <div class="bg-orange-50 border border-orange-100 rounded-2xl p-5 text-sm text-orange-700 max-w-md mx-auto flex gap-3 items-start text-left">
        <.icon name="hero-light-bulb" class="w-5 h-5 shrink-0 mt-0.5" />
        <span>
          Practice builds confidence. You can start a fresh project at any time —
          your next attempt will be scored normally.
        </span>
      </div>

      <button
        phx-click="start_new"
        class="px-8 py-3.5 bg-orange-500 hover:bg-orange-600 text-white font-bold rounded-2xl transition-all shadow-lg shadow-orange-200/50 text-sm"
      >
        Start a New Project
      </button>
    </div>
    """
  end

  # ── Phase 7 — Report (Completed) ─────────────────────────────────────────

  attr :session, :any, required: true

  def report_screen(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto space-y-8 py-4">
      <!-- Grade badge + score hero -->
      <div class="flex items-start gap-6">
        <div class="flex-1">
          <div class="inline-flex items-center gap-2 bg-green-100 text-green-700 rounded-full px-4 py-1.5 mb-3">
            <.icon name="hero-check-circle" class="w-4 h-4" />
            <span class="text-xs font-bold">Project Ready</span>
          </div>
          <h2 class="text-3xl font-black text-gray-900">
            {get_in(@session, [Access.key(:chosen_scenario), "role_title"]) || "Your Project"}
          </h2>
        </div>
        <div class="text-right shrink-0">
          <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-1">Mini Project Score</p>
          <p class="text-7xl font-black text-orange-500 leading-none">{@session.final_score || "–"}</p>
        </div>
      </div>

      <!-- Evaluation dimensions -->
      <div class="bg-white rounded-3xl border border-gray-100 shadow-sm p-7 space-y-4">
        <p class="text-[10px] font-bold text-gray-400 uppercase tracking-widest">Evaluation Dimensions</p>

        <.index_bar label="Domain Knowledge & Technical Skills" score={@session.domain_index} weight={56} />
        <.index_bar label="Collaboration & Teamwork" score={@session.collaboration_index} weight={22} />
        <.index_bar label="Initiative & Leadership" score={@session.initiative_index} weight={22} />
      </div>

      <!-- Grade band -->
      <%= if @session.grade_band do %>
        <div class="bg-orange-50 border border-orange-100 rounded-2xl p-5">
          <p class="text-[10px] font-bold text-orange-500 uppercase tracking-widest mb-1">Grade</p>
          <p class="text-lg font-black text-gray-900">{@session.grade_band}</p>
        </div>
      <% end %>

      <!-- Strengths + Improvements -->
      <div class="grid sm:grid-cols-2 gap-6">
        <div class="bg-white rounded-3xl border border-gray-100 shadow-sm p-6 space-y-3">
          <p class="text-sm font-bold text-gray-700 flex items-center gap-2">
            <.icon name="hero-check-circle" class="w-4 h-4 text-green-500" />
            Strengths
          </p>
          <ul class="space-y-2">
            <%= for strength <- @session.strengths || [] do %>
              <li class="text-sm text-gray-700 flex gap-2">
                <span class="text-green-500 mt-0.5 shrink-0">•</span>
                <span>{strength}</span>
              </li>
            <% end %>
          </ul>
        </div>

        <div class="bg-white rounded-3xl border border-gray-100 shadow-sm p-6 space-y-3">
          <p class="text-sm font-bold text-gray-700 flex items-center gap-2">
            <.icon name="hero-arrow-trending-up" class="w-4 h-4 text-amber-500" />
            Areas to Improve
          </p>
          <ul class="space-y-2">
            <%= for improvement <- @session.improvements || [] do %>
              <li class="text-sm text-gray-700 flex gap-2">
                <span class="text-amber-500 mt-0.5 shrink-0">•</span>
                <span>{improvement}</span>
              </li>
            <% end %>
          </ul>
        </div>
      </div>

      <!-- Full report markdown -->
      <%= if @session.report_markdown do %>
        <div class="bg-white rounded-3xl border border-gray-100 shadow-sm p-8">
          <pre class="whitespace-pre-wrap text-sm text-gray-700 font-sans leading-relaxed">{@session.report_markdown}</pre>
        </div>
      <% end %>

      <!-- Criteria detail -->
      <%= if (@session.criteria || []) != [] do %>
        <div class="bg-white rounded-3xl border border-gray-100 shadow-sm p-7 space-y-4">
          <p class="text-[10px] font-bold text-gray-400 uppercase tracking-widest">Criteria Scores</p>
          <%= for criterion <- @session.criteria do %>
            <div class="flex items-center gap-4">
              <div class="flex-1 min-w-0">
                <p class="text-xs font-semibold text-gray-700 truncate">{criterion["label"]}</p>
                <div class="w-full bg-gray-100 rounded-full h-1.5 mt-1">
                  <div
                    class="bg-orange-500 h-1.5 rounded-full"
                    style={"width: #{(criterion["score"] || 0) * 10}%"}
                  />
                </div>
                <p class="text-xs text-gray-400 mt-0.5">{criterion["justification"]}</p>
              </div>
              <div class={["text-sm font-bold px-2.5 py-1 rounded-full shrink-0 ml-2", score_color_class(criterion["score"])]}>
                {criterion["score"]}/10
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <div class="flex flex-col sm:flex-row gap-3">
        <button
          phx-click="resend_report"
          class="flex-1 py-4 bg-orange-500 hover:bg-orange-600 text-white font-bold rounded-2xl transition-all text-sm"
        >
          ✉️ Email me the report
        </button>
        <button
          phx-click="start_new"
          class="flex-1 py-4 border-2 border-gray-200 text-gray-600 hover:border-orange-400 hover:text-orange-500 font-bold rounded-2xl transition-all text-sm"
        >
          Start a New Mini Project
        </button>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :score, :integer, default: nil
  attr :weight, :integer, required: true

  defp index_bar(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm font-semibold text-gray-800">{@label}</p>
          <p class="text-xs text-gray-400">Weight: {@weight}%</p>
        </div>
        <p class="text-lg font-black text-orange-500 ml-4">{@score || "–"}</p>
      </div>
      <div class="w-full bg-gray-100 rounded-full h-2">
        <div
          class="bg-orange-500 rounded-full h-2 transition-all"
          style={"width: #{@score || 0}%"}
        />
      </div>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp format_bytes(nil), do: "unknown size"
  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
