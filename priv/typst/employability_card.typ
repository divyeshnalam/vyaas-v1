#import "_shared.typ": *

// Two-page mirror of the on-screen flippable employability card
// (VyaasaCampusWeb.Components.Student.CredentialsComponent.employability_card/1)
// — front (branded cover) on page 1, back (score + tier + QR + signature
// block) on page 2 — rather than the full multi-dimension AI8 report.
// Waves/laurel/icons below are extracted 1:1 from that component's inline
// SVGs; if the component's design changes, these assets need updating too.

#let data       = json(sys.inputs.at("datafile"))
#let score      = float(data.at("score", default: 0))
#let tier       = data.at("tier", default: (:))
#let student_name = data.at("student_name", default: "")
#let role       = data.at("role", default: "")
#let cert_id    = data.at("cert_id", default: "")
#let qr_path    = data.at("_qr_path", default: "")
#let seal_path  = data.at("_seal_path", default: "")
#let logo_path  = data.at("_logo_path", default: "")
#let mark_path  = data.at("_mark_path", default: "")

#let c-brand       = rgb("#EF6C00")
#let c-brand-light = rgb("#FEA337")
#let icon-chip(icon_path) = box(width: 6mm, height: 6mm, radius: 1.3mm, fill: rgb("#FFF7ED"))[
  #align(center + horizon)[#image(icon_path, width: 3.4mm)]
]

#let metric-cell(title, subtitle) = align(left)[
  #block[
    #set par(leading: 3.5pt)
    #text(size: 9pt, weight: "bold", fill: c-dark)[#upper(title)]
    #linebreak()
    #text(size: 7pt, fill: c-muted)[#subtitle]
  ]
]

// One grid for all three rows (not three stacked blocks) — that way each
// row's icon and text are centered against that row's own height, and the
// gap between rows can't drift/accumulate the way separately-placed blocks did.

#let metric-rows(rows) = grid(
  columns: (6mm, 1fr), column-gutter: 2.2mm, row-gutter: 7pt,
  align: horizon, ..rows.map(((icon_path, title, subtitle)) => (icon-chip(icon_path), metric-cell(title, subtitle))).flatten() )

// Faint diagonal "VYAASA VYAASA" watermark, mirroring the card back's CSS
// (`text-[#EF6C0008] -rotate-18`), at three staggered positions.
#let watermark-line = rotate(-18deg, text(size: 22pt, weight: 900, fill: rgb("#EF6C0008"))[VYAASA VYAASA])
#let card-watermark() = {
  place(top + left, dx: 8mm, dy: 10mm, watermark-line)
  place(left + horizon, dx: -18mm, watermark-line)
  place(bottom + left, dx: 12mm, dy: -6mm, watermark-line)
}

#let bl-waves() = {
  place(bottom + left, image("employability_card/wave-bl-1.svg", width: 66mm))
  place(bottom + left, image("employability_card/wave-bl-2.svg", width: 50mm))
}

// ── Page 1 — Front ───────────────────────────────────────────────────────────
#set page(width: 190mm, height: 123mm, margin: 0mm, fill: rgb("#FCFBF9"))

#bl-waves()
#place(top + right, image("employability_card/wave-tr-1.svg", width: 70mm))
#place(top + right, image("employability_card/wave-tr-2.svg", width: 54mm))

#place(center + horizon)[
  #if logo_path != "" {
    image(logo_path, width: 58mm)
  }
]

// ── Page 2 — Back ────────────────────────────────────────────────────────────
#pagebreak()
#set page(fill: rgb("#FEFBF7"))

#card-watermark()
#bl-waves()

#place(top + left, dx: 9mm, dy: 8mm)[
  #if logo_path != "" {
    image(logo_path, height: 15mm)
  }
]

#place(top + right, dx: -9mm, dy: 9mm)[
  #box(
    fill: white,
    stroke: (paint: c-brand-light, thickness: 0.6pt),
    radius: 3pt,
    inset: (x: 7pt, y: 4pt),
  )[
    #grid(columns: (3.6mm, auto), gutter: 1.5mm, align: horizon,
      image("employability_card/icon-shield-check.svg", width: 3.6mm),
      text(size: 8pt, weight: "bold", fill: c-brand)[VYAASA VERIFIED],
    )
  ]
]

#place(center + horizon, dy: -6mm)[
  #grid(columns: (42mm, 0.6pt, 58mm, 0.6pt, 34mm), column-gutter: (8mm, 8mm, 8mm, 8mm), align: horizon,
    align(center)[
      #grid(columns: (9mm, auto, 9mm), gutter: 2mm, align: horizon,
        image("employability_card/score-dots.svg", height: 16mm),
        text(size: 44pt, weight: "bold", fill: c-brand)[#calc.round(score)],
        rotate(180deg, image("employability_card/score-dots.svg", height: 16mm)),
      )
      #v(1pt)
      #grid(columns: (4mm, auto, 4mm), gutter: 2mm, align: horizon,
        box(width: 4mm, height: 0.4mm, fill: c-brand-light),
        text(size: 8pt, fill: c-muted, tracking: 1.5pt)[AI8 SCORE],
        box(width: 4mm, height: 0.4mm, fill: c-brand-light),
      )
    ],
    align(center + horizon)[#line(length: 30mm, angle: 90deg, stroke: 0.6pt + rgb("#EF6C004D"))],
    pad(left: 4mm)[
      #metric-rows((
        ("employability_card/icon-trophy.svg", tier.at("percentile", default: "-"), "Among All Candidates"),
        ("employability_card/icon-trending-up.svg", tier.at("potential", default: "-"), "Employability Tier"),
        ("employability_card/icon-check-badge.svg", tier.at("readiness", default: "-"), "Career Ready Candidate"),
      ))
    ],
    align(center + horizon)[#line(length: 30mm, angle: 90deg, stroke: 0.6pt + rgb("#EF6C004D"))],
    align(center)[
      #if qr_path != "" {
        box(
          fill: white,
          stroke: (paint: c-brand-light, thickness: 0.6pt, dash: "dashed"),
          radius: 4pt, inset: 3pt,
        )[
          #box(width: 32mm, height: 32mm)[
            #image(qr_path, width: 32mm, height: 32mm, scaling: "pixelated")
            #if mark_path != "" {
              place(center + horizon)[
                #box(width: 8.4mm, height: 8.4mm, radius: 4.2mm, fill: white, inset: 0.7mm)[
                  #image(mark_path, width: 100%, height: 100%)
                ]
              ]
            }
          ]
        ]
        v(3pt)
        text(size: 6.5pt, weight: "semibold", fill: c-brand)[SCAN TO VIEW PROFILE]
      }
    ]
  )
]           

#place(bottom + center, dy: -9mm)[
  #align(center)[
    #box(width: 160mm, height: 0.6pt, fill: c-brand)
    #v(7pt)
    #grid(columns: (auto, auto, auto), gutter: 8pt, align: horizon,
      image("employability_card/laurel.svg", height: 12mm),
      block[
        #align(center)[
          #text(size: 11.5pt, weight: "bold", fill: c-dark)[#upper(student_name)]
          #v(2pt)
          #grid(columns: (8mm, auto, 8mm), gutter: 2mm, align: horizon,
            box(width: 8mm, height: 0.35mm, fill: rgb("#EF6C00B3")),
            text(size: 8pt, fill: rgb("#374151"))[#upper(role)],
            box(width: 8mm, height: 0.35mm, fill: rgb("#EF6C00B3")),
          )
        ]
      ],
      scale(x: -100%)[#image("employability_card/laurel.svg", height: 12mm)],
    )
    #v(5pt)
    #box(stroke: (paint: c-border, thickness: 0.5pt), radius: 8pt, inset: (x: 8pt, y: 3pt))[
      #grid(columns: (3.2mm, auto), gutter: 2mm, align: horizon,
        image("employability_card/icon-identification.svg", width: 3.2mm),
        text(size: 8pt, fill: c-muted)[#cert_id],
      )
    ]
  ]
]

#place(bottom + right, dx: -9mm, dy: -9mm)[
  #if seal_path != "" {
    image(seal_path, width: 17mm)
  }
]
