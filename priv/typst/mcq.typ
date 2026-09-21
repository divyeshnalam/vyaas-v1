#import "_shared.typ": *

#let data = json(sys.inputs.at("datafile"))
#let pct  = float(data.at("percentage", default: 0))
#let col  = score-color(pct)

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 10pt, fill: c-dark)
#set par(leading: 0.6em)

#report-header(data, "MCQ Assessment Report",
  subtitle: data.at("assessment", default: (:)).at("title", default: ""))

// ── Score Hero ───────────────────────────────────────────────────────────────
#card[
  #grid(columns: (auto, 1fr), gutter: 18pt, align: horizon,
    score-circle(pct),
    block[
      #text(size: 26pt, weight: "bold", fill: col)[#calc.round(pct)%]
      #h(8pt)
      #perf-badge(data.at("performance_label", default: ""), col)
      #v(6pt)
      #text(size: 9pt, fill: c-muted)[
        Score: #data.at("score", default: 0) / #data.at("total_marks", default: 0)
        · Attempted #(int(data.at("correct", default: 0)) + int(data.at("wrong", default: 0))) of #data.at("total_questions", default: 0)
      ]
    ]
  )
]

// ── Breakdown stats ───────────────────────────────────────────────────────────
#card(title: "Score Breakdown")[
  #grid(columns: (1fr, 1fr, 1fr, 1fr, 1fr), gutter: 8pt,
    // Correct
    block(fill: rgb("#f0fdf4"), stroke: (paint: rgb("#bbf7d0"), thickness: 0.5pt), radius: 6pt, inset: 8pt, width: 100%)[
      #align(center)[
        #text(size: 14pt, weight: "bold", fill: c-green)[#data.at("correct", default: 0)]
        #linebreak()
        #text(size: 7.5pt, fill: c-muted)[CORRECT]
      ]
    ],
    // Wrong
    block(fill: rgb("#fef2f2"), stroke: (paint: rgb("#fecaca"), thickness: 0.5pt), radius: 6pt, inset: 8pt, width: 100%)[
      #align(center)[
        #text(size: 14pt, weight: "bold", fill: c-red)[#data.at("wrong", default: 0)]
        #linebreak()
        #text(size: 7.5pt, fill: c-muted)[WRONG]
      ]
    ],
    // Skipped
    block(fill: c-bg, stroke: (paint: c-border, thickness: 0.5pt), radius: 6pt, inset: 8pt, width: 100%)[
      #align(center)[
        #text(size: 14pt, weight: "bold", fill: c-muted)[#data.at("unanswered", default: 0)]
        #linebreak()
        #text(size: 7.5pt, fill: c-muted)[SKIPPED]
      ]
    ],
    // Negative
    block(fill: rgb("#fff7ed"), stroke: (paint: rgb("#fed7aa"), thickness: 0.5pt), radius: 6pt, inset: 8pt, width: 100%)[
      #align(center)[
        #text(size: 14pt, weight: "bold", fill: c-orange2)[#data.at("negative_marks", default: 0)]
        #linebreak()
        #text(size: 7.5pt, fill: c-muted)[NEGATIVE]
      ]
    ],
    // Final
    block(fill: rgb("#eff6ff"), stroke: (paint: rgb("#bfdbfe"), thickness: 0.5pt), radius: 6pt, inset: 8pt, width: 100%)[
      #align(center)[
        #text(size: 14pt, weight: "bold", fill: c-blue)[#data.at("score", default: 0)]
        #linebreak()
        #text(size: 7.5pt, fill: c-muted)[FINAL]
      ]
    ],
  )
]

// ── Performance ───────────────────────────────────────────────────────────────
#grid(columns: (1fr, 1fr), gutter: 10pt,
  card(title: "Performance Metrics")[
    #score-bar("Accuracy", data.at("accuracy", default: 0))
    #score-bar("Completion", data.at("completion", default: 0), color: c-blue)
  ],
  card(title: "Time Analysis")[
    #let secs = int(data.at("time_taken", default: 0))
    #kv-row("Time Taken", str(calc.floor(secs / 60)) + " min " + str(calc.rem(secs, 60)) + " s")
    #kv-row("Avg / Question", str(data.at("avg_time_per_question", default: 0)) + " min")
    #kv-row("Total Questions", str(data.at("total_questions", default: 0)))
  ]
)

