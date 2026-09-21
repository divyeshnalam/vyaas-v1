# AI8 Scoring — How the Index is Calculated

The **AI8 Index** is a single 0–100 "career readiness" score for a student, built
from the assessments they complete. It rolls up into **8 skill dimensions**, which
combine into the overall index shown on the student's AI8 Overview.

## The 8 dimensions

`domain_expertise` · `communication` · `problem_solving` · `adaptability` ·
`collaboration` · `leadership` · `work_ethics` · `cultural_fit`

## The 8 modules (assessments) that feed it

`resume` · `interview` · `mcq` · `jam` · `behavioral` · `case_study` ·
`psychometric` · `mini_project`

## Two layers of configuration (super-admin, global)

Set in **Admin → AI8 Config** (`ai8_module_dimensions` + `dimension_weights`):

1. **Module × Dimension weights** — for each module, the % each dimension
   contributes. A cell `> 0` *enables* that dimension for the module (only enabled
   dimensions are requested from the LLM and scored). Each module's row sums to
   **100%**.
2. **Global dimension weights** — how much each of the 8 dimensions counts toward
   the overall index. Sum to **100%** (e.g. Domain 24, Communication 15, …).

## The pipeline

```
assessment completed
      │  each module scores ITS configured dimensions 0–100
      ▼
AI8.publish_module / publish_evaluation   → ai8_module_evaluations row
      │  (publish_module keeps only the module's configured dimensions)
      ▼
per-dimension roll-up  (across every module that scored that dimension)
      ▼
overall AI8 index      (combine the 8 dimensions by global weights)
```

### Step 1 — Module scores its dimensions (0–100)

Each engine produces `skill_scores = %{dimension => 0..100}` for the dimensions
configured for that module, and publishes them. `publish_module` filters the raw
scores to the module's **configured** dimensions (`Map.take`) so nothing
unconfigured is stored. `module_score` (the dashboard "pill") is the weighted
average of the module's dimensions by its Module × Dimension weights — it is shown
for context but is **not** used in the index.

### Step 2 — Per-dimension roll-up (weighted across modules)

For each dimension, compute a **weighted average over every module _configured_
to measure it**, each weighted by its Module × Dimension weight:

```
dimension_value = Σ(module_score × module_weight) / Σ(module_weight)
                    over modules SCORED          over ALL modules CONFIGURED
```

The denominator is the **full configured weight** for that dimension — modules
the student hasn't completed stay in the denominator and contribute **0** to the
numerator. So a dimension only reaches 100 when *every* assessment feeding it has
been taken and aced.

If no module has a configured weight for the dimension, it falls back to a plain
equal-weight average of whatever was scored. (Code: `AI8.student_profile/2`.)

### Step 3 — Overall AI8 index (weighted by global dimension weights)

```
index = Σ(dimension_value × global_weight) / Σ(global_weight)   # Σ global_weight = 100
```

Because both steps normalise, an all-100 student scores exactly **100** and an
all-0 student exactly **0**, whatever the weights are — but only after
**all 8 assessments** are complete. The index rises as more are finished.

`completion` = **assessments completed ÷ assessments configured** (e.g. 3 of 8 →
37.5%). It deliberately counts *assessments*, not dimensions: dimension coverage
overlaps so heavily that MCQ + JAM + behavioral alone touch all 8 dimensions,
which used to read as "100% complete". (Code: `AI8.ai8_index/2`.)

### Why all 8 assessments are required

Each of the 8 modules holds weight in at least one dimension, so skipping any one
of them caps the index below 100. Skipping a module costs exactly its share of the
dimensions it feeds:

| Missing assessment | Index (everything else 100) | What drops |
|---|---|---|
| *(none — all 8 done)* | **100.0** | — |
| Resume | 91.2 | domain 100 → 64.9 |
| Psychometric | 88.5 | cultural_fit → 33.3, work_ethics → 44.4, adaptability → 68.8 |
| *(only MCQ + JAM + behavioral)* | 44.9 | most dimensions |

## The production configuration

Module × Dimension weights (each row sums to 100):

| Module | Dimensions (weight) |
|---|---|
| resume | domain 100 |
| interview | domain 46, communication 27, leadership 18, cultural_fit 9 |
| mcq | domain 63, problem_solving 37 |
| jam | communication 56, adaptability 44 |
| behavioral | collaboration 30, leadership 30, work_ethics 24, cultural_fit 16 |
| case_study | leadership 48, problem_solving 32, domain 20 |
| psychometric | cultural_fit 50, work_ethics 30, adaptability 20 |
| mini_project | domain 56, collaboration 22, leadership 22 |

Global dimension weights (sum to 100): domain 25 · communication 15 ·
problem_solving 15 · adaptability 12 · collaboration 10 · leadership 10 ·
work_ethics 8 · cultural_fit 5.

**Invariant:** every weighted cell must be a dimension that module's engine
actually emits. A cell no engine can fill is permanent dead weight in that
dimension's denominator and caps it below 100 forever. Check with:

```bash
mix run -e "VyaasaCampus.Contexts.AI8.config_audit() |> IO.inspect()"   # [] = sound
```

## One score, one engine

The AI8 index is the **only** composite score in the product. Every surface reads
`Contexts.AI8` — there is no second formula:

| Surface | Reads |
|---|---|
| Student AI8 Overview | `AI8.ai8_index/2` |
| Student dashboard · profile · shared profile | `StudentRankings.calculate_ai8_score/2` → `AI8.ai8_index/2` |
| Tenant/admin dashboard & student list | `DashboardLive.attach_ai8_scores/2` → `AI8.ai8_indexes/2` |
| PDF reports (leaderboard, specialization, analytics, readiness) | same enhanced list as the dashboard |

Use **`AI8.ai8_indexes(student_ids, prefix)`** for lists — a fixed three queries
regardless of student count, sharing the exact computation as `ai8_index/2`
(verified equal across 508 students). Never re-derive a composite score elsewhere.

### Live updates

`publish_evaluation/2` broadcasts `{:dashboard_event, %{kind: :ai8, action: :published,
student_id: …, module: …}}` on the tenant and student topics **after** the row is
written. Because all 8 modules reach AI8 through this one function, it is the only
place that needs to signal a score change — individual engines should not add their
own broadcast for scores (an engine-level broadcast can also fire *before* the AI8
row lands, which is the race this replaced).

Subscribers refresh the affected student only: `DashboardLive.load_student_with_scores/2`
reloads one row (~26ms) and aggregates are recomputed in memory, versus ~10s to reload
a 501-student tenant.

> **History:** `StudentRankings` used to compute a separate "Vyaasa Score" — an
> unweighted mean of the 6 assessments it knew about (ignoring case study and mini
> project), divided by *completed* assessments only. The admin dashboard displayed
> it under "AI8" labels, so admin and student screens disagreed by 10–90 points.
> That formula is gone; `vyaasa_score` is now `ai8_score` everywhere.

## Key source

- `lib/vyaasa_campus/contexts/ai8.ex` — `publish_module/4`, `aggregate_score/2`,
  `student_profile/2` (per-dimension roll-up), `ai8_index/2` (overall index),
  `ai8_indexes/2` (bulk, for lists), `config_audit/0` (config sanity check),
  `seed_config/0` (canonical weights).
- Each engine's publish call (e.g. `Contexts.Psychometric.publish_ai8/2`,
  `Contexts.Behavioral.publish_ai8/2`, interview/jam publish via
  `publish_evaluation`).
- `lib/vyaasa_campus/ai8/backfill.ex` — recompute AI8 rows for historical
  assessments.

## Notes / gotchas

- **Interview & JAM** publish via `publish_evaluation` directly (they bypass the
  `Map.take` config filter), but emit exactly their configured keys.
- **Behavioral** computes `adaptability` too; if the config doesn't enable it for
  behavioral, it is dropped — harmless (the reverse — configuring a dimension the
  engine never emits — is *not* harmless; see the invariant above).
- Historical rows written before a scoring fix can be stale (wrong dimensions or an
  old 0–10 scale) — re-run the assessment or run `AI8.Backfill`.
