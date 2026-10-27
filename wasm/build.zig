const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const optimize = b.standardOptimizeOption(.{});
    const solver = b.createModule(.{
        .root_source_file = b.path("../zig/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "solver", .module = solver }},
    });
    const exe = b.addExecutable(.{ .name = "vigenere", .root_module = module });
    exe.entry = .disabled;
    exe.rdynamic = true;
    exe.export_memory = true;
    exe.stack_size = 1024 * 1024;
    exe.max_memory = 256 * 1024 * 1024;
    b.installArtifact(exe);
}
