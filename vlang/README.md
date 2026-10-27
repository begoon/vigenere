# V implementation

See the [main README](../README.md) for the cipher, attack, shared data,
findings, and cross-language benchmarks.

## Version

Tested with V 0.5.2 (`7ec4894`) on macOS arm64. Uses only V's standard library
and the C backend; no external V packages are required.

## Build and run

From this directory:

```sh
v -prod -o vigenerecrack .
./vigenerecrack
./vigenerecrack ../data/crypted-ru.txt
```

Or build and run in one command:

```sh
v -prod run .
```

Use `-prod` for the full search. The optional first argument is a UTF-8
ciphertext filename. Without it, the program locates `data/crypted-ru.txt` from
the repository root or this directory. It prints the period, keyword, mixed
alphabet and entire literal plaintext in the common output format. Input
errors exit with status 1.

## Test

```sh
v test .
v -prod -force-bounds-checking test .
VIGENERE_INTEGRATION=1 v -prod test .
```

Routine tests cover the RNG, normalization, period detection, model validation,
rotation invariance, and the same incremental-score matrix as Go and Zig,
including accepted proposals, rollback, and cache consistency. The opt-in
integration test runs all 11.52 million proposals and checks the period,
keyword, alphabet and every plaintext letter against `../data/decrypted-ru.txt`.
The expected solution is only used in tests.

To benchmark V and verify its complete CLI output, from the repository root:

```sh
python3 scripts/benchmark.py --languages vlang --runs 1 --warmups 0
```

## Implementation notes

`main.v` implements the same single-threaded search as Go and Zig: `f64`
scores, an explicit `u64` RNG, precomputed mutation plans, incremental scoring,
periodic score refreshes, and reusable score and best-solution buffers.
Floating-point differences can change the annealing trajectory across platforms.

The scoring table precombines each tetragram's score with its trigram prefix,
reducing the hot path to one lookup without changing score arithmetic. A final
trigram uses a separate tail of that table. This adds about 8.25 MiB of lookup
storage. Position updates use `& 31` for modulo 32 on nonnegative values.

The four search/scoring functions use `@[direct_array_access]` to omit redundant
bounds checks. Their indexes come from bounded random draws and precomputed
plans; buffers never resize during the search. Explicit indexed loops also
avoid generic checked element reads emitted by this V compiler for array
iteration. Input parsing, model loading, and plan construction retain checks.
The test command with `-force-bounds-checking` restores checks in these
functions to validate their index assumptions. No global bounds-check disabling
or fast-math flags are required; the search budget remains unchanged.

`tri.txt` and `quad.txt` are embedded at compile time with `$embed_file`, so the
executable needs no model files at runtime. Their format and contents match
the Go and Zig copies; V tests verify all three. Update them together.
