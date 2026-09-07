#!/usr/bin/env python3
"""
PILOT: gpt-image-1 with artist reference.

Tests whether OpenAI's newer image model can take an artist sprite as reference
and produce style-matched variations we'd want for LoRA training.

Generates 5 variations of the rogue at ~$0.17 each = ~$1 total (quality=high).
Or use --low for $0.01/image = $0.05 total.

Output: tmp/gpt_image_pilot/
"""

import argparse
import base64
import io
import json
import os
import sys
import time
from pathlib import Path

from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = PROJECT / "tmp" / "gpt_image_pilot"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Prices as of 2026-04
COST_PER_IMAGE = {
    "low":    0.011,
    "medium": 0.042,
    "high":   0.167,
}

ARTIST_REFS = {
    "rogue": PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/ROGUE/Rogue Base sprite.png",
    "fighter": PROJECT / "assets/sprites/jobs/fighter/idle.png",
    "cleric": PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/CLERIC/Cleric Main design-Sheet.png",
    "mage": PROJECT / "assets/sprites/jobs/mage_artist/idle.png",
}

# Test poses — 5 variations for the pilot
PILOT_POSES = [
    "the same character in a walking stride pose, side view, mid-step",
    "the same character in an attack pose, sword or weapon raised overhead",
    "the same character in a casting pose, hand extended forward with magical energy",
    "the same character in a hit reaction, recoiling backward",
    "the same character in a victory pose, arms raised triumphantly",
]

BASE_PROMPT_TMPL = (
    "A 16-bit JRPG pixel art battle sprite of {pose}. "
    "Match the exact character design, palette, proportions, and pixel art style of the reference image. "
    "Pure transparent background, isolated character sprite, hard pixel outlines, no anti-aliasing, "
    "no text, no multiple characters, no reference sheet."
)


def prepare_reference(ref_path: Path) -> bytes:
    """Prepare an artist reference sprite for the API.

    API accepts up to 1024x1024. Upscale small sprites via nearest-neighbor
    to preserve pixel boundaries.
    """
    img = Image.open(ref_path).convert("RGBA")
    w, h = img.size
    # Scale to 1024 on longest side via nearest-neighbor (preserve pixel art look)
    target = 1024
    scale = min(target / w, target / h)
    new_w, new_h = max(1, int(w * scale)), max(1, int(h * scale))
    img = img.resize((new_w, new_h), Image.NEAREST)
    # Pad to square with transparent
    square = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    square.paste(img, ((target - new_w) // 2, (target - new_h) // 2), img)

    buf = io.BytesIO()
    square.save(buf, format="PNG")
    buf.seek(0)
    return buf.getvalue()


def call_gpt_image(client: OpenAI, prompt: str, ref_bytes: bytes,
                   quality: str = "high", size: str = "1024x1024") -> Image.Image:
    """Call gpt-image-1 with a reference image. Uses images.edit endpoint.

    Returns the generated PIL image.
    """
    ref_file = ("reference.png", ref_bytes, "image/png")
    resp = client.images.edit(
        model="gpt-image-1",
        image=ref_file,
        prompt=prompt,
        size=size,
        quality=quality,
        n=1,
    )
    b64 = resp.data[0].b64_json
    img_bytes = base64.b64decode(b64)
    return Image.open(io.BytesIO(img_bytes))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", default="rogue", choices=list(ARTIST_REFS.keys()))
    parser.add_argument("--quality", default="high", choices=["low", "medium", "high"])
    parser.add_argument("--size", default="1024x1024")
    parser.add_argument("--num", type=int, default=5, help="Number of pilot poses")
    args = parser.parse_args()

    ref_path = ARTIST_REFS[args.job]
    if not ref_path.exists():
        print(f"ERROR: artist ref not found: {ref_path}")
        sys.exit(1)

    if not os.environ.get("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not set. Run 'source setenv.sh' first.")
        sys.exit(1)

    print(f"Pilot: gpt-image-1 with {args.job} reference")
    print(f"  Ref: {ref_path}")
    print(f"  Quality: {args.quality}  Cost/image: ${COST_PER_IMAGE[args.quality]}")
    print(f"  Estimated total: ${COST_PER_IMAGE[args.quality] * args.num:.2f}")
    print()

    client = OpenAI()
    ref_bytes = prepare_reference(ref_path)

    # Save the prepared reference for inspection
    with open(OUTPUT_DIR / "_reference_prepped.png", "wb") as f:
        f.write(ref_bytes)

    results = []
    total_cost = 0.0
    start = time.time()

    for i, pose in enumerate(PILOT_POSES[:args.num]):
        prompt = BASE_PROMPT_TMPL.format(pose=pose)
        print(f"[{i+1}/{args.num}] {pose[:60]}...")
        try:
            img = call_gpt_image(client, prompt, ref_bytes, args.quality, args.size)
            out_path = OUTPUT_DIR / f"{args.job}_pilot_{i:02d}.png"
            img.save(out_path)
            cost = COST_PER_IMAGE[args.quality]
            total_cost += cost
            results.append({"idx": i, "pose": pose, "path": str(out_path), "cost": cost, "ok": True})
            print(f"   OK saved {out_path.name} ({img.size[0]}x{img.size[1]})  cost: ${cost:.3f}")
        except Exception as e:
            print(f"   ERROR: {e}")
            results.append({"idx": i, "pose": pose, "error": str(e), "ok": False})

    elapsed = time.time() - start

    meta = {
        "job": args.job,
        "quality": args.quality,
        "size": args.size,
        "model": "gpt-image-1",
        "total_cost_usd": round(total_cost, 3),
        "elapsed_sec": round(elapsed, 1),
        "results": results,
    }
    (OUTPUT_DIR / f"{args.job}_pilot_meta.json").write_text(json.dumps(meta, indent=2))

    print()
    print(f"Done. Total cost: ${total_cost:.3f}")
    print(f"Time: {elapsed:.1f}s")
    print(f"Output: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
