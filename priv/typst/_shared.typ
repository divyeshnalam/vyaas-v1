// Shared colors, components, and layout helpers for all Vyaasa report templates.

// ── Palette ─────────────────────────────────────────────────────────────────
#let c-orange  = rgb("#f97316")
#let c-dark    = rgb("#111827")
#let c-muted   = rgb("#6b7280")
#let c-border  = rgb("#e5e7eb")
#let c-bg      = rgb("#f9fafb")
#let c-white   = rgb("#ffffff")
#let c-green   = rgb("#16a34a")
#let c-amber   = rgb("#d97706")
#let c-red     = rgb("#dc2626")
#let c-blue    = rgb("#2563eb")
#let c-orange2 = rgb("#ea580c")

// ── Score → color ────────────────────────────────────────────────────────────
#let score-color(s) = {
  let n = if type(s) == float { s } else { float(s) }
  if n >= 75 { c-green }
  else if n >= 60 { c-amber }
  else if n >= 40 { c-orange2 }
  else { c-red }
}

// ── Score circle ─────────────────────────────────────────────────────────────
#let score-circle(score, size: 64pt) = {
  let col = score-color(score)
  let label = calc.round(if type(score) == float { score } else { float(score) })
  box(
    width: size, height: size,
    fill: col, radius: size / 2,
    clip: true, inset: 0pt,
  )[
    #align(center + horizon)[
      #text(weight: "bold", size: size * 0.30, fill: white)[#label]
    ]
  ]
}

// ── Horizontal score bar ─────────────────────────────────────────────────────
#let score-bar(label, score, max: 100, color: none) = {
  let n    = if type(score) == float { score } else { float(int(score)) }
  let m    = if type(max) == float { max } else { float(int(max)) }
  let pct  = if m > 0 { calc.min(100.0, calc.max(0.0, n / m * 100.0)) } else { 0.0 }
  let col  = if color != none { color } else { score-color(n) }
  block(below: 8pt, width: 100%)[
    #grid(columns: (1fr, 28pt), gutter: 4pt,
      text(size: 8.5pt, weight: "semibold", fill: c-dark)[#label],
      align(right, text(size: 8.5pt, weight: "bold", fill: col)[#calc.round(n)])
    )
    #v(3pt)
    #block(width: 100%, height: 5pt, fill: c-border, radius: 2.5pt, clip: true)[
      #block(width: pct * 1%, height: 100%, fill: col, radius: 2.5pt)[]
    ]
  ]
}

// ── Card ─────────────────────────────────────────────────────────────────────
// No fill of its own (page background, incl. the watermark, shows straight
// through) — otherwise the card's white would add a second dimming layer on
// top of the watermark's own alpha, making the mark look darker in open page
// space than it does under a card. One fade stage, defined once on the
// watermark itself, keeps it visually identical everywhere on the page.
#let card(title: none, body) = block(
  width: 100%, below: 10pt,
  fill: none,
  stroke: (paint: c-border, thickness: 0.5pt),
  radius: 7pt,
  inset: 14pt,
  breakable: false,
)[
  #if title != none {
    text(size: 10pt, weight: "semibold", fill: c-dark)[#title]
    v(8pt)
  }
  #body
]

// ── Bullet list from array ───────────────────────────────────────────────────
#let bullet-list(items) = {
  for item in items {
    grid(columns: (10pt, 1fr), gutter: 0pt,
      text(fill: c-orange, size: 9pt)[•],
      text(size: 9pt, fill: rgb("#374151"))[#item]
    )
    v(3pt)
  }
}

// ── Key-value row ────────────────────────────────────────────────────────────
#let kv-row(key, val) = {
  grid(columns: (1fr, auto), gutter: 6pt,
    text(size: 9pt, fill: c-muted)[#key],
    align(right, text(size: 9pt, weight: "semibold", fill: c-dark)[#val])
  )
  v(3pt)
}

// ── Section label (all-caps sub-heading inside card) ─────────────────────────
#let section-label(t) = {
  text(size: 7.5pt, weight: "semibold", fill: c-muted, tracking: 0.8pt)[#upper(t)]
  v(5pt)
}

// ── Orange accent rule ────────────────────────────────────────────────────────
#let orange-rule = rect(fill: c-orange, width: 100%, height: 2.5pt, stroke: none)

// ── Report header ─────────────────────────────────────────────────────────────
#let report-header(data, title, subtitle: "") = {
  let student   = data.at("student", default: none)
  let gen       = data.at("generated_at", default: "")
  let logo_path = data.at("_logo_path", default: "")

  orange-rule
  v(10pt)

  grid(columns: (1fr, auto), gutter: 12pt,
    // Left: brand + title
    block[
      #grid(columns: (auto, 1fr), gutter: 8pt, align: horizon,
        if logo_path != "" { image(logo_path, height: 26pt) },
        block[
          #text(weight: "bold", size: 13pt, fill: c-dark)[Vyaasa]
          #h(4pt)
          #text(size: 8.5pt, fill: c-muted)[Assessment Report]
        ]
      )
      #v(8pt)
      #text(weight: "bold", size: 17pt, fill: c-dark)[#title]
      #if subtitle != "" {
        v(2pt)
        text(size: 9pt, fill: c-muted)[#subtitle]
      }
    ],
    // Right: student meta
    align(right, block[
      #if student != none {
        let fname = student.at("first_name", default: "")
        let lname = student.at("last_name", default: "")
        let email = student.at("email", default: "")
        text(weight: "semibold", size: 10pt, fill: c-dark)[#fname #lname]
        linebreak()
        text(size: 8.5pt, fill: c-muted)[#email]
        linebreak()
      }
      #text(size: 8.5pt, fill: c-muted)[#gen]
    ])
  )

  v(6pt)
  line(stroke: (paint: c-border, thickness: 0.5pt), length: 100%)
  v(14pt)
}

// ── Report footer ─────────────────────────────────────────────────────────────
// Passed as `page(footer: ...)` so it's pinned to the bottom margin of every
// page regardless of how much body content precedes it, instead of flowing
// inline and landing wherever the content happens to end.
#let report-footer(data, gen) = {
  let logo_path = data.at("_logo_path", default: "")

  orange-rule
  v(1pt)

  // The logo sits to the left of the text as a decoration, absolutely placed
  // so it never contributes to the text's own width — otherwise centering
  // the (logo + text) pair as one unit shifts the *text* off true center by
  // half the logo's width, which reads as visibly off-center on the page.
  let footer-text = text(size: 7.5pt, fill: luma(170))[Vyaasa · Assessment Report · #gen]

  align(center)[
    #context {
      let sz = measure(footer-text)
      box(width: sz.width, height: sz.height)[
        #if logo_path != "" {
          place(left + horizon, dx: -16pt, image(logo_path, height: 14pt))
        }
        #footer-text
      ]
    }
  ]
}

// ── Page watermark ────────────────────────────────────────────────────────────
// Straight (no rotation), centered, faded to one fixed alpha baked in right
// here — the only fade stage on the whole page (`card` has no fill of its
// own). That's what keeps it looking identical whether it falls under a card,
// under text, or in open space: nothing downstream dims it a second time.
#let watermark(data) = {
  let logo_path = data.at("_logo_path", default: "")
  if logo_path == "" { return }
  place(center + horizon)[
    #box(width: 85%, clip: true)[
      #image(logo_path, width: 100%)
      #place(top + left, rect(width: 100%, height: 100%, fill: rgb(255, 255, 255, 70%), stroke: none))
    ]
  ]
}

// ── Performance badge (inline pill) ──────────────────────────────────────────
#let perf-badge(label, color) = box(
  fill: color.lighten(80%),
  stroke: (paint: color.lighten(40%), thickness: 0.5pt),
  radius: 10pt,
  inset: (x: 8pt, y: 3pt),
)[
  #text(size: 8pt, weight: "semibold", fill: color)[#label]
]
