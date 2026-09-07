#!/usr/bin/env python3
"""
JRPG Pixel Art Style LoRA Training Dataset Curator for Cowardly Irregular.

Processes raw sprite rips (or existing artist sheets) into a clean dataset
for training a generic jrpg_pixel_style LoRA that captures the shared visual
language across all jobs — not any single character.

Each output frame is:
  - Split out of a sprite strip if the source is wider than it is tall
  - Auto-cropped to the character's bounding box
  - Scaled up with nearest-neighbor to fill ~75% of the canvas short side
  - Centered on a transparent canvas_size x canvas_size canvas
  - Validated: character content must be 5%-85% of the output canvas area

Usage:
    uv run python tools/curate_style_dataset.py --input-dir /path/to/rips
    uv run python tools/curate_style_dataset.py --include-artist-data
    uv run python tools/curate_style_dataset.py --input-dir /path/to/rips --include-artist-data \\
        --class-tag "cleric" --pose-tag "casting spell"
"""

import argparse
import re
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_JOBS_DIR = REPO_ROOT / "assets" / "sprites" / "jobs"

DEFAULT_OUTPUT_DIR = (
    REPO_ROOT / "tools" / "lora_training" / "style_dataset" / "10_jrpg_pixel_style"
)

STANDARD_ANIMATIONS = [
    "idle", "walk", "attack", "hit", "dead", "cast", "defend", "item", "victory",
]

ARTIST_JOBS = ["fighter", "cleric", "mage", "rogue"]

STYLE_TAG = "jrpg_pixel_style"

FILL_MIN = 0.05
FILL_MAX = 0.85
TARGET_FILL = 0.75

POSE_KEYWORD_MAP = {
    "idle": "idle stance",
    "walk": "walking pose",
    "attack": "attack pose",
    "hit": "hit reaction",
    "dead": "death pose",
    "cast": "casting pose",
    "defend": "defend stance",
    "item": "item use pose",
    "victory": "victory pose",
    "slash": "slash attack pose",
    "dash": "dash attack pose",
    "backstab": "backstab attack pose",
    "steal": "steal action pose",
    "mug": "mug attack pose",
    "flee": "fleeing pose",
    "heal": "healing pose",
    "raise": "raise ally pose",
    "buff": "buff casting pose",
    "advance": "advance action pose",
    "defer": "defer stance",
    "provoke": "provoke taunt pose",
    "cleave": "cleave attack pose",
    "power": "power strike pose",
}

CLASS_KEYWORD_MAP = {
    "fighter": "fighter",
    "warrior": "fighter",
    "cleric": "cleric",
    "healer": "cleric",
    "white_mage": "cleric",
    "mage": "mage",
    "wizard": "mage",
    "black_mage": "mage",
    "rogue": "rogue",
    "thief": "rogue",
    "bard": "bard",
    "guardian": "guardian",
    "ninja": "ninja",
    "summoner": "summoner",
}


def infer_tags_from_filename(stem: str) -> tuple[str, str]:
    """Attempt to infer class and pose tags from a filename stem.

    Returns (class_tag, pose_tag) falling back to generic defaults if nothing
    matches.
    """
    lower = stem.lower()
    parts = re.split(r"[_\-\s]+", lower)

    class_tag = "fantasy warrior"
    for part in parts:
        if part in CLASS_KEYWORD_MAP:
            class_tag = CLASS_KEYWORD_MAP[part]
            break

    pose_tag = "battle stance"
    for part in parts:
        if part in POSE_KEYWORD_MAP:
            pose_tag = POSE_KEYWORD_MAP[part]
            break

    return class_tag, pose_tag


def make_caption(class_tag: str, pose_tag: str) -> str:
    return (
        f"{STYLE_TAG}, pixel art battle sprite, {class_tag} character, "
        f"{pose_tag}, black pixel outline, transparent background"
    )


def alpha_channel(img: Image.Image) -> Image.Image:
    return img.split()[3]


def autocrop(img: Image.Image, alpha_threshold: int = 10) -> Image.Image:
    a = alpha_channel(img)
    bbox = a.point(lambda p: 255 if p > alpha_threshold else 0).getbbox()
    if bbox is None:
        return img
    return img.crop(bbox)


def count_opaque_pixels(img: Image.Image, alpha_threshold: int = 10) -> int:
    a = alpha_channel(img)
    return sum(1 for p in a.getflattened_data() if p > alpha_threshold) if hasattr(a, "getflattened_data") else sum(
        1 for p in a.tobytes() if p > alpha_threshold
    )


def scale_to_fill(cropped: Image.Image, canvas_size: int, target_fill: float) -> Image.Image:
    """Scale cropped sprite so its larger dimension is target_fill * canvas_size.

    Uses nearest-neighbor to preserve pixel art crispness.
    """
    cw, ch = cropped.size
    target_px = int(canvas_size * target_fill)
    scale = target_px / max(cw, ch)
    new_w = max(1, round(cw * scale))
    new_h = max(1, round(ch * scale))
    return cropped.resize((new_w, new_h), Image.NEAREST)


def place_on_canvas(sprite: Image.Image, canvas_size: int) -> Image.Image:
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    sw, sh = sprite.size
    x = (canvas_size - sw) // 2
    y = (canvas_size - sh) // 2
    canvas.paste(sprite, (x, y), sprite)
    return canvas


def canvas_fill_ratio(canvas: Image.Image) -> float:
    total = canvas.width * canvas.height
    opaque = sum(1 for p in canvas.split()[3].tobytes() if p > 10)
    return opaque / total


def split_sprite_strip(img: Image.Image) -> list[Image.Image]:
    """Split a horizontal sprite strip into square frames.

    Assumes square frames of size (height x height).
    """
    w, h = img.size
    frame_count = w // h
    frames = []
    for i in range(frame_count):
        box = (i * h, 0, (i + 1) * h, h)
        frames.append(img.crop(box))
    return frames


def process_single_png(
    png_path: Path,
    output_dir: Path,
    canvas_size: int,
    class_tag: str,
    pose_tag: str,
    counter: list[int],
) -> tuple[int, int]:
    """Process one PNG file, writing accepted frames to output_dir.

    counter is a mutable single-element list used as a shared sequential index.
    Returns (accepted, rejected) count for this file.
    """
    accepted = 0
    rejected = 0

    try:
        with Image.open(png_path) as raw:
            img = raw.convert("RGBA")
    except Exception as exc:
        print(f"  SKIP  {png_path.name}: could not open ({exc})")
        return 0, 1

    w, h = img.size
    if w >= 2 * h:
        frames = split_sprite_strip(img)
    else:
        frames = [img]

    inferred_class, inferred_pose = infer_tags_from_filename(png_path.stem)
    effective_class = class_tag if class_tag != "fantasy warrior" else inferred_class
    effective_pose = pose_tag if pose_tag != "battle stance" else inferred_pose

    for frame in frames:
        cropped = autocrop(frame)
        cw, ch = cropped.size
        if cw == 0 or ch == 0:
            rejected += 1
            continue

        scaled = scale_to_fill(cropped, canvas_size, TARGET_FILL)
        canvas = place_on_canvas(scaled, canvas_size)
        ratio = canvas_fill_ratio(canvas)

        if ratio < FILL_MIN:
            rejected += 1
            continue
        if ratio > FILL_MAX:
            rejected += 1
            continue

        idx = counter[0]
        counter[0] += 1

        out_png = output_dir / f"sprite_{idx:03d}.png"
        out_txt = output_dir / f"sprite_{idx:03d}.txt"

        canvas.save(out_png, "PNG")
        out_txt.write_text(make_caption(effective_class, effective_pose), encoding="utf-8")
        accepted += 1

    return accepted, rejected


def collect_artist_frames(
    output_dir: Path,
    canvas_size: int,
    counter: list[int],
) -> tuple[int, int]:
    total_accepted = 0
    total_rejected = 0

    for job_id in ARTIST_JOBS:
        job_dir = ASSETS_JOBS_DIR / job_id
        if not job_dir.exists():
            print(f"  SKIP  artist job dir not found: {job_dir}")
            continue

        for anim in STANDARD_ANIMATIONS:
            png_path = job_dir / f"{anim}.png"
            if not png_path.exists():
                continue

            class_tag = CLASS_KEYWORD_MAP.get(job_id, job_id)
            pose_tag = POSE_KEYWORD_MAP.get(anim, "battle stance")

            a, r = process_single_png(
                png_path, output_dir, canvas_size, class_tag, pose_tag, counter
            )
            total_accepted += a
            total_rejected += r
            if a:
                print(f"  OK    {job_id}/{anim}.png -> {a} frame(s)")
            else:
                print(f"  SKIP  {job_id}/{anim}.png -> all rejected ({r})")

    return total_accepted, total_rejected


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Curate a JRPG pixel art style LoRA training dataset from sprite rips."
    )
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=None,
        help="Directory of raw sprite PNGs to process.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Output dataset directory (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--canvas-size",
        type=int,
        default=512,
        help="Output canvas size in pixels, square (default: 512).",
    )
    parser.add_argument(
        "--class-tag",
        type=str,
        default="fantasy warrior",
        help=(
            'Character class label for captions (default: "fantasy warrior"). '
            "Override to force all input frames to one class. "
            "If left as default, class is inferred per-filename."
        ),
    )
    parser.add_argument(
        "--pose-tag",
        type=str,
        default="battle stance",
        help=(
            'Pose label for captions (default: "battle stance"). '
            "Override to force all input frames to one pose. "
            "If left as default, pose is inferred per-filename."
        ),
    )
    parser.add_argument(
        "--include-artist-data",
        action="store_true",
        help="Pull existing artist frames from assets/sprites/jobs/<job>/ and include them.",
    )
    args = parser.parse_args()

    if args.input_dir is None and not args.include_artist_data:
        parser.error("Provide --input-dir and/or --include-artist-data.")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Output directory: {args.output_dir}")
    print(f"Canvas size: {args.canvas_size}x{args.canvas_size}")
    print()

    counter = [0]
    total_processed = 0
    total_accepted = 0
    total_rejected = 0

    if args.include_artist_data:
        print("--- Including artist sprites ---")
        a, r = collect_artist_frames(args.output_dir, args.canvas_size, counter)
        total_accepted += a
        total_rejected += r
        total_processed += a + r
        print()

    if args.input_dir is not None:
        if not args.input_dir.exists():
            print(f"ERROR: --input-dir does not exist: {args.input_dir}", file=sys.stderr)
            sys.exit(1)

        pngs = sorted(args.input_dir.glob("*.png"))
        print(f"--- Processing {len(pngs)} PNG(s) from {args.input_dir} ---")

        for png_path in pngs:
            a, r = process_single_png(
                png_path,
                args.output_dir,
                args.canvas_size,
                args.class_tag,
                args.pose_tag,
                counter,
            )
            total_accepted += a
            total_rejected += r
            total_processed += a + r
            status = "OK" if a else "SKIP"
            print(f"  {status:<5} {png_path.name} -> {a} accepted, {r} rejected")
        print()

    print("=== Summary ===")
    print(f"  Images processed : {total_processed}")
    print(f"  Accepted         : {total_accepted}")
    print(f"  Rejected         : {total_rejected}")
    print(f"  Output location  : {args.output_dir}")

    if total_accepted == 0:
        print("\nWARNING: No images were accepted. Check fill-ratio thresholds or input data.")
        sys.exit(1)


if __name__ == "__main__":
    main()
