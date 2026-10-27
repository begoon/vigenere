const std = @import("std");
const solver = @import("main.zig");

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 4) {
        std.debug.print("Usage: vigenere-encrypt-en PLAINTEXT_FILE KEYWORD MIXED_ALPHABET\n", .{});
        std.process.exit(1);
    }
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .unlimited);
    const plain = try solver.normalize(a, bytes);
    const key = try solver.normalize(a, args[2]);
    const alphabet = try solver.normalize(a, args[3]);
    const cipher = try a.alloc(usize, plain.len);
    try solver.encrypt(plain, key, alphabet, cipher);
    var buffer: [4096]u8 = undefined;
    var output: std.Io.File.Writer = .init(.stdout(), init.io, &buffer);
    const w = &output.interface;
    for (cipher, 0..) |letter, i| {
        if (i > 0 and i % 5 == 0) try w.writeByte(if (i % 55 == 0) '\n' else ' ');
        try w.writeByte(@intCast('A' + letter));
    }
    try w.writeByte('\n');
    try w.flush();
}
