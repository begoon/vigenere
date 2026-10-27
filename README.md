# Cracking a mixed-alphabet Vigenère cipher

This project solves the Russian and original English cipher puzzles from C. Wetherell's *Etudes for
Programmers*. The Vigenère base alphabet is an unknown permutation of the
32-letter Russian alphabet (without Ё) or the 26-letter English alphabet. Both the repeated keyword and the mixed
alphabet must be recovered.

Try the [online playground](https://demin.ws/vigenere/) to crack the cipher in your browser.

The Russian [Go](go/README.md), [Zig](zig/README.md), [V](vlang/README.md), and
[WebAssembly](wasm/README.md) implementations
use the same ciphertext-only attack. They share the language
counts, random generator, search budget, incremental scoring, and output format.
There is no hardcoded plaintext phrase or keyword dictionary in the solver.

The [English cracker](zig-english/README.md) is implemented only in Zig,
with its own English language model and a Wasm build. The web app switches
between Russian and English. The English example reconstructs a missing
55-letter line and explicitly corrects 16 printed letters; the original scan
transcript and minimally restored version are retained. See the
[reconstruction audit](data/en/ENGLISH.md), including the unexplained final ARI.

## Running the implementations

Each language README contains its version requirements, build/run commands,
and tests:

| Implementation | Requirements | Quick start from repository root |
| --- | --- | --- |
| [Go](go/README.md) | Go 1.26+; tested with Go 1.27.1 | `cd go && go run .` |
| [Zig English](zig-english/README.md) | Zig 0.16.0 | `cd zig-english && zig build run -Doptimize=ReleaseFast` |
| [Zig](zig/README.md) | Zig 0.16.0 | `cd zig && zig build run -Doptimize=ReleaseFast` |
| [V](vlang/README.md) | Tested with V 0.5.2 | `cd vlang && v -prod run .` |
| [Wasm / Bun](wasm/README.md) | Zig 0.16.0; tested with Bun 1.4.2 | `bun wasm/build.js && bun wasm/cli.js` |

The [static web app](docs/README.md) lives in `docs/`, ready for GitHub Pages.
It runs the Zig Wasm solver in a worker, shows progress and the recovered key,
and displays both five-letter groups and estimated word spacing in either language.
Preview with `just web-serve` and open `http://localhost:8000`.

The Russian implementations use [`data/ru/crypted-ru.txt`](data/ru/crypted-ru.txt) by default. An optional
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
result is [`data/ru/decrypted-ru.txt`](data/ru/decrypted-ru.txt); it is a test fixture,
not an input to the attack.

## Cipher model

The explanation and benchmarks below describe the Russian implementations;
see [Zig English](zig-english/README.md) for its model and initialization.

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

V additionally precombines trigram/tetragram contributions in one lookup table
and uses direct array access in the hot search functions. Its tests can force
bounds checking back on. These optimizations preserve the scoring formula and
proposal budget; see the [V implementation notes](vlang/README.md#implementation-notes).

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
optimized build, Zig ReleaseFast (native and Wasm), V `-prod`, and Bun 1.4.2.
Each implementation had one discarded warmup and three measured runs, in alternating order:

| Implementation | Version | Median elapsed time |
| --- | --- | ---: |
| V | 0.5.2 (`7ec4894`) | 4.02 s |
| Zig | 0.16.0 | 4.10 s |
| Wasm (Bun) | Zig 0.16.0 / Bun 1.4.2 | 4.44 s |
| Go | 1.27.1 | 5.36 s |

[Raw results](benchmarks/go-zig-v-wasm.json) include all samples, versions,
and input/output hashes. Wasm under Bun was about 8% slower than native Zig
in this comparison, including Bun startup and Wasm compilation/instantiation.
Measurements on a non-isolated development machine are illustrative; timings
vary across runs and machines.

All implementations use the same input, language model, single-threaded search
and proposal budget. Timings cover process startup, input/model loading, search,
and captured output; compilation is excluded. Every measured output must match
the golden key, alphabet, and plaintext. These are measurements of this puzzle
on one machine, not a general language ranking.

To reproduce the comparison from the repository root (requires Python 3 for
the benchmark script, plus Go, Zig, V, and Bun):

```sh
python3 scripts/benchmark.py --runs 3 --warmups 1 --output benchmarks/go-zig-v-wasm.json
```

Use `--runs 1 --warmups 0` for a quicker check, `--languages go`,
`--languages zig`, `--languages vlang`, or `--languages wasm` to select one
implementation, or `--input PATH` for other input. Without `--languages`, the script benchmarks
all four implementations (requiring Go, Zig, V, and Bun). Browser dictionary
loading and word segmentation are presentation steps excluded from CLI timings.

Before V's direct array access, combined score table, and explicit indexed-loop
optimizations, its median was 11.44 s ([previous results](benchmarks/go-zig-v-incremental.json)).
The [first optimized 4.42 s median](benchmarks/go-zig-v-optimized.json) was about
2.59× faster. These are separate benchmark sessions, not interleaved before/after trials; the search budget is unchanged.

Before incremental scoring, the Go/Zig medians were 25.232/22.880 seconds.
The earlier optimized medians were 6.067/4.337 seconds: improvements of
4.16×/5.28×. These were separate runs in the same session, not interleaved
before/after trials. Raw data: [original](benchmarks/go-zig-original.json) and
[incremental](benchmarks/go-zig-incremental.json).

## Tests

The three native implementations compare incremental scores with full rescoring using identical
random seeds, text lengths (1, 2, 3, 4, 17, 80, 738), periods (1, 3, 7), every
swap/column mutation, and repeated commits and rollbacks. Zig and V also
check normalization, period detection, RNG values, language counts, and rotation
invariance. Full-search tests check the detected period, key, alphabet and all
738 plaintext letters against the shared golden fixture.

Wasm imports the tested Zig solver. Its Bun tests additionally check the memory
interface, input limits, repeated calls, progress, formatting, segmentation, and
opt-in full recovery.

See the language READMEs for routine and full-test commands. Full recovery is
opt-in to keep routine tests short.

## Shared puzzle data and findings

Puzzle assets are grouped by language in [`data/ru/`](data/ru/) and
[`data/en/`](data/en/):

| File | Purpose |
| --- | --- |
| [crypted-ru.txt](data/ru/crypted-ru.txt) | Russian ciphertext used by all implementations |
| [decrypted-ru.txt](data/ru/decrypted-ru.txt) | Golden expected plaintext, used only for validation |
| [anomaly-ru.png](data/ru/anomaly-ru.png) | Image documenting the suspected transcription error |
| [crypted-en.txt](data/en/crypted-en.txt) | Reconstructed and corrected English ciphertext, used by Zig English and the web app |
| [crypted-en-book.txt](data/en/crypted-en-book.txt) | Exact 595-letter transcript of the reference scan |
| [crypted-en.png](data/en/crypted-en.png) | Reference scan of the printed English ciphertext |
| [crypted-en-restored.txt](data/en/crypted-en-restored.txt) | Missing line inserted; all printed letters preserved |
| [decrypted-en.txt](data/en/decrypted-en.txt) | Corrected English plaintext fixture; not a solver input |
| [decrypted-en-restored.txt](data/en/decrypted-en-restored.txt) | Literal plaintext of the minimally restored book message |
| [crypted-book-fragment-en.png](data/en/crypted-book-fragment-en.png) | Source plaintext scan, pages 132–133; grammar is skipped in the message |
| [decrypted-en-source.txt](data/en/decrypted-en-source.txt) | Prose-only transcription for the source comparison |
| [ENGLISH.md](data/en/ENGLISH.md) | Missing-line reconstruction and complete correction audit |
| [q.txt](data/en/q.txt) | Original supplementary text |

All four former Russian ciphertext copies and all three plaintext copies were
verified byte-for-byte identical before consolidation. The English puzzle uses the separate English model in `zig-english/`.

### English: missing line and errors in the printed ciphertext

The original English ciphertext, as shown in the [book scan](data/en/crypted-en.png),
has **both an entire missing line and erroneous letters in the remaining lines**.
These problems are present in the printed source, not introduced by our transcription:

- One **55-letter line** is missing between the lines beginning `ZTBCW` and
  `YMTIK`. Restoring it brings the ciphertext from 595 to 650 letters and
  restores the repeating key's alignment for the rest of the message.
- **16 printed letters** decrypt incorrectly when compared with the
  [source prose](data/en/crypted-book-fragment-en.png) and the expected `FINIS`
  end marker. Their corrections are inferred from the intended plaintext;
  they are documented editorial corrections, not an independently verified errata list.

The three ciphertext files deliberately preserve different stages:

| File in `data/en/` | Missing line | Original printed typos | Letters |
| --- | --- | --- | ---: |
| [crypted-en-book.txt](data/en/crypted-en-book.txt) | Still missing | Preserved | 595 |
| [crypted-en-restored.txt](data/en/crypted-en-restored.txt) | Restored | Preserved | 650 |
| [crypted-en.txt](data/en/crypted-en.txt) | Restored | 16 letters corrected | 650 |

**`crypted-en-restored.txt` still contains the book's printed typos.
`crypted-en.txt` has those 16 errors fixed.** The two files differ at exactly
16 positions. The English cracker and web app use `crypted-en.txt` by default;
the cracker itself does not insert the missing line or silently fix letters.

The missing line was reconstructed using the source passage and checked by
re-encryption; absent ciphertext cannot be uniquely recovered from ciphertext
alone. See the [reconstruction audit](data/en/ENGLISH.md) for the recovered
line, every correction, and the unexplained `ARI` suffix after `FINIS`.

### Russian: suspected transcription error

Literal decryption produces `ЧТЙОБЫЧНО`, where the surrounding Russian suggests
`ЧТООБЫЧНО`. The likely error is ciphertext `Щ` at encrypted-letter position
513 (one-based, ignoring whitespace): line 10, group 4, character 3.

```text
ЛЭЩЗН  ->  ЛЭШЗН
  ^           ^
```

Replacing `Щ` with `Ш` would produce the expected `О`. The programs and golden
fixture preserve the literal result; they do not silently modify the input.
The [anomaly image](data/ru/anomaly-ru.png) records this finding.

## Repository layout

`go/`, `zig/`, and `vlang/` contain Russian native implementations and tests.
`zig-english/` contains the English native solver, encoder, models and tests.
`wasm/` contains the Zig Wasm wrapper, build, Bun CLI, and JS tests.
`docs/` contains the static web app, built Wasm binary, and licensed dictionary.
`data/ru/` and `data/en/` contain the puzzle assets for each language. `scripts/` contains cross-language
utilities, and `benchmarks/` stores raw timing results.

The native implementations keep aggregate model counts in `tri.txt` and `quad.txt`.
Each line contains a positive count, a space, and concatenated Russian n-grams
of that size. Go embeds its files with `go:embed`, Zig uses `@embedFile`, and V
uses `$embed_file`, so the executables need no model files at runtime. Keep all
three copies identical when updating the model; Go and V tests check this.
Wasm embeds the Zig copies directly. These model files are distinct from the
puzzle inputs and golden answer in `data/`.

The former pure-Python solver is available in Git history at commit `29673fe`.
It was removed because it duplicated the same algorithm with much longer
runtimes. Python is only used for optional maintenance and benchmark scripts;
none of the solvers need it at runtime. Format those scripts with
`uv tool run black scripts`.

## Cleanup

Run `just clean` from the repository root to remove the Go and V executables, Zig
and Wasm build outputs/cache, Python bytecode caches, and the local `.venv`. Source,
model files, shared puzzle data, benchmark results, and global tool caches are
preserved, including the deployable `docs/vigenere.wasm`. Requires `just`.

## License

[MIT](LICENSE) for code. The browser word-frequency data is separately licensed
under CC BY-SA 4.0. English n-gram data is separately GNU LGPL; see
[third-party credits](docs/THIRD_PARTY.md).
