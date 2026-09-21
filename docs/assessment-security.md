# Assessment Security & Proctoring

Browser-based integrity controls applied to every student assessment. These are
**deterrents + evidence**, not a lockdown: a determined student can still use a
second device or a phone camera. True prevention needs a proctoring service or a
locked-down exam browser (a future "camera" phase).

## Shared building blocks

| Piece | Where | What it does |
|-------|-------|--------------|
| `AssessmentIntegrity` JS hook | `assets/js/app.js` | Fullscreen gate, tab/window-blur detection, copy/paste/right-click/shortcut blocking; pushes `integrity_violation` events |
| Fullscreen gate | each LiveView | Overlay that forces the student into full screen before starting; re-shows on exit |
| `record_violation/…` | each context | Appends `{type, at}` to the session's `metadata.violations` + a running `violation_count` |
| `student_integrity_flags/2` | each context | Turns the log into readable admin flags |
| Admin **Integrity Flags** panel | `tenant_user/dashboard_live.ex` | Aggregates flags across all six assessments per student |

**Violation types:** `tab_switch`, `window_blur` (alt-tab / other monitor), `fullscreen_exit`.
Focus loss is de-duped so one switch = one strike. Admin flags surface at **≥2 violations**.

**Mic false-positive guard** (voice assessments): the mic-permission / OS audio
popup steals focus and would log a false strike. Those assessments ignore focus
loss for an **8-second grace window** when recording starts (not the whole
recording, so alt-tabbing to a script mid-answer is still caught).

---

## Per-assessment summary

| Assessment | Text input | Enforcement | Fullscreen | Paste block | Notable |
|------------|:---------:|-------------|:----------:|:-----------:|---------|
| Objective / MCQ | no | **Auto-submit @ 3** | ✅ | n/a | Server timer + auto-submit on expiry |
| Situational & Behavioral | typed (STAR) | **Auto-finalize @ 3** | ✅ | ✅ | Scores completed rounds; mic grace |
| Psychometric | no (Likert) | Log-only + **validity** | ✅ | n/a | Straight-lining + rapid-answer flags |
| Case Study | typed (prompts) | **Auto-submit @ 3** | ✅ | ✅ | Terminates if all prompts blank |
| JAM | prep notes | Log-only | ✅ | ✅ | Voice; mic grace; catches script-reading |
| Interactive Session | no (voice) | Log-only | ✅ | ✅ | Voice; mic grace; merges with moderation flags |
| Mini Project | take-home | **Authenticity forensics** | n/a | n/a | Not proctored — file/git/viva provenance |

---

## 1. Objective / MCQ
**File:** `live/student/assessment/test_live.ex` · **Store:** `assessment_attempts.metadata`

- Fullscreen gate + tab/window-blur detection + copy/paste/right-click/shortcut blocking.
- **Auto-submit after 3 strikes** (`@violation_limit`): warn → final warning → submit current answers.
- Server-enforced timer (elapsed from `started_at`, so refresh can't reset it) + auto-submit on expiry.
- Fresh, reshuffled questions per retake (Vya-001).
- Admin flag: *"Proctoring: N violations (…)"* + the existing answer-pattern heuristics (all-same-answer, rapid answering).

## 2. Situational & Behavioral
**File:** `live/student/behavioral_live.ex` · **Store:** `student_behavioral_assessments.metadata`

- Fullscreen + tab/blur + **paste blocking** (stops pasted AI-written STAR answers).
- **Auto-finalize after 3 strikes** (2 warnings first):
  - ≥1 round complete → ends and **scores completed round(s)** via the normal report path.
  - 0 rounds complete → session `terminated`, no score.
- **Mic grace** (voice input): ignores focus loss while recording / within 8s of tapping the mic.
- Admin flag: *"Behavioral — proctoring: N violations (…)"*.

## 3. Psychometric
**File:** `live/student/psychometric/psychometric_live.ex` · **Store:** `student_psychometric_assessments.metadata`

Personality test — **can't be cheated by lookup**, so proctoring is secondary and the real
signal is **careless/invalid responding**:

- **Straight-lining** — same Likert answer for ≥85% of questions → flag.
- **Rapid answering** — median time-per-answer < 2s → flag.
- Fullscreen for consistency (skipped when only viewing a completed report); tab/blur logged.
- All **log-only** (never cuts off a personality test).
- Admin flags: *"Psychometric — possible straight-lining (X%)"*, *"… very rapid answers (median Ys)"*.

## 4. Case Study
**File:** `live/student/case_study/case_study_live.ex` · **Store:** `case_study_sessions.metadata` *(added via tenant migration)*

- Fullscreen + tab/blur + **paste blocking** (typed prompt answers).
- **Auto-submit after 3 strikes:** submits typed answers (partial-scored); if all prompts blank → `terminated`, no score (consistent with the empty-submission guard, Vya-034).
- Admin flag: *"Case Study — proctoring: N violations (…)"*.

## 5. JAM (Just-A-Minute)
**File:** `live/student/jam/jam_session_live.ex` · **Store:** `jam_sessions.metadata` *(added via tenant migration)*

Short spoken assessment — main cheat is reading a script off another window while speaking:

- Fullscreen + **window/tab-switch detection** (catches the script-reading) + paste block on prep notes.
- **Log-only** (never cuts off a ~1-min speech).
- **Mic grace** at record start; not whole-recording, so mid-speech alt-tab is still caught.
- Admin flag: *"JAM — proctoring: N violations (…)"*.

## 6. Interactive Session (AI interview)
**File:** `live/student/interview/interview_session_live.ex` · **Store:** `interview_sessions.metadata` *(added via tenant migration)*

- Fullscreen + tab/window-blur + copy/paste/right-click blocking.
- **Log-only** (never interrupts a live conversation); **mic grace** at record start.
- Proctoring flags **merge into the existing** `student_integrity_flags` (alongside content-moderation warnings/terminations), so they appear in the admin panel with no extra wiring.
- Admin flag: *"Interactive Session — proctoring: N violations (…)"*.

## 7. Mini Project — authenticity forensics (not proctoring)
**Files:** `live/student/mini_project/mini_project_live.ex`, `ai/mini_project_forensics.ex`
· **Store:** `mini_project_sessions.metadata.authenticity` *(added via tenant migration)*

Mini Project is a **24h take-home on the student's own machine**, so browser
proctoring is meaningless. Instead we ask **"did *this* student do *this* work
*during* the window?"** and produce an **Authenticity Score (0-100) + flags**.
Everything is **advisory** — it flags for admin review, never auto-fails (metadata
can be stripped/spoofed; AI-detection is probabilistic).

**Three signal sources:**

1. **File metadata** (`analyze_file`) — created/modified/author from PDF (`pdfinfo`)
   and OOXML docx/pptx/xlsx (`docProps/core.xml`). Flags:
   - file **created before the assessment started** (pre-fabricated),
   - **author ≠ student**,
   - **created ≈ modified** within 3 min (downloaded, not authored).

2. **Git commits** (`analyze_repo`, GitHub API — optional repo submission alongside files). Flags:
   - **repo / first commit predates the window** (pre-existing project),
   - **single "dump" commit** (whole project pushed at once),
   - **all commits within 5 minutes**, or **many distinct authors**.

3. **Forensic viva** — viva questions cite a **specific detail from the student's
   actual submission** and probe authorship (things only the real author could
   answer). A **low average viva score** adds an *"struggled to explain their own
   submission"* authorship flag. *(This is the most robust leg — understanding
   can't be faked.)*

Plus a **timing** flag (submitted < 10 min after starting a 24h task).

- Score starts at 100 and each flag subtracts a weight; verdict: ≥80 *looks
  authentic*, ≥50 *review recommended*, else *high risk*.
- Admin flag: *"Mini Project — authenticity N/100: &lt;reasons&gt;"*.

---

## Enforcement policy — why it differs

- **Auto-submit / finalize** (MCQ, Behavioral, Case Study): these have lookup-able / AI-generatable answers, so leaving the test has to have consequences. Behavioral/Case-Study score whatever's done rather than zero an honest slip.
- **Log-only** (Psychometric, JAM, Interactive): personality tests can't be cheated by lookup, and the voice assessments are short/live where a mic-popup false positive shouldn't nuke a real attempt. Evidence goes to the admin instead.
- **Authenticity forensics** (Mini Project): a take-home can't be proctored, so instead of watching the session we verify the *provenance* of the submitted work (file/git metadata) and the student's *understanding* of it (forensic viva).

## Configuration & limits

- Strike limit is `@violation_limit = 3` in each enforcing LiveView (not yet per-tenant configurable).
- Admin flag threshold is **≥2 violations**.
- Mic grace window is **8s**.

## Deploy notes

- The JS hook (`assets/js/app.js`) and `hero-lock-closed` icon change → run an **asset rebuild** (`mix assets.deploy`).
- Four assessments added a `metadata` column via **tenant migration** (Case Study, JAM, Interactive, Mini Project) → runs on deploy via `Release.migrate` (public + all tenant schemas).
- Mini Project uses `pdfinfo` (poppler-utils) for PDF metadata — already present alongside `pdftotext`.

## Not covered (future "camera" phase)

Screenshots / PrintScreen, a second phone or device, and a technically capable
user disabling the client controls. These require external proctoring or a
lockdown browser and are explicitly out of scope for the in-app controls above.
