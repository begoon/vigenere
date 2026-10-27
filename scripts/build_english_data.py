"""Rebuild English model/vocabulary/dictionary assets from verified upstream files.

Usage: python3 scripts/build_english_data.py en_full.txt english_trigrams.txt english_quadgrams.txt
Source URLs and separate data licenses: docs/THIRD_PARTY.md.
"""

import gzip
import hashlib
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
HASHES = (
    "7fea67ab954e2c01df6c608c9826e594cf36f8823b3243554f88245fb75dc506",
    "c7b95fae56cab0869b9366050699572e15ff142083de2489435e36d6ca31ddf3",
    "b461953d6ad3b5e1f0f07c133102b7656a205529cb8697a8ecda8d45311f7a55",
)


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    sources = [Path(filename).read_bytes() for filename in sys.argv[1:]]
    for filename, source, expected in zip(sys.argv[1:], sources, HASHES):
        if hashlib.sha256(source).hexdigest() != expected:
            raise SystemExit(f"Source hash differs from the pinned data: {filename}")
    words = {}
    keywords = []
    for line in sources[0].decode().splitlines():
        raw, count = line.rsplit(" ", 1)
        count = int(count)
        if re.fullmatch("[a-z]{3,20}", raw) and count >= 100:
            keywords.append(raw.upper())
        word = raw.upper()
        if not re.fullmatch("[A-Z]+", word) or count < 2:
            continue
        if len(word) == 1 and word not in "AI":
            continue
        words[word] = words.get(word, 0) + count
    dictionary = "".join(f"{word} {count}\n" for word, count in words.items()).encode()
    (ROOT / "docs/en-frequency.txt.gz").write_bytes(gzip.compress(dictionary, mtime=0))
    (ROOT / "zig-english/keywords.txt").write_text("\n".join(keywords) + "\n")
    for name, source in zip(("tri", "quad"), sources[1:]):
        rows = (line.split() for line in source.decode().splitlines())
        (ROOT / f"zig-english/{name}.txt").write_text(
            "".join(f"{count} {gram}\n" for gram, count in rows)
        )
    print(f"Built English counts, {len(keywords):,} keywords, {len(words):,} words")


if __name__ == "__main__":
    main()
