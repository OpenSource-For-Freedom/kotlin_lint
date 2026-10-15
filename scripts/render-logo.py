#!/usr/bin/env python3
"""Render assets/logo.txt as assets/logo.svg (a terminal-style banner for the README).

Same colors as the CLI: robot in Android green, wordmark in Kotlin purple, tagline dimmed.
Run after editing logo.txt:  python3 scripts/render-logo.py
The self-test checks the SVG still matches logo.txt.
"""
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape


def escape(text):
    # Non-breaking spaces: SVG renderers collapse runs of normal spaces, which would
    # squash the ASCII art. NBSP has the same width in a monospace font.
    return xml_escape(text).replace(" ", "&#160;")

ROOT = Path(__file__).resolve().parent.parent
ROBOT_COLS = 26
GREEN, PURPLE, DIM, BG = "#3DDC84", "#A97BFF", "#8B949E", "#0D1117"
FONT, LINE, CHAR = 14, 18, 8.43  # px; CHAR is the advance of a 14px monospace glyph

lines = (ROOT / "assets/logo.txt").read_text().rstrip("\n").split("\n")
cols = max(len(l) for l in lines)
pad_x, top = 24, 48
width = int(pad_x * 2 + cols * CHAR)
height = top + LINE * len(lines) + 24

out = [
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="kotlin-lint: Android robot logo. ktlint + detekt + Compose rules for Android">',
    f'<rect width="{width}" height="{height}" rx="10" fill="{BG}"/>',
    '<circle cx="20" cy="18" r="6" fill="#FF5F56"/><circle cx="40" cy="18" r="6" fill="#FFBD2E"/><circle cx="60" cy="18" r="6" fill="#27C93F"/>',
    f'<g font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, \'DejaVu Sans Mono\', monospace" font-size="{FONT}">',
]
for i, line in enumerate(lines):
    left, right = line[:ROBOT_COLS], line[ROBOT_COLS:]
    right_color = DIM if ("ktlint +" in right or "same results" in right) else PURPLE
    y = top + i * LINE
    out.append(
        f'<text x="{pad_x}" y="{y}"><tspan fill="{GREEN}">{escape(left)}</tspan>'
        f'<tspan fill="{right_color}">{escape(right)}</tspan></text>'
    )
out += ["</g>", "</svg>", ""]
(ROOT / "assets/logo.svg").write_text("\n".join(out))
print(f"wrote assets/logo.svg ({width}x{height})")
