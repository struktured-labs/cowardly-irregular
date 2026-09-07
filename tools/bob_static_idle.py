#!/usr/bin/env python3
"""Give idle frame 1 a 1-pixel vertical shift so it differs from frame 0.

Item 29's 4-pose × 2-duplicate strategy produces pixel-identical idle
frames 0 and 1 by construction. test_monster_sprite_integrity's
test_idle_frames_differ flags them as static dupes.

Fix: shift frame 1's pixels down by 1 (breathing bob). Empty top row
gets filled with transparent — sub-pixel offset per silhouette edge
gives ~40-50 different sampled pixels, easily clearing the >3
threshold.

Reads sprite_manifest.json to find the idle frame slot(s) per monster,
so the shift stays inside frame 1 and doesn't spill into attack.

Usage:
    uv run python tools/bob_static_idle.py                    # all T2 monsters
    uv run python tools/bob_static_idle.py giant_bat cave_rat # just some
    uv run python tools/bob_static_idle.py --tier T2 --dry-run
"""
import argparse
import json
import os
import sys
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
MANIFEST = GAME_REPO / "data/sprite_manifest.json"


def frames_identical(img: Image.Image, frame_w: int, f0: int, f1: int) -> bool:
    H = img.size[1]
    a = img.crop((f0 * frame_w, 0, (f0 + 1) * frame_w, H))
    b = img.crop((f1 * frame_w, 0, (f1 + 1) * frame_w, H))
    return a.tobytes() == b.tobytes()


def bob_frame_1(sheet_path: Path, frame_w: int, idle_start: int,
                idle_end: int, shift_y: int = 1,
                only_if_identical: bool = False) -> str:
    """Shift the pixels in idle frame 1 down by shift_y.

    Returns "bobbed", "skip-single-frame", "skip-out-of-bounds", or
    "skip-already-differs" (latter only in only_if_identical mode —
    guards artist sheets with real animation and already-bobbed sheets
    from a second shift)."""
    if idle_end <= idle_start:
        return "skip-single-frame"
    img = Image.open(sheet_path).convert("RGBA")
    W, H = img.size
    f1 = idle_start + 1
    x0 = f1 * frame_w
    if x0 + frame_w > W:
        return "skip-out-of-bounds"
    if only_if_identical and not frames_identical(img, frame_w, idle_start, f1):
        return "skip-already-differs"
    frame = img.crop((x0, 0, x0 + frame_w, H))
    # Create shifted version — new frame with pixels moved down by shift_y
    shifted = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    shifted.paste(frame, (0, shift_y), frame)
    img.paste(shifted, (x0, 0))
    img.save(sheet_path)
    return "bobbed"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("monsters", nargs="*", help="monster ids; default = all T2")
    parser.add_argument("--tier", default="T2", help="tier filter when no ids given")
    parser.add_argument("--shift", type=int, default=1)
    parser.add_argument("--only-if-identical", action="store_true",
                        help="skip sheets whose idle frames already differ "
                             "(protects artist sheets + already-bobbed sheets)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    mss = manifest.get("monster_sheets", {})

    if args.monsters:
        targets = args.monsters
    else:
        targets = [mid for mid, meta in mss.items()
                   if meta.get("tier") == args.tier]

    if not targets:
        print("No monsters to process")
        return 1

    n_ok = n_skip = 0
    for mid in targets:
        entry = mss.get(mid)
        if not entry:
            print(f"  SKIP {mid}: not in manifest")
            n_skip += 1
            continue
        idle = entry.get("animations", {}).get("idle", {})
        idle_start = int(idle.get("start", 0))
        idle_end = int(idle.get("end", idle_start))
        if idle_end <= idle_start:
            print(f"  SKIP {mid}: single-frame idle ({idle_start}-{idle_end})")
            n_skip += 1
            continue
        sheet_path = GAME_REPO / entry["path"].replace("res://", "")
        if not sheet_path.exists():
            print(f"  SKIP {mid}: missing file {sheet_path}")
            n_skip += 1
            continue
        frame_w = int(entry.get("frame_width", 256))
        if args.dry_run:
            img = Image.open(sheet_path).convert("RGBA")
            identical = frames_identical(img, frame_w, idle_start, idle_start + 1)
            print(f"  WOULD {'BOB' if identical or not args.only_if_identical else 'SKIP (differs)'} "
                  f"{mid}: idle {idle_start}-{idle_end}, frame_w={frame_w}")
        else:
            result = bob_frame_1(sheet_path, frame_w, idle_start, idle_end,
                                 args.shift,
                                 only_if_identical=args.only_if_identical)
            print(f"  {result.upper()} {mid}")
        n_ok += 1

    print(f"\n{'Would process' if args.dry_run else 'Processed'}: "
          f"{n_ok}, skipped {n_skip}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
