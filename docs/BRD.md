# Vyaasa Campus — Business Requirements Document (BRD)

| Field | Value |
|---|---|
| Document version | 0.1 (draft) |
| Date | 2026-05-07 |
| Owner | Product / Founding team |
| Status | Draft for review |
| Scope | Vyaasa Campus v1 — multi-tenant placement-readiness platform |

> **About this draft.** Sections derived from the codebase are marked **\[derived]**. Sections containing reasonable starter assumptions that the business team must confirm or replace are marked **\[assumed — confirm]**. The intent is to give the team a complete BRD shell where every business-side claim is either grounded in the code or explicitly flagged for sign-off.

---

## 1. Executive summary

Vyaasa Campus is a **multi-tenant SaaS placement-readiness platform** for Indian higher-education institutions. Each onboarded institution (a *tenant*) operates an isolated workspace where its placement cell can register students and run them through a structured **six-assessment battery** that produces an objective, AI-graded readiness profile per student and aggregate analytics for the institution.

The platform replaces a mix of manual placement-prep workflows, ad-hoc mock-interview drives, and standalone aptitude tools with a single integrated workflow:

1. Institution onboarded → 2. Students added → 3. Resume parsed and ATS-scored → 4. Admin verifies → 5. Student completes 5 remaining assessments (MCQ, Psychometric, Behavioral, JAM, Mock Interview) → 6. Reports generated and shared.

**Differentiators** — \[assumed — confirm]
- Resume-grounded **AI mock interview** that asks questions strictly anchored to the candidate's actual projects and work experience (no generic "tell me about yourself").
- Adaptive **Big Five psychometric** assessment generated per-question rather than a fixed bank.
- **JAM (Just A Minute)** speech assessment with native AI transcription and per-dimension scoring.
- **Schema-per-tenant** isolation in Postgres — each institution's data lives in its own schema, not just behind a `tenant_id` filter.
- Built on the **BEAM/Elixir** stack to support 500+ concurrent assessment-takers per node with low memory overhead.

---

## 2. Vision and product positioning

### 2.1 Vision \[assumed — confirm]

To make placement-readiness measurable, comparable, and AI-graded across Indian higher education — so that institutions can demonstrate outcomes, students can understand their gaps before interviewing, and recruiters can eventually trust a portable readiness signal.

### 2.2 Product positioning statement \[assumed — confirm]

> For **placement cells, T&P officers, and deans of Indian colleges and universities** who need an **objective, scalable way to measure and improve student placement readiness**, Vyaasa Campus is a **multi-tenant SaaS platform** that combines **AI resume scoring, MCQ aptitude, Big Five psychometrics, behavioral judgment, JAM speech, and resume-grounded mock interviews** into a **single, white-labelled workflow per institution**.
>
> Unlike standalone tools (Naukri Campus, in-house spreadsheet trackers, generic aptitude vendors), Vyaasa Campus delivers **the full readiness battery in one platform**, with **per-tenant schema isolation** and **AI scoring across written, spoken, and behavioral channels**.

### 2.3 Buyer vs. user

| Stakeholder | Role on platform | Primary value |
|---|---|---|
| **Buyer** — Placement Head / T&P Officer / Dean | Tenant Admin (College Admin) | Aggregate dashboards, batch leaderboards, audit trail, downloadable PDF reports per student. |
| **End user** — Final-year / pre-placement student | Student | Honest readiness baseline, gap-area feedback, retakes for improvement, downloadable reports for self-portfolio. |
| **Operator** — Vyaasa internal team | Platform Admin | Tenant onboarding, plan limits, master question bank, support. |

---

## 3. Problem statement

### 3.1 Today's placement-prep landscape \[assumed — confirm]

Placement cells at Indian colleges typically rely on:

- **Spreadsheets** for tracking student profiles, resume versions, and mock-interview scores.
- **Third-party aptitude vendors** for one-off MCQ tests, with no integration into the rest of the prep stack.
- **Manual mock interviews** by faculty / alumni, run irregularly and scored inconsistently.
- **No psychometric or behavioral signal**, despite recruiters increasingly screening for these.
- **Fragmented reporting** — students leave with no consolidated readiness report; the institution has no auditable record beyond marks.

The result is a workflow that is labour-intensive, inconsistent across batches, hard to defend to NAAC/NIRF/recruiter audits, and offers no improvement loop for the student.

### 3.2 What Vyaasa Campus changes

- **One workflow, six assessments.** A student's readiness is captured along six channels — resume quality, aptitude, personality, behavioral judgment, spoken fluency, and structured interview performance — within one platform.
- **AI-graded, not faculty-graded.** Resume scoring, behavioral evaluation, JAM evaluation, and interview evaluation all run on Groq LLMs and native embeddings — eliminating inter-rater variance.
- **Per-tenant data isolation.** Each institution's students, resumes, and reports live in a dedicated Postgres schema (Triplex). No risk of cross-institution leakage even at the query level.
- **Auditable history.** Every resume re-analysis is preserved with an `attempt_number`, so improvement over a semester is traceable per student.
- **Aggregate analytics.** Tenant admins see batch leaderboards, specialization-level performance, and per-student readiness — exportable as PDF.

---

## 4. Business goals and success metrics \[assumed — confirm]

The numbers below are placeholders to align the team — replace with the latest internal targets before sign-off.

### 4.1 Strategic goals (12-month horizon)

| Goal | Target (placeholder) |
|---|---|
| Tenants onboarded | 25 institutions by end of FY26 |
| Active students on the platform | 25,000 (≈1,000 avg per tenant) |
| Assessment completion rate (per registered student) | ≥ 70% complete all 6 |
| Per-tenant retention (year-over-year) | ≥ 80% |
| Net Promoter Score from placement heads | ≥ 40 |

### 4.2 Operational KPIs

| Area | KPI | Target (placeholder) |
|---|---|---|
| Onboarding | Time-to-first-student-assessed after tenant creation | < 48 hours |
| Reliability | Platform uptime (excl. planned maintenance) | ≥ 99.5% / month |
| AI throughput | Concurrent students mid-assessment | ≥ 500 (paid Groq tier — *derived from `docs/concurrency-scaling-500-users.md`*) |
| Email delivery | Profile-completion email open-to-click | ≥ 50% |
| Cost-to-serve | AI cost per fully-assessed student | < ₹X (set after pilot data) |
| Support | First-response time on tenant-admin tickets | < 4 business hours |

### 4.3 Outcome KPIs (institution-facing) \[assumed — confirm]

| Outcome | Why it matters | Measurement |
|---|---|---|
| % of students with all 6 assessments complete before placement season | Placement head's main "is the batch ready?" signal | Dashboard widget |
| Average ATS score lift between attempt 1 and attempt N | Justifies the platform's "improvement loop" pitch | Per-tenant report |
| % of students with overall readiness score ≥ threshold | Readiness benchmark vs. recruiter expectations | Threshold configurable per tenant |

---

## 5. Target market \[assumed — confirm]

### 5.1 Primary segment (v1)

- **Indian higher-education institutions** running undergraduate / postgraduate engineering, management, or science programs with active campus placement cells.
- Tier-2 and tier-3 colleges and universities — where the placement cell has budget but lacks a tooling stack.
- Geographic focus: India only in v1; data residency in India.

### 5.2 Secondary segments (later versions)

- **Tier-1 universities** with central T&P offices managing multiple colleges.
- **Corporate L&D / graduate-hiring teams** who could license the assessment battery for internal mobility or bulk evaluation.
- **Coaching/training providers** running placement-prep bootcamps.

### 5.3 Persona snapshots \[assumed — confirm]

- **"Priya, T&P Officer, autonomous engineering college (Tier-2)"** — manages ~600 final-year students, runs ~30 mock-interview drives per season, today uses Excel + Google Forms. Buys based on: time saved + a defensible readiness number to show to industry partners.
- **"Rahul, final-year B.Tech student"** — anxious about his first technical interview, uses YouTube/LeetCode. Wants: honest signal on where he stands, downloadable report to share with mentors, multiple retakes.
- **"Dr. Mehta, Dean of Placements"** — answers to NAAC/NIRF audits, presents placement readiness to the board. Buys based on: aggregate dashboards, exportable PDFs, NAAC-friendly evidence.

---

## 6. Competitive landscape \[assumed — confirm]

| Category | Examples | How Vyaasa Campus differs |
|---|---|---|
| Job boards with campus modules | Naukri Campus, Internshala | They focus on matching to recruiters; we focus on **readiness measurement** before matching. |
| Aptitude-only vendors | AMCAT, eLitmus, CoCubes | One channel (MCQ) only; no resume parsing, no AI interview, no psychometrics integrated. |
| In-house placement portals | College-built spreadsheets / web apps | No AI grading, no psychometric/behavioral signal, no audit trail. |
| Generic interview-prep apps | Pramp, Interviewing.io, InterviewBit | Aimed at individual learners, not institutions; no per-tenant workspace, no admin dashboards. |
| Edtech with placement bolt-ons | Various | Placement is a feature, not the product. |

**Defensible moat (hypothesis)** — multi-channel readiness signal + per-tenant isolation + a question/scenario library that compounds with usage.

---

## 7. Stakeholders

### 7.1 External

- **Tenant decision makers** — Placement heads, T&P officers, deans.
- **Tenant admin users** — Placement-cell staff, faculty coordinators.
- **End-user students** — Final-year / pre-placement cohorts.
- **Recruiters** — Out of v1 scope but a potential v3 audience for portable readiness scores.

### 7.2 Internal

- **Founders / Product** — Set roadmap, pricing, positioning.
- **Engineering** — Phoenix/Elixir backend, LiveView frontend, AI engines, ops.
- **Sales / institutional partnerships** — Tenant acquisition, RFP responses.
- **Customer success** — Tenant onboarding, training, support.
- **Compliance / legal** — DPDP Act compliance, contracts, data-residency commitments.

---

## 8. Scope

### 8.1 In scope (v1) — *derived from current implementation*

- Platform Admin web console: create / manage tenants, master question bank, degrees and specializations, industries and job roles, Oban job monitoring.
- Tenant Admin web console: add students (single + bulk), verify profiles, view leaderboards, download per-batch and per-specialization reports, manage programs (training cohorts), manage tenant-level users and roles.
- Student web app: profile completion via emailed token, six assessments, dashboard, downloadable per-assessment PDF reports.
- Resume parsing and ATS scoring (native Elixir + Bumblebee embeddings + Groq LLM).
- AI assessments — MCQ (deterministic), Psychometric (adaptive Big Five), Behavioral (3 scenarios), JAM (60-second speech), Mock Interview (resume-grounded).
- Email delivery (Swoosh + SMTP) for: tenant creation, profile completion, profile verified, profile edit-request, password reset, assessment-report delivery.
- PDF generation via ChromicPDF (headless Chrome) for all assessment reports + leaderboard + specialization summaries.
- Oban-backed background jobs for resume processing, report generation, file cleanup.
- JWT-based authentication (Guardian) with role-based scopes (platform admin / tenant user / student).
- Schema-per-tenant data isolation (Triplex on Postgres).
- File storage on local filesystem (S3 wired but not currently used — \[assumed — confirm whether S3 ships in v1]).

### 8.2 Out of scope (v1) — \[assumed — confirm]

- **Recruiter portal** (no recruiter login, no job posting, no candidate matching).
- **Mobile apps** (iOS/Android) — students access via responsive web.
- **Single sign-on** (SAML, Google Workspace, Microsoft Entra). Today's auth is email + password.
- **Payment / subscription billing** in-app — handled offline by sales.
- **Public REST API for third parties** — internal API exists but is not a published surface for integrations.
- **Recruiter-facing readiness scores or candidate marketplace.**
- **Multi-language UI** — English only.
- **Live human-graded interviews** — all interviewing is AI-driven.
- **Calendaring / interview scheduling** with recruiters.

### 8.3 Future scope (v2 / v3 candidates) \[assumed — confirm]

- Recruiter-facing read-only dashboards with consented student profiles.
- SSO via Google Workspace + Microsoft Entra (institutional accounts).
- S3 storage with signed-URL downloads (replaces local filesystem).
- Mobile responsive native wrapper or PWA.
- Tenant-configurable assessment battery (toggle which of the 6 are required, add custom MCQ subjects).
- Per-tenant white-labelling (custom domain, logo on emails and PDFs).
- Live human-led interviews with AI-assisted scoring.
- Multi-tenant analytics (cross-institution benchmarks for the platform admin).
- Public/portable readiness profile (student-controlled share link, currently exists at `/profile/shared/:token` — extend with revocation, expiry, audit).

---

## 9. Business rules and policies

### 9.1 Tenancy

- One institution = one tenant = one Postgres schema. Hard isolation, not soft (no shared `tenant_id` table).
- Tenant alias (e.g. `GBC`, `BITE`, `KLU`) is globally unique and forms part of every tenant URL.
- Tenant lifecycle states: `active`, `inactive`, `suspended`.
- Suspending a tenant blocks all logins for that tenant's users and students; data is preserved.

### 9.2 Student lifecycle — *derived from `lib/vyaasa_campus/schema/students/student.ex`*

```
pending  →  profile_incomplete  →  unverified  →  verified  →  active
                                            ↓
                                       (admin requests edits)
                                            ↓
                                    profile_incomplete (loops back)
```

- Students cannot take assessments until the admin verifies their profile.
- Re-uploading a resume creates a new ATS phase (`attempt_number` increments) — historical scores are preserved.
- A student's password is set in two phases: a temporary password emailed on verification, then forced-change at first login.

### 9.3 Assessment policies — \[assumed — confirm where not derived]

- **Resume / ATS** — unlimited retakes; each retake preserves history.
- **Psychometric** — student-controlled retakes (current behavior); each retake supersedes the previous result for ranking purposes but historical results are preserved via `attempt_number`.
- **MCQ** — admin-controlled retakes via the Assessment configuration.
- **Behavioral, JAM, Mock Interview** — admin-controlled retakes (student must request via tenant admin). \[confirm with product]
- **Time limits** — MCQ time-limit set by admin per assessment; Psychometric and Behavioral are self-paced; JAM has fixed 60s decision / 15s prep / 60s speak phases; Mock Interview defaults to 5 questions / 10 minutes.

### 9.4 Data retention \[assumed — confirm]

- Resume files: default retention 90 days (configurable per ATS phase via `retention_policy_days`).
- Assessment session recordings (JAM audio): same 90-day default.
- Student records and assessment results: retained for the life of the tenant subscription.
- Tenant deletion: \[policy TBD — confirm soft-delete vs hard-delete and the grace period].

### 9.5 Pricing model placeholder \[assumed — confirm]

Common patterns to choose between:

- **Per-tenant annual licence** with a student-count band (e.g. up to 500 / up to 1,500 / up to 5,000).
- **Per-active-student** charged annually, billed in advance per cohort.
- **Per-assessment-attempt** for elastic pricing, useful for pilots.

The platform stores enough data (`students` table per tenant, `attempt_number` per assessment) to support any of these — the choice is commercial, not technical.

---

## 10. Compliance, security and trust \[assumed — confirm]

### 10.1 Regulatory context (India)

- **Digital Personal Data Protection Act, 2023 (DPDP)** — students are data principals; the institution is the data fiduciary; Vyaasa Campus is the data processor. Contracts must reflect this.
- **Data residency** — institutions increasingly require Indian-region hosting. Deployment target should be confirmed (Indian region cloud or on-prem option).
- **NAAC / NIRF audit support** — placement reports may be cited in assessment cycles; audit trails (who verified which student, who accessed which resume) should be exportable.
- **Accessibility** — \[confirm whether v1 commits to WCAG 2.1 AA].

### 10.2 Security commitments — *partially derived*

- **Authentication** — bcrypt-hashed passwords, JWT (Guardian) with 30-minute access token TTL, refresh tokens hashed at rest.
- **Tenant isolation** — Postgres schema-per-tenant; every query carries an explicit `prefix:`.
- **Transport** — HTTPS in production (configured via runtime config).
- **CSRF** — Plug.CSRFProtection on all browser routes.
- **File uploads** — validated by extension and size (5 MB student documents, 100 MB admin question-bank uploads).
- **Rate limiting** — Groq AI calls are queued and rate-limited; per-IP / per-account login rate limiting is **not yet implemented** — flag for v1.1.
- **Observability** — application logs with request IDs; **no external APM yet** (Sentry/Datadog) — flag for v1.1.

### 10.3 Audit and disclosure \[assumed — confirm]

- Per-student audit trail: who created, who verified, who downloaded the resume.
- Per-tenant export: full data export on request (DPDP "right to data portability").
- Data deletion: per-student and per-tenant deletion requests honoured within policy SLA — \[confirm SLA].

---

## 11. Constraints and dependencies

### 11.1 Technical constraints — *derived*

- **Groq API tier** is the dominant scaling constraint. The free tier supports ~10 concurrent users; paid tiers scale to 500–1000+. Concurrency planning depends on the active commercial tier.
- **ChromicPDF requires headless Chrome** in the deploy environment — affects Docker base image and memory footprint.
- **Bumblebee/Nx native ML stack** runs CPU-resident sentence-transformer embeddings; cold-start can take ~3 minutes (warmed at boot via `EmbeddingServer`).
- **Schema-per-tenant** limits tenant count by Postgres schema scaling — comfortable into the low thousands of tenants per database before consolidation is needed.

### 11.2 External dependencies

- **Groq API** — chat completions (Llama 3.1 8B + Llama 3.3 70B), Whisper transcription, optional Orpheus TTS.
- **SMTP provider** — Gmail / SES / configurable; carries all transactional email.
- **Postgres** — primary datastore; tenant schema isolation depends on it.
- **Headless Chrome** — required by ChromicPDF for all PDF generation.

### 11.3 Organisational constraints \[assumed — confirm]

- Engineering capacity, support headcount, sales motion — all gates to how fast tenants can be onboarded.
- Onboarding is not yet self-serve: a tenant requires a one-time `mix run priv/repo/tenant_seeds.exs` for job profiles. v1.1 should automate this.

---

## 12. Assumptions and risks

### 12.1 Key assumptions

- Indian institutions will pay for a structured readiness platform (validated by pilot).
- Students will accept AI-graded behavioral and interview scoring as fair and useful.
- AI provider (Groq) pricing remains stable enough to model gross margin.
- Email is a sufficient communication channel for student onboarding (no SMS / WhatsApp in v1).

### 12.2 Risks

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| Groq API price spike or rate-limit tightening | Direct hit to margin / capacity | Medium | Maintain rate-limiter abstraction; build adapter for at least one alternative LLM provider before scale. |
| AI-graded reports challenged by students or parents as unfair | Reputational | Medium | Per-question evidence in reports; admin override / regrade workflow for v1.1; transparent rubric in student-facing copy. |
| Bulk email deliverability (Gmail/Outlook spam-bin) | Onboarding bottleneck | Medium | DKIM/SPF/DMARC setup; warm-up plan; per-tenant from-domain consideration. |
| Compliance audit (DPDP) reveals gaps | Regulatory / contractual | Medium | DPIA before scale; documented retention/deletion runbook; processor agreement template. |
| Tenant data leak via unprefixed Repo query | Severe trust breach | Low (current code uses prefixes consistently) | Add CI lint that rejects any `Repo.*` call without `prefix:` in tenant contexts. |
| Headless Chrome stability in containerised deploy | PDF reports fail at scale | Medium | Already mitigated via on-demand pool + flags in `application.ex`; add canary report job and alerting. |
| Local-filesystem storage doesn't survive multi-node | Blocks horizontal scale | Medium | S3 migration path is dependency-ready; commit to S3 before second-node deploy. |

---

## 13. Roadmap horizons \[assumed — confirm]

| Horizon | Theme | Representative items |
|---|---|---|
| **Now (v1)** | Land first 25 tenants, prove the workflow | All six assessments live, ChromicPDF reports, manual tenant onboarding, local storage, no SSO. |
| **Next (v1.1, +3 months)** | Reduce ops load, harden trust | Self-serve tenant onboarding (auto-seed job profiles), S3 storage, login rate limiting, external APM (Sentry), password-policy hardening, DPDP compliance pack (export + deletion runbooks). |
| **Later (v2, +6–9 months)** | Institutional features | SSO, per-tenant white-labelling, configurable assessment battery, recruiter-facing read-only views with consent. |
| **Vision (v3, +12+ months)** | Network effects | Portable readiness profile, recruiter marketplace, cross-tenant benchmarks, mobile apps. |

---

## 14. Glossary

| Term | Meaning |
|---|---|
| **Tenant** | An institution onboarded onto the platform; backed by a dedicated Postgres schema. |
| **Tenant alias** | Short code (e.g. `GBC`) used in URLs and DB schema names. |
| **Platform Admin** | Vyaasa internal operator; manages tenants. |
| **Tenant Admin / College Admin** | Institution-side user; manages students and views reports. |
| **Student** | End user; takes the six assessments. |
| **ATS phase** | One resume-scoring attempt for a student (`student_ats_phases` row). |
| **Assessment battery** | The six assessments: Resume, MCQ, Psychometric, Behavioral, JAM, Mock Interview. |
| **JAM** | "Just A Minute" — 60-second spoken-topic assessment. |
| **Big Five / OCEAN** | Personality model used by the Psychometric assessment. |
| **Job profile** | Per-tenant skill rubric (23 default profiles seeded) used to score resume relevance. |
| **Re-analysis** | A student re-uploading their resume; preserved as a new attempt. |

---

## 15. Open questions for sign-off

The following items are flagged \[assumed — confirm] in the body. Resolving these turns this draft into a baselined v1 BRD.

1. **Vision and positioning copy** (§ 2.1, § 2.2) — final marketing-approved statement.
2. **Buyer persona and pricing model** (§ 2.3, § 9.5) — confirmed sales motion.
3. **Strategic and operational KPI targets** (§ 4) — replace placeholders with internal targets.
4. **Target market scope** (§ 5) — geographic / segment confirmation.
5. **Competitive list and moat** (§ 6) — confirm differentiators.
6. **Out-of-scope list for v1** (§ 8.2) — confirm SSO, mobile, recruiter portal are deferred.
7. **Retake policy per assessment** (§ 9.3) — confirm which retakes are admin-gated.
8. **Data retention policy** (§ 9.4) — confirm 90-day default and post-cancellation handling.
9. **Compliance commitments** (§ 10.1, § 10.3) — DPDP DPA template, accessibility commitment, audit SLAs.
10. **Roadmap horizons** (§ 13) — confirm what ships when.

Once the above are resolved, the BRD can be published as v1.0 and the FRD (companion document) baselined alongside it.
