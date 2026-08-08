#!/usr/bin/env python3
"""Key the opaque background off the world-dressed dialogue portraits.

The batch came back with 41 of 70 carrying an opaque backdrop while 13 of the 14 painted
base portraits are transparent. Two flavours, and the shared cleanup missed BOTH:

    regen_archetype_portraits.transparent_bg keys only r,g,b >= 240
      cream  rgb(235,231,228)  ->  BELOW the threshold, survives
      black  rgb(0,0,0)        ->  never in scope at all

A bust with a rectangle behind it composites wrong on the dialogue box, so this is a
render defect, not a cosmetic one — and it is invisible to every guard I have: the file
loads, imports, resolves and is the right character.

Uses chromakey_dark_bg.flood_key_frame (already in the repo, written for the same
gpt-image-1 behaviour on monster sheets) rather than a second implementation. Corner-seeded
flood fill, so interior dark pixels — a black hood, the necromancer's robe — stay opaque;
only background CONNECTED to a corner is keyed.

⚠️ NEVER touches <job>.png. The painted base portraits are artist-tier and already correct;
this operates exclusively on the <job>_<world>.png files this lane generated.

  uv run --with pillow python tools/fix_portrait_bg.py --dry-run
  uv run --with pillow python tools/fix_portrait_bg.py --apply
"""
import argparse
import importlib.util
import json
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
GAME = HERE.parent
PORTRAITS = GAME / "assets" / "sprites" / "portraits"
WORLDS = ["suburban", "steampunk", "industrial", "digital", "abstract"]

spec = importlib.util.spec_from_file_location("_ck", HERE / "chromakey_dark_bg.py")
_ck = importlib.util.module_from_spec(spec)
spec.loader.exec_module(_ck)


def corner_alpha(im: Image.Image) -> int:
    w, h = im.size
    return sum(1 for q in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]
               if im.getpixel(q)[3] > 32)


def opaque_px(im: Image.Image) -> int:
    return sum(1 for a in im.split()[3].getdata() if a > 32)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--threshold", type=int, default=40)
    args = ap.parse_args()

    jobs = sorted(json.load(open(GAME / "data" / "jobs.json")).keys())
    targets = [PORTRAITS / f"{j}_{w}.png" for j in jobs for w in WORLDS]
    targets = [p for p in targets if p.exists()]

    dirty = []
    for p in targets:
        if corner_alpha(Image.open(p).convert("RGBA")):
            dirty.append(p)
    print(f"{len(dirty)} of {len(targets)} world portrait(s) have an opaque backdrop")
    if not args.apply or args.dry_run:
        for p in dirty[:8]:
            print(f"  {p.name}")
        if len(dirty) > 8:
            print(f"  ... and {len(dirty)-8} more")
        print("\n(dry run — pass --apply to write)")
        return 0

    # A flood fill that swallows the character is the failure mode worth guarding:
    # it produces a file that still loads and is silently blank.
    ate, fixed, kept = [], [], []
    for p in dirty:
        before = Image.open(p).convert("RGBA")
        n0 = opaque_px(before)
        after = _ck.flood_key_frame(before.copy(), threshold=args.threshold)
        n1 = opaque_px(after)
        if n1 < n0 * 0.35:
            ate.append(f"{p.name} ({n0}->{n1} px, {100*n1//max(n0,1)}%)")
            continue
        if corner_alpha(after):
            kept.append(p.name)
        after.save(p)
        fixed.append(p.name)

    print(f"keyed {len(fixed)}/{len(dirty)}")
    if ate:
        print(f"⛔ REFUSED — fill would have eaten the subject: {ate}", file=sys.stderr)
    if kept:
        print(f"⚠️ STILL opaque at a corner after keying (gradient backdrop?): {kept}",
              file=sys.stderr)
    return 1 if ate else 0


if __name__ == "__main__":
    sys.exit(main())
