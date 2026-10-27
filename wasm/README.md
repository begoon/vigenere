# WebAssembly implementation

Requires Zig 0.16.0 and Bun (tested with Bun 1.4.2). The Wasm module imports the
existing `zig/main.zig` solver directly: the RNG, language model, scoring,
48 × 240,000 proposal budget, and rotation selection are shared with native Zig.
There is no second solver implementation and no answer embedded in the binary.

## Build and run

From the repository root:

```sh
bun wasm/build.js
bun wasm/cli.js
bun wasm/cli.js data/ru/crypted-ru.txt
```

`build.js` runs `zig build -Doptimize=ReleaseFast` in `wasm/`, then copies the
binary to `docs/vigenere.wasm` and the sample ciphertext to `docs/crypted-ru.txt`.
The CLI reads that same Wasm binary. Set `VIGENERE_WASM=/path/to/vigenere.wasm`
to use another build. All paths except an explicit input filename are resolved
relative to the scripts, so the CLI works from any working directory.

Bun is available from <https://bun.sh/> if not already installed. There are no
npm dependencies, WASI requirements, or runtime network calls in the CLI.
Its output matches the other implementations exactly; errors exit with status 1.
Inputs are limited to 32 KiB of UTF-8 and 4,096 Russian letters to bound browser
resource use. Grouping, punctuation, non-Russian characters, and Ё are ignored.

Word-spaced readings of the supplied samples are available in
[decrypted-en-words.txt](../data/en/decrypted-en-words.txt) and
[decrypted-ru-words.txt](../data/ru/decrypted-ru-words.txt). Both are wrapped at
80 characters and preserve every decrypted letter. They are reading aids,
not inputs to the solvers.

## Tests and benchmarks

```sh
bun test wasm
VIGENERE_INTEGRATION=1 bun test wasm
python3 scripts/benchmark.py --languages wasm --runs 3 --warmups 1
```

Tests cover the memory ABI, input limits, repeated calls after memory growth,
progress, five-letter formatting, and frequency-based segmentation. Full recovery
is opt-in. Native Zig tests also exercise the shared solver. Benchmark timing
includes Bun startup, Wasm compilation/instantiation, model loading, and the full
search, but excludes the Zig build. Word segmentation is a browser presentation
step and is not included in CLI benchmarks.

## Memory interface

This is a `wasm32-freestanding` module, with exported linear memory and a single
host import, `env.progress(completedRestarts)`. `crack(inputLength)` reads the
input buffer and returns a status code. UTF-8 result buffers are read using the
exported pointer/length functions. JS recreates views after memory growth.
All search allocations are released after each call; result buffers remain
valid until the next call. `docs/solver.js` owns the shared JS adapter.

## Browser target

See [`docs/README.md`](../docs/README.md). The committed `docs/vigenere.wasm`
is intentional: GitHub Pages can serve the site without running Zig or Bun.
Rebuild it whenever the shared solver or Wasm wrapper changes.

## English

The same build also produces `docs/vigenere-en.wasm`, importing
`zig-english/main.zig`. Both variants share the wrapper and export byte lengths
for the keyword and alphabet so ASCII and Cyrillic outputs are read correctly.

```sh
bun wasm/build.js
bun wasm/cli.js --english
VIGENERE_INTEGRATION=1 bun test wasm
```

The optional filename follows `--english`. English model provenance and the
reconstruction are documented in `zig-english/README.md` and `data/en/ENGLISH.md`.
