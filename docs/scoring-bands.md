# Scoring bands (canonical)

All LLM-judged assessments score each dimension **0–100** using one shared,
**encouragement-calibrated** band table. The intent is that a genuinely *good*
answer lands in the **80s** so students feel rewarded, while the bottom of the
range still discriminates honestly (gibberish/empty answers stay near 0).

| Band | Meaning |
| --- | --- |
| **90–100** | Excellent — rare, standout, expert-level / original insight |
| **80–89** | **Good** — solid, on-target, specific, real ownership. **Target for a good answer.** |
| **65–79** | Average / competent — on-topic but generic or thin |
| **45–64** | Below average — partial, vague, notable gaps |
| **25–44** | Weak — mostly incorrect / very thin |
| **10–24** | Very weak — minimal engagement |
| **0–9** | No answer / gibberish / off-topic |

## Where it's applied

| Module | File | Notes |
| --- | --- | --- |
| JAM | `ai/jam_engine.ex` (eval prompt) | Worked calibration anchors lifted to match; degenerate-response cap unchanged |
| Interview | `ai/interview/evaluator.ex` | `@system` scoring guide |
| Behavioral | `ai/behavioral_engine.ex` | Band table + calibration examples; gibberish/no-pity guards unchanged |
| Case study | `ai/case_study_engine.ex` | Sub-score maxes (40/30/30) unchanged; sincere-attempt calibration raised to 78–85 |

## Deliberately NOT recalibrated

- **Psychometric** (`ai/psychometric_engine.ex`) — Big Five *trait measurement* on
  a 1–5 Likert scale, not a performance score. Inflating it would corrupt the
  personality interpretation, so it keeps its neutral 3.0 baseline.
- **Resume** (`ai/resume/*`) — algorithmic (not LLM-judged); its distribution is
  set by code weights (30% completeness + 50% relevance + 20% sanity), untouched.
- **MCQ** — deterministic SQL scoring, no judgment bands.

## Trade-off (known)

Encouraging calibration compresses real answers into ~65–100, which **reduces
discrimination** between average and good students and lifts the headline Vyaasa
score (a flat mean of completed modules). Accepted as a product decision to
improve student morale. Behavioral remains the strictest module by design
(hiring-calibrated); its anti-gaming guards are intact.

## Internal thresholds to review (NOT auto-changed)

These signal thresholds were tuned against the *old* bands and may warrant a
revisit now that a given number means something higher:

- Interview follow-up gate `@followup_min 40 / @followup_max 60` (`evaluator.ex`)
- Interview `@weak_dim_threshold 55`, strong-topic `≥70`, weak-topic `<50`
  (`interview/session.ex`)
- Behavioral safety-ceiling math (`behavioral_engine.ex`)
