const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // stb_truetype's declarations, translated to Zig once and shared.
    const translate = b.addTranslateC(.{
        .root_source_file = b.path("vendor/stbtt_decl.h"),
        .target = target,
        .optimize = optimize,
    });
    translate.addIncludePath(b.path("vendor"));
    const ctt_mod = translate.createModule();

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    wire(b, exe_mod, ctt_mod);
    const exe = b.addExecutable(.{ .name = "merz", .root_module = exe_mod });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    run.addPassthruArgs();
    b.step("run", "Run merz").dependOn(&run.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    wire(b, test_mod, ctt_mod);
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    run_tests.has_side_effects = true;
    b.step("test", "Run unit tests").dependOn(&run_tests.step);
}

fn wire(b: *std.Build, m: *std.Build.Module, ctt_mod: *std.Build.Module) void {
    m.addImport("ctt", ctt_mod);
    // stb implementations (text rasterisation + PNG encode).
    m.addIncludePath(b.path("vendor"));
    m.addCSourceFile(.{
        .file = b.path("vendor/stb.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
    });
    // The embedded font, reachable by @embedFile("font_ttf") from any module file.
    m.addAnonymousImport("font_ttf", .{ .root_source_file = b.path("vendor/NotoSans-Regular.ttf") });
}
