#!/usr/bin/env python3
"""
Lock sprite palettes to the artist's actual color palette.

Extracts a master palette from all artist sprite frames, then quantizes
every generated sprite to ONLY use those colors. This is the single
biggest visual improvement for making AI-generated sprites look hand-drawn.

Artist uses 58-134 colors per animation. Our SDXL output uses 500-1500.
After palette lock, output uses the same ~175 core colors the artist uses.

Pipeline:
  1. Extract master palette from all artist sources
  2. For each generated sprite strip:
     a. Split into frames
     b. Map each opaque pixel to nearest palette color (Euclidean RGB distance)
     c. Preserve alpha channel exactly
     d. Reassemble strip
  3. Optionally clean up with median filter to reduce noise from mapping

Usage:
    uv run python tools/palette_lock.py --extract          # build palette from artist data
    uv run python tools/palette_lock.py --apply-monsters   # lock all monster sprites
    uv run python tools/palette_lock.py --apply-jobs       # lock all job sprites
    uv run python tools/palette_lock.py --apply-all        # everything
    uv run python tools/palette_lock.py --file path.png    # single file
"""

import argparse
import json
import os
import shutil
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.spatial import KDTree

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path("/home/struktured/projects/cowardly-irregular")
GAME_MONSTERS = GAME_REPO / "assets" / "sprites" / "monsters"
GAME_JOBS = GAME_REPO / "assets" / "sprites" / "jobs"

PALETTE_FILE = PROJECT / "tools" / "lora_training" / "artist_palette.json"

# Artist source directories — game-specific sprites only (not portfolio samples)
ARTIST_SOURCES = [
    GAME_JOBS / "fighter",
    PROJECT / "assets" / "sprites" / "drive_archive" / "Game graphics - Characters" / "ROGUE",
    PROJECT / "assets" / "sprites" / "drive_archive" / "Game graphics - Characters" / "CLERIC",
    PROJECT / "assets" / "sprites" / "drive_archive" / "Game graphics - Characters" / "MAGE",
]

# Never modify artist files
PROTECTED_JOBS = {
    "fighter": True,  # all anims protected
    "rogue": {"idle", "attack", "cast"},
}

MIN_COLOR_USAGE = 50  # only include colors used at least this many times


def extract_artist_palette(min_usage: int = MIN_COLOR_USAGE) -> list[tuple[int, int, int]]:
    """Extract the master palette from all artist sprite sources."""
    color_counts = Counter()

    for src_dir in ARTIST_SOURCES:
        if not src_dir.exists():
            continue
        for f in src_dir.iterdir():
            if f.suffix.lower() not in (".png", ".gif"):
                continue
            try:
                img = Image.open(f).convert("RGBA")
                for px in img.getdata():
                    if px[3] > 10:  # skip transparent
                        color_counts[(px[0], px[1], px[2])] += 1
            except Exception:
                pass

    # Filter to colors used consistently
    palette = [color for color, count in color_counts.most_common() if count >= min_usage]

    # Always include pure black (outline) and common UI colors
    essentials = [(0, 0, 0), (26, 24, 32), (255, 255, 255)]
    for e in essentials:
        if e not in palette:
            palette.append(e)

    return palette


def save_palette(palette: list[tuple[int, int, int]]):
    """Save palette to JSON for reuse."""
    PALETTE_FILE.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "colors": palette,
        "count": len(palette),
        "min_usage": MIN_COLOR_USAGE,
    }
    PALETTE_FILE.write_text(json.dumps(data, indent=2))
    print(f"Saved palette ({len(palette)} colors) to {PALETTE_FILE}")


def load_palette() -> list[tuple[int, int, int]]:
    """Load palette from JSON."""
    if not PALETTE_FILE.exists():
        print("No saved palette found — extracting from artist data...")
        palette = extract_artist_palette()
        save_palette(palette)
        return palette
    data = json.loads(PALETTE_FILE.read_text())
    return [tuple(c) for c in data["colors"]]


def build_kdtree(palette: list[tuple[int, int, int]]) -> tuple[KDTree, np.ndarray]:
    """Build a KD-tree for fast nearest-color lookup."""
    arr = np.array(palette, dtype=np.float32)
    tree = KDTree(arr)
    return tree, arr


def palette_lock_image(img: Image.Image, tree: KDTree, palette_arr: np.ndarray) -> Image.Image:
    """Map every opaque pixel to its nearest palette color. Preserve alpha."""
    if img.mode != "RGBA":
        img = img.convert("RGBA")

    data = np.array(img)
    h, w, _ = data.shape

    # Separate RGB and alpha
    rgb = data[:, :, :3].reshape(-1, 3).astype(np.float32)
    alpha = data[:, :, 3].reshape(-1)

    # Only process opaque pixels
    opaque_mask = alpha > 10
    if opaque_mask.sum() == 0:
        return img

    opaque_rgb = rgb[opaque_mask]

    # Find nearest palette color for each opaque pixel
    _, indices = tree.query(opaque_rgb)
    mapped = palette_arr[indices].astype(np.uint8)

    # Write back
    rgb[opaque_mask] = mapped
    data[:, :, :3] = rgb.reshape(h, w, 3)

    return Image.fromarray(data, "RGBA")


def process_strip(strip_path: Path, tree: KDTree, palette_arr: np.ndarray,
                  backup: bool = True) -> dict:
    """Palette-lock a sprite strip."""
    try:
        img = Image.open(strip_path).convert("RGBA")
    except Exception as e:
        return {"error": str(e)}

    # Count colors before
    rgb_data = np.array(img)
    alpha = rgb_data[:, :, 3]
    opaque = rgb_data[alpha > 10][:, :3]
    before_colors = len(set(map(tuple, opaque.tolist()))) if len(opaque) > 0 else 0

    # Apply palette lock
    locked = palette_lock_image(img, tree, palette_arr)

    # Count colors after
    rgb_data2 = np.array(locked)
    opaque2 = rgb_data2[alpha > 10][:, :3]
    after_colors = len(set(map(tuple, opaque2.tolist()))) if len(opaque2) > 0 else 0

    # Backup
    if backup:
        bak = strip_path.with_suffix(".pre_palette.png")
        if not bak.exists():
            shutil.copy2(strip_path, bak)

    locked.save(strip_path)

    return {
        "before_colors": before_colors,
        "after_colors": after_colors,
        "reduction": before_colors - after_colors,
    }


def apply_to_monsters(tree, palette_arr):
    print("=== MONSTERS ===")
    total_before = 0
    total_after = 0
    count = 0
    for png in sorted(GAME_MONSTERS.glob("*.png")):
        if "pre_palette" in png.name or "pre_normalize" in png.name or "import" in png.name:
            continue
        result = process_strip(png, tree, palette_arr)
        if "error" in result:
            continue
        total_before += result["before_colors"]
        total_after += result["after_colors"]
        count += 1
        if result["reduction"] > 100:
            print(f"  {png.name}: {result['before_colors']} -> {result['after_colors']} colors")
    print(f"  Processed {count} monsters")
    if count:
        print(f"  Avg colors: {total_before//count} -> {total_after//count}")


def apply_to_jobs(tree, palette_arr):
    print("=== JOBS ===")
    total = 0
    for job_dir in sorted(GAME_JOBS.iterdir()):
        if not job_dir.is_dir():
            continue
        job = job_dir.name

        # Skip fully protected jobs
        protected = PROTECTED_JOBS.get(job)
        if protected is True:
            continue

        for png in sorted(job_dir.glob("*.png")):
            anim = png.stem
            # Skip protected animations
            if isinstance(protected, set) and anim in protected:
                continue
            if "pre_palette" in png.name or "pre_normalize" in png.name or "import" in png.name:
                continue
            if "overworld" in anim:
                continue

            result = process_strip(png, tree, palette_arr)
            if "error" in result:
                continue
            total += 1
            if result["reduction"] > 50:
                print(f"  {job}/{anim}: {result['before_colors']} -> {result['after_colors']} colors")

    print(f"  Processed {total} job animations")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--extract", action="store_true", help="Extract and save artist palette")
    parser.add_argument("--apply-monsters", action="store_true")
    parser.add_argument("--apply-jobs", action="store_true")
    parser.add_argument("--apply-all", action="store_true")
    parser.add_argument("--file", type=Path)
    parser.add_argument("--min-usage", type=int, default=MIN_COLOR_USAGE)
    args = parser.parse_args()

    if args.extract:
        palette = extract_artist_palette(args.min_usage)
        save_palette(palette)
        print(f"\nExtracted {len(palette)} colors (min usage: {args.min_usage})")
        return

    # Load or extract palette
    palette = load_palette()
    tree, palette_arr = build_kdtree(palette)
    print(f"Palette: {len(palette)} colors\n")

    if args.file:
        result = process_strip(args.file, tree, palette_arr)
        print(f"{args.file.name}: {result}")
        return

    if args.apply_monsters or args.apply_all:
        apply_to_monsters(tree, palette_arr)
    if args.apply_jobs or args.apply_all:
        apply_to_jobs(tree, palette_arr)

    if not any([args.apply_monsters, args.apply_jobs, args.apply_all, args.file, args.extract]):
        parser.print_help()


if __name__ == "__main__":
    main()
