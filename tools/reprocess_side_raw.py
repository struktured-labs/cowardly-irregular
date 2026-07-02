#!/usr/bin/env python3
"""Reprocess a saved side-walk raw (no API call) through the fix pipeline.

Used when the generation was good but post-processing failed — e.g. the
transparent-corner chromakey bug that ate the noble's black hair.

Usage:
    uv run python tools/reprocess_side_raw.py noble
    uv run python tools/reprocess_side_raw.py noble --no-hsv
"""
import argparse
import sys
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT))
from tools import gen_overworld_gpt_image as ow
from tools.fix_overworld_side_rows import (
    GAME_REPO, OUT_TMP, slice_side_frames, paste_rows, hsv_match_side_rows,
)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("jobs", nargs="+")
    ap.add_argument("--no-hsv", action="store_true")
    args = ap.parse_args()

    for job in args.jobs:
        raw_path = OUT_TMP / f"{job}_side_raw.png"
        if not raw_path.exists():
            print(f"  SKIP {job}: no saved raw at {raw_path}")
            continue
        dest_root = ow.ENTITY_SOURCES[job].get("dest_root", ow.DEFAULT_DEST_ROOT)
        sheet_path = GAME_REPO / "assets" / "sprites" / dest_root / job / "overworld.png"
        backup = sheet_path.with_name("overworld.pre_side_fix.png")
        # Rebuild from the pristine backup so a prior bad paste doesn't stack
        base = Image.open(backup if backup.exists() else sheet_path).convert("RGBA")

        raw = Image.open(raw_path).convert("RGBA")
        raw = ow._strip_white_bg(raw)
        frames = slice_side_frames(raw, target=32)
        frames = ow.head_lock_row(frames, head_frac=0.65)
        fixed = paste_rows(base, frames)
        if not args.no_hsv:
            fixed = hsv_match_side_rows(fixed)
        fixed.save(sheet_path)
        print(f"  reprocessed {job} → {sheet_path.relative_to(GAME_REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
