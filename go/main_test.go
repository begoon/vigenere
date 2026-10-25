package main

import (
	"math"
	"os"
	"strings"
	"testing"
)

// Exercise every swap/column, including absent letters, overlapping windows,
// short texts, accepted proposals and rejected proposals.
func TestIncrementalScores(t *testing.T) {
	tri, quad := loadLanguageScores()
	for _, n := range []int{1, 2, 3, 4, 17, 80, 738} {
		for _, period := range []int{1, 3, 7} {
			random := rng{state: 12345}
			cipher := make([]int, n)
			for i := range cipher {
				cipher[i] = random.n(32)
			}
			mapping := random.permutation()
			shifts := make([]int, period)
			for i := range shifts {
				shifts[i] = random.n(32)
			}
			plain := decode(cipher, mapping, shifts)
			plans, columns := mutationPlans(cipher, period)
			cached := make([]float64, max(0, n-2))
			score := refreshScores(plain, cached, tri, quad)
			for step := 0; step < 3*len(plans); step++ {
				id := step % len(plans)
				plan := plans[id]
				oldShift := 0
				if id < 1024 {
					x, y := id/32, id%32
					mapping[x], mapping[y] = mapping[y], mapping[x]
				} else {
					col := id - 1024
					oldShift = shifts[col]
					shifts[col] = random.n(32)
				}
				updatePositions(plan, cipher, columns, mapping, shifts, plain)
				proposed := make([]float64, len(plan.windows))
				delta := 0.0
				for j, i := range plan.windows {
					proposed[j] = windowScore(plain, i, tri, quad)
					delta += proposed[j] - cached[i]
				}
				full := languageScore(plain, tri, quad)
				if math.Abs(score+delta-full) > 1e-7 {
					t.Fatalf("n=%d period=%d step=%d: incremental %g, full %g", n, period, step, score+delta, full)
				}
				if step%3 == 0 {
					if id < 1024 {
						x, y := id/32, id%32
						mapping[x], mapping[y] = mapping[y], mapping[x]
					} else {
						shifts[id-1024] = oldShift
					}
					updatePositions(plan, cipher, columns, mapping, shifts, plain)
				} else {
					score += delta
					for j, i := range plan.windows {
						cached[i] = proposed[j]
					}
				}
				expected := decode(cipher, mapping, shifts)
				for i := range plain {
					if plain[i] != expected[i] {
						t.Fatal("partial decode mismatch")
					}
				}
				if math.Abs(score-languageScore(plain, tri, quad)) > 1e-7 {
					t.Fatal("score mismatch after commit/rollback")
				}
				for i, v := range cached {
					if v != windowScore(plain, i, tri, quad) {
						t.Fatal("stale cache entry")
					}
				}
			}
		}
	}
}

func TestFullRecovery(t *testing.T) {
	if os.Getenv("VIGENERE_INTEGRATION") != "1" {
		t.Skip("full search is opt-in")
	}
	cipher, err := readCiphertext("crypted-ru.txt")
	if err != nil {
		t.Fatal(err)
	}
	tri, quad := loadLanguageScores()
	period := findPeriod(cipher)
	if period != 7 {
		t.Fatalf("period = %d", period)
	}
	answer := crack(cipher, period, tri, quad)
	rotation := chooseKeyRotation(answer, tri, quad)
	key := make([]int, period)
	for i, shift := range answer.shifts {
		key[i] = (shift + rotation) % 32
	}
	if letters(key) != "РЕДИСКА" {
		t.Fatal("incorrect keyword")
	}
	if recoveredAlphabet(answer.mapping, rotation) != "ЕХЭЦРБТИОНЪДФГЩЯВУЗШЬЖКЛМПЫЮСЙЧА" {
		t.Fatal("incorrect alphabet")
	}
	expected, err := os.ReadFile("decrypted-ru.txt")
	if err != nil {
		t.Fatal(err)
	}
	if letters(answer.plain) != strings.TrimSpace(string(expected)) {
		t.Fatal("incorrect plaintext")
	}
}
