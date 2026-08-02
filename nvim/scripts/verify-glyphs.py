#!/usr/bin/env python3
"""Check every codepoint in shared/icons.lua against the Nerd Font's cmap.

bar.lua records a glyph that "resolves in the font but came out blank", so
presence in the cmap is necessary but not sufficient. A codepoint can map to
a glyph that the font ships with no outlines at all -- an empty simple glyph
(numberOfContours == 0) with zero advance width -- which is exactly that
failure mode and is checkable without a human looking at a screen, unlike
:IconAudit, which remains the visual pass for everything else (hinting,
overlaps, wrong-weight fallbacks) this can't see.

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


def find_blank(font: "TTFont", cmap: dict, present: list) -> list:
    """Glyphs the cmap resolves to but that carry no visible ink.

    A simple glyph with zero contours and zero advance width was never drawn
    -- it is the font shipping a placeholder for a codepoint it claims to
    support, which is indistinguishable from "missing" on screen even though
    it passes the cmap check above. numberOfContours == -1 means a composite
    glyph (built from other glyphs' outlines) and is not blank; only 0 is.
    """
    if "glyf" not in font:
        sys.exit("font has no glyf table -- this check only supports TrueType outlines")

    glyf = font["glyf"]
    hmtx = font["hmtx"]
    blank = []
    for name, cp, glyph_name in present:
        glyph = glyf[glyph_name]
        advance_width, _lsb = hmtx[glyph_name]
        if glyph.numberOfContours == 0 and advance_width == 0:
            blank.append((name, cp))
    return blank


def main() -> int:
    if not REGISTRY.exists():
        sys.exit(f"{REGISTRY} not found -- run from the repository root")

    entries = ENTRY.findall(REGISTRY.read_text(encoding="utf-8"))
    if not entries:
        sys.exit(f"no glyph entries parsed out of {REGISTRY}")

    font_path = find_font()
    font = TTFont(font_path, fontNumber=0)
    cmap = font.getBestCmap()

    missing = [(name, cp) for name, cp in entries if int(cp, 16) not in cmap]
    present = [(name, cp, cmap[int(cp, 16)]) for name, cp in entries if int(cp, 16) in cmap]
    blank = find_blank(font, cmap, present)

    print(f"font:    {font_path}")
    print(f"checked: {len(entries)} codepoints")

    ok = True

    if missing:
        ok = False
        print(f"missing: {len(missing)}")
        for name, cp in missing:
            print(f"  {name:<12} U+{cp.upper()}")
        print("\nGive each of these an explicit fallback in shared/icons.lua.")
    else:
        print("missing: 0")

    if blank:
        ok = False
        print(f"blank:   {len(blank)}")
        for name, cp in blank:
            print(f"  {name:<12} U+{cp.upper()}")
        print("\nThese resolve in the cmap but the font has no outlines for them --")
        print("give each an explicit fallback in shared/icons.lua.")
    else:
        print("blank:   0")

    print(f"\n{len(present) - len(blank)} renderable, {len(blank)} blank")

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
