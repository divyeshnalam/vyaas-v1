# Readiness Checklist: 1000 Concurrent Students Taking Exams

This extends `docs/concurrency-scaling-500-users.md` (the Groq/Finch/LiveView
infra groundwork, still accurate) with what's specific to **1000 concurrent
students actively taking assessments**, and with four real gaps found and
fixed while preparing this doc — all of it code/migration work doable now,
in development, before any production infra decisions need to be made. Read
the 500-user doc first — this one assumes it.

## What was found and fixed

### 1. Every abandonment-sweep query was a full table scan (fixed)

`AssessmentAbandonmentSweep` (runs every 15 min, every tenant schema) queries
`jam_sessions`, `interview_sessions`, `student_behavioral_assessments`,
`student_psychometric_assessments`, `case_study_sessions`, and
`mini_project_sessions` with `WHERE status NOT IN (...) AND updated_at <
cutoff`. **None of these tables had any index covering `updated_at`** — every
run scanned the full table, in every tenant, unconditionally. At real row
counts (a term's worth of completed sessions across a large cohort), that
scan directly competes with live exam traffic for the same tables, during
the exact window it's least affordable.

Fixed in `priv/repo/tenant_migrations/20260822120000_add_abandonment_sweep_indexes.exs`
— adds `(status, updated_at)` (or `(phase, updated_at)` for mini_project)
composite indexes to all six, plus two smaller gaps the same audit found:
`case_study_sessions` had no index on `tenant_id` at all (every sibling table
has one), and `mini_project_sessions.engine_version` (splits v1/v4 sessions)
had none either.

**Action required:** run this migration against every tenant schema before
any high-concurrency event. `mix tenants.migrate` already exists and does
exactly this (runs every pending tenant migration against every tenant in
one go, or `mix tenants.migrate --tenant BITE` for one college) — this is
not new tooling, just make sure it's actually run against every real tenant
before an event, since it's not automatic. Already applied to the dev
tenant schema and verified directly with `\d <table>`.

### 2. A pre-existing migration was silently never applied anywhere (found AND fixed)

While testing #1, discovered `20260403100004_add_tenant_indexes.exs` uses
raw `execute("... current_schema() ...")` SQL to detect which tenant it's
running against. **Raw SQL executed via `execute/1` does not pick up the
migration's `prefix:` schema** the way `create index(...)` does —
`current_schema()` inside that block evaluates to `public`, not the tenant
schema, so its `IF EXISTS` checks are always false and it has been a silent
no-op in every tenant, including production, despite showing as "applied"
in `schema_migrations`. Confirmed directly against `tenant_test`: none of
its three named indexes or its two CHECK constraints existed.

Auditing what it was actually trying to add: most of it turned out to
already be redundant — `student_id` and `status` already have standalone
indexes on `jam_sessions`/`interview_sessions`/`assessment_attempts` from
their original `CREATE TABLE` migrations, so Postgres can already combine
them via a bitmap index scan. But two things were genuinely missing:

- The `(student_id, status)` composite on `jam_sessions`/`interview_sessions`
  — a real, if modest, improvement over two separate index scans.
- **The two CHECK constraints.** `assessments.status` and
  `assessment_attempts.status` had **zero database-level protection** —
  only the Ecto changeset's `validate_inclusion` guarded them, which does
  nothing against a raw SQL update, a bad future migration, or direct DB
  access. This is a real data-integrity gap, not just a performance one.

Fixed in `priv/repo/tenant_migrations/20260822130000_fix_broken_tenant_indexes_migration.exs`,
using the Ecto DSL throughout (not raw SQL) so it doesn't repeat the same
mistake. Applied to `tenant_test` and verified both the indexes and the
constraints actually exist this time (`\d tenant_test.assessments` shows
`chk_assessment_status`, etc.).

**Also worth doing:** grep for any other tenant migration using
`current_schema()` in raw SQL and check it the same way — this exact bug
pattern could be repeated elsewhere unnoticed.

### 3. `assessment_finalize` Oban queue was undersized (fixed)

5 workers, sized without 1000-user bursts in mind. If an exam's time limit
lapses for a large cohort within the same minute (or many students close
tabs around the same moment — end of a session block, a fire drill, whatever),
each abandoned session enqueues one `AssessmentFinalizer` job, and most of
those jobs make an LLM call. At 5 concurrent workers, a burst of a few hundred
backs up for minutes, during which those students' results are stuck
"processing." Raised to 15 in `config/config.exs`. This trades directly
against database connection headroom — see below.

### 4. No load-test tool exercised a real assessment path (fixed)

`lib/mix/tasks/loadtest.login.ex` and `loadtest.rehash.ex` covered the
bcrypt/login hot path in isolation; `test/scripts/regression_5_users.exs`
(uncommitted, local) exercises the AI engines directly at n=5, bypassing
the DB-backed context layer. Nothing drove the actual context functions a
real student's exam-taking hits, at concurrency.

Added `mix loadtest.exam` (`lib/mix/tasks/loadtest.exam.ex`), two profiles:

- `--type mcq` (default) — the real DB path (`get_or_create_dynamic_assessment/2`
  → `start_assessment_attempt/3` → `force_submit_assessment/3`), no LLM, safe
  at any burst size. This is what actually exercises the index/lock
  questions in this doc.
- `--type jam` — calls `JamEngine.generate_topic/0` directly (the real
  Groq call JAM's "Start" step makes) and reports `GroqRateLimiter.stats()`
  per burst. **Burns real Groq quota** — sized deliberately, not run here
  beyond a couple of manual dry-run bursts to prove the tool itself works.

Dry-run verified against dev data (`Bites` tenant, real seeded
`loadtest_*` students): a fresh run performs genuine writes (assessment
creation, attempt insert, AI8 evaluation publish, report-PDF trigger); a
second run against the *same* students correctly reports real
`:already_submitted` rejections rather than silently succeeding — the
context layer's own no-retake rule surfacing exactly as it should, not a
bug in the tool. Full usage and the reuse caveat are in the task's own
`mix help loadtest.exam`.

## What still needs a decision (infra, not code)

### 5. Oban worker count vs. `POOL_SIZE`

Total configured Oban concurrency, summed across all queues:
`default(10) + emails(5) + imports(3) + ats_processing(5) + ai_reports(10) +
cleanup(1) + assessment_finalize(15) = 49`. Each *active* Oban job holds a
database connection for its duration. The 500-user doc's `POOL_SIZE=40`
default was already tight against the *old* total of 34 (before
`assessment_finalize` existed at all); against the new total of 49 it's now
undersized on its own, before counting a single LiveView web request.

For 1000 concurrent students, the realistic peak concurrent DB operation
count (answer autosaves, session creates, status updates, report saves) is
roughly double the 500-user doc's own estimate of 50–80 — call it 100–160.
**`POOL_SIZE` needs to comfortably exceed Oban's 49 plus that web-request
peak — realistically 150–200+, not 40.**

At that range, a single Postgres instance's default `max_connections=100`
becomes the actual ceiling, not `POOL_SIZE`. Two real options, not mutually
exclusive:
- Raise Postgres `max_connections` (requires a DB restart) to comfortably
  exceed the new `POOL_SIZE` across however many app nodes you run.
- Put **PgBouncer** (or equivalent) in front of Postgres in transaction-
  pooling mode. This is the standard answer at this scale — it lets the app
  hold many logical connections while Postgres itself only ever sees a much
  smaller number of real backend connections, each of which costs real
  Postgres-side memory (~5–10 MB) regardless of how idle it is.

### 6. Groq plan tier and `GROQ_MAX_CONCURRENT`

Per the 500-user doc's own table, reaching 500–1000+ concurrent users needs
an Enterprise-tier Groq plan and `GROQ_MAX_CONCURRENT` around 200. Confirm
the actual plan tier before an event at this scale — the free/developer
tiers hard-cap around 10–30 concurrent calls regardless of anything else in
this doc.

Separately: this session raised `reasoning_effort` from `"low"` to
`"medium"` on every scoring/judgment call (answer evaluation, consistency
checks, report synthesis — see the interview evaluator fix). This was the
right call for score quality, but it means each of those calls now spends
longer *in flight*, holding a rate-limiter slot and a Finch connection for
longer. The 500-user doc's throughput numbers predate this change and are
now a bit optimistic for the scoring-heavy assessments (JAM, Interview,
Case Study, Behavioral, Mini Project) specifically — question/scenario
*generation* calls are unaffected, they're still `"low"`. Re-run the load
test in the 500-user doc's "Load Test Results" table against current code
before trusting its exact numbers at 1000 users.

## Per-assessment edge cases at 1000 concurrent test-takers

| Assessment | What's different at scale | Status |
|---|---|---|
| **MCQ** | No LLM at all — pure DB load. Every answer click writes synchronously (not debounced) via `save_answers/5`. At 1000 students each answering roughly one question every 30–60s, that's ~20–30 writes/sec sustained for the whole exam window, not a burst. `assessment_attempts` is already well-indexed (`student_id`, `status`, and their composite). Time-limit auto-submit (`force_submit_assessment/3`) at exam-end is itself a burst — see the abandonment sweep / MCQ deadline handling in `docs/assessment-abandonment.md`. | OK, already the most scale-tolerant type |
| **JAM** | 3 Groq calls/session (topic gen, transcription, evaluation) plus audio payloads (larger than text completions — more bandwidth/memory per request than other types). Now indexed for the sweep (fix #1). | Needs the migration + Groq tier confirmation |
| **Interview** | Most Groq-call-heavy type (planner, interviewer, evaluator, consistency, reporter, GitHub analysis). `reasoning_effort: "medium"` on the judgment calls (fix from this session) adds real latency per call. Attempt-limit blocking screen and the create-row-after-guard-check ordering fix (this session) prevent a second, DB-level failure mode under retry pressure. | Needs the migration + re-run load test |
| **Behavioral** | 2–4 calls per conversational turn, 10–15 turns/session — the highest total-calls-per-session of any type. Naturally staggered (users type between turns), per the 500-user doc's own analysis — that analysis still holds. | Needs the migration |
| **Psychometric** | 1 call per follow-up question during the session (not just at the end) plus 1 final interpretation call — more calls than the 500-user doc assumed ("1 Groq call per user — only at submit time" undercounts this; it's adaptive, so there's a call *between* nearly every question). | Needs the migration; re-check the 500-user doc's psychometric call estimate |
| **Case Study** | 2 calls (scenario gen + report/scoring), but the report call now runs at `reasoning_effort: "medium"`. Proctoring (fullscreen/tab-switch detection) is client-side, no server load concern. | Needs the migration |
| **Mini Project (v1)** | The most DB-write-heavy type after MCQ — discovery messages, viva turns, and reflection all persist incrementally, not just at completion. Real submission deadline (24h) means its own abandonment-sweep query is deadline-based, not just grace-window based (see `docs/assessment-abandonment.md`) — this is the type most likely to generate a large *simultaneous* abandonment burst if many students share the same deadline, directly stressing the now-larger `assessment_finalize` queue. | Needs the migration; this is the type most likely to stress fix #3 |
| **Mini Project (v4)** | Same deadline-burst risk as v1. Six LLM calls across the flow; viva-answer scoring now runs at `reasoning_effort: "medium"`. Not currently linked from the student dashboard (v1 is what students actually reach), so this is lower real-world risk today. | Needs the migration |
| **Resume/ATS** | Onboarding, not an "exam," but a real burst pattern in its own right — 1000 students uploading resumes the night before an exam event is exactly the kind of correlated burst this whole doc is about. JD-relevance judging now runs at `reasoning_effort: "medium"`. `ats_processing` Oban queue (5 workers) and `AtsResumeProcessor`/`Lifeline` recovery already exist for this — confirm queue size is adequate for the actual onboarding cohort size, same reasoning as fix #3. | Confirm `ats_processing` queue size for your cohort |

## Done now, in development (this pass)

- [x] Added the missing abandonment-sweep indexes (finding #1) — migration written, applied to the dev tenant, verified.
- [x] Fixed the silently-broken `20260403100004` migration (finding #2) — rewritten with the Ecto DSL, applied, verified (indexes *and* the two CHECK constraints both actually exist now).
- [x] Raised `assessment_finalize` Oban queue 5 → 15 (finding #3).

## Still to do before a 1000-user event

**Can do now, in development, no production access needed:**
1. **Run `mix tenants.migrate`** against every real tenant once any exist (dev already has the dev tenant covered) — the two new migrations aren't applied automatically to tenants that already existed before them.
2. **Check `ats_processing` queue size (currently 5)** against your actual onboarding cohort size, same reasoning as the `assessment_finalize` fix — if 1000 students upload resumes the night before an exam, 5 workers may be just as undersized.
3. **Run `mix loadtest.exam --tenant <alias> --bursts 10,50,100,500,1000`** (MCQ, no Groq cost — safe to run at full scale) against a freshly-seeded batch to get real numbers for this environment. Run `--type jam` separately, deliberately, when ready to spend the quota.
4. **Grep for other tenant migrations using `current_schema()` in raw SQL** — the exact bug in finding #2 could be silently repeated elsewhere.

**Needs your input / real infra access — not code changes:**
5. **`POOL_SIZE`** — needs to go well past 40 (realistically 150–200+) and Postgres `max_connections` (or PgBouncer) needs to actually support it. Depends on your DB server's real specs.
6. **Confirm Groq plan tier** supports `GROQ_MAX_CONCURRENT` in the 150–200 range — the free/developer tiers hard-cap around 10–30 regardless of anything else in this doc.
7. If running multi-node: confirm sticky sessions (LiveView WebSocket affinity) are configured, per the 500-user doc.

## Related docs

- `docs/concurrency-scaling-500-users.md` — infra groundwork (Groq rate limiter, Finch, DB pool, LiveView/Bandit tuning) — still accurate, read first
- `docs/assessment-abandonment.md` — the sweep and per-type completion logic referenced above
- `docs/scoring-bands.md` — the `reasoning_effort` split between generation and judgment calls
- `docs/architecture.md` — system overview
