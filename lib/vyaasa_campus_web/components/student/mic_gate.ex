defmodule VyaasaCampusWeb.Components.Student.MicGate do
  @moduledoc """
  Microphone permission gate for the voice-based assessments (JAM, Interview,
  Behavioral).

  Students used to reach a recording screen and only then discover the browser
  had the mic blocked — by which point a session row already existed and the
  attempt was burnt. This module checks permission *before* the voice flow
  starts and, when the browser can still be asked, triggers the native prompt.

  ## Wiring a LiveView

      import VyaasaCampusWeb.Components.Student.MicGate

      def mount(_, _, socket), do: {:ok, mount_mic_gate(socket)}

      # The event that kicks off recording
      def handle_event("start_session", params, socket) do
        case require_mic(socket, "start_session") do
          {:gated, socket} -> {:noreply, socket}
          {:ok, socket} -> ...
        end
      end

      # Reports coming back from the `MicGate` JS hook
      def handle_event("mic_permission", params, socket) do
        case handle_mic_report(socket, params) do
          {:resume, event, socket} -> handle_event(event, %{}, socket)
          {:ok, socket} -> {:noreply, socket}
        end
      end

      def handle_event("mic_gate_retry", _p, socket), do: {:noreply, retry_mic(socket)}
      def handle_event("mic_gate_dismiss", _p, socket), do: {:noreply, close_mic_gate(socket)}

  and render `<.mic_gate state={@mic_permission} open={@mic_gate_open} />` once
  in the template.
  """

  use Phoenix.Component

  import Phoenix.LiveView, only: [push_event: 3]
  import VyaasaCampusWeb.Components.UI, only: [icon: 1]

  @doc "Default assigns for the gate. Call from `mount/3`."
  def mount_mic_gate(socket) do
    socket
    |> assign(:mic_permission, nil)
    |> assign(:mic_detail, nil)
    |> assign(:mic_verified, false)
    |> assign(:mic_checking, false)
    |> assign(:mic_probe_silent, false)
    |> assign(:mic_gate_open, false)
    |> assign(:mic_gate_pending, nil)
  end

  @doc """
  Fires the probe ahead of time, without a dialog and without queueing an event.

  For assessments where voice is optional (Situational & Behavioral), call this
  as soon as the page is ready and *before* the student enters full screen —
  browsers suppress the permission prompt in full screen, so asking at the
  moment they tap "Voice" would be too late. A failed silent probe stays quiet;
  it just means `require_mic/2` has a real answer ready when voice is picked.
  """
  def probe_mic(socket) do
    if socket.assigns[:mic_verified] or socket.assigns[:mic_checking] do
      socket
    else
      socket
      |> assign(:mic_checking, true)
      |> assign(:mic_probe_silent, true)
      |> push_event("request_mic_permission", %{})
    end
  end

  @doc """
  Guards an event that needs the microphone.

  Returns `{:ok, socket}` only when a real `getUserMedia` probe has already
  succeeded on this page — the Permissions API alone is not enough, since it
  reports "granted" for a site permission the OS or another app can still
  block, which is exactly how students ended up on the speaking screen with a
  "Permission denied" toast.

  Otherwise returns `{:gated, socket}` and fires the probe. `resume_event` is
  the event name replayed automatically the moment the mic checks out, so the
  student never has to click Start twice.
  """
  def require_mic(socket, resume_event, opts \\ []) when is_binary(resume_event) do
    if socket.assigns[:mic_verified] do
      {:ok, socket}
    else
      # `dialog: false` for screens that already carry an inline `mic_status`
      # notice — the banner is the explanation, so a modal on top of it would
      # only be noise.
      dialog? = Keyword.get(opts, :dialog, true)

      {:gated,
       socket
       |> assign(:mic_gate_pending, resume_event)
       |> assign(:mic_checking, true)
       |> assign(:mic_probe_silent, not dialog?)
       # Probe silently when the browser already reports a grant — no popup is
       # coming, so a dialog would only flash. Every other state gets the
       # dialog up front, to explain the popup or how to unblock.
       |> assign(:mic_gate_open, dialog? and socket.assigns[:mic_permission] != "granted")
       |> push_event("request_mic_permission", %{})}
    end
  end

  @doc """
  Folds a report from the JS hook into the socket.

  Reports from the passive Permissions API check (`source: "check"`) only
  refresh the dialog copy; a grant is trusted — and a queued event resumed —
  only on the back of a real `getUserMedia` probe (`source: "request"`).

  Returns `{:resume, event, socket}` when the mic just checked out and an event
  was waiting on it — the caller should re-dispatch that event.
  """
  def handle_mic_report(socket, %{"state" => state} = params) do
    probe? = params["source"] == "request"
    granted? = state == "granted"
    pending = socket.assigns[:mic_gate_pending]

    verified? =
      cond do
        # Only the probe can decide, either way.
        probe? -> granted?
        # A passive report of a hard block is worth acting on: the student
        # revoked the permission, so the next voice action must re-check.
        state in ["denied", "unsupported", "unavailable"] -> false
        # Everything else (including a one-time grant lapsing back to "prompt"
        # once we release the stream) leaves the last probe's verdict standing.
        # Re-probing mid-session would fail anyway — the assessment runs in full
        # screen, where browsers suppress the permission prompt.
        true -> !!socket.assigns[:mic_verified]
      end

    silent? = probe? and !!socket.assigns[:mic_probe_silent]

    socket =
      socket
      |> assign(:mic_permission, state)
      |> assign(:mic_detail, params["detail"])
      |> assign(:mic_verified, verified?)

    socket = if probe?, do: assign(socket, :mic_probe_silent, false), else: socket

    cond do
      probe? and granted? and is_binary(pending) ->
        {:resume, pending,
         socket |> assign(:mic_gate_open, false) |> assign(:mic_checking, false) |> assign(:mic_gate_pending, nil)}

      probe? and granted? ->
        {:ok, socket |> assign(:mic_gate_open, false) |> assign(:mic_checking, false)}

      probe? ->
        # The probe failed. Surface the fix-it dialog — unless this was a
        # pre-flight probe on a page where voice is only one of the options,
        # in which case the student finds out if and when they pick voice.
        {:ok, socket |> assign(:mic_gate_open, not silent?) |> assign(:mic_checking, false)}

      true ->
        {:ok, socket}
    end
  end

  def handle_mic_report(socket, _params), do: {:ok, socket}

  @doc """
  Re-asks the browser for permission (the gate's primary button).

  When the site permission is already denied the browser won't re-prompt, but
  `getUserMedia` still resolves immediately with the *current* state — so this
  doubles as the "I've just allowed it in the address bar" re-check.
  """
  def retry_mic(socket) do
    socket
    |> assign(:mic_checking, true)
    |> assign(:mic_probe_silent, false)
    |> push_event("request_mic_permission", %{})
  end

  @doc """
  Re-opens the gate after the recorder itself failed to get the mic.

  The pre-flight probe can pass and the mic still disappear later (revoked
  permission, unplugged headset, another app grabbing the device), so a
  recording failure invalidates the verification instead of just flashing a
  toast.
  """
  def mic_recording_failed(socket, error_name) do
    state =
      case error_name do
        n when n in ["NotAllowedError", "SecurityError"] -> "denied"
        _ -> "unavailable"
      end

    socket
    |> assign(:mic_verified, false)
    |> assign(:mic_permission, state)
    |> assign(:mic_detail, error_name)
    |> assign(:mic_checking, false)
    |> assign(:mic_gate_open, true)
  end

  @doc "Closes the gate and drops the queued event."
  def close_mic_gate(socket) do
    socket
    |> assign(:mic_gate_open, false)
    |> assign(:mic_checking, false)
    |> assign(:mic_gate_pending, nil)
  end

  @doc "True once a real `getUserMedia` probe has confirmed a working mic."
  def mic_granted?(socket_or_assigns)
  def mic_granted?(%{assigns: assigns}), do: mic_granted?(assigns)
  def mic_granted?(%{mic_verified: verified}), do: !!verified
  def mic_granted?(_), do: false

  # ── Component ──────────────────────────────────────────────────────────

  attr :id, :string, default: "mic-gate"
  attr :state, :string, default: nil
  attr :detail, :string, default: nil
  attr :open, :boolean, default: false
  attr :checking, :boolean, default: false
  attr :dismissible, :boolean, default: true

  @doc """
  Mounts the permission watcher and renders the blocking dialog when the mic
  is not usable. Render this once per voice assessment page.
  """
  def mic_gate(assigns) do
    assigns = assign(assigns, :copy, copy(assigns.state))

    ~H"""
    <div id={@id} phx-hook="MicGate"></div>

    <div
      :if={@open}
      class="fixed inset-0 z-[110] flex items-center justify-center p-4"
      style="background-color: rgba(17, 24, 39, 0.55);"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
    >
      <div class="w-full max-w-md bg-white rounded-3xl shadow-xl border border-gray-100 p-7 text-center">
        <div class="w-14 h-14 mx-auto rounded-2xl flex items-center justify-center mb-4" style="background-color: #FFF1DE;">
          <.icon name={@copy.icon} class="w-7 h-7" style="color: #B85F00;" />
        </div>

        <h2 id={"#{@id}-title"} class="text-lg font-bold text-gray-900 mb-2">{@copy.title}</h2>
        <p class="text-sm text-gray-600 leading-relaxed">{@copy.body}</p>

        <ul :if={@copy.steps != []} class="mt-4 space-y-2 text-left">
          <li :for={{step, idx} <- Enum.with_index(@copy.steps, 1)} class="flex items-start gap-2.5 text-xs text-gray-700">
            <span class="w-5 h-5 shrink-0 rounded-full flex items-center justify-center text-[10px] font-bold" style="background-color: #FFE9D2; color: #B85F00;">
              {idx}
            </span>
            <span class="leading-relaxed">{step}</span>
          </li>
        </ul>

        <div class="mt-6 flex items-center justify-center gap-3">
          <button
            :if={@dismissible}
            type="button"
            phx-click="mic_gate_dismiss"
            class="px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-semibold text-gray-600 hover:bg-gray-50 transition"
          >
            Not now
          </button>
          <button
            type="button"
            phx-click="mic_gate_retry"
            disabled={@checking}
            class="px-5 py-2.5 rounded-xl text-white text-sm font-bold transition shadow-sm disabled:opacity-60"
            style="background-color: #FF8B00;"
          >
            {if @checking, do: "Waiting for your browser…", else: @copy.action}
          </button>
        </div>

        <p class="mt-4 text-[11px] text-gray-400">
          We only use your microphone while you are recording an answer.
        </p>
      </div>
    </div>
    """
  end

  attr :verified, :boolean, default: false
  attr :state, :string, default: nil
  attr :checking, :boolean, default: false
  attr :class, :string, default: nil

  @doc """
  Inline microphone status for a pre-start screen.

  The dialog is a backstop; this is the part the student should see *before*
  committing — a blocked mic is called out on the "ready to begin" screen, with
  the fix and an Enable button, instead of surfacing as a failed recording
  (and an integrity strike) once the assessment is already running.
  """
  def mic_status(assigns) do
    ~H"""
    <div
      :if={not @verified}
      class={["rounded-xl p-4 mb-5", @class]}
      style={
        if blocked?(@state),
          do: "background-color: #FEF2F2; border: 1px solid #FECACA;",
          else: "background-color: #FFF1DE; border: 1px solid #F4ECDD;"
      }
    >
      <div class="flex items-start gap-3">
        <.icon
          name={if blocked?(@state), do: "hero-no-symbol", else: "hero-microphone"}
          class="w-5 h-5 mt-0.5 shrink-0"
          style={if blocked?(@state), do: "color: #B91C1C;", else: "color: #B85F00;"}
        />
        <div class="min-w-0">
          <p class="text-sm font-semibold" style={if blocked?(@state), do: "color: #991B1B;", else: "color: #7C3F00;"}>
            {copy(@state).title}
          </p>
          <p class="text-xs mt-0.5 leading-relaxed" style={if blocked?(@state), do: "color: #B91C1C;", else: "color: #92400E;"}>
            {copy(@state).body}
          </p>

          <ol :if={blocked?(@state) and copy(@state).steps != []} class="mt-2 space-y-1 text-xs list-decimal list-inside" style="color: #B91C1C;">
            <li :for={step <- copy(@state).steps}>{step}</li>
          </ol>

          <button
            type="button"
            phx-click="mic_gate_retry"
            disabled={@checking}
            class="mt-3 inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg text-white text-xs font-bold transition disabled:opacity-60"
            style="background-color: #FF8B00;"
          >
            {if @checking, do: "Checking…", else: copy(@state).action}
          </button>
        </div>
      </div>
    </div>

    <div :if={@verified} class={["flex items-center gap-2 mb-5", @class]}>
      <.icon name="hero-microphone" class="w-4 h-4" style="color: #047857;" />
      <span class="text-xs font-semibold" style="color: #047857;">Microphone ready ✓</span>
    </div>
    """
  end

  defp blocked?(state), do: state in ["denied", "unsupported", "unavailable"]

  defp copy("denied") do
    %{
      icon: "hero-no-symbol",
      title: "Microphone is blocked",
      body: "Your browser is blocking the mic for this site, so we can't record your answer yet.",
      steps: [
        "Click the lock (or camera/mic) icon in the address bar.",
        "Set Microphone to \"Allow\".",
        "Come back here and press \"Check again\"."
      ],
      action: "Check again"
    }
  end

  defp copy("unavailable") do
    %{
      icon: "hero-exclamation-triangle",
      title: "No microphone detected",
      body: "We couldn't find a working microphone. Plug in a headset or check that no other app is using it.",
      steps: [],
      action: "Try again"
    }
  end

  defp copy("unsupported") do
    %{
      icon: "hero-exclamation-triangle",
      title: "Recording isn't available here",
      body:
        "This browser can't record audio on this page — it usually means an insecure connection or an unsupported browser. Try the latest Chrome, Edge or Safari over https.",
      steps: [],
      action: "Try again"
    }
  end

  defp copy(_promptable) do
    %{
      icon: "hero-microphone",
      title: "Allow microphone access",
      body: "This is a spoken assessment, so we need your mic before you begin.",
      steps: [
        "Press \"Allow microphone\" below.",
        "Choose \"Allow\" in your browser's popup.",
        "We'll start your session automatically."
      ],
      action: "Allow microphone"
    }
  end
end
