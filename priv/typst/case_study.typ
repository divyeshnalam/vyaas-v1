#import "_shared.typ": *

#let data  = json(sys.inputs.at("datafile"))
#let total = float(data.at("total_score", default: 0))
#let col   = score-color(total)

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 10pt, fill: c-dark)
#set par(leading: 0.6em)

#let scenario = data.at("scenario_title", default: "Case Study")
#let spec     = data.at("specialization", default: "")
#let subtitle = if spec != none and spec != "" { scenario + " · " + spec } else { scenario }
#report-header(data, "Case Study Assessment", subtitle: subtitle)

// ── Total Score ───────────────────────────────────────────────────────────────
#card[
  #grid(columns: (auto, 1fr), gutter: 18pt, align: horizon,
    score-circle(total),
    block[
      #text(size: 26pt, weight: "bold", fill: col)[#calc.round(total)/100]
      #h(8pt)
      #perf-badge(data.at("performance_label", default: ""), col)
      #v(6pt)
      #let verdict = data.at("verdict", default: "")
      #if verdict != none and verdict != "" {
        text(size: 9pt, fill: c-muted)[#verdict]
      }
    ]
  )
]

// ── Sub-scores ────────────────────────────────────────────────────────────────
#let sub_scores = data.at("scores", default: ())
#if sub_scores.len() > 0 {
  card(title: "Score Breakdown")[
    #for item in sub_scores {
      let label    = item.at(0, default: "")
      let sc       = float(item.at(1, default: 0))
      let max_sc   = float(item.at(2, default: 100))
      let feedback = item.at(3, default: none)
      let pct      = if max_sc > 0 { sc / max_sc * 100.0 } else { 0.0 }
      score-bar(label + " (/" + str(int(max_sc)) + ")", pct)
      if feedback != none and feedback != "" {
        text(size: 8pt, fill: c-muted)[#feedback]
        v(6pt)
      }
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

// ── Summary ───────────────────────────────────────────────────────────────────
#let summary = data.at("summary", default: "")
#if summary != none and summary != "" {
  card(title: "Evaluator Summary")[
    #block[#set par(leading: 0.8em); #text(size: 9pt, fill: rgb("#374151"))[#summary]]
  ]
}

