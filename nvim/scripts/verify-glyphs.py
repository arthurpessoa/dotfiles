#!/usr/bin/env python3
"""Check every codepoint in shared/icons.lua against the Nerd Font's cmap.

bar.lua records a glyph that "resolves in the font but came out blank", so
presence in the cmap is necessary but not sufficient -- :IconAudit is the
second half of this check. This half is the one that can run unattended.

Run from the repository root:  python nvim/scripts/verify-glyphs.py
"""
import re
import sys
from pathlib import Path

try:
    from fontTools.ttLib import TTFont
except ImportError:
    sys.exit("fontTools is required: pip install fonttools")

FONT_CANDIDATES = [
    Path("C:/Windows/Fonts/JetBrainsMonoNerdFont-Regular.ttf"),
    Path.home() / "AppData/Local/Microsoft/Windows/Fonts/JetBrainsMonoNerdFont-Regular.ttf",
    Path.home() / ".local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf",
    Path("/usr/share/fonts/truetype/JetBrainsMonoNerdFont-Regular.ttf"),
]

REGISTRY = Path("shared/icons.lua")
# Matches `name = { glyph = u(0xe738), ...` and `M.FALLBACK = { glyph = u(0xf018d)`
ENTRY = re.compile(r"(\w+)\s*=\s*\{\s*glyph\s*=\s*u\(0x([0-9a-fA-F]+)\)")


def find_font() -> Path:
    for path in FONT_CANDIDATES:
        if path.exists():
            return path
    sys.exit("JetBrainsMono Nerd Font not found in any known location")


def main() -> int:
    if not REGISTRY.exists():
        sys.exit(f"{REGISTRY} not found -- run from the repository root")

    entries = ENTRY.findall(REGISTRY.read_text(encoding="utf-8"))
    if not entries:
        sys.exit(f"no glyph entries parsed out of {REGISTRY}")

    font_path = find_font()
    cmap = TTFont(font_path, fontNumber=0).getBestCmap()

    missing = [(name, cp) for name, cp in entries if int(cp, 16) not in cmap]

    print(f"font:    {font_path}")
    print(f"checked: {len(entries)} codepoints")

    if missing:
        print(f"missing: {len(missing)}")
        for name, cp in missing:
            print(f"  {name:<12} U+{cp.upper()}")
        print("\nGive each of these an explicit fallback in shared/icons.lua.")
        return 1

    print("missing: 0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
