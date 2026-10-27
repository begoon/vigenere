module main

import math
import os
import strconv

const russian_alphabet = 'АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'

// Explicit xorshift64 state matches the other implementations.
struct Rng {
mut:
	state u64
}

fn (mut r Rng) next() u64 {
	mut x := r.state
	x ^= x << 13
	x ^= x >> 7
	x ^= x << 17
	r.state = x
	return x
}

fn (mut r Rng) n(n int) int {
	return int(r.next() % u64(n))
}

fn (mut r Rng) unit() f64 {
	return f64(r.next() >> 11) / f64(u64(1) << 53)
}

fn (mut r Rng) permutation() []int {
	mut p := []int{len: 32, init: index}
	for i := 31; i > 0; i-- {
		j := r.n(i + 1)
		p[i], p[j] = p[j], p[i]
	}
	return p
}

fn letter_index(r rune) int {
	if r >= `А` && r <= `Я` {
		return int(r - `А`)
	}
	if r >= `а` && r <= `я` {
		return int(r - `а`)
	}
	return -1
}

fn read_ciphertext(filename string) ![]int {
	data := os.read_file(filename)!
	mut result := []int{}
	for r in data.runes() {
		x := letter_index(r)
		if x >= 0 {
			result << x
		}
	}
	if result.len == 0 {
		return error('no Russian letters in input')
	}
	return result
}

fn index_of_coincidence(cipher []int, period int) f64 {
	mut total := 0.0
	for col in 0 .. period {
		mut count := [32]int{}
		mut n := 0
		for i := col; i < cipher.len; i += period {
			count[cipher[i]]++
			n++
		}
		if n < 2 {
			continue
		}
		mut pairs := 0.0
		for c in count {
			pairs += f64(c) * f64(c - 1)
		}
		total += pairs / (f64(n) * f64(n - 1))
	}
	return total / f64(period)
}

fn find_period(cipher []int) int {
	limit := math.min(20, cipher.len / 20)
	mut best := 1
	mut best_ic := 0.0
	for p := 1; p <= limit; p++ {
		ic := index_of_coincidence(cipher, p)
		// Prefer the first convincing peak over a multiple of the period.
		if ic > 0.045 {
			return p
		}
		if ic > best_ic {
			best, best_ic = p, ic
		}
	}
	return best
}

fn language_score(text []int, tri []f64, quad []f64) f64 {
	mut score := 0.0
	for i := 0; i + 2 < text.len; i++ {
		score += 0.25 * tri[(text[i] * 32 + text[i + 1]) * 32 + text[i + 2]]
	}
	for i := 0; i + 3 < text.len; i++ {
		score += quad[((text[i] * 32 + text[i + 1]) * 32 + text[i + 2]) * 32 + text[i + 3]]
	}
	return score
}

fn decode(cipher []int, mapping []int, shifts []int) []int {
	mut plain := []int{len: cipher.len}
	for i, c in cipher {
		plain[i] = (mapping[c] + 32 - shifts[i % shifts.len]) % 32
	}
	return plain
}

struct Solution {
mut:
	score   f64
	mapping []int
	shifts  []int
	plain   []int
}

struct MutationPlan {
	positions []int
	windows   []int
}

fn make_plan(cipher []int, positions []int) MutationPlan {
	mut touched := []bool{len: cipher.len}
	for pos in positions {
		for start := math.max(0, pos - 3); start <= pos && start + 2 < cipher.len; start++ {
			touched[start] = true
		}
	}
	mut windows := []int{}
	for i, yes in touched {
		if yes {
			windows << i
		}
	}
	return MutationPlan{ positions: positions, windows: windows }
}

fn mutation_plans(cipher []int, period int) ([]MutationPlan, []int) {
	mut plans := []MutationPlan{len: 1024 + period}
	columns := []int{len: cipher.len, init: index % period}
	for x in 0 .. 32 {
		for y in x + 1 .. 32 {
			mut positions := []int{}
			for i, c in cipher {
				if c == x || c == y {
					positions << i
				}
			}
			plan := make_plan(cipher, positions)
			plans[x * 32 + y], plans[y * 32 + x] = plan, plan
		}
	}
	for col in 0 .. period {
		mut positions := []int{}
		for i := col; i < cipher.len; i += period {
			positions << i
		}
		plans[1024 + col] = make_plan(cipher, positions)
	}
	return plans, columns
}

// One lookup per scoring window: the first 32^4 entries combine the
// tetragram and its trigram prefix; the final 32^3 cover the last trigram.
fn make_window_table(tri []f64, quad []f64) []f64 {
	mut table := []f64{len: quad.len + tri.len}
	for code, value in quad {
		table[code] = 0.25 * tri[code >> 5] + value
	}
	for code, value in tri {
		table[quad.len + code] = 0.25 * value
	}
	return table
}

// Plans contain only valid windows and decoded symbols are always in 0..31.
@[direct_array_access]
fn window_score(plain []int, i int, table []f64) f64 {
	code := (plain[i] * 32 + plain[i + 1]) * 32 + plain[i + 2]
	if i + 3 < plain.len {
		return table[code * 32 + plain[i + 3]]
	}
	return table[(1 << 20) + code]
}

// The cache has exactly max(0, plain.len - 2) entries.
@[direct_array_access]
fn refresh_scores(plain []int, mut cached []f64, table []f64) f64 {
	mut score := 0.0
	for i in 0 .. cached.len {
		cached[i] = window_score(plain, i, table)
		score += cached[i]
	}
	return score
}

// Plans and columns are built from this ciphertext. Mapping and shifts hold
// only 0..31, so masking by 31 is equivalent to modulo 32 here.
@[direct_array_access]
fn update_positions(plan &MutationPlan, cipher []int, columns []int, mapping []int, shifts []int, mut plain []int) {
	for j in 0 .. plan.positions.len {
		i := plan.positions[j]
		plain[i] = (mapping[cipher[i]] + 32 - shifts[columns[i]]) & 31
	}
}

// All hot-loop indexes come from bounded RNG draws or precomputed plans.
// Buffers retain their sizes throughout the search. Keep normal checks in
// input/model parsing and plan construction; no global unsafe build flag.
@[direct_array_access]
fn crack(cipher []int, period int, tri []f64, quad []f64) Solution {
	mut random := Rng{ state: 0x9e3779b97f4a7c15 }
	mut best := Solution{
		score:   math.inf(-1)
		mapping: []int{len: 32}
		shifts:  []int{len: period}
		plain:   []int{len: cipher.len}
	}
	table := make_window_table(tri, quad)
	plans, columns := mutation_plans(cipher, period)
	mut cached := []f64{len: math.max(0, cipher.len - 2)}
	mut proposed := []f64{len: cached.len}
	for _ in 0 .. 48 {
		mut mapping := random.permutation()
		mut shifts := []int{len: period}
		for i in 1 .. period {
			shifts[i] = random.n(32)
		}
		mut plain := decode(cipher, mapping, shifts)
		mut score := refresh_scores(plain, mut cached, table)
		for iteration in 0 .. 240000 {
			// Bound floating-point drift at each cooling epoch.
			if iteration % 30000 == 0 {
				score = refresh_scores(plain, mut cached, table)
			}
			phase := f64(iteration % 30000) / 30000.0
			temp := 14 * (1 - phase) + 0.25
			swap := random.n(4) != 0 || period == 1
			mut plan_id := 0 // Diagonal swap plans are empty, also used for no-op shifts.
			mut x, mut y, mut col, mut old_shift := 0, 0, 0, 0
			if swap {
				x, y = random.n(32), random.n(32)
				mapping[x], mapping[y] = mapping[y], mapping[x]
				plan_id = x * 32 + y
			} else {
				col = 1 + random.n(period - 1)
				old_shift = shifts[col]
				shifts[col] = random.n(32)
				if shifts[col] != old_shift {
					plan_id = 1024 + col
				}
			}
			plan := &plans[plan_id]
			update_positions(plan, cipher, columns, mapping, shifts, mut plain)
			mut delta := 0.0
			for j in 0 .. plan.windows.len {
				i := plan.windows[j]
				proposed[j] = window_score(plain, i, table)
				delta += proposed[j] - cached[i]
			}
			if delta < 0 && random.unit() > math.exp(delta / temp) {
				if swap {
					mapping[x], mapping[y] = mapping[y], mapping[x]
				} else {
					shifts[col] = old_shift
				}
				update_positions(plan, cipher, columns, mapping, shifts, mut plain)
			} else {
				score += delta
				for j in 0 .. plan.windows.len {
					i := plan.windows[j]
					cached[i] = proposed[j]
				}
			}
			if score > best.score {
				best.score = score
				copy(mut best.mapping, mapping)
				copy(mut best.shifts, shifts)
				copy(mut best.plain, plain)
			}
		}
	}
	return best
}

// Resolve the unavoidable global rotation by scoring all equivalent keys.
fn choose_key_rotation(s Solution, tri []f64, quad []f64) int {
	mut best := 0
	mut best_score := math.inf(-1)
	for rotation in 0 .. 32 {
		candidate := s.shifts.map((it + rotation) % 32)
		score := language_score(candidate, tri, quad)
		if score > best_score {
			best, best_score = rotation, score
		}
	}
	return best
}

fn letters(values []int) string {
	alphabet := russian_alphabet.runes()
	return values.map(alphabet[it]).string()
}

fn recovered_alphabet(mapping []int, rotation int) string {
	alphabet := russian_alphabet.runes()
	mut mixed := []rune{len: 32}
	for encrypted, pos in mapping {
		mixed[(pos + rotation) % 32] = alphabet[encrypted]
	}
	return mixed.string()
}

fn load_ngram_table(data string, size int, smoothing f64) ![]f64 {
	mut table := []f64{len: 1 << (5 * size), init: math.log(smoothing)}
	for line_number, line in data.split_into_lines() {
		fields := line.fields()
		if fields.len == 0 {
			continue
		}
		if fields.len != 2 {
			return error('line ${line_number + 1}: expected count and n-grams')
		}
		count := strconv.atoi(fields[0]) or {
			return error('line ${line_number + 1}: invalid count')
		}
		if count <= 0 {
			return error('line ${line_number + 1}: invalid count')
		}
		chars := fields[1].runes()
		if chars.len % size != 0 {
			return error('line ${line_number + 1}: incomplete ${size}-gram')
		}
		value := math.log(f64(count) + smoothing)
		for start := 0; start < chars.len; start += size {
			mut code := 0
			for letter in chars[start..start + size] {
				if letter < `А` || letter > `Я` {
					return error('line ${line_number + 1}: invalid letter')
				}
				code = code * 32 + int(letter - `А`)
			}
			table[code] = value
		}
	}
	return table
}

fn load_language_scores() !([]f64, []f64) {
	tri := load_ngram_table($embed_file('tri.txt').to_string(), 3, 0.05)!
	quad := load_ngram_table($embed_file('quad.txt').to_string(), 4, 0.02)!
	return tri, quad
}

fn main() {
	mut filename := 'data/crypted-ru.txt'
	if os.args.len > 1 {
		filename = os.args[1]
	} else if !os.exists(filename) {
		filename = '../data/crypted-ru.txt'
	}
	cipher := read_ciphertext(filename) or {
		eprintln(err)
		exit(1)
	}
	tri, quad := load_language_scores() or {
		eprintln(err)
		exit(1)
	}
	period := find_period(cipher)
	answer := crack(cipher, period, tri, quad)
	rotation := choose_key_rotation(answer, tri, quad)
	key := answer.shifts.map((it + rotation) % 32)
	println('Detected key length: ${period}')
	println('Keyword: ${letters(key)}')
	println('Base alphabet: ${recovered_alphabet(answer.mapping, rotation)}')
	println('Decrypted text:')
	println(letters(answer.plain))
}
