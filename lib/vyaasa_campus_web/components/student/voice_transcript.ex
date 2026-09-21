defmodule VyaasaCampusWeb.Components.Student.VoiceTranscript do
  @moduledoc """
  Transcript UI shared by the voice assessments (JAM, Interview, Behavioral).

  Two pieces, used together:

    * `live_transcript/1` — a running preview of what the student is saying,
      written straight into the DOM by the `AudioRecorder` JS hook using the
      browser's Web Speech API. It is a *preview*: nothing in it reaches the
      server and nothing in it is scored.

    * `heard_transcript/1` — the authoritative transcript, i.e. what Whisper
      made of the finished recording. This is the text the AI actually
      evaluated, shown back read-only so a student can see exactly what was
      graded (and tell "the AI was harsh" apart from "the mic ate my answer").

  ## Wiring

      import VyaasaCampusWeb.Components.Student.VoiceTranscript

      # on the recording screen, anywhere inside or beside the AudioRecorder
      <.live_transcript recording?={@is_recording} />

      # once the transcript comes back
      <.heard_transcript transcript={@last_transcript} />
  """

  use Phoenix.Component

  import VyaasaCampusWeb.Components.UI, only: [icon: 1]

  attr :id, :string, default: "live-transcript"
  attr :recording?, :boolean, default: false
  attr :enabled, :boolean, default: true
  attr :lang, :string, default: "en-IN"
  attr :height_class, :string, default: "h-32"
  attr :class, :string, default: nil

  @doc """
  Live, in-progress transcript of the answer being spoken.

  Everything inside is owned by the JS hook — hence `phx-update="ignore"`. A
  LiveView patch lands here every half-second (the audio-level tick), which
  would otherwise wipe the text mid-sentence.

  `recording?` only decides the initial copy: once recording starts the hook
  takes over the status line, including telling the student when their browser
  has no Web Speech support (Firefox, some Safari builds) — in which case the
  recording and the Whisper transcript are entirely unaffected.
  """
  def live_transcript(assigns) do
    ~H"""
    <div
      id={@id}
      phx-update="ignore"
      data-live-transcript={if @enabled, do: "on", else: "off"}
      data-lang={@lang}
      class={[
        "rounded-xl border p-4",
        @class
      ]}
      style="background-color: #FFFFFF; border-color: #F4ECDD;"
    >
      <div class="flex items-center justify-between gap-3 mb-2">
        <p class="text-[10px] font-semibold tracking-[0.18em] uppercase text-gray-500 flex items-center gap-1.5">
          <.icon name="hero-microphone" class="w-3.5 h-3.5" style="color: #B85F00;" /> Live transcript
        </p>
        <span
          data-live-transcript-status
          class="text-[10px] text-gray-400 text-right leading-snug"
        >{if @recording?, do: "Listening…", else: ""}</span>
      </div>

      <%!-- A FIXED height, not a max: the box is the same size before the first
            word and after the last, so the record button never walks down the
            page mid-answer. The scroller is this inner box, not the card, so
            the heading, status and footer note stay put while the words scroll
            under them. The hook keeps it pinned to the newest text unless the
            student has scrolled back to re-read something. --%>
      <div data-live-transcript-body class={["overflow-y-auto overscroll-contain", @height_class]}>
        <p data-live-transcript-empty class="text-xs text-gray-400 italic">
          Start speaking — your words will appear here as you go.
        </p>
        <p class="text-sm text-gray-800 leading-relaxed">
          <span data-live-transcript-final></span><span data-live-transcript-interim class="text-gray-400"></span>
        </p>
      </div>

      <p class="text-[10px] text-gray-400 mt-2">
        A rough guide from your browser — it can mishear or lag. The accurate transcript
        appears once you submit, and that is the one you're scored on.
      </p>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :transcript, :string, default: nil
  attr :title, :string, default: "What we heard"
  attr :note, :string, default: "This is the transcript your answer was scored from."
  attr :height_class, :string, default: "max-h-64"
  attr :class, :string, default: nil

  @doc """
  Read-only view of the transcript an answer was actually scored from.

  Renders nothing when there is no transcript, so callers can drop it in
  unconditionally.
  """
  def heard_transcript(assigns) do
    assigns = assign(assigns, :text, normalize(assigns.transcript))

    ~H"""
    <div
      :if={@text}
      id={@id}
      class={["rounded-2xl border p-5", @class]}
      style="background-color: #FAF6EE; border-color: #F4ECDD;"
    >
      <div class="flex items-center gap-1.5 mb-2">
        <.icon name="hero-document-text" class="w-4 h-4" style="color: #B85F00;" />
        <p class="text-[10px] font-semibold tracking-[0.18em] uppercase text-gray-500">{@title}</p>
      </div>

      <%!-- A long answer scrolls in place rather than pushing the scores and the
            rest of the report off the screen. --%>
      <div class={["overflow-y-auto overscroll-contain", @height_class]}>
        <p class="text-sm text-gray-800 leading-relaxed whitespace-pre-line">{@text}</p>
      </div>

      <p :if={@note not in [nil, ""]} class="text-[10px] text-gray-400 mt-3">{@note}</p>
    </div>
    """
  end

  # The engines fall back to placeholder strings ("No transcript available.")
  # when Whisper returned nothing; showing those verbatim under a "what we
  # heard" heading reads like a bug, so treat them as absent.
  defp normalize(text) when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed == "" or String.downcase(trimmed) in [
         "no transcript available.",
         "no transcript available",
         "(no response recorded)"
       ] do
      nil
    else
      trimmed
    end
  end

  defp normalize(_), do: nil
end
