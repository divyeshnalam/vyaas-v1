#import "_shared.typ": *

// One-page mirror of the on-screen "View Certificate" tab
// (VyaasaCampusWeb.Components.Student.CredentialsComponent.certificate/1).

#let data              = json(sys.inputs.at("datafile"))
#let student_name      = data.at("student_name", default: "")
#let cert_id           = data.at("cert_id", default: "")
#let issued_on         = data.at("issued_on", default: "")
#let valid_until       = data.at("valid_until", default: "")
#let score             = data.at("score", default: 0)
#let qr_path           = data.at("_qr_path", default: "")
#let logo_path         = data.at("_logo_path", default: "")
#let mark_path         = data.at("_mark_path", default: "")
#let ceo_sig_path      = data.at("_ceo_sig_path", default: "")
#let cofounder_sig_path = data.at("_cofounder_sig_path", default: "")

#let c-brand = rgb("#EF6C00")

#set page(width: 210mm, height: 148mm, margin: 0mm, fill: rgb("#FFFBF5"))

#place(top + left, rect(width: 100%, height: 2.4mm, fill: gradient.linear(rgb("#FB923C"), c-brand, rgb("#FB923C"))))

#place(center + horizon, rect(
  width: 190mm, height: 128mm, radius: 10pt,
  fill: none, stroke: (paint: rgb("#FED7AA"), thickness: 1.2pt),
))

// Faint centered logo watermark, matching the on-screen card's opacity-5 mark.
#if logo_path != "" {
  place(center + horizon)[
    #box(width: 60%, clip: true)[
      #image(logo_path, width: 100%)
      #place(top + left, rect(width: 100%, height: 100%, fill: rgb("#FFFBF5").transparentize(5%), stroke: none))
    ]
  ]
}

#place(top + center, dy: 10mm)[
  #align(center)[
    #if logo_path != "" { image(logo_path, height: 15mm) }
    #v(4pt)
    #text(size: 15pt, weight: 800, fill: rgb("#111827"), tracking: 0.5pt)[VYAASA CERTIFICATION]
    #v(2pt)
    #text(size: 7.5pt, weight: "bold", fill: c-brand, tracking: 1.5pt)[CERTIFICATE OF CAREER READINESS]
    #v(2pt)
    #box(width: 60mm, height: 0.5pt, fill: rgb("#D1D5DB"))
  ]
]

#place(center + horizon, dy: 6mm)[
  #box(width: 178mm)[
  #grid(columns: (32mm, 1fr, 26mm), gutter: 12mm, align: horizon,
    align(center)[
      #if qr_path != "" {
        box(width: 30mm, height: 30mm)[
          #image(qr_path, width: 30mm, height: 30mm, scaling: "pixelated")
          #if mark_path != "" {
            place(center + horizon)[
              #box(width: 8mm, height: 8mm, radius: 4mm, fill: white, inset: 0.9mm)[
                #image(mark_path, width: 100%, height: 100%)
              ]
            ]
          }
        ]
        v(4pt)
        text(size: 6.5pt, fill: rgb("#6b7280"))[Scan to Verify \ Authenticity]
      }
    ],
    align(center)[
      #text(size: 9pt, fill: rgb("#6b7280"))[This certificate is proudly presented to]
      #v(4pt)
      #text(size: 20pt, weight: "bold", fill: rgb("#7A1F1F"), tracking: 0.4pt)[#upper(student_name)]
      #v(4pt)
      #text(size: 12pt, weight: 800, fill: rgb("#111827"))[OVERALL SCORE: #score/100]
      #v(6pt)
      #text(size: 7.5pt, fill: rgb("#4b5563"))[
        This candidate has demonstrated strong employability skills, including technical proficiency,
        problem-solving ability, and industry readiness, as validated by the VYAASA AI Assessment Framework.
      ]
    ],
    align(center)[
      #grid(columns: 1fr, row-gutter: 16pt,
        [
          #text(size: 6.5pt, weight: "semibold", fill: rgb("#374151"))[Certificate ID:]
          #v(2pt)
          #text(size: 6.5pt, fill: rgb("#6b7280"))[#cert_id]
          #v(1pt)
          #box(width: 20mm, height: 0.5pt, fill: rgb("#EF6C00"))
        ],
        [
          #text(size: 6.5pt, weight: "semibold", fill: rgb("#374151"))[Issue Date:]
          #v(2pt)
          #text(size: 6.5pt, fill: rgb("#6b7280"))[#issued_on]
           #v(1pt)
          #box(width: 20mm, height: 0.5pt, fill: rgb("#EF6C00"))
        ],
        [
          #text(size: 6.5pt, weight: "semibold", fill: rgb("#374151"))[Valid Until:]
          #v(2pt)
          #text(size: 6.5pt, fill: rgb("#6b7280"))[#valid_until]
          #v(1pt)
          #box(width: 20mm, height: 0.5pt, fill: rgb("#EF6C00"))
        ],
        [
          #text(size: 6.5pt, weight: "semibold", fill: rgb("#374151"))[Assessment Type:]
          #v(2pt)
          #text(size: 6.5pt, fill: rgb("#6b7280"))[AI8 Employability Assessment]
        ],
      )
    ]
  )
  ]
]

// Signature PNGs are pre-cropped to their ink bounding box (see priv/static/
// images/{ceosig,co-foundersig}.png) — no extra blank canvas to crop away.
// Anchoring both to the bottom of a shared fixed-height box (rather than
// vertically centering each on its own canvas) keeps the two signatures,
// which differ in size/aspect, sitting flush with their divider lines.
#let sig-crop(path) = box(height: 7mm)[
  #align(bottom)[#image(path, height: 7mm)]
]

#place(bottom + center, dy: -12mm)[
  #grid(columns: (auto, auto), column-gutter: 40mm, align: horizon + center,
    align(center)[
      #if ceo_sig_path != "" { sig-crop(ceo_sig_path) }
      
      #box(width: 30mm, height: 0.5pt, fill: rgb("#EF6C00"))
      #v(2pt)
      #text(size: 8pt, weight: "bold", fill: rgb("#111827"))[Shreeram Dittakavi]
      #v(1pt)
      #text(size: 6.5pt, weight: "medium", fill: c-brand)[CEO]
      #v(1pt)
      #text(size: 6.5pt, weight: "medium", fill: c-brand)[VYAASA]
    ],
    align(center)[
      #if cofounder_sig_path != "" { sig-crop(cofounder_sig_path) }
      
      #box(width: 30mm, height: 0.5pt, fill: rgb("#EF6C00"))
      #v(2pt)
      #text(size: 8pt, weight: "bold", fill: rgb("#111827"))[Rajya Lakshmi]
      #v(1pt)
      #text(size: 6.5pt, weight: "medium", fill: c-brand)[Co-Founder]
      #v(1pt)
      #text(size: 6.5pt, weight: "medium", fill: c-brand)[VYAASA]
    ]
  )
]
