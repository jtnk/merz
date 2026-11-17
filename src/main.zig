//! merz — a native Zig Mermaid renderer. No Node, no headless browser.
//!
//! Usage:
//!   merz [INPUT]            render INPUT (or stdin) to SVG on stdout
//!   merz INPUT -o OUT.svg   write SVG to a file
//!   merz --help | --version
const std = @import("std");
const c = std.c;
const parser = @import("parser.zig");
const layout = @import("layout.zig");
const svg = @import("svg.zig");
const raster = @import("raster.zig");

const version = "0.1.0";
const max_input: usize = 8 * 1024 * 1024;

// The standalone binary carries a font so it can rasterise on its own. A host
// like tmd would call raster.renderPng with its own font bytes instead.
const font_ttf = @embedFile("font_ttf");

const Format = enum { svg, png };

const usage =
    \\merz — native Mermaid renderer (flowcharts)
    \\
    \\Usage:
    \\  merz [INPUT]              render INPUT (or stdin) to SVG on stdout
    \\  merz INPUT -o OUTPUT      write to a file (.png renders a PNG, else SVG)
    \\  merz --png [INPUT]        force PNG output
    \\  merz --help | --version
    \\
;

pub fn main(init: std.process.Init.Minimal) void {
    run(init) catch |e| {
        fail(@errorName(e));
    };
}

fn run(init: std.process.Init.Minimal) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const gpa = arena_state.allocator();

    var input_path: ?[:0]const u8 = null;
    var output_path: ?[:0]const u8 = null;
    var forced_format: ?Format = null;

    var it = init.args.iterate();
    _ = it.next(); // argv[0]
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            writeAll(1, usage);
            return;
        } else if (std.mem.eql(u8, arg, "--version")) {
            writeAll(1, "merz " ++ version ++ "\n");
            return;
        } else if (std.mem.eql(u8, arg, "--png")) {
            forced_format = .png;
        } else if (std.mem.eql(u8, arg, "--svg")) {
            forced_format = .svg;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            output_path = it.next() orelse failRet("-o needs a file path");
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and !std.mem.eql(u8, arg, "-")) {
            failRet2("unknown option: ", arg);
        } else {
            input_path = arg;
        }
    }

    // Choose output format: an explicit flag wins, else a .png output path, else SVG.
    const format: Format = forced_format orelse blk: {
        if (output_path) |p| {
            if (std.mem.endsWith(u8, p, ".png")) break :blk .png;
        }
        break :blk .svg;
    };

    const source = if (input_path) |p| blk: {
        if (std.mem.eql(u8, p, "-")) break :blk try readFd(gpa, 0);
        break :blk readFile(gpa, p.ptr) catch failRet2("cannot read ", p);
    } else try readFd(gpa, 0);

    var g = parser.parse(gpa, source) catch |e| {
        switch (e) {
            error.UnsupportedDiagram => failRet("only flowcharts are supported so far (graph / flowchart)"),
            error.EmptyInput => failRet("no diagram found in the input"),
            else => return e,
        }
    };
    defer g.deinit();

    const bounds = try layout.layout(gpa, &g);
    const out = switch (format) {
        .svg => try svg.render(gpa, &g, bounds),
        .png => try raster.renderPng(gpa, &g, bounds, font_ttf),
    };

    if (output_path) |p| {
        writeFile(p.ptr, out) catch failRet2("cannot write ", p);
    } else {
        writeAll(1, out);
    }
}

// ------------------------------------------------------------------ io (over libc)

fn readFd(gpa: std.mem.Allocator, fd: c.fd_t) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(gpa);
    while (true) {
        try buf.ensureUnusedCapacity(gpa, 64 * 1024);
        const dest = buf.unusedCapacitySlice();
        const n = c.read(fd, dest.ptr, dest.len);
        if (n < 0) {
            if (std.posix.errno(n) == .INTR) continue;
            return error.ReadFailed;
        }
        if (n == 0) break;
        buf.items.len += @intCast(n);
        if (buf.items.len > max_input) return error.InputTooBig;
    }
    return buf.toOwnedSlice(gpa);
}

fn readFile(gpa: std.mem.Allocator, path: [*:0]const u8) ![]u8 {
    const fd = c.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true });
    if (fd < 0) return error.NotFound;
    defer _ = c.close(fd);
    return readFd(gpa, fd);
}

fn writeFile(path: [*:0]const u8, bytes: []const u8) !void {
    const fd = c.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, @as(c.mode_t, 0o644));
    if (fd < 0) return error.WriteFailed;
    defer _ = c.close(fd);
    rawWrite(fd, bytes);
}

fn writeAll(fd: c.fd_t, bytes: []const u8) void {
    rawWrite(fd, bytes);
}

fn rawWrite(fd: c.fd_t, bytes: []const u8) void {
    var i: usize = 0;
    while (i < bytes.len) {
        const n = c.write(fd, bytes[i..].ptr, bytes.len - i);
        if (n <= 0) return;
        i += @intCast(n);
    }
}

fn fail(msg: []const u8) noreturn {
    writeAll(2, "merz: ");
    writeAll(2, msg);
    writeAll(2, "\n");
    std.process.exit(1);
}

fn failRet(msg: []const u8) noreturn {
    fail(msg);
}

fn failRet2(a: []const u8, b: []const u8) noreturn {
    writeAll(2, "merz: ");
    writeAll(2, a);
    writeAll(2, b);
    writeAll(2, "\n");
    std.process.exit(1);
}

// Pull unit tests from the modules into `zig build test`.
test {
    std.testing.refAllDecls(@This());
    _ = parser;
    _ = layout;
    _ = svg;
    _ = raster;
    _ = @import("model.zig");
}
