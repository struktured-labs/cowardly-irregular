#!/usr/bin/env python3
"""Swap the side rows of overworld walk sheets whose walk_left row faces right.

Every overworld sheet is read as rows 0 down, 1 LEFT, 2 RIGHT, 3 up. On about 80 villager sheets the
generator drew the right-facing walk on row 1 and the left-facing one on row 2, so those villagers
walked left facing right and right facing left. Nothing measured it: the two rows are exact mirrors
of each other, so every mirror and geometry guard is satisfied either way round.

The signal is the FACE. In a side view the skin of the head sits toward the way the figure looks, so
the skin centroid of the head, taken against the figure's own centre, leans left on a left-facing row
and right on a right-facing one. A sheet is swapped only when both rows lean clearly the wrong way;
front-facing, masked or flat placeholder figures give a weak lean and are left alone. T1 sheets only,
and never a sheet whose rows are still cut in the wrong place.

Roaming monsters are judged the same way by their EYE (wolf and snake, 2026-10-12).

Usage:
    python3 tools/fix_overworld_side_facing.py --audit
    python3 tools/fix_overworld_side_facing.py --apply
    python3 tools/fix_overworld_side_facing.py --selftest
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from reseat_overworld_rows import cut_cells  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CELL = 32
ALPHA = 128
LEFT_ROW, RIGHT_ROW = 1, 2
# Both rows must lean at least this far (share of the figure's width) the wrong way before a swap.
CLEAR_LEAN = 0.10
# The head is the top share of the figure; hands below it are skin too and point nowhere useful.
HEAD_SHARE = 0.6
# Weak-lean sheets checked by eye on 2026-10-12 and found swapped.
REVIEWED_SWAPPED = (
    "fairy", "blacksmith_abstract", "old_woman_steampunk",
    # Second pass: leans of 0.08-0.10, each zoomed.
    "blacksmith", "dr_temporal", "fairy_industrial", "fisherman_industrial", "fisherman_steampunk",
    "young_man_abstract", "king_industrial", "noble_abstract", "old_man_industrial", "priestess_steampunk",
)


def _skin(cell: np.ndarray) -> np.ndarray:
    r, g, b = (cell[..., i].astype(float) / 255 for i in range(3))
    hi = np.maximum(np.maximum(r, g), b)
    lo = np.minimum(np.minimum(r, g), b)
    sat = np.where(hi > 0, (hi - lo) / np.maximum(hi, 1e-6), 0)
    return (cell[..., 3] >= ALPHA) & (r > g) & (g > b) & (hi > 0.6) & (sat > 0.15) & (sat < 0.65) & ((r - b) > 0.12)


def row_lean(rgba: np.ndarray, row: int):
    """Mean over the row's frames of (head skin centroid - figure centre) / figure width; + is facing right. None if no face."""
    leans = []
    for col in range(rgba.shape[1] // CELL):
        cell = rgba[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL]
        ys, xs = np.nonzero(cell[..., 3] >= ALPHA)
        if len(xs) < 40:
            continue
        skin = _skin(cell)
        skin[ys.min() + int((ys.max() - ys.min()) * HEAD_SHARE):] = False
        sx = np.nonzero(skin)[1]
        if len(sx) < 4:
            continue
        leans.append((sx.mean() - (xs.min() + xs.max()) / 2) / max(1, xs.max() - xs.min()))
    return float(np.mean(leans)) if leans else None


# A roaming monster has no skin to find a face by: its bright yellow or orange EYE says which way it looks.
CLEAR_EYE_LEAN = 0.15


def eye_lean(rgba: np.ndarray, row: int):
    """Mean over the row's frames of (eye centroid - figure centre) / figure width; + looks right. None if no eye."""
    leans = []
    for col in range(rgba.shape[1] // CELL):
        cell = rgba[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL]
        opaque = cell[..., 3] >= ALPHA
        xs = np.nonzero(opaque)[1]
        r, g, b = (cell[..., i].astype(int) for i in range(3))
        ex = np.nonzero(opaque & (r >= 180) & (g >= 120) & (b <= 90) & (r - b >= 120))[1]
        if len(xs) < 20 or len(ex) == 0:
            continue
        leans.append((ex.mean() - (xs.min() + xs.max()) / 2) / max(1, xs.max() - xs.min()))
    return float(np.mean(leans)) if leans else None


def monster_is_swapped(rgba: np.ndarray) -> bool:
    left, right = eye_lean(rgba, LEFT_ROW), eye_lean(rgba, RIGHT_ROW)
    return left is not None and right is not None and left >= CLEAR_EYE_LEAN and right <= -CLEAR_EYE_LEAN


def is_swapped(rgba: np.ndarray, floor: float = CLEAR_LEAN) -> bool:
    left, right = row_lean(rgba, LEFT_ROW), row_lean(rgba, RIGHT_ROW)
    return left is not None and right is not None and left >= floor and right <= -floor


def swap_side_rows(img: Image.Image) -> Image.Image:
    out = img.copy()
    out.paste(img.crop((0, RIGHT_ROW * CELL, img.width, (RIGHT_ROW + 1) * CELL)), (0, LEFT_ROW * CELL))
    out.paste(img.crop((0, LEFT_ROW * CELL, img.width, (LEFT_ROW + 1) * CELL)), (0, RIGHT_ROW * CELL))
    return out


def sheets() -> dict:
    """path -> (id, tier) for every 32px villager sheet. Player and world-costume sheets are judged by the guard, not swapped here."""
    manifest = json.load(open(ROOT / "data" / "sprite_manifest.json"))
    out = {}
    for key, entry in manifest.get("overworld_npc_sheets", {}).items():
        if (entry.get("frame_width", CELL), entry.get("frame_height", CELL)) == (CELL, CELL):
            out[entry["path"].replace("res://", "")] = (key, entry.get("tier", ""))
    return out


def selftest() -> int:
    def sheet(face_dx_left_row: int):
        img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        for row, dx in ((LEFT_ROW, face_dx_left_row), (RIGHT_ROW, -face_dx_left_row)):
            for col in range(4):
                x0, y0 = col * 32 + 8, row * 32 + 4
                for y in range(y0, y0 + 26):
                    for x in range(x0, x0 + 16):
                        img.putpixel((x, y), (60, 50, 90, 255))
                fx = x0 + 6 + dx
                for y in range(y0 + 4, y0 + 10):
                    for x in range(fx, fx + 5):
                        img.putpixel((x, y), (236, 190, 150, 255))
        return img

    good = np.asarray(sheet(-5))
    bad_img = sheet(5)
    bad = np.asarray(bad_img)
    assert row_lean(good, LEFT_ROW) < -CLEAR_LEAN and row_lean(good, RIGHT_ROW) > CLEAR_LEAN, "a face on the left faces left"
    assert not is_swapped(good), "a sheet whose left row faces left is not swapped"
    assert is_swapped(bad), "a sheet whose left row faces right is seen"
    fixed = np.asarray(swap_side_rows(bad_img))
    assert not is_swapped(fixed) and row_lean(fixed, LEFT_ROW) < -CLEAR_LEAN, "swapping the rows turns it round"
    assert (fixed[0:32] == bad[0:32]).all() and (fixed[96:128] == bad[96:128]).all(), "down and up rows are untouched"
    front = np.asarray(sheet(0))
    assert not is_swapped(front), "a front-facing figure gives no lean and is left alone"
    beast = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    for row, ex in ((LEFT_ROW, 24), (RIGHT_ROW, 6)):
        for col in range(4):
            for y in range(row * 32 + 10, row * 32 + 24):
                for x in range(col * 32 + 4, col * 32 + 28):
                    beast.putpixel((x, y), (90, 90, 90, 255))
            beast.putpixel((col * 32 + ex, row * 32 + 12), (240, 200, 20, 255))
    assert monster_is_swapped(np.asarray(beast)), "a beast whose left row looks right is seen by its eye"
    assert not monster_is_swapped(np.asarray(swap_side_rows(beast))), "swapping its rows turns it round"
    assert eye_lean(np.asarray(sheet(5)), LEFT_ROW) is None, "no eye, no verdict"
    masked = np.asarray(Image.new("RGBA", (128, 128), (60, 50, 90, 255)))
    assert row_lean(masked, LEFT_ROW) is None and not is_swapped(masked), "no face, no verdict"
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
    n = 0
    for rel, (key, tier) in sorted(sheets().items()):
        path = ROOT / rel
        if not path.exists():
            continue
        img = Image.open(path).convert("RGBA")
        if img.size != (CELL * 4, CELL * 4):
            continue
        rgba = np.asarray(img)
        reviewed = key in REVIEWED_SWAPPED and is_swapped(rgba, 0.0)
        if not (is_swapped(rgba) or reviewed):
            continue
        if cut_cells(rgba[..., 3] >= ALPHA):
            print("LEFT %s: its rows are cut in the wrong place (reseat_overworld_rows.py); swapping cells would shuffle halves" % key)
            continue
        if tier != "T1":
            print("REFUSED %s: tier %s, artist art is not rearranged" % (key, tier))
            continue
        n += 1
        print("%s %s: left row leans %+.2f, right row %+.2f%s" % ("SWAPPED" if args.apply else "CAN SWAP", key,
            row_lean(rgba, LEFT_ROW), row_lean(rgba, RIGHT_ROW), " (reviewed by eye)" if reviewed else ""))
        if args.apply:
            swap_side_rows(img).save(path)
    manifest = json.load(open(ROOT / "data" / "sprite_manifest.json"))
    for key, entry in sorted(manifest.get("overworld_monster_sheets", {}).items()):
        path = ROOT / entry["path"].replace("res://", "")
        rows = {name: anim.get("row") for name, anim in entry.get("animations", {}).items()}
        if not path.exists() or (rows.get("walk_left"), rows.get("walk_right")) != (LEFT_ROW, RIGHT_ROW):
            continue
        img = Image.open(path).convert("RGBA")
        rgba = np.asarray(img)
        if img.size != (CELL * 4, CELL * 4) or not monster_is_swapped(rgba):
            continue
        if entry.get("tier", "") != "T1":
            print("REFUSED monster %s: tier %s, artist art is not rearranged" % (key, entry.get("tier")))
            continue
        n += 1
        print("%s monster %s: eye leans %+.2f on its left row" % ("SWAPPED" if args.apply else "CAN SWAP", key, eye_lean(rgba, LEFT_ROW)))
        if args.apply:
            swap_side_rows(img).save(path)
    print("%d sheet(s) %s" % (n, "swapped" if args.apply else "to swap"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
