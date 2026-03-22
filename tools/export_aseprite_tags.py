#!/usr/bin/env python3
"""
Export Aseprite tags as horizontal strip PNGs for the Cowardly Irregular sprite system.

Fighter_extended.aseprite: 128x128 frames -> upscale 2x to 256x256
Cleric_extended.aseprite: 630x400 frames -> scale-to-fit-height 256x256 with centering

Usage:
    python3 tools/export_aseprite_tags.py
"""

import subprocess
import json
import os
import sys
from pathlib import Path

# ---- Paths ----------------------------------------------------------------
GAME_ROOT = Path("/home/struktured/projects/cowardly-irregular")
ASE_DIR = GAME_ROOT / "assets/sprites/jobs/aseprite"
TMP_DIR = GAME_ROOT / "tmp/aseprite_export"
TMP_DIR.mkdir(parents=True, exist_ok=True)

FIGHTER_SRC = ASE_DIR / "Fighter_extended.aseprite"
FIGHTER_OUT = GAME_ROOT / "assets/sprites/jobs/fighter"

CLERIC_SRC = ASE_DIR / "Cleric_extended.aseprite"
CLERIC_OUT = GAME_ROOT / "assets/sprites/jobs/cleric_artist"

TARGET_FRAME = 256  # game standard: 256x256 per frame

# ---- Tags to export -------------------------------------------------------
# Fighter: only overwrite these 5 animations
FIGHTER_TAGS = ["idle", "attack", "walk", "hit", "dead"]

# Cleric: only the tags present in the aseprite (idle, cast, walk)
CLERIC_TAGS = ["idle", "cast", "walk"]

# ---- Helpers --------------------------------------------------------------

def run(cmd, check=True):
    """Run a shell command, print it, and return CompletedProcess."""
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 and check:
        print(f"  STDERR: {result.stderr.strip()}")
        print(f"  STDOUT: {result.stdout.strip()}")
        raise RuntimeError(f"Command failed: {cmd}")
    if result.stderr.strip():
        print(f"  (stderr): {result.stderr.strip()[:200]}")
    return result


def aseprite_export_tag(src: Path, tag: str, out_dir: Path) -> list[Path]:
    """
    Export all frames of a tag from an aseprite file as individual PNGs.
    Returns list of frame PNG paths in order.
    """
    out_pattern = out_dir / f"{tag}_f{{frame}}.png"
    cmd = [
        "aseprite", "-b", str(src),
        "--tag", tag,
        "--save-as", str(out_pattern),
    ]
    run(cmd)
    # Collect all exported frames (sorted)
    frames = sorted(out_dir.glob(f"{tag}_f*.png"))
    return frames


def scale_frame_nearest(src: Path, dst: Path, size: int):
    """Upscale a frame to size x size using nearest-neighbor (pixel-perfect)."""
    cmd = [
        "convert", str(src),
        "-filter", "Point",
        "-resize", f"{size}x{size}!",
        str(dst),
    ]
    run(cmd)


def fit_frame_to_square(src: Path, dst: Path, size: int):
    """
    Scale-to-fit a frame into a size x size square (preserving aspect ratio),
    centered on a transparent background.
    Input is 630x400 (cleric) -> fits 256x256 with letterbox.
    """
    cmd = [
        "convert", str(src),
        "-resize", f"{size}x{size}",   # fit inside, preserve aspect
        "-background", "none",
        "-gravity", "Center",
        "-extent", f"{size}x{size}",   # pad to exact size
        str(dst),
    ]
    run(cmd)


def build_horizontal_strip(frame_paths: list[Path], out_path: Path):
    """Concatenate frames side by side into a horizontal strip PNG."""
    cmd = ["convert"] + [str(p) for p in frame_paths] + ["+append", str(out_path)]
    run(cmd)


def verify_strip(path: Path, expected_frames: int):
    """Verify a strip PNG has the right dimensions."""
    result = run(["identify", "-format", "%wx%h", str(path)])
    dims = result.stdout.strip()
    # Remove trailing newline artifact from identify
    dims = dims.split("\n")[0]
    w_str, h_str = dims.split("x")
    w, h = int(w_str), int(h_str)
    frame_w = w // expected_frames
    if frame_w != TARGET_FRAME or h != TARGET_FRAME:
        raise ValueError(
            f"{path.name}: expected {expected_frames*TARGET_FRAME}x{TARGET_FRAME}, "
            f"got {w}x{h} (frame_w={frame_w})"
        )
    print(f"  OK: {path.name} = {w}x{h} ({expected_frames} frames @ {TARGET_FRAME}x{TARGET_FRAME})")


# ---- Fighter export -------------------------------------------------------

def export_fighter():
    print("\n=== FIGHTER ===")
    work_dir = TMP_DIR / "fighter"
    work_dir.mkdir(parents=True, exist_ok=True)

    # Clean up old temp frames
    for old in work_dir.glob("*.png"):
        old.unlink()

    for tag in FIGHTER_TAGS:
        print(f"\n-- Tag: {tag} --")
        frames = aseprite_export_tag(FIGHTER_SRC, tag, work_dir)
        print(f"  Exported {len(frames)} raw frames")

        if not frames:
            print(f"  WARNING: no frames found for tag '{tag}', skipping")
            continue

        # Verify raw frame size is 128x128
        result = run(["identify", "-format", "%wx%h", str(frames[0])])
        raw_dims = result.stdout.strip().split("\n")[0]
        if raw_dims != "128x128":
            print(f"  WARNING: unexpected raw frame size {raw_dims} for fighter/{tag}")

        # Upscale each frame 128->256 nearest-neighbor
        scaled_frames = []
        for i, fp in enumerate(frames):
            scaled = work_dir / f"{tag}_scaled_{i:02d}.png"
            scale_frame_nearest(fp, scaled, TARGET_FRAME)
            scaled_frames.append(scaled)

        # Build horizontal strip
        out_png = FIGHTER_OUT / f"{tag}.png"
        print(f"  Building strip: {out_png}")
        build_horizontal_strip(scaled_frames, out_png)
        verify_strip(out_png, len(scaled_frames))

    print("\nFighter export complete.")


# ---- Cleric export --------------------------------------------------------

def export_cleric():
    print("\n=== CLERIC ===")
    work_dir = TMP_DIR / "cleric"
    work_dir.mkdir(parents=True, exist_ok=True)

    # Clean up old temp frames
    for old in work_dir.glob("*.png"):
        old.unlink()

    for tag in CLERIC_TAGS:
        print(f"\n-- Tag: {tag} --")
        frames = aseprite_export_tag(CLERIC_SRC, tag, work_dir)
        print(f"  Exported {len(frames)} raw frames")

        if not frames:
            print(f"  WARNING: no frames found for tag '{tag}', skipping")
            continue

        # Verify raw frame size
        result = run(["identify", "-format", "%wx%h", str(frames[0])])
        raw_dims = result.stdout.strip().split("\n")[0]
        print(f"  Raw frame size: {raw_dims}")

        # Scale-to-fit into 256x256 with centering
        scaled_frames = []
        for i, fp in enumerate(frames):
            scaled = work_dir / f"{tag}_scaled_{i:02d}.png"
            fit_frame_to_square(fp, scaled, TARGET_FRAME)
            scaled_frames.append(scaled)

        # Build horizontal strip
        out_png = CLERIC_OUT / f"{tag}.png"
        print(f"  Building strip: {out_png}")
        build_horizontal_strip(scaled_frames, out_png)
        verify_strip(out_png, len(scaled_frames))

    print("\nCleric export complete.")


# ---- Main -----------------------------------------------------------------

def main():
    print(f"Target frame size: {TARGET_FRAME}x{TARGET_FRAME}")
    print(f"Temp dir: {TMP_DIR}")

    if not FIGHTER_SRC.exists():
        print(f"ERROR: Fighter source not found: {FIGHTER_SRC}")
        sys.exit(1)
    if not CLERIC_SRC.exists():
        print(f"ERROR: Cleric source not found: {CLERIC_SRC}")
        sys.exit(1)

    export_fighter()
    export_cleric()

    print("\n=== EXPORT SUMMARY ===")
    print("Fighter outputs:")
    for tag in FIGHTER_TAGS:
        p = FIGHTER_OUT / f"{tag}.png"
        if p.exists():
            result = subprocess.run(["identify", "-format", "%wx%h", str(p)], capture_output=True, text=True)
            dims = result.stdout.strip().split("\n")[0]
            w, h = dims.split("x")
            frames = int(w) // int(h)
            print(f"  {tag}.png: {dims} = {frames} frames")
        else:
            print(f"  {tag}.png: MISSING")

    print("Cleric (cleric_artist) outputs:")
    for tag in CLERIC_TAGS:
        p = CLERIC_OUT / f"{tag}.png"
        if p.exists():
            result = subprocess.run(["identify", "-format", "%wx%h", str(p)], capture_output=True, text=True)
            dims = result.stdout.strip().split("\n")[0]
            w, h = dims.split("x")
            frames = int(w) // int(h)
            print(f"  {tag}.png: {dims} = {frames} frames")
        else:
            print(f"  {tag}.png: MISSING")


if __name__ == "__main__":
    main()
