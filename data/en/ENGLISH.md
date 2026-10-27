# English puzzle: scan, missing line, and corrected edition

## Source fidelity

[crypted-en.png](crypted-en.png) is the reference scan of Figure 24-1. The original
[crypted-en.txt](crypted-en.txt) transcript was checked against its eleven printed lines:
595 letters, in five-letter groups, with eleven groups on each full line and
nine on the last. That transcript is preserved as [crypted-en-book.txt](crypted-en-book.txt).
In particular the scan reads `CMKPA`, `QYXKJ`, `XQPOM`, `RJHVQ`, and `KAUYM`.

The supplied [crypted-book-fragment-en.png](crypted-book-fragment-en.png) shows
the full source text on pages 132–133, including the Programs paragraph of
Chapter 27, “Easy Does It,” in Charles Wetherell's *Etudes for Programmers*
(1978). The encrypted
message uses STOP for sentence boundaries (including the semicolon after
“segments”), PARA for the paragraph break, and FINI for the end. The grammar
productions between the two prose paragraphs are omitted.

[decrypted-en-source.txt](decrypted-en-source.txt) transcribes only the prose from the supplied fragment
(with grammar-angle brackets removed and the line-end word “compiled” joined).
A letter-by-letter comparison after interpreting those markers has exactly
one wording difference: the encrypted message says “all **of** the segments,”
where the source scan says “all the segments.” The corrected ciphertext keeps
that extra OF rather than silently forcing the book's prose wording. Marker
positions are also recorded in `english-corrections.json`; do not remove every
substring PARA indiscriminately, because SEPARATED also contains it. The full reconstructed message is a fixture in
[decrypted-en.txt](decrypted-en.txt); the cracker never reads it.
For the same message split into words and wrapped at 80 characters, see
[decrypted-en-words.txt](decrypted-en-words.txt). It preserves all 650 letters,
including STOP, PARA, and the final FINI HARI; only whitespace is added.


## Missing ninth line

After eight lines (440 letters), one full 55-letter line is missing. The
remaining print begins `YMTIK`. Since 55 modulo 7 is 6, removing this line
changes the key phase for every subsequent letter. With the recovered key
`COMPILE` and alphabet `EXACRBTIONDFGWVYZHJKLMPQUS`, the missing span of the
source passage is:

```text
NALLOFTHENORMALFEATURESOFAPROGRAMSTOPWEMIGHTASWELLNOTEH
```

It begins with the final N of CONTAIN and ends with the initial H of HERE.
Encrypting it at zero-based offset 440 gives:

```text
HASQC WRFTX ETLFY IJGOA AOLAH YQAJO BGXER JHDZX ZHFMV RFGPY YABKY
```

Insert this between the printed lines beginning `ZTBCW` and `YMTIK`.
[crypted-en-restored.txt](crypted-en-restored.txt) does exactly that and changes none of the 595
printed letters. Its literal decryption is `decrypted-en-restored.txt`.
Both the corrected and this minimally restored ciphertext independently
recover the key and alphabet in the Zig integration tests.

This is a source-based reconstruction, not proof of the exact characters on
a now-absent printed line. Without the source passage, the deleted letters
are not uniquely recoverable from ciphertext. The position, length, key
phase, continuation, and re-encryption all agree with this reconstruction.

## Remaining printed-letter anomalies

The minimally restored version decrypts to several misspellings, including
ACOMPIEATION and SVGMENT. [crypted-en.txt](crypted-en.txt) is the corrected reading edition:
it contains the missing line and the following **15 explicit substitutions**,
corresponding to the source passage. The ending FINI HARI needs no correction.
They are editorial corrections, not changes silently made by the cracker.
Positions are one-based in the **restored 650-letter** message; line/group/letter
use eleven groups of five per line. The machine-readable audit is
`english-corrections.json`.

| Position | Line/group/letter | Ciphertext | Plaintext |
| ---: | --- | --- | --- |
| 7 | 1/2/2 | O → Y | E → L |
| 61 | 2/2/1 | C → G | V → E |
| 135 | 3/5/5 | O → P | U → I |
| 227 | 5/2/2 | C → G | R → A |
| 342 | 7/3/2 | N → J | Y → H |
| 397 | 8/3/2 | C → G | V → E |
| 404 | 8/4/4 | S → Z | R → I |
| 409 | 8/5/4 | C → G | R → A |
| 411 | 8/6/1 | C → G | V → E |
| 433 | 8/10/3 | A → F | R → A |
| 434 | 8/10/4 | F → A | H → Y |
| 548 | 10/11/3 | A → Y | O → B |
| 557 | 11/2/2 | Y → T | A → R |
| 572 | 11/5/2 | C → G | V → E |
| 601 | 11/11/1 | A → S | R → O |

## The ending: FINI HARI

The literal ending is **FINIHARI**, naturally read as **FINI HARI**:
FINI is French for “finished” and serves as the end marker; HARI is the
signature of Miss Hari, the French-speaking spy introduced in Chapter 24,
“A Code of Dishonor.” STOP is the ordinary period marker.

This ending is not a typo or unexplained padding. Do not change FINIH to
FINIS: the H begins HARI. The final ciphertext group stays **PKYSK**, exactly
as printed, in both the restored and corrected editions. All 650 letters
are retained. The prose scan contains the compiler passage; the signature's
context comes from Chapter 24's story.

## Why the English Zig cracker differs from the Russian one

The [Russian Zig solver](../../zig/README.md) and
[English Zig solver](../../zig-english/README.md) attack the same kind of
mixed-alphabet Vigenère cipher: both the alphabet permutation and the repeating
key are unknown. Their main difference is how they choose starting candidates
for the search, in addition to using different alphabets and language models.

| Component | Russian (`zig/`) | English (`zig-english/`) |
| --- | --- | --- |
| Alphabet | 32 Russian letters, excluding Ё | 26 English letters, A–Z |
| Plaintext scoring | Russian trigram and tetragram counts | English trigram and tetragram counts |
| Period detection | First mean column coincidence above 0.045, otherwise the strongest candidate | Same rule, with threshold 0.060 |
| Starting candidates | Random alphabet permutations and key shifts | Up to 32 vocabulary-ranked candidates; remaining restarts use frequency-seeded random candidates |
| Contextual search | 48 restarts × 240,000 proposals | Same, plus the initialization work described below |
| Final key rotation | Score 32 equivalent rotations | Score 26 equivalent rotations |

Both period detectors consider lengths up to `min(20, ciphertext_length / 20)`.
Their thresholds are language-specific heuristics, not guarantees that the
first peak is the true period.

### Why the English initialization was added

During development, adapting the Russian random-start search to English did
not consistently recover the English message within the same search budget.
Even correcting letters in the ciphertext could change whether a run
converged: those changes alter candidate scores and the sequence of accepted
moves. A preliminary letter-frequency search alone also did not make recovery
consistent across the restored and corrected examples.

The additional initialization supplies more promising starting points before
the contextual search. This is an observation about these samples, models,
and search settings, not evidence that English is inherently harder to crack
than Russian. The Russian implementation recovered its supplied puzzle without
this extra machinery, so it retains the simpler initialization.

### How vocabulary ranking and Hungarian assignment work

1. **Infer a key length from the ciphertext.** Consider every word of that
   length in a general English vocabulary. The vocabulary contains 58,076
   words of length 3–20 occurring at least 100 times in the pinned
   FrequencyWords source. It was filtered by those general rules, not selected
   to contain the puzzle's answer.
2. **Treat each word as a candidate key.** Its letter values give the shifts
   for the repeating key columns. Count occurrences of each ciphertext letter
   in each column.
3. **Build a 26 × 26 assignment-cost table.** A row represents a ciphertext
   letter and a column represents its proposed position in the mixed alphabet.
   Given the candidate key, that assignment determines a plaintext letter in
   each key column. Its cost is the sum of observed counts multiplied by the
   negative log of the corresponding general English letter frequency.
4. **Find the best bijective alphabet for that key.** The Hungarian algorithm
   minimizes the total assignment cost while using every alphabet position
   exactly once. Choosing the cheapest position independently for each letter
   could assign several letters to the same position, which would not be a
   valid alphabet permutation.
5. **Rank the candidates by their assignment scores.** Keep the best 32 as
   starting points for the contextual search. These are starting guesses,
   not accepted answers: letter frequencies alone do not establish readable
   plaintext.

The other 16 restarts begin with random permutations and shifts, then run
100,000 preliminary annealing proposals scored by single-letter frequencies.
If fewer than 32 vocabulary candidates are available, more restarts use that
fallback; if none are available, all 48 do. Thus equal contextual proposal
counts do not mean equal total work: English also ranks vocabulary candidates
and performs frequency-based initialization.

### What remains the same, and what the solver does not know

After initialization, both solvers perform simulated annealing with swaps of
alphabet entries and changes to key-column shifts. They score candidate
plaintext with log tetragram counts plus 0.25 times log trigram counts, rescore
only affected windows, and use the same contextual cooling schedule. The
English search can change the proposed key as well as the alphabet; it is not
restricted to returning a vocabulary word.

Both remove a redundant rotation during the search by fixing the first key
shift to zero. Afterwards they score equivalent key rotations with their
language's n-gram model to choose a plausible displayed keyword. Ciphertext
alone cannot identify which equivalent rotation the author used.

The English vocabulary and frequency tables are general language data. The
cracker does not read the known plaintext, the scans, the reconstruction audit,
or the expected key and alphabet from the tests. Reconstruction of the missing
line and editorial correction of printed letters are separate preparation
steps; the cracker receives the resulting ciphertext and recovers its literal
plaintext. Native and browser/Wasm execution use the same Zig solver.

Vocabulary initialization favors word-like keys, and recovery remains
heuristic for arbitrary keys, short messages, or unusual language. Integration
tests check both English editions and an independently written passage with a
different key and alphabet; they do not establish a general success rate.
The extra machinery could also be implemented in Go or added to Russian Zig.
It is an implementation choice, not a limitation of Go or a requirement of Zig.

## Reproduce the checks

From `zig-english/`:

```sh
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseSafe -Dintegration=true
zig build -Doptimize=ReleaseFast
./zig-out/bin/vigenere-encrypt-en ../data/en/decrypted-en.txt COMPILE EXACRBTIONDFGWVYZHJKLMPQUS > /tmp/reconstructed-en.txt
diff ../data/en/crypted-en.txt /tmp/reconstructed-en.txt
```

The audit verifies that removing offsets 440–494 from the minimally restored
file reproduces every original scan-transcript letter, that the corrected
edition differs at exactly 15 positions, and that encryption reproduces the
entire corrected ciphertext. The search tests separately verify literal
plaintext recovery rather than merely checking that the output looks English.
