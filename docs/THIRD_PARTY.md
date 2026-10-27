# Russian word-frequency data

`ru-frequency.txt.gz` is a filtered and compressed Russian frequency list from
[FrequencyWords by Hermit Dave](https://github.com/hermitdave/FrequencyWords),
based on OpenSubtitles 2018.

- Source: <https://raw.githubusercontent.com/hermitdave/FrequencyWords/525f9b560de45753a5ea01069454e72e9aa541c6/content/2018/ru/ru_full.txt>
- Revision: `525f9b560de45753a5ea01069454e72e9aa541c6`
- Data license: [Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/)
- Original corpus: <https://opus.nlpl.eu/OpenSubtitles2018.php>
- Original SHA-256: `32dfd94138aea2667ec455dcc8512029e39bd4b8ea70b09410d569b69d511a30`

The derived data is distributed under **CC BY-SA 4.0**, separate from this
repository's MIT-licensed code. Changes made by this project: fold case and Ё
to Е, retain Russian-only tokens, exclude unlikely single-letter words and
multi-letter tokens without vowels, remove singleton counts except `-овать`
infinitives, combine duplicate counts, and gzip the result. The reproducible
transformation is `scripts/build_dictionary.py`.

At runtime the segmenter estimates additional productive verb forms. Word
segmentation is an estimate and does not change the decrypted letters.

# English word-frequency data and keyword vocabulary

`en-frequency.txt.gz` and `zig-english/keywords.txt` derive from
[Hermit Dave's FrequencyWords](https://github.com/hermitdave/FrequencyWords),
OpenSubtitles 2018, revision `525f9b560de45753a5ea01069454e72e9aa541c6`.

- Source: <https://raw.githubusercontent.com/hermitdave/FrequencyWords/525f9b560de45753a5ea01069454e72e9aa541c6/content/2018/en/en_full.txt>
- Original SHA-256: `7fea67ab954e2c01df6c608c9826e594cf36f8823b3243554f88245fb75dc506`
- Data license: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)

The English dictionary folds case, keeps ASCII-letter words with count >= 2,
retains only A/I as single-letter words, combines duplicate counts, and gzips
with a fixed timestamp. It has 538,263 entries. The keyword vocabulary keeps
lowercase ASCII words of length 3–20 with counts >= 100 and folds them to
uppercase, yielding 58,076 entries. Neither transformation uses the puzzle
plaintext or selects a known keyword. These derived assets remain CC BY-SA
4.0 data, separate from the MIT code. The keyword list is embedded in the
English native and Wasm binaries; the spacing dictionary is fetched locally.

# English n-gram counts

`zig-english/tri.txt` and `quad.txt` derive from
[John Burkardt's NGRAMS dataset](https://people.sc.fsu.edu/~jburkardt/datasets/ngrams/ngrams.html).
The upstream page identifies its data license as **GNU LGPL** (without an
explicit version). The upstream raw counts are preserved; only each row's
columns are reversed from `NGRAM COUNT` to `COUNT NGRAM`. The data license
remains separate from this repository's MIT code. Counts are embedded in the
English native and Wasm binaries; the complete transformed data and rebuild
sources are distributed here.

- <https://people.sc.fsu.edu/~jburkardt/datasets/ngrams/english_trigrams.txt>
  SHA-256: `c7b95fae56cab0869b9366050699572e15ff142083de2489435e36d6ca31ddf3`
- <https://people.sc.fsu.edu/~jburkardt/datasets/ngrams/english_quadgrams.txt>
  SHA-256: `b461953d6ad3b5e1f0f07c133102b7656a205529cb8697a8ecda8d45311f7a55`

The monogram initializer uses the standard approximate English A–Z percentage
table beginning 8.167, 1.492, 2.782, 4.253, 12.702. These are general language
frequencies, not measurements of the puzzle's answer.

To reproduce all English derived assets, download the three pinned-by-hash
sources above and run:

```sh
python3 scripts/build_english_data.py /path/to/en_full.txt /path/to/english_trigrams.txt /path/to/english_quadgrams.txt
bun wasm/build.js
```

No data download occurs while cracking. Python is only a maintenance tool;
the English cracker and encryption utility are implemented in Zig.
