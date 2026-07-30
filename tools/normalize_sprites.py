#!/usr/bin/env python3
"""
Normalize sprite frame alignment — fix position jumping and scale inconsistency.

For each sprite strip (horizontal sequence of 256x256 frames):
  1. Extract character bounding box per frame
  2. Compute reference size (max width/height across all frames)
  3. Scale each frame's character to the reference size
  4. Center each frame at the same position within the 256x256 cell
  5. Save the normalized strip

This fixes:
  - Monster idle "splitting" (position shifts between frames)
  - Cleric/mage scale inconsistency (character grows/shrinks)

Usage:
    uv run python tools/normalize_sprites.py --monsters   # fix all monster strips
    uv run python tools/normalize_sprites.py --jobs        # fix all job animations
    uv run python tools/normalize_sprites.py --file path/to/strip.png
    uv run python tools/normalize_sprites.py --all         # everything
"""

import argparse
import shutil
from pathlib import Path

from PIL import Image

GAME_REPO = Path("/home/struktured/projects/cowardly-irregular")
GAME_MONSTERS = GAME_REPO / "assets" / "sprites" / "monsters"
GAME_JOBS = GAME_REPO / "assets" / "sprites" / "jobs"

FRAME_SIZE = 256
ALPHA_THRESHOLD = 10

# Never touch artist files
PROTECTED = {
    "fighter": {"idle", "walk", "attack", "hit", "dead", "cast", "defend", "item", "victory",
                "advance", "defer", "cleave", "power_strike", "provoke", "slash"},
    "rogue": {"idle", "attack", "cast"},
}


def get_content_bbox(frame: Image.Image) -> tuple | None:
    """Get bounding box of non-transparent pixels in a frame."""
    if frame.mode != "RGBA":
        frame = frame.convert("RGBA")
    alpha = frame.split()[3]
    bbox = alpha.point(lambda p: 255 if p > ALPHA_THRESHOLD else 0).getbbox()
    return bbox


def normalize_strip(strip_path: Path, backup: bool = True) -> dict:
    """Normalize a horizontal sprite strip so all frames are aligned and same scale.

    Returns stats dict with drift measurements before/after.
    """
    img = Image.open(strip_path).convert("RGBA")
    w, h = img.size

    if h != FRAME_SIZE:
        return {"skipped": True, "reason": f"height {h} != {FRAME_SIZE}"}

    n_frames = w // FRAME_SIZE
    if n_frames < 2:
        return {"skipped": True, "reason": "single frame"}

    # Extract bounding boxes for each frame
    bboxes = []
    for i in range(n_frames):
        frame = img.crop((i * FRAME_SIZE, 0, (i + 1) * FRAME_SIZE, FRAME_SIZE))
        bbox = get_content_bbox(frame)
        bboxes.append(bbox)

    # Filter out empty frames
    valid = [(i, bb) for i, bb in enumerate(bboxes) if bb is not None]
    if len(valid) < 2:
        return {"skipped": True, "reason": "too few valid frames"}

    # Compute reference: use FIRST frame as canonical size/position
    # This anchors all other frames to the "hero" frame's appearance
    first_bb = valid[0][1]
    ref_w = first_bb[2] - first_bb[0]
    ref_h = first_bb[3] - first_bb[1]
    ref_cx = (first_bb[0] + first_bb[2]) / 2
    ref_cy = (first_bb[1] + first_bb[3]) / 2

    # For measurement purposes, still track all centers
    centers_x = [(bb[0] + bb[2]) / 2 for _, bb in valid]
    centers_y = [(bb[1] + bb[3]) / 2 for _, bb in valid]
    widths = [bb[2] - bb[0] for _, bb in valid]
    heights = [bb[3] - bb[1] for _, bb in valid]

    # Measure pre-fix drift
    pre_cx_drift = max(centers_x) - min(centers_x)
    pre_cy_drift = max(centers_y) - min(centers_y)
    pre_w_drift = max(widths) - min(widths)
    pre_h_drift = max(heights) - min(heights)

    # Build normalized strip
    out = Image.new("RGBA", (w, FRAME_SIZE), (0, 0, 0, 0))

    for i in range(n_frames):
        bbox = bboxes[i]
        frame = img.crop((i * FRAME_SIZE, 0, (i + 1) * FRAME_SIZE, FRAME_SIZE))

        if bbox is None:
            # Empty frame — leave transparent
            continue

        # Extract character content
        content = frame.crop(bbox)
        cw, ch = content.size

        # Scale to reference size (nearest-neighbor to preserve pixel art)
        if cw > 0 and ch > 0:
            scale_x = ref_w / cw
            scale_y = ref_h / ch
            # Use the SMALLER scale factor to preserve aspect ratio
            scale = min(scale_x, scale_y)
            # Allow up to 2x scale for aggressive alignment
            scale = max(0.4, min(2.0, scale))
            new_w = max(1, round(cw * scale))
            new_h = max(1, round(ch * scale))
            scaled = content.resize((new_w, new_h), Image.NEAREST)
        else:
            scaled = content
            new_w, new_h = cw, ch

        # Place at reference center within this frame's cell
        ox = i * FRAME_SIZE
        paste_x = int(ref_cx - new_w / 2)
        paste_y = int(ref_cy - new_h / 2)

        # Clamp to frame bounds
        paste_x = max(0, min(FRAME_SIZE - new_w, paste_x))
        paste_y = max(0, min(FRAME_SIZE - new_h, paste_y))

        out.paste(scaled, (ox + paste_x, paste_y), scaled)

    # Backup original
    if backup:
        backup_path = strip_path.with_suffix(".pre_normalize.png")
        if not backup_path.exists():
            shutil.copy2(strip_path, backup_path)

    # Save normalized
    out.save(strip_path)

    return {
        "skipped": False,
        "frames": n_frames,
        "pre_center_drift": (round(pre_cx_drift, 1), round(pre_cy_drift, 1)),
        "pre_size_drift": (pre_w_drift, pre_h_drift),
        "ref_size": (ref_w, ref_h),
    }


def process_monsters():
    """Normalize all monster strips."""
    print("=== MONSTERS ===")
    fixed = 0
    for png in sorted(GAME_MONSTERS.glob("*.png")):
        if "pre_normalize" in png.name or "import" in png.name:
            continue
        result = normalize_strip(png)
        if result.get("skipped"):
            continue
        drift = result["pre_center_drift"]
        size_d = result["pre_size_drift"]
        if drift[0] > 5 or drift[1] > 5 or size_d[0] > 20 or size_d[1] > 20:
            print(f"  FIXED {png.name}: center_drift={drift} size_drift={size_d}")
            fixed += 1
        else:
            # Still normalize for consistency, just don't report
            fixed += 1
    print(f"  Normalized {fixed} monster strips")
    return fixed


def process_jobs():
    """Normalize all job animation strips."""
    print("=== JOBS ===")
    fixed = 0
    for job_dir in sorted(GAME_JOBS.iterdir()):
        if not job_dir.is_dir():
            continue
        job = job_dir.name
        protected = PROTECTED.get(job, set())

        for png in sorted(job_dir.glob("*.png")):
            anim = png.stem
            if anim in protected:
                continue
            if "pre_normalize" in png.name or "import" in png.name or "overworld" in png.name:
                continue

            result = normalize_strip(png)
            if result.get("skipped"):
                continue
            drift = result["pre_center_drift"]
            size_d = result["pre_size_drift"]
            print(f"  FIXED {job}/{anim}: center_drift={drift} size_drift={size_d}")
            fixed += 1

    print(f"  Normalized {fixed} job animations")
    return fixed


def process_file(path: Path):
    """Normalize a single file."""
    result = normalize_strip(path)
    if result.get("skipped"):
        print(f"Skipped: {result['reason']}")
    else:
        print(f"Normalized {path.name}:")
        print(f"  Pre-fix center drift: {result['pre_center_drift']}")
        print(f"  Pre-fix size drift:   {result['pre_size_drift']}")
        print(f"  Reference size:       {result['ref_size']}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--monsters", action="store_true")
    parser.add_argument("--jobs", action="store_true")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--file", type=Path)
    parser.add_argument("--no-backup", action="store_true")
    args = parser.parse_args()

    if args.file:
        process_file(args.file)
        return

    total = 0
    if args.monsters or args.all:
        total += process_monsters()
    if args.jobs or args.all:
        total += process_jobs()

    if not any([args.monsters, args.jobs, args.all, args.file]):
        parser.print_help()
        return

    print(f"\nTotal normalized: {total}")


if __name__ == "__main__":
    main()
