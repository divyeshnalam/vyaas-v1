# Vyaasa Campus — Functional Requirements Document (FRD)

| Field | Value |
|---|---|
| Document version | 0.1 (draft) |
| Date | 2026-05-07 |
| Companion to | `docs/BRD.md` v0.1 |
| Status | Draft — most content **derived from the current implementation**; items needing business sign-off marked **\[assumed — confirm]** |
| Audience | Engineering, QA, customer success, and external integrators |

> **Method.** This FRD is mostly a structured read of the running v1 codebase: routes, schemas, contexts, AI engines, jobs, and integrations. Where the code already encodes a behavior, that behavior is stated as a requirement. Where the code is silent or ambiguous on a policy question, the item is marked `[assumed — confirm]` so product can lock it down before sign-off.

---

## 1. Document scope

This FRD covers the functional and non-functional requirements of **Vyaasa Campus v1**:

- Three role-based user experiences: Platform Admin, Tenant Admin, Student.
- Six student assessments and their AI engines.
- Multi-tenant data model (Postgres schema-per-tenant via Triplex).
- Email, file storage, PDF generation, background jobs.
- Authentication, authorisation, and tenant isolation.
- Performance, availability, observability, and security NFRs.

It does **not** cover:

- Pricing, contracts, or RFP content (see BRD).
- Marketing copy.
- Detailed UI mockups (refer to design files).

---

## 2. System overview

### 2.1 High-level architecture

```
Browser (LiveView + small JS hooks)
       │
       ▼
Phoenix endpoint (Bandit)  ─── plugs: TenantPlug → AuthPlug → ScopePlug
       │
       ▼
LiveView / Controller layer
       │
       ▼
Context layer  (Tenants, Students, Assessments, Jam, Interview, …)
       │       │
       │       └──▶ AI engines (PsychometricEngine, BehavioralEngine, JamEngine,
       │                         InterviewEngine, ResumeScorer, EmbeddingServer)
       │                          │
       │                          └──▶ GroqClient ──▶ GroqRateLimiter ──▶ Finch pool ──▶ Groq API
       │
       ├──▶ Ecto Repo (Postgres + Triplex schema-per-tenant)
       │
       ├──▶ Oban (queues: default, emails, imports, ats_processing, ai_reports, cleanup)
       │
       ├──▶ ChromicPDF (headless Chrome) ──▶ PDF reports
       │
       ├──▶ Swoosh + SMTP ──▶ Transactional email
       │
       └──▶ Local filesystem (priv/uploads/) — S3 wired but not in active use [confirm]
```

### 2.2 Key components — *derived*

- **Phoenix 1.8 + LiveView 1.0** for the entire web UI.
- **Bandit** as the HTTP server, tuned with 100 acceptors and 60s read timeout.
- **Postgres** with **Triplex** for schema-per-tenant isolation.
- **Guardian** for JWT authentication.
- **Oban** for background jobs.
- **ChromicPDF** for headless-Chrome PDF rendering.
- **Bumblebee + Nx + EXLA** for native sentence-transformer embeddings.
- **Groq API** for chat completions (Llama 3.1 8B and Llama 3.3 70B), Whisper transcription, and Orpheus TTS.

### 2.3 Roles and access matrix

| Role | Login URL | Token / session | Scoped to | Capabilities (high level) |
|---|---|---|---|---|
| Platform Admin | `/admin/login` | JWT in session + bearer | Public schema | Manage tenants, master question bank, degrees, industries, jobs. |
| Tenant Admin (College Admin) | `/auth/tenant/{ALIAS}/login` | JWT in session + bearer | Tenant schema | Manage students, verify profiles, view dashboards, download reports, manage tenant-side users and roles. |
| Student | `/auth/tenant/{ALIAS}/login` | JWT in session + bearer | Tenant schema (own records) | Complete profile, take 6 assessments, view and download own reports. |
| Profile-completion link recipient (pre-login student) | `/profile/{token}/ats` | Unsigned profile token | Single student record | Upload documents, review parsed resume, submit for verification. |

---

## 3. Functional requirements — Platform Admin

### 3.1 Authentication and account management

| ID | Requirement |
|---|---|
| **FR-PA-1** | Platform admin shall log in at `GET /admin/login` and receive a JWT (TTL = 30 minutes) on `POST /api/auth/platform-admin/login`. |
| **FR-PA-2** | Platform admin shall be able to request password reset via `GET /admin/forgot-password` → `POST /api/auth/password-reset/request`, receive a tokenised email, and complete reset at `GET /admin/reset-password/:token`. Reset token TTL = 24 hours. |
| **FR-PA-3** | Platform admin shall be forced to change password if `temp_password` flag is set. |
| **FR-PA-4** | Platform admin password shall be bcrypt-hashed at rest. |
| **FR-PA-5** | All platform-admin pages shall enforce the `:require_admin` pipeline (rejects tenant users and students). |

### 3.2 Tenant management

| ID | Requirement |
|---|---|
| **FR-PA-6** | Platform admin shall create a new tenant via `POST /api/platform_admin/tenants` with: `full_name`, `short_name`, `alias` (unique), `affiliation_type` (`university`/`college`/`school`/`institute`/`corporate`), `email`, `phone`, optional `website_url`, `logo_url`. |
| **FR-PA-7** | On tenant creation, the system shall: (a) create a Postgres schema named `tenant_{alias_downcased}` via Triplex; (b) run all tenant migrations; (c) auto-create a tenant admin user and email login credentials to the contact email — *derived from commit `eb7ef4e fix: auto-create tenant admin user on tenant creation`*. |
| **FR-PA-8** | Platform admin shall list tenants (`GET /api/platform_admin/tenants`), view a single tenant with student counts (`GET /api/platform_admin/tenants/:id`), update (`PUT`), delete (`DELETE`), activate (`POST /:id/activate`), and deactivate (`POST /:id/deactivate`). |
| **FR-PA-9** | Tenant lifecycle states shall be `active`, `inactive`, `suspended` (default: `active`). |
| **FR-PA-10** | Suspending or deactivating a tenant shall block all logins for that tenant's tenant-users and students; data shall be preserved. |
| **FR-PA-11** | Tenant aliases shall be globally unique (DB-level unique index). |
| **FR-PA-12** | After tenant creation, an operator shall seed default job profiles via `TENANT_ID=<uuid> mix run priv/repo/tenant_seeds.exs` — *current behavior; v1.1 candidate to automate inside FR-PA-7*. |

### 3.3 Tenant locations

| ID | Requirement |
|---|---|
| **FR-PA-13** | Platform admin shall manage tenant locations: `GET/POST /api/platform_admin/locations`, `GET/PUT/DELETE /:id`, `POST /:id/set_primary`. |
| **FR-PA-14** | A tenant may have multiple locations; exactly one shall be marked `is_primary`. |

### 3.4 Master question bank and master data

| ID | Requirement |
|---|---|
| **FR-PA-15** | Platform admin shall manage master MCQ questions at `/admin/question-bank` backed by the public `qa` table; supported types: `multiple_choice`, `multiple_select`, `true_false`, `fill_in_blank`, `short_answer`. |
| **FR-PA-16** | Platform admin shall manage master degrees and specializations at `/admin/degrees`. |
| **FR-PA-17** | Platform admin shall manage assessment configurations at `/admin/assessments-config` (time limits, pass marks). |
| **FR-PA-18** | Platform admin shall view Oban queue health at `/admin/jobs`. |
| **FR-PA-19** | Master industries and job roles shall be CRUD-able via `/admin/jobs` and the `industries` / `job_roles` public tables. |

### 3.5 Platform observability \[assumed — confirm]

| ID | Requirement |
|---|---|
| **FR-PA-20** | Platform admin dashboard shall display tenant-count, student-count, and assessment-completion roll-ups across all tenants — *current implementation present at `/admin/dashboard`; confirm exact metrics with product*. |

---

## 4. Functional requirements — Tenant Admin (College Admin)

### 4.1 Authentication

| ID | Requirement |
|---|---|
| **FR-TA-1** | Tenant admin shall log in at `GET /auth/tenant/:tenant/login` (LiveView) → `POST /api/auth/tenant-user/login`. |
| **FR-TA-2** | First login with a temporary password shall force a change at `GET /user/:tenant/change-password`. |
| **FR-TA-3** | Tenant admin shall be able to reset password via `GET /auth/tenant/:tenant/forgot-password`. |
| **FR-TA-4** | All `/user/:tenant/*` routes shall enforce the `:require_tenant_user_only` pipeline. |

### 4.2 Student management

| ID | Requirement |
|---|---|
| **FR-TA-5** | Tenant admin shall add a single student via `POST /api/tenant/students` with: `first_name`, `middle_name?`, `last_name`, `email`, `phone`, `degree_id`, `specialization_id`, `year_of_passing`, `registration_id`, optional `cgpa`, `tenure`, `current_academic_year`, `location_id`. |
| **FR-TA-6** | Tenant admin shall bulk-create students via `POST /api/tenant/students/bulk` (CSV-driven; `csv` dependency available). |
| **FR-TA-7** | On student creation, the system shall send a profile-completion email containing a unique `profile_token` link to `/profile/:profile_token/ats`. The token is single-use, scoped to one student. |
| **FR-TA-8** | Tenant admin shall list students at `GET /api/tenant/students` and `/user/:tenant/dashboard/students`, with filters by status (verified / unverified / pending), degree, year of passing. |
| **FR-TA-9** | Tenant admin shall list pending verifications at `GET /api/tenant/students/pending`. |
| **FR-TA-10** | Tenant admin shall approve a student profile via `POST /api/tenant/students/:id/approve`. On approval, the system shall generate a temporary password, set `temp_password` on the student record, and send the welcome email with credentials. |
| **FR-TA-11** | Tenant admin shall reject a student profile (revert to `profile_incomplete`) via `POST /api/tenant/students/:id/reject` with optional `admin_notes`. |
| **FR-TA-12** | Tenant admin shall download a student's resume via `GET /api/tenant/students/:student_id/resume/*filename`. |
| **FR-TA-13** | Tenant admin shall update a student record via `PUT /api/tenant/students/:id`. |

### 4.3 Profile edit-request workflow

| ID | Requirement |
|---|---|
| **FR-TA-14** | When a student submits a profile-edit request, it shall appear at `GET /api/tenant/students/edit-requests`. |
| **FR-TA-15** | Tenant admin shall approve an edit request via `POST /api/tenant/students/:id/approve-edit` (sends `profile_edit_approved` email with re-edit link, 48h validity). |
| **FR-TA-16** | Tenant admin shall reject an edit request via `POST /api/tenant/students/:id/reject-edit` with `rejection_notes` (sends `profile_edit_rejected` email). |

### 4.4 Tenant-side users and roles (RBAC within a tenant)

| ID | Requirement |
|---|---|
| **FR-TA-17** | Tenant admin shall CRUD tenant users via `GET/POST/PUT/DELETE /api/tenant/users`. |
| **FR-TA-18** | Tenant admin shall CRUD roles via `GET/POST/PUT/DELETE /api/tenant/roles`. |
| **FR-TA-19** | Tenant admin shall assign roles via `POST /api/tenant/user_roles`. |
| **FR-TA-20** | Roles shall carry an array of permission strings; system roles (`is_system_role = true`) shall not be deletable. |

### 4.5 Assessment configuration (tenant-scoped)

| ID | Requirement |
|---|---|
| **FR-TA-21** | Tenant admin shall configure tenant-side assessments via `GET/POST /api/tenant/assessments`, `GET/PUT/DELETE /:id`, with: `title`, `description`, `assessment_type` (`quiz`/`exam`/`assignment`/`project`/`practice`/`behavioural`), `duration_minutes`, `total_marks`, `weightage` (0–100), `passing_marks` (≤ total_marks), `time_period.{start_date, end_date}`, `settings` (free-form map). |
| **FR-TA-22** | Assessment lifecycle states shall be `draft → published → active → completed → archived`. |
| **FR-TA-23** | Tenant admin shall publish an assessment via `POST /api/tenant/assessments/:id/publish`, archive via `POST /:id/archive`. |

### 4.6 Programs (training cohorts)

| ID | Requirement |
|---|---|
| **FR-TA-24** | Tenant admin shall create programs at `/user/:tenant/dashboard/programs`, assign students, and track progress. \[confirm exact program model with product] |

### 4.7 Reports (tenant-scoped)

| ID | Requirement |
|---|---|
| **FR-TA-25** | Tenant admin shall download leaderboard PDF via `GET /user/:tenant/reports/leaderboard`. |
| **FR-TA-26** | Tenant admin shall download specialization-level performance PDF via `GET /user/:tenant/reports/specialization`. |
| **FR-TA-27** | All tenant-side reports shall be ChromicPDF-rendered from HEEx templates in `lib/vyaasa_campus_web/controllers/report_html/`. |

### 4.8 Tenant dashboard

| ID | Requirement |
|---|---|
| **FR-TA-28** | `/user/:tenant/dashboard` shall display: total students, active sessions, pending profiles, top performers, recent activity feed. \[confirm exact widget set with product] |

---

## 5. Functional requirements — Student

### 5.1 Profile completion (pre-login)

| ID | Requirement |
|---|---|
| **FR-ST-1** | Student shall open the profile-completion link `/profile/:profile_token/ats`; system shall validate the token via `GET /api/student/profile-completion/verify`. |
| **FR-ST-2** | Step 1 — Document upload: student shall upload Resume (PDF, ≤ 5 MB), College ID card (image, ≤ 2 MB), Profile photo (image, ≤ 2 MB), and pick a target job role from the seeded `job_profiles` list. |
| **FR-ST-3** | On submission, the system shall enqueue an `AtsResumeProcessor` Oban job (queue `:ats_processing`, max 3 attempts, 5-minute timeout) which calls `VyaasaCampus.AI.ResumeScorer.run/1`. |
| **FR-ST-4** | While the resume is processing, the page shall poll status; expected completion ≤ 90 seconds; on prolonged delay (> 2 minutes) the UI shall show a graceful retry message. |
| **FR-ST-5** | Step 2 — Review parsed resume: the system shall display the AI-extracted fields (`personal_information`, `portfolio_and_links`, `professional_summary`, `skills`, `work_experience`, `projects`, `education`, `certifications`, `languages`, `achievements_and_activities`, ATS score 0–100). All fields shall be editable. |
| **FR-ST-6** | Step 3 — Submit: on submit (`POST /api/student/profile-completion/submit`), the student shall transition from `profile_incomplete` → `unverified`. |
| **FR-ST-7** | Profile-completion tokens shall be single-use and shall expire after \[confirm — current default 48h]. |
| **FR-ST-8** | Student shall request a re-send of the profile-completion email via `POST /api/student/profile-completion/resend`. |

### 5.2 Authentication and first login

| ID | Requirement |
|---|---|
| **FR-ST-9** | After admin approval, the student shall receive a `profile_approved` email with login credentials (temporary password). |
| **FR-ST-10** | Student shall log in at `/auth/tenant/:tenant/login` → `POST /api/auth/student/login`. |
| **FR-ST-11** | First login with a temporary password shall force a change at `/student/:tenant/change-password`. |
| **FR-ST-12** | Student shall reset password via `/auth/tenant/:tenant/forgot-password`. |
| **FR-ST-13** | All `/student/:tenant/*` routes shall enforce the `:require_student` pipeline. |

### 5.3 Student dashboard

| ID | Requirement |
|---|---|
| **FR-ST-14** | `/student/:tenant/dashboard` shall display: ATS score, parsed resume summary, six assessment cards (Resume / MCQ / Psychometric / Behavioral / JAM / Mock Interview) with status (`not_started` / `in_progress` / `completed`), overall score, ranking, "Re-analyze Resume" button. |

### 5.4 Profile edit (post-verification)

| ID | Requirement |
|---|---|
| **FR-ST-15** | An active student shall request a profile edit via `POST /api/student/profile/edit-request` with proposed changes; status returns to `unverified`-flow until tenant admin approves. |

### 5.5 Resume re-analysis

| ID | Requirement |
|---|---|
| **FR-ST-16** | Student shall re-upload their resume from `/student/:tenant/resume/reanalyze`; in re-analyze mode only the resume + target role are required (ID card and profile photo carry forward). |
| **FR-ST-17** | Each re-analysis shall create a new `student_ats_phases` row with `attempt_number = previous + 1`; previous attempts shall be preserved (unique constraint `(student_id, attempt_number)`). |
| **FR-ST-18** | The system shall show a history of attempts so students can track score lift over time. |

### 5.6 Public shared profile \[assumed — confirm]

| ID | Requirement |
|---|---|
| **FR-ST-19** | Student-shared profile shall be accessible at `/profile/shared/:token` (LiveView `Student.SharedProfileLive`). \[confirm what the shared payload includes — full reports vs. summary; confirm revocation/expiry] |

---

## 6. Functional requirements — The six assessments

> **Source of truth.** Each assessment's engine, schema, and AI calls are derived from `lib/vyaasa_campus/ai/*_engine.ex` and `lib/vyaasa_campus/schema/{students,jam,interview,assessments}/*.ex`. Items needing product confirmation are tagged.

### 6.1 Assessment 1 — Resume / ATS scoring

| ID | Requirement |
|---|---|
| **FR-A1-1** | Engine: `VyaasaCampus.AI.ResumeScorer` (lib/vyaasa_campus/ai/resume_scorer.ex). |
| **FR-A1-2** | Inputs: PDF / DOCX / TXT resume (≤ 5 MB), target job role (selected from tenant's `job_profiles`). |
| **FR-A1-3** | Pipeline: text extraction (`Resume.Extractor`) → LLM-based parse and validation (`Resume.LlmParser` via Groq) → completeness scoring (`Resume.Completeness`) → relevance scoring (`Resume.Relevance` using Bumblebee embeddings + tier match) → sanity check (`Resume.Sanity`). |
| **FR-A1-4** | Final score formula: `0.30 × completeness + 0.50 × relevance + 0.20 × sanity` (range 0–100). |
| **FR-A1-5** | Output stored on `student_ats_phases`: `ats_score`, `metadata` (full breakdown), parsed fields (personal, skills, work_experience, projects, education, certifications, languages, achievements). |
| **FR-A1-6** | Status transitions: `processing → completed` (or `failed` / `errored` / `manual_review`). |
| **FR-A1-7** | Retake policy: unlimited; each retake increments `attempt_number`. |
| **FR-A1-8** | AI calls per attempt: 1 LLM call (parse), embeddings computed locally via `EmbeddingServer` (Bumblebee + Nx + EXLA, model `sentence-transformers/all-MiniLM-L6-v2`). |
| **FR-A1-9** | Job profile data: 23 default profiles seeded per tenant via `priv/repo/tenant_seeds.exs`; each profile is a markdown document with sections Role Summary / Core Technical Skills / Key Responsibilities / Essential Tools / Appreciated Skills / Educational Background. |
| **FR-A1-10** | Report download: `GET /student/:tenant/reports/...` → ChromicPDF render of the resume report \[confirm exact controller route — current implementation focuses on per-assessment downloads]. |

### 6.2 Assessment 2 — MCQ

| ID | Requirement |
|---|---|
| **FR-A2-1** | Engine: generic `VyaasaCampus.Schema.Assessments.Assessment` + `AssessmentAttempt` (no AI). |
| **FR-A2-2** | Question source: master `qa` table (public schema), filtered by topic / subject / curriculum / chapter linkage. |
| **FR-A2-3** | Question types supported: multiple_choice, multiple_select, true_false, fill_in_blank, short_answer. |
| **FR-A2-4** | Time limit: `assessments.duration_minutes` (admin-configured); auto-submit on expiry. |
| **FR-A2-5** | Routes: `GET /api/student/assessments`, `POST /api/student/assessments/:id/start`, `GET /api/student/attempts/:id`, `PUT /api/student/attempts/:id/submit`, LiveView at `/student/:tenant/assessment/instructions` → `/assessment/:id/test` → `/assessment/:id/result`. |
| **FR-A2-6** | Scoring: deterministic match against `qa.answer`, optional `weightage` per question. |
| **FR-A2-7** | Output: `assessment_attempts.score`, `percentage`, `obtained_marks`, `total_marks`, `answers` (map of question_id → student_choice). |
| **FR-A2-8** | Retake policy: admin-configurable via `assessments.settings`. |
| **FR-A2-9** | Report download: `GET /student/:tenant/reports/mcq/:attempt_id` → ChromicPDF (template `mcq.html.heex`). |

### 6.3 Assessment 3 — Psychometric (Big Five / OCEAN)

| ID | Requirement |
|---|---|
| **FR-A3-1** | Engine: `VyaasaCampus.AI.PsychometricEngine`. |
| **FR-A3-2** | Adaptive question generation: each question generated on-demand by Groq (model `openai/gpt-oss-120b`, temperature 0.5), seeded with few-shot examples per Big Five trait. |
| **FR-A3-3** | Question count: 30 total, max 6 per trait. Likert scale 1–5 ("Strongly Disagree" → "Strongly Agree"). |
| **FR-A3-4** | Ambiguous answers (Likert 2–3) shall trigger up to 3 tiered follow-up questions. |
| **FR-A3-5** | Deduplication: Jaccard word-overlap > 0.55 triggers retry; falls back to few-shot examples if retry also collides. |
| **FR-A3-6** | Scoring: positive- and negative-keyed items; per-trait score is mean of keyed responses; result range per trait 1.0–5.0. |
| **FR-A3-7** | Output stored on `student_psychometric_assessments`: `openness_score`, `conscientiousness_score`, `extraversion_score`, `agreeableness_score`, `neuroticism_score`, `factor_scores`, `factor_reports`, `overall_summary`, `strengths`, `development_areas`, `suggestions`. |
| **FR-A3-8** | Routes: LiveView at `/student/:tenant/assessment/psychometric`. AI calls run via `Task.Supervisor` so the LiveView remains responsive. |
| **FR-A3-9** | AI calls per session: 1 per question (≤ ~33 incl. follow-ups) + 1 final report-generation call. |
| **FR-A3-10** | Retake policy: student-controlled; `attempt_number` increments per retake. |
| **FR-A3-11** | Report download: `GET /student/:tenant/reports/psychometric/latest` → ChromicPDF (template `psychometric.html.heex`). |

### 6.4 Assessment 4 — Behavioral

| ID | Requirement |
|---|---|
| **FR-A4-1** | Engine: `VyaasaCampus.AI.BehavioralEngine`. |
| **FR-A4-2** | Phases: `:greeting → :profile_collection → :star_explained → :ready_for_scenarios → :awaiting_scenario_response (×3) → :closing_qa → :completed`. |
| **FR-A4-3** | Scenario source: static JSON file `priv/data/behavioral_scenarios.json` (50 scenarios). 3 scenarios per session, 2 random options per round. |
| **FR-A4-4** | Output competencies (0–100 each): Work Ethics & Reliability, Teamwork & Collaboration, Adaptability & Learning, Leadership Potential, Communication Skills. Overall = mean of the five. |
| **FR-A4-5** | Quality guard: if all answers < 15 words or detected as gibberish, the engine returns a zero-score report. Post-LLM ceiling penalty if fewer than 3 of 3 scenarios were answered substantively. |
| **FR-A4-6** | AI calls per session: 1 final report call (Llama 3.3 70B, temperature 0.0, 60s timeout); flow itself is template-driven. |
| **FR-A4-7** | Routes: LiveView at `/student/:tenant/assessment/behavioral`. |
| **FR-A4-8** | Output stored on `student_behavioral_assessments`: `overall_score`, the five competency scores, `ratings`, `reasoning`, `summary`, `strengths`, `areas_for_development`, `completed_scenarios`, `raw_report`. |
| **FR-A4-9** | Retake policy: \[confirm — current code allows student retake; product to confirm whether to admin-gate]. |
| **FR-A4-10** | Report download: `GET /student/:tenant/reports/behavioral/latest` → ChromicPDF (`behavioral.html.heex`). |

### 6.5 Assessment 5 — JAM (Just A Minute)

| ID | Requirement |
|---|---|
| **FR-A5-1** | Engine: `VyaasaCampus.AI.JamEngine`. |
| **FR-A5-2** | Phases: `created → topic_generated → decision_phase → preparation → speaking → processing → completed` (or `failed` at any phase). |
| **FR-A5-3** | Topic generation: Groq fast model (Llama 3.1 8B) prompts categorised across Current Affairs / College Challenges / Social Phenomena / Events & Trends / Future of Work. Student may change topic once. |
| **FR-A5-4** | Time limits: 60s decision, 15s preparation, 60s speaking. |
| **FR-A5-5** | Audio capture: browser-side via Web Audio / MediaRecorder; uploaded to `POST /api/student/jam/sessions/:id/upload-audio`. |
| **FR-A5-6** | Transcription: Groq Whisper (`whisper-large-v3-turbo`) — performed in-process; no Python dependency. |
| **FR-A5-7** | Evaluation: 1 Groq LLM call returning per-dimension scores (clarity, structure, relevance, impact, confidence — each 1–10) + final score 0–100 + overall summary. |
| **FR-A5-8** | Output stored on `jam_sessions`: `topic_title`, `topic_explanation`, `transcript`, `word_count`, `speech_duration_seconds`, `final_score`, five dimension scores, `overall_summary`, `evaluation_data`, actual time used per phase. |
| **FR-A5-9** | Retry: up to 3 retries on failure (`retry_count` field). |
| **FR-A5-10** | Routes: LiveView at `/student/:tenant/jam/session`; REST API at `/api/student/jam/sessions/*`. |
| **FR-A5-11** | TTS for the topic: browser-side Web Speech API (`SpeechSynthesisUtterance`) — server pushes a `speak_text` event to the JS hook; on TTS failure the flow continues silently. |
| **FR-A5-12** | Report download: `GET /student/:tenant/reports/jam/:session_id` → ChromicPDF (`jam.html.heex`). |

### 6.6 Assessment 6 — Mock Interview (resume-grounded)

| ID | Requirement |
|---|---|
| **FR-A6-1** | Engine: `VyaasaCampus.AI.InterviewEngine`. |
| **FR-A6-2** | Phases: `created → resume_indexed → initialized → interviewing → completing → completed` (or `failed`). |
| **FR-A6-3** | Resume context: engine reads the latest `student_ats_phases` row (`personal_information`, `professional_summary`, `skills`, `work_experience`, `projects`) — adapter normalises to a flat shape. Pre-condition: at least one project OR one job in the parsed resume. |
| **FR-A6-4** | Question generation: anchored strictly to a project (by name) or job (by role + company); generic questions are rejected by prompt rules. |
| **FR-A6-5** | Difficulty adaptation: EMA over the last 3 per-question scores, with weights `[0.2, 0.3, 0.5]`. Difficulty levels: easy / medium / hard. |
| **FR-A6-6** | Follow-up logic: when a per-question score falls in the 55–80 "sweet spot", a follow-up engages, capped at 1 consecutive follow-up. |
| **FR-A6-7** | Per-answer evaluation: Groq JSON-mode call scoring 4 dimensions — `technical_accuracy`, `relevance`, `depth`, `clarity`. Weighted rollup `0.40 × technical + 0.25 × relevance + 0.20 × depth + 0.15 × clarity` is the per-question score. |
| **FR-A6-8** | Errored evaluations are flagged and excluded from averages (no silent 50-score poisoning). |
| **FR-A6-9** | Defaults: `max_questions = 5`, `max_duration_minutes = 10`. |
| **FR-A6-10** | Audio answers: browser `AudioRecorder` hook → base64 → server-side decode → Groq Whisper transcription → engine receives transcript text. |
| **FR-A6-11** | TTS: Groq Orpheus (`canopylabs/orpheus-v1-english`); on failure, the LiveView silently falls back (text-only flow continues). |
| **FR-A6-12** | Output stored on `interview_sessions`: `overall_score`, `final_report` (markdown placement-readiness assessment with sections Overall Performance / Dimension Breakdown / What Went Well / Areas for Improvement / Action Plan / Encouraging Final Thought), `strengths`, `improvements`, `questions_data` (array of per-question records). |
| **FR-A6-13** | Routes: LiveView at `/student/:tenant/interview/session`. |
| **FR-A6-14** | Retry: up to 3 retries on failure (`retry_count`). |
| **FR-A6-15** | Retake policy: \[confirm — current code permits retry on failure but no explicit student-initiated retake; product to confirm]. |
| **FR-A6-16** | Report download: `GET /student/:tenant/reports/interview/:session_id` → ChromicPDF (`interview.html.heex`). |

---

## 7. Cross-cutting functional requirements

### 7.1 Email

| ID | Requirement |
|---|---|
| **FR-EM-1** | All transactional email shall be delivered via Swoosh + SMTP (configurable provider; Gmail SMTP supported by default). |
| **FR-EM-2** | Email templates shall live in `VyaasaCampus.Mail.Templates`. Templates required for v1: `password_reset`, `welcome`, `welcome_with_role`, `tenant_creation`, `profile_completion`, `profile_approved`, `profile_edit_request`, `profile_edit_approved`, `profile_edit_rejected`, `assessment_report`. |
| **FR-EM-3** | All email links shall use `FRONTEND_URL` env var (no hardcoded localhost) — *derived from commit `a8132ab fix: email templates use FRONTEND_URL config instead of hardcoded localhost`*. |
| **FR-EM-4** | Bulk email shall be supported via `EmailOrchestrator.send_bulk_emails*` (Task.async_stream + DynamicSupervisor for >20 recipients). |
| **FR-EM-5** | The `assessment_report` email shall attach the generated PDF binary. |
| **FR-EM-6** | In dev, email delivery shall use the local `Swoosh` mailbox (preview at `/dev/mailbox`); in prod, SMTP credentials shall come from `SMTP_USERNAME` / `SMTP_PASSWORD`. |

### 7.2 PDF generation

| ID | Requirement |
|---|---|
| **FR-PDF-1** | All PDF reports shall be rendered via ChromicPDF with `no_sandbox: true` for Docker compatibility. |
| **FR-PDF-2** | ChromicPDF session pool shall be sized 1 with 60s timeout and on-demand startup (`on_demand: true`). |
| **FR-PDF-3** | HEEx templates shall live under `lib/vyaasa_campus_web/controllers/report_html/` (one per assessment + leaderboard + specialization). |
| **FR-PDF-4** | PDF generation shall be available both **on-demand** (student / admin clicks Download) and **asynchronously via the `ai_reports` Oban queue** for email delivery. |
| **FR-PDF-5** | Per memory note "PDF reports refactor direction" (2026-04-22) — the system shall use ChromicPDF + email-on-completion + on-demand download, replacing legacy jsPDF/html2canvas/window.print. v1 is expected to honour this direction. |

### 7.3 Background jobs (Oban)

| ID | Requirement |
|---|---|
| **FR-OB-1** | Oban queues shall be: `default: 10`, `emails: 5`, `imports: 3`, `ats_processing: 5`, `ai_reports: 10`, `cleanup: 1`. |
| **FR-OB-2** | Cron: `0 2 * * *` shall trigger `VyaasaCampus.Jobs.AtsFileCleanup` (daily 02:00 UTC). |
| **FR-OB-3** | `AtsResumeProcessor` job shall: max 3 attempts; exponential backoff (1m / 4m / 9m); 5-minute timeout. |
| **FR-OB-4** | `ReportGenerator` job shall: max 3 attempts; quadratic backoff (30s / 120s / 270s); 2-minute timeout. |
| **FR-OB-5** | `AtsFileCleanup` job shall: max 3 attempts; exponential backoff (1h / 4h / 9h); 1-hour timeout. |
| **FR-OB-6** | Plugins enabled: `Oban.Plugins.Pruner`, `Oban.Plugins.Cron`. |

### 7.4 File storage

| ID | Requirement |
|---|---|
| **FR-FS-1** | v1 shall store student documents on the local filesystem under `priv/uploads/{tenant_id}/students/{student_id}/`. \[confirm whether v1 ships with S3] |
| **FR-FS-2** | File-size limits: student documents 5 MB; admin question-bank uploads 100 MB. |
| **FR-FS-3** | Allowed types: resume `.pdf` / `.docx` / `.doc`; ID card and profile photo `.jpg` / `.jpeg` / `.png`. |
| **FR-FS-4** | Retention: 90-day default per ATS phase (`retention_policy_days`); cleanup job purges expired files. |
| **FR-FS-5** | When v1.1 migrates to S3, all file-access shall move to signed URLs; the existing Waffle dependencies are already wired and ready. |

### 7.5 Authentication and authorisation

| ID | Requirement |
|---|---|
| **FR-AUTH-1** | Guardian-issued JWT, `ACCESS_TOKEN_TTL_MINUTES = 30` (configurable), 60s allowed clock drift. |
| **FR-AUTH-2** | Three subject types supported: `AdminUser`, `User`, `Student`. |
| **FR-AUTH-3** | Tokens shall be cached for up to 1 hour via `AuthServer` (ETS). |
| **FR-AUTH-4** | Pipelines: `:require_auth`, `:require_admin`, `:require_tenant_user_or_admin`, `:require_tenant_user_only`, `:require_student`. |
| **FR-AUTH-5** | Refresh tokens shall be hashed at rest (`refresh_token_hash`) with explicit `refresh_token_expires_at`. |
| **FR-AUTH-6** | Password reset tokens shall be hashed at rest; raw token sent only via email; expiry 24 hours. |
| **FR-AUTH-7** | `temp_password` flag enforces a forced password change on first login. |
| **FR-AUTH-8** | All passwords shall be bcrypt-hashed (default cost). |
| **FR-AUTH-9** | Session cookie: signed (not encrypted), `same_site: Lax`, key `_vyaasa_campus_key`. CSRF protection on all browser routes. |

### 7.6 Multi-tenancy (Triplex)

| ID | Requirement |
|---|---|
| **FR-MT-1** | Each tenant shall have a dedicated Postgres schema named `tenant_{alias_lowercased}`. |
| **FR-MT-2** | Tenant migrations shall live in `priv/repo/tenant_migrations/`; run automatically on tenant creation; runnable in bulk via `mix ecto.migrate --prefix tenant_<name>`. |
| **FR-MT-3** | All tenant-scoped Ecto operations shall pass an explicit `prefix:` (no implicit tenant). |
| **FR-MT-4** | `TenantPlug` shall resolve the active tenant in this order: `X-Tenant` header → URL `:tenant` param → query string → subdomain → fallback. The resolved alias is uppercased before DB lookup. |
| **FR-MT-5** | Tenant context (schema name, tenant id, scope) shall be cached per request via `ScopePlug`. |
| **FR-MT-6** | A CI guard \[v1.1] should reject any new tenant-context Repo call lacking a `prefix:`. |

### 7.7 API surface

| ID | Requirement |
|---|---|
| **FR-API-1** | All API endpoints listed in `lib/vyaasa_campus_web/router.ex` shall accept JSON, set CORS appropriately, and return `application/json`. |
| **FR-API-2** | `POST /api/auth/refresh` shall accept a refresh token and return a new access token. |
| **FR-API-3** | `POST /api/auth/logout` shall revoke the active token. |
| **FR-API-4** | `POST /api/auth/clear-temp-password` shall clear the `temp_password` flag after first-login change. |
| **FR-API-5** | The internal API is not currently a published external surface; documented for engineering and CSM tooling only. \[confirm whether to publish in v2] |

### 7.8 Master data: industries, job roles, degrees

| ID | Requirement |
|---|---|
| **FR-MD-1** | `industries` (public) carry: `name`, `code`, `description`, `icon`, `is_active`. |
| **FR-MD-2** | `job_roles` (public) carry: `title`, `code`, `description`, `skills` (string array), `experience_level` (`entry`/`mid`/`senior`/`lead`), `is_active`, `industry_id`. |
| **FR-MD-3** | `degrees` and `specializations` (public) carry: `name`, `code`, `is_active`; `specialization` belongs_to `degree`. |
| **FR-MD-4** | Per-tenant `job_profiles` carry: `role`, `profile_text` (markdown), unique `(tenant_id, role)`. |

---

## 8. Non-functional requirements

### 8.1 Performance and concurrency

| ID | Requirement |
|---|---|
| **NFR-PE-1** | The platform shall support **500+ concurrent students** mid-assessment (with a paid Groq tier). Source: `docs/concurrency-scaling-500-users.md`. |
| **NFR-PE-2** | Page TTFB for authenticated dashboard pages shall be ≤ 500 ms p50, ≤ 1.5 s p95 under nominal load. \[confirm SLO with product] |
| **NFR-PE-3** | Resume parsing wall-clock shall be ≤ 90 seconds p95 (single LLM call + local embeddings). |
| **NFR-PE-4** | Groq rate limiter shall be configured with `GROQ_MAX_CONCURRENT = 50` and `GROQ_MAX_QUEUE_SIZE = 500` by default; both tunable per environment. |
| **NFR-PE-5** | Finch shall maintain 50 persistent HTTPS connections to `api.groq.com` (size 50, count 2 partitions). |
| **NFR-PE-6** | Postgres connection pool shall default to `POOL_SIZE = 40` (prod), `queue_target = 500ms`, `queue_interval = 2000ms`. |
| **NFR-PE-7** | LiveView processes shall hibernate after 30s idle (`hibernate_after: 30_000`) to keep memory footprint at ~5 KB per idle process. |
| **NFR-PE-8** | Bandit shall run with 100 acceptors and 60s read timeout in production. |
| **NFR-PE-9** | Production releases shall set `ERL_FLAGS="+P 1000000 +Q 65536"` to allow large numbers of processes and ports. |

### 8.2 Availability and reliability

| ID | Requirement |
|---|---|
| **NFR-AV-1** | Target uptime: **99.5% / month** excluding planned maintenance \[confirm SLO with product]. |
| **NFR-AV-2** | The system shall degrade gracefully when Groq is overloaded: queue absorbs bursts, 429 triggers a global pause for the `retry-after` duration, user-facing error is `groq_overloaded`. |
| **NFR-AV-3** | Oban shall retry failed report-generation jobs with quadratic backoff up to 3 attempts. |
| **NFR-AV-4** | Resume processing shall retry up to 3 times before marking the ATS phase as `failed`. |
| **NFR-AV-5** | Email delivery shall be enqueued via Oban (`emails` queue) so SMTP outages don't break user-facing flows. \[confirm — current implementation uses direct sends in some paths] |

### 8.3 Scalability

| ID | Requirement |
|---|---|
| **NFR-SC-1** | Horizontal scaling shall use sticky sessions (LiveView WebSocket affinity). Per-node DB pool and Groq concurrency shall be divided across nodes (e.g. 2 nodes × 20 pool size each = 40 total). |
| **NFR-SC-2** | Multi-node deployment shall require S3 (or shared storage) for student documents — local filesystem is single-node only. |
| **NFR-SC-3** | The platform shall support at least 1,000 tenant schemas per Postgres database before considering a different tenancy model. \[confirm targets with infra] |

### 8.4 Security

| ID | Requirement |
|---|---|
| **NFR-SE-1** | All passwords stored as bcrypt hashes; raw passwords never logged. |
| **NFR-SE-2** | All transit shall be HTTPS in production; `runtime.exs` enforces `scheme: "https"` and port 443. |
| **NFR-SE-3** | CSRF protection enabled on browser routes; `same_site: Lax` cookies. |
| **NFR-SE-4** | File uploads validated by extension + MIME type + size. |
| **NFR-SE-5** | JWT secrets (`SECRET_KEY_BASE`, `GUARDIAN_SECRET_KEY`) shall be loaded from env at runtime; defaults shall not be used in production. \[v1.1: lint to fail boot if defaults detected in prod] |
| **NFR-SE-6** | Tenant isolation shall be schema-level (not just `tenant_id` filter); no Repo call in tenant contexts shall omit `prefix:`. |
| **NFR-SE-7** | Login-attempt rate limiting and per-IP throttling are **not implemented in v1**; tracked as v1.1 requirement. |
| **NFR-SE-8** | Sobelow (security linter) is enabled in `dev`/`test`; CI shall run `mix sobelow` and gate on findings. \[confirm with engineering] |

### 8.5 Privacy and compliance \[assumed — confirm]

| ID | Requirement |
|---|---|
| **NFR-PR-1** | The platform shall comply with the Indian DPDP Act 2023 — student is data principal, institution is fiduciary, Vyaasa is processor. |
| **NFR-PR-2** | Hosting region: India (matches data-residency expectations of institutional buyers). |
| **NFR-PR-3** | Per-tenant and per-student data export shall be supported on request. |
| **NFR-PR-4** | Per-student deletion request shall be honoured within \[confirm SLA — proposed 30 days]. |
| **NFR-PR-5** | Resume retention default: 90 days from ingestion; configurable per ATS phase. |
| **NFR-PR-6** | Audit fields (`created_by_id`, `created_by_type`, `approved_by_id`, `last_login_at`, `email_verified_at`, `profile_reviewed_at`) shall be populated on all relevant lifecycle events. |

### 8.6 Observability

| ID | Requirement |
|---|---|
| **NFR-OB-1** | All requests shall carry a `request_id`; structured logs shall include `request_id` in metadata. |
| **NFR-OB-2** | Telemetry metrics shall be emitted for Phoenix endpoint, router dispatch, Ecto query (total / decode / query / queue / idle), and BEAM VM (memory, run queues). |
| **NFR-OB-3** | Phoenix LiveDashboard shall be available at `/dev/dashboard` (dev) and `/admin/jobs` for Oban (prod, gated to platform admin). |
| **NFR-OB-4** | Groq rate-limiter stats shall be queryable: `in_flight`, `max_concurrent`, `queue_size`, `total_processed`, `total_queued`, `total_rejected`, `paused`. |
| **NFR-OB-5** | External APM (Sentry / Datadog / New Relic) is **not configured in v1**; tracked as v1.1 requirement. |
| **NFR-OB-6** | Alert thresholds (target for v1.1): `queue_size > 50` warn / `> 200` critical; `total_rejected > 0/min` warn; `paused > 30s` warn / `> 60s` critical; DB pool checkout `> 200ms` warn / `> 1000ms` critical. |

### 8.7 Maintainability

| ID | Requirement |
|---|---|
| **NFR-MA-1** | All code shall pass `mix credo --strict` (configured) and `mix sobelow`. |
| **NFR-MA-2** | All schemas shall live under `lib/vyaasa_campus/schema/<domain>/`; contexts under `lib/vyaasa_campus/contexts/`. |
| **NFR-MA-3** | AI engines shall be pure-function modules wrapped by context modules (no AI calls in LiveView modules; instead dispatched via `Task.Supervisor`). |
| **NFR-MA-4** | Migrations shall be split into `priv/repo/migrations/` (public) and `priv/repo/tenant_migrations/` (per-tenant). |

### 8.8 Testability

| ID | Requirement |
|---|---|
| **NFR-TE-1** | Test categories present: unit (`test/unit/`), domain (`test/vyaasa_campus/`), web (`test/web/`). |
| **NFR-TE-2** | Test DB shall use `Ecto.Adapters.SQL.Sandbox` with optional `MIX_TEST_PARTITION` for CI parallelism. |
| **NFR-TE-3** | Test mailer shall be `Swoosh.Adapters.Test`. |
| **NFR-TE-4** | A regression load script shall exist at `scripts/regression_5_users.exs` exercising all five AI flows (Psychometric, Behavioral, JAM, Interview, Resume). \[v1.1: extend to 50 / 500 users; gate on Groq tier] |
| **NFR-TE-5** | Wallaby (E2E) scaffolding is present but unused; v1.1 should add a smoke E2E suite for the three role flows. |

---

## 9. Data model summary

### 9.1 Public schema (platform-wide)

| Table | Purpose | Key fields |
|---|---|---|
| `platform_admins` | Vyaasa internal users | `email` (unique), `encrypted_password`, `role`, `status`, refresh + reset tokens |
| `tenants` | Onboarded institutions | `full_name`, `alias` (unique), `schema_name` (unique), `affiliation_type`, `status`, `settings`, `created_by` |
| `tenant_locations` | Per-tenant addresses | `tenant_id`, `name`, `address`, `city`, `state`, `pincode`, `is_primary` |
| `degrees` / `specializations` | Master academic taxonomy | `name`, `code`, `is_active`; specialization belongs_to degree |
| `industries` / `job_roles` | Master career taxonomy | `name`, `code`, `description`, `experience_level`, `skills[]` |
| `qa` (master question bank) | MCQ question pool | `question`, `answer`, `options`, `type`, `weightage`, `topic_id` |
| `oban_jobs` | Oban queue table | standard Oban schema |

### 9.2 Tenant schema (per-tenant)

| Table | Purpose | Key fields |
|---|---|---|
| `users` | Tenant-side users (admin, instructor, etc.) | `email`, `role`, `status`, temp + reset tokens, `tenant_id` |
| `roles` / `user_roles` | Tenant RBAC | `permissions[]`, join table |
| `students` | Student records | `email`, `degree_id`, `specialization_id`, `year_of_passing`, `registration_id`, status, profile/edit tokens, audit fields |
| `student_ats_phases` | Resume scoring attempts (history-aware) | `attempt_number` (unique with `student_id`), parsed JSON fields, `ats_score`, `metadata`, retention fields |
| `student_psychometric_assessments` | Big Five sessions | per-trait scores 1.0–5.0, `factor_reports`, `attempt_number` |
| `student_behavioral_assessments` | Behavioral sessions | five competency scores 0–100, `completed_scenarios`, `attempt_number` |
| `jam_sessions` | JAM speech sessions | topic, transcript, five dimension scores 1–10, final 0–100, `retry_count` |
| `interview_sessions` | Mock-interview sessions | `questions_data`, `overall_score`, `final_report`, `retry_count` |
| `assessments` / `assessment_attempts` | Tenant-side MCQ assessments | lifecycle states, `weightage`, `passing_marks`, attempt history |
| `job_profiles` | Per-tenant role rubrics | `role` (unique with `tenant_id`), markdown `profile_text` |

### 9.3 State diagrams

**Student lifecycle** — *derived*

```
pending → profile_incomplete → unverified → verified → active
                                        ↑
                          (admin requests edits)
```

**ATS phase status** — *derived*

```
queued → processing → completed
                  ↘ failed / errored / manual_review
```

**Tenant-side assessment lifecycle** — *derived*

```
draft → published → active → completed → archived
```

**Assessment session statuses** — *derived from each engine module*

- Psychometric: `started → processing → completed` / `failed`
- Behavioral: `started → interviewing → completed` / `failed`
- JAM: `created → topic_generated → decision_phase → preparation → speaking → processing → completed` / `failed`
- Interview: `created → resume_indexed → initialized → interviewing → completing → completed` / `failed`

---

## 10. External integrations

| Integration | Purpose | Module(s) | Env vars |
|---|---|---|---|
| Groq API (chat) | All LLM-driven scoring & generation | `VyaasaCampus.AI.GroqClient`, `GroqRateLimiter` | `GROQ_API_KEY`, `GROQ_MAX_CONCURRENT`, `GROQ_MAX_QUEUE_SIZE` |
| Groq API (Whisper) | JAM and Mock Interview audio transcription | same | same |
| Groq API (Orpheus TTS) | Mock Interview voice output | same | same |
| Bumblebee + Nx + EXLA | Sentence-transformer embeddings for resume relevance | `EmbeddingServer` | none |
| SMTP | Transactional email | `VyaasaCampus.Contexts.Mailer`, Swoosh | `SMTP_RELAY`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM_EMAIL` |
| Postgres | Primary data store | Ecto + Triplex | `DATABASE_URL`, `POOL_SIZE` |
| ChromicPDF / Headless Chrome | PDF rendering | `VyaasaCampus.Reports`, `ChromicPDF` | none (binary at `/usr/bin/google-chrome`) |
| AWS S3 (planned) | File storage | Waffle (wired, not active) | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (when enabled) |

External dependencies that **do not exist yet** but are likely v1.1 candidates:

- Sentry / Datadog / New Relic for APM.
- IP / login rate limiter (e.g. Hammer).
- SSO providers (Google Workspace, Microsoft Entra).
- Per-IP file-download rate limiting on resume access.

---

## 11. Configuration reference

| Variable | Purpose | Default |
|---|---|---|
| `DATABASE_URL` | Postgres DSN (prod) | required |
| `POOL_SIZE` | Postgres pool (prod) | 40 |
| `PORT` | HTTP port | 4000 |
| `PHX_HOST` | Public hostname | example.com |
| `SECRET_KEY_BASE` | Phoenix signing | required in prod |
| `GUARDIAN_SECRET_KEY` | JWT signing | required in prod (default fails fast) |
| `ACCESS_TOKEN_TTL_MINUTES` | JWT lifetime | 30 |
| `FRONTEND_URL` | Email link base URL | https://dev-ui.vyaasa.in |
| `SMTP_RELAY` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` / `SMTP_FROM_EMAIL` | SMTP creds | provider-specific |
| `GROQ_API_KEY` | Groq API key | required for AI |
| `GROQ_MAX_CONCURRENT` | Rate-limiter concurrency | 50 |
| `GROQ_MAX_QUEUE_SIZE` | Rate-limiter queue depth | 500 |

Legacy variables (no longer used in v1; keep for transition only): `ATS_BASE_URL`, `ATS_SERVICE_TOKEN`, `PYTHON_BASE_URL`.

---

## 12. Routes reference (abridged)

> Full list in `lib/vyaasa_campus_web/router.ex`. Below is a tiered summary by audience.

### 12.1 Public / browser

- `GET /` — institution-selection homepage.
- `GET /admin/login` `/admin/forgot-password` `/admin/reset-password/:token`.
- `GET /auth/tenant/:tenant/login` `/forgot-password` `/reset-password/:token`.
- `GET /profile/:profile_token/ats` — pre-login profile completion.
- `GET /profile/shared/:token` — public shared profile.

### 12.2 Platform admin (LiveView, `:require_admin`)

- `/admin/dashboard`, `/admin/assessments-config`, `/admin/degrees`, `/admin/question-bank`, `/admin/jobs`, `/admin/change-password`.

### 12.3 Tenant admin (LiveView, `:require_tenant_user_only`)

- `/user/:tenant/dashboard`, `/dashboard/addstudent`, `/dashboard/students`, `/dashboard/programs`, `/change-password`.
- Reports (`:require_tenant_user_or_admin`): `/user/:tenant/reports/leaderboard`, `/reports/specialization`.

### 12.4 Student (LiveView, `:require_student`)

- `/student/:tenant/dashboard`, `/change-password`.
- Assessments: `/assessment/instructions`, `/assessment/behavioral`, `/assessment/:id/test`, `/assessment/:id/review`, `/assessment/:id/result`, `/jam/session`, `/interview/session`, `/assessment/psychometric`, `/resume/reanalyze`.
- Reports: `/reports/mcq/:attempt_id`, `/reports/jam/:session_id`, `/reports/psychometric/latest`, `/reports/behavioral/latest`, `/reports/interview/:session_id`.

### 12.5 API (JSON)

- Auth: `/api/auth/{platform-admin,tenant-user,student}/login`, `/refresh`, `/me`, `/logout`, `/password-reset/{request,reset}`, `/clear-temp-password`, `/student/register`.
- Profile completion (token-based): `/api/student/profile-completion/verify`, `/submit`, `/resend`.
- Platform admin: `/api/platform_admin/tenants*`, `/locations*`.
- Tenant admin: `/api/tenant/users*`, `/roles*`, `/user_roles*`, `/students*`, `/students/pending`, `/students/:id/{approve,reject,approve-edit,reject-edit}`, `/students/edit-requests`, `/students/bulk`, `/students/:student_id/resume/*filename`, `/assessments*`.
- Student: `/api/student/assessments*`, `/attempts*`, `/jam/sessions*`, `/profile/edit-request`.

---

## 13. Acceptance criteria (high-level)

The system is functionally accepted for v1 when, for a representative test tenant:

1. Platform admin can create the tenant; tenant admin user is auto-created and emailed.
2. Tenant admin can add at least one student; student receives the profile-completion email.
3. Student completes profile upload; resume is parsed within 90s p95; ATS score is computed.
4. Tenant admin verifies the student; student receives credentials and logs in.
5. Student completes all six assessments end-to-end; all six reports are downloadable as PDFs.
6. All transitions are reflected on tenant admin dashboard within ≤ 5 seconds.
7. 50 concurrent students complete the JAM and Behavioral flows without rate-limiter rejection (paid Groq tier).
8. All tests in `test/` pass; `mix credo --strict` clean; `mix sobelow` no critical findings.
9. Tenant data is observably isolated: a query without `prefix:` cannot return another tenant's row.
10. PDF reports render legibly across the supported templates (`mcq`, `psychometric`, `behavioral`, `jam`, `interview`, `leaderboard`, `specialization`).

---

## 14. Open questions for engineering / product sign-off

The following items in this FRD are flagged \[assumed — confirm]. Resolving them turns this draft into v1.0:

1. **Retake gating** for Behavioral / JAM / Mock Interview (FR-A4-9, FR-A6-15) — admin-gated or student-controlled?
2. **Profile-completion token TTL** (FR-ST-7) — confirm 48h.
3. **S3 vs local filesystem in v1** (FR-FS-1, NFR-SC-2) — does v1 ship with S3 or stay on local FS?
4. **Email-on-completion vs on-demand-only PDFs** (FR-PDF-4, FR-PDF-5) — confirm per assessment.
5. **Performance SLOs** (NFR-PE-2) — page TTFB targets.
6. **Uptime SLO** (NFR-AV-1) — 99.5% acceptable?
7. **Login rate limiting and APM** (NFR-SE-7, NFR-OB-5) — defer to v1.1 or land in v1?
8. **Privacy/retention SLAs** (NFR-PR-4) — student-deletion SLA.
9. **Public shared profile semantics** (FR-ST-19) — payload, expiry, revocation.
10. **Tenant program model** (FR-TA-24) — confirm program schema and intended workflow.
11. **External API publication** (FR-API-5) — does the JSON API become an external surface in v2?
