#import "_shared.typ": *

#let data    = json(sys.inputs.at("datafile"))
#let overall = float(data.at("overall_score", default: 0))
#let col     = score-color(overall)

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 10pt, fill: c-dark)
#set par(leading: 0.6em)

#report-header(data, "Psychometric Assessment",
  subtitle: "Big Five Personality Profile")

// ── Overall ───────────────────────────────────────────────────────────────────
#card[
  #grid(columns: (auto, 1fr), gutter: 18pt, align: horizon,
    score-circle(overall),
    block[
      #text(size: 26pt, weight: "bold", fill: col)[#calc.round(overall)/100]
      #h(8pt)
      #perf-badge(data.at("performance_label", default: ""), col)
      #v(6pt)
      #let summary = data.at("overall_summary", default: "")
      #if summary != none and summary != "" {
        text(size: 9pt, fill: c-muted)[#summary]
      }
    ]
  )
]

// ── Big Five Traits ───────────────────────────────────────────────────────────
#let scores = data.at("scores", default: (:))
#card(title: "Big Five Trait Scores")[
  #score-bar("Openness", float(scores.at("openness", default: 0)) * 20.0)
  #score-bar("Conscientiousness", float(scores.at("conscientiousness", default: 0)) * 20.0)
  #score-bar("Extraversion", float(scores.at("extraversion", default: 0)) * 20.0)
  #score-bar("Agreeableness", float(scores.at("agreeableness", default: 0)) * 20.0)
  #score-bar("Neuroticism", float(scores.at("neuroticism", default: 0)) * 20.0)
  #text(size: 7.5pt, fill: c-muted)[Raw scores (1–5) scaled to 100 for display.]
]

// ── AI8 Composites ────────────────────────────────────────────────────────────
#let comp = data.at("composites", default: (:))
#card(title: "Competency Composites")[
  #score-bar("Work Ethics & Reliability", float(comp.at("work_ethics", default: 0)))
  #score-bar("Teamwork & Collaboration",  float(comp.at("collaboration", default: 0)))
  #score-bar("Initiative & Leadership",   float(comp.at("leadership", default: 0)))
]

// ── Strengths / Development ───────────────────────────────────────────────────
#let strengths = data.at("strengths", default: ())
#let dev       = data.at("development_areas", default: ())
#grid(columns: (1fr, 1fr), gutter: 10pt,
  card(title: "Strengths")[
    #if strengths.len() > 0 { bullet-list(strengths) } else { text(size: 9pt, fill: c-muted)[—] }
  ],
  card(title: "Development Areas")[
    #if dev.len() > 0 { bullet-list(dev) } else { text(size: 9pt, fill: c-muted)[—] }
  ]
)

// ── Suggestions ───────────────────────────────────────────────────────────────
#let suggestions = data.at("suggestions", default: ())
#if suggestions.len() > 0 {
  card(title: "Suggestions")[
    #bullet-list(suggestions)
  ]
}

