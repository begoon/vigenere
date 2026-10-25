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
	tri, quad, err := loadLanguageScores()
	if err != nil {
		t.Fatal(err)
	}
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
	cipher, err := readCiphertext("../data/crypted-ru.txt")
	if err != nil {
		t.Fatal(err)
	}
	tri, quad, err := loadLanguageScores()
	if err != nil {
		t.Fatal(err)
	}
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
	expected, err := os.ReadFile("../data/decrypted-ru.txt")
	if err != nil {
		t.Fatal(err)
	}
	if letters(answer.plain) != strings.TrimSpace(string(expected)) {
		t.Fatal("incorrect plaintext")
	}
}

func TestNgramFiles(t *testing.T) {
	for name, data := range map[string]string{"tri.txt": triData, "quad.txt": quadData} {
		zigData, err := os.ReadFile("../zig/" + name)
		if err != nil {
			t.Fatal(err)
		}
		if data != string(zigData) {
			t.Fatalf("%s differs between Go and Zig", name)
		}
	}
	tri, quad, err := loadLanguageScores()
	if err != nil {
		t.Fatal(err)
	}
	if len(tri) != 32*32*32 || len(quad) != 32*32*32*32 {
		t.Fatal("incorrect table sizes")
	}
	code := 0
	for _, letter := range "ЕНИЯ" {
		code = code*32 + letterIndex(letter)
	}
	if quad[code] != math.Log(2173.02) || quad[0] != math.Log(.02) {
		t.Fatal("incorrect counts or smoothing")
	}
}

func TestNgramTableValidation(t *testing.T) {
	for _, data := range []string{"bad АБВ", "0 АБВ", "-1 АБВ", "1 АБ", "1 АБЁ", "1 abc", "1 АБВ extra", "1"} {
		if _, err := loadNgramTable(data, 3, .05); err == nil {
			t.Errorf("accepted invalid data: %q", data)
		}
	}
	table, err := loadNgramTable("2 АБВГДЕ\n\n", 3, .05)
	if err != nil {
		t.Fatal(err)
	}
	if table[(0*32+1)*32+2] != math.Log(2.05) || table[(3*32+4)*32+5] != math.Log(2.05) {
		t.Fatal("group not expanded correctly")
	}
}
