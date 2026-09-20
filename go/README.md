# Cracking the mixed-alphabet Vigenère cipher

This program performs a ciphertext-only attack against `crypted-ru.txt`. The
keyword and mixed alphabet are not stored in the program. They are recovered
at runtime using coincidence analysis, Russian-language statistics, and
simulated annealing.

## Running it

```sh
go run .
```

The default input is `crypted-ru.txt`. A different filename can be passed as
the first argument:

```sh
go run . another-ciphertext.txt
```

The search is deterministic and takes roughly 20–30 seconds on a typical
desktop. It prints the detected key length, keyword, mixed alphabet, and
plaintext.

For the supplied ciphertext, the result is:

```text
Detected key length: 7
Keyword: РЕДИСКА
Base alphabet: ЕХЭЦРБТИОНЪДФГЩЯВУЗШЬЖКЛМПЫЮСЙЧА
```

## Cipher model

The normal 32-letter Russian alphabet, without `Ё`, is:

```text
АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ
```

Let `A(x)` be the numerical position of letter `x` in that alphabet. Let `B`
be the unknown mixed alphabet, represented as an array of 32 letters. The
encryption used here is:

```text
c[i] = B[(A(p[i]) + A(k[i mod m])) mod 32]
```

where:

- `p` is the plaintext;
- `c` is the ciphertext;
- `k` is the keyword;
- `m` is the keyword length.

It is useful to search for the inverse of `B`. Define `M(c)` as the position
at which ciphertext letter `c` occurs in `B`. If `s[j]` is the numerical value
of keyword letter `j`, decryption becomes:

```text
p[i] = (M(c[i]) - s[i mod m]) mod 32
```

The unknowns are therefore one permutation `M` of the numbers 0 through 31
and `m` shift values.

## 1. Normalizing the ciphertext

`readCiphertext` reads UTF-8 text, accepts upper- or lowercase Russian
letters, removes whitespace and grouping, and converts every letter to a
number from 0 through 31. The input contains all 32 Russian letters but no
`Ё`, confirming the alphabet convention.

## 2. Finding the keyword length

For a proposed period `m`, the ciphertext is separated into `m` columns:

```text
column 0: c[0], c[m],   c[2m], ...
column 1: c[1], c[m+1], c[2m+1], ...
...
```

Every real key column was encrypted with one fixed shift and the same mixed
alphabet. That operation is a monoalphabetic substitution, so it changes the
letter labels but preserves equality and collision frequencies.

For each column, `indexOfCoincidence` computes:

```text
IC = sum(count[x] * (count[x] - 1)) / (n * (n - 1))
```

The column values are averaged. Incorrect periods are close to the random
32-letter value of `1/32`, while the correct period has the higher collision
rate of Russian text. The first clear peak is at period 7. Selecting the first
peak is important because 14 and 21 are also periods of a seven-letter key.

## 3. Scoring possible plaintext

Frequency analysis alone cannot choose among the enormous number of possible
mixed alphabets. The program therefore includes aggregate Russian trigram and
tetragram counts in `main.go`.

`loadLanguageScores` expands those counts into lookup tables. Unseen n-grams
receive a small smoothed probability, while common Russian sequences receive
higher scores. A candidate plaintext is scored as:

```text
score = 0.25 * sum(log P(trigram)) + sum(log P(tetragram))
```

Tetragrams provide most of the discrimination. Trigrams make the score less
brittle when the candidate is still far from correct. Only frequency tables
are embedded; the recovered key, alphabet, and plaintext are not present in
the model.

## 4. Searching for the alphabet and shifts

Exhaustive search is impossible: the mixed alphabet alone has `32!` possible
orders. `crack` uses simulated annealing instead.

One search state contains:

- a 32-element permutation mapping each ciphertext letter to its position in
  the hypothetical mixed alphabet;
- one shift for each of the seven key columns;
- the resulting plaintext and its Russian-language score.

The search begins with a random permutation and random shifts. It repeatedly
applies one of two mutations:

1. Swap the positions assigned to two ciphertext letters.
2. Replace the shift for one key column.

After a mutation, the affected plaintext letters are updated and the complete
text is rescored. An improvement is always accepted. A worse candidate with
score change `delta` is accepted with probability:

```text
exp(delta / temperature)
```

At high temperature this allows the search to escape local maxima. As the
temperature falls, the search becomes increasingly greedy. The implementation
uses 48 random restarts, 240,000 mutations per restart, and a cooling epoch of
30,000 mutations. A fixed pseudo-random seed makes the output reproducible.

## 5. Resolving the rotation ambiguity

There is an unavoidable algebraic ambiguity. Adding the same value `r` modulo
32 to every entry in `M` and every key shift does not change the plaintext:

```text
(M(c) + r) - (s + r) = M(c) - s
```

Consequently, ciphertext statistics can recover the alphabet and key shifts
only up to one of 32 simultaneous rotations. During the main search,
`shifts[0]` is fixed to zero to remove this redundant dimension.

After the plaintext has been recovered, `chooseKeyRotation` tries all 32
equivalent rotations and scores each resulting seven-letter key as Russian
text. The best rotation gives `РЕДИСКА`. Applying that same rotation
to the recovered permutation produces the printed mixed alphabet.

## 6. Reconstructing the mixed alphabet

The search stores the inverse relationship `M(cipherLetter) = position`.
`recoveredAlphabet` reverses it:

```text
B[position] = cipherLetter
```

This yields:

```text
ЕХЭЦРБТИОНЪДФГЩЯВУЗШЬЖКЛМПЫЮСЙЧА
```

Using this alphabet and `РЕДИСКА` in the decryption equation produces
the final plaintext.

## Ciphertext anomaly

The supplied file contains one likely transcription error. Literal decryption
produces `ЧТЙОБЫЧНО`, while the surrounding Russian clearly suggests
`ЧТООБЫЧНО`. The program intentionally prints the literal result rather
than silently modifying the ciphertext.

The corresponding ciphertext is on line 10:

```text
ВБЭКЗ ФКЫТВ ЛЕЪЭЯ ЛЭЩЗН ФХГЧК ТКЫЮЗ ...
                  ^^^
```

The complete ciphertext fragment corresponding to `ЧТЙОБЫЧНО` is:

```text
ЛЭЩЗН ФХГЧ
```

The specific anomalous letter is `Щ`:

- line 10;
- group 4, `ЛЭЩЗН`;
- character 3 within that group;
- encrypted-letter position 513 when counted from one, ignoring whitespace;
- literal plaintext value `Й`.

With the recovered keyword and alphabet, the expected plaintext letter `О`
would be produced by ciphertext letter `Ш`. Thus the likely correction is:

```text
ЛЭЩЗН  ->  ЛЭШЗН
  ^           ^
```
