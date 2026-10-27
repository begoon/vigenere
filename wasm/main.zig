const std = @import("std");
const solver = @import("solver");
const english = @import("build_options").english;
const alphabet_size = if (english) 26 else 32;
const letter_bytes = if (english) 1 else 2;

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

export fn alphabet_len() usize {
    return alphabet_size * letter_bytes;
}
export fn keyword_len() usize {
    return period * letter_bytes;
}

fn encode(values: []const usize, out: []u8) void {
    for (values, 0..) |value, i| {
        if (english) {
            out[i] = @intCast('A' + value);
            continue;
        }
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
    for (answer.shifts, 0..) |value, i| key[i] = (value + rotation) % alphabet_size;
    var mixed: [alphabet_size]usize = undefined;
    for (answer.mapping, 0..) |pos, letter| mixed[(pos + rotation) % alphabet_size] = letter;
    encode(key[0..found_period], &keyword);
    encode(&mixed, &alphabet);
    encode(answer.plain, &plaintext);
    period = found_period;
    plain_len = cipher.len * letter_bytes;
}

// Results remain valid until the next call. No allocation crosses the ABI.
// 0 = success, 1 = empty input, 2 = input limit, 3 = allocation/internal error.
export fn crack(len: usize) u32 {
    period = 0;
    plain_len = 0;
    if (len > input.len) return 2;
    solve(len) catch |err| return switch (err) {
        (if (english) error.NoEnglishLetters else error.NoRussianLetters) => 1,
        error.TooLong => 2,
        else => 3,
    };
    return 0;
}
