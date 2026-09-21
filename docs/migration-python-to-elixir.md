# Migration: Python FastAPI to Native Elixir

## Overview

This document covers the migration of AI assessment services from a Python FastAPI microservice to native Elixir modules running inside the Phoenix application. The migration eliminates the inter-service communication layer and resolves critical concurrency bugs.

## Why We Migrated

### The Problem

The original architecture had Phoenix calling a Python FastAPI service for all AI features. With only 5 concurrent users, the system experienced:

- **"Session not found" errors (67% of requests)**: Python stored sessions in per-process dictionaries. With 3 uvicorn workers and round-robin routing, a session created by Worker 1 was invisible to Workers 2 and 3.
- **Request timeouts**: 3 Python workers could only handle 3 concurrent requests. The other 2 users queued until timeout.
- **Callback failures**: The async callback pattern (Phoenix → Python → callback POST → Phoenix) added failure surface area.

### Root Cause

```
Worker 1 (PID 1001): sessions = {"abc-123": <session>}
Worker 2 (PID 1002): sessions = {}    ← status request → 404
Worker 3 (PID 1003): sessions = {}    ← status request → 404
```

Every Python module used in-memory dicts for session storage:
- `jam_engine.py`: `active_sessions: Dict[str, SessionManager] = {}`
- `interview_engine.py`: `self.sessions: Dict[str, InterviewSession] = {}`
- `assessment_engine.py`: `MemorySaver()` + `_session_meta: dict = {}`
- `psychometric_engine.py`: `_sessions: Dict[str, dict] = {}`

### The Solution

Move all AI logic to Elixir. The BEAM VM handles concurrency natively — each user gets their own lightweight process, sessions live in socket assigns, and there is no inter-process session sharing problem.

## Architecture: Before vs After

```
BEFORE:
  User → LiveView → Phoenix Context → HTTP to Python → Groq API
                                             ↓
                       LiveView ← PubSub ← Callback from Python

AFTER:
  User → LiveView → Phoenix Context → Elixir AI Engine → Groq API
              ↑                              ↓
              └──────── Task.Supervisor ──────┘
```

## What Was Migrated

### New Elixir Modules

| File | Purpose | Replaces |
|------|---------|----------|
| `lib/vyaasa_campus/ai/groq_client.ex` | HTTP client for Groq API (chat + Whisper + retries + rate limiting) | Python `groq` SDK |
| `lib/vyaasa_campus/ai/psychometric_engine.ex` | Question bank, Likert scoring, AI report generation | `psychometric_engine.py` |
| `lib/vyaasa_campus/ai/behavioral_engine.ex` | Multi-turn conversation state machine, scenario generation, evaluation | `assessment_engine.py` (LangGraph) |
| `lib/vyaasa_campus/ai/jam_engine.ex` | Topic generation, audio transcription (Groq Whisper), speech evaluation | `jam_engine.py` |
| `lib/vyaasa_campus/ai/interview_engine.ex` | Full resume-grounded interview: anchored question generation, EMA-adaptive difficulty, follow-up logic, per-question multi-dimensional scoring, placement-readiness final report | `engine.py` from `zed/vyaasa` (full port) |
| `lib/vyaasa_campus/ai/groq_rate_limiter.ex` | Token bucket rate limiter with request queue | N/A (new) |
| `priv/data/behavioral_scenarios.json` | 50 behavioral interview scenarios | `Data/expanded_scenarios.json` |

### Modified Files

| File | Change |
|------|--------|
| `lib/vyaasa_campus/contexts/psychometric.ex` | Replaced Python `Req.post` calls with native `PsychometricEngine` |
| `lib/vyaasa_campus/contexts/behavioral.ex` | Replaced Python API + PubSub callbacks with native `BehavioralEngine` |
| `lib/vyaasa_campus/contexts/jam.ex` | Replaced Python API calls with native `JamEngine` |
| `lib/vyaasa_campus/contexts/interview.ex` | Removed Python REST helpers (`start_python_session`, `initialize_python_session`, `download_interview_zip`, `health_check`). Added `start_session/2` (reads latest `student_ats_phases`), `proceed/1`, `submit_answer/2`, `transcribe_audio/2` |
| `lib/vyaasa_campus_web/live/student/interview/interview_session_live.ex` | Rewrote around the native engine: no WebSocket, LLM calls dispatched via `Task.Supervisor`, audio transcribed via Groq Whisper, TTS via Groq Orpheus with silent fallback |
| `mix.exs` | Removed `{:websockex, "~> 0.4.3"}` (no longer needed — interview WS gone) |
| `config/dev.exs` | Dropped `:interview_service_url` and `:interview_ws_url` |
| `lib/vyaasa_campus/contexts/student_ats.ex` | Added `list_all_by_student/2`, `next_attempt_number/2`, `create_reanalysis_phase/4`; `get_by_student_id/2` now returns latest attempt |
| `lib/vyaasa_campus/schema/students/student_ats_phase.ex` | Added `attempt_number` field; unique constraint changed from `student_id` to `(student_id, attempt_number)` |
| `lib/vyaasa_campus_web/live/student/psychometric/psychometric_live.ex` | Uses `Task.Supervisor` instead of Python callback/PubSub |
| `lib/vyaasa_campus_web/live/student/behavioral_live.ex` | Holds `session_state` in socket assigns, uses `Task.Supervisor` |
| `lib/vyaasa_campus_web/live/student/profile_completion_live.ex` | Dual mount: profile_token (email link) + current_user (reanalyze); reanalyze_mode skips ID card requirement; fix cancel_upload bug |
| `lib/vyaasa_campus_web/live/student/profile_completion/document_uploads.ex` | Shows only resume in reanalyze mode; passes `upload_type` for targeted cancel |
| `lib/vyaasa_campus_web/live/student/profile_completion/step_renderers.ex` | Conditionally hides Education Details, changes header/button text in reanalyze mode |
| `lib/vyaasa_campus_web/live/student/dashboard_live.ex` | Reanalyze button redirects to `/student/:tenant/resume/reanalyze` (not profile_token URL) |
| `lib/vyaasa_campus_web/live/student/jam/jam_session_live.ex` | Better error handling for "too short" speech, returns user to speak step to retry |
| `lib/vyaasa_campus/application.ex` | Added Finch pool and GroqRateLimiter to supervision tree |
| `assets/js/app.js` | Added browser Web Speech API TTS (`speak_text` event); `stop_audio`/`mute_audio` cancel speech synthesis |
| `config/runtime.exs` | Added `groq_api_key`, rate limiter config, increased DB pool |
| `config/config.exs` | Added `ai_reports` Oban queue, `hibernate_after` for LiveView |

### New Files (non-AI)

| File | Purpose |
|------|---------|
| `lib/vyaasa_campus_web/live/student/reanalyze/reanalyze_service.ex` | Resume re-analysis service — creates new ATS phase with incremented `attempt_number`, carries forward verified ID card/photo |
| `priv/repo/tenant_migrations/20260416120000_add_attempt_number_to_student_ats_phases.exs` | Tenant migration: adds `attempt_number` column, replaces unique index |

### Deleted Files

| File | Reason |
|------|--------|
| `controllers/api/behavioral_callback_controller.ex` | No longer needed — no Python callbacks |
| `controllers/api/psychometric_callback_controller.ex` | No longer needed |
| `controllers/api/jam_callback_controller.ex` | No longer needed |
| `plugs/behavioral_callback_auth.ex` | No longer needed |
| `plugs/psychometric_callback_auth.ex` | No longer needed |
| `plugs/jam_callback_auth.ex` | No longer needed |
| `lib/vyaasa_campus/services/interview_ws_client.ex` | No longer needed — interview now runs natively without WebSocket |

### Router Changes

Removed callback route scopes and pipeline definitions for:
- `/api/behavioral/callback/*`
- `/api/psychometric/callback/*`
- `/api/jam/callback/*`

Added:
- `/student/:tenant/resume/reanalyze` — authenticated resume re-analysis (reuses `ProfileCompletionLive` with `reanalyze_mode?`)

Kept:
- `/api/ats/callback` — resume scoring still uses Python

## What Still Requires Python

| Feature | Why |
|---------|-----|
| Resume scoring (`/score-resume/`) | spaCy NLP, SentenceTransformer embeddings, PDF parsing |

This is the only feature that still requires the Python service. The AI interview no longer needs a RAG pipeline — question generation uses the already-parsed resume JSON stored in `student_ats_phases` (no vector DB needed).

## Migration Details by Module

### Psychometric Assessment

**Python flow**: `POST /psychometric/start` → returns questions → `POST /psychometric/submit` → Python calls Groq → `POST /api/psychometric/callback/response` → PubSub → LiveView

**Elixir flow**: `PsychometricEngine.create_session_data/3` → returns questions → `PsychometricEngine.process_responses/2` + `PsychometricEngine.generate_report/2` → result sent via `Task.Supervisor` → LiveView

Key details:
- 50 questions embedded as module attribute `@question_bank` (copied from CSV)
- `sample_questions/1` selects 30 balanced questions (6 per Big Five factor)
- `score_response/2` handles positive/negative keying (reverse scoring)
- `calculate_factor_scores/2` computes mean per factor
- `generate_report/2` sends one Groq API call with the system prompt from `psychometric_engine.py`

### Behavioral Assessment

**Python flow**: LangGraph state machine with 3 nodes (chatbot → tools → evaluate), `MemorySaver` for session persistence, async callbacks via PubSub

**Elixir flow**: State machine implemented as pure functions in `BehavioralEngine`. Session state held in LiveView socket assigns (`:session_state`). No external state store needed.

State machine phases:
```
:greeting → :profile_collection → :star_explained → :ready_for_scenarios
    → :awaiting_scenario_response (×3) → :closing_qa → :completed
```

Key details:
- `process_message/2` is the main entry point — takes current state + user message, returns new state + response
- `determine_action/2` routes to the correct handler based on phase and message content
- `generate_and_present_scenarios/1` picks 2 random scenarios from the 50-scenario database, generates unique questions via Groq fast model
- `run_evaluation/1` generates the comprehensive behavioral report via Groq (same prompt as Python)
- Scenario response parsing extracts "scenario 1" or "scenario 2" choice from free-text user input

### JAM (Just A Minute)

**Python flow**: `POST /jam/generate-topic` (Groq chat) → `POST /jam/process-audio` (noise cancellation → VAD → Whisper transcription → Groq evaluation)

**Elixir flow**: `JamEngine.generate_topic/0` (Groq chat) → `JamEngine.process_audio/2` (Groq Whisper → Groq evaluation)

Key simplification: **Removed the entire audio preprocessing pipeline** (librosa, noisereduce, scipy, Silero VAD). Groq's Whisper model handles noisy audio natively. This eliminated ~200 lines of Python audio processing code and the following dependencies:
- librosa, soundfile, scipy, noisereduce, torch, torchaudio, pydub

**Topic variety**: `generate_topic/0` and `change_topic/1` don't rely on sampling alone — a static prompt at low temperature collapses onto the same most-probable topic every session. Each call injects a randomly chosen category (`@topic_categories`) plus a variation token into the prompt, and sends `temperature: 0.9` with a random `seed` (`GroqClient` now passes `seed`/`top_p` through to the API). This is what keeps topics from repeating across sessions.

### Interview (Full native port)

**Python flow**: FastAPI service with `POST /interview/start` → `POST /interview/{sid}/proceed` → `POST /interview/{sid}/answer`. `engine.py` ran an `Interviewer` (anchored question generation with EMA-adaptive difficulty and follow-ups) + `Evaluator` (silent per-question multi-dimensional scoring + final placement-readiness markdown report). Session state in per-process dicts.

**Elixir flow**: `Interview.start_session/2` reads the latest `student_ats_phases` row, adapts it, and returns a prepared greeting. `Interview.proceed/1` generates the first anchored question. `Interview.submit_answer/2` evaluates the answer and either returns the next question or the final report. Session state lives in LiveView socket assigns. All LLM work runs via `Task.Supervisor`.

Key details (the engine lives in `lib/vyaasa_campus/ai/interview/` — `Session` orchestrates `Profile`, `Planner`, `Interviewer`, `Evaluator`, `Reporter`. The old monolithic `interview_engine.ex` was **deleted**; `contexts/interview.ex` now aliases `Interview.Session, as: Engine`):
- `Interview.Profile` / `Extractor` normalise the ATS phase JSON (`personal_information`, `projects`, `work_experience`, `skills`) into the engine's flat shape — same contract as the Python `adapt_resume_schema`.
- `Interviewer` conversation history is bootstrapped with the candidate's projects + work experience + supporting skills. Questions are anchored strictly to projects (by name) or jobs (by role + company) — generic questions are rejected by prompt rules.
- Difficulty adapts across questions (`easy` / `medium` / `hard`) from recent per-answer scores.
- `Evaluator` scores each main answer on `technical`, `communication`, and `leadership` (0–100), with a separate `cultural_fit` pass. Per-question and final scores are domain-weighted via `Specializations.competency_weights/1` (default technical 50 / communication 30 / leadership 10 / cultural_fit 10). Scoring uses the shared band table in `docs/scoring-bands.md`.
- Follow-up mode engages when the answer's `technical` score is in the 40–60 range (`@followup_min`/`@followup_max`); hard-capped at 1 consecutive follow-up. Dimensions below 55 are flagged "weak" and probed in the next question.
- `Github.ownership_questions_pool/1` fetches the candidate's repos (resume repo links → GitHub API → README) and uses Groq to generate README-grounded ownership questions. Repos are **shuffled** and questions are **round-robined one per repo** (capped at `@max_github_questions`), so the starting project and positions vary across attempts and every repo gets a turn rather than the first repo monopolising the slots.
- Errored evaluations are flagged explicitly and excluded from averages — no silent 50-score poisoning.
- Final report is a structured markdown document (Overall Performance → Dimension Breakdown → What Went Well → Areas for Improvement → Action Plan → Encouraging Final Thought). Same prompt as Python.
- Audio arrives as base64 from the browser `AudioRecorder` hook, is decoded and transcribed in-process via `GroqClient.transcribe_audio/2`, then the transcript is submitted to the engine. No audio ever touches the Python service.
- TTS uses Groq Orpheus (`canopylabs/orpheus-v1-english`); on failure, the LiveView silently falls back — no audio is pushed but the flow continues.

No DB migration was needed: the existing `python_session_id` column on `interview_sessions` is reused to store the native UUID, so historical interview records remain readable.

### Case Study

The specialization (`sub`) that tailors the scenario is the **role the student selected during resume/ATS processing** — `preferred_role` on their latest `StudentAtsPhase` (`CaseStudyLive.resume_specialization/2`). It falls back to the profile (`specialization` → `degree` → `"General"`) only when there is no ATS phase yet. `Specializations.group_for/1` derives the group for the evaluation rubric (returns `nil` when the role isn't an exact catalog entry).

`CaseStudyEngine.generate_scenario/2` (Groq `qwen/qwen3-32b`, temp 0.95) invents a fictional company + incident from randomized building blocks (`@industries`, `@regions`, `@failure_archetypes`, `@timeframes` + a per-call nonce) so scenarios don't repeat. `evaluate/4` (temp 0.2) scores 3 dimensions — domain 0–40, problem-solving 0–30, initiative 0–30 — totalling 0–100.

**Difficulty is calibrated for a final-year student / fresher** (no industry experience): the `@failure_archetypes` are everyday product/business failures (billing errors, overcharges, duplicate orders, slow app during a sale) rather than production-infra/SRE/security incidents; the prompt carries an explicit DIFFICULTY CALIBRATION block that frames incidents around **user/business impact** (wrong prices, double charges, stuck orders) and forbids engineering-internals framing (auth/session tokens, cryptography, DB migrations/schema, caching/infra internals, race conditions), avoids deep jargon, keeps numbers modest, and caps `difficulty`/`complexity` at Easy/Low (Medium at most, never Hard/High). Scoring calibration lives in `docs/scoring-bands.md`.

## How Groq API Is Called

All Groq calls go through `GroqClient`, which provides:

1. **Chat completions**: `GroqClient.chat/2`, `GroqClient.ask/3`, `GroqClient.ask_fast/3`
2. **Audio transcription**: `GroqClient.transcribe_audio/2`, `GroqClient.transcribe_file/2`
3. **JSON extraction**: `GroqClient.extract_json/1` — handles markdown code blocks and raw text
4. **Rate limiting**: Every call acquires a slot from `GroqRateLimiter` before executing
5. **Connection pooling**: All HTTP goes through a named Finch pool with persistent connections
6. **Retry with backoff**: Automatic retry on 429 (rate limited) and 503 (service unavailable)

Models used:
- `llama-3.3-70b-versatile` — complex reasoning (reports, evaluation, behavioral chat)
- `llama-3.1-8b-instant` — fast tasks (topic generation, scenario generation, speech evaluation)
- `whisper-large-v3-turbo` — audio transcription

## Configuration

### Environment Variables

```env
# Required
GROQ_API_KEY=gsk_your_key_here

# Optional (defaults shown)
GROQ_MAX_CONCURRENT=50      # max simultaneous Groq API calls
GROQ_MAX_QUEUE_SIZE=500      # max queued requests before rejection
POOL_SIZE=40                 # PostgreSQL connection pool size
```

### Config Files Changed

- `config/runtime.exs` — Groq API key, rate limiter config, DB pool sizing
- `config/config.exs` — Oban `ai_reports` queue, LiveView `hibernate_after`

## Testing

All 16 integration tests passed against the live Groq API:

```
GroqClient.chat                              1104ms  PASS
GroqClient.ask_fast                           110ms  PASS
GroqClient.extract_json                        13ms  PASS
PsychometricEngine.sample_questions              4ms  PASS
PsychometricEngine.process_responses             3ms  PASS
PsychometricEngine.generate_report            2512ms  PASS
BehavioralEngine.load_scenarios                  8ms  PASS
BehavioralEngine.greeting                      665ms  PASS
BehavioralEngine.user_reply                   2358ms  PASS
JamEngine.generate_topic                       821ms  PASS
JamEngine.change_topic                         691ms  PASS
JamEngine.explain_topic                        632ms  PASS
JamEngine.evaluate_speech                     1697ms  PASS
JamEngine.too_short_rejection                    1ms  PASS
InterviewEngine.evaluate_response             1602ms  PASS
InterviewEngine.generate_final_report         1960ms  PASS
```

## Database Migration

### Tenant Migration: `attempt_number` for ATS Score History

**File**: `priv/repo/tenant_migrations/20260416120000_add_attempt_number_to_student_ats_phases.exs`

The `student_ats_phases` table previously allowed only one ATS phase per student (unique constraint on `student_id`). This prevented tracking resume improvement over time. The migration:

1. Adds `attempt_number` integer column (default 1, not null)
2. Drops old unique index on `student_id`
3. Creates compound unique index on `(student_id, attempt_number)`
4. Creates supporting index for fast history queries

**Applying the migration on the server:**

If your Triplex tenant migrations are in sync, run:
```bash
mix ecto.migrate --prefix tenant_your_schema
```

If migrations are out of sync (common on dev), apply directly via SQL:

```sql
DO $$
DECLARE
    tenant_schema text;
BEGIN
    FOR tenant_schema IN
        SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'tenant_%'
    LOOP
        EXECUTE format('
            ALTER TABLE %I.student_ats_phases
            ADD COLUMN IF NOT EXISTS attempt_number integer NOT NULL DEFAULT 1
        ', tenant_schema);

        EXECUTE format('DROP INDEX IF EXISTS %I.student_ats_phases_student_id_index', tenant_schema);

        EXECUTE format('
            CREATE UNIQUE INDEX IF NOT EXISTS student_ats_phases_student_id_attempt_index
            ON %I.student_ats_phases (student_id, attempt_number)
        ', tenant_schema);

        EXECUTE format('
            CREATE INDEX IF NOT EXISTS student_ats_phases_student_id_attempt_number_index
            ON %I.student_ats_phases (student_id, attempt_number)
        ', tenant_schema);

        RAISE NOTICE 'Migrated schema: %', tenant_schema;
    END LOOP;
END $$;
```

The SQL is idempotent (`IF NOT EXISTS` / `IF EXISTS` on everything) — safe to run multiple times.

## Resume Re-analysis Feature

### Overview

Students can re-upload their resume from the dashboard to track score improvements over time. Each re-analysis creates a new `StudentAtsPhase` record with an incremented `attempt_number`, preserving the full history.

### Flow

1. Student clicks "Re-analyze Resume" on the dashboard
2. Redirected to `/student/:tenant/resume/reanalyze` (authenticated, no profile_token needed)
3. Page shows the student dashboard chrome (sidebar, header, back button)
4. Only the resume upload + job role selector are shown (ID card and profile photo already verified)
5. Student uploads new resume and clicks "Analyze My Resume"
6. `ReanalyzeService` creates a new ATS phase (attempt_number = previous + 1), carrying forward the verified ID card and profile picture
7. `AtsResumeProcessor` Oban job processes the resume via the Python service
8. Results appear on the same ATS Analysis dashboard (step 2)
9. Previous scores preserved — full history queryable via `StudentAts.list_all_by_student/2`

### Key Differences: First-time vs Re-analysis

| Aspect | First-time (email link) | Re-analysis (dashboard) |
|--------|------------------------|------------------------|
| URL | `/profile/:token/ats` | `/student/:tenant/resume/reanalyze` |
| Auth | Profile token verification | `current_user` (session) |
| Documents | Resume + ID card + profile photo | Resume only |
| DB action | Create or update single phase | Create new phase (incremented attempt) |
| Layout | Standalone centered card | Dashboard chrome (sidebar + header) |
| Step 1 header | "Step 1: Profile Creation" | "Re-analyze Your Resume" |
| Education details | Shown (editable) | Hidden (already verified) |
| Next button | "Next - Step 2" | "Analyze My Resume" |

## Post-Migration Fixes

### JAM TTS Voice

Python used `gTTS` (Google Text-to-Speech) to generate base64 MP3 audio sent from the backend. Since Elixir doesn't have a gTTS equivalent, TTS was replaced with the browser's **Web Speech API** (`SpeechSynthesisUtterance`). The LiveView pushes a `speak_text` event to the JS `AudioPlayer` hook, which speaks the topic aloud on the client side. No server-side audio generation needed.

### JAM Evaluation Response Normalization

Groq's LLM sometimes returns varied JSON shapes for the same prompt:
- `overall_summary` as a map `%{"summary" => "..."}` instead of a string
- `feedback` fields as arrays of strings instead of a single string
- `score` as a string or float instead of integer

Added normalizer helpers (`normalize_score/1`, `normalize_text/1`, `normalize_summary/1`) in `JamEngine` to ensure all fields are the expected types before saving to DB or rendering in the LiveView.

### Topic Title Cleanup

Groq sometimes wraps topic titles in markdown formatting (`**Topic: "..."**`). Added `clean_topic_title/1` to strip `**`, `#`, and `Topic:` prefixes.

### Upload Cancel Bug Fix

The document upload "X" button was calling `cancel_upload/3` on ALL upload types (resume, id_card, profile_photo) instead of just the one being removed. Fixed by passing `upload_type` through the component and targeting only the specific upload.

## Impact

| Metric | Before (Python) | After (Elixir) |
|--------|----------------|----------------|
| 5 concurrent users | Failures (session not found, timeouts) | All pass |
| Session bugs | 67% chance of "not found" with 3 workers | Impossible |
| Bottleneck | Python workers (3) + in-memory sessions | Groq API rate limit only |
| External dependencies | FastAPI + uvicorn + 30+ Python packages | Groq API key only |
| Deployment complexity | 2 services + shared secrets + callback URLs | 1 service |
| Audio preprocessing | librosa + scipy + noisereduce + PyTorch | Eliminated (Whisper handles it) |
| Resume re-analysis | Overwrites single record | Preserves full score history |
| Interview RAG stack | LlamaIndex + Qdrant + FastEmbed vector DB | Eliminated — questions generated directly from parsed resume JSON |
| Interview transport | WebSocket (`websockex` + per-session client process) | Direct function calls via `Task.Supervisor` |
