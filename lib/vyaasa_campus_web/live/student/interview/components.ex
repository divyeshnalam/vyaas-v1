defmodule VyaasaCampusWeb.Student.Interview.Components do
  @moduledoc """
  UI components for the Interactive Session (AI-Led Resume Interview).
  Matches the new "calm coaching" Figma design.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Student.MicGate, only: [mic_status: 1]
  import VyaasaCampusWeb.Components.Student.VoiceTranscript

  # ── 8-Step Stepper ──────────────────────────────────────────────────
  # INSTRUCTIONS → PRACTICE → QUESTION 1..5 → INSIGHTS

  attr :current_step, :atom, required: true
  attr :current_question_number, :integer, default: 0
  attr :total_questions, :integer, default: 5
  attr :interview_phase, :atom, default: :welcome

  def interview_stepper(assigns) do
    total_q = max(assigns.total_questions, 5)
    steps = stepper_steps(total_q)

    active_idx =
      active_step_index(assigns.current_step, assigns.current_question_number, assigns.interview_phase, total_q)

    assigns = assign(assigns, steps: steps, active_idx: active_idx)

    ~H"""
    <div class="flex items-center justify-center mb-8 overflow-x-auto">
      <div class="flex items-center min-w-max">
        <%= for {step, idx} <- Enum.with_index(@steps) do %>
          <div class="flex flex-col items-center">
            <div class={[
              "w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold",
              stepper_circle_class(idx, @active_idx)
            ]}
              style={stepper_circle_style(idx, @active_idx)}
            >
              <%= if idx < @active_idx do %>
                ✓
              <% else %>
                {step.number}
              <% end %>
            </div>
            <span
              class={[
                "text-[10px] font-semibold tracking-[0.12em] uppercase mt-2 whitespace-nowrap",
                stepper_label_class(idx, @active_idx)
              ]}
              style={stepper_label_active_style(idx, @active_idx)}
            >{step.label}</span>
          </div>

          <%= if idx < length(@steps) - 1 do %>
            <div class={[
              "h-0.5 w-8 lg:w-12 mx-1 mt-[-22px]",
              if(idx < @active_idx, do: "bg-green-500", else: "bg-gray-200")
            ]}></div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp stepper_steps(_total_q) do
    [
      %{number: 1, label: "Instructions"},
      %{number: 2, label: "In Progress"},
      %{number: 3, label: "Insights"}
    ]
  end

  defp active_step_index(:initialize, _, _, _), do: 0
  defp active_step_index(:interview, _q_num, _phase, _total), do: 1
  defp active_step_index(:results, _, _, _), do: 2
  defp active_step_index(_, _, _, _), do: 0

  defp stepper_circle_class(idx, active_idx) do
    cond do
      idx < active_idx -> "text-white"
      idx == active_idx -> "text-white"
      true -> "text-gray-500 border border-gray-200 bg-cream-100"
    end
  end

  defp stepper_circle_style(idx, active_idx) do
    cond do
      idx < active_idx -> "background-color: #22C55E;"
      idx == active_idx -> "background-color: #FF8B00;"
      true -> ""
    end
  end

  defp stepper_label_class(idx, active_idx) do
    cond do
      idx < active_idx -> "text-gray-500"
      idx == active_idx -> ""
      true -> "text-gray-400"
    end
  end

  defp stepper_label_active_style(idx, active_idx) do
    if idx == active_idx, do: "color: #FF8B00;", else: ""
  end

  # ── Step 1: Welcome / Instructions ─────────────────────────────────

  attr :resume_info, :map, required: true
  attr :interview_phase, :atom, required: true
  attr :loading, :atom, default: nil
  attr :error, :string, default: nil
  attr :greeting_text, :string, default: nil
  attr :mic_verified, :boolean, default: false
  attr :mic_permission, :string, default: nil
  attr :mic_checking, :boolean, default: false

  def initialize_step(assigns) do
    ~H"""
    <%= cond do %>
      <% @loading in [:indexing, :initializing] -> %>
        <.indexing_card resume_info={@resume_info} />

      <% @interview_phase == :ready -> %>
        <.ready_card
          resume_info={@resume_info}
          greeting_text={@greeting_text}
          mic_verified={@mic_verified}
          mic_permission={@mic_permission}
          mic_checking={@mic_checking}
        />

      <% true -> %>
        <.welcome_card resume_info={@resume_info} />
    <% end %>
    """
  end

  attr :resume_info, :map, required: true

  defp welcome_card(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <div class="lg:col-span-2 bg-white rounded-2xl border border-gray-100 p-6">
        <span class="inline-block text-[11px] font-semibold px-2.5 py-1 rounded-full mb-3"
          style="background-color: #FFE9D2; color: #B85F00;">Welcome 👋</span>
        <h2 class="text-xl font-bold text-gray-900 mb-1">Let's get you interview-ready.</h2>
        <p class="text-sm text-gray-500 mb-5">Based on your resume you'll answer 5 friendly questions. We'll listen, learn, and share supportive insights — no scoring against others.</p>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 mb-6">
          <.meta_pill icon="hero-clock" label="60-90 sec per answer" />
          <.meta_pill icon="hero-ear" label="Vyaasa listening" />
          <.meta_pill icon="hero-clock" label="~20 minutes total" />
          <.meta_pill icon="hero-sparkles" label="Clarity + Confidence" />
          <.meta_pill icon="hero-light-bulb" label="Personalized tips" />
          <.meta_pill icon="hero-trophy" label="Earn growth XP" />
        </div>

        <%= if @resume_info && @resume_info.filename do %>
          <div class="flex items-center gap-3">
            <%!-- No `data-enter-fullscreen` on this one: the mic check runs
            first, and browsers suppress the permission prompt in full screen.
            "Continue to Interview" enters full screen once the mic is known
            good. --%>
            <button
              phx-click="start_interview"
              class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold transition"
              style="background-color: #FF8B00;"
            >
              ▶ Start Interview
            </button>
            <button
              phx-click="back_to_dashboard"
              class="px-4 py-2.5 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition"
            >
              Back to Dashboard
            </button>
          </div>
        <% else %>
          <div class="rounded-xl p-4 text-sm" style="background-color: #FEF2F2; color: #991B1B; border: 1px solid #FECACA;">
            No resume on file yet. Please complete your profile and upload a resume first.
          </div>
        <% end %>
      </div>

      <div class="space-y-4">
        <div class="rounded-2xl border border-cream-200 p-4" style="background-color: #FFF1DE;">
          <div class="flex items-start gap-2 mb-1">
            <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5" style="color: #B85F00;" />
            <p class="text-sm font-semibold text-gray-800">Tip from your Vyaasa Coach</p>
          </div>
          <p class="text-xs text-gray-600 leading-relaxed">
            A small smile changes your tone. Most students sound 12% more confident after one practice round.
          </p>
        </div>

        <div class="bg-white rounded-2xl border border-gray-100 p-4">
          <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">What we listen for</p>
          <ul class="space-y-2 text-sm text-gray-700">
            <li class="flex items-center gap-2"><span class="w-1.5 h-1.5 rounded-full" style="background-color: #FF8B00;"></span>Clarity</li>
            <li class="flex items-center gap-2"><span class="w-1.5 h-1.5 rounded-full" style="background-color: #FF8B00;"></span>Pace & pauses</li>
            <li class="flex items-center gap-2"><span class="w-1.5 h-1.5 rounded-full" style="background-color: #FF8B00;"></span>Structure</li>
            <li class="flex items-center gap-2"><span class="w-1.5 h-1.5 rounded-full" style="background-color: #FF8B00;"></span>Confidence</li>
            <li class="flex items-center gap-2"><span class="w-1.5 h-1.5 rounded-full" style="background-color: #FF8B00;"></span>Word choice</li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :resume_info, :map, required: true

  defp indexing_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-10 text-center">
      <div class="animate-spin rounded-full h-12 w-12 border-2 border-cream-200 mx-auto mb-4" style="border-top-color: #FF8B00;"></div>
      <h2 class="text-lg font-bold text-gray-900 mb-1">Indexing your resume…</h2>
      <p class="text-sm text-gray-500">Vyaasa is reading and structuring your resume — a few seconds.</p>
      <%= if @resume_info && @resume_info.filename do %>
        <p class="text-xs text-gray-400 mt-3">{@resume_info.filename}</p>
      <% end %>
    </div>
    """
  end

  attr :resume_info, :map, required: true
  attr :greeting_text, :string, default: nil
  attr :mic_verified, :boolean, default: false
  attr :mic_permission, :string, default: nil
  attr :mic_checking, :boolean, default: false

  defp ready_card(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <div class="lg:col-span-2 bg-white rounded-2xl border border-gray-100 p-6">
        <span class="inline-block text-[11px] font-semibold px-2.5 py-1 rounded-full mb-3"
          style="background-color: #ECFDF5; color: #047857;">Resume indexed ✓</span>
        <h2 class="text-xl font-bold text-gray-900 mb-2">Ready to begin.</h2>

        <%= if @greeting_text && @greeting_text != "" do %>
          <div class="rounded-xl border border-cream-200 p-4 mb-5" style="background-color: #FFF1DE;">
            <div class="flex items-start gap-2 mb-1">
              <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5" style="color: #B85F00;" />
              <p class="text-xs font-semibold tracking-wider uppercase" style="color: #B85F00;">Vyaasa</p>
            </div>
            <p class="text-sm text-gray-700 leading-relaxed whitespace-pre-line">{@greeting_text}</p>
          </div>
        <% end %>

        <.mic_status verified={@mic_verified} state={@mic_permission} checking={@mic_checking} />

        <div class="flex items-center gap-3">
          <%!-- Full screen engages in this click ONLY when the mic is already
          verified: browsers suppress the permission prompt in full screen, so
          an unverified click must stay windowed for the prompt to appear. --%>
          <button
            phx-click="begin_interview"
            data-enter-fullscreen={@mic_verified && "true"}
            class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold transition"
            style="background-color: #FF8B00;"
          >
            ▶ Continue to Interview
          </button>
          <%!-- <button
            phx-click="upload_different_resume"
            class="px-4 py-2.5 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition"
          >
            Upload a different resume
          </button> --%>
        </div>
      </div>

      <div class="rounded-2xl border border-cream-200 p-4" style="background-color: #FFF1DE;">
        <div class="flex items-start gap-2 mb-1">
          <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5" style="color: #B85F00;" />
          <p class="text-sm font-semibold text-gray-800">You're warming up beautifully</p>
        </div>
        <p class="text-xs text-gray-600 leading-relaxed">
          Take one slow breath before the next button. Calm voice = confident voice.
        </p>
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp meta_pill(assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-3 py-2 rounded-full bg-cream-50 border border-cream-200">
      <.icon name={@icon} class="w-3.5 h-3.5" style="color: #B85F00;" />
      <span class="text-xs text-gray-700">{@label}</span>
    </div>
    """
  end

  # ── Step 2: Interview (Practice / Question / AI Reflecting) ─────────

  attr :interview_phase, :atom, required: true
  attr :current_question, :map, default: nil
  attr :current_question_number, :integer, default: 0
  attr :total_questions, :integer, default: 5
  attr :is_recording, :boolean, default: false
  attr :audio_level, :integer, default: 0
  attr :remaining_time, :integer, default: 600
  attr :loading, :atom, default: nil
  attr :current_transcript, :string, default: nil

  def interview_step(assigns) do
    ~H"""
    <%= cond do %>
      <% @loading == :starting_ws or @interview_phase == :connecting -> %>
        <.loading_card message="Connecting to interview service…" />

      <% @interview_phase in [:processing, :evaluating] -> %>
        <.ai_reflecting_card transcript={@current_transcript} />

      <% @interview_phase == :completing -> %>
        <.loading_card message="Wrapping up your interview…" />

      <% @current_question != nil -> %>
        <.question_card
          question={@current_question}
          number={@current_question_number}
          total={@total_questions}
          is_recording={@is_recording}
          audio_level={@audio_level}
        />

      <% true -> %>
        <.loading_card message="Preparing your first question…" />
    <% end %>
    """
  end

  attr :message, :string, required: true

  defp loading_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-10 text-center">
      <div class="animate-spin rounded-full h-12 w-12 border-2 border-cream-200 mx-auto mb-4" style="border-top-color: #FF8B00;"></div>
      <p class="text-sm font-medium text-gray-700">{@message}</p>
      <p class="text-xs text-gray-400 mt-1">This may take a moment.</p>
    </div>
    """
  end

  attr :transcript, :string, default: nil

  defp ai_reflecting_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-cream-200 p-10" style="background-color: #FFF6EC;">
      <div class="text-center mb-6">
        <div class="w-12 h-12 rounded-xl mx-auto mb-3 flex items-center justify-center" style="background-color: #FF8B00;">
          <svg viewBox="0 0 24 24" class="w-7 h-7" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M6 10 L16 6 L26 10 L22 24 L10 24 Z" />
            <path d="M11 14 L16 22 L21 14" />
          </svg>
        </div>
        <h2 class="text-lg font-bold text-gray-900">Your Vyaasa Coach is reflecting</h2>
        <p class="text-xs text-gray-500 mt-0.5">Soft, supportive analysis no judgment.</p>
      </div>

      <div class="max-w-xl mx-auto space-y-3">
        <.reflecting_step text="Transcribing your response..." />
        <.reflecting_step text="Analysing communication clarity..." />
        <.reflecting_step text="Evaluating confidence level..." />
        <.reflecting_step text="Extracting strength singles..." />
        <.reflecting_step text="Mapping to AI8 dimensions" />
      </div>

      <div class="max-w-xl mx-auto mt-6">
        <.heard_transcript
          transcript={@transcript}
          title="Your answer, as we heard it"
          note="Transcribed from your recording — this is what your coach is reading."
        />
      </div>
    </div>
    """
  end

  attr :text, :string, required: true

  defp reflecting_step(assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-4 py-2.5 rounded-full" style="background-color: #ECFDF5; border: 1px solid #A7F3D0;">
      <span class="w-5 h-5 rounded-full flex items-center justify-center shrink-0" style="background-color: #22C55E;">
        <svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
      </span>
      <span class="text-sm text-green-800">{@text}</span>
    </div>
    """
  end

  attr :question, :map, required: true
  attr :number, :integer, required: true
  attr :total, :integer, required: true
  attr :is_recording, :boolean, required: true
  attr :audio_level, :integer, required: true

  defp question_card(assigns) do
    q_text = assigns.question.text || assigns.question["text"] || ""
    assigns = assign(assigns, :q_text, q_text)

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <div class="lg:col-span-2 bg-white rounded-2xl border border-gray-100 p-6">
        <div class="flex items-center mb-3">
          <span class="text-[10px] font-semibold px-2.5 py-1 rounded-full"
            style="background-color: #FFE9D2; color: #B85F00;">Question {@number} of {@total}</span>
        </div>

        <h2 class="text-lg font-bold text-gray-900 leading-relaxed mb-5">{@q_text}</h2>

        <div class="rounded-2xl p-5 mb-4" style="background-color: #FAF6EE;">
          <p class="text-[10px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">Live Waveform</p>
          <.waveform active={@is_recording} level={@audio_level} />
          <div class="grid grid-cols-3 gap-3 mt-3">
            <.metric_chip label="Pace" value="—" />
            <.metric_chip label="Clarity" value="—" />
            <.metric_chip label="Filler" value="—" />
          </div>
        </div>

        <!-- Live transcript (browser preview; scoring uses the recording) -->
        <.live_transcript id="interview-live-transcript" recording?={@is_recording} class="mb-4" />

        <!-- Recorder button row -->
        <div id="audio-recorder" phx-hook="AudioRecorder" class="flex items-center gap-3 mb-5">
          <button
            phx-click="toggle_recording"
            class={[
              "flex-1 inline-flex items-center justify-center gap-1.5 px-4 py-2.5 rounded-lg text-white text-sm font-semibold transition"
            ]}
            style={if @is_recording, do: "background-color: #DC2626;", else: "background-color: #FF8B00;"}
          >
            <%= if @is_recording do %>
              ⏹ Stop Recording
            <% else %>
              ▶ Start Recording
            <% end %>
          </button>
          <button
            phx-click="discard_recording"
            class="inline-flex items-center gap-1.5 px-4 py-2.5 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition"
          >
            ↻ Retry
          </button>
        </div>

        <!-- STAR steps -->
        <div class="grid grid-cols-3 gap-2">
          <.star_step number="1" title="Hook" description="Open with one sentence about why this mattered." />
          <.star_step number="2" title="Body" description="Briefly cover your role, challenge, decision." />
          <.star_step number="3" title="Outcome" description="End with the result and what you learned." />
        </div>
      </div>

      <!-- Right helper column -->
      <div class="space-y-4">
        <div class="rounded-2xl border border-cream-200 p-4" style="background-color: #FFF1DE;">
          <div class="flex items-start gap-2 mb-1">
            <.icon name="hero-sparkles" class="w-4 h-4 mt-0.5" style="color: #B85F00;" />
            <p class="text-sm font-semibold text-gray-800">You've got this 💪</p>
          </div>
          <p class="text-xs text-gray-600 leading-relaxed">
            Pauses are powerful recruiters love thoughtful answers more than fast ones.
          </p>
        </div>

        <div class="bg-white rounded-2xl border border-gray-100 p-4">
          <p class="text-[11px] font-semibold tracking-[0.18em] uppercase text-gray-500 mb-3">Sample starters</p>
          <ul class="space-y-1.5 text-xs text-gray-700">
            <li class="flex items-start gap-2"><span class="text-green-500 mt-0.5">✓</span>"One project I'm especially proud of is…"</li>
            <li class="flex items-start gap-2"><span class="text-green-500 mt-0.5">✓</span>"The challenge we faced was…"</li>
            <li class="flex items-start gap-2"><span class="text-green-500 mt-0.5">✓</span>"What made it meaningful was…"</li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp metric_chip(assigns) do
    ~H"""
    <div class="bg-white rounded-lg px-3 py-2 text-center border border-cream-200">
      <p class="text-[10px] uppercase tracking-wider text-gray-400">{@label}</p>
      <p class="text-sm font-semibold text-gray-900 mt-0.5">{@value}</p>
    </div>
    """
  end

  attr :number, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp star_step(assigns) do
    ~H"""
    <div class="bg-cream-50 rounded-xl p-3 border border-cream-200">
      <p class="text-[10px] font-semibold tracking-[0.12em] uppercase text-gray-500 mb-1">Step {@number}</p>
      <p class="text-sm font-semibold text-gray-900 mb-0.5">{@title}</p>
      <p class="text-[11px] text-gray-500 leading-relaxed">{@description}</p>
    </div>
    """
  end

  # ── Waveform ────────────────────────────────────────────────────────

  attr :active, :boolean, default: false
  attr :level, :integer, default: 0

  def waveform(assigns) do
    bars =
      if assigns.active and assigns.level > 0 do
        base = assigns.level

        for i <- 0..38 do
          variation = :erlang.phash2({i, base}, 30) - 15
          min(95, max(15, base + variation))
        end
      else
        if assigns.active do
          [
            35,
            55,
            40,
            65,
            45,
            70,
            50,
            60,
            38,
            68,
            42,
            58,
            48,
            62,
            36,
            55,
            44,
            66,
            40,
            52,
            46,
            64,
            38,
            56,
            50,
            42,
            60,
            38,
            52,
            46,
            40,
            58,
            44,
            36,
            50,
            42,
            48,
            38,
            56
          ]
        else
          # Static "idle" waveform pattern matching Figma
          [
            20,
            35,
            50,
            30,
            40,
            55,
            35,
            25,
            45,
            60,
            40,
            30,
            50,
            35,
            45,
            55,
            30,
            40,
            50,
            35,
            45,
            30,
            55,
            40,
            50,
            35,
            45,
            30,
            40,
            55,
            35,
            50,
            40,
            30,
            45,
            35,
            50,
            40,
            30
          ]
        end
      end

    assigns = assign(assigns, bars: bars)

    ~H"""
    <div class="flex items-center justify-center gap-[3px] h-12">
      <%= for height <- @bars do %>
        <div
          class="w-1 rounded-full transition-all duration-150"
          style={"height: #{height}%; background-color: #{if @active, do: "#FF8B00", else: "#FFB36B"};"}
        ></div>
      <% end %>
    </div>
    """
  end

  # ── Step 3: Results ─────────────────────────────────────────────────

  attr :overall_score, :any, default: nil
  attr :strengths, :list, default: []
  attr :improvements, :list, default: []
  attr :questions_answered, :list, default: []
  attr :expanded_question, :integer, default: nil
  attr :tenant_alias, :string, default: nil
  attr :interview_session, :map, default: nil
  attr :student_name, :string, default: "Student"
  attr :error, :string, default: nil
  attr :error_title, :string, default: nil

  def results_step(assigns) do
    score_val = score_to_float(assigns.overall_score)
    display_score = round(score_val)
    first_name = assigns.student_name |> to_string() |> String.split(" ") |> List.first() || "there"

    assigns =
      assigns
      |> assign(:display_score, display_score)
      |> assign(:first_name, first_name)

    ~H"""
    <div class="space-y-4">
      <!-- Orange gradient hero -->
      <div class="rounded-2xl p-6 text-white relative overflow-hidden"
        style="background: linear-gradient(135deg, #FF983A 0%, #FF8B00 50%, #E67800 100%);"
      >
        <span class="inline-block text-[10px] font-semibold px-2 py-0.5 rounded-full mb-3"
          style="background-color: rgba(255,255,255,0.25); color: white;">Session Complete</span>

        <div class="flex items-start justify-between gap-4">
          <div class="flex-1">
            <h2 class="text-2xl font-bold mb-2">Beautifully done, {@first_name}</h2>
            <p class="text-sm" style="color: rgba(255,255,255,0.9);">
              You showed real warmth and structure — clear, confident communication throughout.
            </p>
          </div>
          <div class="text-center shrink-0">
            <div class="w-20 h-20 rounded-full flex items-center justify-center" style="background-color: #22C55E;">
              <span class="text-2xl font-bold text-white">{@display_score}</span>
            </div>
            <p class="text-[10px] mt-1 uppercase tracking-wider" style="color: rgba(255,255,255,0.9);">Score / 100</p>
          </div>
        </div>
      </div>

      <!-- Strengths / Areas -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="bg-white rounded-2xl border border-gray-100 p-5">
          <div class="flex items-center gap-2 mb-3">
            <.icon name="hero-arrow-trending-up" class="w-4 h-4 text-green-600" />
            <p class="text-sm font-semibold text-gray-900">Strengths</p>
          </div>
          <ul class="space-y-2 text-sm text-gray-700">
            <%= if @strengths != [] do %>
              <%= for s <- @strengths do %>
                <li class="flex items-start gap-2"><span class="text-green-500 mt-0.5">✓</span>{s}</li>
              <% end %>
            <% else %>
              <li class="flex items-start gap-2"><span class="text-green-500 mt-0.5">✓</span>Clear communication and articulation of ideas</li>
              <li class="flex items-start gap-2"><span class="text-green-500 mt-0.5">✓</span>Strong problem-solving approach with concrete examples</li>
              <li class="flex items-start gap-2"><span class="text-green-500 mt-0.5">✓</span>Demonstrates leadership qualities and team collaboration</li>
              <li class="flex items-start gap-2"><span class="text-green-500 mt-0.5">✓</span>Shows genuine enthusiasm for the role and industry</li>
            <% end %>
          </ul>
        </div>

        <div class="bg-white rounded-2xl border border-gray-100 p-5">
          <div class="flex items-center gap-2 mb-3">
            <.icon name="hero-light-bulb" class="w-4 h-4" style="color: #B85F00;" />
            <p class="text-sm font-semibold text-gray-900">Areas to Improve</p>
          </div>
          <ul class="space-y-2 text-sm text-gray-700">
            <%= if @improvements != [] do %>
              <%= for imp <- @improvements do %>
                <li class="flex items-start gap-2"><span style="color: #FF8B00;" class="mt-0.5">○</span>{imp}</li>
              <% end %>
            <% else %>
              <li class="flex items-start gap-2"><span style="color: #FF8B00;" class="mt-0.5">○</span>Could provide more specific metrics and quantifiable achievements</li>
              <li class="flex items-start gap-2"><span style="color: #FF8B00;" class="mt-0.5">○</span>Consider elaborating more on tech-soft skills and tools</li>
              <li class="flex items-start gap-2"><span style="color: #FF8B00;" class="mt-0.5">○</span>Practice discussing weaknesses in a more constructive manner</li>
            <% end %>
          </ul>
        </div>
      </div>

      <!-- Overall Summary -->
      <%= if @interview_session && @interview_session.final_report not in [nil, ""] do %>
        <div class="bg-white rounded-2xl border border-gray-100 p-5">
          <div class="flex items-center gap-2 mb-3">
            <.icon name="hero-document-text" class="w-4 h-4 text-gray-500" />
            <p class="text-sm font-semibold text-gray-900">Interview Summary</p>
          </div>
          <div class="text-sm text-gray-700 leading-relaxed whitespace-pre-line">
            {@interview_session.final_report}
          </div>
        </div>
      <% end %>

      <.error_card
        :if={@error}
        title={@error_title}
        error_message={@error}
        retry_event="start_new_interview"
        class="mb-2"
      />

      <!-- Actions -->
      <div data-print-hide>
        <VyaasaCampusWeb.Components.Student.AssessmentFooter.assessment_footer
          next_event="back_to_dashboard"
          restart_event="start_new_interview"
          restart_label="Start New Interview"
          show_restart={true}
          dashboard_event="back_to_dashboard"
        />
      </div>
    </div>
    """
  end

  attr :question, :map, required: true
  attr :expanded, :boolean, default: false

  defp question_accordion(assigns) do
    q_num = assigns.question["question_number"] || assigns.question[:question_number]
    q_text = assigns.question["question_text"] || assigns.question[:question_text] || ""
    score = assigns.question["score"] || assigns.question[:score] || 0
    display_score = if is_number(score), do: round(score), else: 0
    transcript = assigns.question["transcript"] || assigns.question[:transcript] || "Question was skipped"
    feedback = assigns.question["feedback"] || assigns.question[:feedback] || ""
    evaluation = assigns.question["evaluation"] || assigns.question[:evaluation] || ""

    assigns =
      assigns
      |> assign(:q_num, q_num)
      |> assign(:q_text, q_text)
      |> assign(:display_score, display_score)
      |> assign(:transcript, transcript)
      |> assign(:feedback, feedback)
      |> assign(:evaluation, evaluation)

    ~H"""
    <div class="rounded-xl border border-gray-100 overflow-hidden">
      <button
        phx-click="toggle_question_detail"
        phx-value-question_number={@q_num}
        class="w-full flex items-center justify-between px-4 py-3 hover:bg-cream-50 transition text-left"
      >
        <div class="flex items-center gap-3">
          <span class="text-[10px] font-semibold text-gray-500">Q{@q_num}</span>
          <span class="text-sm text-gray-800">{@q_text}</span>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-[10px] font-semibold px-2 py-0.5 rounded-full"
            style="background-color: #FFE9D2; color: #B85F00;">{@display_score}/100</span>
          <.icon name={if @expanded, do: "hero-chevron-up", else: "hero-chevron-down"} class="w-4 h-4 text-gray-400" />
        </div>
      </button>

      <%= if @expanded do %>
        <div class="px-4 pb-4 border-t border-gray-100 space-y-3">
          <div class="mt-3">
            <p class="text-[10px] font-semibold tracking-wider uppercase text-gray-500 mb-1">Your Response</p>
            <div class="rounded-lg p-3" style="background-color: #FAF6EE;">
              <p class="text-xs text-gray-700">{@transcript}</p>
            </div>
          </div>
          <div>
            <p class="text-[10px] font-semibold tracking-wider uppercase text-gray-500 mb-1">Vyaasa Feedback</p>
            <p class="text-xs text-gray-700">{@evaluation}</p>
            <%= if @feedback != "" do %>
              <p class="text-xs text-green-700 mt-1 italic">{@feedback}</p>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── PDF Print Area (kept simple) ─────────────────────────────────────

  attr :overall_score, :any, default: nil
  attr :strengths, :list, default: []
  attr :improvements, :list, default: []
  attr :questions_answered, :list, default: []
  attr :student_name, :string, default: "Student"

  def pdf_print_area(assigns) do
    score_val = score_to_float(assigns.overall_score)
    display_score = round(score_val)
    assigns = assign(assigns, :display_score, display_score)

    ~H"""
    <div class="hidden print:block">
      <h1 class="text-2xl font-bold mb-4">Interview Feedback - {@student_name}</h1>
      <p class="mb-4">Overall Score: {@display_score} / 100</p>

      <h2 class="text-lg font-semibold mt-4 mb-2">Strengths</h2>
      <ul class="list-disc pl-5">
        <%= for s <- @strengths do %><li>{s}</li><% end %>
      </ul>

      <h2 class="text-lg font-semibold mt-4 mb-2">Areas to Improve</h2>
      <ul class="list-disc pl-5">
        <%= for i <- @improvements do %><li>{i}</li><% end %>
      </ul>

      <h2 class="text-lg font-semibold mt-4 mb-2">Question Feedback</h2>
      <%= for q <- @questions_answered do %>
        <div class="mb-3">
          <p class="font-bold">Q{q["question_number"] || q[:question_number]}: {q["question_text"] || q[:question_text]}</p>
          <p class="text-sm text-gray-700">{q["evaluation"] || q[:evaluation]}</p>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp score_to_float(nil), do: 0.0
  defp score_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp score_to_float(n) when is_float(n), do: n
  defp score_to_float(n) when is_integer(n), do: n * 1.0
  defp score_to_float(_), do: 0.0
end
