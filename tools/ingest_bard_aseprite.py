#!/usr/bin/env python3
"""Ingest the artist's Bard Base sprite.aseprite into the game.

Source: 12 frames @ 128x128, no tags. Layout (read left-to-right, top-to-bottom):
  Frames 0-3:  Idle stance (subtle sway/breathing)
  Frames 4-7:  Attack wind-up — magenta energy forms on the keyboard-glaive
  Frames 8-11: Attack swing arc + recovery

Mapping to the established 9-animation starter convention:
  idle    <- frames 0-3
  cast    <- frames 4-7   (energy charge maps cleanly to "cast")
  attack  <- frames 8-11  (the swing itself)

Output: horizontal-strip PNGs at 256x256 frames (2x nearest-neighbor upscale
to match fighter/mage/cleric/rogue convention). Each output replaces the
existing T1 file but only after the T1 version is backed up as
`<anim>.pre_artist.png` (mirrors the slime.pre_artist.png pattern).
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

ASEPRITE_SRC = Path(__file__).resolve().parents[1] / "tmp/bard_drop/Bard Base sprite.aseprite"
GAME_REPO = Path(__file__).resolve().parents[1].parent / "cowardly-irregular"
BARD_DIR = GAME_REPO / "assets/sprites/jobs/bard"

FRAME_SIZE = 128         # source frame size in the .aseprite
TARGET_FRAME = 256       # game-side starter convention

ANIM_MAP = {
    "idle":   (0, 3),    # frames 0..3 inclusive
    "cast":   (4, 7),    # frames 4..7 inclusive (energy wind-up)
    "attack": (8, 11),   # frames 8..11 inclusive (swing + recovery)
}


def export_individual_frames(out_dir: Path) -> list[Path]:
    """Use aseprite CLI to export each frame as a separate PNG."""
    out_dir.mkdir(parents=True, exist_ok=True)
    template = str(out_dir / "frame_{frame}.png")
    subprocess.run(
        ["aseprite", "-b", str(ASEPRITE_SRC),
         "--save-as", template],
        check=True,
        capture_output=True,
    )
    frames = sorted(out_dir.glob("frame_*.png"),
                    key=lambda p: int(p.stem.split("_")[1]))
    if len(frames) != 12:
        raise RuntimeError(f"expected 12 frames, got {len(frames)}: {frames}")
    return frames


def build_strip(frame_paths: list[Path], start: int, end: int) -> Image.Image:
    """Concatenate frames[start..end] (inclusive) into a horizontal strip,
    upscaled 2x nearest-neighbor to 256x256 per frame."""
    selected = frame_paths[start:end + 1]
    count = len(selected)
    strip = Image.new("RGBA", (TARGET_FRAME * count, TARGET_FRAME), (0, 0, 0, 0))
    for i, p in enumerate(selected):
        f = Image.open(p).convert("RGBA")
        if f.size != (FRAME_SIZE, FRAME_SIZE):
            raise RuntimeError(f"{p}: expected {FRAME_SIZE}x{FRAME_SIZE}, got {f.size}")
        upscaled = f.resize((TARGET_FRAME, TARGET_FRAME), Image.NEAREST)
        strip.paste(upscaled, (i * TARGET_FRAME, 0))
    return strip


def backup_existing(anim: str) -> None:
    """Back up existing <anim>.png to <anim>.pre_artist.png if not already."""
    existing = BARD_DIR / f"{anim}.png"
    backup = BARD_DIR / f"{anim}.pre_artist.png"
    if existing.exists() and not backup.exists():
        shutil.copy2(existing, backup)
        print(f"  backup: {anim}.png -> {anim}.pre_artist.png")


def main() -> int:
    if not ASEPRITE_SRC.exists():
        print(f"ERROR: source aseprite not found at {ASEPRITE_SRC}", file=sys.stderr)
        return 1
    if not BARD_DIR.exists():
        print(f"ERROR: bard dir missing at {BARD_DIR}", file=sys.stderr)
        return 1

    work_dir = ASEPRITE_SRC.parent / "frames"
    print(f"exporting individual frames to {work_dir}...")
    frames = export_individual_frames(work_dir)
    print(f"  got {len(frames)} frames @ {FRAME_SIZE}x{FRAME_SIZE}")

    for anim, (start, end) in ANIM_MAP.items():
        backup_existing(anim)
        strip = build_strip(frames, start, end)
        out_path = BARD_DIR / f"{anim}.png"
        strip.save(out_path)
        n = end - start + 1
        print(f"  -> {anim}.png: {strip.width}x{strip.height} ({n} frames @ {TARGET_FRAME}px)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
