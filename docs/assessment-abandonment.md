# Abandoned Assessments

What happens when a student closes the tab, navigates away, disconnects, or
the server crashes mid-assessment — across all 8 assessment types. Before
this, there was no background sweep, no `terminate/2`, no disconnect
handling anywhere: a student who closed the tab left a row stuck
non-terminal forever, with no path back to it.

## The rule

```
Close the tab → it gets submitted and evaluated. No pending assessment survives.
```

- **Detection is `terminate/2`-triggered, immediate** — not a periodic poll.
  The moment a connected session's socket goes away, finalization runs (or is
  enqueued) right then.
- **A periodic sweep is the safety net**, for what `terminate/2` structurally
  can't catch: a BEAM node crash / brutal kill skips `terminate/2` entirely.
- **Force through real evaluation**, even for near-empty sessions — no
  separate "abandoned, unscored" status. One completion path regardless of
  how much content exists; the existing scoring strictness (insufficient
  content already scores low/zero) naturally handles a near-empty session.
- **Idempotent everywhere.** Every completion function checks current status
  first and no-ops if already terminal, so `terminate/2` and the sweep can
  never double-process the same session, and neither can race a genuine
  in-flight submit.

## Architecture

```
Student closes tab ──┐
                      ├──▶ force_complete/2 (per type) ──▶ terminal status + score
Periodic sweep ───────┘         (async types: via AssessmentFinalizer, an Oban job)
(safety net, catches               (MCQ: synchronous — no LLM, no need to hand off)
 what terminate/2 missed)
```

- **`terminate/2` in each of the 8 student LiveViews** — guarded on
  `connected?(socket)`, since LiveView mounts twice (a disconnected
  static-render pass, then a connected mount over the websocket); without the
  guard this would fire on every page load, before the student even starts.
  MCQ calls `Assessments.force_submit_assessment/3` directly (already
  synchronous, no LLM — safe to run inline). Every other type enqueues an
  `AssessmentFinalizer` job and returns immediately — `terminate/2` must stay
  fast, an LLM call has no place blocking process shutdown.

- **`VyaasaCampus.Jobs.AssessmentFinalizer`** — one Oban worker (queue
  `assessment_finalize`), dispatched per type via `args["type"]` through a
  module-atom map + `apply/3`. Covered by the existing
  `Oban.Plugins.Lifeline` for orphan-rescue and normal Oban retries for
  transient LLM failures. `unique: [fields: [:args], period: 300, states:
  [:available, :scheduled, :executing]]` — `terminate/2` and the sweep can
  both enqueue for the same session (a `terminate/2` job still queued when
  the sweep next ticks, or two sweep ticks either side of a slow job); each
  type's `force_complete/2` idempotency guard only protects against a
  *sequential* repeat (it re-reads status from the DB before writing), not
  two instances reading "not yet terminal" at the same moment and both
  re-running real evaluation — the Oban-level dedup closes that.

- **`VyaasaCampus.Jobs.AssessmentAbandonmentSweep`** — Oban cron, every 15
  minutes (`config/config.exs`). Iterates every tenant schema
  (`Tenants.list_tenants/0`) and, per type, finds sessions past staleness and
  enqueues the same `AssessmentFinalizer` job (MCQ again bypasses it and
  calls `force_submit_assessment/3` directly). A tenant whose schema fails to
  query (e.g. a stale fixture row with no migrated schema) is logged and
  skipped — one bad tenant never blocks the sweep for the rest.

  Staleness rule, per type:
  - **Types with a real deadline** — MCQ (`duration_minutes` off the
    assessment + the attempt's `started_at`), Mini Project v1/v4
    (`submission_deadline`) — are only swept once that deadline has actually
    passed. A student still validly mid-session is never touched just for
    being quiet.
  - **Everything else** (JAM, Interview, Behavioral, Psychometric, Case
    Study; and the pre-deadline phases of Mini Project, before a deadline is
    even assigned) uses a flat 30-minute inactivity grace window on
    `updated_at`, which every incremental write (a discovery message, a viva
    answer, a proctoring log) bumps.

## Per-type completion function

| Type | `force_complete/2` reuses | Empty-content behavior |
|---|---|---|
| MCQ | `Assessments.force_submit_assessment/3` (pre-existing) | Objective scoring handles it natively — no special case |
| JAM | `Jam.process_audio/2` + `complete_processing/3` | Direct zero score, no LLM call |
| Interview | `Interview.complete_interview/3` | Arithmetic average of already-answered questions (`average_question_score/1`), no LLM re-invocation either way — first-ever force-submit for this type |
| Behavioral | `Behavioral.save_report/3` | Always direct zero score — nothing persists incrementally for this type |
| Psychometric | `Psychometric.finalize_report/2` | Direct write, scores left `nil` (not fabricated) — see note below |
| Case Study | (direct write only) | Always direct zero score — answers live in LiveView assigns only, never persisted incrementally |
| Mini Project v1 | `MiniProject.expire_session/2`, now extended to score for real | Direct zero score if no viva answer exists yet |
| Mini Project v4 | `MiniProjectV4.finalize/2` | Direct zero score if no viva answer exists yet |

Each `force_complete/2` follows the same shape: look up by session id, no-op
if already terminal (`{:ok, :already_terminal}`), otherwise either call the
type's real completion function (when there's genuine partial content worth
evaluating) or write a direct terminal record (when there's nothing to
evaluate, skipping the wasted LLM call). This is deliberately **not** a
second scoring implementation — force-completion is always an alternate
entry point into the same function a normal submit already uses.

**Every side effect the live path triggers now lives in that shared
completion function, not the LiveView.** JAM and Interview originally
published to AI8 only from a LiveView `handle_info` callback on the
connected, live path — `force_complete/2` (run from an Oban job, no
LiveView involved) silently never reached it. Both were moved into
`Jam.complete_processing/3` and `Interview.complete_interview/3`
respectively (same fix already applied to `MiniProject.complete_session/4`
during this work); Interview's move also preserves the live path's original
behavior of overriding the stored `overall_score` with the AI8-weighted
module score when available, not just firing the publish as an
afterthought. Behavioral, Psychometric, Case Study and Mini Project v4
already had this right — their AI8 publish lived in the context function
from the start.

### Psychometric — a flagged exception

Every other type's design predates this change with "no completion path at
all" for an abandoned session. Psychometric is different: it had a
**deliberate** prior decision (documented in `PsychometricLive.mount/3`) not
to resume or score a partial adaptive attempt, since a Big Five composite
built from 2 of ~20 answered items is noise, not a real personality score —
not the same failure mode as "wrong MCQ answers score 0."

This change reverses that decision: an abandoned session now does reach a
terminal `"completed"` record either way. The nuance kept from the original
concern: a zero-answer session gets trait score columns left `nil`, not a
fabricated neutral value — `complete_changeset/2` doesn't require them, so
there's nothing to invent, and no LLM call is spent interpreting nothing.

### Mini Project — one table, two engines, two deadlines

`mini_project_sessions` is shared between the legacy 7-phase engine (v1,
`Contexts.MiniProject`) and the viva-driven engine (v4,
`Contexts.MiniProjectV4`), split by `engine_version`. Both dispatch through
`AssessmentFinalizer` under different `type` strings (`"mini_project"` /
`"mini_project_v4"`) and score via a viva-defense gate: a session with no
(or very weak) defended viva answers is capped at/near zero by the engine's
own scoring regardless of how polished an uploaded artifact looks — so
`force_complete/2` short-circuits to a direct zero score whenever there are
zero *answered* viva turns, since the real evaluation function would land
there anyway, just after several wasted LLM calls.

v4's `submission_deadline` (set in `choose_scenario/3`) previously had
nothing reading it — this change is what wires it up, via the sweep's
deadline-based staleness check.

## Edge cases handled

- **Double-mount trap** — `terminate/2` guarded on `connected?(socket)`.
- **Race with a genuine in-flight submit** — every `force_complete/2`
  re-checks status before writing, so a `terminate/2` firing right after a
  normal successful submit is a no-op.
- **`terminate/2` and the sweep both catching the same session** — same
  idempotency guard covers it; whichever runs first wins, the second no-ops.
- **Legitimate resume must survive** — MCQ and Mini Project let a student
  continue an in-progress session on return; the sweep only touches sessions
  *past their real deadline* for those types, never a student still validly
  mid-session.

## Key source

- `lib/vyaasa_campus/jobs/assessment_finalizer.ex` — the dispatch worker
- `lib/vyaasa_campus/jobs/assessment_abandonment_sweep.ex` — the safety net
- Per-type `force_complete/2` in each `lib/vyaasa_campus/contexts/*.ex`
  (jam, interview, behavioral, psychometric, case_study, mini_project,
  mini_project_v4)
- `terminate/2` in each of the 8 `lib/vyaasa_campus_web/live/student/**/*_live.ex`
- `config/config.exs` — the `assessment_finalize` queue and the cron entry

## Not covered

Presence-based "student is idle but tab still open" detection — this handles
*closed*, not *idle-but-open*. Retroactively fixing already-stuck historical
rows from before this change is a one-off cleanup, not handled here.
