#import "lib.typ": *

// Page
#set page(
  paper:  "us-letter",
  margin: (top: 0.5in, bottom: 0.5in, left: 0.65in, right: 0.65in),
  fill:   clr-light,
  footer: context {
    set text(font: "Funnel Sans", size: 7pt, fill: clr-mid-gray)
    grid(
      columns: (1fr, auto, 1fr),
      align: (left, center, right),
      [pubsub -- performance report],
      [#counter(page).display("1 / 1", both: true)],
      [March 2026],
    )
  },
)

// Typography
#set text(font: "Lora", size: 9pt, fill: clr-dark, weight: "regular")
#set par(leading: 0.65em, justify: true)
// Report-specific helpers

// Metric: bold number + muted label
#let metric(value, label) = {
  [
    #hd(size: 18pt, weight: "bold", fill: clr-dark)[#value] \
    #v(-4pt)
    #hd(size: 7.5pt, fill: clr-mid-gray)[#label]
  ]
}

// Before/after delta row for tables
#let delta(before, after, unit, improvement) = {
  (
    table-mono[#before #unit],
    table-mono[#after #unit],
    if improvement.starts-with("-") {
      text(fill: clr-green, weight: "semibold")[#improvement]
    } else {
      text(fill: clr-accent, weight: "semibold")[#improvement]
    },
  )
}

// ============================================================================
// HEADER
// ============================================================================

#align(center)[
  #v(8pt)
  #hd(size: 26pt, weight: "bold", fill: clr-dark)[pubsub]
  #v(-12pt)
  #hd(size: 11pt, weight: "regular", fill: clr-mid-gray)[Performance Report & Development Log]
  #v(-4pt)
  #hd(size: 8pt, fill: clr-mid-gray)[v0.1.2 -- March 2026 -- Criterion 0.5 statistical benchmarks]
  #v(4pt)
]

// ============================================================================
// HEADLINE NUMBERS
// ============================================================================

#line(length: 100%, stroke: 0.5pt + clr-light-gray)
#v(16pt)
#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  gutter: 12pt,
  metric("7.1M", "trie lookups/sec at 5M subs"),
  metric("139x", "frame serialize speedup (16KB)"),
  metric("3.5M", "routed deliveries/sec (1K subs)"),
  metric("20%", "router pipeline improvement"),
)
#v(8pt)
// #line(length: 100%, stroke: 0.5pt + clr-light-gray)

// ============================================================================
// WHAT CHANGED
// ============================================================================

#section("What changed")

Four targeted optimizations across three crates. No public API changes.

#v(4pt)

#grid(
  columns: (1fr, 1fr),
  gutter: 16pt,
  [
    *1. Zero-copy frame serialization* #dim[(pubsub-protocol)] \
    #v(2pt)
    Split #mono[FrameHelper] into #mono[FrameSerHelper<'a>] (borrows, zero allocs)
    and #mono[FrameDeHelper] (owns, decode only). Added #mono[serde_bytes] so
    payloads encode as msgpack binary instead of integer arrays. Eliminates
    #mono[payload.to_vec()] and all string clones on the serialize path.

    #v(6pt)
    *2. Single-pass router dispatch* #dim[(pubsub-broker)] \
    #v(2pt)
    Merged #mono[get_queue_group()] and #mono[get_sender()] into a single
    #mono[get_routing_info()] call -- one DashMap lookup instead of two per
    subscriber. Direct subscribers now deliver inline, removing the
    intermediate #mono[direct_sids] vector.
  ],
  [
    *3. Arc\<str\> for queue group names* #dim[(pubsub-broker)] \
    #v(2pt)
    Replaced #mono[String] with #mono[Arc<str>] for queue group names.
    Clone cost: O(n) string copy to a single atomic increment.

    #v(6pt)
    *4. Pre-allocated match results* #dim[(pubsub-broker)] \
    #v(2pt)
    Changed #mono[TopicTrie::matches()] from #mono[Vec::new()] to
    #mono[Vec::with_capacity(4)], avoiding the first two reallocations
    on the hottest function in the system.

    #v(10pt)

    #box(
      width: 100%,
      inset: 10pt,
      radius: 3pt,
      stroke: 0.5pt + clr-light-gray,
      fill: rgb("#f5f5f0"),
      [
        #hd(size: 7.5pt, weight: "semibold", fill: clr-mid-gray, tracking: 1pt)[DESIGN PRINCIPLE] \
        #v(2pt)
        #text(size: 8.5pt)[Remove allocations from the hot path. No algorithmic
        changes, no unsafe code, no API breakage.]
      ],
    )
  ],
)

// ============================================================================
// PROTOCOL BENCHMARKS (the big win)
// ============================================================================

#section("Protocol layer -- before/after")

The old path copied every payload byte twice (#mono[Vec<u8>] + output buffer).
The new path borrows directly from #mono[Frame].

#v(4pt)

#{
  set text(size: 8pt)
  grid(
    columns: (1fr, 1fr),
    gutter: 16pt,
    [
      #hd(size: 9pt, weight: "semibold")[Frame Serialization]
      #v(3pt)
      #table(
        columns: (1.4fr, 1fr, 1fr, 0.8fr),
        align: (left, right, right, right),
        fill: cell-fill,
        stroke: none,
        inset: (x: 6pt, y: 4pt),
        hd(weight: "semibold", fill: clr-accent)[Benchmark],
        hd(weight: "semibold", fill: clr-accent)[Before],
        hd(weight: "semibold", fill: clr-accent)[After],
        hd(weight: "semibold", fill: clr-accent)[Delta],

        [ping],              ..delta("15", "14", "ns", "-7%"),
        [publish / 0B],      ..delta("74", "62", "ns", "-16%"),
        [publish / 64B],     ..delta("258", "106", "ns", "-59%"),
        [publish / 1KB],     ..delta("12.1", "0.137", "us", "-99%"),
        [publish / 16KB],    ..delta("28.5", "0.204", "us", "-99%"),
      )
    ],
    [
      #hd(size: 9pt, weight: "semibold")[Frame Deserialization]
      #v(3pt)
      #table(
        columns: (1.4fr, 1fr, 1fr, 0.8fr),
        align: (left, right, right, right),
        fill: cell-fill,
        stroke: none,
        inset: (x: 6pt, y: 4pt),
        hd(weight: "semibold", fill: clr-accent)[Benchmark],
        hd(weight: "semibold", fill: clr-accent)[Before],
        hd(weight: "semibold", fill: clr-accent)[After],
        hd(weight: "semibold", fill: clr-accent)[Delta],

        [ping],              ..delta("19", "20", "ns", "+5%"),
        [publish / 0B],      ..delta("58", "60", "ns", "+3%"),
        [publish / 64B],     ..delta("275", "67", "ns", "-76%"),
        [publish / 1KB],     ..delta("13.2", "0.074", "us", "-99%"),
        [publish / 16KB],    ..delta("50.2", "0.176", "us", "-99%"),
      )
    ],
  )
}

#v(2pt)

#{
  set text(size: 8pt)
  grid(
    columns: (1fr, 1fr),
    gutter: 16pt,
    [
      #hd(size: 9pt, weight: "semibold")[Codec Roundtrip #dim[(encode + decode)]]
      #v(3pt)
      #table(
        columns: (1.4fr, 1fr, 1fr, 0.8fr),
        align: (left, right, right, right),
        fill: cell-fill,
        stroke: none,
        inset: (x: 6pt, y: 4pt),
        hd(weight: "semibold", fill: clr-accent)[Payload],
        hd(weight: "semibold", fill: clr-accent)[Before],
        hd(weight: "semibold", fill: clr-accent)[After],
        hd(weight: "semibold", fill: clr-accent)[Delta],

        [0 bytes],    ..delta("169", "155", "ns", "-8%"),
        [64 bytes],   ..delta("638", "214", "ns", "-66%"),
        [1 KB],       ..delta("15.5", "0.268", "us", "-98%"),
        [16 KB],      ..delta("81.9", "0.577", "us", "-99%"),
      )
    ],
    [
      #hd(size: 9pt, weight: "semibold")[Message Frame Roundtrip]
      #v(3pt)
      #table(
        columns: (1.4fr, 1fr, 1fr, 0.8fr),
        align: (left, right, right, right),
        fill: cell-fill,
        stroke: none,
        inset: (x: 6pt, y: 4pt),
        hd(weight: "semibold", fill: clr-accent)[Payload],
        hd(weight: "semibold", fill: clr-accent)[Before],
        hd(weight: "semibold", fill: clr-accent)[After],
        hd(weight: "semibold", fill: clr-accent)[Delta],

        [64 bytes],   ..delta("662", "226", "ns", "-66%"),
        [1 KB],       ..delta("5.5", "0.310", "us", "-94%"),
      )
      #v(6pt)
      #box(
        width: 100%,
        inset: 8pt,
        radius: 3pt,
        fill: clr-green.lighten(90%),
        stroke: 0.5pt + clr-green.lighten(60%),
        [
          #hd(size: 7.5pt, weight: "semibold", fill: clr-green)[KEY INSIGHT] \
          #v(1pt)
          #text(size: 8pt)[#mono[serde_bytes] alone accounts for most of the
          deserialization gain -- without it, msgpack decodes binary as
          integer arrays.]
        ],
      )
    ],
  )
}

#pagebreak()

// ============================================================================
// BROKER BENCHMARKS
// ============================================================================

#section("Broker layer -- before/after")

#{
  set text(size: 8pt)
  grid(
    columns: (1fr, 1fr),
    gutter: 16pt,
    [
      #hd(size: 9pt, weight: "semibold")[Router Dispatch #dim[(full async pipeline)]]
      #v(3pt)
      #table(
        columns: (1.6fr, 1fr, 1fr, 0.8fr),
        align: (left, right, right, right),
        fill: cell-fill,
        stroke: none,
        inset: (x: 6pt, y: 4pt),
        hd(weight: "semibold", fill: clr-accent)[Benchmark],
        hd(weight: "semibold", fill: clr-accent)[Before],
        hd(weight: "semibold", fill: clr-accent)[After],
        hd(weight: "semibold", fill: clr-accent)[Delta],

        [fanout / 1 sub],     ..delta("194", "164", "ns", "-15%"),
        [fanout / 10 subs],   ..delta("930", "758", "ns", "-18%"),
        [fanout / 100 subs],  ..delta("17.6", "16.4", "us", "-7%"),
        [fanout / 1K subs],   ..delta("77.1", "61.5", "us", "-20%"),
        [miss (no match)],    ..delta("76", "78", "ns", "+3%"),
      )
      #v(4pt)
      Gains scale with subscriber count: one fewer DashMap lookup per match.
      At 1K subs, that is 1,000 eliminated hash lookups per publish.
    ],
    [
      #hd(size: 9pt, weight: "semibold")[Trie Matching #dim[(hot path)]]
      #v(3pt)
      #table(
        columns: (1.6fr, 1fr, 1fr, 0.8fr),
        align: (left, right, right, right),
        fill: cell-fill,
        stroke: none,
        inset: (x: 6pt, y: 4pt),
        hd(weight: "semibold", fill: clr-accent)[Benchmark],
        hd(weight: "semibold", fill: clr-accent)[Before],
        hd(weight: "semibold", fill: clr-accent)[After],
        hd(weight: "semibold", fill: clr-accent)[Delta],

        [exact / 10 subs],     ..delta("94", "87", "ns", "-7%"),
        [exact / 10K subs],    ..delta("93", "91", "ns", "-2%"),
        [wildcard / 10],       ..delta("94", "75", "ns", "-20%"),
        [wildcard / 1K],       ..delta("92", "78", "ns", "-15%"),
        [registry / 1K],       ..delta("122", "117", "ns", "-4%"),
      )
      #v(4pt)
      Stable across subscription counts -- confirms O(topic_depth) complexity.
      #mono[with_capacity(4)] helped most on single-match patterns.
    ],
  )
}


// ============================================================================
// THROUGHPUT NUMBERS
// ============================================================================

#section("Throughput benchmarks -- stress testing at scale")

Batched throughput benchmarks via Criterion's #mono[Throughput::Elements] to
show aggregate capacity beyond per-operation latency.

#v(4pt)

#{
  set text(size: 8pt)
  grid(
    columns: (1fr, 1fr),
    gutter: 16pt,
    [
      #hd(size: 9pt, weight: "semibold")[Trie Lookup Throughput]
      #v(3pt)
      #text(size: 8.5pt)[Batches of 10K lookups against tries of varying size.]
      #v(3pt)
      #table(
        columns: (1fr, 1fr),
        align: (left, right),
        fill: cell-fill,
        stroke: none,
        inset: (x: 6pt, y: 4pt),
        hd(weight: "semibold", fill: clr-accent)[Subscriptions],
        hd(weight: "semibold", fill: clr-accent)[Throughput],

        [100],        hd(fill: clr-dark)[10.9 M lookups/sec],
        [1,000],      hd(fill: clr-dark)[9.4 M lookups/sec],
        [10,000],     hd(fill: clr-dark)[8.3 M lookups/sec],
        [100,000],    hd(fill: clr-dark)[8.1 M lookups/sec],
        [1,000,000],  hd(fill: clr-dark)[7.3 M lookups/sec],
        [5,000,000],  hd(fill: clr-dark, weight: "semibold")[7.1 M lookups/sec],
      )
      #v(4pt)
      100 to 5M subs: only ~35% drop. Lookup cost tracks topic depth,
      not subscription count.
    ],
    [
      #hd(size: 9pt, weight: "semibold")[Routing Delivery Throughput]
      #v(3pt)
      #text(size: 8.5pt)[Full async pipeline: trie match + DashMap + channel send.]
      #v(3pt)
      #table(
        columns: (1fr, 1fr),
        align: (left, right),
        fill: cell-fill,
        stroke: none,
        inset: (x: 6pt, y: 4pt),
        hd(weight: "semibold", fill: clr-accent)[Configuration],
        hd(weight: "semibold", fill: clr-accent)[Throughput],

        [10 subs x 1K msgs],    hd(fill: clr-dark)[4.6 M deliveries/sec],
        [100 subs x 1K msgs],   hd(fill: clr-dark)[3.2 M deliveries/sec],
        [1K subs x 500 msgs],   hd(fill: clr-dark, weight: "semibold")[3.5 M deliveries/sec],
      )
      #v(3pt)
      #table(
        columns: (1fr, 1fr),
        align: (left, right),
        fill: cell-fill,
        stroke: none,
        inset: (x: 6pt, y: 4pt),
        hd(weight: "semibold", fill: clr-accent)[Wildcard Routing],
        hd(weight: "semibold", fill: clr-accent)[Throughput],

        [60 wildcard subs x 1K msgs], hd(fill: clr-dark)[4.1 M deliveries/sec],
      )
      #v(4pt)
      Wildcards do not degrade throughput vs exact match. At high fanout,
      channel send latency dominates trie traversal.
    ],
  )
}
