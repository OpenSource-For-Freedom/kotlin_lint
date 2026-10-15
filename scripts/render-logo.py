#!/usr/bin/env python3
"""Render the README logo from the CLI's own colored output.

  assets/logo.svg   `kotlin-lint logo` as a terminal-style SVG (top of the README)

Exactly the CLI's colors, so the README shows what the terminal shows. Run after
changing assets/logo.txt:
    python3 scripts/render-logo.py
The self-test fails if the SVG's text no longer matches the CLI output.
"""
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "bin" / "kotlin-lint"

FG, BG = "#E6EDF3", "#0D1117"
SGR = {  # ANSI SGR code -> SVG attributes (same palette as the CLI)
    "38;5;78": {"fill": "#3DDC84"},  # Android green
    "38;5;99": {"fill": "#A97BFF"},  # Kotlin purple
    "2": {"fill": "#8B949E"},        # dim
    "1": {"font-weight": "bold"},
    "31": {"fill": "#FF6B6B"},
    "36": {"fill": "#56D4DD"},
}
FONT, LINE, CHAR = 14, 18, 8.43  # px; CHAR is the advance of a 14px monospace glyph


def cli(*args, stdin=""):
    env = dict(os.environ, FORCE_COLOR="1")
    env.pop("NO_COLOR", None)
    return subprocess.run(["bash", str(CLI), *args], input=stdin, capture_output=True,
                          text=True, env=env, check=False).stdout


def esc(text):
    # Non-breaking spaces: SVG renderers collapse runs of normal spaces, which would
    # squash the ASCII art. NBSP has the same width in a monospace font.
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace(" ", "&#160;"))


def to_svg(ansi, label):
    lines = ansi.rstrip("\n").split("\n")
    rows, width_cols = [], 0
    for line in lines:
        attrs, spans, col = {}, [], 0
        for part in re.split(r"(\x1b\[[0-9;]*m)", line):
            m = re.fullmatch(r"\x1b\[([0-9;]*)m", part)
            if m:
                attrs = {} if m.group(1) in ("", "0") else {**attrs, **SGR.get(m.group(1), {})}
            elif part:
                a = "".join(f' {k}="{v}"' for k, v in attrs.items())
                spans.append(f"<tspan{a}>{esc(part)}</tspan>")
                col += len(part)
        rows.append("".join(spans))
        width_cols = max(width_cols, col)
    pad_x, top = 24, 48
    width = int(pad_x * 2 + width_cols * CHAR) + 16  # +16: glyph widths vary a little by font
    height = top + LINE * len(rows) + 16
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" role="img" aria-label="{label}">',
        f'<rect width="{width}" height="{height}" rx="10" fill="{BG}"/>',
        '<circle cx="20" cy="18" r="6" fill="#FF5F56"/><circle cx="40" cy="18" r="6" fill="#FFBD2E"/>'
        '<circle cx="60" cy="18" r="6" fill="#27C93F"/>',
        f'<g font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, \'DejaVu Sans Mono\', monospace" '
        f'font-size="{FONT}" fill="{FG}">',
    ]
    out += [f'<text x="{pad_x}" y="{top + i * LINE}">{r}</text>' for i, r in enumerate(rows)]
    out += ["</g>", "</svg>", ""]
    return "\n".join(out)


def main():
    label = "kotlin-lint: the Android robot. ktlint + detekt + Compose rules for Android. Same system, new rules."
    (ROOT / "assets" / "logo.svg").write_text(to_svg(cli("logo"), label))
    print("wrote assets/logo.svg")


if __name__ == "__main__":
    main()
