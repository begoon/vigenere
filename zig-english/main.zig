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
    fn permutation(r: *Rng) [26]usize {
        var p: [26]usize = undefined;
        for (&p, 0..) |*x, i| x.* = i;
        var i: usize = 25;
        while (i > 0) : (i -= 1) std.mem.swap(usize, &p[i], &p[r.n(i + 1)]);
        return p;
    }
};

// ASCII English letters only; whitespace and non-English bytes are ignored.
pub fn normalize(a: Allocator, bytes: []const u8) ![]usize {
    var out: std.ArrayList(usize) = .empty;
    errdefer out.deinit(a);
    for (bytes) |byte| {
        const c = std.ascii.toUpper(byte);
        if (c >= 'A' and c <= 'Z') try out.append(a, c - 'A');
    }
    if (out.items.len == 0) return error.NoEnglishLetters;
    return out.toOwnedSlice(a);
}

fn indexOfCoincidence(cipher: []const usize, period: usize) f64 {
    var total: f64 = 0;
    for (0..period) |col| {
        var count = [_]usize{0} ** 26;
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
pub fn findPeriod(cipher: []const usize) usize {
    var best: usize = 1;
    var best_ic: f64 = 0;
    for (1..@min(20, cipher.len / 20) + 1) |p| {
        const ic = indexOfCoincidence(cipher, p);
        if (ic > 0.060) return p;
        if (ic > best_ic) {
            best = p;
            best_ic = ic;
        }
    }
    return best;
}

pub const Scores = struct {
    tri: []f64,
    quad: []f64,
    pub fn init(a: Allocator) !Scores {
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
            result += 0.25 * s.tri[(text[i] * 26 + text[i + 1]) * 26 + text[i + 2]];
        i = 0;
        while (i + 3 < text.len) : (i += 1)
            result += s.quad[((text[i] * 26 + text[i + 1]) * 26 + text[i + 2]) * 26 + text[i + 3]];
        return result;
    }
};
fn loadTable(a: Allocator, data: []const u8, size: usize, smoothing: f64) ![]f64 {
    const table = try a.alloc(f64, std.math.pow(usize, 26, size));
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
            for (values[start..][0..size]) |x| code = code * 26 + x;
            table[code] = @log(@as(f64, @floatFromInt(count)) + smoothing);
        }
    }
    return table;
}

fn decode(cipher: []const usize, mapping: []const usize, shifts: []const usize, plain: []usize) void {
    for (cipher, 0..) |c, i| plain[i] = (mapping[c] + 26 - shifts[i % shifts.len]) % 26;
}
// General encoder, used by the reconstruction audit and the standalone utility.
pub fn encrypt(plain: []const usize, key: []const usize, alphabet: []const usize, out: []usize) !void {
    if (key.len == 0 or key.len > 20 or alphabet.len != 26 or out.len != plain.len) return error.InvalidCipherParameters;
    var seen = [_]bool{false} ** 26;
    for (alphabet) |letter| {
        if (letter >= 26 or seen[letter]) return error.InvalidAlphabet;
        seen[letter] = true;
    }
    for (key) |letter| if (letter >= 26) return error.InvalidCipherParameters;
    for (plain, 0..) |letter, i| {
        if (letter >= 26) return error.InvalidCipherParameters;
        out[i] = alphabet[(letter + key[i % key.len]) % 26];
    }
}

pub const Solution = struct {
    score: f64 = -std.math.inf(f64),
    mapping: [26]usize = undefined,
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
    const plans = try a.alloc(MutationPlan, 676 + period);
    @memset(plans, .{});
    const columns = try a.alloc(usize, cipher.len);
    for (columns, 0..) |*col, i| col.* = i % period;
    for (0..26) |x| {
        for (x + 1..26) |y| {
            var positions: std.ArrayList(usize) = .empty;
            for (cipher, 0..) |c, i| {
                if (c == x or c == y) try positions.append(a, i);
            }
            const plan = try makePlan(a, cipher.len, try positions.toOwnedSlice(a));
            plans[x * 26 + y] = plan;
            plans[y * 26 + x] = plan;
        }
    }
    for (0..period) |col| {
        var positions: std.ArrayList(usize) = .empty;
        var i = col;
        while (i < cipher.len) : (i += period) try positions.append(a, i);
        plans[676 + col] = try makePlan(a, cipher.len, try positions.toOwnedSlice(a));
    }
    return .{ .mutations = plans, .columns = columns };
}
fn windowScore(plain: []const usize, i: usize, scores: Scores) f64 {
    const code = (plain[i] * 26 + plain[i + 1]) * 26 + plain[i + 2];
    var score = 0.25 * scores.tri[code];
    if (i + 3 < plain.len) score += scores.quad[code * 26 + plain[i + 3]];
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
    for (plan.positions) |i| plain[i] = (mapping[cipher[i]] + 26 - shifts[columns[i]]) % 26;
}
const KeySeed = struct {
    score: f64 = -std.math.inf(f64),
    mapping: [26]usize = undefined,
    shifts: [20]usize = undefined,
};
const english_frequencies = [_]f64{ 8.167, 1.492, 2.782, 4.253, 12.702, 2.228, 2.015, 6.094, 6.966, 0.153, 0.772, 4.025, 2.406, 6.749, 7.507, 1.929, 0.095, 5.987, 6.327, 9.056, 2.758, 0.978, 2.360, 0.150, 1.974, 0.074 };

// Hungarian assignment: the most likely bijective mixed alphabet for a key.
// Rows are ciphertext letters; columns are their positions in the alphabet.
fn assign(cost: *const [26][26]f64) KeySeed {
    var u = [_]f64{0} ** 27;
    var v = [_]f64{0} ** 27;
    var matching = [_]usize{0} ** 27;
    var way = [_]usize{0} ** 27;
    for (1..27) |row| {
        matching[0] = row;
        var j0: usize = 0;
        var minv = [_]f64{std.math.inf(f64)} ** 27;
        var used = [_]bool{false} ** 27;
        while (true) {
            used[j0] = true;
            const row0 = matching[j0];
            var delta = std.math.inf(f64);
            var j1: usize = 0;
            for (1..27) |j| {
                if (used[j]) continue;
                const cur = cost[row0 - 1][j - 1] - u[row0] - v[j];
                if (cur < minv[j]) {
                    minv[j] = cur;
                    way[j] = j0;
                }
                if (minv[j] < delta) {
                    delta = minv[j];
                    j1 = j;
                }
            }
            for (0..27) |j| {
                if (used[j]) {
                    u[matching[j]] += delta;
                    v[j] -= delta;
                } else minv[j] -= delta;
            }
            j0 = j1;
            if (matching[j0] == 0) break;
        }
        while (true) {
            const j1 = way[j0];
            matching[j0] = matching[j1];
            j0 = j1;
            if (j0 == 0) break;
        }
    }
    var result: KeySeed = .{ .score = 0 };
    for (1..27) |j| {
        const c = matching[j] - 1;
        result.mapping[c] = j - 1;
        result.score -= cost[c][j - 1];
    }
    return result;
}

// General subtitle-derived English vocabulary, independent of the puzzle.
// Rank every word of the detected length; never select a puzzle-specific key.
fn keywordSeeds(cipher: []const usize, period: usize) [32]KeySeed {
    var counts = [_][26]usize{[_]usize{0} ** 26} ** 20;
    for (cipher, 0..) |c, i| counts[i % period][c] += 1;
    var logs: [26]f64 = undefined;
    for (english_frequencies, 0..) |f, i| logs[i] = -@log(f / 100);
    var seeds = [_]KeySeed{.{}} ** 32;
    var words = std.mem.tokenizeScalar(u8, @embedFile("keywords.txt"), '\n');
    while (words.next()) |word| {
        if (word.len != period) continue;
        var shifts: [20]usize = undefined;
        for (word, 0..) |c, i| shifts[i] = (26 + @as(usize, c) - word[0]) % 26;
        var costs: [26][26]f64 = undefined;
        for (0..26) |c| for (0..26) |pos| {
            var cost: f64 = 0;
            for (0..period) |col| cost += @as(f64, @floatFromInt(counts[col][c])) * logs[(pos + 26 - shifts[col]) % 26];
            costs[c][pos] = cost;
        };
        var candidate = assign(&costs);
        candidate.shifts = shifts;
        if (candidate.score <= seeds[31].score) continue;
        var at: usize = 31;
        while (at > 0 and candidate.score > seeds[at - 1].score) : (at -= 1) seeds[at] = seeds[at - 1];
        seeds[at] = candidate;
    }
    return seeds;
}

// Fit column histograms using general English letter frequencies.
fn seedFrequencies(cipher: []const usize, mapping: *[26]usize, shifts: []usize, random: *Rng) void {
    const frequencies = english_frequencies;
    var logs: [26]f64 = undefined;
    for (frequencies, 0..) |v, i| logs[i] = @log(v);
    var counts = [_][26]usize{[_]usize{0} ** 26} ** 20;
    for (cipher, 0..) |c, i| counts[i % shifts.len][c] += 1;
    for (0..100000) |iteration| {
        const phase = @as(f64, @floatFromInt(iteration % 20000)) / 20000;
        const temp = 8 * (1 - phase) + 0.2;
        if (random.n(4) != 0 or shifts.len == 1) {
            const x = random.n(26);
            const y = random.n(26);
            var delta: f64 = 0;
            for (shifts, 0..) |shift, col| {
                const before = logs[(mapping[x] + 26 - shift) % 26];
                const after = logs[(mapping[y] + 26 - shift) % 26];
                delta += (@as(f64, @floatFromInt(counts[col][x])) - @as(f64, @floatFromInt(counts[col][y]))) * (after - before);
            }
            if (delta >= 0 or random.unit() < @exp(delta / temp)) std.mem.swap(usize, &mapping[x], &mapping[y]);
        } else {
            const col = 1 + random.n(shifts.len - 1);
            const next = random.n(26);
            var delta: f64 = 0;
            for (counts[col], 0..) |count, c| delta += @as(f64, @floatFromInt(count)) * (logs[(mapping[c] + 26 - next) % 26] - logs[(mapping[c] + 26 - shifts[col]) % 26]);
            if (delta >= 0 or random.unit() < @exp(delta / temp)) shifts[col] = next;
        }
    }
}

pub fn crack(a: Allocator, cipher: []const usize, period: usize, scores: Scores) !Solution {
    return crackWithProgress(a, cipher, period, scores, null);
}

// Optional host callback; native and WebAssembly use the same search.
pub fn crackWithProgress(a: Allocator, cipher: []const usize, period: usize, scores: Scores, progress: ?*const fn (u32) void) !Solution {
    if (period == 0 or period > 20) return error.InvalidPeriod;
    if (cipher.len == 0) return error.NoEnglishLetters;
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
    const seeds = keywordSeeds(cipher, period);
    for (0..48) |restart| {
        if (progress) |notify| notify(@intCast(restart));
        var mapping = random.permutation();
        shifts[0] = 0;
        for (shifts[1..]) |*x| x.* = random.n(26);
        if (restart < seeds.len and std.math.isFinite(seeds[restart].score)) {
            mapping = seeds[restart].mapping;
            @memcpy(shifts, seeds[restart].shifts[0..period]);
        } else seedFrequencies(cipher, &mapping, shifts, &random);
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
                x = random.n(26);
                y = random.n(26);
                std.mem.swap(usize, &mapping[x], &mapping[y]);
                plan = plans.mutations[x * 26 + y];
            } else {
                col = 1 + random.n(period - 1);
                old_shift = shifts[col];
                shifts[col] = random.n(26);
                if (shifts[col] != old_shift) plan = plans.mutations[676 + col];
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
    if (progress) |notify| notify(48);
    return best;
}
pub fn chooseKeyRotation(s: Solution, scores: Scores) usize {
    var best: usize = 0;
    var best_score = -std.math.inf(f64);
    var candidate: [20]usize = undefined;
    for (0..26) |rotation| {
        for (s.shifts, 0..) |x, i| candidate[i] = (x + rotation) % 26;
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
        const len = try std.unicode.utf8Encode(@as(u21, @intCast(x)) + 'A', &buf);
        try w.writeAll(buf[0..len]);
    }
    try w.writeByte('\n');
}
fn defaultFilename(io: std.Io) []const u8 {
    std.Io.Dir.cwd().access(io, "data/en/crypted-en.txt", .{}) catch return "../data/en/crypted-en.txt";
    return "data/en/crypted-en.txt";
}

// Test fixtures live outside the implementation; no plaintext enters the binary.
fn readTestFixture(filename: []const u8) ![]usize {
    const a = std.testing.allocator;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, filename, a, .unlimited);
    defer a.free(bytes);
    return normalize(a, bytes);
}

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    const filename = if (args.len > 1) args[1] else defaultFilename(init.io);
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, filename, a, .unlimited) catch |err| {
        std.debug.print("{s}: {s}\n", .{ filename, @errorName(err) });
        std.process.exit(1);
    };
    const cipher = normalize(a, bytes) catch |err| {
        if (err == error.NoEnglishLetters) std.debug.print("no English letters in input\n", .{}) else std.debug.print("{s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    const scores = try Scores.init(a);
    const period = findPeriod(cipher);
    const answer = try crack(a, cipher, period, scores);
    const rotation = chooseKeyRotation(answer, scores);
    var key: [20]usize = undefined;
    for (answer.shifts, 0..) |x, i| key[i] = (x + rotation) % 26;
    var mixed: [26]usize = undefined;
    for (answer.mapping, 0..) |pos, encrypted| mixed[(pos + rotation) % 26] = encrypted;
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

test "English normalization and malformed input" {
    const a = std.testing.allocator;
    const letters = try normalize(a, "a Z! Ёяé\xff");
    defer a.free(letters);
    try std.testing.expectEqualSlices(usize, &.{ 0, 25 }, letters);
    try std.testing.expectError(error.NoEnglishLetters, normalize(a, "Я!123"));
    try std.testing.expectEqual(@as(usize, 1), findPeriod(&.{0}));
}

test "minimum cost assignment is a permutation and beats greedy assignment" {
    var costs = [_][26]f64{[_]f64{1000} ** 26} ** 26;
    for (0..26) |i| costs[i][i] = 0;
    costs[0][0] = 1;
    costs[0][1] = 2;
    costs[1][0] = 1;
    costs[1][1] = 100;
    const result = assign(&costs);
    try std.testing.expectEqual(@as(f64, -3), result.score);
    try std.testing.expectEqual(@as(usize, 1), result.mapping[0]);
    try std.testing.expectEqual(@as(usize, 0), result.mapping[1]);
    for (2..26) |i| try std.testing.expectEqual(i, result.mapping[i]);
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
            for (cipher) |*c| c.* = random.n(26);
            var mapping = random.permutation();
            const shifts = try scratch.alloc(usize, period);
            for (shifts) |*x| x.* = random.n(26);
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
                if (id < 676) {
                    std.mem.swap(usize, &mapping[id / 26], &mapping[id % 26]);
                } else {
                    old_shift = shifts[id - 676];
                    shifts[id - 676] = random.n(26);
                }
                updatePositions(plan, cipher, plans.columns, &mapping, shifts, plain);
                var delta: f64 = 0;
                for (plan.windows, 0..) |i, j| {
                    proposed[j] = windowScore(plain, i, scores);
                    delta += proposed[j] - cached[i];
                }
                try std.testing.expectApproxEqAbs(scores.score(plain), score + delta, 1e-7);
                if (step % 3 == 0) {
                    if (id < 676) {
                        std.mem.swap(usize, &mapping[id / 26], &mapping[id % 26]);
                    } else {
                        shifts[id - 676] = old_shift;
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

test "reconstructed and literal book fixtures recover without answer inputs" {
    if (!@import("test_options").integration) return error.SkipZigTest;
    const a = std.testing.allocator;
    const scores = try Scores.init(a);
    defer scores.deinit(a);
    for ([_][]const u8{ "", "-restored" }) |suffix| {
        const cf = try std.fmt.allocPrint(a, "../data/en/crypted-en{s}.txt", .{suffix});
        defer a.free(cf);
        const pf = try std.fmt.allocPrint(a, "../data/en/decrypted-en{s}.txt", .{suffix});
        defer a.free(pf);
        const cipher = try readTestFixture(cf);
        defer a.free(cipher);
        const expected = try readTestFixture(pf);
        defer a.free(expected);
        try std.testing.expectEqual(@as(usize, 650), cipher.len);
        const period = findPeriod(cipher);
        try std.testing.expectEqual(@as(usize, 7), period);
        const answer = try crack(a, cipher, period, scores);
        defer answer.deinit(a);
        try std.testing.expectEqualSlices(usize, expected, answer.plain);
        const rotation = chooseKeyRotation(answer, scores);
        for (answer.shifts, "COMPILE") |shift, letter| try std.testing.expectEqual(@as(usize, letter - 'A'), (shift + rotation) % 26);
        const alphabet = "EXACRBTIONDFGWVYZHJKLMPQUS";
        for (answer.mapping, 0..) |pos, encrypted| try std.testing.expectEqual(encrypted, alphabet[(pos + rotation) % 26] - 'A');
    }
}

test "independent prose and a different key and permutation" {
    if (!@import("test_options").integration) return error.SkipZigTest;
    const a = std.testing.allocator;
    const expected = try normalize(a, "The small village stood beside a river at the edge of the forest. Every morning the baker opened his shop before the sun appeared above the trees. " ++
        "People came from the surrounding farms to buy bread and exchange stories about the weather. A young woman worked in the library across the square. " ++
        "She kept a careful record of every book and helped the children choose something interesting to read. One afternoon a stranger arrived with a wooden box full of old maps. " ++
        "He explained that his grandfather had drawn them while travelling through the mountains many years before. The librarian spread the maps across a table and studied the names of the towns. " ++
        "Some of the roads had disappeared but the river still followed the same winding course. Together they decided to make copies so that everyone could learn about the history of their home.");
    defer a.free(expected);
    var rng: Rng = .{ .state = 92871 };
    const alphabet = rng.permutation();
    const cipher = try a.alloc(usize, expected.len);
    defer a.free(cipher);
    const key = "ORANGE";
    for (expected, 0..) |letter, i| cipher[i] = alphabet[(letter + key[i % key.len] - 'A') % 26];
    try std.testing.expectEqual(key.len, findPeriod(cipher));
    const scores = try Scores.init(a);
    defer scores.deinit(a);
    const answer = try crack(a, cipher, findPeriod(cipher), scores);
    defer answer.deinit(a);
    try std.testing.expectEqualSlices(usize, expected, answer.plain);
}

test "reconstruction preserves the scan except for the documented gap and 16 corrections" {
    const a = std.testing.allocator;
    const book = try readTestFixture("../data/en/crypted-en-book.txt");
    defer a.free(book);
    const restored = try readTestFixture("../data/en/crypted-en-restored.txt");
    defer a.free(restored);
    const corrected = try readTestFixture("../data/en/crypted-en.txt");
    defer a.free(corrected);
    const plain = try readTestFixture("../data/en/decrypted-en.txt");
    defer a.free(plain);
    try std.testing.expectEqual(@as(usize, 595), book.len);
    try std.testing.expectEqual(@as(usize, 650), restored.len);
    try std.testing.expectEqualSlices(usize, book[0..440], restored[0..440]);
    try std.testing.expectEqualSlices(usize, book[440..], restored[495..]);
    try std.testing.expectEqualSlices(usize, corrected[440..495], restored[440..495]);
    var differences: usize = 0;
    for (corrected, restored) |x, y| {
        if (x != y) differences += 1;
    }
    try std.testing.expectEqual(@as(usize, 16), differences);
    const key = try normalize(a, "COMPILE");
    defer a.free(key);
    const alphabet = try normalize(a, "EXACRBTIONDFGWVYZHJKLMPQUS");
    defer a.free(alphabet);
    const encoded = try a.alloc(usize, plain.len);
    defer a.free(encoded);
    try encrypt(plain, key, alphabet, encoded);
    try std.testing.expectEqualSlices(usize, corrected, encoded);
    var duplicate = [_]usize{0} ** 26;
    try std.testing.expectError(error.InvalidAlphabet, encrypt(plain, key, &duplicate, encoded));
    try std.testing.expectError(error.InvalidCipherParameters, encrypt(plain, &.{}, alphabet, encoded));
}

test "source prose agrees apart from encrypted OF and punctuation markers" {
    const a = std.testing.allocator;
    const plain = try readTestFixture("../data/en/decrypted-en.txt");
    defer a.free(plain);
    const source = try readTestFixture("../data/en/decrypted-en-source.txt");
    defer a.free(source);
    var prose: std.ArrayList(usize) = .empty;
    defer prose.deinit(a);
    const markers = [_]struct { start: usize, len: usize }{
        .{ .start = 51, .len = 4 },
        .{ .start = 107, .len = 4 },
        .{ .start = 249, .len = 4 },
        .{ .start = 290, .len = 4 },
        .{ .start = 352, .len = 4 },
        .{ .start = 473, .len = 4 },
        .{ .start = 642, .len = 5 },
    };
    var start: usize = 0;
    for (markers) |marker| {
        try prose.appendSlice(a, plain[start..marker.start]);
        start = marker.start + marker.len;
    }
    const suffix = try normalize(a, "ARI");
    defer a.free(suffix);
    try std.testing.expectEqualSlices(usize, suffix, plain[start..]);
    try std.testing.expectEqualSlices(usize, source[0..106], prose.items[0..106]);
    try std.testing.expectEqualSlices(usize, &.{ 'O' - 'A', 'F' - 'A' }, prose.items[106..108]);
    try std.testing.expectEqualSlices(usize, source[106..], prose.items[108..]);
}
