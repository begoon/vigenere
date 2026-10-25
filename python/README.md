# Python implementation

See the [main README](../README.md) for the cipher, attack, shared data,
findings, and cross-language benchmarks.

## Version

Requires Python 3.13 or newer; tested with CPython 3.14.8. No third-party
packages are needed. `.python-version` selects 3.13 for tools such as uv.

## Run

From this directory:

```sh
python3 main.py
python3 main.py ../data/crypted-ru.txt
```

From the repository root, `python3 python/main.py` also works. The default
ciphertext is resolved relative to the script at `../data/crypted-ru.txt`;
an explicit filename is relative to the working directory.

With uv, use `uv run main.py`. Project metadata, lockfile and Python version
configuration live in this directory.

Output uses the common period/key/alphabet/plaintext format. Input errors exit
with status 1. The pure-Python full search takes several minutes because it
performs the same 11.52 million proposals as the compiled implementations.

## Test

```sh
python3 -m unittest -v
VIGENERE_INTEGRATION=1 python3 -m unittest -v
```

Or use `uv run python -m unittest -v`. Routine tests cover normalization, period
detection, rotation invariance, language counts, the RNG, and Go's full
incremental-score test matrix. The opt-in integration test performs the complete
search and checks period, key, alphabet and all golden plaintext letters.
Fixtures are loaded from `../data/`; they are not used by the attack.

## Implementation notes

`main.py` is a pure-Python implementation, not a wrapper around Go/Zig. Explicit
64-bit masks reproduce the uint64 xorshift generator. Model files `tri.txt` and
`quad.txt` are loaded relative to the script. Regenerate them with
`python3 ../scripts/extract_ngrams.py` after changing Go's counts.

The original `crack.py` / `find_keyword.py` two-stage workflow has been replaced
by the single `main.py` entry point. Its hardcoded crib, keyword list and
`cipher-params.txt` output have been removed.
