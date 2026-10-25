# Cracking a mixed-alphabet Vigenère cipher

This project solves the Russian cipher puzzle from C. Wetherell's *Etudes for
Programmers*. The Vigenère base alphabet is an unknown permutation of the
32-letter Russian alphabet, without Ё. Both the repeated keyword and the mixed
alphabet must be recovered.

The [Go](go/README.md) and [Zig](zig/README.md) implementations use the same ciphertext-only attack. They share the language
counts, random generator, search budget, incremental scoring, and output format.
There is no hardcoded plaintext phrase or keyword dictionary in the solver.

## Running the implementations

Each language README contains its version requirements, build/run commands,
and tests:

| Implementation | Requirements | Quick start from repository root |
| --- | --- | --- |
| [Go](go/README.md) | Go 1.26+; tested with Go 1.27.1 | `cd go && go run .` |
| [Zig](zig/README.md) | Zig 0.16.0 | `cd zig && zig build run -Doptimize=ReleaseFast` |

All use [`data/crypted-ru.txt`](data/crypted-ru.txt) by default. An optional
filename selects another ciphertext. Russian letters in either case are
accepted; grouping, punctuation, Ё, and invalid UTF-8 are ignored. Input with
no Russian letters fails. The supplied ciphertext has 738 letters and yields:

```text
Detected key length: 7
Keyword: РЕДИСКА
Base alphabet: ЕХЭЦРБТИОНЪДФГЩЯВУЗШЬЖКЛМПЫЮСЙЧА
Decrypted text:
ЕДИНИЦАКОМПИЛЯЦИИЭТОЦЕПОЧКАЗАМКНУТЫХ...
```

The programs print the entire plaintext without spaces. The complete expected
result is [`data/decrypted-ru.txt`](data/decrypted-ru.txt); it is a test fixture,
not an input to the attack.

## Cipher model

Let `A(x)` be the index of letter `x` in the standard alphabet:

```text
АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ
```

Let `B` be the unknown mixed alphabet, `p` the plaintext, `k` the keyword,
and `m` the keyword length. Encryption is:

```text
c[i] = B[(A(p[i]) + A(k[i mod m])) mod 32]
```

Search for the inverse permutation `M`, where `M(c)` is ciphertext letter `c`'s
position in `B`. With key shifts `s[j] = A(k[j])`, decryption becomes:

```text
p[i] = (M(c[i]) - s[i mod m]) mod 32
```

The unknowns are a permutation of 0 through 31 and `m` shifts.

## How the attack works

### 1. Detect the keyword length

For each proposed period, split ciphertext positions into key columns:

```text
column 0: c[0], c[m],   c[2m], ...
column 1: c[1], c[m+1], c[2m+1], ...
```

A real key column undergoes a fixed monoalphabetic substitution. Letter labels
change, but collision frequencies do not. For each column, compute its index
of coincidence and average across columns:

```text
IC = sum(count[x] * (count[x] - 1)) / (n * (n - 1))
```

Random 32-letter text has IC near `1/32`. Russian text has a higher value.
The search considers periods up to `min(20, length/20)` and takes the first
average above `0.045`, otherwise the highest-scoring period. Choosing the first
peak avoids selecting a multiple of the true period. Here the first peak is 7.
Very short or statistically unusual ciphertexts can defeat this heuristic.

### 2. Score candidate plaintexts

Aggregate Russian trigram and tetragram counts become lookup tables. Unseen
sequences receive low scores; frequent Russian sequences receive higher ones:

```text
tri[t]  = log(count[t] + 0.05)
quad[q] = log(count[q] + 0.02)
score   = 0.25 * sum(tri[each trigram]) + sum(quad[each tetragram])
```

These are smoothed log counts. Probability normalization would add a constant
for fixed-length candidates, so it would not change their ranking. Tetragrams
provide most of the discrimination; trigrams help guide imperfect candidates.
The model contains aggregate counts, not the answer's key or plaintext.

### 3. Search with simulated annealing

Each restart begins with a random permutation and random column shifts. There
are two proposal types:

- Swap the mapping entries for two ciphertext letters (three quarters of proposals).
- Replace one key-column shift (one quarter; only swaps when the period is 1).

Improvements are accepted. A worse score change `delta` is accepted with
probability `exp(delta / temperature)`, allowing escape from local maxima.
Each cooling epoch uses:

```text
temperature = 14 * (1 - (iteration mod 30000) / 30000) + 0.25
```

Every implementation performs **48 restarts × 240,000 proposals**, or
11.52 million proposals, on one thread. The same xorshift64 generator and seed
`0x9e3779b97f4a7c15` make runs reproducible within a given implementation/runtime.
Floating-point differences can still change search trajectories across runtimes.

### 4. Rescore only what changes

Before searching, precompute the plaintext positions affected by each swap or
column change and the union of overlapping n-gram windows. Also cache each
position's key column, avoiding repeated modulo operations.

Each window caches its trigram and, where present, tetragram contribution.
A proposal recomputes only affected positions/windows. Accepted proposals
commit the new window scores; rejected proposals restore plaintext positions
and leave the cache untouched. Windows are deduplicated so overlapping changes
are counted once. No-op proposals use empty plans.

A full score refresh every cooling epoch limits accumulated floating-point
drift. This preserves the search budget while greatly reducing work compared
with rescoring the entire plaintext on every proposal.

### 5. Resolve the rotation ambiguity

Adding the same offset `r` to every mapping entry and key shift leaves the
plaintext unchanged:

```text
(M(c) + r) - (s + r) = M(c) - s  (mod 32)
```

The search fixes `s[0] = 0` to remove this redundant dimension. Afterwards,
all 32 equivalent keyword rotations are scored using the language model.
The most Russian-like rotation here is `РЕДИСКА`. Apply the same rotation to
the mapping, then invert it to print the mixed alphabet.

Ciphertext alone cannot identify the original rotation; choosing a
Russian-looking keyword is an additional assumption. Simulated annealing is
also heuristic, so recovery on arbitrary ciphertexts is not guaranteed.

## Benchmarks

Measured on macOS 27.0.1 arm64, using default compiler targets, Go's normal
optimized build and Zig ReleaseFast. Each implementation had one discarded
warmup and three measured runs, in alternating order:

| Implementation | Version | Median elapsed time |
| --- | --- | ---: |
| Zig | 0.16.0 | 4.34 s |
| Go | 1.27.1 | 6.07 s |

[Raw results](benchmarks/go-zig-incremental.json) include all samples, versions,
and input/output hashes. Zig was about 1.40× faster in this comparison.
Measurements on a non-isolated development machine are illustrative; timings
vary across runs and machines.

All implementations use the same input, language model, single-threaded search
and proposal budget. Timings cover process startup, input/model loading, search,
and captured output; compilation is excluded. Every measured output must match
the golden key, alphabet, and plaintext. These are measurements of this puzzle
on one machine, not a general language ranking.

To reproduce the comparison from the repository root (requires Python 3 for
the benchmark script, plus Go and Zig):

```sh
python3 scripts/benchmark.py --runs 3 --warmups 1 --output benchmarks/go-zig-incremental.json
```

Use `--runs 1 --warmups 0` for a quicker check, `--languages go` or
`--languages zig` to select one implementation, or `--input PATH` for other input.

Before incremental scoring, the Go/Zig medians were 25.232/22.880 seconds.
The earlier optimized medians were 6.067/4.337 seconds: improvements of
4.16×/5.28×. These were separate runs in the same session, not interleaved
before/after trials. Raw data: [original](benchmarks/go-zig-original.json) and
[incremental](benchmarks/go-zig-incremental.json).

## Tests

Both implementations compare incremental scores with full rescoring using identical
random seeds, text lengths (1, 2, 3, 4, 17, 80, 738), periods (1, 3, 7), every
swap/column mutation, and repeated commits and rollbacks. Zig also
check normalization, period detection, RNG values, language counts, and rotation
invariance. Full-search tests check the detected period, key, alphabet and all
738 plaintext letters against the shared golden fixture.

See the language READMEs for routine and full-test commands. Full recovery is
opt-in to keep routine tests short.

## Shared puzzle data and findings

All puzzle assets live in [`data/`](data/):

| File | Purpose |
| --- | --- |
| [crypted-ru.txt](data/crypted-ru.txt) | Russian ciphertext used by both implementations |
| [decrypted-ru.txt](data/decrypted-ru.txt) | Golden expected plaintext, used only for validation |
| [anomaly-ru.png](data/anomaly-ru.png) | Image documenting the suspected transcription error |
| [crypted-en.txt](data/crypted-en.txt) | Separate English ciphertext puzzle |
| [english.png](data/english.png) | Original English puzzle image |
| [q.txt](data/q.txt) | Original supplementary text |

All four former Russian ciphertext copies and all three plaintext copies were
verified byte-for-byte identical before consolidation. The English puzzle is
not supported by the Russian language model.

### Suspected transcription error

Literal decryption produces `ЧТЙОБЫЧНО`, where the surrounding Russian suggests
`ЧТООБЫЧНО`. The likely error is ciphertext `Щ` at encrypted-letter position
513 (one-based, ignoring whitespace): line 10, group 4, character 3.

```text
ЛЭЩЗН  ->  ЛЭШЗН
  ^           ^
```

Replacing `Щ` with `Ш` would produce the expected `О`. The programs and golden
fixture preserve the literal result; they do not silently modify the input.
The [anomaly image](data/anomaly-ru.png) records this finding.

## Repository layout

`go/` and `zig/` contain language implementations and tests.
`data/` contains the shared puzzle assets. `scripts/` contains cross-language
utilities, and `benchmarks/` stores raw timing results.

Both implementations keep aggregate model counts in `tri.txt` and `quad.txt`.
Each line contains a positive count, a space, and concatenated Russian n-grams
of that size. Go embeds its files with `go:embed`; Zig uses `@embedFile`, so
neither executable needs model files at runtime. Keep the Go and Zig copies
identical when updating the model; Go's tests check this. These model files
are distinct from the puzzle inputs and golden answer in `data/`.

The former pure-Python solver is available in Git history at commit `29673fe`.
It was removed because it duplicated the same algorithm with much longer
runtimes. Python is only used for optional maintenance and benchmark scripts;
neither solver needs it at runtime. Format those scripts with
`uv tool run black scripts`.

## License

[MIT](LICENSE).
