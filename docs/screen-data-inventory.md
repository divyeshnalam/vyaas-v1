# Screen Data Inventory

A reference for redesigning the UI. For every screen and every PDF report this lists **what data is on it** — the exact fields, lists, scores, and counts the current code renders — plus actions, states, and where the data comes from.

This is **not** an API reference. Field names use the codebase's internal naming (Elixir snake_case). A designer can use this to lay out screens without reading the code; an engineer can grep these names to find the underlying schema.

## Contents

1. [Reports (PDF)](#1-reports-pdf) — *primary focus*
   - Shared report chrome
   - MCQ Assessment Report
   - JAM Session Report
   - Interview Session Report
   - Behavioral Assessment Report
   - Psychometric Assessment Report
   - Leaderboard Report (admin)
   - Specialization Performance Report (admin)
2. [Student screens](#2-student-screens)
3. [Tenant-admin screens](#3-tenant-admin-screens)
4. [Platform-admin screens](#4-platform-admin-screens)
5. [Auth & public screens](#5-auth--public-screens)
6. [Reference data structures](#6-reference-data-structures)

---

## 1. Reports (PDF)

All PDF reports are rendered server-side by ChromicPDF from `.heex` templates in `lib/vyaasa_campus_web/controllers/report_html/`. Controller: `lib/vyaasa_campus_web/controllers/report_controller.ex`.

### 1.0 Shared report chrome

Every report (student or admin) uses the same shared layout components:

**Header (`report_header`)**
- Vyaasa logo (PNG, base64-embedded)
- Brand tag: "Vyaasa Assessment Report"
- Student metadata strip *(student reports only — `nil` for admin)*:
  - `student.first_name` + `student.last_name`
  - `student.email`
  - Generated timestamp (`generated_at_display`)

**Watermark** — fixed centered logo at 8% opacity.

**Footer** — `"Vyaasa · Confidential Assessment Report · {generated_at_display}"`, 8pt gray.

**Common visual styling**
| Element | Spec |
|---|---|
| Page size | A4 portrait (12 mm margins); leaderboard is **A4 landscape** (10 mm) |
| Font | -apple-system stack, 11pt base, body color `#111827` |
| Primary accent | Orange `#f97316` (top border, table headers) |
| Card chrome | 1px border, 10px radius, 14px padding, white bg, `page-break-inside: avoid` |
| Title block | h1 (18pt) + subtitle (10pt) + colored performance badge |

**Performance band rules** (used wherever a 0–100 score is shown)
| Score range | Label | Color | Hex |
|---|---|---|---|
| ≥ 90 | Outstanding | green | `#16a34a` |
| ≥ 75 | Excellent | green | `#16a34a` |
| ≥ 60 | Good | amber | `#d97706` |
| ≥ 40 | Needs Improvement | orange | `#ea580c` |
| < 40 | Keep Trying | red | `#dc2626` |

**Computed helpers** (consistent across all reports)
- `performance_label(score)`, `performance_color(score)`, `perf_color(score)` — the band thresholds above.
- `accuracy_bar_color(pct)` — green ≥75%, amber ≥50%, red otherwise.
- `format_score(value)` — `nil → "-"`, otherwise rounded integer string.
- `humanize_key(snake_case)` — `clarity_notes → "Clarity Notes"` (for feedback dict keys).

---

### 1.1 MCQ Assessment Report

**Route:** `GET /student/:tenant/reports/mcq/:attempt_id`
**Audience:** Student, after submitting an MCQ assessment.
**Data sources:** `AssessmentAttempt` (with `evaluation_data` + timestamps) and the parent `Assessment`.

**Sections, top to bottom**

1. **Title block** — *"MCQ Assessment Report"* with `assessment.title` subtitle and performance badge.
2. **Score Overview**
   - Circular SVG gauge (0–100, animated stroke)
   - Center text: `score / total_marks`
   - Right column: `percentage` (rounded), verdict label, subtitle line "Attempted X of Y questions · Total marks Z"
3. **Score Breakdown** — five cards in a row, color-coded:
   | Card | Value | Type | Color |
   |---|---|---|---|
   | Correct | `correct` | int | green |
   | Wrong | `wrong` | int | red |
   | Unanswered | `unanswered` | int | gray |
   | Negative | `negative_marks` | float (2dp) | orange |
   | Final | `score` | float (1dp) | blue |
4. **Performance Summary** — two horizontal bars:
   - **Accuracy bar** — `correct / (correct + wrong) * 100`, color via `accuracy_bar_color`
   - **Completion bar** — `(correct + wrong) / total_questions * 100`, blue
5. **Time Analysis** (key-value table)
   - Total Time Taken — `{minutes(time_taken)} min of {assessment.duration_minutes} min`
   - Average Time per Question — `avg_time_per_question` (float, 2dp, minutes)
   - Questions — `total_questions`

---

### 1.2 JAM Session Report

**Route:** `GET /student/:tenant/reports/jam/:session_id`
**Audience:** Student, after completing a JAM (Just A Minute) speaking task.
**Data sources:** `JamSession` (evaluation, transcript, audio metadata).

**Sections**

1. **Title block** — *"JAM Session Report"*; subtitle `topic_title`; performance badge.
2. **Overall Performance** — gauge (0–100) + `final_score`, verdict, subtitle "Spoke for {speech_duration}s · {word_count} words".
3. **Sub-score grid** (5 columns, each 0–10):
   `clarity`, `structure`, `relevance`, `impact`, `confidence`. Nil values render as 0.
4. **Overall Summary** *(conditional on `overall_summary`)* — paragraph.
5. **Strengths & Areas to Improve** *(conditional)* — two bulleted columns: `strengths`, `improvements`. Empty list → "—".
6. **Detailed Feedback** *(conditional on `detailed_feedback` map non-empty)*. For each key (typically `clarity_feedback`, `structure_feedback`, etc.) render a sub-heading via `humanize_key/1` and the paragraph.
7. **Transcript** *(conditional)* — preformatted text in a scrollable box (max-height 220px in print).

---

### 1.3 Interview Session Report

**Route:** `GET /student/:tenant/reports/interview/:session_id`
**Audience:** Student, after an AI-led interview session.
**Data sources:** `InterviewSession` (`questions_data`, scores, transcripts, final_report).

**Sections**

1. **Title block** — *"Interactive Session Report"*, subtitle "Generated for {candidate_name}", performance badge from `overall_score`.
2. **Overall Score** — gauge + `overall_score`, subtitle "Completed {questions_completed} of {length(questions)} questions".
3. **Strengths & Areas to Improve** *(conditional)* — same pattern as JAM.
4. **Question-by-Question Breakdown** *(conditional on `questions != []`)*. Per question card:
   - Header: `Q{question_number}: {question_text}`
   - Score chip *(if `q["score"]`)*: `{score}/100`, color via `perf_color`
   - **Transcript** *(if present)* — monospace, dashed border
   - **Feedback rows** *(any of these may be present)*:
     - `q["evaluation"]` → "Evaluation: …"
     - `q["reasoning"]` → "Reasoning: …"
     - `q["feedback"]` → "Feedback: …"
5. **Final Report** *(conditional on `final_report`)* — pre-wrapped paragraph.

---

### 1.4 Behavioral Assessment Report

**Route:** `GET /student/:tenant/reports/behavioral/latest`
**Audience:** Student, after the scenario-based behavioral assessment.
**Data sources:** `StudentBehavioralAssessment` (`scores`, `reasoning` map, `completed_scenarios`, `candidate_profile`).

**Sections**

1. **Title block** — *"Behavioral Assessment"*, subtitle "{candidate_name} · {role} · {education}" (role and education conditional), performance badge.
2. **Overall Score** — gauge + `overall_score`, verdict, optional `summary` line.
3. **Competencies** — five rows, each with label, score chip `{value}/100`, color-coded bar (via `perf_color`), and a reasoning paragraph from `reasoning[key]`:
   | Row | Label | Source |
   |---|---|---|
   | 1 | Work Ethics & Reliability | `scores.work_ethics` |
   | 2 | Teamwork & Collaboration | `scores.teamwork` |
   | 3 | Adaptability & Learning | `scores.adaptability` |
   | 4 | Leadership Potential | `scores.leadership` |
   | 5 | Communication Skills | `scores.communication` |
4. **Strengths & Areas for Development** *(conditional)* — two bulleted columns: `strengths`, `areas_for_development`.
5. **Scenario Responses** *(conditional on `completed_scenarios != []`)*. Per scenario:
   - "Scenario {scenario_number}: {question}"
   - Optional meta line: "Score: {score}"
   - `response` paragraph

---

### 1.5 Psychometric Assessment Report

**Route:** `GET /student/:tenant/reports/psychometric/latest`
**Audience:** Student. Big Five personality profile — **not** a 0–100 score report (no performance badge).
**Data sources:** `StudentPsychometricAssessment` (`scores`, `factor_reports`, `strengths`, `development_areas`, `suggestions`).

**Sections**

1. **Title block** — *"Psychometric Assessment"*, subtitle *"Big Five Personality Profile"*. No badge.
2. **Overall Summary** *(conditional)* — paragraph from `overall_summary`.
3. **Big Five Factor Scores** — 5 rows, each a label + score / 5.0 + horizontal bar (`(score / 5) * 100` % width):
   | Trait label | Field |
   |---|---|
   | Openness to Experience | `scores.openness` |
   | Conscientiousness | `scores.conscientiousness` |
   | Extraversion | `scores.extraversion` |
   | Agreeableness | `scores.agreeableness` |
   | Emotional Stability | `scores.neuroticism` *(field name preserved from source data; the label is inverted in UI)* |

   Nil shows as "—".
4. **Factor Reports** *(conditional)*. Each factor is an orange-bordered box containing:
   - Title `factor["factor"]`
   - "Score: {factor["score"]} / 5.0"
   - Optional `interpretation` paragraph
   - **Strengths** list *(if non-empty)*
   - **Risks** list *(if non-empty)*
   - **Suggestions** list *(if non-empty)*
5. **Key Strengths & Development Areas** *(conditional)* — two bulleted columns.
6. **Recommendations** *(conditional)* — bulleted `suggestions` list.

---

### 1.6 Leaderboard Report (admin)

**Route:** `GET /user/:tenant/reports/leaderboard?department=&specialization=&year=` (admin only)
**Audience:** Tenant admin/faculty. **Landscape A4.**
**Data sources:** `DashboardLive.load_all_students_with_scores()` + `StudentRankings.get_top_rankers()` with the query-param filters applied.

**Sections**

1. **Title block**
   - Heading: *"Overall Leaderboard"*
   - Subtitle: a description of active filters, e.g. "All departments · All specializations · All years" or "Dept: Engineering · Spec: AI/ML · Year: 2024"
   - Badge: "{total} students"
2. **Leaderboard table**, 11 columns. Empty state row spans full width: "No students match the selected filters."
   | Col | Header | Field | Notes |
   |---|---|---|---|
   | 1 | # | rank | Rank pill — gold (1), silver (2), bronze (3), gray default |
   | 2 | Student | `r.name` + `r.registration_id` | Two-line cell |
   | 3 | Degree | `r.degree` | |
   | 4 | Specialization | `r.specialization` | |
   | 5 | Resume | `r.ats_score` | via `format_score` |
   | 6 | MCQ | `r.mcq_percentage` | via `format_score` |
   | 7 | Behav. | `r.behavioral_score` | |
   | 8 | JAM | `r.jam_score` | |
   | 9 | Intrv. | `r.interview_score` | |
   | 10 | Psych. | `r.psychometric_score` | |
   | 11 | Vyaasa | `r.vyaasa_score` | Bold blue |

   Row backgrounds: rank 1 yellow (`#fef9c3`), rank 2 gray (`#f3f4f6`), rank 3 amber (`#fef3c7`); zebra stripe otherwise.

---

### 1.7 Specialization Performance Report (admin)

**Route:** `GET /user/:tenant/reports/specialization` (admin only)
**Audience:** Tenant admin/faculty. Aggregated view by specialization/department.
**Data sources:** `StudentRankings.get_department_stats()`.

**Sections**

1. **Title block** — *"Specialization-wise Performance"*, subtitle "{count} specializations · sorted by Vyaasa Score".
2. **Department performance table**, 6 columns. Empty state: "No specialization data available."
   | Col | Header | Field | Type / styling |
   |---|---|---|---|
   | 1 | Specialization | `d.department` | bold |
   | 2 | Students | `d.student_count` | int |
   | 3 | Scored | `d.scored_count` | int |
   | 4 | Highest Vyaasa | `d.highest_vyaasa_score` | green bold; "-" if nil |
   | 5 | Topper | `d.topper.name` | text; "-" if no topper |
   | 6 | Topper Score | `d.topper.score` | blue bold; "-" if nil |

---

## 2. Student screens

### 2.1 Student Dashboard

**Purpose:** Hub showing profile summary, scores, rankings, and assessment entry points.
**Route:** `/student/:tenant/dashboard`

**Layout:** Collapsible left sidebar (with ranking mini-scores) · top header · main column stacked with cards.

**Cards / sections, top to bottom**

| Card | Content |
|---|---|
| User header | `user_info.name`, `user_info.role` (= "Student"), `user_info.email` |
| Profile card | `student.first_name`, `last_name`, `email`, `status` ("active"/"verified"/"unverified"), `registration_id`, `degree`, `specialization`, `cgpa`, `year_of_passing` |
| About | `ats_data.personal_information.location` or `.city`; `ats_data.professional_summary.summary`; `ats_data.professional_summary.total_experience` |
| Resume Score | Circular gauge of `ats_data.ats_score` (0–100); sub-bars for `metadata.completeness_score`, `metadata.relevance_score`, `metadata.sanity_score` (each 0–100); `metadata.completeness_feedback` list |
| Skill radar | Built from `rankings.{ats,mcq,behavioral,jam,interview}.score` |
| Verified skills | `ats_data.skills.technical_skills` + `non_technical_skills` (string lists) |
| Vyaasa Score | Circular gauge of `vyaasa_data.vyaasa_score` (0–100, gradient) |
| Component scores | One row each: ATS, MCQ, Behavioral, JAM, Interview — value, rank, percentile |
| Attempt history | `attempt_history` list — title, score, date |
| Assessment steps | `instructions` list — id (`resume_parsing` / `objective_evaluation` / `jam_session` / `ai_introduction` / `behavioral_questions` / `psychometric`), title, description; completion badge driven by `has_completed_interview`, `has_completed_jam`, `behavioral_completed`, `psychometric_completed`, `submitted_attempt` |

**Actions:** Start assessment (per step) · Download Resume (auth API) · Re-analyze Resume (`/student/:tenant/resume/reanalyze`) · Share Profile → opens modal showing `share_url` (Phoenix signed token) · Copy share link · Logout.

**Modals:** `show_ats_modal`, `show_share_modal`.

**Empty / error states**
- No completed assessment → "No completed assessment found"
- No ATS data → "No resume available for download"
- Invalid `profile_token` → error card with "Try Again"

---

### 2.2 Profile Completion — Step 1 (Documents + Job Role)

**Purpose:** Collect resume, ID card, profile photo; choose preferred job role.
**Route:** `/student/:tenant/resume?profile_token=…&step=1` (first-time) or `/student/:tenant/resume/reanalyze?step=1` (re-analyze flow).

**Layout:** Outer card with orange top border; header + 3-step progress stepper (numeric circles connected by lines); step content; footer nav.

**Fields shown read-only** (first-time):
`student.first_name`, `last_name`, `email`, `registration_id`, `degree`, `specialization`, `year_of_passing`, `cgpa`.

**Uploads** (Phoenix LiveView uploads, 5 MB max each):
`resume`, `id_card`, `profile_photo`, `certification` — each entry has `client_name`, `done?`, `ref`.

**Job-role picker:** `job_roles` is a list of `{industry_name, [role_name, …]}` tuples; `preferred_job_role` is the current selection (highlighted orange when set).

**UI state:** `current_step` (1/2/3), `completion_percentage` (10/60/100), `loading?`, `reanalyze_mode?`, `processing_after_step1?`, `processing_timeout`, `error_message`.

**Actions:** auto-upload on file pick · Cancel an entry (`cancel_upload`, ref + type) · Select job role · Next Step / Analyze My Resume · Previous Step · Retry Verification (on error).

**Empty / error states**
- No files: "Please upload resume and ID card"
- Token invalid/expired: error card with "Try Again"
- Processing > 180 s: timeout warning (still tries to load data)
- No job role: "Please select a job role to continue"

---

### 2.3 Profile Completion — Step 2 (Resume Analysis Dashboard)

**Purpose:** Show parsed resume + scored breakdown.
**Route:** `…?step=2`

**Layout:** Sticky navbar (filename, last-updated, role input, Re-Analyze / Upload New Resume / Download Report) · Dashboard header · Overall Resume Score (gauge + 3 metric cards) · Improvement banner · Skills · Work Experience · Education · Projects · External Links · footer nav.

**Source data:** `ats_phase` (id, `resume_url`, `status`, `updated_at`, `preferred_role`) + `ats_data` (parsed structure):

- `ats_data.ats_score` (0–100)
- `ats_data.preferred_role`
- `ats_data.skills` (string list)
- `ats_data.work_experience[]`: `job_title`, `company_name`, `start_date`, `end_date`, `responsibilities`
- `ats_data.languages` (string list)
- `ats_data.external_links`: `linkedin`, `github`, `portfolio`, `other`
- `ats_data.education[]`, `ats_data.projects[]`
- `ats_data.completeness`: `score`, `feedback[]`, `other_links[]`
- `ats_data.relevance`: `score`, `matching_keywords[]`, `missing_keywords[]`, `justification`
- `ats_data.sanity`: `score`, details
- `ats_data.areas_for_improvement` (map)

**Toggle state:** `show_completeness_feedback`, `show_relevance_feedback`, `show_sanity_feedback` — click on a metric card expands its details.

**Actions:** Toggle feedback section · Re-Analyze (clears ATS data, back to step 1) · Upload New Resume · Download Report · Next Step.

---

### 2.4 Profile Completion — Step 3 (Verification)

**Purpose:** Show admin-verification status; final-step confirmation.
**Route:** `…?step=3`

**Data:** `student.status` and `ats_phase.status`; optional verification timestamps.

**Visuals:** Verification badge (blue pending / green verified / red rejected); progress bar at 100%.

**Actions:** View Dashboard · Start Assessment *(if verified)*.

**States:** Pending: "Your profile is under review…" · Rejected: "Verification failed. Please contact support."

---

### 2.5 Assessment Instructions

**Purpose:** Pre-test screen — rules + section breakdown + acknowledgment.
**Route:** `/student/:tenant/assessment/instructions`

**Sections**

1. **4 info cards** — Questions (count of `assessment.settings.questions`), Duration (`assessment.duration_minutes`), Total Marks (`assessment.total_marks`), Sections (derived).
2. **Section breakdown table** — for each entry in `sections`: `name`, `count`, `duration`, marks/q, negative marking.
3. **Rules & guidelines** — 9 hardcoded rules with emoji icons.
4. **Acknowledgment** — `agreed_to_terms` checkbox + "Start Assessment →" (disabled until checked).

**Actions:** Toggle agreement · Start (redirects to test or, if already submitted, to result) · Back to Dashboard.

---

### 2.6 Assessment Test (in-test)

**Purpose:** MCQ test taking.
**Route:** `/student/:tenant/assessment/:assessment_id/test?attempt=:attempt_id`

**Layout:** Optional red banner (tab-switch warning) · sticky top bar (title, section badge, **timer center**, student name, submit) · split body: left = question + options, right sidebar = question grid + legend + section summary.

**Per-question data:** `questions[i]` = `{ id, question, options: %{a:…, b:…, c:…, d:…}, subject_name }`.

**Attempt state:** `attempt.id`, `attempt.status` ("started"/"submitted"), `attempt.started_at`, `attempt.submitted_at`, `attempt.answers` (`%{question_id => option_key}`), `attempt.metadata.{current_question_index, tab_switch_count, answer_timestamps, answer_change_counts}`.

**Client-side state (LiveView assigns):** `current_question_index`, `current_section`, `answers`, `marked_for_review` (MapSet), `visited_questions` (MapSet), `time_remaining` (seconds), `timer_warning_level` (`:normal | :caution | :warning | :critical`), `tab_switch_count`, `show_tab_warning`, `submitting`.

**Timer color rules**
- > 10 min: gray
- 5–10 min: orange
- 1–5 min: red
- < 1 min: red pulsing

**Question-grid cell colors**
- Blue: current
- Green: answered
- Amber: marked for review
- Pink/light-red: visited but not answered
- Gray: not visited

**Section summary (right sidebar):** Answered (green), Marked for Review (amber), Not Visited (gray).

**Actions:** Select option · Clear Response · Mark / Unmark for Review · Previous · Next · Review & Submit (last question) · Click cell in grid to jump · Submit (top right, with confirm) · Auto-submit on timer 0 · Tab-switch warning dismiss.

**Error/edge:** No questions loaded → redirect to instructions · Already submitted → redirect to result · Time expired on load → force-submit.

---

### 2.7 Assessment Review

**Purpose:** Pre-submission summary.
**Route:** `/student/:tenant/assessment/:assessment_id/review?attempt=:attempt_id`

**Sections**

1. Header (title + time remaining badge in orange).
2. 4 summary cards: Total Questions, Answered (green), Marked for Review (amber), Unanswered (red).
3. Warning banner *(if unanswered > 0)*.
4. **Section-wise breakdown table** — per section: Total / Answered / Marked / Unanswered.
5. **Question grid** (large) — green = answered, gray = not answered.
6. Action bar — "← Back to Test" / "Submit Assessment".
7. **Submit confirmation modal** — `show_submit_modal`.

**Edge cases:** No attempt → back to instructions · Already submitted → result · Time expired → force-submit · Submission too fast → error stays on page.

---

### 2.8 Assessment Result

**Purpose:** Score report (mirrors MCQ PDF).
**Route:** `/student/:tenant/assessment/:assessment_id/result`

**Sections**

1. Title + performance badge (label includes emoji: 🌟 Outstanding, 🎯 Excellent, 👍 Good, 📈 Needs Improvement, 💪 Keep Trying)
2. Score Overview — circular gauge + colored % text (green ≥75, amber 60–75, orange 40–60, red <40)
3. Score Breakdown (5 cards): Correct/Wrong/Unanswered/Negative/Final — same fields as the PDF
4. Performance Summary — Accuracy bar, Completion bar (same formulas as MCQ PDF)
5. Time Analysis — total time, average per question
6. Action bar: "Go to Dashboard", "Download Score Card" (links to `/student/:tenant/reports/mcq/:attempt_id`)
7. **Confetti** when `percentage >= 75`

**Source fields:** `attempt.score`, `attempt.percentage`, `attempt.evaluation_data.{correct, wrong, unanswered, total_questions, negative_marks}`, `attempt.started_at`/`submitted_at`, `assessment.total_marks`, `assessment.duration_minutes`. Time-taken derived from the two timestamps.

---

### 2.9 JAM Session

**Purpose:** Speak on a generated topic for 60 s; AI evaluates.
**Route:** `/student/:tenant/jam/session`

**Phase machine** — `current_step` ∈ `{:instructions, :topic, :speak, :feedback}`.

| Phase | What's on screen |
|---|---|
| Instructions | Collapsible instructions (`show_full_instructions`) + Start Session button |
| Topic | `topic.title`, optional `topic.guidance`, optional `topic.explanation` (after Explain Further); **decision countdown** (`decision_countdown`, 15 s); Explain Further button (loading flag `:explain`) |
| Speak | Recording widget · audio-level bar (`audio_level` 0–100, `audio_muted`) · speaking timer (`speak_countdown`, 60 s) · Stop Recording |
| Feedback | Overall score gauge + sub-scores + strengths/improvements + summary + detailed feedback tabs + transcript |

**Persisted record:** `jam_session.id`, `topic_title`, `topic_explanation`, `actual_speech_time_used`, `evaluation_data.{speech_duration_seconds, final_score, clarity_score, confidence_score, structure_score, relevance_score, strengths[], improvements[], overall_summary, transcript, detailed_feedback.{clarity, structure, relevance, impact}}`.

**Derived assigns shown:** `feedback.overall_score`, `feedback.speaking_duration` ("MM:SSs"), `feedback.scores.{clarity, fluency, structure, relevance}`, `feedback.strengths/improvements/summary/transcript/detailed_feedback`.

**Error states:** No resume → "Please complete your profile first" · Topic generation failed → retry · Recording failed → retry · No audio input → warning.

---

### 2.10 AI Interview Session

**Purpose:** 5-question conversational interview based on the student's resume.
**Route:** `/student/:tenant/interview/session`

**Phases:** `current_step` ∈ `{:initialize, :interview, :results}`; `interview_phase` ∈ `{:welcome, :question, :results}`.

| Phase | Content |
|---|---|
| Initialize | `resume_info.filename`, `resume_info.size`, Start Interview button (validates `ats_data.resume_url`) |
| Welcome | `greeting_text` from the AI |
| Question | `current_question`, "Question {current_question_number} of {total_questions}" (= 5), Record / Stop, audio-level bar, `current_transcript` preview, Submit Answer |
| Results | `overall_score` gauge, `final_report` paragraph, `strengths[]`, `improvements[]`, expandable Q&A list from `questions_data.questions[]` (text, transcript, AI evaluation) |

**Persisted record:** `interview_session.{id, student_id, overall_score, final_report, strengths[], improvements[], questions_data}`.

**Async signals:** `loading` ∈ `{"indexing", "question", "evaluating"}`.

**Error states:** No resume → "No resume found. Please upload a resume first." · Resume still analyzing → "Your resume is still being analysed…" · Session init failed → retry.

---

### 2.11 Psychometric (Big Five Adaptive)

**Purpose:** Adaptive 30-question Big Five test.
**Route:** `/student/:tenant/assessment/psychometric`

**Phase machine:** `phase` ∈ `{:loading, :instructions, :test, :thinking, :processing, :report}`.

**Per-question fields:** `current_question.{question, trait, keyed: "forward"|"reverse", question_number, total_questions (30), is_followup, followup_number}`.

**Likert options** (fixed list of 5 button labels): Strongly Disagree, Disagree, Neutral, Agree, Strongly Agree.

**On report:** `assessment.factor_scores.{openness, conscientiousness, extraversion, agreeableness, neuroticism}` (each 0–100) + `assessment.factor_reports` (per-trait description/insights, often a JSON-stringified map).

**Engine state (persisted in `assessment.metadata.engine_state`):** `current_q`, `current_trait`, `total_asked`, `consecutive_followup_count`.

**Actions:** Start Assessment · Select Likert (per question) · Retake Assessment (resets to `:instructions`).

---

### 2.12 Behavioral (4 scenarios)

**Purpose:** 4 AI-led scenario role-plays scored on 5 competencies.
**Route:** `/student/:tenant/assessment/behavioral`

**Phase machine:** `phase` ∈ `{:loading, :scenario_select, :conversation, :completed}`.

**Scenario selection:** `scenario_options[]` = `{id, title, description}`; selecting one becomes `chosen_scenario`.

**Conversation:** `messages[]` = `{role: "ai"|"student", text, timestamp}`; current AI prompt in `active_question`; `scenarios_completed` (0–4) progress.

**Completion report:** `assessment.raw_response_json.report.ratings[trait] = { score, description }` for each of the 5 traits used in the behavioral PDF (Work Ethics, Teamwork, Adaptability, Leadership, Communication).

**Error states:** Session error → retry · Previous completed → cached report + Retake.

---

### 2.13 Shared Profile (public)

**Purpose:** Public, read-only profile viewable via a signed token.
**Route:** `/profile/shared/:token`

**Layout:** Minimal header (Vyaasa logo, "Verified Student Profile", `tenant_name`) · Profile card · About · Vyaasa Score card · Verified Skills.

**Profile card:** `initials` (computed), `name`, verification badge *(if `student.status == "verified"`)*, `preferred_role`, `location`/`city`, `total_experience`, `degree` / `specialization`, `cgpa`.

**About card:** `summary_text` from `professional_summary.summary` *(omitted if absent)*.

**Vyaasa Score card:** Gauge of `vyaasa_data.vyaasa_score`; below, mini rows for Resume / MCQ / Behavioral / JAM / Interview — each row shows score and percentile from `rankings.{ats, mcq, behavioral, jam, interview}` (each `{score, rank, percentile}`).

**Skills card:** `ats_data.skills.technical_skills`, `ats_data.skills.non_technical_skills` — rendered with checkmark icons (no interactivity).

**Empty / error states:** Invalid token → "Invalid Link" · Student not found → "Profile Not Found" · Other error → generic error page.

---

## 3. Tenant-admin screens

### 3.1 Tenant Admin Dashboard (Placement Analytics)

**Purpose:** Primary admin view; richest data screen in the app.
**Route:** `/user/:tenant/dashboard`
**Tabs:** `admin_tab` ∈ `{"overview", "leaderboard", "departments", "students"}`.

**Global header:** "Placement Analytics Dashboard" + Refresh + **Add Student** button.

#### Overview tab

**Alert cards (3)** — each card has title, subtitle, count:
- Low Performers ("Score < 40") — `alerts.low_performers.count`
- Incomplete Profiles ("Pending completion") — `alerts.incomplete_profiles.count`
- Integrity Flags ("Needs review") — `alerts.integrity_flags.count`

**Overview metrics (3)**
- Total Students — `overview_stats.total_all_students`, subtitle "{verified} verified | {unverified} unverified"
- Profile Completion — `overview_stats.profile_completed` of `{total}`
- Highest Vyaasa Score — `overview_stats.highest_vyaasa_score`, "{count} completed all 5"

**Assessment Completion grid (6 progress bars)** — for each of `:ats, :mcq, :behavioral, :jam, :interview, :psychometric`, render `overview_stats.assessments[key] = {completed, total}` as a labeled progress bar.

**Students by Specialization** — top 8 from `department_stats`, each: `department`, `student_count`.

#### Leaderboard tab

**Filters:** `leaderboard_department`, `leaderboard_specialization` (filtered by department), `leaderboard_year`.

**Main leaderboard table** — same columns as the **Leaderboard PDF (1.6)** but on-screen with sortable headers. Per row: rank (gold/silver/bronze pill for top 3), name + registration_id, degree, specialization, ats_score, mcq_percentage, behavioral_score, jam_score, interview_score, psychometric_score, vyaasa_score (color-coded by range).

**Top 5 per Assessment (6 cards)** — for each of ATS / MCQ / Behavioral / JAM / Interview / Psychometric: rank, `name`, `specialization`, `score`. Source: `assessment_toppers` map.

#### Specializations tab

**Specialization performance table** — same shape as the **Specialization PDF (1.7)**, each row clickable.

**Drill-down modal** *(when a specialization is clicked)*: `selected_spec`, `selected_spec_students[]` — table per student: name + email, registration_id, `mcq_percentage`, `ats_score`, `vyaasa_score`.

#### Students tab

**Search & filters:** debounced search (300 ms) on name/email/registration_id; status filter (Unverified / Verified / All); year dropdown from `student_year_options`.

**Students table (paginated, 25/page)** — see column list below; supports column sort (`sort_by`, `sort_dir`).

| Column | Source | Notes |
|---|---|---|
| Name | `first_name` + `last_name` + `registration_id` | Avatar initial; status badge if verified; integrity-flag count chip if any |
| Role | `preferred_role` | inline dropdown from `job_roles` |
| Resume | `ats_score` | badge, "-" if nil |
| MCQ | `mcq_percentage` | percentage badge |
| Behavioral | `behavioral_score` | badge |
| JAM | `jam_score` | badge |
| Interview | `interview_score` | badge (rounded) |
| Psychometric | `psychometric_score` | badge (rounded) |
| Vyaasa | `vyaasa_score` | colored number + bar; "No data" if nil |
| CV | `resume_filename` | "View" link opens iframe modal |
| Actions | Verify (if unverified) + menu (Reset Test if verified) | |

**Resume Modal** — full-screen modal with iframe of `resume_url` and Download fallback.

**Add Student bar** — "Add Student" button → `/user/:tenant/dashboard/addstudent`; "Upload CSV file" → CSV modal (5 MB max, columns documented in `priv/static/templates/student_bulk_template.csv`).

#### Live updates

The dashboard subscribes to `DashboardEvents.subscribe_tenant(tenant_schema)` and debounces reloads (`schedule_dashboard_reload`) so bulk writes don't spam the page.

---

### 3.2 Students list (`/dashboard/students`)

**Purpose:** Primary tenant-admin view of all students with AI readiness metrics, smart tags, stat summary cards, and two right-side slide-over drawers (Create + Detail).
**Route:** `/user/:tenant/dashboard/students`
**LiveView:** `VyaasaCampusWeb.TenantUser.StudentsLive`

**Stat cards (5, computed over the entire unfiltered student set)**

| Card | Condition |
|---|---|
| Total Students | `length(all)` |
| Placement Ready | `vyaasa_score >= 65` |
| High Potential | `vyaasa_score >= 75` |
| Needs Mentoring | `vyaasa_score > 0 AND < 45` |
| Incomplete Profiles | `status in ["pending", "profile_incomplete"]` |

**Assigns:** `students` (current page slice), `total_students`, `filtered_count`, `stats` (map of 5 card values), `search_term`, `status_filter`, `department_filter`, `year_filter`, `dept_options[]`, `year_options[]`, `current_page`, `per_page` (= 10), `show_sidebar` (`:none | :create | :detail`), `sidebar_student`, `create_form`, `create_loading`, `create_errors[]`, `degree_options[]`, `specialization_options[]`.

**Filters (toolbar):** Search (debounced 300 ms) · Status dropdown (`all / verified / unverified`) · Department dropdown (auto-populated from data) · Year dropdown (auto-populated) · Export button (coming soon).

**Table columns:** Student (avatar initials + name + verified badge + reg ID) · Department + year · CGPA (`cgpa`, Decimal, 1 d.p.) · Readiness badge · Tags (up to 3) · Status badge · Actions (Verify button for `pending`/`unverified`).

**Readiness bands** (derived from `vyaasa_score`)

| Band key | Score range | Label | Badge colour |
|---|---|---|---|
| `elite` | ≥ 85 | Elite Talent | indigo |
| `high` | 75–84 | High Potential | blue |
| `ready` | 65–74 | Placement Ready | emerald |
| `emerging` | 50–64 | Emerging Talent | amber |
| `mentoring` | 35–49 | Needs Mentoring | orange |
| `developing` | 1–34 | Developing | gray |
| `unassessed` | 0 | Not Assessed | gray |

**Smart tags** (up to 3 per student, derived from module scores)

| Tag | Condition |
|---|---|
| Top Performer | `vyaasa >= 85` |
| High Potential | `80 ≤ vyaasa < 85` |
| Leadership Candidate | `interview_score >= 75` |
| Placement Ready | `65 ≤ vyaasa < 75` |
| Internship Ready | `50 ≤ vyaasa < 65` |
| Communication Risk | `jam_score > 0 AND < 40` |
| Needs Mentoring | `vyaasa > 0 AND < 35` |

**Data source:** `DashboardLive.load_all_students_with_scores(tenant_schema, :all)` — merges `ats_score`, `mcq_percentage`, `behavioral_score`, `psychometric_score`, `jam_score`, `interview_score`, `vyaasa_score` onto each student struct.

**Pagination:** 10 per page, Previous / page-number / Next, `?page=N` query param.

---

### 3.2a Create Student drawer (right slide-over)

**Trigger:** "Add Student" button → `open_create_sidebar` event.  
**State:** `show_sidebar == :create`.

**Form fields**

*Personal:* `first_name` *, `last_name` *, `email` *, `phone`, `registration_id`.  
*Academic:* `degree` (select, from `Academics.get_tenant_degree_options/1`), `specialization` (select), `cgpa`, `year_of_passing`.

**Events:** `validate_create_student` (on change, runs changeset validation) · `save_create_student` (on submit, calls `Students.create_student/3` then closes drawer).

**On success:** drawer closes, table reloads, flash "Student created. Profile-completion invite sent."

---

### 3.2b Student Detail drawer (right slide-over)

**Trigger:** Clicking any table row → `open_student_detail` event with `student_id`.  
**State:** `show_sidebar == :detail`, `sidebar_student` holds the selected student map.

**Content**

- Avatar (colour-coded initials, deterministic by student ID hash) + full name + verified badge + email + status badge
- Info grid (2 col): Registration · Phone · Department · Specialization · CGPA · Year of Passing
- AI Readiness: band badge + numeric score / 100 + tags
- Module Scores: 6 horizontal bar charts (Resume AI8, MCQ, Behavioural, Psychometric, JAM, Interview) — shows `—` when score is 0/nil
- Actions: Verify Student button (only shown when `status in ["unverified", "pending"]`)

**After verify:** sidebar stays open, `sidebar_student` refreshes in-place from the reloaded page.

---

### 3.4 Programs (Degrees & Specializations selection)

**Purpose:** Tenant chooses which catalog degrees + specializations they actually offer.
**Route:** `/user/:tenant/dashboard/programs`

**Assigns:** `all_degrees[]` (with nested `specializations[]`), `selected_degree_ids` (MapSet), `selected_spec_ids` (MapSet).

**UI:** For each degree, a row with: checkbox (degree-level toggle), `degree.name`, `degree.code`, "{n} specializations" count. When checked, expand to pill row of `specializations`; each pill toggles individually.

---

## 4. Platform-admin screens

### 4.1 Platform Admin Dashboard (Tenants)

**Route:** `/admin/dashboard`

**Stats cards:** Total Tenants, Active, Inactive/Suspended (counts derived from `tenants`).

**Tenants table (paginated, 10/page):** `full_name`, `alias`, `affiliation_type` (university/college/school/institute/corporate), `email`, `status` (active/inactive/suspended badge), `inserted_at`, Actions (Activate/Deactivate).

**Create Tenant modal — form fields:** `full_name *`, `short_name *`, `alias *`, `affiliation_type *`, `email *`, `phone`, `website_url`, `admin_first_name *`, `admin_last_name *`, `admin_email *`, `admin_password` (default `"admin123"`).

---

### 4.2 Industries & Job Roles

**Route:** `/admin/jobs`

**Two-pane layout.**

**Industries pane** — table columns: `name`, `role_count`, `is_active` (toggle), Edit, Delete. Form fields when adding/editing: `name *`, `code`, `description`.

**Roles pane** *(enabled when industry selected)* — columns: `title`, `code`, `description`, `skills` (tag list), `experience_level` (entry/mid/senior/lead), `is_active`. Form fields: `title *`, `code`, `description`, `skills_text` (comma-separated → array), `experience_level`.

---

### 4.3 Degrees & Specializations Catalog

**Route:** `/admin/degrees`

**Degrees pane columns:** `name`, `code`, "{n} specs".
**Specializations pane** *(when degree selected)* columns: `name`, `code`.
**Form fields (both):** `name *`, `code *`.

---

### 4.4 Question Bank

**Route:** `/admin/question_bank`

**Top stats:** Total Questions, Subjects, Topics (from `@total_questions`, `@total_subjects`, `@total_topics`).

**Left pane (upload):** Degree picker → Specialization picker → ZIP/RAR upload (≤ 100 MB). Expected per-file JSON:
```json
[
  {"question": "…", "options": ["…","…","…","…"], "correct_answer": "…",
   "difficulty": "easy|medium|hard", "topic": "…"}
]
```

**Right pane (browser):**
- Subjects table — `name`, `topic_count`, `count` (badge), Delete
- Topics table *(when subject selected)* — `name`, `count`, `easy`, `medium`, `hard`

**Question bank row schema:** `id`, `question`, `answer` (single letter a/b/c/d/...), `options` (map keyed by letter), `difficulty_level`, `type`, `topic_id`.

---

### 4.5 Assessment Configuration

**Route:** `/admin/assessments_config`

**Top:** Pill row of tenants (green dot if a config is saved for that tenant).

**Config form (3-col grid)** — fields and ranges:
| Field | Range | Notes |
|---|---|---|
| `total_questions` | 1–200 | |
| `duration_minutes` | 1–300 | |
| `negative_marking` | 0–1, step 0.05 | decimal |
| `aptitude_percentage` | 0–100 | |
| `technical_percentage` | (readonly) | `100 - aptitude_percentage` |
| `easy_percentage` | 0–100 | |
| `medium_percentage` | 0–100 | |
| `hard_percentage` | (readonly) | `100 - easy - medium` |
| `passing_percentage` | 0–100 | |

**Summary line:** "60 questions (24 aptitude + 36 technical) in 90 min, pass at 50%, negative marking 0.25/wrong".

**Existing assessments table:** `title`, `assessment_type`, `settings["total_questions"]`, `duration_minutes`, `passing_marks / total_marks`, `status` (draft/published/active/completed/archived).

---

## 5. Auth & public screens

### 5.1 Public Homepage (institution picker)

**Route:** `/`

**Fields:** `search_query` (3-char min, debounced); results `tenants[]` (limit 10) — each shows `full_name`, `short_name`, `alias`, optional `logo_url`.

**Actions:** Type to search → click a result → `/auth/tenant/:alias/login`.

---

### 5.2 Tenant Login

**Route:** `/auth/tenant/:tenant/login`
**Form:** `email *`, `password *`. Detects whether identity is a tenant user or student behind the scenes.
**Assigns:** `tenant_alias`, `tenant`, `tenant_name`, `error_message`, `loading?`, `tenant_not_found?`.
**Edge:** Invalid tenant → blocks form with error card.

### 5.3 Forgot / Reset Password

**Routes:** `/auth/tenant/:tenant/forgot-password`, `/auth/tenant/:tenant/reset-password/:token`
**Forgot form:** `email`. On success → confirmation card with "Back to Login".
**Reset form:** new password + confirmation (token validated server-side).

### 5.4 Platform Admin Login

**Route:** `/admin/login`
**Form:** `email *`, `password *`. Authenticates via `Auth.authenticate_admin`, sets Guardian token, redirects to `/admin/dashboard`.

---

## 6. Reference data structures

These are the recurring shapes the UI consumes — useful when building wireframes that must reserve space for every field.

### Student
```
id                       UUID
first_name               string
last_name                string
email                    string  (unique per tenant)
registration_id          string?
phone                    string?
degree                   string?
specialization           string?
year_of_passing          integer?
cgpa                     decimal?
department               string?
status                   "pending" | "unverified" | "verified" | "active" | "inactive"
tenant_id                UUID
created_by_id, _type     UUID, string
profile_approved_at      datetime?
temp_password            string?     (set on approval, then cleared)
temp_password_expires_at datetime?
inserted_at, updated_at  datetime
```

### Per-student score bundle (used everywhere scores are listed)
```
ats_score            decimal (0–100) ?
mcq_percentage       float   (0–100) ?
behavioral_score     integer (0–100) ?
jam_score            integer (0–100) ?
interview_score      float   (0–100) ?
psychometric_score   float   (0–100) ?
vyaasa_score         number  (0–100) ?   composite, derived
```

### Tenant
```
id, full_name, short_name, alias (unique), affiliation_type,
email, phone?, website_url?, status, schema_name, created_by,
inserted_at, updated_at
```

### Assessment / AssessmentAttempt
```
Assessment:
  id, title, assessment_type, duration_minutes, total_marks,
  passing_marks, settings (JSON; e.g. settings["questions"]),
  status ("draft"|"published"|"active"|"completed"|"archived")

AssessmentAttempt:
  id, assessment_id, student_id,
  status ("started"|"submitted"),
  started_at, submitted_at?,
  answers: %{question_id => option_key},
  score?, percentage?,
  evaluation_data: { correct, wrong, unanswered, total_questions, negative_marks },
  metadata: { current_question_index, tab_switch_count, answer_timestamps,
              answer_change_counts }
```

### JamSession (relevant subset)
```
id, student_id, topic_title, topic_explanation, actual_speech_time_used,
evaluation_data: {
  speech_duration_seconds, final_score,
  clarity_score, confidence_score, structure_score, relevance_score, impact_score?,
  strengths[], improvements[], overall_summary, transcript,
  detailed_feedback: { clarity, structure, relevance, impact }
}
```

### InterviewSession
```
id, student_id, overall_score?, final_report?,
strengths[]?, improvements[]?,
questions_data: { questions: [{ question, transcript?, score?, evaluation?, reasoning?, feedback? }] }
```

### StudentPsychometricAssessment
```
id, session_id, status, attempt_number,
factor_scores: { openness, conscientiousness, extraversion, agreeableness, neuroticism },  -- 0–100
factor_reports: [{ factor, score, interpretation?, strengths[]?, risks[]?, suggestions[]? }],
strengths[], development_areas[], suggestions[], overall_summary?,
metadata.engine_state: { current_q, current_trait, total_asked, consecutive_followup_count }
```

### StudentBehavioralAssessment
```
id, session_id, status,
overall_score, summary?,
scores: { work_ethics, teamwork, adaptability, leadership, communication },  -- 0–100
reasoning: { work_ethics: "…", teamwork: "…", … },
strengths[], areas_for_development[],
candidate_profile: { role?, desired_role?, education? },
completed_scenarios[]: { scenario_number, question, score?, response? },
raw_response_json.report.ratings: { trait => { score, description } }
```

### Rankings (used on dashboard + shared profile)
```
rankings = {
  ats:        { score?, rank?, percentile? },
  mcq:        { percentage?, rank?, percentile? },
  behavioral: { score?, rank?, percentile? },
  jam:        { score?, rank?, percentile? },
  interview:  { score?, rank?, percentile? }
}
vyaasa_data = { vyaasa_score }      -- weighted composite
```

### Department/Specialization stats (admin views & reports)
```
department_stats[] = {
  department,           -- specialization name
  student_count,
  scored_count,
  highest_vyaasa_score?,
  topper?: { name, score }
}
```

---

*Last updated: 2026-05-19. Field names match `lib/vyaasa_campus/...` and `lib/vyaasa_campus_web/...` as of this date. When in doubt, grep the field name in the codebase — every name in this document is verbatim from the templates or LiveView assigns.*
