#import "_shared.typ": *

#let data  = json(sys.inputs.at("datafile"))
#let total = float(data.at("total_score", default: 0))
#let col   = score-color(total)

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 10pt, fill: c-dark)
#set par(leading: 0.6em)

#let role = data.at("role_title", default: "Mini Project")
#let spec = data.at("specialization", default: "")
#let subtitle = if spec != none and spec != "" { role + " · " + spec } else { role }
#report-header(data, "Domain Mini Project", subtitle: subtitle)

// ── Overall Score ───────────────────────────────────────────────────────────────
#card[
  #grid(columns: (auto, 1fr), gutter: 18pt, align: horizon,
    score-circle(total),
    block[
      #text(size: 26pt, weight: "bold", fill: col)[#calc.round(total)/100]
      #h(8pt)
      #perf-badge(data.at("performance_label", default: ""), col)
      #let band = data.at("grade_band", default: "")
      #if band != none and band != "" {
        h(6pt)
        perf-badge(band, c-blue)
      }
    ]
  )
]

// ── Competency Breakdown ────────────────────────────────────────────────────────
#let indexes = data.at("indexes", default: ())
#if indexes.len() > 0 {
  card(title: "Competency Breakdown")[
    #for item in indexes {
      let label  = item.at(0, default: "")
      let sc     = float(item.at(1, default: 0))
      let weight = item.at(2, default: 0)
      score-bar(label + " (weight " + str(int(weight)) + "%)", sc)
    }
  ]
}

// ── Strengths / Improvements ──────────────────────────────────────────────────
#let strengths    = data.at("strengths", default: ())
#let improvements = data.at("improvements", default: ())
#grid(columns: (1fr, 1fr), gutter: 10pt,
  card(title: "Strengths")[
    #if strengths.len() > 0 { bullet-list(strengths) } else { text(size: 9pt, fill: c-muted)[—] }
  ],
  card(title: "Areas for Improvement")[
    #if improvements.len() > 0 { bullet-list(improvements) } else { text(size: 9pt, fill: c-muted)[—] }
  ]
)

// ── Evaluator Report ────────────────────────────────────────────────────────────
#let summary = data.at("summary", default: "")
#if summary != none and summary != "" {
  card(title: "Evaluator Report")[
    #block[#set par(leading: 0.8em); #text(size: 9pt, fill: rgb("#374151"))[#summary]]
  ]
}

