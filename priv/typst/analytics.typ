#import "_shared.typ": *

#let data       = json(sys.inputs.at("datafile"))
#let overview   = data.at("overview", default: (:))
#let alerts     = data.at("alerts", default: (:))
#let dept_stats = data.at("department_stats", default: ())
#let ready_pct  = float(data.at("ready_pct", default: 0))
#let ready_cnt  = data.at("ready_count", default: 0)
#let topper     = data.at("top_performer", default: none)

// ── Executive-dashboard palette (scoped to this template's body only) ────────
#let d-blue      = rgb("#2563EB")
#let d-blue-dark = rgb("#1D4ED8")
#let d-border    = rgb("#E2E8F0")
#let d-text      = rgb("#0F172A")
#let d-text2     = rgb("#475569")
#let d-muted     = rgb("#94A3B8")
#let d-success   = rgb("#16A34A")
#let d-warning   = rgb("#EAB308")
#let d-orange    = rgb("#F97316")
#let d-danger    = rgb("#DC2626")
#let d-purple    = rgb("#7C3AED")
#let d-lime      = rgb("#84CC16")

#let band-color(s) = {
  let n = if type(s) == float { s } else { float(s) }
  if n >= 90 { d-success }
  else if n >= 70 { d-lime }
  else if n >= 50 { d-warning }
  else if n >= 30 { d-orange }
  else { d-danger }
}

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 9.5pt, fill: c-dark)
#set par(leading: 0.6em)

#report-header(data, "Analytics",
  subtitle: data.at("subtitle", default: ""))

// ── KPI card ──────────────────────────────────────────────────────────────────
#let kpi-card(label, value, accent: d-blue) = block(
  width: 100%, fill: none, stroke: (paint: c-border, thickness: 0.5pt),
  radius: 7pt, inset: 10pt, breakable: false,
)[
  #text(size: 8pt, fill: c-muted)[#label]
  #v(4pt)
  #text(size: 16pt, weight: "bold", fill: c-dark)[#value]
]

#let completion = calc.round(float(overview.at("avg_assessment_completion_rate", default: 0)))
#let avg_score  = overview.at("avg_vyaasa_score", default: 0)
#let highest    = overview.at("highest_vyaasa_score", default: 0)
#let topper_val = if topper != none { str(calc.round(float(topper.at("score", default: 0)))) } else { "—" }
#let topper_lbl = if topper != none { "Top Performer · " + topper.at("name", default: "") } else { "Top Performer" }

#grid(columns: (1fr, 1fr, 1fr, 1fr), rows: (auto, auto), column-gutter: 8pt, row-gutter: 8pt,
  kpi-card("Total Students", str(overview.at("total_all_students", default: 0)), accent: d-blue),
  kpi-card("Verified Students", str(overview.at("verified", default: 0)), accent: d-blue-dark),
  kpi-card("Assessment Completion", str(completion) + "%", accent: d-purple),
  kpi-card("Placement Ready", str(calc.round(ready_pct)) + "%", accent: d-success),
  kpi-card("Average AI8 Score", str(avg_score), accent: d-blue),
  kpi-card("Highest Score", str(highest), accent: d-lime),
  kpi-card("Fully Assessed", str(overview.at("all_assessments_completed", default: 0)), accent: d-warning),
  kpi-card(topper_lbl, topper_val, accent: d-orange),
)

#v(12pt)

// ── Two-column main content ──────────────────────────────────────────────────
#grid(columns: (7fr, 3fr), column-gutter: 12pt,
  // ── Left: Department Performance table ───────────────────────────────────
  block[
    #text(size: 12pt, weight: "semibold", fill: d-text)[Department Performance]
    #v(8pt)
    #block(
      width: 100%, fill: none, stroke: (paint: d-border, thickness: 0.5pt),
      radius: 10pt, clip: true,
    )[
      #block(fill: none, width: 100%, inset: (x: 12pt, y: 7pt), stroke: (bottom: (paint: d-border, thickness: 0.5pt)))[
        #grid(columns: (1fr, 60pt, 60pt),
          text(size: 8.5pt, weight: "bold", fill: d-text2)[Department],
          align(center, text(size: 8.5pt, weight: "bold", fill: d-text2)[Students]),
          align(center, text(size: 8.5pt, weight: "bold", fill: d-text2)[Avg. Score]),
        )
      ]
      #if dept_stats.len() > 0 {
        for (idx, dept) in dept_stats.enumerate() {
          let name  = dept.at("department", default: "Unknown")
          let count = dept.at("student_count", default: 0)
          let avg   = float(dept.at("avg_vyaasa_score", default: 0))
          let col   = band-color(avg)
          let last  = idx == dept_stats.len() - 1

          block(
            fill: none, width: 100%, inset: (x: 12pt, y: 8pt),
            stroke: if not last { (bottom: (paint: d-border, thickness: 0.4pt)) } else { none },
          )[
            #grid(columns: (1fr, 60pt, 60pt), align: horizon,
              text(size: 9pt, weight: "medium", fill: d-text)[#name],
              align(center, text(size: 9pt, fill: d-text2)[#count]),
              align(center, text(size: 9pt, weight: "bold", fill: col)[#calc.round(avg)]),
            )
          ]
        }
      } else {
        block(width: 100%, inset: (x: 12pt, y: 14pt))[
          #align(center, text(size: 9pt, fill: d-muted)[No department data available.])
        ]
      }
    ]
  ],

  // ── Right: Intervention Center + Quick Summary ───────────────────────────
  block[
    #text(size: 12pt, weight: "semibold", fill: d-text)[Needs Attention]
    #v(8pt)
    #let attention-row(label, count, tint) = block(
      width: 100%, fill: tint.lighten(85%), radius: 8pt, inset: (x: 10pt, y: 8pt), below: 6pt,
    )[
      #grid(columns: (5pt, 1fr, auto), column-gutter: 8pt, align: horizon,
        block(width: 5pt, height: 5pt, fill: tint, radius: 2.5pt)[],
        text(size: 9pt, weight: "medium", fill: d-text)[#label],
        text(size: 12pt, weight: "bold", fill: tint)[#count],
      )
    ]
    #attention-row("Low Performers", str(alerts.at("low_performers", default: 0)), d-danger)
    #attention-row("Incomplete Profiles", str(alerts.at("incomplete_profiles", default: 0)), d-orange)
    #attention-row("Not Started", str(alerts.at("not_started", default: 0)), d-muted)
    #attention-row("Integrity Flags", str(alerts.at("integrity_flags", default: 0)), d-purple)

    #v(10pt)
    #text(size: 12pt, weight: "semibold", fill: d-text)[Quick Summary]
    #v(8pt)
    #block(
      width: 100%, fill: none, stroke: (paint: d-border, thickness: 0.5pt),
      radius: 10pt, inset: 12pt,
    )[
      #let summary-row(label, val) = {
        grid(columns: (1fr, auto), gutter: 6pt,
          text(size: 9pt, fill: d-text2)[#label],
          align(right, text(size: 9pt, weight: "bold", fill: d-text)[#val]),
        )
        v(7pt)
      }
      #summary-row("Average Score", str(avg_score))
      #summary-row("Highest Score", str(highest))
      #summary-row("Completion Rate", str(completion) + "%")
      #summary-row("Placement Ready", str(calc.round(ready_pct)) + "% (" + str(ready_cnt) + ")")
    ]
  ],
)
