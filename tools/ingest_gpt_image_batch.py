#!/usr/bin/env python3
"""
Ingest the gpt-image-1 batch into the LoRA training dataset.

Each image:
  - Is scaled down to 512x512 (keeping aspect) with LANCZOS
  - Auto-cropped to content bounding box (if transparent bg)
  - Placed on transparent 512x512 canvas
  - Gets a caption file matching the per-job / per-pose prompt it was generated from

Goes into tools/lora_training/style_dataset/20_artist/ (highest repeat weight).
"""

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
BATCH_DIR = PROJECT / "tmp" / "gpt_image_batch"
TARGET_BUCKET = PROJECT / "tools" / "lora_training" / "style_dataset" / "20_artist"

sys.path.insert(0, str(PROJECT))

STYLE_TAG = "jrpg_pixel_style"

JOB_CAPTIONS = {
    "fighter": "medieval fighter warrior, red plate armor, brown hair, broadsword",
    "rogue":   "rogue assassin, dark navy hooded leather, red accents, dual weapons, long brown hair",
    "cleric":  "cleric priestess, white and purple hooded robes, golden star staff, braided hair",
    "mage":    "mage wizard, deep blue robes, tall pointed hat, glowing staff",
}

# Same pose library as generator — index must match filename suffix
from tools.gen_gpt_image_training_batch import POSES


def autocrop_and_normalize(img: Image.Image, canvas_size: int = 512) -> Image.Image:
    """Crop to content, scale to fill ~75% of canvas, center on transparent canvas.

    If the image has a solid (non-transparent) background, we pass through at
    fit-scale without cropping, since the background is part of the training signal.
    """
    if img.mode != "RGBA":
        img = img.convert("RGBA")

    # Check if background is mostly transparent
    alpha = img.split()[3]
    bbox = alpha.point(lambda p: 255 if p > 10 else 0).getbbox()
    total_opaque = sum(1 for p in alpha.tobytes() if p > 10)
    total_pixels = img.width * img.height
    opaque_ratio = total_opaque / total_pixels

    if bbox and opaque_ratio < 0.85:
        # Transparent-bg style — crop tight
        cropped = img.crop(bbox)
    else:
        # Solid bg — downscale whole image, preserve framing
        cropped = img

    # Fit into canvas preserving aspect
    cw, ch = cropped.size
    target_fill = 0.80
    target_px = int(canvas_size * target_fill)
    scale = target_px / max(cw, ch)
    new_w = max(1, int(cw * scale))
    new_h = max(1, int(ch * scale))
    scaled = cropped.resize((new_w, new_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    x = (canvas_size - new_w) // 2
    y = (canvas_size - new_h) // 2
    canvas.paste(scaled, (x, y), scaled if scaled.mode == "RGBA" else None)
    return canvas


def caption_for(job: str, pose_idx: int) -> str:
    char_desc = JOB_CAPTIONS.get(job, job)
    pose = POSES[pose_idx % len(POSES)]
    return (
        f"{STYLE_TAG}, pixel art battle sprite, {char_desc}, "
        f"{pose}, black pixel outline, transparent background, "
        f"artist-anchored, 16-bit SNES style"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    TARGET_BUCKET.mkdir(parents=True, exist_ok=True)

    # Find the next available index in the 20_artist bucket
    existing_idx = 0
    for f in TARGET_BUCKET.glob("*.png"):
        stem = f.stem
        parts = stem.rsplit("_", 1)
        if len(parts) == 2 and parts[1].isdigit():
            existing_idx = max(existing_idx, int(parts[1]) + 1)

    print(f"Target: {TARGET_BUCKET}")
    print(f"Starting index: gpt_{existing_idx:03d}")
    print()

    total_ok = 0
    total_fail = 0
    counter = [existing_idx]

    for job_dir in sorted(BATCH_DIR.iterdir()):
        if not job_dir.is_dir():
            continue
        job = job_dir.name
        if job not in JOB_CAPTIONS:
            continue

        print(f"--- {job} ---")
        for png_path in sorted(job_dir.glob(f"{job}_*.png")):
            # Extract pose index from filename
            stem = png_path.stem  # e.g. "rogue_003"
            try:
                pose_idx = int(stem.rsplit("_", 1)[1])
            except (IndexError, ValueError):
                print(f"  SKIP {png_path.name}: bad name")
                continue

            try:
                img = Image.open(png_path)
                normalized = autocrop_and_normalize(img)

                idx = counter[0]
                counter[0] += 1

                out_png = TARGET_BUCKET / f"gpt_{idx:03d}.png"
                out_txt = TARGET_BUCKET / f"gpt_{idx:03d}.txt"

                caption = caption_for(job, pose_idx)

                if not args.dry_run:
                    normalized.save(out_png, "PNG")
                    out_txt.write_text(caption, encoding="utf-8")

                total_ok += 1
                if total_ok % 20 == 0 or args.dry_run:
                    print(f"  [{total_ok}] {png_path.name} -> gpt_{idx:03d}.png")
            except Exception as e:
                print(f"  FAIL {png_path.name}: {e}")
                total_fail += 1

    print()
    print(f"{'='*60}")
    print(f"  Ingested: {total_ok}  Failed: {total_fail}")
    print(f"  Dry-run: {args.dry_run}")
    print(f"  Bucket: {TARGET_BUCKET}")
    print(f"{'='*60}")

    if not args.dry_run and total_ok > 0:
        print("\nNext steps:")
        print("  1. Purge .npz caches: find tools/lora_training/style_dataset -name '*.npz' -delete")
        print("  2. Retrain: bash tools/lora_training/train_style_lora.sh 12000")


if __name__ == "__main__":
    main()
