# English mixed-alphabet Vigenère cracker

A standalone Zig 0.16 implementation for the 26-letter English alphabet.
The runtime needs only ciphertext: no plaintext fixture, known key, known
permutation, scan, network service, Go, V, or Python is used by the cracker.
The browser imports this exact solver as `docs/vigenere-en.wasm`.

```sh
cd zig-english
zig build -Doptimize=ReleaseFast
./zig-out/bin/vigenerecrack-en
./zig-out/bin/vigenerecrack-en ../data/en/crypted-en-restored.txt
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseSafe -Dintegration=true
```

The default is [data/en/crypted-en.txt](../data/en/crypted-en.txt) (from the root) or [../data/en/crypted-en.txt](../data/en/crypted-en.txt)
(from this directory): the reconstructed, corrected 650-letter sample.
ASCII A–Z/a–z are accepted; other bytes are ignored. Empty input fails.
Output has the same period/key/alphabet/plaintext format as the Russian solver.
Use ReleaseFast for searches. Recovery is heuristic, especially on short text,
non-word keys, unusual language, and ciphertext with missing sections.

For a word-spaced reading of the sample, see
[decrypted-en-words.txt](../data/en/decrypted-en-words.txt), wrapped at 80
characters. It preserves all 650 decrypted letters and the ending `FINI HARI`;
it is a reading aid, not an input to the cracker.

## Attack

Encryption is `c[i] = B[(p[i] + key[i % period]) % 26]`, with an unknown
permutation B. Mean column coincidence suggests the period: take the first
period above 0.060, or the strongest candidate, among 1 through
`min(20, length / 20)`. This is a heuristic, not a proof of period.

General English trigram and tetragram counts score candidate text. The score
is the sum of log tetragram counts plus 0.25 times the sum of log trigram
counts, with 0.02 and 0.05 smoothing respectively. Proposals update only the
affected windows. No puzzle text is included in those counts.

English keyword initialization uses a **general vocabulary**, not an answer
list: all 58,076 lowercase ASCII words of length 3–20 with at least 100
occurrences in the pinned English FrequencyWords source. For every word of
the inferred period, a Hungarian assignment finds the most likely bijective
alphabet under standard English letter frequencies. The best 32 assignments
seed contextual searches. The remaining 16 restarts use random keys and
frequency annealing; if no words have the inferred length, all restarts use
that fallback. This biases recovery toward English-word keys but does not
force them: the search can change both the key shifts and alphabet.

Each of 48 restarts makes 240,000 contextual proposals, swapping two alphabet
entries or changing a column shift. The cooling schedule and incremental
window scoring follow the Russian Zig implementation. A fixed xorshift seed
makes searches repeatable within a build; different floating-point targets can
follow different trajectories. Progress reports completed restarts; the initial
keyword-ranking phase can leave the progress indicator at zero briefly.

The first key shift is fixed at zero to remove rotation redundancy. The final
26 equivalent key rotations are ranked by English n-grams. Ciphertext cannot
distinguish equivalent rotations, so the displayed word is a language-based
choice. For the supplied example it is `COMPILE` and the alphabet is
`EXACRBTIONDFGWVYZHJKLMPQUS`.

## Reconstruction is separate from cracking

See [the data audit](../data/en/ENGLISH.md). The absent line was reconstructed
using the source passage and independently checked by re-encryption. A
ciphertext-only cracker cannot uniquely infer 55 entirely absent letters.
The original 595-letter print transcript remains available; this solver does
not silently insert letters, correct spelling, or repair phase discontinuities.

The separate encoder accepts an explicit key and alphabet, so the reconstruction
can be reproduced without changing the cracker:

```sh
./zig-out/bin/vigenere-encrypt-en ../data/en/decrypted-en.txt COMPILE EXACRBTIONDFGWVYZHJKLMPQUS > /tmp/reconstructed-en.txt
diff ../data/en/crypted-en.txt /tmp/reconstructed-en.txt
```

Routine tests check normalization, assignment optimality, incremental scoring,
input constraints, and the reconstruction's exact preservation and round trip.
Integration tests recover both corrected and literal restored text, plus
independently written prose encrypted with a different key and permutation.
Golden plaintext and keys occur only in tests, not in the search.

## Language data

[tri.txt](tri.txt) and [quad.txt](quad.txt) derive from John Burkardt's general English n-gram
collection (upstream GNU LGPL data). [keywords.txt](keywords.txt) derives from Hermit Dave's
FrequencyWords / OpenSubtitles 2018 (CC BY-SA 4.0 data). These data licenses
are separate from the MIT source-code license. Sources, hashes, transformations,
and rebuild instructions are in [third-party credits](../docs/THIRD_PARTY.md).
