"""Build the browser word-frequency asset from the pinned FrequencyWords source.

Usage: python3 scripts/build_dictionary.py /path/to/ru_full.txt
See docs/THIRD_PARTY.md for its source URL and data license.
"""

import gzip
import hashlib
from pathlib import Path
import re
import sys

SOURCE_SHA256 = "32dfd94138aea2667ec455dcc8512029e39bd4b8ea70b09410d569b69d511a30"
ROOT = Path(__file__).resolve().parent.parent


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    source = Path(sys.argv[1]).read_bytes()
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        raise SystemExit("Source hash differs from the pinned Russian frequency list")
    words = {}
    for line in source.decode().splitlines():
        word, count = line.rsplit(" ", 1)
        word = word.upper().replace("Ё", "Е")
        count = int(count)
        if not re.fullmatch("[А-Я]+", word):
            continue
        if len(word) == 1 and word not in "АВИКОСУЯ":
            continue
        if len(word) > 1 and not re.search("[АЕИОУЫЭЮЯ]", word):
            continue
        # Exclude singleton noise, retaining rare verbs for morphology fallback.
        if count < 2 and not word.endswith("ОВАТЬ"):
            continue
        words[word] = words.get(word, 0) + count
    data = "".join(f"{word} {count}\n" for word, count in words.items()).encode()
    target = ROOT / "docs/ru-frequency.txt.gz"
    target.write_bytes(gzip.compress(data, mtime=0))
    print(f"{len(words):,} entries; {target.stat().st_size:,} gzip bytes")


if __name__ == "__main__":
    main()
