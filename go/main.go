package main

import (
	_ "embed"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

const russianAlphabet = "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"

// rng is deterministic so that the stochastic attack is reproducible.
type rng struct{ state uint64 }

func (r *rng) next() uint64 {
	x := r.state
	x ^= x << 13
	x ^= x >> 7
	x ^= x << 17
	r.state = x
	return x
}
func (r *rng) n(n int) int   { return int(r.next() % uint64(n)) }
func (r *rng) unit() float64 { return float64(r.next()>>11) / (1 << 53) }
func (r *rng) permutation() []int {
	p := make([]int, 32)
	for i := range p {
		p[i] = i
	}
	for i := 31; i > 0; i-- {
		j := r.n(i + 1)
		p[i], p[j] = p[j], p[i]
	}
	return p
}

func letterIndex(r rune) int {
	if r >= 'А' && r <= 'Я' {
		return int(r - 'А')
	}
	if r >= 'а' && r <= 'я' {
		return int(r - 'а')
	}
	return -1
}

func readCiphertext(filename string) ([]int, error) {
	b, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	var result []int
	for _, r := range string(b) {
		if x := letterIndex(r); x >= 0 {
			result = append(result, x)
		}
	}
	if len(result) == 0 {
		return nil, fmt.Errorf("no Russian letters in input")
	}
	return result, nil
}

// A repeated-key column has ordinary Russian letter frequencies, merely
// permuted. Therefore its index of coincidence reveals the key period even
// though the alphabet order is unknown.
func indexOfCoincidence(cipher []int, period int) float64 {
	total := 0.0
	for col := 0; col < period; col++ {
		var count [32]int
		n := 0
		for i := col; i < len(cipher); i += period {
			count[cipher[i]]++
			n++
		}
		if n < 2 {
			continue
		}
		pairs := 0
		for _, c := range count {
			pairs += c * (c - 1)
		}
		total += float64(pairs) / float64(n*(n-1))
	}
	return total / float64(period)
}

func findPeriod(cipher []int) int {
	limit := 20
	if len(cipher)/20 < limit {
		limit = len(cipher) / 20
	}
	best, bestIC := 1, 0.0
	for p := 1; p <= limit; p++ {
		ic := indexOfCoincidence(cipher, p)
		// Take the first convincing peak, rather than a later multiple of it.
		if ic > 0.045 {
			return p
		}
		if ic > bestIC {
			best, bestIC = p, ic
		}
	}
	return best
}

func languageScore(text []int, tri, quad []float64) float64 {
	s := 0.0
	for i := 0; i+2 < len(text); i++ {
		s += .25 * tri[(text[i]*32+text[i+1])*32+text[i+2]]
	}
	for i := 0; i+3 < len(text); i++ {
		s += quad[((text[i]*32+text[i+1])*32+text[i+2])*32+text[i+3]]
	}
	return s
}

func decode(cipher, mapping, shifts []int) []int {
	p := make([]int, len(cipher))
	for i, c := range cipher {
		p[i] = (mapping[c] - shifts[i%len(shifts)] + 32) % 32
	}
	return p
}

type solution struct {
	score                  float64
	mapping, shifts, plain []int
}

// mutationPlan contains changed letters and the union of overlapping scoring
// windows. Plans depend only on ciphertext and period, not the search state.
// Each window combines its trigram and (when present) tetragram contribution.
type mutationPlan struct{ positions, windows []int }

func makePlan(cipher []int, positions []int) mutationPlan {
	touched := make([]bool, len(cipher))
	for _, pos := range positions {
		for start := max(0, pos-3); start <= pos && start+2 < len(cipher); start++ {
			touched[start] = true
		}
	}
	plan := mutationPlan{positions: positions}
	for i, yes := range touched {
		if yes {
			plan.windows = append(plan.windows, i)
		}
	}
	return plan
}

func mutationPlans(cipher []int, period int) ([]mutationPlan, []int) {
	plans := make([]mutationPlan, 1024+period)
	columns := make([]int, len(cipher))
	for i := range cipher {
		columns[i] = i % period
	}
	for x := 0; x < 32; x++ {
		for y := x + 1; y < 32; y++ {
			var positions []int
			for i, c := range cipher {
				if c == x || c == y {
					positions = append(positions, i)
				}
			}
			plan := makePlan(cipher, positions)
			plans[x*32+y], plans[y*32+x] = plan, plan
		}
	}
	for col := 0; col < period; col++ {
		var positions []int
		for i := col; i < len(cipher); i += period {
			positions = append(positions, i)
		}
		plans[1024+col] = makePlan(cipher, positions)
	}
	return plans, columns
}

func windowScore(plain []int, i int, tri, quad []float64) float64 {
	code := (plain[i]*32+plain[i+1])*32 + plain[i+2]
	score := .25 * tri[code]
	if i+3 < len(plain) {
		score += quad[code*32+plain[i+3]]
	}
	return score
}

func refreshScores(plain []int, cached, tri, quad []float64) float64 {
	score := 0.0
	for i := range cached {
		cached[i] = windowScore(plain, i, tri, quad)
		score += cached[i]
	}
	return score
}

func updatePositions(plan mutationPlan, cipher, columns, mapping, shifts, plain []int) {
	for _, i := range plan.positions {
		plain[i] = (mapping[cipher[i]] + 32 - shifts[columns[i]]) % 32
	}
}

// Full search budget is unchanged. Only windows affected by a mutation are
// rescored; rejected proposals leave the score cache untouched.
func crack(cipher []int, period int, tri, quad []float64) solution {
	random := rng{state: 0x9e3779b97f4a7c15}
	best := solution{score: math.Inf(-1), mapping: make([]int, 32), shifts: make([]int, period), plain: make([]int, len(cipher))}
	plans, columns := mutationPlans(cipher, period)
	cached := make([]float64, max(0, len(cipher)-2))
	proposed := make([]float64, len(cached))
	const restarts, iterations, epoch = 48, 240000, 30000
	for restart := 0; restart < restarts; restart++ {
		mapping := random.permutation()
		shifts := make([]int, period)
		for i := 1; i < period; i++ {
			shifts[i] = random.n(32)
		}
		plain := decode(cipher, mapping, shifts)
		score := refreshScores(plain, cached, tri, quad)
		for iteration := 0; iteration < iterations; iteration++ {
			// Bound accumulated rounding drift once per cooling epoch.
			if iteration%epoch == 0 {
				score = refreshScores(plain, cached, tri, quad)
			}
			phase := float64(iteration%epoch) / epoch
			temp := 14*(1-phase) + .25
			swap := random.n(4) != 0 || period == 1
			var plan mutationPlan
			var x, y, col, oldShift int
			if swap {
				x, y = random.n(32), random.n(32)
				mapping[x], mapping[y] = mapping[y], mapping[x]
				plan = plans[x*32+y]
			} else {
				col = 1 + random.n(period-1)
				oldShift = shifts[col]
				shifts[col] = random.n(32)
				if shifts[col] != oldShift {
					plan = plans[1024+col]
				}
			}
			updatePositions(plan, cipher, columns, mapping, shifts, plain)
			delta := 0.0
			for j, i := range plan.windows {
				proposed[j] = windowScore(plain, i, tri, quad)
				delta += proposed[j] - cached[i]
			}
			if delta < 0 && random.unit() > math.Exp(delta/temp) {
				if swap {
					mapping[x], mapping[y] = mapping[y], mapping[x]
				} else {
					shifts[col] = oldShift
				}
				updatePositions(plan, cipher, columns, mapping, shifts, plain)
			} else {
				score += delta
				for j, i := range plan.windows {
					cached[i] = proposed[j]
				}
			}
			if score > best.score {
				best.score = score
				copy(best.mapping, mapping)
				copy(best.shifts, shifts)
				copy(best.plain, plain)
			}
		}
	}
	return best
}

// Adding the same value to all mapping entries and key shifts changes neither
// plaintext nor ciphertext. Resolve that unavoidable rotation by choosing the
// rotation for which the recovered key is itself most Russian-like.
func chooseKeyRotation(s solution, tri, quad []float64) int {
	best, bestScore := 0, math.Inf(-1)
	for rotation := 0; rotation < 32; rotation++ {
		candidate := make([]int, len(s.shifts))
		for i, x := range s.shifts {
			candidate[i] = (x + rotation) % 32
		}
		if score := languageScore(candidate, tri, quad); score > bestScore {
			best, bestScore = rotation, score
		}
	}
	return best
}

func letters(values []int) string {
	a := []rune(russianAlphabet)
	out := make([]rune, len(values))
	for i, x := range values {
		out[i] = a[x]
	}
	return string(out)
}
func recoveredAlphabet(mapping []int, rotation int) string {
	a := []rune(russianAlphabet)
	mixed := make([]rune, 32)
	for encrypted, pos := range mapping {
		mixed[(pos+rotation)%32] = a[encrypted]
	}
	return string(mixed)
}

func main() {
	filename := "data/ru/crypted-ru.txt"
	if len(os.Args) > 1 {
		filename = os.Args[1]
	} else if _, err := os.Stat(filename); os.IsNotExist(err) {
		filename = "../data/ru/crypted-ru.txt"
	}
	cipher, err := readCiphertext(filename)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	tri, quad, err := loadLanguageScores()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	period := findPeriod(cipher)
	answer := crack(cipher, period, tri, quad)
	rotation := chooseKeyRotation(answer, tri, quad)
	key := make([]int, len(answer.shifts))
	for i, x := range answer.shifts {
		key[i] = (x + rotation) % 32
	}
	fmt.Println("Detected key length:", period)
	fmt.Println("Keyword:", letters(key))
	fmt.Println("Base alphabet:", recoveredAlphabet(answer.mapping, rotation))
	fmt.Println("Decrypted text:")
	fmt.Println(letters(answer.plain))
}

// Keep the model as data, in the same format as Zig, while retaining a
// self-contained executable with no runtime model-file dependency.
//
//go:embed tri.txt
var triData string

//go:embed quad.txt
var quadData string

func loadNgramTable(data string, size int, smoothing float64) ([]float64, error) {
	table := make([]float64, 1<<(5*size))
	for i := range table {
		table[i] = math.Log(smoothing)
	}
	for lineNumber, line := range strings.Split(data, "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		if len(fields) != 2 {
			return nil, fmt.Errorf("line %d: expected count and n-grams", lineNumber+1)
		}
		count, err := strconv.Atoi(fields[0])
		if err != nil || count <= 0 {
			return nil, fmt.Errorf("line %d: invalid count %q", lineNumber+1, fields[0])
		}
		letters := []rune(fields[1])
		if len(letters)%size != 0 {
			return nil, fmt.Errorf("line %d: incomplete %d-gram", lineNumber+1, size)
		}
		value := math.Log(float64(count) + smoothing)
		for start := 0; start < len(letters); start += size {
			code := 0
			for _, letter := range letters[start : start+size] {
				if letter < 'А' || letter > 'Я' {
					return nil, fmt.Errorf("line %d: invalid letter %q", lineNumber+1, letter)
				}
				code = code*32 + int(letter-'А')
			}
			table[code] = value
		}
	}
	return table, nil
}

func loadLanguageScores() ([]float64, []float64, error) {
	tri, err := loadNgramTable(triData, 3, .05)
	if err != nil {
		return nil, nil, fmt.Errorf("tri.txt: %w", err)
	}
	quad, err := loadNgramTable(quadData, 4, .02)
	if err != nil {
		return nil, nil, fmt.Errorf("quad.txt: %w", err)
	}
	return tri, quad, nil
}
