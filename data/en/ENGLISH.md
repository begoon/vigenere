# English puzzle: scan, missing line, and corrected edition

## Source fidelity

`crypted-en.png` is the reference scan of Figure 24-1. The original
`crypted-en.txt` transcript was checked against its eleven printed lines:
595 letters, in five-letter groups, with eleven groups on each full line and
nine on the last. That transcript is preserved as `crypted-en-book.txt`.
In particular the scan reads `CMKPA`, `QYXKJ`, `XQPOM`, `RJHVQ`, and `KAUYM`.

The supplied `crypted-book-fragment-en.png` shows the full source passage on
pages 132–133, including the Programs paragraph of Chapter 27, “Easy Does It,” in
Charles Wetherell's *Etudes for Programmers* (1978). An accessible
[transcription of the book](https://tanami.org/archive/Etudes%20for%20Programmers.html)
contains the source passage under “Compilations” and “Programs.” The encrypted
message uses STOP for sentence boundaries (including the semicolon after
“segments”), PARA for the paragraph break, and FINIS for the end. The grammar
productions between the two prose paragraphs are omitted.

`decrypted-en-source.txt` transcribes only the prose from the supplied fragment
(with grammar-angle brackets removed and the line-end word “compiled” joined).
A letter-by-letter comparison after interpreting those markers has exactly
one wording difference: the encrypted message says “all **of** the segments,”
where the source scan says “all the segments.” The corrected ciphertext keeps
that extra OF rather than silently forcing the book's prose wording. Marker
positions are also recorded in `english-corrections.json`; do not remove every
substring PARA indiscriminately, because SEPARATED also contains it. The full reconstructed message is a fixture in
`decrypted-en.txt`; the cracker never reads it.

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
`crypted-en-restored.txt` does exactly that and changes none of the 595
printed letters. Its literal decryption is `decrypted-en-restored.txt`.
Both the corrected and this minimally restored ciphertext independently
recover the key and alphabet in the Zig integration tests.

This is a source-based reconstruction, not proof of the exact characters on
a now-absent printed line. Without the source passage, the deleted letters
are not uniquely recoverable from ciphertext. The position, length, key
phase, continuation, and re-encryption all agree with this reconstruction.

## Remaining printed-letter anomalies

The minimally restored version decrypts to several misspellings, including
ACOMPIEATION and SVGMENT. `crypted-en.txt` is the corrected reading edition:
it contains the missing line and the following **16 explicit substitutions**,
corresponding to the source passage and the spelled-out terminator FINIS.
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
| 647 | 12/9/2 | K → R | H → S |

After correcting FINIH to FINIS, the last three decrypted letters are still
**ARI**. They occur after the FINIS end marker, outside the message proper.
They may be padding, but their purpose is unverified. They are retained
literally in every relevant fixture and in browser output, not removed or
reinterpreted. Five-letter grouping is also preserved (650 letters total).

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
edition differs at exactly 16 positions, and that encryption reproduces the
entire corrected ciphertext. The search tests separately verify literal
plaintext recovery rather than merely checking that the output looks English.
