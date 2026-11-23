#!/usr/bin/env python3
"""The Cave Rat King's crown as a prop: a very small crown that drops, rolls and comes to rest (T1, hand-placed pixels).

struktured's easter egg (cowir-main 24215/24233): beat the Rat King before ever talking to Elder Theron and the party
arrives while he rehearses his briefing; the crown lands on the Harmony Fountain's rim. Story 24234: it is the SAME
crown the defeat scene names ("the tiny crown rolls off and spins to a stop"), so it SPINS down and stops upright.
(The first sheet rested it on its side; composited on the scene's backdrop that read as a small flag, not a crown.)

No image model: every pixel is placed below. The golds and the jewel red are MEASURED from frame 0 of
assets/sprites/monsters/cave_rat_king.png (the most common opaque gold / red pixels there), so it reads as his.

4 frames of 16x16, a horizontal strip (the prop_art convention: `frames`, `fps`):
  0 falling, upright   1 landed, spinning, edge-on   2 coming round   3 at rest, upright (hold this one)

Usage:
    uv run --with pillow python tools/gen_tiny_crown.py            # writes the PNG
    uv run --with pillow python tools/gen_tiny_crown.py --check    # exit 1 if the PNG on disk differs
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/sprites/props/common/tiny_crown.png"
CELL = 16
PAL = {
    ".": (0, 0, 0, 0),
    "o": (74, 40, 18, 255),      # outline: a dark brown, not black, so it sits on stone
    "s": (187, 117, 71, 255),    # shadow gold   (rat king sheet: 187,117,71)
    "Y": (234, 167, 44, 255),    # body gold     (234,167,44, his commonest gold)
    "L": (246, 225, 51, 255),    # light gold    (246,225,51)
    "h": (254, 240, 80, 255),    # highlight     (254,240,80)
    "R": (204, 44, 44, 255),     # jewel
}
# Upright, 11x6 before its outline: three points with a bead each, a jewelled band, a shadowed base.
UPRIGHT = [
    "h....h....h",
    "L....L....L",
    "LY..YLY..YY",
    "LYYYYYYYYYs",
    "YRYYYRYYYRs",
    "sssssssssss",
]
# The same crown part-way round a spin about its upright axis: narrower, the jewels moved round the band.
EDGE_ON = [
    "h.h.h",
    "L.L.L",
    "LYLYY",
    "LYYYs",
    "YYRYs",
    "sssss",
]
THREE_QUARTER = [
    "h..h..h",
    "L..L..L",
    "LY.L.YY",
    "LYYYYYs",
    "YYRYYRs",
    "sssssss",
]


def outlined(rows: list[str]) -> list[str]:
    h, w = len(rows), len(rows[0])
    g = [["."] * (w + 2)] + [["."] + list(r) + ["."] for r in rows] + [["."] * (w + 2)]
    out = [row[:] for row in g]
    for y in range(h + 2):
        for x in range(w + 2):
            if g[y][x] != ".":
                continue
            for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h + 2 and 0 <= xx < w + 2 and g[yy][xx] != ".":
                    out[y][x] = "o"
                    break
    return ["".join(r) for r in out]


def stamp(strip: Image.Image, frame: int, rows: list[str], left: int, bottom: int) -> None:
    """Place a shape in its cell with its lowest row on `bottom` (the ground line is y=14, one clear row under it)."""
    top = bottom - len(rows) + 1
    assert top >= 0 and left >= 0 and left + len(rows[0]) <= CELL and bottom < CELL, (frame, left, top)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                strip.putpixel((frame * CELL + left + x, top + y), PAL[ch])


def build() -> Image.Image:
    strip = Image.new("RGBA", (CELL * 4, CELL), (0, 0, 0, 0))
    stamp(strip, 0, outlined(UPRIGHT), 2, 9)          # in the air: five rows above the ground line
    stamp(strip, 1, outlined(EDGE_ON), 4, 14)         # landed, spinning: seen edge-on
    stamp(strip, 2, outlined(THREE_QUARTER), 4, 14)   # coming round
    stamp(strip, 3, outlined(UPRIGHT), 2, 14)         # at rest, facing us
    return strip


def main() -> int:
    img = build()
    if "--check" in sys.argv:
        on_disk = Image.open(OUT).convert("RGBA")
        same = on_disk.size == img.size and on_disk.tobytes() == img.tobytes()
        print("tiny_crown: %s" % ("matches the generator" if same else "DIFFERS from the generator"))
        return 0 if same else 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print("wrote %s %dx%d" % (OUT.relative_to(ROOT), img.width, img.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
