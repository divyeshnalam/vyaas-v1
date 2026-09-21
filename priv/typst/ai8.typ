#import "_shared.typ": *

#let data  = json(sys.inputs.at("datafile"))
#let index = float(data.at("index", default: 0))
#let col   = score-color(index)

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 10pt, fill: c-dark)
#set par(leading: 0.6em)

#report-header(data, "AI8 Employability Profile",
  subtitle: "Comprehensive assessment across 8 dimensions")

// ── AI8 Index ────────────────────────────────────────────────────────────────
#card[
  #grid(columns: (auto, 1fr), gutter: 18pt, align: horizon,
    score-circle(index, size: 70pt),
    block[
      #text(size: 28pt, weight: "bold", fill: col)[#calc.round(index)]
      #text(size: 12pt, fill: c-muted)[out of 100 · AI8 Index]
      #h(8pt)
      #perf-badge(data.at("performance_label", default: ""), col)
      #v(6pt)
      #let completion = data.at("completion", default: none)
      #if completion != none {
        text(size: 9pt, fill: c-muted)[Assessment completion: #completion%]
      }
    ]
  )
]

// ── Dimension Scores ──────────────────────────────────────────────────────────
#let dims = data.at("dims", default: ())
#if dims.len() > 0 {
  card(title: "Dimension Breakdown")[
    #for dim in dims {
      let sc = float(dim.at("score", default: 0))
      score-bar(dim.at("label", default: ""), sc)
    }
  ]
}

// ── Strength & Opportunity ────────────────────────────────────────────────────
#let strength    = data.at("strength", default: none)
#let opportunity = data.at("opportunity", default: none)
#if strength != none or opportunity != none {
  grid(columns: (1fr, 1fr), gutter: 10pt,
    card(title: "Top Strength")[
      #if strength != none {
        let sc = float(strength.at("score", default: 0))
        text(size: 11pt, weight: "bold", fill: c-green)[#strength.at("label", default: "")]
        v(4pt)
        text(size: 9pt, fill: c-muted)[Score: #calc.round(sc)/100]
      } else {
        text(size: 9pt, fill: c-muted)[Complete more assessments to see your top strength.]
      }
    ],
    card(title: "Growth Opportunity")[
      #if opportunity != none {
        let sc = float(opportunity.at("score", default: 0))
        text(size: 11pt, weight: "bold", fill: c-amber)[#opportunity.at("label", default: "")]
        v(4pt)
        text(size: 9pt, fill: c-muted)[Score: #calc.round(sc)/100]
      } else {
        text(size: 9pt, fill: c-muted)[Complete more assessments to identify growth areas.]
      }
    ]
  )
}

