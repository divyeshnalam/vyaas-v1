#import "_shared.typ": *

#let data    = json(sys.inputs.at("datafile"))
#let overall = float(data.at("overall_score", default: 0))
#let col     = score-color(overall)

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 10pt, fill: c-dark)
#set par(leading: 0.6em)

#report-header(data, "Interview Assessment",
  subtitle: data.at("candidate_name", default: ""))

// ── Overall Score ─────────────────────────────────────────────────────────────
#card[
  #grid(columns: (auto, 1fr), gutter: 18pt, align: horizon,
    score-circle(overall),
    block[
      #text(size: 26pt, weight: "bold", fill: col)[#calc.round(overall)/100]
      #h(8pt)
      #perf-badge(data.at("performance_label", default: ""), col)
      #v(6pt)
      #let summary = data.at("summary_text", default: "")
      #if summary != none and summary != "" {
        text(size: 9pt, fill: c-muted)[#summary]
      }
    ]
  )
]

// ── Competencies ──────────────────────────────────────────────────────────────
#let competency = data.at("competency", default: ())
#if competency.len() > 0 {
  card(title: "Competency Breakdown")[
    #for item in competency {
      let label = item.at(0, default: "")
      let sc    = float(item.at(1, default: 0))
      let wt    = item.at(2, default: "")
      score-bar(label + " (" + wt + ")", sc)
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

// ── Questions ─────────────────────────────────────────────────────────────────
#let questions = data.at("questions", default: ())
#if questions.len() > 0 {
  card(title: "Questions & Responses")[
    #for (idx, q) in questions.enumerate() {
      let qtext = q.at("question", default: q.at("text", default: ""))
      let resp  = q.at("response", default: q.at("answer", default: ""))
      let sc    = q.at("score", default: none)
      block(below: 10pt, width: 100%)[
        #text(size: 9pt, weight: "semibold", fill: c-dark)[Q#(idx + 1): #qtext]
        #if sc != none {
          h(6pt)
          text(size: 8pt, fill: col)[Score: #sc]
        }
        #if resp != none and resp != "" {
          v(4pt)
          text(size: 8.5pt, fill: rgb("#374151"))[#resp]
        }
        #line(length: 100%, stroke: (paint: c-border, thickness: 0.3pt))
      ]
    }
  ]
}

