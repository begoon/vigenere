const std = @import("std");
const solver = @import("solver");

extern "env" fn progress(completed: u32) void;
fn notify(completed: u32) void {
    progress(completed);
}

var input: [32768]u8 = undefined;
var plaintext: [8192]u8 = undefined;
var keyword: [40]u8 = undefined;
var alphabet: [64]u8 = undefined;
var plain_len: usize = 0;
var period: usize = 0;

export fn input_ptr() [*]u8 {
    return &input;
}
export fn input_capacity() usize {
    return input.len;
}
export fn plaintext_ptr() [*]const u8 {
    return &plaintext;
}
export fn plaintext_len() usize {
    return plain_len;
}
export fn keyword_ptr() [*]const u8 {
    return &keyword;
}
export fn key_length() usize {
    return period;
}
export fn alphabet_ptr() [*]const u8 {
    return &alphabet;
}

fn encode(values: []const usize, out: []u8) void {
    for (values, 0..) |value, i| {
        const cp: u16 = @intCast('А' + value);
        out[i * 2] = @intCast(0xc0 | (cp >> 6));
        out[i * 2 + 1] = @intCast(0x80 | (cp & 63));
    }
}

fn solve(len: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cipher = try solver.normalize(a, input[0..len]);
    if (cipher.len > 4096) return error.TooLong;
    const scores = try solver.Scores.init(a);
    const found_period = solver.findPeriod(cipher);
    const answer = try solver.crackWithProgress(a, cipher, found_period, scores, notify);
    const rotation = solver.chooseKeyRotation(answer, scores);
    var key: [20]usize = undefined;
    for (answer.shifts, 0..) |value, i| key[i] = (value + rotation) % 32;
    var mixed: [32]usize = undefined;
    for (answer.mapping, 0..) |pos, letter| mixed[(pos + rotation) % 32] = letter;
    encode(key[0..found_period], &keyword);
    encode(&mixed, &alphabet);
    encode(answer.plain, &plaintext);
    period = found_period;
    plain_len = cipher.len * 2;
}

// Results remain valid until the next call. No allocation crosses the ABI.
// 0 = success, 1 = empty input, 2 = input limit, 3 = allocation/internal error.
export fn crack(len: usize) u32 {
    period = 0;
    plain_len = 0;
    if (len > input.len) return 2;
    solve(len) catch |err| return switch (err) {
        error.NoRussianLetters => 1,
        error.TooLong => 2,
        else => 3,
    };
    return 0;
}
