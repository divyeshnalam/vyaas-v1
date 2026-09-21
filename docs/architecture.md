# Vyaasa Campus — Architecture

How the Admin side (Platform Admin + College Admin) and the Student side fit
together. Both run on the same Phoenix app and share one backend — they're
drawn separately below for readability, not because they're separate systems.

---

## System overview

```mermaid
flowchart TB
    subgraph ADMIN["🛠️ Admin side"]
        direction TB
        PA["Platform Admin<br/>/admin/*"]
        CA["College Admin<br/>/user/:tenant/*"]
        PA -->|"create/suspend colleges,<br/>degrees, job roles,<br/>question bank, AI8 weights,<br/>attempt limits"| ADMIN_LV["Admin LiveViews<br/>dashboard · add_college · college_config<br/>degrees · jobs · question_bank · ai8_config"]
        CA -->|"add/verify students,<br/>bulk CSV, view results,<br/>grant extra attempts"| TENANT_LV["College-Admin LiveViews<br/>dashboard · students · add_student · programs"]
    end

    subgraph STUDENT["🎓 Student side"]
        direction TB
        ST["Student<br/>/student/:tenant/*"]
        ST --> ONBOARD["Profile completion<br/>(resume + ID upload → AI parse → admin verifies)"]
        ONBOARD --> DASH["Student Dashboard<br/>8 assessment cards + AI8 score"]
        DASH --> A1["MCQ<br/>(rule-based, no LLM)"]
        DASH --> A2["JAM"]
        DASH --> A3["Interview"]
        DASH --> A4["Behavioral"]
        DASH --> A5["Psychometric"]
        DASH --> A6["Case Study"]
        DASH --> A7["Mini Project"]
        DASH --> A8["Resume / ATS"]
    end

    ADMIN_LV --> CONTEXTS
    TENANT_LV --> CONTEXTS
    A1 --> CONTEXTS
    A2 & A3 & A4 & A5 & A6 & A7 & A8 --> CONTEXTS

    subgraph BACKEND["Shared backend"]
        direction TB
        CONTEXTS["Contexts layer<br/>(business logic — one module per domain:<br/>Tenants, Students, Entitlements/AttemptGuard,<br/>Jam, Interview, Behavioral, Psychometric,<br/>CaseStudy, MiniProject(V4), StudentAts, AI8)"]

        CONTEXTS --> AI["AI engines<br/>(GroqClient → Groq API)<br/>gpt-oss-120b: scoring/judgment<br/>gpt-oss-20b / llama-3.1-8b-instant: fast generation"]

        CONTEXTS --> DB[("Postgres, multi-tenant<br/>public schema: platform/tenant registry<br/>tenant_&lt;college&gt; schema per college:<br/>students, assessment tables, AI8 evaluations")]

        CONTEXTS --> JOBS["Oban background jobs<br/>AssessmentFinalizer + AssessmentAbandonmentSweep<br/>(closed-tab / crash recovery)<br/>ReportGenerator (PDF + email)<br/>AtsResumeProcessor · AtsFileCleanup"]

        JOBS --> DB
        JOBS --> MAIL["Email<br/>(credentials, verification, reports)"]
    end

    AI8AGG["AI8 aggregation<br/>rolls up all 8 module scores<br/>into one weighted index"] --> DB
    CONTEXTS -.publishes scores.-> AI8AGG
    AI8AGG -.read by.-> ADMIN_LV
    AI8AGG -.read by.-> DASH
```

---

## Admin side

Two tiers, same codebase, different scope:

| Tier | Route prefix | Scope |
|---|---|---|
| **Platform Admin** | `/admin/*` | Onboards colleges (tenants), configures degrees/specializations, job roles, the shared question bank, AI8 dimension weights, and per-college attempt limits |
| **College Admin** | `/user/:tenant/*` | Manages their own college: add/verify students (single or bulk CSV), view results and rankings, grant individual students extra attempts, run programs |

Both talk to the same **Contexts layer** — there's no separate admin backend, just narrower LiveViews and (for College Admin) requests scoped to their tenant schema.

## Student side

One flow, three phases:

1. **Onboarding** — upload resume + ID → AI parses the resume (`ai/resume/llm_parser.ex`, `relevance.ex`) → college admin verifies → student gets login credentials.
2. **Dashboard** — 8 assessment cards, each independently startable, plus a combined AI8 score.
3. **Assessments** — each has its own LiveView + Context module. MCQ is deterministic (no LLM); the other 7 call into Groq via `GroqClient`, with `reasoning_effort` split between fast generation (question/scenario/topic generation) and careful judgment (answer scoring, report synthesis) — see `docs/scoring-bands.md`.

Every assessment funnels into the same completion path regardless of whether the student finishes normally or closes the tab mid-session — see `docs/assessment-abandonment.md`.

## Shared backend

- **Contexts** — one Elixir module per domain (`Jam`, `Interview`, `Behavioral`, `Psychometric`, `CaseStudy`, `MiniProject`/`MiniProjectV4`, `StudentAts`, `AI8`, `Entitlements`/`AttemptGuard`, `Tenants`, `Students`...). LiveViews are thin — all real logic lives here, which is what both the admin and student LiveViews call into.
- **Multi-tenant Postgres** (Triplex) — one Postgres schema per college (`tenant_<alias>`), holding that college's students and assessment data in isolation; a `public` schema holds the platform-wide tenant registry.
- **AI engines** — `GroqClient` wraps the Groq API. `openai/gpt-oss-120b` handles anything that judges a student's work; a faster model handles turn-based/generative calls where latency matters more than deliberation.
- **AI8 aggregation** — every assessment publishes its scores into one shared evaluation table; AI8 rolls them up (per super-admin-configured dimension weights) into the single score shown on both the student dashboard and the admin's student-detail view.
- **Oban background jobs** — `AssessmentFinalizer` + `AssessmentAbandonmentSweep` recover abandoned sessions; `ReportGenerator` emails PDF reports; `AtsResumeProcessor`/`AtsFileCleanup` handle resume scoring and retention.

---

## Related docs

- `docs/user-guide.md` — role-by-role walkthrough
- `docs/attempt-limits.md` — how per-college attempt quotas work
- `docs/assessment-abandonment.md` — closed-tab / crash recovery
- `docs/ai8-scoring.md` — the AI8 aggregation model
- `docs/scoring-bands.md` — the shared 0–100 scoring calibration
