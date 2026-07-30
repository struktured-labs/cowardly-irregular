#!/usr/bin/env python3
"""Head-lock repair: pin the upper body across a row's walk frames.

struktured 2026-07-28: "no proc gen stuff please at all" + "make sure
cowir-sprites has metrics to know if his sprites are broken" — ruled as
no broken sprites ship.

test_overworld_head_lock_regression requires the upper 65% of a chibi
(head + neck + torso + arms) to be pixel-identical across frames 1/2/3 of
each row; only the legs may cycle. That is the SNES convention and it is
what stops a walk cycle reading as garble.

Seven sheets fail once the ratchet's window is anchored correctly (see
sprites-headlock-anchor-BLOCKED): the old anchor took the FIRST OPAQUE ROW
in the cell, which on a bleeding sheet is the previous row's overflowed
feet — identical across frames, so it always passed. Fixing the anchor
exposed real head drift underneath.

Repair: copy frame 0's head band into frames 1..3 of the same row,
preserving each frame's own legs. Deterministic, no generation, no API.
Frame 0 is the reference by convention (it is the rest pose).

Usage:
    uv run python tools/fix_head_lock.py --check
    uv run python tools/fix_head_lock.py npcs/monk jobs/mage --apply
"""
import argparse
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME = Path("/home/struktured/projects/cowardly-irregular-artist-ship")
SPRITES = GAME / "assets" / "sprites"
BACKUP = PROJECT / "tmp" / "pre_head_lock_backups"

CELL = 32
COLS = 4
ROWS = 4
LOCK_FRAC = 0.65


def row_sprite_top(arr: np.ndarray, row: int) -> int:
    """First opaque row of THIS row's own sprite — largest contiguous band.

    Mirrors the corrected ratchet anchor. Using first-opaque here would
    reintroduce the very bug the anchor fix removed: on a bleeding sheet
    the band above belongs to the previous row.
    """
    top, bot = row * CELL, (row + 1) * CELL
    rows_any = (arr[top:bot] > 8).any(axis=1)
    best_start, best_len, cur = -1, 0, -1
    for i, on in enumerate(list(rows_any) + [False]):
        if on and cur < 0:
            cur = i
        elif not on and cur >= 0:
            if i - cur > best_len:
                best_len, best_start = i - cur, cur
            cur = -1
    return top + best_start if best_start >= 0 else -1


def repair(path: Path, apply: bool) -> list[str]:
    img = Image.open(path).convert("RGBA")
    arr = np.array(img)
    alpha = arr[:, :, 3]
    notes = []
    for row in range(ROWS):
        y0 = row_sprite_top(alpha, row)
        if y0 < 0:
            continue
        y1 = min(y0 + int(CELL * LOCK_FRAC), (row + 1) * CELL)
        ref = arr[y0:y1, 0:CELL].copy()          # frame 0's head band
        for col in range(1, COLS):
            x0 = col * CELL
            band = arr[y0:y1, x0:x0 + CELL]
            # A UNIFORM vertical shift is a deliberate walk bob, not garble —
            # the ratchet models it the same way (_head_pixels_match_shifted).
            # Copying frame 0 verbatim would pass the test by DELETING the
            # animation, so find the bob first and re-lay the head AT that
            # offset: garble goes, rhythm stays.
            best_dy, best_diff = 0, None
            for dy in (0, 1, -1, 2, -2):
                src = np.roll(ref, dy, axis=0)
                if dy > 0:
                    src[:dy] = band[:dy]
                elif dy < 0:
                    src[dy:] = band[dy:]
                d = int((band != src).any(axis=2).sum())
                if best_diff is None or d < best_diff:
                    best_dy, best_diff = dy, d
            if best_diff:
                notes.append(f"row{row} frame{col}: {best_diff}px drift "
                             f"(bob dy={best_dy:+d})")
                if apply:
                    src = np.roll(ref, best_dy, axis=0)
                    if best_dy > 0:
                        src[:best_dy] = band[:best_dy]
                    elif best_dy < 0:
                        src[best_dy:] = band[best_dy:]
                    arr[y0:y1, x0:x0 + CELL] = src
    if apply and notes:
        BACKUP.mkdir(parents=True, exist_ok=True)
        bak = BACKUP / f"{path.parent.name}_{path.name}.bak"
        if not bak.exists():
            shutil.copy2(path, bak)
        Image.fromarray(arr).save(path)
    return notes


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("targets", nargs="*",
                    help="paths relative to assets/sprites, e.g. npcs/monk")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    paths = ([SPRITES / t / "overworld.png" for t in args.targets]
             if args.targets else sorted(SPRITES.glob("*/*/overworld.png")))

    total = 0
    for p in paths:
        if not p.exists():
            print(f"  MISSING {p}")
            continue
        notes = repair(p, args.apply and not args.check)
        if notes:
            total += 1
            print(f"\n{p.relative_to(SPRITES)}")
            for n in notes[:6]:
                print(f"  {n}")
            if len(notes) > 6:
                print(f"  … +{len(notes)-6} more")
    print(f"\n{total} sheet(s) with head drift"
          + ("" if args.apply and not args.check else "  (dry run)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
