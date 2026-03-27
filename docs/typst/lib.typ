// Shared design system for pubsub documents.
// Usage: #import "lib.typ": *

// Palette: crimson
#let clr-dark       = rgb("#141414")
#let clr-light      = rgb("#fafafa")
#let clr-mid-gray   = rgb("#999999")
#let clr-light-gray = rgb("#e0e0e0")
#let clr-accent     = rgb("#c0392b")
#let clr-blue       = rgb("#5a8abf")
#let clr-green      = rgb("#4a8c5a")
#let clr-orange     = rgb("#d48a3c")

// Heading text (Funnel Sans)
#let hd(..args, body) = text(font: "Funnel Sans", ..args, body)

// Inline code with pill background
#let mono(body) = box(
  inset: (x: 2.5pt, y: 1.5pt),
  outset: (y: 1.5pt),
  radius: 2pt,
  fill: rgb("#e8e8e8"),
  text(font: "JetBrains Mono", size: 7.5pt, body),
)

// Plain monospace for table cells (no pill)
#let table-mono(body) = text(font: "JetBrains Mono", size: 7.5pt, body)

// Text style helpers
#let accent(body) = text(fill: clr-accent, weight: "semibold", body)
#let dim(body) = text(fill: clr-mid-gray, body)

// Section divider: accent label + horizontal rule
#let section(title, v-before: 8pt, v-after: 4pt, gutter: 8pt, size: 8pt) = {
  v(v-before)
  grid(
    columns: (auto, 1fr),
    gutter: gutter,
    align: (left + horizon, horizon),
    hd(size: size, weight: "semibold", fill: clr-accent, tracking: 2pt)[#upper(title)],
    line(length: 100%, stroke: 0.5pt + clr-light-gray),
  )
  v(v-after)
}

// Alternating row fill for tables
#let cell-fill(col, row) = {
  if row == 0 { clr-accent.lighten(88%) }
  else if calc.rem(row, 2) == 0 { rgb("#f5f5f5") }
  else { white }
}
