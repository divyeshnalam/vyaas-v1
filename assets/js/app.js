// Phoenix LiveView setup - Clean slate for fresh frontend build
import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
// html2pdf vendor lib kept but no longer imported – using browser print instead
import { Auth } from "./auth";
// SweetAlert2 — replaces native window.confirm/alert dialogs app-wide.
// Vendored (like topbar/daisyui/heroicons) so the Docker build needs no
// `npm install` in assets/. This "esm.all" build self-injects its own CSS,
// so no separate stylesheet import is required.
import Swal from "../vendor/sweetalert2.js";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

// ── Single-tab guard ─────────────────────────────────────────────────────
// Vyaasa may only run in one tab per browser profile at a time (mirrors the
// anti-multi-session policy already enforced during assessments). Tabs in the
// same profile share localStorage, so it doubles as a simple leader-election
// lock; a separate Chrome profile has its own localStorage and is unaffected.
const TAB_LOCK_KEY = "vyaasa:active-tab";
const TAB_LOCK_HEARTBEAT_MS = 2000;
const TAB_LOCK_STALE_MS = 6000;
// A fresh id per page load — deliberately NOT persisted in sessionStorage.
// Chrome's "Duplicate tab" clones sessionStorage into the new tab, so an id
// read from sessionStorage would be identical to the original tab's id and
// let the duplicate slip past the lock as if it were the same tab reloading.
// Releasing the lock on unload/pagehide (below) already covers the
// legitimate same-tab-reload case, so no persisted identity is needed.
const tabId = crypto.randomUUID();

const readTabLock = () => {
  try {
    return JSON.parse(localStorage.getItem(TAB_LOCK_KEY));
  } catch {
    return null;
  }
};

const tabLockIsFree = (lock) => !lock || Date.now() - lock.ts > TAB_LOCK_STALE_MS;

const claimTabLock = () => {
  localStorage.setItem(TAB_LOCK_KEY, JSON.stringify({ id: tabId, ts: Date.now() }));
};

const showDuplicateTabOverlay = () => {
  const overlay = document.createElement("div");
  overlay.id = "vyaasa-duplicate-tab-overlay";
  overlay.className =
    "fixed inset-0 z-[9999] flex items-center justify-center bg-gray-900/80 backdrop-blur-sm px-4";
  overlay.innerHTML = `
    <div class="max-w-sm w-full bg-white rounded-2xl shadow-2xl p-6 text-center">
      <div class="mx-auto mb-4 h-12 w-12 rounded-full bg-orange-50 text-orange-500 flex items-center justify-center">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="h-6 w-6"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m0 3.75h.008v.008H12v-.008ZM21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" /></svg>
      </div>
      <h2 class="text-base font-bold text-gray-900">Vyaasa is already open</h2>
      <p class="mt-2 text-sm text-gray-500">This browser already has Vyaasa open in another tab. Close this tab and use the existing one, or open a different Chrome profile if you need a separate session.</p>
      <p class="mt-3 text-xs text-gray-400">Waiting for the other tab to close…</p>
    </div>
  `;
  document.body.appendChild(overlay);

  const tryReclaim = () => {
    if (tabLockIsFree(readTabLock())) window.location.reload();
  };
  window.addEventListener("storage", (e) => e.key === TAB_LOCK_KEY && tryReclaim());
  setInterval(tryReclaim, TAB_LOCK_HEARTBEAT_MS);
};

const isPrimaryTab = tabLockIsFree(readTabLock());
if (isPrimaryTab) {
  claimTabLock();
  setInterval(claimTabLock, TAB_LOCK_HEARTBEAT_MS);
  const releaseTabLock = () => {
    const lock = readTabLock();
    if (lock && lock.id === tabId) localStorage.removeItem(TAB_LOCK_KEY);
  };
  // pagehide fires more reliably than beforeunload (e.g. under bfcache),
  // so both are registered to free the lock promptly on close/navigation.
  window.addEventListener("beforeunload", releaseTabLock);
  window.addEventListener("pagehide", releaseTabLock);
} else {
  showDuplicateTabOverlay();
}

// LiveView hooks
const Hooks = {
  StoreToken: {
    mounted() {
      this.handleEvent("store_token", (data) => {
        Auth.storeToken(data.token);
      });
    },
  },

  AutoDismissToast: {
    mounted() {
      this.scheduleDismiss();
    },
    updated() {
      this.scheduleDismiss();
    },
    destroyed() {
      if (this._dismissTimer) clearTimeout(this._dismissTimer);
      if (this._fadeTimer) clearTimeout(this._fadeTimer);
    },
    scheduleDismiss() {
      if (this._dismissTimer) clearTimeout(this._dismissTimer);
      if (this._fadeTimer) clearTimeout(this._fadeTimer);

      const duration = parseInt(this.el.dataset.duration) || 5000;
      // Reset any prior fade so re-mounted toasts are visible again.
      this.el.style.opacity = "1";

      this._dismissTimer = setTimeout(() => {
        if (!this.el || !this.el.parentNode) return;
        this.el.style.transition = "opacity 0.3s ease-out";
        this.el.style.opacity = "0";

        this._fadeTimer = setTimeout(() => {
          if (this.el && this.el.parentNode) this.el.remove();
        }, 300);
      }, duration);
    },
  },

  DownloadFile: {
    mounted() {
      this.handleEvent("download_file", (data) => {
        this.downloadFile(data);
      });
    },

    downloadFile(data) {
      const { url, headers = {} } = data;

      // Use fetch API to download with proper headers
      fetch(url, {
        method: "GET",
        headers: {
          Accept: "application/octet-stream",
          ...headers,
        },
      })
        .then((response) => {
          if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
          }
          return response.blob();
        })
        .then((blob) => {
          // Create download link
          const downloadUrl = window.URL.createObjectURL(blob);
          const link = document.createElement("a");
          link.href = downloadUrl;
          link.download = url.split("/").pop(); // Extract filename from URL
          document.body.appendChild(link);
          link.click();
          document.body.removeChild(link);
          window.URL.revokeObjectURL(downloadUrl);
        })
        .catch((error) => {
          console.error("Download failed:", error);
          // Fallback to direct link
          window.open(url, "_blank");
        });
    },
  },

  // Assessment Integrity Hook
  // Prevents copy-paste, right-click, and tracks tab/focus switching.
  // Pushes events to LiveView: "tab_switch_detected", "integrity_violation"
  AssessmentIntegrity: {
    mounted() {
      this.tabSwitchCount = 0;
      this.warningShown = false;

      // --- Copy / Cut / Paste prevention ---
      this._onCopy = (e) => {
        e.preventDefault();
      };
      this._onCut = (e) => {
        e.preventDefault();
      };
      this._onPaste = (e) => {
        e.preventDefault();
      };
      document.addEventListener("copy", this._onCopy);
      document.addEventListener("cut", this._onCut);
      document.addEventListener("paste", this._onPaste);

      // --- Right-click prevention ---
      this._onContextMenu = (e) => {
        e.preventDefault();
      };
      document.addEventListener("contextmenu", this._onContextMenu);

      // --- Keyboard shortcut prevention (DevTools, copy, etc.) ---
      this._onKeyDown = (e) => {
        const blocked =
          ((e.ctrlKey || e.metaKey) &&
            ["c", "x", "v", "u", "s", "p", "a"].includes(
              e.key.toLowerCase(),
            )) ||
          e.key === "F12" ||
          (e.ctrlKey &&
            e.shiftKey &&
            ["i", "j", "c"].includes(e.key.toLowerCase()));
        if (blocked) {
          e.preventDefault();
        }
      };
      document.addEventListener("keydown", this._onKeyDown);

      // --- Focus-loss detection (tab switch OR window blur / alt-tab) ---
      // Fire ONE violation per "away" transition so a single switch isn't
      // double-counted by both visibilitychange and blur.
      this._away = false;
      const reportAway = (type) => {
        if (this._away) return;
        this._away = true;
        this.pushEvent("integrity_violation", { type });
      };
      const backHome = () => {
        this._away = false;
      };

      this._onVisibilityChange = () => {
        if (document.hidden) reportAway("tab_switch");
        else backHome();
      };
      this._onBlur = () => reportAway("window_blur");
      this._onFocus = () => backHome();
      document.addEventListener("visibilitychange", this._onVisibilityChange);
      window.addEventListener("blur", this._onBlur);
      window.addEventListener("focus", this._onFocus);

      // --- Fullscreen enforcement ---
      // A user gesture is required to enter fullscreen, so we show a gate
      // overlay with a button. IMPORTANT: the gate is a nudge, not a hard block
      // — once the student clicks "begin" it is dismissed for good even if
      // fullscreen is unavailable (iframe / browser policy), so they can never
      // get trapped and be unable to take the test. Exiting fullscreen later is
      // recorded as a violation but does NOT re-block.
      this._requireFullscreen = this.el.dataset.requireFullscreen === "true";
      this._started = false;
      this._gate = document.getElementById("fullscreen-gate");

      this._enterFullscreen = () => {
        const el = document.documentElement;
        const req =
          el.requestFullscreen ||
          el.webkitRequestFullscreen ||
          el.msRequestFullscreen;
        if (req) req.call(el).catch(() => {});
      };

      this._isFullscreen = () =>
        !!(document.fullscreenElement || document.webkitFullscreenElement);

      this._syncGate = () => {
        // Focus mode (hide side-nav, show the header Exit) is tied to whether the
        // assessment currently REQUIRES full screen — i.e. it turns on the moment
        // the student starts (require_fullscreen flips true), not only once full
        // screen actually engages, and turns off when the assessment ends
        // (results phase). Toggled on <body> — outside the LiveView-managed DOM —
        // so frequent re-renders (e.g. the MCQ timer) never reset it.
        document.body.classList.toggle("assessment-focus", this._requireFullscreen);
        if (!this._requireFullscreen) {
          if (this._gate) this._gate.classList.add("hidden");
          return;
        }
        // STRICT: the assessment is only usable in full screen. Show the gate
        // whenever we're not in full screen — so exiting full screen mid-exam
        // re-blocks and forces the student to re-enter to continue.
        if (this._gate) {
          if (this._isFullscreen()) this._gate.classList.add("hidden");
          else this._gate.classList.remove("hidden");
        }
      };

      this._onFullscreenChange = () => {
        if (this._isFullscreen()) {
          this._started = true;
        } else if (this._started) {
          // Exited fullscreen after starting → recorded violation, but do NOT
          // re-block the test.
          this.pushEvent("integrity_violation", { type: "fullscreen_exit" });
        }
        this._syncGate();
      };
      document.addEventListener("fullscreenchange", this._onFullscreenChange);
      document.addEventListener(
        "webkitfullscreenchange",
        this._onFullscreenChange,
      );

      // Delegated click for the gate button — the gate may be rendered LATER
      // (only after "Start Assessment"), so we can't bind the button directly.
      this._gateClickHandler = (e) => {
        if (!e.target.closest) return;
        // Two ways to enter full screen, both handled here so the request runs
        // synchronously inside the real user click (required by the browser):
        //   1. the gate overlay button (#enter-fullscreen-btn), and
        //   2. an assessment's own "Start/Begin" button, marked
        //      [data-enter-fullscreen], so starting the assessment enters full
        //      screen in the SAME click — no separate gate step.
        if (
          e.target.closest("#enter-fullscreen-btn") ||
          e.target.closest("[data-enter-fullscreen]")
        ) {
          // Enter fullscreen; fullscreenchange hides the gate once it engages.
          // If it can't (iframe/policy) the gate stays and the student uses the
          // Exit link — never forced to take the exam outside full screen.
          this._started = true;
          this._enterFullscreen();
          this._syncGate();
        }
      };
      document.addEventListener("click", this._gateClickHandler);

      // Show the gate initially if fullscreen is required and not yet active.
      this._syncGate();

      // Server can force-submit (e.g. too many violations) → leave fullscreen.
      this.handleEvent("exit_fullscreen", () => {
        if (document.exitFullscreen && this._isFullscreen()) {
          document.exitFullscreen().catch(() => {});
        }
      });
    },

    updated() {
      // require_fullscreen can flip on only after "Start Assessment" is clicked,
      // and the gate element is rendered at that point — re-read both and sync.
      this._requireFullscreen = this.el.dataset.requireFullscreen === "true";
      this._gate = document.getElementById("fullscreen-gate");
      this._syncGate();
    },

    destroyed() {
      document.removeEventListener("copy", this._onCopy);
      document.removeEventListener("cut", this._onCut);
      document.removeEventListener("paste", this._onPaste);
      document.removeEventListener("contextmenu", this._onContextMenu);
      document.removeEventListener("keydown", this._onKeyDown);
      document.removeEventListener(
        "visibilitychange",
        this._onVisibilityChange,
      );
      window.removeEventListener("blur", this._onBlur);
      window.removeEventListener("focus", this._onFocus);
      document.removeEventListener(
        "fullscreenchange",
        this._onFullscreenChange,
      );
      document.removeEventListener(
        "webkitfullscreenchange",
        this._onFullscreenChange,
      );
      document.removeEventListener("click", this._gateClickHandler);
      // Restore the side-nav when leaving the assessment.
      document.body.classList.remove("assessment-focus");
    },
  },

  MessageCard: {
    mounted() {
      this.el.style.opacity = "0";
      requestAnimationFrame(() => {
        this.el.classList.add("animate-slide-in");
      });
    },
  },

  ScrollToBottom: {
    mounted() {
      this.scrollToBottom();
      this.observer = new MutationObserver(() => this.scrollToBottom());
      this.observer.observe(this.el, { childList: true, subtree: true });
    },
    updated() {
      this.scrollToBottom();
    },
    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight;
    },
    destroyed() {
      if (this.observer) this.observer.disconnect();
    },
  },

  WordCounter: {
    mounted() {
      const display = document.getElementById("word-count-display");
      const limit = parseInt(this.el.getAttribute("maxlength") || "2000", 10);
      this.el.addEventListener("input", () => {
        const chars = this.el.value.length;
        if (display) {
          display.textContent = `${chars} / ${limit.toLocaleString()} characters`;
          display.className =
            chars > limit
              ? "text-xs text-red-600 mt-1 font-medium"
              : "text-xs text-gray-500 mt-1";
        }
      });
    },
  },

  // Checks (and, on request, asks for) microphone permission BEFORE a voice
  // assessment starts, so a student never lands on a recording screen only to
  // discover the browser has the mic blocked. Reports every state change to the
  // LiveView as `mic_permission`; the server decides what the gate renders.
  //
  // Reports carry a `source`: "check" is the cheap Permissions API read (a hint
  // only — it can say "granted" while getUserMedia still fails because the OS
  // or another app is holding the mic), while "request" is the result of a real
  // getUserMedia probe. Only "request" reports are proof the mic actually works.
  MicGate: {
    mounted() {
      this._permStatus = null;
      this._onPermChange = null;

      this.check();
      this.handleEvent("request_mic_permission", () => this.request());
    },

    destroyed() {
      this.detachPermissionListener();
    },

    supported() {
      return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
    },

    async check() {
      // No getUserMedia at all — typically an insecure (non-HTTPS) origin.
      if (!this.supported()) return this.report("unsupported", null, "check");

      try {
        const status = await navigator.permissions.query({
          name: "microphone",
        });
        this.attachPermissionListener(status);
        this.report(status.state, null, "check"); // "granted" | "denied" | "prompt"
      } catch (_err) {
        // Some browsers don't expose the "microphone" permission name. We
        // can't know the state without prompting, so treat it as promptable.
        this.report("prompt", null, "check");
      }
    },

    attachPermissionListener(status) {
      this.detachPermissionListener();
      this._permStatus = status;
      // Re-report if the student flips the site permission mid-session.
      this._onPermChange = () => this.report(status.state, null, "check");
      status.addEventListener("change", this._onPermChange);
    },

    detachPermissionListener() {
      if (this._permStatus && this._onPermChange) {
        this._permStatus.removeEventListener("change", this._onPermChange);
      }
      this._permStatus = null;
      this._onPermChange = null;
    },

    async request() {
      if (!this.supported()) return this.report("unsupported", null, "request");

      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: true,
        });
        // A granted permission is not the same as a usable mic: an OS-level
        // block or a device held by another app still yields a track-less or
        // dead stream. Only call it granted if we actually got a live track.
        const track = stream.getAudioTracks()[0];
        const live = !!track && track.readyState === "live";
        // Release the mic straight away — AudioRecorder opens its own stream
        // when the assessment actually starts recording.
        stream.getTracks().forEach((t) => t.stop());

        if (live) {
          this.report("granted", null, "request");
        } else {
          this.report("unavailable", "NoLiveTrack", "request");
        }
      } catch (err) {
        const name = err && err.name;
        // NotAllowedError = the student (or a policy) blocked it. Anything
        // else (NotFoundError, NotReadableError) means there's no usable mic.
        this.report(
          name === "NotAllowedError" || name === "SecurityError"
            ? "denied"
            : "unavailable",
          name,
          "request",
        );
      }
    },

    report(state, detail, source) {
      this.pushEvent("mic_permission", {
        state,
        detail: detail || null,
        source: source || "check",
      });
    },
  },

  AudioRecorder: {
    mounted() {
      this.mediaRecorder = null;
      this.audioChunks = [];
      this.audioContext = null;
      this.analyser = null;
      this.animationFrame = null;
      this.stream = null;
      // Live transcript (Web Speech API) — see startLiveTranscript().
      this.recognition = null;
      this.liveWanted = false;
      this.liveFinal = "";
      this.liveInterim = "";
      this.liveRestarts = 0;
      this.liveRestartTimer = null;

      this.handleEvent("start_recording", () => this.startRecording());
      this.handleEvent("stop_recording", () => this.stopRecording());
      // Discard the current recording WITHOUT transcribing/submitting it
      // (used by the interview "Retry" control so it re-records instead of
      // finalising the answer — Vya-028).
      this.handleEvent("discard_recording", () => this.discardRecording());

      // Auto-start recording when the element has data-autostart="true"
      // (used by JAM when transitioning prep → speak so user doesn't have to click Resume).
      if (this.el.dataset.autostart === "true") {
        this.startRecording();
      }

      // Set transcribed text into the active textarea
      this.handleEvent("set_input_text", (data) => {
        const targets = ["chat-input", "star-response"];
        for (const id of targets) {
          const el = document.getElementById(id);
          if (el) {
            el.value = data.text;
            el.dispatchEvent(new Event("input", { bubbles: true }));
            el.focus();
            break;
          }
        }
      });
    },

    async startRecording() {
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          },
        });
        this.audioChunks = [];

        // Create + START the MediaRecorder FIRST, before tapping the stream for
        // the waveform. Setting up an AudioContext MediaStreamSource on the same
        // track before recording can make the recorder capture silence in some
        // browsers — which then transcribes as a hallucinated "Thank you".
        const mimeType = MediaRecorder.isTypeSupported("audio/webm;codecs=opus")
          ? "audio/webm;codecs=opus"
          : "audio/webm";

        this.mediaRecorder = new MediaRecorder(this.stream, { mimeType });

        this.mediaRecorder.ondataavailable = (e) => {
          if (e.data.size > 0) this.audioChunks.push(e.data);
        };

        this.mediaRecorder.onstop = () => {
          // Discard requested (Retry): drop the audio, don't submit.
          if (this._discard) {
            this._discard = false;
            this.audioChunks = [];
            this.cleanupStream();
            return;
          }

          const blob = new Blob(this.audioChunks, {
            type: this.mediaRecorder.mimeType,
          });
          const reader = new FileReader();
          reader.onloadend = () => {
            // reader.result is "data:audio/webm;...base64,XXXXX"
            const base64 = reader.result.split(",")[1];
            this.pushEvent("audio_recorded", {
              audio_data: base64,
              mime_type: this.mediaRecorder.mimeType,
              size: blob.size,
            });
          };
          reader.readAsDataURL(blob);
          this.cleanupStream();
        };

        // NO timeslice: a timeslice produces a FRAGMENTED webm where only the
        // first fragment carries a valid header, so Whisper only decodes the
        // first ~250ms (a full sentence transcribed to "Hi"). Recording without
        // one yields a single, complete, well-formed webm at stop.
        this.mediaRecorder.start();
        this.pushEvent("recording_started", {});

        // Waveform visualization — set up AFTER recording is live so it can
        // never interfere with capture. Purely cosmetic; failures are ignored.
        try {
          this.audioContext = new AudioContext();
          const source = this.audioContext.createMediaStreamSource(this.stream);
          this.analyser = this.audioContext.createAnalyser();
          this.analyser.fftSize = 256;
          source.connect(this.analyser);
          this.visualize();
        } catch (_vizErr) {
          /* visualization is optional */
        }

        this.startLiveTranscript();
      } catch (err) {
        console.error("Mic access error:", err);
        this.pushEvent("recording_error", {
          reason: err.message || "Microphone access denied",
          // Lets the server tell "the student blocked us" apart from "there is
          // no usable mic" and re-open the permission gate with the right copy.
          name: (err && err.name) || null,
        });
      }
    },

    stopRecording() {
      // Stop the preview immediately so the panel freezes on the last words
      // instead of drifting on while Whisper runs.
      this.stopLiveTranscript();
      if (this.mediaRecorder && this.mediaRecorder.state !== "inactive") {
        this.mediaRecorder.stop();
      }
    },

    discardRecording() {
      this.stopLiveTranscript();
      this.clearLiveTranscript();
      if (this.mediaRecorder && this.mediaRecorder.state !== "inactive") {
        this._discard = true;
        this.mediaRecorder.stop(); // onstop sees _discard and skips the upload
      } else {
        this.audioChunks = [];
        this.cleanupStream();
      }
    },

    // ── Live transcript ────────────────────────────────────────────────
    // A client-side preview only, so the student can see they're being heard
    // while they speak. The authoritative transcript is still Whisper on the
    // finished recording — this text is never sent to the server and never
    // scored, which is why a browser without SpeechRecognition (Firefox, some
    // Safari builds) can just say so and carry on recording normally.
    //
    // The panel is rendered by VoiceTranscript.live_transcript/1 under
    // phx-update="ignore", so writing into it directly can't be clobbered by a
    // LiveView patch (an audio_level tick arrives every 500ms).

    livePanel() {
      return document.querySelector("[data-live-transcript]");
    },

    startLiveTranscript() {
      const panel = this.livePanel();
      if (!panel || panel.dataset.liveTranscript === "off") return;

      const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
      this.liveFinal = "";
      this.liveInterim = "";
      this.liveRestarts = 0;
      this.renderLiveTranscript("", "");

      if (!SR) return this.setLiveStatus("unsupported");

      try {
        const rec = new SR();
        rec.continuous = true;
        rec.interimResults = true;
        rec.lang = panel.dataset.lang || "en-IN";

        rec.onresult = (e) => {
          let interim = "";
          for (let i = e.resultIndex; i < e.results.length; i++) {
            const result = e.results[i];
            // Chunks arrive without separators, so plain concatenation glues
            // the last word of one to the first of the next ("workhard").
            if (result.isFinal) this.appendLiveFinal(result[0].transcript);
            else interim += result[0].transcript;
          }
          // Held so it can be committed if the session ends before finalising
          // it — see commitLiveInterim().
          this.liveInterim = interim.trim();
          // Words are arriving, so whatever made the last session end has
          // recovered — forget the restart budget.
          this.liveRestarts = 0;
          this.setLiveStatus("listening");
          this.renderLiveTranscript(this.liveFinal, this.liveInterim);
        };

        rec.onerror = (e) => {
          const err = e && e.error;
          // Only a refused recogniser is fatal. Everything else — a pause with
          // no speech, Chrome's periodic "network" blip against its cloud
          // engine, an aborted session — is transient, and `onend` fires right
          // after with the restart. Killing the preview on those was why it
          // stopped printing part-way through a long answer.
          if (err === "not-allowed" || err === "service-not-allowed") {
            this.liveWanted = false;
            this.setLiveStatus("unavailable");
          } else if (err && err !== "no-speech" && err !== "aborted") {
            this.setLiveStatus("reconnecting");
          }
        };

        rec.onend = () => {
          // Must run before the early return: a session can end still holding
          // an un-finalised interim result, and the next session starts from a
          // clean results list. Speaking a single word into silence hits this
          // every time — Chrome ends on "no-speech" with the word never
          // finalised — which is why short answers showed nothing at all.
          this.commitLiveInterim();

          // Chrome ends a recognition session on its own — after a few seconds
          // of silence, and again every minute or so regardless. Restart it
          // while the MediaRecorder is still running so the preview covers the
          // whole answer rather than just the opening lines.
          if (!this.liveWanted) return;
          this.scheduleLiveRestart();
        };

        this.recognition = rec;
        this.liveWanted = true;
        rec.start();
        this.setLiveStatus("listening");
      } catch (_err) {
        // Constructing or starting the recogniser can throw on browsers that
        // expose the API but don't back it. Recording itself is unaffected.
        this.liveWanted = false;
        this.setLiveStatus("unavailable");
      }
    },

    // Joins a finalised chunk onto the running text with a space. The engine
    // hands back bare phrases with no leading separator.
    appendLiveFinal(text) {
      const chunk = (text || "").trim();
      if (!chunk) return;
      this.liveFinal = this.liveFinal ? this.liveFinal + " " + chunk : chunk;
    },

    // Promotes the in-flight interim text to final. Called whenever a
    // recognition session ends, so nothing spoken is dropped on the floor.
    commitLiveInterim() {
      if (!this.liveInterim) return;
      this.appendLiveFinal(this.liveInterim);
      this.liveInterim = "";
      this.renderLiveTranscript(this.liveFinal, "");
    },

    scheduleLiveRestart() {
      if (!this.liveWanted || !this.recognition) return;

      // A restart too soon after `onend` throws InvalidStateError; a short delay
      // lets the engine settle. The budget only guards a recogniser that is
      // ending immediately every time — any result resets it, so a normal
      // answer restarts as often as it needs to.
      if (this.liveRestarts >= 12) {
        this.liveWanted = false;
        return this.setLiveStatus("offline");
      }

      this.liveRestarts += 1;
      clearTimeout(this.liveRestartTimer);
      this.liveRestartTimer = setTimeout(() => {
        if (!this.liveWanted || !this.recognition) return;
        try {
          this.recognition.start();
        } catch (_err) {
          // Already starting, or still shutting down — try once more.
          this.scheduleLiveRestart();
        }
      }, 250);
    },

    stopLiveTranscript() {
      this.liveWanted = false;
      clearTimeout(this.liveRestartTimer);
      this.liveRestartTimer = null;
      this.commitLiveInterim();
      if (this.recognition) {
        try {
          this.recognition.stop();
        } catch (_err) {
          /* already stopped */
        }
        this.recognition = null;
      }
      // A preview that caught nothing is not a lost answer — the recording is
      // still on its way to Whisper — so say so rather than leaving an empty
      // box that reads like a failure.
      this.setLiveStatus(this.liveFinal ? "idle" : "pending");
    },

    renderLiveTranscript(final, interim) {
      const panel = this.livePanel();
      if (!panel) return;

      const finalEl = panel.querySelector("[data-live-transcript-final]");
      const interimEl = panel.querySelector("[data-live-transcript-interim]");
      const placeholder = panel.querySelector("[data-live-transcript-empty]");
      const body = panel.querySelector("[data-live-transcript-body]");

      // Measure BEFORE writing: whether the newest words were in view decides
      // whether we follow them. A student who scrolled back to re-read an
      // earlier sentence keeps their place instead of being yanked to the
      // bottom on every interim result.
      const follow =
        !body ||
        body.scrollHeight - body.scrollTop - body.clientHeight < 24;

      if (finalEl) finalEl.textContent = final;
      if (interimEl) interimEl.textContent = interim ? (final ? " " : "") + interim : "";
      if (placeholder) placeholder.classList.toggle("hidden", !!(final || interim));
      if (body && follow) body.scrollTop = body.scrollHeight;
    },

    clearLiveTranscript() {
      this.liveFinal = "";
      this.liveInterim = "";
      this.renderLiveTranscript("", "");
    },

    setLiveStatus(state) {
      const panel = this.livePanel();
      if (!panel) return;
      const statusEl = panel.querySelector("[data-live-transcript-status]");
      if (!statusEl) return;

      const copy = {
        listening: "Listening…",
        reconnecting: "Reconnecting…",
        idle: "Preview stopped — the accurate transcript follows shortly.",
        pending: "The accurate transcript is being prepared from your recording.",
        unsupported: "Live preview isn't supported in this browser — your answer is still being recorded and transcribed.",
        unavailable: "Live preview unavailable — your answer is still being recorded and transcribed.",
        offline: "Live preview paused — your answer is still being recorded and transcribed.",
      };

      statusEl.textContent = copy[state] || "";
      panel.dataset.liveTranscriptState = state;
    },

    visualize() {
      if (!this.analyser) return;
      const dataArray = new Uint8Array(this.analyser.frequencyBinCount);

      // Find waveform bars container (rendered by the Elixir waveform component)
      const waveformContainer = this.el.querySelector(
        ".flex.items-center.justify-center.gap-1",
      );
      const bars = waveformContainer
        ? waveformContainer.querySelectorAll("div")
        : [];

      const tick = () => {
        this.analyser.getByteFrequencyData(dataArray);
        const sum = dataArray.reduce((a, b) => a + b, 0);
        const avg = sum / dataArray.length;
        const level = Math.min(100, Math.round((avg / 255) * 100 * 2));

        // Update waveform bars directly in JS (no server round-trip)
        if (bars.length > 0) {
          bars.forEach((bar, i) => {
            const variation = ((i * 7 + level * 3) % 30) - 15;
            const height = Math.min(95, Math.max(8, level + variation));
            bar.style.height = `${height}%`;
            bar.classList.remove("bg-gray-300");
            bar.classList.add("bg-orange-500");
          });
        }

        // Only push to server occasionally (for state persistence, not UI)
        if (!this._lastPush || Date.now() - this._lastPush > 500) {
          this.pushEvent("audio_level", { level });
          this._lastPush = Date.now();
        }

        this.animationFrame = requestAnimationFrame(tick);
      };
      tick();
    },

    cleanupStream() {
      this.stopLiveTranscript();
      if (this.animationFrame) {
        cancelAnimationFrame(this.animationFrame);
        this.animationFrame = null;
      }
      if (this.audioContext) {
        this.audioContext.close();
        this.audioContext = null;
        this.analyser = null;
      }
      if (this.stream) {
        this.stream.getTracks().forEach((t) => t.stop());
        this.stream = null;
      }
    },

    destroyed() {
      this.stopRecording();
      this.cleanupStream();
    },
  },

  AnimatedDonutChart: {
    mounted() {
      const circle = this.el.querySelector("[data-donut-circle]");
      if (!circle) return;
      const target = parseFloat(this.el.dataset.score) || 0;
      const circumference = 534.07;

      circle.style.strokeDashoffset = String(circumference);

      requestAnimationFrame(() => {
        setTimeout(() => {
          circle.style.transition = "stroke-dashoffset 1.5s ease-out";
          circle.style.strokeDashoffset = String(
            circumference * (1 - target / 100),
          );
        }, 200);
      });
    },
  },

  AccordionToggle: {
    mounted() {
      this.el.addEventListener("click", () => {
        const content = this.el.nextElementSibling;
        const icon = this.el.querySelector("[data-accordion-icon]");
        if (content) content.classList.toggle("hidden");
        if (icon) icon.classList.toggle("rotate-180");
      });
    },
  },

  PageTransition: {
    mounted() {
      this.el.classList.add("animate-fade-in");
    },
    updated() {
      this.el.classList.remove("animate-fade-in");
      void this.el.offsetWidth;
      this.el.classList.add("animate-fade-in");
    },
  },

  ToastContainer: {
    mounted() {
      this.handleEvent("show_toast", (data) => {
        this.showToast(data);
      });

      this.handleEvent("download_text_file", (data) => {
        const { content, filename, content_type } = data;
        const blob = new Blob([content], {
          type: content_type || "text/plain",
        });
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement("a");
        link.href = url;
        link.download = filename || "download.txt";
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        window.URL.revokeObjectURL(url);
      });
    },

    showToast(data) {
      const { type, message, duration = 5000 } = data;
      const toastId = `toast-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

      // Create toast HTML
      const toastHTML = `
        <div id="${toastId}" class="toast toast-top toast-end z-50 cursor-pointer">
          <div class="alert ${this.getAlertClass(type)} min-w-0 max-w-sm shadow-lg">
            ${this.getIcon(type)}
            <span class="text-sm font-medium">${message}</span>
            <button class="btn btn-sm btn-circle btn-ghost ml-2" onclick="this.closest('.toast').remove()">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>
        </div>
      `;

      // Add to container
      this.el.insertAdjacentHTML("beforeend", toastHTML);

      // Auto-dismiss
      setTimeout(() => {
        const toastEl = document.getElementById(toastId);
        if (toastEl) {
          toastEl.style.transition = "opacity 0.3s ease-out";
          toastEl.style.opacity = "0";

          setTimeout(() => {
            if (toastEl && toastEl.parentNode) {
              toastEl.remove();
            }
          }, 300);
        }
      }, duration);
    },

    getAlertClass(type) {
      switch (type) {
        case "success":
          return "alert-success";
        case "error":
          return "alert-error";
        case "warning":
          return "alert-warning";
        case "info":
          return "alert-info";
        default:
          return "alert-info";
      }
    },

    getIcon(type) {
      switch (type) {
        case "success":
          return '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>';
        case "error":
          return '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>';
        case "warning":
          return '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.728-.833-2.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z"></path></svg>';
        case "info":
          return '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>';
        default:
          return '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>';
      }
    },
  },

  AudioPlayer: {
    mounted() {
      this.audioCache = {};
      this.currentAudio = null;
      this.audioUnlocked = false;
      this.pendingBlob = null;
      this.muted = false;

      // Unlock audio on any user click within the page.
      // Uses Web Audio API to create a silent buffer — avoids CSP issues with data URIs.
      this._unlockAudio = () => {
        if (this.audioUnlocked) return;
        try {
          const ctx = new (window.AudioContext || window.webkitAudioContext)();
          const buffer = ctx.createBuffer(1, 1, 22050);
          const source = ctx.createBufferSource();
          source.buffer = buffer;
          source.connect(ctx.destination);
          source.start(0);
          ctx.resume().then(() => {
            this.audioUnlocked = true;
            ctx.close();
            if (this.pendingBlob && !this.muted) {
              this.playBlob(this.pendingBlob);
              this.pendingBlob = null;
            }
          });
        } catch (e) {}
      };
      document.addEventListener("click", this._unlockAudio, {
        once: false,
        capture: true,
      });

      this.handleEvent("play_audio", (data) => {
        const { audio_data, audio_type, audio_key } = data;
        if (!audio_data) return;

        const byteCharacters = atob(audio_data);
        const byteArray = new Uint8Array(byteCharacters.length);
        for (let i = 0; i < byteCharacters.length; i++) {
          byteArray[i] = byteCharacters.charCodeAt(i);
        }
        const blob = new Blob([byteArray], {
          type: `audio/${audio_type || "mp3"}`,
        });

        this.audioCache[audio_key] = blob;

        if (this.muted) return;

        if (this.audioUnlocked) {
          this.playBlob(blob);
        } else {
          this.pendingBlob = blob;
        }
      });

      this.handleEvent("stop_audio", () => {
        if (this.currentAudio) {
          this.currentAudio.pause();
          this.currentAudio.currentTime = 0;
          URL.revokeObjectURL(this.currentAudio.src);
          this.currentAudio = null;
        }
        // Also stop browser TTS
        if (window.speechSynthesis.speaking) {
          window.speechSynthesis.cancel();
        }
      });

      this.handleEvent("mute_audio", () => {
        this.muted = true;
        if (this.currentAudio) {
          this.currentAudio.pause();
          this.currentAudio.currentTime = 0;
          URL.revokeObjectURL(this.currentAudio.src);
          this.currentAudio = null;
        }
        if (window.speechSynthesis.speaking) {
          window.speechSynthesis.cancel();
        }
      });

      this.handleEvent("unmute_audio", () => {
        this.muted = false;
      });

      this.handleEvent("replay_audio", (data) => {
        const { audio_key } = data;
        if (this.muted) return;
        const blob = this.audioCache[audio_key];
        if (blob) {
          this.playBlob(blob);
        }
      });

      // Browser TTS via Web Speech API (replaces server-side gTTS)
      this.handleEvent("speak_text", (data) => {
        const { text, audio_key } = data;
        if (this.muted || !text) return;

        // Stop any current speech
        if (window.speechSynthesis.speaking) {
          window.speechSynthesis.cancel();
        }

        const utterance = new SpeechSynthesisUtterance(text);
        utterance.lang = "en-US";
        utterance.rate = 1.0;
        utterance.pitch = 1.0;

        // Try to pick a natural-sounding voice
        const voices = window.speechSynthesis.getVoices();
        const preferred =
          voices.find(
            (v) =>
              v.lang.startsWith("en") &&
              (v.name.includes("Google") ||
                v.name.includes("Natural") ||
                v.name.includes("Samantha")),
          ) || voices.find((v) => v.lang.startsWith("en"));
        if (preferred) utterance.voice = preferred;

        this.currentUtterance = utterance;
        window.speechSynthesis.speak(utterance);
      });
    },

    playBlob(blob) {
      if (this.muted) return;

      if (this.currentAudio) {
        this.currentAudio.pause();
        this.currentAudio.currentTime = 0;
        URL.revokeObjectURL(this.currentAudio.src);
        this.currentAudio = null;
      }

      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      this.currentAudio = audio;

      audio.addEventListener("ended", () => {
        URL.revokeObjectURL(url);
        this.currentAudio = null;
      });

      audio.addEventListener("error", () => {
        URL.revokeObjectURL(url);
        this.currentAudio = null;
      });

      audio.play().catch(() => {});
    },

    destroyed() {
      if (this.currentAudio) {
        this.currentAudio.pause();
        URL.revokeObjectURL(this.currentAudio.src);
        this.currentAudio = null;
      }
      this.audioCache = {};
      if (this._unlockAudio) {
        document.removeEventListener("click", this._unlockAudio, {
          capture: true,
        });
      }
    },
  },

  // DEPRECATED — kept only as a null-object so legacy `phx-hook="PdfDownload"`
  // markers (admin leaderboard / specialization exports) don't log a "hook not
  // found" warning. Student report PDFs are now generated server-side via
  // ChromicPDF; admin exports will migrate next.
  PdfDownload: {
    mounted() {},
  },
};

// Client-side countdown timer hook for smooth visual updates on remote servers.
// The server remains authoritative for phase transitions (auto-submit, etc.),
// but visual countdown runs locally to avoid WebSocket latency jitter.
// Client-side countdown timer for JAM session.
// Listens for push_events from LiveView to start/stop/sync the timer.
// This avoids relying on DOM patching (updated()) which is unreliable with nested hooks.
Hooks.CountdownTimer = {
  mounted() {
    this.localSeconds = parseInt(this.el.dataset.seconds) || 0;
    this.total = parseInt(this.el.dataset.total) || 60;
    this.displayEl = this.el.querySelector("[data-countdown-display]");
    this.circleEl = this.el.querySelector("[data-countdown-circle]");
    this.circleTextEl = this.el.querySelector("[data-countdown-circle-text]");
    this.interval = null;

    // Listen for server events
    this.handleEvent("countdown_start", ({ id, seconds, total }) => {
      if (id === this.el.id) {
        this.localSeconds = seconds;
        this.total = total || this.total;
        this.startLocalTick();
      }
    });

    this.handleEvent("countdown_stop", ({ id }) => {
      if (id === this.el.id) {
        this.stopLocalTick();
      }
    });

    this.handleEvent("countdown_sync", ({ id, seconds }) => {
      if (id === this.el.id && Math.abs(this.localSeconds - seconds) > 2) {
        this.localSeconds = seconds;
        this.render();
      }
    });

    // Also check data-active on mount (for page reload scenarios)
    if (this.el.dataset.active === "true" && this.localSeconds > 0) {
      this.startLocalTick();
    }

    this.render();
  },

  updated() {
    // Re-read data attributes on LiveView patch
    const newSeconds = parseInt(this.el.dataset.seconds) || 0;
    const newActive = this.el.dataset.active === "true";

    if (newActive && !this.interval) {
      this.localSeconds = newSeconds;
      this.startLocalTick();
    } else if (!newActive && this.interval) {
      this.stopLocalTick();
      this.localSeconds = newSeconds;
      this.render();
    } else if (Math.abs(this.localSeconds - newSeconds) > 2) {
      this.localSeconds = newSeconds;
      this.render();
    }
  },

  destroyed() {
    this.stopLocalTick();
  },

  startLocalTick() {
    this.stopLocalTick();
    this.render();
    this.interval = setInterval(() => {
      if (this.localSeconds > 0) {
        this.localSeconds--;
        this.render();
      } else {
        this.stopLocalTick();
      }
    }, 1000);
  },

  stopLocalTick() {
    if (this.interval) {
      clearInterval(this.interval);
      this.interval = null;
    }
  },

  render() {
    const secs = Math.max(0, this.localSeconds);

    if (this.displayEl) {
      if (this.total <= 15) {
        this.displayEl.textContent = `${secs}`;
      } else {
        const mins = Math.floor(secs / 60);
        const remainSecs = secs % 60;
        this.displayEl.textContent = `${String(mins).padStart(2, "0")}:${String(remainSecs).padStart(2, "0")}`;
      }
    }

    if (this.circleEl) {
      const pct = this.total > 0 ? secs / this.total : 0;
      const circumference = 2 * Math.PI * 18;
      const offset = circumference * (1 - pct);
      this.circleEl.style.strokeDasharray = `${circumference}`;
      this.circleEl.style.strokeDashoffset = `${offset}`;
      // Change color: green > 10s, red <= 10s
      this.circleEl.setAttribute("stroke", secs > 10 ? "#22c55e" : "#ef4444");
    }

    if (this.circleTextEl) {
      const mins = Math.floor(secs / 60);
      const remainSecs = secs % 60;
      this.circleTextEl.textContent = `${String(mins).padStart(2, "0")}:${String(remainSecs).padStart(2, "0")}`;
    }
  },
};

// Sidebar collapse/expand toggle for admin dashboard
Hooks.SidebarToggle = {
  mounted() {
    this.expandedWidth = this.el.dataset.expandedWidth || "256px";
    this.collapsedWidth = this.el.dataset.collapsedWidth || "72px";
    this.applySavedState();

    this.el.addEventListener("toggle-sidebar", () => {
      const isCollapsed = this.el.classList.contains("sidebar-collapsed");
      if (isCollapsed) {
        this.expand();
      } else {
        this.collapse();
      }
    });
  },

  // Re-apply state after LiveView patches (tab switches, etc.)
  updated() {
    this.applySavedState();
  },

  applySavedState() {
    if (localStorage.getItem("sidebar-collapsed") === "true") {
      this.collapse(false);
    } else {
      this.expand(false);
    }
  },

  collapse(save = true) {
    this.el.classList.add("sidebar-collapsed");
    this.el.style.width = this.collapsedWidth;
    this.el
      .querySelectorAll(".sidebar-label")
      .forEach((l) => l.classList.add("hidden"));
    this.el
      .querySelectorAll(".sidebar-expanded-only")
      .forEach((l) => l.classList.add("hidden"));
    this.el
      .querySelectorAll(".sidebar-expanded-icon")
      .forEach((l) => l.classList.add("hidden"));
    this.el
      .querySelectorAll(".sidebar-collapsed-icon")
      .forEach((l) => l.classList.remove("hidden"));
    if (save) localStorage.setItem("sidebar-collapsed", "true");
  },

  expand(save = true) {
    this.el.classList.remove("sidebar-collapsed");
    this.el.style.width = this.expandedWidth;
    this.el
      .querySelectorAll(".sidebar-label")
      .forEach((l) => l.classList.remove("hidden"));
    this.el
      .querySelectorAll(".sidebar-expanded-only")
      .forEach((l) => l.classList.remove("hidden"));
    this.el
      .querySelectorAll(".sidebar-expanded-icon")
      .forEach((l) => l.classList.remove("hidden"));
    this.el
      .querySelectorAll(".sidebar-collapsed-icon")
      .forEach((l) => l.classList.add("hidden"));
    if (save) localStorage.setItem("sidebar-collapsed", "false");
  },
};

// Show/hide password toggle for the shared <.input type="password"> component
// Triggers a browser download from a server-pushed content blob event
// (content, filename, mime), used for CSV export buttons.
//
// NOTE: this listens on "download_content", not "download_file" — the
// "download_file" event name is also used by the Hooks.DownloadFile hook
// (fetch-by-url downloads), which is mounted on the same pages. Reusing
// that name here made both hooks fire on every push: this one saved the
// blob correctly, but DownloadFile's fetch(undefined) failed and its
// catch-block opened an about:blank tab via window.open as a fallback.
const downloadBlob = ({ content, filename, mime }) => {
  const blob = new Blob([content], { type: mime || "text/plain" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename || "download.csv";
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
};

Hooks.FileDownload = {
  mounted() {
    this.handleEvent("download_content", downloadBlob);
  },
};

Hooks.PasswordToggle = {
  mounted() {
    this.visible = false;
    this.input = this.el.querySelector("input");
    this.showIcon = this.el.querySelector("[data-icon-show]");
    this.hideIcon = this.el.querySelector("[data-icon-hide]");
    const button = this.el.querySelector("[data-password-toggle]");
    if (button) {
      button.addEventListener("click", () => this.toggle(button));
    }
    this.apply();
  },

  // Re-apply after LiveView patches (e.g. phx-change="validate") so morphdom
  // resetting the input type back to "password" doesn't undo the user's choice.
  updated() {
    this.apply();
  },

  toggle(button) {
    this.visible = !this.visible;
    if (button) {
      button.setAttribute(
        "aria-label",
        this.visible ? "Hide password" : "Show password",
      );
    }
    this.apply();
  },

  apply() {
    if (!this.input) return;
    this.input.type = this.visible ? "text" : "password";
    if (this.showIcon) this.showIcon.classList.toggle("hidden", this.visible);
    if (this.hideIcon) this.hideIcon.classList.toggle("hidden", !this.visible);
  },
};

// Restricts an input to digits only, live-truncating at a max length
// (data-maxlength, default 10) as the user types — used for phone numbers.
Hooks.DigitsOnly = {
  mounted() {
    this.maxLength = parseInt(this.el.dataset.maxlength, 10) || 10;
    this.handler = () => {
      const digits = this.el.value.replace(/\D/g, "").slice(0, this.maxLength);
      if (digits !== this.el.value) this.el.value = digits;
    };
    this.el.addEventListener("input", this.handler);
  },
  destroyed() {
    this.el.removeEventListener("input", this.handler);
  },
};

Hooks.LettersOnly = {
  mounted() {
    this.handler = () => {
      const letters = this.el.value.replace(/[^a-zA-Z\s]/g, "");
      if (letters !== this.el.value) this.el.value = letters;
    };
    this.el.addEventListener("input", this.handler);
  },
  destroyed() {
    this.el.removeEventListener("input", this.handler);
  },
};

// 24-hour deadline countdown for the mini project submission window.
// Reads data-deadline (unix ms), ticks every second, shifts colour orange
// (<6h) then red (<1h), and pushes deadline_reached_client to the server at zero.
Hooks.DeadlineTimer = {
  mounted() {
    this._start();
  },
  updated() {
    this._start();
  },
  destroyed() {
    clearInterval(this._timer);
  },
  _start() {
    clearInterval(this._timer);
    const deadline = parseInt(this.el.dataset.deadline, 10);
    const tick = () => {
      const rem = deadline - Date.now();
      if (rem <= 0) {
        this.el.textContent = "00:00:00";
        this.el.classList.add("text-red-600");
        clearInterval(this._timer);
        this.pushEvent("deadline_reached_client", {});
        return;
      }
      const h = Math.floor(rem / 3600000);
      const m = Math.floor((rem % 3600000) / 60000);
      const s = Math.floor((rem % 60000) / 1000);
      this.el.textContent = `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
      if (rem < 3_600_000) {
        this.el.classList.remove("text-gray-800", "text-orange-500");
        this.el.classList.add("text-red-600");
      } else if (rem < 21_600_000) {
        this.el.classList.remove("text-gray-800", "text-red-600");
        this.el.classList.add("text-orange-500");
      }
    };
    tick();
    this._timer = setInterval(tick, 1000);
  },
};

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page — duplicate tabs (see the
// single-tab guard above) stay disconnected so they don't open a second
// live session behind the blocking overlay.
if (isPrimaryTab) {
  liveSocket.connect();
}

// File download via Blob — avoids data URL length limits and LV link interception
window.addEventListener("phx:download-file", (e) => {
  const { content, filename, mime, base64 } = e.detail;
  // Binary files (e.g. PDFs) are sent base64-encoded — decode to bytes so the
  // Blob isn't corrupted; text callers still pass raw content unchanged.
  let part = content;
  if (base64) {
    const bin = atob(content);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    part = bytes;
  }
  const blob = new Blob([part], { type: mime || "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename || "Vyaasa-download";
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
});

// Copy to clipboard handler (used by share profile)
window.addEventListener("phx:copy_to_clipboard", (e) => {
  if (e.detail && e.detail.text) {
    navigator.clipboard.writeText(e.detail.text).catch(() => {
      // Fallback for older browsers
      const ta = document.createElement("textarea");
      ta.value = e.detail.text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
    });
  }
});

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// ── SweetAlert2 confirmations ────────────────────────────────────────────────
// Replace the browser's native window.confirm (used by `data-confirm` on
// phx-click buttons and phoenix_html links) with a SweetAlert2 dialog, app-wide
// and without touching every template. We intercept the click in the CAPTURE
// phase — before LiveView / phoenix_html handle it — cancel it, show the async
// dialog, and only on confirmation replay the click with `data-confirm` removed.
window.Swal = Swal;

const SWAL_CONFIRM_DEFAULTS = {
  icon: "warning",
  showCancelButton: true,
  confirmButtonText: "Yes, continue",
  cancelButtonText: "Cancel",
  confirmButtonColor: "#f97316", // brand orange
  cancelButtonColor: "#6b7280",
  reverseButtons: true,
  focusCancel: true,
};

document.addEventListener(
  "click",
  (e) => {
    const el = e.target.closest("[data-confirm]");
    // `data-swal-bypass` marks our own replayed click — let it through.
    if (!el || el.dataset.swalBypass === "1") return;

    e.preventDefault();
    e.stopImmediatePropagation();

    const message = el.getAttribute("data-confirm");

    Swal.fire({
      ...SWAL_CONFIRM_DEFAULTS,
      title: "Are you sure?",
      text: message,
    }).then((result) => {
      if (!result.isConfirmed) return;
      // Replay the original interaction without the native confirm so LiveView
      // / phoenix_html handle it normally, then restore the attribute.
      el.dataset.swalBypass = "1";
      el.removeAttribute("data-confirm");
      el.click();
      el.setAttribute("data-confirm", message);
      delete el.dataset.swalBypass;
    });
  },
  true // capture phase — runs before LiveView's bubble-phase listener
);

// Optional: let the server trigger a SweetAlert toast/dialog via
// `push_event(socket, "swal", %{...})` — payload is passed straight to Swal.fire.
window.addEventListener("phx:swal", (e) => {
  if (e.detail) Swal.fire(e.detail);
});
