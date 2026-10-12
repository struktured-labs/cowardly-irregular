#!/usr/bin/env python3
"""Give dialogue portraits back the whites of their eyes.

The AI portraits were generated on a white backdrop and keyed on near-white (R,G,B >= 240). The key
took the backdrop and, with it, everything else that white: the whites of the eyes, teeth, the glint
on a lens. 102 of 165 portraits have see-through holes inside the figure, so in a conversation the
speaker's eyes show the dialogue panel through them.

A hole here is a clear region the figure fully encloses. What the key removed was near-white, so:
- a hole of 5..MAX_HOLE px (an eye white, a row of teeth) is filled near-white;
- a speck of up to 4 px takes the commonest colour on its own rim (a white dot in dark hair would
  be a new defect, and a speck that small is a lost highlight of its surroundings);
- a hole larger than MAX_HOLE is LEFT and reported: a whole keyed face or veil needs an eye on it,
  and a real opening (staff to body) must not be painted shut.
Portraits cut from the artist's own sheets are never touched (ARTIST_DERIVED): a hole in those is his.

Usage:
    python3 tools/fill_portrait_key_holes.py --audit
    python3 tools/fill_portrait_key_holes.py --apply
    python3 tools/fill_portrait_key_holes.py --selftest
"""
import argparse
import glob
import os
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PORTRAITS = "assets/sprites/portraits"
ALPHA = 128
MAX_HOLE = 160
SPECK = 4
KEYED_WHITE = (246, 246, 246)
NEIGHBOURS = ((-1, 0), (1, 0), (0, -1), (0, 1))
# Busts cut from the artist's battle sheets (the five starters, Mordaine and her other face): never filled.
ARTIST_DERIVED = ("fighter.png", "cleric.png", "mage.png", "rogue.png", "bard.png", "mordaine.png",
                  "chancellor_mordaine.png", "calibrant.png")


def holes(rgba: np.ndarray) -> list:
    """[(pixels, rim pixels)] for every clear region the figure fully encloses (4-connected)."""
    opaque = rgba[..., 3] >= ALPHA
    h, w = opaque.shape
    seen = np.zeros((h, w), dtype=bool)
    out = []
    for sy in range(h):
        for sx in range(w):
            if opaque[sy, sx] or seen[sy, sx]:
                continue
            seen[sy, sx] = True
            stack, region, rim, enclosed = [(sy, sx)], [], set(), True
            while stack:
                y, x = stack.pop()
                region.append((y, x))
                for dy, dx in NEIGHBOURS:
                    ny, nx = y + dy, x + dx
                    if ny < 0 or nx < 0 or ny >= h or nx >= w:
                        enclosed = False
                    elif opaque[ny, nx]:
                        rim.add((ny, nx))
                    elif not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if enclosed and rim:
                out.append((region, rim))
    return out


def fill(img: Image.Image):
    """(new image, pixels filled, [sizes of holes left as too large])."""
    rgba = np.asarray(img.convert("RGBA")).copy()
    filled, left = 0, []
    for region, rim in holes(rgba):
        if len(region) > MAX_HOLE:
            left.append(len(region))
            continue
        if len(region) <= SPECK:
            colour = Counter(tuple(int(v) for v in rgba[y, x, :3]) for y, x in rim).most_common(1)[0][0]
        else:
            colour = KEYED_WHITE
        for y, x in region:
            rgba[y, x] = (*colour, 255)
        filled += len(region)
    return Image.fromarray(rgba), filled, left


def portraits() -> list:
    """Every portrait a fill may touch: all of them but the artist-derived busts."""
    found = sorted(os.path.relpath(p, ROOT) for p in glob.glob(str(ROOT / PORTRAITS / "**" / "*.png"), recursive=True))
    return [p for p in found if os.path.basename(p) not in ARTIST_DERIVED]


def selftest() -> int:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    for y in range(8, 56):
        for x in range(8, 56):
            px[x, y] = (200, 150, 120, 255)
    for y in range(20, 24):
        for x in range(16, 24):
            px[x, y] = (0, 0, 0, 0)          # an eye white: 32 px
    px[40, 40] = (0, 0, 0, 0)                # a speck
    for y in range(30, 50):
        for x in range(28, 48):
            px[x, y] = (0, 0, 0, 0) if (x, y) != (40, 40) and x >= 30 else px[x, y]   # a 360 px opening
    out, n, left = fill(img)
    assert out.getpixel((18, 21)) == (*KEYED_WHITE, 255), "an eye-sized hole comes back near-white"
    assert left and left[0] > MAX_HOLE and out.getpixel((35, 45))[3] == 0, "a large opening is left and reported (%s)" % left
    edge = Image.new("RGBA", (64, 64), (200, 150, 120, 255))
    edge.putpixel((0, 30), (0, 0, 0, 0))
    assert fill(edge)[1] == 0, "a notch open to the image edge is not a hole"
    speck = Image.new("RGBA", (64, 64), (30, 20, 20, 255))
    speck.putpixel((30, 30), (0, 0, 0, 0))
    out2, n2, _ = fill(speck)
    assert n2 == 1 and out2.getpixel((30, 30)) == (30, 20, 20, 255), "a speck takes its rim's colour, not white"
    assert fill(out)[1] == 0, "a second pass fills nothing"
    print("selftest ok")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    total = files = 0
    for rel in portraits():
        img = Image.open(ROOT / rel)
        out, n, left = fill(img)
        if left:
            print("LEFT %s: %d hole(s) too large to fill blind, %s px" % (rel, len(left), sorted(left, reverse=True)[:4]))
        if not n:
            continue
        files += 1
        total += n
        print("%s %s: %d px" % ("FILLED" if args.apply else "CAN FILL", rel, n))
        if args.apply:
            out.save(ROOT / rel)
    print("%d portrait(s), %d px %s" % (files, total, "filled" if args.apply else "fillable"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
