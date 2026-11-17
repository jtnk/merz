//! Render a laid-out Graph to SVG. The first backend: it emits standard SVG that
//! any browser (or a rasteriser) can show, which makes the layout easy to eyeball.
//! A terminal/raster backend can share everything up to here.
const std = @import("std");
const model = @import("model.zig");
const layout = @import("layout.zig");
const Graph = model.Graph;

const font_size: f32 = 14.0;
const font_family = "ui-sans-serif, -apple-system, Segoe UI, Roboto, sans-serif";

// A restrained, Mermaid-ish default palette.
const node_fill = "#ECECFF";
const node_stroke = "#9370DB";
const edge_stroke = "#334155";
const text_fill = "#1e293b";
const bg_fill = "#ffffff";

const Buf = std.ArrayList(u8);

fn w(out: *Buf, gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(s);
    try out.appendSlice(gpa, s);
}

/// Render to an owned SVG byte slice. Caller frees.
pub fn render(gpa: std.mem.Allocator, g: *Graph, bounds: layout.Bounds) ![]u8 {
    var out: Buf = .empty;
    errdefer out.deinit(gpa);

    try w(&out, gpa,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.0}" height="{d:.0}" viewBox="0 0 {d:.0} {d:.0}" font-family="{s}">
        \\
    , .{ bounds.w, bounds.h, bounds.w, bounds.h, font_family });

    try out.appendSlice(gpa,
        \\<defs>
        \\<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
        \\<path d="M0,0 L10,5 L0,10 z" fill="
    );
    try out.appendSlice(gpa, edge_stroke);
    try out.appendSlice(gpa,
        \\"/>
        \\</marker>
        \\</defs>
        \\
    );

    try w(&out, gpa,
        \\<rect width="{d:.0}" height="{d:.0}" fill="{s}"/>
        \\
    , .{ bounds.w, bounds.h, bg_fill });

    // Edges under nodes.
    for (g.edges.items) |e| try renderEdge(&out, gpa, g, e);
    // Nodes on top.
    for (g.nodes.items) |node| try renderNode(&out, gpa, node);

    try out.appendSlice(gpa, "</svg>\n");
    return out.toOwnedSlice(gpa);
}

fn renderEdge(out: *Buf, gpa: std.mem.Allocator, g: *Graph, e: model.Edge) !void {
    const a = g.nodes.items[e.from];
    const b = g.nodes.items[e.to];
    const p0 = borderPoint(a, b.x, b.y);
    const p1 = borderPoint(b, a.x, a.y);

    const dash = switch (e.style) {
        .dotted => " stroke-dasharray=\"4 4\"",
        else => "",
    };
    const width: f32 = if (e.style == .thick) 3.0 else 1.5;
    const marker = if (e.arrow) " marker-end=\"url(#arrow)\"" else "";

    try w(out, gpa,
        \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="{d:.1}"{s}{s}/>
        \\
    , .{ p0.x, p0.y, p1.x, p1.y, edge_stroke, width, dash, marker });

    if (e.label.len > 0) {
        const mx = (p0.x + p1.x) / 2;
        const my = (p0.y + p1.y) / 2;
        const lw: f32 = @as(f32, @floatFromInt(cols(e.label))) * 7.0 + 8;
        try w(out, gpa,
            \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="18" fill="{s}" opacity="0.9"/>
            \\
        , .{ mx - lw / 2, my - 9, lw, bg_fill });
        try w(out, gpa,
            \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" dominant-baseline="central" font-size="12" fill="{s}">
        , .{ mx, my, text_fill });
        try appendEscaped(out, gpa, e.label);
        try out.appendSlice(gpa, "</text>\n");
    }
}

fn renderNode(out: *Buf, gpa: std.mem.Allocator, n: model.Node) !void {
    const x = n.x - n.w / 2;
    const y = n.y - n.h / 2;

    switch (n.shape) {
        .rect, .subroutine, .cylinder => {
            try w(out, gpa,
                \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" rx="4" fill="{s}" stroke="{s}" stroke-width="1.5"/>
                \\
            , .{ x, y, n.w, n.h, node_fill, node_stroke });
            if (n.shape == .subroutine) {
                try w(out, gpa,
                    \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="1.5"/>
                    \\<line x1="{d:.1}" y1="{d:.1}" x2="{d:.1}" y2="{d:.1}" stroke="{s}" stroke-width="1.5"/>
                    \\
                , .{ x + 6, y, x + 6, y + n.h, node_stroke, x + n.w - 6, y, x + n.w - 6, y + n.h, node_stroke });
            }
        },
        .round, .stadium => {
            const rx: f32 = if (n.shape == .stadium) n.h / 2 else 10;
            try w(out, gpa,
                \\<rect x="{d:.1}" y="{d:.1}" width="{d:.1}" height="{d:.1}" rx="{d:.1}" fill="{s}" stroke="{s}" stroke-width="1.5"/>
                \\
            , .{ x, y, n.w, n.h, rx, node_fill, node_stroke });
        },
        .circle => {
            try w(out, gpa,
                \\<ellipse cx="{d:.1}" cy="{d:.1}" rx="{d:.1}" ry="{d:.1}" fill="{s}" stroke="{s}" stroke-width="1.5"/>
                \\
            , .{ n.x, n.y, n.w / 2, n.h / 2, node_fill, node_stroke });
        },
        .diamond => {
            try w(out, gpa,
                \\<polygon points="{d:.1},{d:.1} {d:.1},{d:.1} {d:.1},{d:.1} {d:.1},{d:.1}" fill="{s}" stroke="{s}" stroke-width="1.5"/>
                \\
            , .{ n.x, y, x + n.w, n.y, n.x, y + n.h, x, n.y, node_fill, node_stroke });
        },
        .hexagon, .asymmetric => {
            const c: f32 = n.h / 2;
            try w(out, gpa,
                \\<polygon points="{d:.1},{d:.1} {d:.1},{d:.1} {d:.1},{d:.1} {d:.1},{d:.1} {d:.1},{d:.1} {d:.1},{d:.1}" fill="{s}" stroke="{s}" stroke-width="1.5"/>
                \\
            , .{ x + c, y, x + n.w - c, y, x + n.w, n.y, x + n.w - c, y + n.h, x + c, y + n.h, x, n.y, node_fill, node_stroke });
        },
    }

    try w(out, gpa,
        \\<text x="{d:.1}" y="{d:.1}" text-anchor="middle" dominant-baseline="central" font-size="{d:.0}" fill="{s}">
    , .{ n.x, n.y, font_size, text_fill });
    try appendEscaped(out, gpa, n.label);
    try out.appendSlice(gpa, "</text>\n");
}

const Point = struct { x: f32, y: f32 };

/// Where the line from a node's centre toward (tx,ty) crosses the node's box.
fn borderPoint(n: model.Node, tx: f32, ty: f32) Point {
    const dx = tx - n.x;
    const dy = ty - n.y;
    if (dx == 0 and dy == 0) return .{ .x = n.x, .y = n.y };
    const hw = n.w / 2;
    const hh = n.h / 2;
    var scale: f32 = std.math.inf(f32);
    if (dx != 0) scale = @min(scale, hw / @abs(dx));
    if (dy != 0) scale = @min(scale, hh / @abs(dy));
    return .{ .x = n.x + dx * scale, .y = n.y + dy * scale };
}

fn cols(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

fn appendEscaped(out: *Buf, gpa: std.mem.Allocator, s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '&' => try out.appendSlice(gpa, "&amp;"),
            '<' => try out.appendSlice(gpa, "&lt;"),
            '>' => try out.appendSlice(gpa, "&gt;"),
            '"' => try out.appendSlice(gpa, "&quot;"),
            else => try out.append(gpa, ch),
        }
    }
}

// ------------------------------------------------------------------ tests

const testing = std.testing;
const parse = @import("parser.zig").parse;

test "rendering produces well-formed-ish svg with the labels in it" {
    var g = try parse(testing.allocator, "flowchart TD\n A[Start] --> B[End]");
    defer g.deinit();
    const b = try layout.layout(testing.allocator, &g);
    const svg = try render(testing.allocator, &g, b);
    defer testing.allocator.free(svg);
    try testing.expect(std.mem.startsWith(u8, svg, "<svg"));
    try testing.expect(std.mem.endsWith(u8, svg, "</svg>\n"));
    try testing.expect(std.mem.indexOf(u8, svg, "Start") != null);
    try testing.expect(std.mem.indexOf(u8, svg, "End") != null);
    try testing.expect(std.mem.indexOf(u8, svg, "marker-end") != null);
}

test "special characters in labels are escaped" {
    var g = try parse(testing.allocator, "flowchart TD\n A[\"a & b < c\"] --> B[ok]");
    defer g.deinit();
    const b = try layout.layout(testing.allocator, &g);
    const svg = try render(testing.allocator, &g, b);
    defer testing.allocator.free(svg);
    try testing.expect(std.mem.indexOf(u8, svg, "a &amp; b &lt; c") != null);
}
