#import "_shared.typ": *

#let data    = json(sys.inputs.at("datafile"))
#let funnel  = data.at("funnel", default: ())
#let depts   = data.at("departments", default: ())
#let alerts  = data.at("alerts", default: (:))
#let insights = data.at("insights", default: ())

// ── Premium dashboard palette (scoped to this template) ──────────────────────
#let p-primary  = rgb("#2563EB")
#let p-success  = rgb("#22C55E")
#let p-warning  = rgb("#F59E0B")
#let p-danger   = rgb("#EF4444")
#let p-purple   = rgb("#8B5CF6")
#let p-text     = rgb("#0F172A")
#let p-text2    = rgb("#64748B")
#let p-border   = rgb("#E2E8F0")

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 9.5pt, fill: p-text)
#set par(leading: 0.6em)

#report-header(data, "Placement Readiness",
  subtitle: data.at("subtitle", default: ""))

// ── KPI glass tiles (from the placement funnel) ───────────────────────────────
#let kpi-tile(label, value, caption) = block(
  width: 100%, fill: none, stroke: (paint: p-border, thickness: 0.6pt),
  radius: 12pt, inset: 12pt, breakable: false,
)[
  #text(size: 20pt, weight: "bold", fill: p-text)[#value]
  #v(3pt)
  #text(size: 8pt, weight: "medium", fill: p-text2)[#label]
  #v(2pt)
  #text(size: 6.5pt, fill: p-text2.lighten(15%))[#caption]
]

#grid(columns: (1fr, 1fr, 1fr, 1fr), column-gutter: 8pt,
  ..funnel.map((s) => kpi-tile(s.at("label", default: ""), str(s.at("count", default: 0)), s.at("caption", default: ""))),
)

#v(14pt)

// ── Two-column body ──────────────────────────────────────────────────────────
#grid(columns: (6fr, 4fr), column-gutter: 14pt,

  // ── Left: Department Ranking ────────────────────────────────────────────
  block[
    #text(size: 12pt, weight: "semibold", fill: p-text)[Department Ranking]
    #v(2pt)
    #text(size: 7.5pt, fill: p-text2)[Sorted by highest average score]
    #v(8pt)
    #let status-pill(label, color) = {
      let words = label.split(" ")
      box(fill: color.lighten(85%), radius: 6pt, inset: (x: 7pt, y: 3pt))[
        #align(center, text(size: 6.5pt, weight: "bold", fill: color)[
          #for (i, w) in words.enumerate() {
            if i > 0 { linebreak() }
            w
          }
        ])
      ]
    }
    #if depts.len() > 0 {
      for (idx, d) in depts.enumerate() {
        let last     = idx == depts.len() - 1
        let color    = rgb(d.at("color", default: "#64748B"))
        let rank_str = "#" + str(d.at("rank", default: 0))
        block(
          width: 100%, inset: (x: 2pt, y: 9pt),
          stroke: if not last { (bottom: (paint: p-border, thickness: 0.5pt)) } else { none },
        )[
          #grid(columns: (22pt, 1fr, auto, 50pt), column-gutter: 8pt, align: horizon,
            text(size: 7.5pt, weight: "bold", fill: p-text2)[#rank_str],
            block[
              #text(size: 9.5pt, weight: "semibold", fill: p-text)[#d.at("name", default: "Unknown")]
              #linebreak()
              #text(size: 7pt, fill: p-text2)[#d.at("count", default: 0) students]
            ],
            status-pill(d.at("status", default: ""), color),
            align(right, text(size: 17pt, weight: "bold", fill: color)[#d.at("avg", default: 0)]),
          )
        ]
      }
    } else {
      block(width: 100%, inset: (y: 14pt))[
        #align(center, text(size: 9pt, fill: p-text2)[No department data available.])
      ]
    }
  ],

  // ── Right: Attention + Insights ──────────────────────────────────────────
  block[
    #text(size: 12pt, weight: "semibold", fill: p-text)[Students Requiring Attention]
    #v(8pt)
    #let alert-card(count, label, color) = block(
      width: 100%, fill: none, stroke: (paint: p-border, thickness: 0.6pt), radius: 10pt, inset: 10pt, breakable: false,
    )[
      #text(size: 17pt, weight: "bold", fill: p-text)[#count]
      #v(1pt)
      #text(size: 7pt, fill: p-text2)[#label]
    ]
    #grid(columns: (1fr, 1fr), column-gutter: 8pt, row-gutter: 8pt,
      alert-card(str(alerts.at("low_performers", default: 0)), "Low Performers", p-danger),
      alert-card(str(alerts.at("incomplete_profiles", default: 0)), "Incomplete Profiles", p-warning),
      alert-card(str(alerts.at("not_started", default: 0)), "Not Started", rgb("#334155")),
      alert-card(str(alerts.at("integrity_flags", default: 0)), "Integrity Flags", p-purple),
    )

    #v(14pt)
    #text(size: 12pt, weight: "semibold", fill: p-text)[Key Insights]
    #v(8pt)
    #let insight-card(title, body) = block(
      width: 100%, fill: none, stroke: (paint: p-border, thickness: 0.6pt),
      radius: 10pt, inset: (x: 10pt, y: 9pt), below: 7pt, breakable: false,
    )[
      #text(size: 8.5pt, weight: "bold", fill: p-text)[#title]
      #v(2pt)
      #text(size: 8pt, fill: p-text2)[#body]
    ]
    #for i in insights {
      insight-card(i.at("title", default: ""), i.at("body", default: ""))
    }
  ],
)
