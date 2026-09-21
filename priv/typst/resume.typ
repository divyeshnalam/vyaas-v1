#import "_shared.typ": *

#let data  = json(sys.inputs.at("datafile"))
#let score = float(data.at("score", default: 0))
#let col   = score-color(score)

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 10pt, fill: c-dark)
#set par(leading: 0.6em)

#report-header(data, "Resume ATS Analysis",
  subtitle: "Completeness · Relevance · Sanity Check")

// ── ATS Score ────────────────────────────────────────────────────────────────
#card[
  #grid(columns: (auto, 1fr), gutter: 18pt, align: horizon,
    score-circle(score),
    block[
      #text(size: 26pt, weight: "bold", fill: col)[#calc.round(score)/100]
      #h(8pt)
      #perf-badge(data.at("performance_label", default: ""), col)
      #v(6pt)
      #let exp = data.at("total_experience", default: none)
      #if exp != none and exp != "" {
        text(size: 9pt, fill: c-muted)[Experience: #exp]
        linebreak()
      }
      #let work_count = data.at("experience_count", default: 0)
      #let proj_count = data.at("projects_count", default: 0)
      #let edu_count  = data.at("education_count", default: 0)
      #text(size: 9pt, fill: c-muted)[
        #work_count work entries · #proj_count projects · #edu_count education entries
      ]
    ]
  )
]

// ── Sub-scores ────────────────────────────────────────────────────────────────
#let subscores = data.at("subscores", default: ())
#if subscores.len() > 0 {
  card(title: "Score Components")[
    #for item in subscores {
      let label = item.at(0, default: "")
      let sc    = float(item.at(1, default: 0))
      score-bar(label, sc)
    }
  ]
}

// ── Summary ───────────────────────────────────────────────────────────────────
#let summary = data.at("summary_text", default: "")
#if summary != none and summary != "" {
  card(title: "Professional Summary")[
    #block[#set par(leading: 0.8em); #text(size: 9pt, fill: rgb("#374151"))[#summary]]
  ]
}

// ── Skills ────────────────────────────────────────────────────────────────────
#let tech_skills = data.at("technical_skills", default: ())
#let soft_skills = data.at("non_technical_skills", default: ())
#if tech_skills.len() > 0 or soft_skills.len() > 0 {
  grid(columns: (1fr, 1fr), gutter: 10pt,
    card(title: "Technical Skills")[
      #if tech_skills.len() > 0 {
        for skill in tech_skills {
          box(
            fill: rgb("#eff6ff"),
            stroke: (paint: rgb("#bfdbfe"), thickness: 0.5pt),
            radius: 4pt,
            inset: (x: 6pt, y: 2pt),
          )[#text(size: 8pt, fill: c-blue)[#skill]]
          h(4pt)
        }
      } else {
        text(size: 9pt, fill: c-muted)[—]
      }
    ],
    card(title: "Non-Technical Skills")[
      #if soft_skills.len() > 0 {
        for skill in soft_skills {
          box(
            fill: rgb("#f0fdf4"),
            stroke: (paint: rgb("#bbf7d0"), thickness: 0.5pt),
            radius: 4pt,
            inset: (x: 6pt, y: 2pt),
          )[#text(size: 8pt, fill: c-green)[#skill]]
          h(4pt)
        }
      } else {
        text(size: 9pt, fill: c-muted)[—]
      }
    ]
  )
}

// ── Improvements ─────────────────────────────────────────────────────────────
#let improvements = data.at("improvements", default: ())
#if improvements.len() > 0 {
  card(title: "Recommended Improvements")[
    #bullet-list(improvements)
  ]
}

