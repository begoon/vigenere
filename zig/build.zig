const std = @import("std");
pub fn build(b: *std.Build) void {
    const module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    const options = b.addOptions();
    options.addOption(bool, "integration", b.option(bool, "integration", "Run full recovery test") orelse false);
    module.addOptions("test_options", options);
    const exe = b.addExecutable(.{ .name = "vigenerecrack", .root_module = module });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Crack a ciphertext").dependOn(&run.step);
    const tests = b.addRunArtifact(b.addTest(.{ .root_module = module }));
    tests.setCwd(b.path("."));
    b.step("test", "Run unit tests").dependOn(&tests.step);
}
