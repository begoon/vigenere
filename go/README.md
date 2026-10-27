# Go implementation

See the [main README](../README.md) for the cipher, attack, shared data,
findings, and cross-language benchmarks.

## Version

Requires Go 1.26 or newer (`go.mod`); tested with Go 1.27.1 on macOS arm64.
Only the Go standard library is used.

## Run

From this directory:

```sh
go run .
go run . ../data/crypted-ru.txt
```

For repeated runs, build once:

```sh
go build -o vigenerecrack .
./vigenerecrack
```

The optional first argument is a UTF-8 ciphertext filename. Without it, the
program locates `data/crypted-ru.txt` from the repository root or this directory.
It prints the period, keyword, mixed alphabet and entire literal plaintext in
the common output format. Input errors exit with status 1.

## Test

```sh
go test ./...
VIGENERE_INTEGRATION=1 go test ./...
```

The routine test checks incremental scores against full rescoring across the
shared mutation matrix, including rollback and cache consistency. The opt-in
integration test executes all 11.52 million proposals and verifies the period,
keyword, alphabet and [`../data/decrypted-ru.txt`](../data/decrypted-ru.txt).

## Implementation notes

`main.go` contains the solver. `tri.txt` and `quad.txt` contain the aggregate
language counts, embedded with `go:embed` at build time. They use the same
format and contents as Zig's and V's model files; Go and V tests verify that
they stay identical. The search uses `float64` scores, an explicit uint64 RNG,
precomputed mutation plans, periodic
score refreshes and reusable best-solution buffers. It runs on one thread.
