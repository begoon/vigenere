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
