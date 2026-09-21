#import "_shared.typ": *

#let data     = json(sys.inputs.at("datafile"))
#let depts    = data.at("departments", default: ())
#let tiles    = data.at("summary_tiles", default: ())
#let top_dept = data.at("top_department", default: none)

// ── Premium dashboard palette (scoped to this template) ──────────────────────
#let p-text   = rgb("#0F172A")
#let p-text2  = rgb("#64748B")
#let p-border = rgb("#E2E8F0")

#set page(paper: "a4", margin: (x: 14mm, y: 12mm, bottom: 16mm), background: watermark(data),
  footer: report-footer(data, data.at("generated_at", default: "")))
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "sans-serif"), size: 9.5pt, fill: p-text)
#set par(leading: 0.6em)

#report-header(data, "Specializations",
  subtitle: data.at("subtitle", default: ""))

// ── Summary tiles ─────────────────────────────────────────────────────────────
#let summary-tile(label, value, caption) = block(
  width: 100%, fill: none, stroke: (paint: p-border, thickness: 0.6pt),
  radius: 12pt, inset: 12pt, breakable: false,
)[
  #text(size: 16pt, weight: "bold", fill: p-text)[#value]
  #v(3pt)
  #text(size: 8pt, weight: "medium", fill: p-text2)[#label]
  #v(2pt)
  #text(size: 6.5pt, fill: p-text2.lighten(15%))[#caption]
]

#grid(columns: (1fr, 1fr, 1fr), column-gutter: 8pt,
  ..tiles.map((t) => summary-tile(t.at("label", default: ""), t.at("value", default: ""), t.at("caption", default: ""))),
)

#v(12pt)

// ── Top Specialization spotlight ─────────────────────────────────────────────
#if top_dept != none {
  let color = rgb(top_dept.at("color", default: "#F97316"))
  block(
    width: 100%, fill: none, stroke: (paint: color.lighten(35%), thickness: 0.7pt),
    radius: 14pt, inset: 16pt, breakable: false, below: 16pt,
  )[
    #grid(columns: (1fr, auto), column-gutter: 12pt, align: horizon,
      block[
        #text(size: 7.5pt, weight: "bold", fill: color, tracking: 1pt)[TOP SPECIALIZATION]
        #v(4pt)
        #text(size: 18pt, weight: "bold", fill: p-text)[#top_dept.at("name", default: "—")]
        #v(2pt)
        #text(size: 8pt, fill: p-text2)[#top_dept.at("count", default: 0) students · Top scorer: #top_dept.at("topper", default: "—")]
      ],
      align(right)[
        #text(size: 30pt, weight: "bold", fill: color)[#top_dept.at("avg", default: 0)]
        #v(2pt)
        #text(size: 7.5pt, fill: p-text2)[avg score]
      ],
    )
  ]
}

// ── Specialization ranking ────────────────────────────────────────────────────
#text(size: 12pt, weight: "semibold", fill: p-text)[Specialization Ranking]
#v(2pt)
#text(size: 7.5pt, fill: p-text2)[Sorted by highest average score]
#v(10pt)

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
      width: 100%, inset: (x: 2pt, y: 10pt),
      stroke: if not last { (bottom: (paint: p-border, thickness: 0.5pt)) } else { none },
    )[
      #grid(columns: (24pt, 1fr, auto, 60pt), column-gutter: 10pt, align: horizon,
        text(size: 9.5pt, weight: "bold", fill: p-text2)[#rank_str],
        block[
          #text(size: 10pt, weight: "semibold", fill: p-text)[#d.at("name", default: "Unknown")]
          #linebreak()
          #text(size: 7pt, fill: p-text2)[#d.at("count", default: 0) students · Top: #d.at("topper", default: "—")]
        ],
        status-pill(d.at("status", default: ""), color),
        align(right, text(size: 19pt, weight: "bold", fill: color)[#d.at("avg", default: 0)]),
      )
    ]
  }
} else {
  block(width: 100%, inset: (y: 14pt))[
    #align(center, text(size: 9pt, fill: p-text2)[No specialization data available.])
  ]
}
