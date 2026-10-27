# Zig implementation

See the [main README](../README.md) for the cipher, attack, shared data,
findings, and cross-language benchmarks.

## Version

Requires Zig 0.16.0; tested on macOS arm64. The implementation uses Zig's
standard library and does not require Go or Python at runtime.

## Build and run

From this directory:

```sh
zig build -Doptimize=ReleaseFast
./zig-out/bin/vigenerecrack
./zig-out/bin/vigenerecrack ../data/ru/crypted-ru.txt
```

Or build and run in one command:

```sh
zig build run -Doptimize=ReleaseFast -- ../data/ru/crypted-ru.txt
```

The optional first argument is a UTF-8 ciphertext filename. Without it, the
program locates [data/ru/crypted-ru.txt](../data/ru/crypted-ru.txt) from the repository root or this directory.
It prints the period, keyword, mixed alphabet and entire literal plaintext in
the common output format. Input errors exit with status 1. Use an optimized
build for the full search; the default build mode is Debug.

For a word-spaced reading of the sample, see
[decrypted-ru-words.txt](../data/ru/decrypted-ru-words.txt), wrapped at 80
characters. It preserves every decrypted letter, including the `ЧТЙ` anomaly;
it is a reading aid, not an input to the cracker.

## Test

```sh
zig build test
zig build test -Doptimize=ReleaseSafe -Dintegration=true
```

Routine tests cover normalization, period detection, rotation invariance,
language counts, the RNG, and the same incremental-score matrix as Go.
The opt-in integration test executes all 11.52 million proposals and checks
the period, key, alphabet and every golden plaintext letter. Tests read the
shared fixtures in `../data/ru/`; `zig build` sets the test working directory.
The expected plaintext is not embedded in the solver.

## Implementation notes

`main.zig` uses `f64` scores and explicit uint64 RNG arithmetic. Temporary
mutation plans use a search-local arena; best-solution buffers are reused.
Arithmetic remains strict in ReleaseFast; floating-point library differences
can nevertheless change the annealing trajectory across languages/platforms.

The [WebAssembly target](../wasm/README.md) imports this solver directly.
`crackWithProgress` accepts an optional callback after each completed restart;
the native `crack` entry point uses no callback. Rebuild the web binary with
`bun wasm/build.js` from the repository root after changes to the solver.

[tri.txt](tri.txt) and [quad.txt](quad.txt) are aggregate model counts embedded at compile time.
They have the same format and contents as Go's and V's files. Update all copies
together; Go and V tests verify that they remain identical.
