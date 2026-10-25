"""Regenerate Zig's counts from the original Go source (stdlib only)."""

from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
source = (root / "go/main.go").read_text()
for name, size in [("tri", 3), ("quad", 4)]:
    body = re.search(
        r"var " + name + r"Groups = \[\]ngramGroup\{(.*?)\n\}", source, re.S
    ).group(1)
    rows = []
    for count, literals in re.findall(r"\{(\d+),\s*((?:`[^`]*`\s*\+?\s*)+)\}", body):
        data = "".join(re.findall(r"`([^`]*)`", literals))
        assert len(data) % size == 0
        assert all("А" <= c <= "Я" for c in data)
        rows.append(f"{count} {data}\n")
    assert rows
    (root / "zig" / f"{name}.txt").write_text("".join(rows), encoding="utf-8")
