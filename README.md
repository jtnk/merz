# merz

A native Zig [Mermaid](https://mermaid.js.org/) renderer. No Node, no headless
Chromium — just a small binary that turns Mermaid text into a diagram.

Built as a sibling of [`tmd`](https://github.com/jtnk/tmd), the terminal Markdown viewer, so a
` ```mermaid ` code block can be rendered inline the way images already are.
Two backends: **SVG** (portable, inspectable) and **PNG** (a raster image ready
for a terminal's graphics protocol).

## Status

Early. Handles the **flowchart** subset:

- `graph` / `flowchart` with a direction (`TD`, `TB`, `BT`, `LR`, `RL`)
- node shapes: `[rect]`, `(round)`, `([stadium])`, `((circle))`, `{diamond}`,
  `{{hexagon}}`, `[[subroutine]]`, `[(cylinder)]`, `>asymmetric]`
- edges: `-->`, `---`, `-.->`, `==>`, and the reverse `<--`
- edge labels in both forms: `A -->|yes| B` and `A -- yes --> B`

Not yet: subgraphs (grouping is ignored, inner nodes still render), crossing
minimisation, edge routing around nodes, and the other diagram types (sequence,
class, state, …) — those report an error rather than guess.

## Usage

```sh
merz diagram.mmd              # SVG to stdout
merz diagram.mmd -o out.svg   # SVG to a file
merz diagram.mmd -o out.png   # PNG (raster)
merz --png diagram.mmd        # force PNG to stdout
cat diagram.mmd | merz        # from stdin
```

The PNG backend rasterises shapes with signed-distance anti-aliasing and draws
text with [stb_truetype](https://github.com/nothings/stb). The font is passed in
as bytes: the standalone binary embeds Noto Sans, while a host like tmd can hand
it whatever font it already has.

## Build

Needs Zig 0.17. This repo carries a `minimal.toml`, so inside a
[`min`](https://github.com/gominimal) session the toolchain is provided:

```sh
zig build            # builds ./zig-out/bin/merz
zig build test       # runs the unit tests
zig build run -- diagram.mmd
```

## Layout

- `src/model.zig`  — the graph: nodes, edges, the slots layout fills in
- `src/parser.zig` — Mermaid flowchart text → graph
- `src/layout.zig` — layered (Sugiyama-style) positioning
- `src/svg.zig`    — graph + geometry → SVG
- `src/raster.zig` — graph + geometry → RGBA → PNG (SDF shapes, stb_truetype text)
- `src/main.zig`   — CLI
- `vendor/`        — stb_truetype, stb_image_write (public domain), Noto Sans (OFL)

Third-party licenses are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
