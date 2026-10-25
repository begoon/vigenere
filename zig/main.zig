const std = @import("std");
const Allocator = std.mem.Allocator;

const Rng = struct {
    state: u64 = 0x9e3779b97f4a7c15,
    fn next(r: *Rng) u64 {
        var x = r.state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        r.state = x;
        return x;
    }
    fn n(r: *Rng, limit: usize) usize {
        return @intCast(r.next() % limit);
    }
    fn unit(r: *Rng) f64 {
        return @as(f64, @floatFromInt(r.next() >> 11)) / (1 << 53);
    }
    fn permutation(r: *Rng) [32]usize {
        var p: [32]usize = undefined;
        for (&p, 0..) |*x, i| x.* = i;
        var i: usize = 31;
        while (i > 0) : (i -= 1) std.mem.swap(usize, &p[i], &p[r.n(i + 1)]);
        return p;
    }
};

// Invalid UTF-8 bytes, grouping, punctuation and Ё are ignored, as in Go.
fn normalize(a: Allocator, bytes: []const u8) ![]usize {
    var out: std.ArrayList(usize) = .empty;
    errdefer out.deinit(a);
    var i: usize = 0;
    while (i < bytes.len) {
        const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch {
            i += 1;
            continue;
        };
        if (i + len > bytes.len) {
            i += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(bytes[i..][0..len]) catch {
            i += 1;
            continue;
        };
        i += len;
        if (cp >= 'А' and cp <= 'Я') try out.append(a, cp - 'А') else if (cp >= 'а' and cp <= 'я') try out.append(a, cp - 'а');
    }
    if (out.items.len == 0) return error.NoRussianLetters;
    return out.toOwnedSlice(a);
}

fn indexOfCoincidence(cipher: []const usize, period: usize) f64 {
    var total: f64 = 0;
    for (0..period) |col| {
        var count = [_]usize{0} ** 32;
        var n: usize = 0;
        var i = col;
        while (i < cipher.len) : (i += period) {
            count[cipher[i]] += 1;
            n += 1;
        }
        if (n < 2) continue;
        var pairs: usize = 0;
        for (count) |c| {
            if (c > 0) pairs += c * (c - 1);
        }
        total += @as(f64, @floatFromInt(pairs)) / @as(f64, @floatFromInt(n * (n - 1)));
    }
    return total / @as(f64, @floatFromInt(period));
}
fn findPeriod(cipher: []const usize) usize {
    var best: usize = 1;
    var best_ic: f64 = 0;
    for (1..@min(20, cipher.len / 20) + 1) |p| {
        const ic = indexOfCoincidence(cipher, p);
        if (ic > 0.045) return p;
        if (ic > best_ic) {
            best = p;
            best_ic = ic;
        }
    }
    return best;
}

const Scores = struct {
    tri: []f64,
    quad: []f64,
    fn init(a: Allocator) !Scores {
        const tri = try loadTable(a, @embedFile("tri.txt"), 3, 0.05);
        errdefer a.free(tri);
        return .{ .tri = tri, .quad = try loadTable(a, @embedFile("quad.txt"), 4, 0.02) };
    }
    fn deinit(s: Scores, a: Allocator) void {
        a.free(s.tri);
        a.free(s.quad);
    }
    fn score(s: Scores, text: []const usize) f64 {
        // Strict accumulation order matches Go; do not enable fast math.
        var result: f64 = 0;
        var i: usize = 0;
        while (i + 2 < text.len) : (i += 1)
            result += 0.25 * s.tri[(text[i] * 32 + text[i + 1]) * 32 + text[i + 2]];
        i = 0;
        while (i + 3 < text.len) : (i += 1)
            result += s.quad[((text[i] * 32 + text[i + 1]) * 32 + text[i + 2]) * 32 + text[i + 3]];
        return result;
    }
};
fn loadTable(a: Allocator, data: []const u8, size: usize, smoothing: f64) ![]f64 {
    const table = try a.alloc(f64, std.math.pow(usize, 32, size));
    errdefer a.free(table);
    @memset(table, @log(smoothing));
    var lines = std.mem.tokenizeScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const split = std.mem.indexOfScalar(u8, line, ' ').?;
        const count = try std.fmt.parseInt(usize, line[0..split], 10);
        const values = try normalize(a, line[split + 1 ..]);
        defer a.free(values);
        var start: usize = 0;
        while (start + size <= values.len) : (start += size) {
            var code: usize = 0;
            for (values[start..][0..size]) |x| code = code * 32 + x;
            table[code] = @log(@as(f64, @floatFromInt(count)) + smoothing);
        }
    }
    return table;
}

fn decode(cipher: []const usize, mapping: []const usize, shifts: []const usize, plain: []usize) void {
    for (cipher, 0..) |c, i| plain[i] = (mapping[c] + 32 - shifts[i % shifts.len]) % 32;
}
const Solution = struct {
    score: f64 = -std.math.inf(f64),
    mapping: [32]usize = undefined,
    shifts: []usize,
    plain: []usize,
    fn deinit(s: Solution, a: Allocator) void {
        a.free(s.shifts);
        a.free(s.plain);
    }
};
// Plans are built once: changed positions and deduplicated overlapping windows.
const MutationPlan = struct {
    positions: []const usize = &.{},
    windows: []const usize = &.{},
};
fn makePlan(a: Allocator, len: usize, positions: []const usize) !MutationPlan {
    const touched = try a.alloc(bool, len);
    defer a.free(touched);
    @memset(touched, false);
    for (positions) |pos| {
        var start = pos -| 3;
        while (start <= pos and start + 2 < len) : (start += 1) touched[start] = true;
    }
    var windows: std.ArrayList(usize) = .empty;
    for (touched, 0..) |yes, i| {
        if (yes) try windows.append(a, i);
    }
    return .{ .positions = positions, .windows = try windows.toOwnedSlice(a) };
}
const Plans = struct { mutations: []MutationPlan, columns: []usize };
// Allocated in a search-local arena, including shared symmetric swap plans.
fn mutationPlans(a: Allocator, cipher: []const usize, period: usize) !Plans {
    const plans = try a.alloc(MutationPlan, 1024 + period);
    @memset(plans, .{});
    const columns = try a.alloc(usize, cipher.len);
    for (columns, 0..) |*col, i| col.* = i % period;
    for (0..32) |x| {
        for (x + 1..32) |y| {
            var positions: std.ArrayList(usize) = .empty;
            for (cipher, 0..) |c, i| {
                if (c == x or c == y) try positions.append(a, i);
            }
            const plan = try makePlan(a, cipher.len, try positions.toOwnedSlice(a));
            plans[x * 32 + y] = plan;
            plans[y * 32 + x] = plan;
        }
    }
    for (0..period) |col| {
        var positions: std.ArrayList(usize) = .empty;
        var i = col;
        while (i < cipher.len) : (i += period) try positions.append(a, i);
        plans[1024 + col] = try makePlan(a, cipher.len, try positions.toOwnedSlice(a));
    }
    return .{ .mutations = plans, .columns = columns };
}
fn windowScore(plain: []const usize, i: usize, scores: Scores) f64 {
    const code = (plain[i] * 32 + plain[i + 1]) * 32 + plain[i + 2];
    var score = 0.25 * scores.tri[code];
    if (i + 3 < plain.len) score += scores.quad[code * 32 + plain[i + 3]];
    return score;
}
fn refreshScores(plain: []const usize, cached: []f64, scores: Scores) f64 {
    var score: f64 = 0;
    for (cached, 0..) |*value, i| {
        value.* = windowScore(plain, i, scores);
        score += value.*;
    }
    return score;
}
fn updatePositions(plan: MutationPlan, cipher: []const usize, columns: []const usize, mapping: []const usize, shifts: []const usize, plain: []usize) void {
    for (plan.positions) |i| plain[i] = (mapping[cipher[i]] + 32 - shifts[columns[i]]) % 32;
}
fn crack(a: Allocator, cipher: []const usize, period: usize, scores: Scores) !Solution {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const plans = try mutationPlans(scratch, cipher, period);
    const cached = try scratch.alloc(f64, cipher.len -| 2);
    const proposed = try scratch.alloc(f64, cached.len);
    var random: Rng = .{};
    const best_shifts = try a.alloc(usize, period);
    errdefer a.free(best_shifts);
    var best: Solution = .{ .shifts = best_shifts, .plain = try a.alloc(usize, cipher.len) };
    errdefer a.free(best.plain);
    const shifts = try scratch.alloc(usize, period);
    const plain = try scratch.alloc(usize, cipher.len);
    for (0..48) |_| {
        var mapping = random.permutation();
        shifts[0] = 0;
        for (shifts[1..]) |*x| x.* = random.n(32);
        decode(cipher, &mapping, shifts, plain);
        var score = refreshScores(plain, cached, scores);
        for (0..240000) |iteration| {
            // Bound floating-point drift once per cooling epoch.
            if (iteration % 30000 == 0) score = refreshScores(plain, cached, scores);
            const phase = @as(f64, @floatFromInt(iteration % 30000)) / 30000;
            const temp = 14 * (1 - phase) + 0.25;
            const swap = random.n(4) != 0 or period == 1;
            var plan: MutationPlan = .{};
            var x: usize = 0;
            var y: usize = 0;
            var col: usize = 0;
            var old_shift: usize = 0;
            if (swap) {
                x = random.n(32);
                y = random.n(32);
                std.mem.swap(usize, &mapping[x], &mapping[y]);
                plan = plans.mutations[x * 32 + y];
            } else {
                col = 1 + random.n(period - 1);
                old_shift = shifts[col];
                shifts[col] = random.n(32);
                if (shifts[col] != old_shift) plan = plans.mutations[1024 + col];
            }
            updatePositions(plan, cipher, plans.columns, &mapping, shifts, plain);
            var delta: f64 = 0;
            for (plan.windows, 0..) |i, j| {
                proposed[j] = windowScore(plain, i, scores);
                delta += proposed[j] - cached[i];
            }
            if (delta < 0 and random.unit() > @exp(delta / temp)) {
                if (swap) {
                    std.mem.swap(usize, &mapping[x], &mapping[y]);
                } else {
                    shifts[col] = old_shift;
                }
                updatePositions(plan, cipher, plans.columns, &mapping, shifts, plain);
            } else {
                score += delta;
                for (plan.windows, 0..) |i, j| cached[i] = proposed[j];
            }
            if (score > best.score) {
                best.score = score;
                best.mapping = mapping;
                @memcpy(best.shifts, shifts);
                @memcpy(best.plain, plain);
            }
        }
    }
    return best;
}
fn chooseKeyRotation(s: Solution, scores: Scores) usize {
    var best: usize = 0;
    var best_score = -std.math.inf(f64);
    var candidate: [20]usize = undefined;
    for (0..32) |rotation| {
        for (s.shifts, 0..) |x, i| candidate[i] = (x + rotation) % 32;
        const score = scores.score(candidate[0..s.shifts.len]);
        if (score > best_score) {
            best = rotation;
            best_score = score;
        }
    }
    return best;
}
fn writeLetters(w: *std.Io.Writer, values: []const usize) !void {
    for (values) |x| {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(@as(u21, @intCast(x)) + 'А', &buf);
        try w.writeAll(buf[0..len]);
    }
    try w.writeByte('\n');
}
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    const filename = if (args.len > 1) args[1] else "crypted-ru.txt";
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, filename, a, .unlimited) catch |err| {
        std.debug.print("{s}: {s}\n", .{ filename, @errorName(err) });
        std.process.exit(1);
    };
    const cipher = normalize(a, bytes) catch |err| {
        if (err == error.NoRussianLetters) std.debug.print("no Russian letters in input\n", .{}) else std.debug.print("{s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    const scores = try Scores.init(a);
    const period = findPeriod(cipher);
    const answer = try crack(a, cipher, period, scores);
    const rotation = chooseKeyRotation(answer, scores);
    var key: [20]usize = undefined;
    for (answer.shifts, 0..) |x, i| key[i] = (x + rotation) % 32;
    var mixed: [32]usize = undefined;
    for (answer.mapping, 0..) |pos, encrypted| mixed[(pos + rotation) % 32] = encrypted;
    var buffer: [4096]u8 = undefined;
    var output: std.Io.File.Writer = .init(.stdout(), init.io, &buffer);
    const w = &output.interface;
    try w.print("Detected key length: {d}\nKeyword: ", .{period});
    try writeLetters(w, key[0..period]);
    try w.writeAll("Base alphabet: ");
    try writeLetters(w, &mixed);
    try w.writeAll("Decrypted text:\n");
    try writeLetters(w, answer.plain);
    try w.flush();
}

test "normalization accepts cases and ignores malformed UTF-8 and Ё" {
    const a = std.testing.allocator;
    const values = try normalize(a, "А я Ёё!\xffБ\xd0");
    defer a.free(values);
    try std.testing.expectEqualSlices(usize, &.{ 0, 31, 1 }, values);
    try std.testing.expectError(error.NoRussianLetters, normalize(a, "abc Ёё"));
}
test "period detection and short inputs" {
    try std.testing.expectEqual(@as(usize, 1), findPeriod(&.{0}));
    var cipher: [140]usize = undefined;
    for (&cipher, 0..) |*x, i| x.* = i % 7;
    try std.testing.expectApproxEqAbs(@as(f64, 1), indexOfCoincidence(&cipher, 7), 1e-12);
    const a = std.testing.allocator;
    const supplied = try normalize(a, @embedFile("crypted-ru.txt"));
    defer a.free(supplied);
    try std.testing.expectEqual(@as(usize, 738), supplied.len);
    try std.testing.expectEqual(@as(usize, 7), findPeriod(supplied));
}
test "decoding is invariant under simultaneous rotation" {
    var mapping: [32]usize = undefined;
    for (&mapping, 0..) |*x, i| x.* = i;
    var plain: [4]usize = undefined;
    decode(&.{ 0, 31, 2, 3 }, &mapping, &.{ 1, 3 }, &plain);
    try std.testing.expectEqualSlices(usize, &.{ 31, 28, 1, 0 }, &plain);
    for (&mapping) |*x| x.* = (x.* + 5) % 32;
    var rotated: [4]usize = undefined;
    decode(&.{ 0, 31, 2, 3 }, &mapping, &.{ 6, 8 }, &rotated);
    try std.testing.expectEqualSlices(usize, &plain, &rotated);
}
test "language tables contain original counts and smoothing" {
    const a = std.testing.allocator;
    const scores = try Scores.init(a);
    defer scores.deinit(a);
    const letters = try normalize(a, "ЕНИЯ");
    defer a.free(letters);
    var code: usize = 0;
    for (letters) |x| code = code * 32 + x;
    try std.testing.expectApproxEqAbs(@log(@as(f64, 2173.02)), scores.quad[code], 1e-12);
    try std.testing.expectEqual(@as(f64, 0), scores.score(&.{ 0, 1 }));
}

test "RNG matches Go's unsigned 64-bit xorshift sequence" {
    var r: Rng = .{};
    for ([_]u64{ 0xdc1b77ae0bf34dad, 0x64f0eeb9026e6076, 0x7b07ce91e5906136 }) |expected|
        try std.testing.expectEqual(expected, r.next());
}

test "incremental scoring matches full rescoring across accepted and rejected moves" {
    const a = std.testing.allocator;
    const scores = try Scores.init(a);
    defer scores.deinit(a);
    for ([_]usize{ 1, 2, 3, 4, 17, 80, 738 }) |len| {
        for ([_]usize{ 1, 3, 7 }) |period| {
            var arena = std.heap.ArenaAllocator.init(a);
            defer arena.deinit();
            const scratch = arena.allocator();
            var random: Rng = .{ .state = 12345 };
            const cipher = try scratch.alloc(usize, len);
            for (cipher) |*c| c.* = random.n(32);
            var mapping = random.permutation();
            const shifts = try scratch.alloc(usize, period);
            for (shifts) |*x| x.* = random.n(32);
            const plain = try scratch.alloc(usize, len);
            const expected = try scratch.alloc(usize, len);
            decode(cipher, &mapping, shifts, plain);
            const plans = try mutationPlans(scratch, cipher, period);
            const cached = try scratch.alloc(f64, len -| 2);
            const proposed = try scratch.alloc(f64, cached.len);
            var score = refreshScores(plain, cached, scores);
            for (0..3 * plans.mutations.len) |step| {
                const id = step % plans.mutations.len;
                const plan = plans.mutations[id];
                var old_shift: usize = 0;
                if (id < 1024) {
                    std.mem.swap(usize, &mapping[id / 32], &mapping[id % 32]);
                } else {
                    old_shift = shifts[id - 1024];
                    shifts[id - 1024] = random.n(32);
                }
                updatePositions(plan, cipher, plans.columns, &mapping, shifts, plain);
                var delta: f64 = 0;
                for (plan.windows, 0..) |i, j| {
                    proposed[j] = windowScore(plain, i, scores);
                    delta += proposed[j] - cached[i];
                }
                try std.testing.expectApproxEqAbs(scores.score(plain), score + delta, 1e-7);
                if (step % 3 == 0) {
                    if (id < 1024) {
                        std.mem.swap(usize, &mapping[id / 32], &mapping[id % 32]);
                    } else {
                        shifts[id - 1024] = old_shift;
                    }
                    updatePositions(plan, cipher, plans.columns, &mapping, shifts, plain);
                } else {
                    score += delta;
                    for (plan.windows, 0..) |i, j| cached[i] = proposed[j];
                }
                decode(cipher, &mapping, shifts, expected);
                try std.testing.expectEqualSlices(usize, expected, plain);
                try std.testing.expectApproxEqAbs(scores.score(plain), score, 1e-7);
                for (cached, 0..) |value, i| try std.testing.expectEqual(windowScore(plain, i, scores), value);
            }
        }
    }
}

test "full recovery matches known key alphabet and plaintext" {
    if (!@import("test_options").integration) return error.SkipZigTest;
    const a = std.testing.allocator;
    const cipher = try normalize(a, @embedFile("crypted-ru.txt"));
    defer a.free(cipher);
    const expected = try normalize(a, @embedFile("decrypted-ru.txt"));
    defer a.free(expected);
    const scores = try Scores.init(a);
    defer scores.deinit(a);
    const period = findPeriod(cipher);
    try std.testing.expectEqual(@as(usize, 7), period);
    const answer = try crack(a, cipher, period, scores);
    defer answer.deinit(a);
    try std.testing.expectEqualSlices(usize, expected, answer.plain);
    const rotation = chooseKeyRotation(answer, scores);
    const key = try normalize(a, "РЕДИСКА");
    defer a.free(key);
    for (answer.shifts, key) |shift, letter| try std.testing.expectEqual(letter, (shift + rotation) % 32);
    const alphabet = try normalize(a, "ЕХЭЦРБТИОНЪДФГЩЯВУЗШЬЖКЛМПЫЮСЙЧА");
    defer a.free(alphabet);
    for (answer.mapping, 0..) |pos, encrypted| try std.testing.expectEqual(encrypted, alphabet[(pos + rotation) % 32]);
}
