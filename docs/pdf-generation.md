# PDF Generation — Typst Pipeline

## Overview

Vyaasa generates report PDFs server-side using [Typst](https://typst.app/), a modern
typesetting system compiled to a single static binary. There is no Chrome, no headless
browser, and no external service.

## Architecture

```
generate_pdf(type, id, tenant_schema)
        │
        ▼
Reports.load_context/3          ← loads DB data, builds context map
        │
        ▼
TypstRenderer.render/2          ← serializes context → JSON temp file
        │                          calls: typst compile <template> <out.pdf>
        ▼
priv/typst/<type>.typ           ← Typst template reads JSON via sys.inputs
        │
        ▼
{:ok, pdf_binary}               ← returned to Oban worker → emailed
```

## Key Files

| File | Purpose |
|------|---------|
| `lib/vyaasa_campus/reports.ex` | Context loaders for each report type |
| `lib/vyaasa_campus/reports/typst_renderer.ex` | Elixir → Typst bridge (serialization, shell-out, cleanup) |
| `priv/bin/typst` | Typst 0.15.0 static binary (musl, no runtime deps) |
| `priv/typst/_shared.typ` | Shared colors, components, header/footer |
| `priv/typst/<type>.typ` | One template per report type |

## Report Types

| Type | Template | Triggered by |
|------|----------|-------------|
| `:mcq` | `mcq.typ` | MCQ submission |
| `:jam` | `jam.typ` | JAM completion |
| `:behavioral` | `behavioral.typ` | Behavioral assessment completion |
| `:psychometric` | `psychometric.typ` | Psychometric completion |
| `:interview` | `interview.typ` | Interview session end |
| `:case_study` | `case_study.typ` | Case study submission |
| `:ai8` | `ai8.typ` | "Email me my AI8 report" button |
| `:resume` | `resume.typ` | ATS pipeline completion |
| `:leaderboard` | `leaderboard.typ` | Admin download (manual) |
| `:specialization` | `specialization.typ` | Admin download (manual) |

All student reports are auto-enqueued on completion via Oban and emailed. Admin
reports (leaderboard, specialization) remain on-demand downloads.

## Data Flow

1. `TypstRenderer.render/2` receives the context map from `Reports.load_context/3`.
2. It runs `serialize/1` to convert Elixir-specific types to JSON-safe values:
   - `%DateTime{}` → ISO 8601 string
   - `%Decimal{}` → float
   - Structs → plain maps with string keys
   - Atoms → strings
   - Tuples → lists
3. The serialized map is written to a temp file (`/tmp/vyaasa_<id>.json`).
4. `typst compile <template>.typ <out>.pdf --input datafile=<json_path> --root /` is called via `System.cmd/3`.
5. PDF bytes are read from the output file, both temp files are deleted in `after`.

## Templates

Templates are in `priv/typst/`. Each one:

```typst
#import "_shared.typ": *

#let data = json(sys.inputs.at("datafile"))   // reads the JSON temp file
// ...build PDF layout using data...
```

Shared components from `_shared.typ`:

| Component | Description |
|-----------|-------------|
| `score-circle(score)` | Filled circle with score number |
| `score-bar(label, score)` | Labelled progress bar |
| `card(title:, body)` | Rounded bordered card block |
| `bullet-list(items)` | Orange-bulleted list |
| `kv-row(key, val)` | Key-value row with right-aligned value |
| `report-header(data, title)` | Brand header with student meta |
| `report-footer(generated_at)` | Confidentiality footer |

Colors follow the Vyaasa brand palette (`c-orange`, `c-green`, `c-amber`, `c-red`, etc.).
Score colors are computed by `score-color(n)`: green ≥ 75, amber ≥ 60, orange ≥ 40, red < 40.

## Adding a New Report Type

1. Add the type atom to the `@type report_type` union in `reports.ex`.
2. Add a `load_context/3` clause and a `build_*_context` private function.
3. Add a `filename/2` clause.
4. Create `priv/typst/<type>.typ` (import `_shared.typ`, read `sys.inputs.at("datafile")`).
5. Wire auto-enqueue at the completion point (if student-facing).

Verify the template compiles before committing:

```bash
# Write a minimal JSON fixture
echo '{"student":{"first_name":"Test","last_name":"User","email":"t@t.com"},"generated_at":"2026-01-01","_logo_path":""}' \
  > /tmp/test.json

priv/bin/typst compile priv/typst/<type>.typ /tmp/out.pdf \
  --input datafile=/tmp/test.json --root /
```

## Why Typst (not ChromicPDF / WeasyPrint)

| | ChromicPDF | WeasyPrint | **Typst** |
|--|-----------|-----------|-----------|
| Runtime dep | Chrome (~600MB) | Python + Cairo | None (static binary) |
| Cold start | 10–20s | ~1s | ~50ms |
| Avg render | 3–5s | ~1s | ~500ms |
| Docker image delta | +600MB | +150MB | +9MB |
| CSS support | Full | Good | N/A (own syntax) |
| Selectable text | Yes | Yes | Yes |
| Server-side | Yes | Yes | Yes |

ChromicPDF was removed in commit `4518928` (June 2026).

## Deployment

The Typst binary at `priv/bin/typst` is a musl static binary and runs on any Linux
x86-64 host without installing anything. No `apt install`, no Docker layer changes.

On the server, after `git pull`:

```bash
mix deps.get
mix phx.server   # or restart the container
```

No `typst` package needs to be installed system-wide — the binary is bundled.
