#!/usr/bin/env python3
"""
Fix monster sprite backgrounds — make them truly transparent.

Strategy: for each 256x256 frame within the 2048x256 strip:
  1. Run rembg (U2Net-based bg removal) on the individual frame
  2. Paste back into strip at the same position

Usage:
    uv run python tools/fix_monster_bg.py
    uv run python tools/fix_monster_bg.py --monster slime   # single monster
    uv run python tools/fix_monster_bg.py --install          # copy to game repo
"""

import argparse
import shutil
import sys
from pathlib import Path

from PIL import Image
from rembg import remove, new_session

PROJECT = Path(__file__).parent.parent
SOURCE_DIR = PROJECT / "tmp" / "monster_sweep_v2"
OUTPUT_DIR = PROJECT / "tmp" / "monster_sweep_v2_transparent"
GAME_MONSTERS = Path("/home/struktured/projects/cowardly-irregular/assets/sprites/monsters")

FRAME_W = 256
FRAME_H = 256
N_FRAMES = 8


def fix_strip(src_path: Path, dest_path: Path, session) -> bool:
    """Remove background from each frame in a sprite strip."""
    try:
        strip = Image.open(src_path).convert("RGBA")
    except Exception as e:
        print(f"  ERROR opening {src_path.name}: {e}")
        return False

    # Assert strip dimensions
    if strip.size != (FRAME_W * N_FRAMES, FRAME_H):
        print(f"  WARN {src_path.name}: unexpected size {strip.size}, expected {FRAME_W*N_FRAMES}x{FRAME_H}")

    out_strip = Image.new("RGBA", strip.size, (0, 0, 0, 0))

    for i in range(N_FRAMES):
        x = i * FRAME_W
        box = (x, 0, x + FRAME_W, FRAME_H)
        frame = strip.crop(box)

        # Run bg removal on this frame
        frame_no_bg = remove(frame, session=session)

        # Paste back into strip
        out_strip.paste(frame_no_bg, (x, 0))

    out_strip.save(dest_path, "PNG")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--monster", help="Fix single monster")
    parser.add_argument("--install", action="store_true", help="Copy to game repo after")
    parser.add_argument("--source", choices=["sweep", "game"], default="sweep",
                        help="Source: 'sweep' (tmp/monster_sweep_v2) or 'game' (game repo)")
    args = parser.parse_args()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Select source directory
    if args.source == "game":
        source_dir = GAME_MONSTERS
    else:
        source_dir = SOURCE_DIR

    if not source_dir.exists():
        print(f"ERROR: source dir does not exist: {source_dir}")
        sys.exit(1)

    # Select files
    if args.monster:
        files = [source_dir / f"{args.monster}.png"]
    else:
        files = sorted(source_dir.glob("*.png"))

    # Skip non-monster files
    files = [f for f in files if f.name not in ("sweep_results.json",)]

    print(f"{'='*60}")
    print(f"  MONSTER BG REMOVAL")
    print(f"  Source: {source_dir}")
    print(f"  Output: {OUTPUT_DIR}")
    print(f"  Files: {len(files)}")
    print(f"{'='*60}")

    # Load rembg model once
    print("\nLoading rembg U2Net model...")
    session = new_session("u2net")
    print("Model loaded.\n")

    ok = 0
    fail = 0
    for i, src in enumerate(files):
        dest = OUTPUT_DIR / src.name
        print(f"  [{i+1}/{len(files)}] {src.name}...", end=" ", flush=True)
        if fix_strip(src, dest, session):
            print("OK")
            ok += 1
        else:
            print("FAIL")
            fail += 1

    print(f"\n{'='*60}")
    print(f"  DONE: {ok}/{len(files)} ok, {fail} failed")
    print(f"{'='*60}")

    if args.install and ok > 0:
        print("\nInstalling to game repo...")
        installed = 0
        for src in OUTPUT_DIR.glob("*.png"):
            dest = GAME_MONSTERS / src.name
            shutil.copy2(src, dest)
            installed += 1
        print(f"  Installed {installed} files to {GAME_MONSTERS}")


if __name__ == "__main__":
    main()
