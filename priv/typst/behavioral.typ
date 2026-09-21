#import "_shared.typ": *

#let data    = json(sys.inputs.at("datafile"))
#let overall = float(data.at("overall_score", default: 0))
#let col     = score-color(overall)

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 10pt, fill: c-dark)
#set par(leading: 0.6em)

#report-header(data, "Behavioral Assessment",
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
      #let summary = data.at("summary", default: "")
      #if summary != none and summary != "" {
        text(size: 9pt, fill: c-muted)[#summary]
      }
    ]
  )
]

// ── Competencies ──────────────────────────────────────────────────────────────
#let scores   = data.at("scores", default: (:))
#let reasoning = data.at("reasoning", default: (:))

#card(title: "Competency Scores")[
  #let dims = (
    ("Work Ethics & Reliability",  "work_ethics",  "work_ethics_and_reliability"),
    ("Teamwork & Collaboration",   "teamwork",     "teamwork_and_collaboration"),
    ("Adaptability & Learning",    "adaptability", "adaptability_and_learning"),
    ("Leadership Potential",       "leadership",   "leadership_potential"),
    ("Communication Skills",       "communication","communication_skills"),
  )
  #for (label, skey, rkey) in dims {
    let sc = float(scores.at(skey, default: 0))
    score-bar(label, sc)
    let reason = reasoning.at(rkey, default: none)
    if reason != none and reason != "" {
      text(size: 8pt, fill: c-muted)[#reason]
      v(6pt)
    }
  }
]

// ── Strengths / Development ───────────────────────────────────────────────────
#let strengths = data.at("strengths", default: ())
#let areas     = data.at("areas_for_development", default: ())
#if strengths.len() > 0 or areas.len() > 0 {
  grid(columns: (1fr, 1fr), gutter: 10pt,
    card(title: "Strengths")[
      #if strengths.len() > 0 { bullet-list(strengths) } else { text(size: 9pt, fill: c-muted)[—] }
    ],
    card(title: "Areas for Development")[
      #if areas.len() > 0 { bullet-list(areas) } else { text(size: 9pt, fill: c-muted)[—] }
    ]
  )
}

// ── Scenario Responses ────────────────────────────────────────────────────────
#let scenarios = data.at("completed_scenarios", default: ())
#if scenarios != none and scenarios.len() > 0 {
  card(title: "Scenario Responses")[
    #for s in scenarios {
      let q = s.at("scenario_question", default: s.at("question", default: ""))
      let r = s.at("candidate_response", default: s.at("response", default: ""))
      block(
        fill: none,
        stroke: (paint: c-border, thickness: 0.5pt),
        radius: 6pt, inset: 10pt, below: 8pt, width: 100%,
      )[
        #text(size: 9pt, weight: "semibold", fill: c-dark)[#q]
        #if r != none and r != "" {
          v(5pt)
          text(size: 8.5pt, fill: rgb("#374151"))[#r]
        }
      ]
    }
  ]
}

