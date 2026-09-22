# Opik Integration — Change Log & Tracking Guide

**Scope:** observability only. Every change adds tracing data; none changes app behaviour, return values, error handling or UI.
**Opik project:** `Vyaas Demo Test` · **Export:** OpenTelemetry (OTLP/HTTP) → self-hosted Opik (see `config/config.exs`).
**Status:** code complete for all modules; not yet compiled/tested (run `mix compile && mix test`, then one session per module).

---

## 1. How it works (the three Opik concepts we use)

| Concept | What it is in Opik | How we send it |
|---|---|---|
| **Trace / span** | One operation and its LLM calls | Every Groq call (`groq.chat`, `groq.transcribe`, `groq.text_to_speech`) is a span; `Tracing.span/3` opens a parent span (e.g. `interview.submit_answer`) so its calls land in one trace |
| **Thread** | All traces of one assessment session, in order | Span attribute `thread_id` = the session's id |
| **Metadata** | Filterable labels on a trace | Span attributes `opik.metadata.student_id`, `opik.metadata.module`, `opik.metadata.tenant` (Opik only treats the `opik.metadata.` prefix as metadata) |

**Filter examples in Opik:** `metadata.student_id = "<uuid>"` · `metadata.module = "jam"` · `metadata.tenant = "<schema>"`.

**How the ids reach the LLM calls.** The LiveViews run AI work in background Tasks (separate processes), which is why TTS/STT originally arrived as loose traces. Three mechanisms, all fail-safe:

- **Metadata:** set once per LiveView in `mount` (only after the socket is connected). Tasks find it automatically through Elixir's `$callers` chain, so no Task code was changed for metadata.
- **Thread id, scoped:** `Tracing.with_thread_id(id, fun)` sets the id only while `fun` runs, then restores the previous value. It's used in context functions that can also run in reused processes (HTTP request, LiveView, Oban job).
- **Thread id, per Task:** either `put_thread_id(id)` as the first line of a short-lived Task, or an explicit `thread_id:` option on the TTS/STT calls.

---

## 2. Changes by folder and file

About **236 lines added** and **15 lines modified** across **17 files**, with no logic removed. Every changed line is commented `# Opik: …`.

### `lib/vyaasa_campus/ai/` — shared tracing (2 files)

| File | Lines | Change |
|---|---|---|
| `tracing.ex` | +67 | New `put_metadata/1`, `metadata_attributes/0` (own process → `$callers` fallback, never raises), `with_thread_id/2` (scoped, restores previous); `span/3` attaches metadata |
| `groq_client.ex` | +18, ~2 | Optional `thread_id:` on `transcribe_audio/2` and `text_to_speech/2`; the internal `traced/3` prefers the explicit thread id and attaches metadata to every Groq span |

### `lib/vyaasa_campus/contexts/` — module logic (6 files)

| File | Lines | Change |
|---|---|---|
| `interview.ex` | +4 | `put_thread_id(session_id)` in `do_start_session` (the resume-extractor LLM call joins the thread) |
| `jam.ex` | +22, ~3 | `generate_topic`, `change_topic`, `process_audio` → `with_thread_id(jam_session.id)` wrappers around the unchanged bodies (now `do_*`); metadata in `do_force_complete` |
| `psychometric.ex` | +23 | `submit_answer`, `finalize_report` → `with_thread_id(session_id)` wrappers (`do_*`); metadata in `force_complete` |
| `case_study.ex` | +9 | `submit` → `with_thread_id(session.session_token)` wrapper (`do_submit`) |
| `mini_project.ex` | +12, ~1 | `expire_session` → `with_thread_id(session.id)` wrapper (`do_expire_session`); metadata in `force_complete` |
| `mini_project_v4.ex` | +19 | `process_submission`, `finalize` → `with_thread_id(session.id)` wrappers (`do_*`); metadata in `force_complete` |

### `lib/vyaasa_campus/jobs/` (1 file)

| File | Lines | Change |
|---|---|---|
| `ats_resume_processor.ex` | +3 | Metadata (`module: "resume"`) at the top of `process_ats_phase` |

### `lib/vyaasa_campus_web/live/student/` — LiveViews (8 files)

| File | Lines | Change |
|---|---|---|
| `interview/interview_session_live.ex` | +8, ~4 | Metadata in `mount`; session id passed as `thread_id:` to STT (`run_transcription_async/2`) and TTS (`maybe_push_tts`) |
| `behavioral_live.ex` | +8, ~2 | Metadata in `mount`; `thread_id:` on the STT and TTS calls |
| `jam/jam_session_live.ex` | +8, ~1 | Metadata in `mount`; the "explain further" Task wraps `Jam.explain_topic` in `with_thread_id` |
| `psychometric/psychometric_live.ex` | +4 | Metadata in `mount` |
| `case_study/case_study_live.ex` | +4 | Metadata in `mount` |
| `mini_project/mini_project_live.ex` | +19 | Metadata in `mount`; `put_thread_id(session.id)` as the first line of 5 AI Tasks |
| `mini_project/mini_project_v4_live.ex` | +8, ~1 | Metadata in `mount`; scenario-generation Task tagged with `put_thread_id(session.id)` |

---

## 3. How each module is tracked in Opik

Every trace of every module carries **metadata** (`student_id`, `module`, `tenant`). The **thread** column says whether a session's traces are grouped.

### Resume Insights / Resume analysis — **no thread (by design)**
One analysis = one background job = **one trace** (`resume.analyze`, with all its LLM calls as child spans). A thread would only ever hold one item, so it was left out. Find analyses by `metadata.student_id` / `metadata.module = "resume"`.
- **Upload / Re-analyze:** Oban `AtsResumeProcessor` → `resume.analyze` trace.
- **Insights page:** shows stored results, no AI call, no trace.
- **Identical re-upload:** served from `ResumeScoreCache`, no AI call, no trace.

### Interactive Session (interview) — **thread = interview session UUID** ✅ verified in Opik
| Feature | Opik traces in the thread |
|---|---|
| Start (resume indexing) | `groq.chat` (skill extractor) → `interview.new_session` → `interview.greeting` |
| Greeting / question narration | `groq.text_to_speech` |
| Begin | `interview.proceed` |
| Spoken answer | `groq.transcribe` → `interview.submit_answer` (evaluate + next question) |
| Closing | `groq.text_to_speech` ("thanks") |

### JAM — **thread = `jam_session.id`**
| Feature | Opik traces in the thread |
|---|---|
| Topic | `groq.chat` + `groq.text_to_speech` |
| Explain further | `groq.chat` + `groq.text_to_speech` |
| Change topic | `groq.chat` + `groq.text_to_speech` |
| Speech evaluation (incl. Retry) | `jam.process_audio` (Whisper + evaluation LLM inside) |
| Abandoned session | Finalizer re-scoring → `jam.process_audio` in the same thread |

### Behavioral — **thread = behavioral `session_id`**
| Feature | Opik traces in the thread |
|---|---|
| Greeting / proceed / choose scenario / answer / probe / report | `behavioral.turn` (one per turn; LLM calls inside) |
| Narration | `groq.text_to_speech` |
| Spoken answer | `groq.transcribe` |
| Proctoring auto-finish | `behavioral.force_finish` |

### Psychometric — **thread = assessment `session_id`**
| Feature | Opik traces in the thread |
|---|---|
| Question-bank answers | none (no AI call) |
| Adaptive follow-up question | `groq.chat` |
| Final report (also for an abandoned session, via the finalizer) | `groq.chat` |

### Case Study — **thread = `session_token`, but it holds only the evaluation**
| Feature | Where it appears |
|---|---|
| Generate two scenarios | **Separate trace, not in the thread.** It runs before the session exists; the session is created when the student picks a scenario. Find it via metadata. |
| Start session | No AI call |
| Submit answers → evaluation | `groq.chat`, **in the session thread** |

### Mini Project (v1) — **thread = session `id`**
| Feature | Where it appears |
|---|---|
| Generate scenarios | **Separate trace, not in the thread** (runs before the session exists) |
| Discovery question (stakeholder reply) | `groq.chat` in the thread |
| Finish discovery (recap + brief) | `groq.chat` ×2 in the thread |
| Upload → first viva question | `groq.chat` in the thread |
| Viva answer (score + next question) | `groq.chat` ×2 in the thread |
| Reflection → final evaluation | `groq.chat` (several rubric passes) in the thread |
| Deadline / abandoned session | Evaluation via `expire_session`, in the thread |

### Mini Project v4 — **thread = session `id` (the whole attempt)**
The session is created before any AI call, so everything is in one thread: scenario generation → submission (artifact ceilings + viva questions) → finalize (viva scoring + feedback), including finalizer runs.

---

## 4. Known limitations

- **Case Study and Mini Project v1 scenario generation** are outside the thread (no session exists yet); they're still labelled with metadata.
- **JAM evaluation after a tab close:** if the tab closes mid-evaluation, the running Task loses its metadata labels (the thread id is kept). The trace still arrives; the finalizer's re-scoring trace is fully labelled.
- **Trace input/output on thread messages:** parent spans (`interview.*`, `behavioral.turn`, `jam.process_audio`) carry no input/output of their own, so open the trace to see the LLM prompts.

## 5. How to verify (per module)

1. In Opik → project `Vyaas Demo Test` → **Threads**: one thread per session, with TTS/STT inside it for voice modules.
2. Open any trace → **Metadata** shows `student_id`, `module` and `tenant`.
3. **Traces** tab, filter `metadata.module = "<module>"`: every trace of that module is listed.
