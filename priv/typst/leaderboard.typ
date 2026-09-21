#import "_shared.typ": *

#let data    = json(sys.inputs.at("datafile"))
#let rankers = data.at("rankers", default: ())
#let total   = data.at("total", default: 0)

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 9.5pt, fill: c-dark)
#set par(leading: 0.6em)

#report-header(data, "Student Leaderboard",
  subtitle: data.at("subtitle", default: ""))

// ── Summary ───────────────────────────────────────────────────────────────────
#card[
  Showing top #text(weight: "bold")[#total] students ranked by Vyaasa Score.
]

// ── Leaderboard table ─────────────────────────────────────────────────────────
#if rankers.len() > 0 [
  #block(
    width: 100%,
    stroke: (paint: c-border, thickness: 0.5pt),
    radius: 7pt,
    clip: true,
  )[
    #block(width: 100%, inset: (x: 12pt, y: 8pt))[
      #grid(columns: (1fr, 1fr, 1fr, 1fr),
        align(center, text(size: 8pt, weight: "bold", fill: c-muted)[Rank]),
        align(center, text(size: 8pt, weight: "bold", fill: c-muted)[Student]),
        align(center, text(size: 8pt, weight: "bold", fill: c-muted)[Registration]),
        align(center, text(size: 8pt, weight: "bold", fill: c-muted)[AI8 Score]),
      )
    ]
    #line(stroke: (paint: c-border, thickness: 0.5pt), length: 100%)
    #for (idx, s) in rankers.enumerate() {
      let rank     = idx + 1
      let top3_col = if rank == 1 { rgb("#fbbf24") } else if rank == 2 { rgb("#9ca3af") } else if rank == 3 { rgb("#d97706") } else { c-muted }
      let name     = s.at("name", default: "—")
      let reg      = s.at("registration_id", default: "—")
      let vs_raw   = s.at("vyaasa_score", default: none)
      let vs_str   = if vs_raw  != none { str(calc.round(float(vs_raw)))  } else { "—" }
      let vs_col   = if vs_raw  != none { score-color(float(vs_raw))  } else { c-muted }
      block(width: 100%, inset: (x: 12pt, y: 6pt))[
        #grid(columns: (1fr, 1fr, 1fr, 1fr),
          align(center, text(weight: "bold", fill: top3_col)[#rank]),
          align(center, text[#name]),
          align(center, text(fill: c-muted)[#reg]),
          align(center, text(weight: "bold", fill: vs_col)[#vs_str]),
        )
      ]
      if idx < rankers.len() - 1 {
        line(stroke: (paint: c-border, thickness: 0.4pt), length: 100%)
      }
    }
  ]
]

