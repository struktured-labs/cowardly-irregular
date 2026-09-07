#!/usr/bin/env python3
"""Audit and fix BACKWARDS-facing side rows in per-world overworld walk grids.

struktured, 2026-08-09: 'overworld "fighter" sprite in steampunk world walks backwards'
plus "do a backwards walk check across the board".

ROOT CAUSE. `assemble_game_grid` takes ONE side view from the generated image and mirrors it
into the opposite row, so rows 1 and 2 are always exact per-frame mirrors (verified 25/25).
Which row is correct therefore depends entirely on which way gpt-image-1 happened to draw
that single side view — a coin flip per generation. Measured: 14 of 25 came out backwards.

So this is NOT a reroll. The frames are good; only their row assignment is wrong, and
swapping rows 1 and 2 is exactly equivalent to mirroring both in place.

DETECTOR — skin-pixel centroid in the head region, relative to the body's own centre.
A side-view chibi's face sits toward the direction it faces.
  VALIDATED ON CONTROLS, 5/5: every artist sheet reads row1 negative (left), row2 positive.
  MUTANT: swapping a known-good artist sheet's rows flips the verdict to BACKWARDS, so the
  checker can fail. A checker never shown failing is not evidence.

⚠️ WEAK / NO-SKIN verdicts are NOT passes. A helmeted or hooded sprite can expose too few
skin pixels to call (fighter/digital, mage/digital), and a near-zero bias means the signal
is inside the noise (bard/industrial at 0.024). Those need eyes and are reported separately
rather than silently counted clean.

✅ IDEMPOTENT BY CONSTRUCTION, deliberately. It swaps only sheets that currently READ
backwards, so a second run finds them correct and skips. `fix_battle_sprite_facing.py`
needed a stamp file because it mirrored unconditionally — mirroring is its own inverse, and
running it twice put every sheet back to wrong while reporting success. Conditioning on a
measured verdict removes that whole failure mode instead of guarding it.

  uv run --with pillow python tools/fix_overworld_facing.py            # audit only
  uv run --with pillow python tools/fix_overworld_facing.py --apply
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
GAME = HERE.parent
JOBS_DIR = GAME / "assets" / "sprites" / "jobs"
WORLDS = ["suburban", "steampunk", "industrial", "digital", "abstract"]
FRAME = 32
WEAK = 0.04
ROW_LEFT, ROW_RIGHT = 1, 2

## READABILITY gate, and it is a SEPARATE question from direction — that separation is the
## whole point. Bias magnitude cannot do both jobs: fighter/industrial is genuinely backwards
## at 0.045, summoner is unreadable at 0.067, bard is genuinely correct at 0.075. The bounds
## CROSS, so no magnitude threshold exists. Skin-pixel count is independent of the bias sign.
##   FLOOR    above the faceless artist sheets — necromancer 0 · ninja 0 · speculator 4 ·
##            summoner 5. Hooded or masked; their facing is not determinable by eye either,
##            so a player cannot see it wrong.
##   CEILING  below the lowest artist sheet the detector reads CORRECTLY — guardian at 11.
## 5 < 8 <= 11, non-empty. Two bounds, two sources, checked for a non-empty range.
MIN_SKIN = 8


def head_skin_count(frame: Image.Image) -> int:
    px = frame.load()
    w, h = frame.size
    n = 0
    for y in range(int(h * 0.55)):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a >= 40 and r > 150 and r > g > b and (r - b) > 35 and (g - b) > 10:
                n += 1
    return n


def skin_bias(frame: Image.Image):
    px = frame.load()
    w, h = frame.size
    head_h = int(h * 0.55)
    body_x, skin_x = [], []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 40:
                continue
            body_x.append(x)
            if y < head_h and r > 150 and r > g > b and (r - b) > 35 and (g - b) > 10:
                skin_x.append(x)
    if not body_x or len(skin_x) < 4:
        return None
    return (sum(skin_x) / len(skin_x) - sum(body_x) / len(body_x)) / (w / 2.0)


def row_bias(img: Image.Image, row: int):
    vals = [skin_bias(img.crop((c * FRAME, row * FRAME, (c + 1) * FRAME, (row + 1) * FRAME)))
            for c in range(img.width // FRAME)]
    vals = [v for v in vals if v is not None]
    return sum(vals) / len(vals) if vals else None


def verdict(img: Image.Image):
    skin = sum(head_skin_count(img.crop((c * FRAME, ROW_LEFT * FRAME,
               (c + 1) * FRAME, (ROW_LEFT + 1) * FRAME)))
               for c in range(img.width // FRAME)) / float(img.width // FRAME)
    if skin < MIN_SKIN:
        # Hooded or masked: no face to read, and none for a player to read either
        return "FACELESS", None, None
    left, right = row_bias(img, ROW_LEFT), row_bias(img, ROW_RIGHT)
    if left is None or right is None:
        return "NO-SKIN", left, right
    if abs(left) < WEAK and abs(right) < WEAK:
        return "WEAK", left, right
    if left < 0 < right:
        return "ok", left, right
    if right < 0 < left:
        return "BACKWARDS", left, right
    return "ODD", left, right


def swap_side_rows(path: Path) -> None:
    img = Image.open(path).convert("RGBA")
    left = img.crop((0, ROW_LEFT * FRAME, img.width, (ROW_LEFT + 1) * FRAME))
    right = img.crop((0, ROW_RIGHT * FRAME, img.width, (ROW_RIGHT + 1) * FRAME))
    img.paste(right, (0, ROW_LEFT * FRAME))
    img.paste(left, (0, ROW_RIGHT * FRAME))
    img.save(path)


def control_passes() -> bool:
    """The audit is void unless the artist sheets read correctly AND a mutant reads wrong."""
    ok = True
    for job in sorted(p.name for p in JOBS_DIR.iterdir() if p.is_dir()):
        base = JOBS_DIR / job / "overworld.png"
        if not base.exists():
            continue
        v, _l, _r = verdict(Image.open(base).convert("RGBA"))
        if v == "FACELESS":
            continue
        if v == "BACKWARDS":
            print(f"  🔴 CONTROL FAILED: artist sheet {job} reads BACKWARDS", file=sys.stderr)
            ok = False
    src = JOBS_DIR / "cleric" / "overworld.png"
    if src.exists():
        img = Image.open(src).convert("RGBA")
        mut = img.copy()
        mut.paste(img.crop((0, 2 * FRAME, img.width, 3 * FRAME)), (0, FRAME))
        mut.paste(img.crop((0, FRAME, img.width, 2 * FRAME)), (0, 2 * FRAME))
        if verdict(mut)[0] != "BACKWARDS":
            print("  🔴 CONTROL FAILED: a deliberately swapped sheet is not detected",
                  file=sys.stderr)
            ok = False
    return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    print("controls (artist sheets read correctly; a swapped sheet reads BACKWARDS)")
    if not control_passes():
        print("⛔ controls failed — the detector is not measuring facing. Nothing written.",
              file=sys.stderr)
        return 2
    print("  ✅ controls pass\n")

    jobs = sorted(json.load(open(GAME / "data" / "jobs.json")).keys())
    backwards, review, fixed = [], [], []
    for job in jobs:
        for world in WORLDS:
            p = JOBS_DIR / job / f"overworld_{world}.png"
            if not p.exists():
                continue
            v, left, right = verdict(Image.open(p).convert("RGBA"))
            tag = f"{job}/{world}"
            if v == "BACKWARDS":
                backwards.append(tag)
                if args.apply:
                    swap_side_rows(p)
                    after = verdict(Image.open(p).convert("RGBA"))[0]
                    if after == "ok":
                        fixed.append(tag)
                    else:
                        print(f"  🔴 {tag}: still {after} after swap", file=sys.stderr)
            elif v != "ok":
                review.append(f"{tag} ({v} l={left and round(left, 3)} r={right and round(right, 3)})")

    print(f"BACKWARDS: {len(backwards)}  {backwards}")
    print(f"NEEDS EYES (not a pass): {len(review)}  {review}")
    if args.apply:
        print(f"\nswapped and re-verified: {len(fixed)}/{len(backwards)}")
        return 0 if len(fixed) == len(backwards) else 1
    print("\n(audit only — pass --apply to swap)")
    return 1 if backwards else 0


if __name__ == "__main__":
    sys.exit(main())
