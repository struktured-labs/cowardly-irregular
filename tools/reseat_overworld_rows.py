#!/usr/bin/env python3
"""Re-seat an overworld walk sheet's four rows onto the 32px grid the game cuts it at.

Found 2026-10-12: 69 of 214 overworld sheets (villagers and world costumes) hold four whole rows of
figures at an UNEVEN pitch (typically 34/30/30/30 instead of 32/32/32/32). The game cuts every sheet at
y = 32, 64, 96, so a villager walking left, right or up was drawn as the previous row's feet floating
over a figure with its own feet cut off.

This moves each row's figures, untouched, to the bottom of their own 32px cell. A row taller than 32px
is squashed vertically to fit (nearest neighbour, the same call fix_overworld_row_bleed.py makes). It
REFUSES a sheet it cannot read as four comparable rows: those have three or two rows of figures, or
were mangled earlier, and need a re-roll, not a shuffle. T1 sheets only: artist sheets are never touched.

AFTER --apply, re-run tools/fix_head_lock.py on the moved sheets: the head lock was laid at the old cell
positions, so test_overworld_head_lock_regression reds until it is laid again.

Usage:
    python3 tools/reseat_overworld_rows.py --audit            # every manifest + world sheet
    python3 tools/reseat_overworld_rows.py --apply            # fix what can be fixed
    python3 tools/reseat_overworld_rows.py --selftest
"""
import argparse
import glob
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CELL = 32
ROWS = 4
# A stray body of at least this many pixels on a cell's top or bottom edge is another row's figure.
MIN_PIECE = 10
# Bands this short are specks (a halo, a spark), not a row of figures.
MIN_BAND = 6
# Four rows of figures are comparable in height; a band under this share of the tallest is not a row.
MIN_BAND_SHARE = 0.7
ALPHA = 128


def _components(mask: np.ndarray):
    """8-connected labels of a small boolean mask, as (labels, count). Plain flood fill: no scipy on the gate box."""
    lab = np.zeros(mask.shape, dtype=np.int32)
    n = 0
    h, w = mask.shape
    for sy in range(h):
        for sx in range(w):
            if not mask[sy, sx] or lab[sy, sx]:
                continue
            n += 1
            lab[sy, sx] = n
            stack = [(sy, sx)]
            while stack:
                y, x = stack.pop()
                for ny in range(max(0, y - 1), min(h, y + 2)):
                    for nx in range(max(0, x - 1), min(w, x + 2)):
                        if mask[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = n
                            stack.append((ny, nx))
    return lab, n


def cut_cells(alpha: np.ndarray) -> list:
    """(row, col) of every cell holding a detached piece of another row's figure on its top or bottom edge."""
    out = []
    for r in range(alpha.shape[0] // CELL):
        for c in range(alpha.shape[1] // CELL):
            cell = alpha[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL]
            lab, n = _components(cell)
            if n < 2:
                continue
            sizes = np.bincount(lab.ravel(), minlength=n + 1)
            sizes[0] = 0
            main = int(sizes.argmax())
            for k in range(1, n + 1):
                if k != main and sizes[k] >= MIN_PIECE and ((lab[0] == k).any() or (lab[-1] == k).any()):
                    out.append((r, c))
                    break
    return out


def row_bands(alpha: np.ndarray):
    """The four [y0, y1) bands holding the rows of figures, or a string saying why there are not four."""
    occ = alpha.sum(axis=1)
    bands = []
    y = 0
    while y < len(occ):
        if occ[y]:
            start = y
            while y < len(occ) and occ[y]:
                y += 1
            bands.append((start, y))
        else:
            y += 1
    if any(b[1] - b[0] < MIN_BAND for b in bands):
        return "a band under %dpx tall (a detached speck between rows)" % MIN_BAND
    # Two rows that touch read as one tall band: split it at its emptiest line near the middle.
    split = []
    for y0, y1 in bands:
        h = y1 - y0
        if len(bands) < ROWS and 1.6 * CELL <= h <= 2.4 * CELL:
            lo, hi = y0 + h // 3, y1 - h // 3
            mid = lo + int(np.argmin(occ[lo:hi]))
            split += [(y0, mid), (mid, y1)]
        else:
            split.append((y0, y1))
    if len(split) != ROWS:
        return "%d rows of figures, not %d" % (len(split), ROWS)
    heights = [b[1] - b[0] for b in split]
    if min(heights) < MIN_BAND_SHARE * max(heights):
        return "rows of unequal height %s" % heights
    return split


def reseat(img: Image.Image):
    """(new image, note) with each row at the bottom of its cell, or (None, why not)."""
    if img.size != (CELL * ROWS, CELL * ROWS):
        return None, "size %s is not a 4x4 grid of %dpx cells" % (img.size, CELL)
    alpha = np.asarray(img)[..., 3] >= ALPHA
    bands = row_bands(alpha)
    if isinstance(bands, str):
        return None, bands
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    notes = []
    for r, (y0, y1) in enumerate(bands):
        band = img.crop((0, y0, img.width, y1))
        if y1 - y0 > CELL:
            band = band.resize((img.width, CELL), Image.NEAREST)
            notes.append("row %d squashed %d->%d" % (r, y1 - y0, CELL))
        out.paste(band, (0, (r + 1) * CELL - band.height))
    left = cut_cells(np.asarray(out)[..., 3] >= ALPHA)
    if left:
        return None, "still cut after re-seating (cells %s): the columns are off too" % left[:4]
    return out, "; ".join(notes) or "moved, no pixel changed"


def sheets() -> dict:
    """path -> (label, tier) for every 32px overworld sheet the game can load."""
    manifest = json.load(open(ROOT / "data" / "sprite_manifest.json"))
    out = {}
    for section in ("overworld_npc_sheets", "overworld_player_sheets", "overworld_monster_sheets"):
        for key, entry in manifest.get(section, {}).items():
            if (entry.get("frame_width", CELL), entry.get("frame_height", CELL)) == (CELL, CELL):
                out[entry["path"].replace("res://", "")] = ("%s %s" % (section, key), entry.get("tier", ""))
    # World costumes sit beside a job's sheet and share its T1 provenance.
    for path in sorted(glob.glob(str(ROOT / "assets/sprites/jobs/*/overworld_*.png"))):
        rel = os.path.relpath(path, ROOT)
        out.setdefault(rel, ("world " + rel.split("/")[3] + "/" + os.path.basename(rel), "T1"))
    return out


def selftest() -> int:
    def sheet(tops, height=28):
        img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        for r, top in enumerate(tops):
            for c in range(4):
                for y in range(top, top + height):
                    for x in range(c * 32 + 10, c * 32 + 22):
                        img.putpixel((x, y), (40 + r * 50, 90, 200, 255))
        return img

    def alpha(img):
        return np.asarray(img)[..., 3] >= ALPHA

    good = sheet([4, 36, 68, 100])
    assert cut_cells(alpha(good)) == [], "a sheet on the grid has no cut cell"
    uneven = sheet([2, 38, 70, 100], height=28)
    uneven_rows = sheet([0, 36, 67, 99], height=29)
    for name, bad in (("uneven", uneven), ("uneven_rows", uneven_rows)):
        assert cut_cells(alpha(bad)), "%s: rows off the grid are seen as cut" % name
        fixed, note = reseat(bad)
        assert fixed is not None, "%s: four whole rows are re-seated (%s)" % (name, note)
        assert cut_cells(alpha(fixed)) == [], "%s: nothing is cut afterwards" % name
        assert int(alpha(fixed).sum()) == int(alpha(bad).sum()), "%s: a move keeps every pixel" % name
        for r in range(4):
            assert alpha(fixed)[(r + 1) * 32 - 1].any(), "%s: row %d stands on its cell's floor" % (name, r)
    three, why = reseat(sheet([4, 46, 88], height=38))
    assert three is None and "3 rows" in why, "three rows of figures are refused, not shuffled (%s)" % why
    wrong, why = reseat(Image.new("RGBA", (192, 192)))
    assert wrong is None and "size" in why, "another cell size is refused (%s)" % why
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
    fixed, refused, clean = [], [], 0
    for rel, (label, tier) in sorted(sheets().items()):
        path = ROOT / rel
        if not path.exists():
            continue
        img = Image.open(path).convert("RGBA")
        if img.size[0] % CELL or img.size[1] % CELL:
            continue
        if not cut_cells(np.asarray(img)[..., 3] >= ALPHA):
            clean += 1
            continue
        if tier != "T1":
            refused.append((label, "tier %s: artist art is not re-seated" % tier))
            continue
        out, note = reseat(img)
        if out is None:
            refused.append((label, note))
            continue
        fixed.append((label, note))
        if args.apply:
            out.save(path)
    for label, note in fixed:
        print("%s %s: %s" % ("FIXED" if args.apply else "CAN FIX", label, note))
    for label, note in refused:
        print("REFUSED %s: %s" % (label, note))
    print("%d clean, %d %s, %d refused" % (clean, len(fixed), "fixed" if args.apply else "fixable", len(refused)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
