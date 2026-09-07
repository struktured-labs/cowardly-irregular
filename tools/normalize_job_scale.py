#!/usr/bin/env python3
"""
Normalize character scale across all job sprite strips.

Problem: fighter fills 39% of 256x256 frame, AI sprites fill 67-83%.
BattleScene scales uniformly by frame_height, so characters appear
at wildly different sizes on screen.

Fix: rescale each frame's character content to target fill percentage,
matching the artist's range (~45% of frame height). Characters get
smaller within the frame, surrounded by more transparent space.

Usage:
    uv run python tools/normalize_job_scale.py                # fix all jobs
    uv run python tools/normalize_job_scale.py --job mage     # single job
    uv run python tools/normalize_job_scale.py --target-fill 0.45
"""

import argparse
import shutil
from pathlib import Path

from PIL import Image

GAME_JOBS = Path("/home/struktured/projects/cowardly-irregular/assets/sprites/jobs")
FRAME_SIZE = 256
DEFAULT_TARGET_FILL = 0.45  # 45% of frame height — matches artist range

PROTECTED_JOBS = {
    "fighter": True,
    "rogue": {"idle", "attack", "cast"},
}


def get_bbox(frame: Image.Image) -> tuple | None:
    if frame.mode != "RGBA":
        frame = frame.convert("RGBA")
    alpha = frame.split()[3]
    return alpha.point(lambda p: 255 if p > 10 else 0).getbbox()


def normalize_strip_scale(strip_path: Path, target_fill: float,
                          backup: bool = True) -> dict:
    """Rescale character within each frame to target fill percentage."""
    img = Image.open(strip_path).convert("RGBA")
    w, h = img.size
    if h != FRAME_SIZE:
        return {"skipped": True, "reason": f"height {h} != {FRAME_SIZE}"}

    n_frames = w // FRAME_SIZE
    if n_frames < 1:
        return {"skipped": True, "reason": "no frames"}

    # Measure all frames to get current fill
    bboxes = []
    for i in range(n_frames):
        frame = img.crop((i * FRAME_SIZE, 0, (i + 1) * FRAME_SIZE, FRAME_SIZE))
        bboxes.append(get_bbox(frame))

    valid = [(i, bb) for i, bb in enumerate(bboxes) if bb is not None]
    if not valid:
        return {"skipped": True, "reason": "all frames empty"}

    # Current fill: use first frame as reference
    ref_bb = valid[0][1]
    ref_h = ref_bb[3] - ref_bb[1]
    current_fill = ref_h / FRAME_SIZE

    # Skip if already close to target (within 10%)
    if abs(current_fill - target_fill) < 0.10:
        return {"skipped": True, "reason": f"fill {current_fill:.0%} already near target"}

    # Skip if character is SMALLER than target (don't upscale — preserves artist small sprites)
    if current_fill < target_fill:
        return {"skipped": True, "reason": f"fill {current_fill:.0%} below target, not upscaling"}

    # Scale factor to achieve target fill
    scale = target_fill / current_fill

    # Build output strip
    out = Image.new("RGBA", (w, FRAME_SIZE), (0, 0, 0, 0))

    for i in range(n_frames):
        bbox = bboxes[i]
        frame = img.crop((i * FRAME_SIZE, 0, (i + 1) * FRAME_SIZE, FRAME_SIZE))

        if bbox is None:
            continue

        # Crop character content
        content = frame.crop(bbox)
        cw, ch = content.size

        # Scale down
        new_w = max(1, round(cw * scale))
        new_h = max(1, round(ch * scale))
        scaled = content.resize((new_w, new_h), Image.NEAREST)

        # Center in frame — anchor to bottom-center (feet stay grounded)
        paste_x = (FRAME_SIZE - new_w) // 2
        paste_y = FRAME_SIZE - new_h - 10  # 10px bottom margin for grounding

        out.paste(scaled, (i * FRAME_SIZE + paste_x, paste_y), scaled)

    if backup:
        bak = strip_path.with_suffix(".pre_scale.png")
        if not bak.exists():
            shutil.copy2(strip_path, bak)

    out.save(strip_path)

    return {
        "skipped": False,
        "before_fill": f"{current_fill:.0%}",
        "after_fill": f"{target_fill:.0%}",
        "scale": f"{scale:.2f}",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", help="Single job to fix")
    parser.add_argument("--target-fill", type=float, default=DEFAULT_TARGET_FILL)
    args = parser.parse_args()

    print(f"Target fill: {args.target_fill:.0%} of {FRAME_SIZE}px frame\n")

    total_fixed = 0
    jobs = [args.job] if args.job else sorted([d.name for d in GAME_JOBS.iterdir() if d.is_dir()])

    for job in jobs:
        job_dir = GAME_JOBS / job
        if not job_dir.is_dir():
            continue

        protected = PROTECTED_JOBS.get(job)
        if protected is True:
            continue

        for png in sorted(job_dir.glob("*.png")):
            anim = png.stem
            if isinstance(protected, set) and anim in protected:
                continue
            if any(skip in png.name for skip in ["pre_", "import", "overworld"]):
                continue

            result = normalize_strip_scale(png, args.target_fill)
            if result.get("skipped"):
                continue

            print(f"  {job}/{anim}: {result['before_fill']} -> {result['after_fill']} (scale {result['scale']})")
            total_fixed += 1

    print(f"\nNormalized {total_fixed} animations to {args.target_fill:.0%} fill")


if __name__ == "__main__":
    main()
