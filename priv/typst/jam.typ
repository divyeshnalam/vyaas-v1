#import "_shared.typ": *

#let data  = json(sys.inputs.at("datafile"))
#let score = float(data.at("final_score", default: 0))
#let col   = score-color(score)

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 10pt, fill: c-dark)
#set par(leading: 0.6em)

#report-header(data, "JAM Assessment Report",
  subtitle: "Just-A-Minute · Communication & Fluency")

// ── Score Hero ────────────────────────────────────────────────────────────────
#card[
  #grid(columns: (auto, 1fr), gutter: 18pt, align: horizon,
    score-circle(score),
    block[
      #text(size: 26pt, weight: "bold", fill: col)[#calc.round(score)/100]
      #h(8pt)
      #perf-badge(data.at("performance_label", default: ""), col)
      #v(6pt)
      #let topic = data.at("topic_title", default: "")
      #if topic != none and topic != "" {
        text(size: 9pt, fill: c-muted)[Topic: #topic]
        linebreak()
      }
      #let dur = int(data.at("speech_duration", default: 0))
      #let wc  = data.at("word_count", default: 0)
      #text(size: 9pt, fill: c-muted)[
        Duration: #str(calc.floor(dur / 60)):#str(calc.rem(dur, 60)) · #wc words
      ]
    ]
  )
]

// ── Dimension Scores ──────────────────────────────────────────────────────────
#card(title: "Dimension Scores")[
  #score-bar("Clarity", data.at("clarity", default: 0))
  #score-bar("Structure", data.at("structure", default: 0))
  #score-bar("Relevance", data.at("relevance", default: 0))
  #score-bar("Impact", data.at("impact", default: 0))
  #score-bar("Confidence", data.at("confidence", default: 0))
]

// ── Strengths / Improvements ──────────────────────────────────────────────────
#let strengths    = data.at("strengths", default: ())
#let improvements = data.at("improvements", default: ())
#if strengths.len() > 0 or improvements.len() > 0 {
  grid(columns: (1fr, 1fr), gutter: 10pt,
    card(title: "Strengths")[
      #if strengths.len() > 0 { bullet-list(strengths) } else { text(size: 9pt, fill: c-muted)[—] }
    ],
    card(title: "Areas for Improvement")[
      #if improvements.len() > 0 { bullet-list(improvements) } else { text(size: 9pt, fill: c-muted)[—] }
    ]
  )
}

// ── Overall Summary ───────────────────────────────────────────────────────────
#let summary = data.at("overall_summary", default: "")
#if summary != none and summary != "" {
  card(title: "Overall Summary")[
    #block[#set par(leading: 0.8em); #text(size: 9pt, fill: rgb("#374151"))[#summary]]
  ]
}

// ── Topic ─────────────────────────────────────────────────────────────────────
#let topic_exp = data.at("topic_explanation", default: "")
#if topic_exp != none and topic_exp != "" {
  card(title: "Topic")[
    #text(size: 9pt, fill: rgb("#374151"))[#topic_exp]
  ]
}

