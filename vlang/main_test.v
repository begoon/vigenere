module main

import math
import os

const fixture_dir = @VMODROOT + '/../data/ru'

fn test_rng_and_normalization() {
	mut random := Rng{ state: 0x9e3779b97f4a7c15 }
	for expected in [u64(0xdc1b77ae0bf34dad), 0x64f0eeb9026e6076, 0x7b07ce91e5906136] {
		assert random.next() == expected
	}
	for r in 'АаЯяЁё abc!?'.runes() {
		assert letter_index(r) == match r {
			`А`, `а` { 0 }
			`Я`, `я` { 31 }
			else { -1 }
		}
	}
	assert find_period([0]) == 1
	cipher := read_ciphertext(fixture_dir + '/crypted-ru.txt')!
	assert cipher.len == 738
	assert find_period(cipher) == 7
}

fn test_model_and_validation() {
	for name in ['tri.txt', 'quad.txt'] {
		data := os.read_file(@VMODROOT + '/' + name)!
		for implementation in ['go', 'zig'] {
			assert data == os.read_file(@VMODROOT + '/../' + implementation + '/' + name)!
		}
	}
	tri, quad := load_language_scores()!
	assert tri.len == 32 * 32 * 32
	assert quad.len == 32 * 32 * 32 * 32
	mut code := 0
	for r in 'ЕНИЯ'.runes() {
		code = code * 32 + letter_index(r)
	}
	assert quad[code] == math.log(2173.02)
	assert quad[0] == math.log(0.02)
	for data in ['bad АБВ', '0 АБВ', '-1 АБВ', '1 АБ', '1 АБЁ', '1 abc', '1 АБВ extra',
		'1'] {
		if _ := load_ngram_table(data, 3, 0.05) {
			assert false, 'accepted invalid model: ${data}'
		}
	}
	table := load_ngram_table('2 АБВГДЕ\n\n', 3, 0.05)!
	assert table[1 * 32 + 2] == math.log(2.05)
	assert table[(3 * 32 + 4) * 32 + 5] == math.log(2.05)
}

// Every swap and column, including overlaps, absent letters and rollback.
fn test_incremental_scores() {
	tri, quad := load_language_scores()!
	table := make_window_table(tri, quad)
	for n in [1, 2, 3, 4, 17, 80, 738] {
		for period in [1, 3, 7] {
			mut random := Rng{ state: 12345 }
			mut cipher := []int{len: n}
			for i in 0 .. n {
				cipher[i] = random.n(32)
			}
			mut mapping := random.permutation()
			mut shifts := []int{len: period}
			for i in 0 .. period {
				shifts[i] = random.n(32)
			}
			mut plain := decode(cipher, mapping, shifts)
			plans, columns := mutation_plans(cipher, period)
			mut cached := []f64{len: math.max(0, n - 2)}
			mut score := refresh_scores(plain, mut cached, table)
			for step in 0 .. 3 * plans.len {
				id := step % plans.len
				plan := &plans[id]
				mut old_shift := 0
				if id < 1024 {
					x, y := id / 32, id % 32
					mapping[x], mapping[y] = mapping[y], mapping[x]
				} else {
					col := id - 1024
					old_shift = shifts[col]
					shifts[col] = random.n(32)
				}
				update_positions(plan, cipher, columns, mapping, shifts, mut plain)
				mut proposed := []f64{len: plan.windows.len}
				mut delta := 0.0
				for j, i in plan.windows {
					proposed[j] = window_score(plain, i, table)
					delta += proposed[j] - cached[i]
				}
				assert math.abs(score + delta - language_score(plain, tri, quad)) < 1e-7
				if step % 3 == 0 {
					if id < 1024 {
						x, y := id / 32, id % 32
						mapping[x], mapping[y] = mapping[y], mapping[x]
					} else {
						shifts[id - 1024] = old_shift
					}
					update_positions(plan, cipher, columns, mapping, shifts, mut plain)
				} else {
					score += delta
					for j, i in plan.windows {
						cached[i] = proposed[j]
					}
				}
				assert plain == decode(cipher, mapping, shifts)
				assert math.abs(score - language_score(plain, tri, quad)) < 1e-7
				for i, value in cached {
					assert value == window_score(plain, i, table)
				}
			}
			for rotation in 0 .. 32 {
				assert decode(cipher, mapping.map((it + rotation) % 32), shifts.map((it + rotation) % 32)) == plain
			}
		}
	}
}

fn test_full_recovery() {
	if os.getenv('VIGENERE_INTEGRATION') != '1' {
		return
	}
	cipher := read_ciphertext(fixture_dir + '/crypted-ru.txt')!
	tri, quad := load_language_scores()!
	period := find_period(cipher)
	assert period == 7
	answer := crack(cipher, period, tri, quad)
	rotation := choose_key_rotation(answer, tri, quad)
	assert letters(answer.shifts.map((it + rotation) % 32)) == 'РЕДИСКА'
	assert recovered_alphabet(answer.mapping, rotation) == 'ЕХЭЦРБТИОНЪДФГЩЯВУЗШЬЖКЛМПЫЮСЙЧА'
	expected := os.read_file(fixture_dir + '/decrypted-ru.txt')!
	assert letters(answer.plain) == expected.trim_space()
}
