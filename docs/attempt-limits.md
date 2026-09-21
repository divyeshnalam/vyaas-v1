# Assessment Attempt Limits

How many times a student may take each assessment, configured per college by the
super admin. Built on a generic **entitlements** store so subscription plans can
later grant the same quotas without a schema change.

## The rule

```
per-module override  →  global default  →  unlimited
```

- **No entitlement configured = unlimited.** A college is unrestricted until
  someone sets a limit, so nothing changes for existing tenants on deploy.
- **An explicit `0` means blocked**, not "unset".
- Attempts are counted inside the college's **subscription period**; with no
  period set, they count over all time.
- **Started** attempts count, not completed ones — otherwise a student could
  abandon and restart forever.

## Where it's configured

**Colleges → (row menu) Configure → Limits & Attempts**
(`/admin/colleges/:id/config`)

Set a default for every assessment plus optional per-assessment overrides, and
the subscription period. Each override shows its *effective* value so the impact
of the default is visible before saving.

Tenant admins can grant an individual student extra attempts from the **student
detail drawer** — grants are append-only and attributed to the admin who made
them.

## Data model

| Table | Schema | Purpose |
|---|---|---|
| `tenant_entitlements` | public | `key`/`value` quotas, unique per `(tenant_id, key)`. NULL value = unlimited |
| `tenant_subscriptions` | public | The period attempts reset on. Billing attaches here later |
| `attempt_grants` | tenant | Append-only extra attempts for one student + module |

Keys in use: `attempts.default`, `attempts.<module>` for the 8 modules
(`resume` `mcq` `behavioral` `psychometric` `jam` `interview` `case_study`
`mini_project`). Future quotas (`students.max`, `ai_credits.period`,
`feature.*`) need no migration.

## Enforcement

Guards live in the **contexts**, not the LiveViews, so LiveView, API and jobs are
all covered by one change:

| Module | Guarded function |
|---|---|
| MCQ | `Assessments.retake_with_new_assessment/2` |
| JAM | `Jam.create_jam_session/2` |
| Interview | `Interview.start_session/2` |
| Behavioural | `Behavioral.create_assessment/4` |
| Psychometric | `Psychometric.start_adaptive/3` |
| Case Study | `CaseStudy.start_session/5` |
| Mini Project | `MiniProjectV4.create_session/5` and `MiniProject.create_session/2` |
| Resume | `StudentAts.create_reanalysis_phase/4` |

Each returns `{:error, :attempt_limit_reached, %{used:, limit:, granted:}}`.

Two deliberate choices:

- **Resume is capped on re-analysis only.** The first upload *updates* the
  existing ATS phase rather than inserting, so onboarding can never be blocked.
- **The guard fails open.** If quota accounting raises, it logs and allows the
  attempt — a bug in limits must never lock a student out of an exam.

## Key source

- `lib/vyaasa_campus/contexts/entitlements.ex` — `attempt_limit/2` (resolution),
  `put_attempt_limits/3`, `current_period/1`
- `lib/vyaasa_campus/contexts/attempt_guard.ex` — `check/3,4`, `status/3,4`,
  `used/4`, `grant_extra/6`. `@module_sources` maps each module to its table;
  note JAM and interview have no `attempt_number` column, so every module is
  counted by row.
- `lib/vyaasa_campus_web/live/admin/college_config_live.ex` — the admin UI

## Not covered

Billing, plan self-service, invoices, and quotas other than attempts (seats and
AI credits can be stored but nothing enforces them yet).

Also note: **deactivating a college does not currently block logins** — that is a
separate gap in `Auth.authenticate_student/3` and `authenticate_user/3`, which
never consult `tenant.status`.
