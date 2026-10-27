"""Render an exact side-by-side ciphertext comparison as SVG.

Usage: python3 scripts/render_english_comparison.py [OUTPUT.svg]
The SVG uses only the archived transcript, corrected ciphertext, and audit JSON.
Render the SVG in a browser to export a PNG without changing its text.
"""

import html
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent


def render(root):
    data = root / "data/en"
    original = (data / "crypted-en-book.txt").read_text().splitlines()
    corrected = (data / "crypted-en.txt").read_text().splitlines()
    audit = json.loads((data / "english-corrections.json").read_text())
    start = audit["missing_line_after"] * 55
    missing = audit["missing_letters"]
    raw_original = "".join("".join(original).split())
    raw_corrected = "".join("".join(corrected).split())
    assert len(raw_original) == 595 and len(raw_corrected) == 650
    assert corrected[audit["missing_line_after"]] == audit["missing_ciphertext"]
    changes = {item["position"] - 1: item for item in audit["corrections"]}
    assert len(changes) == 15
    assert raw_original[-5:] == raw_corrected[-5:] == "PKYSK"
    for i, actual in enumerate(raw_corrected):
        if start <= i < start + missing:
            continue
        source = i if i < start else i - missing
        printed = raw_original[source]
        if i in changes:
            assert (printed, actual) == (changes[i]["printed"], changes[i]["corrected"])
        else:
            assert printed == actual
    for lines in (original, corrected):
        assert all(len(line.split()) == 11 for line in lines[:-1])
        assert len(lines[-1].split()) == 9

    svg = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="2240" height="864" viewBox="0 0 2240 864" role="img" aria-labelledby="title description">',
        '<title id="title">English ciphertext: original print and corrected reconstruction</title>',
        '<desc id="description">Original 595-letter transcript on the left; corrected 650-letter ciphertext on the right. Red boxes mark fifteen changed letters in both panels. A red rectangle encloses the recovered ninth line in the right panel. Original line breaks are preserved. The final group PKYSK remains unchanged.</desc>',
        '<style>text{font-family:Arial,Helvetica,sans-serif;fill:#17252d}.cipher{font-family:Menlo,"DejaVu Sans Mono",monospace;font-size:20px}.muted{fill:#64717b}.number{font-family:Menlo,monospace;font-size:13px;fill:#98a0a6}.error{fill:#ae2929}</style>',
        '<rect width="2240" height="864" fill="#f6f5f1"/>',
    ]

    def text(x, y, value, size=18, cls="", weight="normal", anchor="start"):
        svg.append(f'<text x="{x}" y="{y}" font-size="{size}" class="{cls}" font-weight="{weight}" text-anchor="{anchor}">{html.escape(value)}</text>')

    def rect(x, y, width, height, stroke, fill="none", radius=0, sw=1):
        svg.append(f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="{radius}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')

    text(48, 62, "A missing line. Fifteen changed letters.", 36, weight="bold")
    text(48, 99, "Wetherell’s English Vigenère puzzle · exact ciphertext comparison", 20, "muted")
    cell = 14
    first_baseline = 270
    row_height = 39
    for side, lines in enumerate((original, corrected)):
        panel_x = 48 + side * 1096
        text_x = panel_x + 64
        rect(panel_x, 140, 1048, 600, "#d9dcd9", "#ffffff", 10)
        text(panel_x + 28, 182, "ORIGINAL PRINT" if side == 0 else "CORRECTED RECONSTRUCTION", 23, weight="bold")
        text(panel_x + 28, 212, "595 letters · missing line and printed errors preserved" if side == 0 else "650 letters · missing line restored + 15 letter corrections", 17, "muted")
        svg.append(f'<path d="M {panel_x + 28} 231 H {panel_x + 1020}" stroke="#e6e8e6"/>')
        for row, line in enumerate(lines):
            baseline = first_baseline + row * row_height
            # Center the short final line as in the printed figure.
            indent = (65 - len(line)) * cell / 2
            text(panel_x + 31, baseline - 1, f"{row + 1:02}", cls="number", anchor="middle")
            inserted = side == 1 and row == audit["missing_line_after"]
            if inserted:
                rect(text_x - 7, baseline - 25, 65 * cell + 14, 33, "#c43b3b", "#fff3f1", 3, 2)
            letter_in_row = 0
            for col, char in enumerate(line):
                if char == " ":
                    continue
                index = row * 55 + letter_in_row
                letter_in_row += 1
                restored_index = index if side == 1 or index < start else index + missing
                changed = restored_index in changes
                x = text_x + indent + col * cell
                if changed:
                    rect(x - 1, baseline - 24, cell + 2, 31, "#c43b3b", "#fff3f1", 2, 1.6)
                text(x + cell / 2, baseline, char, cls="cipher error" if changed else "cipher", anchor="middle")
        if side == 0:
            text(panel_x + 28, 716, "Original line breaks retained; the printed message has only 11 lines.", 15, "muted")

    rect(49, 776, 18, 26, "#c43b3b", "#fff3f1", 2, 1.6)
    text(79, 795, "Changed letter (shown before and after)", 17)
    rect(500, 776, 70, 26, "#c43b3b", "#fff3f1", 3, 2)
    text(582, 795, "Recovered line 09 · 55 letters", 17)
    text(1100, 795, "Original lines 09–11 become corrected lines 10–12.", 17, "muted")
    text(48, 835, "Corrections are inferred from the source prose. Final group PKYSK is unchanged; the full plaintext ending remains FINI HARI.", 17, "muted")
    svg.append('</svg>')
    return "\n".join(svg) + "\n"


def main():
    if len(sys.argv) > 2:
        raise SystemExit(__doc__)
    target = Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT / "data/en/crypted-en-comparison.svg"
    target.write_text(render(ROOT))
    print(target)


if __name__ == "__main__":
    main()
