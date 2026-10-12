#!/usr/bin/env python3
"""Fill the see-through slots a white key punched into pale cloth on overworld walk sheets.

The August overworld sheets were keyed on near-white (R,G,B >= 240), so the brightest highlight of a
pale robe went clear with the backdrop: the cleric walks the overworld with a slot in her hood that
shows the grass through it. A hole is that damage, and not a real gap (staff to body, between the
legs), when the pixels around it are mostly pale: it is filled with the commonest pale colour on its
own rim, so no colour is invented. T1 sheets only: artist sheets are never touched.

Usage:
    python3 tools/fill_pale_holes.py --audit
    python3 tools/fill_pale_holes.py --apply
    python3 tools/fill_pale_holes.py --selftest
"""
import argparse
import glob
import json
import os
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CELL = 32
ALPHA = 128
# A rim pixel is pale when its darkest channel is at least this; a hole is damage when this share of its rim is.
PALE_MIN = 200
PALE_SHARE = 0.6
NEIGHBOURS = ((-1, 0), (1, 0), (0, -1), (0, 1))


def pale_holes(rgba: np.ndarray) -> list:
    """[(pixels, fill colour)] for every enclosed clear region of a cell whose rim is mostly pale."""
    out = []
    opaque = rgba[..., 3] >= ALPHA
    for r in range(rgba.shape[0] // CELL):
        for c in range(rgba.shape[1] // CELL):
            y0, x0 = r * CELL, c * CELL
            cell = opaque[y0:y0 + CELL, x0:x0 + CELL]
            seen = np.zeros((CELL, CELL), dtype=bool)
            for sy in range(CELL):
                for sx in range(CELL):
                    if cell[sy, sx] or seen[sy, sx]:
                        continue
                    seen[sy, sx] = True
                    stack, region, rim, enclosed = [(sy, sx)], [], set(), True
                    while stack:
                        y, x = stack.pop()
                        region.append((y0 + y, x0 + x))
                        for dy, dx in NEIGHBOURS:
                            ny, nx = y + dy, x + dx
                            if ny < 0 or nx < 0 or ny >= CELL or nx >= CELL:
                                enclosed = False
                            elif cell[ny, nx]:
                                rim.add((y0 + ny, x0 + nx))
                            elif not seen[ny, nx]:
                                seen[ny, nx] = True
                                stack.append((ny, nx))
                    if not enclosed or not rim:
                        continue
                    colours = [tuple(int(v) for v in rgba[y, x, :3]) for y, x in rim]
                    pale = [col for col in colours if min(col) >= PALE_MIN]
                    if len(pale) >= PALE_SHARE * len(colours):
                        out.append((region, Counter(pale).most_common(1)[0][0]))
    return out


def fill(img: Image.Image):
    """(new image, pixels filled)."""
    rgba = np.asarray(img.convert("RGBA")).copy()
    filled = 0
    for region, colour in pale_holes(rgba):
        for y, x in region:
            rgba[y, x] = (*colour, 255)
            filled += 1
    return Image.fromarray(rgba), filled


def sheets() -> dict:
    """path -> (label, tier) for every 32px overworld sheet the game can load."""
    manifest = json.load(open(ROOT / "data" / "sprite_manifest.json"))
    out = {}
    for section in ("overworld_npc_sheets", "overworld_player_sheets", "overworld_monster_sheets"):
        for key, entry in manifest.get(section, {}).items():
            if (entry.get("frame_width", CELL), entry.get("frame_height", CELL)) == (CELL, CELL):
                out[entry["path"].replace("res://", "")] = ("%s %s" % (section, key), entry.get("tier", ""))
    for path in sorted(glob.glob(str(ROOT / "assets/sprites/jobs/*/overworld_*.png"))):
        rel = os.path.relpath(path, ROOT)
        out.setdefault(rel, ("world " + rel.split("/")[3] + "/" + os.path.basename(rel), "T1"))
    return out


def selftest() -> int:
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    px = img.load()
    for y in range(4, 28):
        for x in range(8, 24):
            px[x, y] = (232, 230, 224, 255)
    for x in range(12, 16):
        px[x, 8] = (0, 0, 0, 0)
    # A real gap in the next cell: a dark-rimmed opening between a staff and a body.
    for y in range(4, 28):
        for x in range(40, 56):
            px[x, y] = (70, 40, 30, 255)
    for y in range(10, 14):
        px[46, y] = (0, 0, 0, 0)
    holes = pale_holes(np.asarray(img))
    assert len(holes) == 1 and len(holes[0][0]) == 4, "the slot in pale cloth is found, the dark-rimmed gap is not (%s)" % len(holes)
    out, n = fill(img)
    assert n == 4 and out.getpixel((13, 8)) == (232, 230, 224, 255), "the slot takes its rim's own colour"
    assert out.getpixel((46, 11))[3] == 0, "a real gap stays open"
    assert pale_holes(np.asarray(out)) == [], "nothing is left to fill"
    edge = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    for y in range(0, 20):
        for x in range(8, 24):
            edge.putpixel((x, y), (240, 240, 240, 255))
    edge.putpixel((12, 0), (0, 0, 0, 0))
    assert pale_holes(np.asarray(edge)) == [], "a notch open to the cell edge is not an enclosed hole"
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
    total = 0
    for rel, (label, tier) in sorted(sheets().items()):
        path = ROOT / rel
        if not path.exists():
            continue
        img = Image.open(path)
        if img.size[0] % CELL or img.size[1] % CELL:
            continue
        out, n = fill(img)
        if not n:
            continue
        if tier != "T1":
            print("REFUSED %s: tier %s, artist art is not filled (%d px)" % (label, tier, n))
            continue
        total += 1
        print("%s %s: %d px" % ("FILLED" if args.apply else "CAN FILL", label, n))
        if args.apply:
            out.save(path)
    print("%d sheet(s) %s" % (total, "filled" if args.apply else "fillable"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
