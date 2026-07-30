#!/usr/bin/env python3
"""Regenerate broken party portraits with gpt-image-1.

Uses the artist's source sprite sheet as reference and prompts for a
tight face-and-shoulders bust matching the (already good) cleric.png
framing: 256x256, transparent background, JRPG close-up portrait.

Broken portraits (per playtest audit 2026-07-01):
    fighter.png — truncated, red smudge artifact right side
    mage.png    — face obscured under hat, duplicate body artifact below
    rogue.png   — head-only, stylistically off (smaller anime features)
    bard.png    — head-only, missing shoulders

Good baseline (unchanged):
    cleric.png  — face + upper torso + hooded robe

Cost at medium quality: ~$0.042/image = ~$0.17 for all 4.

Usage:
    uv run python tools/regen_broken_portraits.py            # regen all 4 broken
    uv run python tools/regen_broken_portraits.py --jobs fighter  # just one
    uv run python tools/regen_broken_portraits.py --quality high  # $0.17/img
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
GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
OUTPUT_DIR = PROJECT / "tmp" / "portrait_regen"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

COST_PER_IMAGE = {"low": 0.011, "medium": 0.042, "high": 0.167}

# Artist source references — identity anchor. Sheets are OK; the AI
# focuses on the character even when the reference is a strip.
ARTIST_REFS = {
    "fighter": PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/FIGHTER/Main Fighter IDLE-Sheet.png",
    "mage":    PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/MAGE/Mage IDLE.png",
    "rogue":   PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/ROGUE/Rogue Base sprite.png",
    "bard":    Path("/tmp/bard_ref.png"),  # exported from Bard Base sprite.aseprite
}

# Per-character identity description (reinforces the artist reference)
JOB_DESC = {
    "fighter": "young male warrior with brown spiky hair, blue eyes, wearing red plate armor with steel-gray trim, determined expression",
    "mage":    "young dark wizard mage with dark shadowed features under a tall pointed purple wizard hat, glowing violet eyes, wearing teal-navy robes with silver trim",
    "rogue":   "hooded rogue with face partially hidden by a deep dark navy hood and dusty purple scarf, only sharp amber eyes visible in shadow, dark leather collar",
    "bard":    "charming young female bard with long orange hair pulled back in a loose ponytail, warm hazel eyes, wearing a crimson-and-plum leather doublet with dark purple accents at the collar, half-smile, no hat",
}

# Style anchor — matches the (good) cleric portrait framing exactly.
STYLE_PROMPT = (
    "16-bit JRPG pixel-art character portrait bust. Close-up on face, "
    "hair, and upper shoulders — head fills roughly 60% of frame, "
    "shoulders visible at bottom. Centered composition on a fully "
    "transparent background. Same clean pixel-art style, palette, and "
    "shading discipline as classic Final Fantasy VI / Chrono Trigger "
    "menu portraits: bold outlines, soft cel shading, no anti-aliasing "
    "artifacts, no floating pixels, no duplicate limbs, no weapons in "
    "frame, no scenery. Face fully visible and unobscured."
)


def load_reference(path: Path) -> bytes:
    img = Image.open(path).convert("RGBA")
    # If reference is a strip, take the first frame (leftmost square-ish region)
    w, h = img.size
    if w > h * 1.5:
        img = img.crop((0, 0, h, h))
    # Pad to 1024x1024 for the API (upscale nearest to preserve pixel art)
    target = 1024
    scale = target / max(img.size)
    new_w, new_h = int(img.size[0] * scale), int(img.size[1] * scale)
    img = img.resize((new_w, new_h), Image.NEAREST)
    canvas = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    canvas.paste(img, ((target - new_w) // 2, (target - new_h) // 2), img)
    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def call_gpt_image(client, prompt: str, ref_bytes: bytes, quality: str,
                   max_retries: int = 3) -> Image.Image:
    for attempt in range(max_retries):
        try:
            resp = client.images.edit(
                model="gpt-image-1",
                image=("reference.png", ref_bytes, "image/png"),
                prompt=prompt,
                size="1024x1024",
                quality=quality,
                n=1,
            )
            b64 = resp.data[0].b64_json
            return Image.open(io.BytesIO(base64.b64decode(b64)))
        except Exception as e:
            msg = str(e).lower()
            if "rate" in msg or "429" in msg:
                wait = 30 * (attempt + 1)
                print(f"    Rate limit; backing off {wait}s...")
                time.sleep(wait)
            elif any(k in msg for k in ("billing", "quota", "insufficient")):
                raise
            else:
                print(f"    Error: {e}; retry {attempt+1}/{max_retries}")
                time.sleep(5)
    raise RuntimeError(f"Failed after {max_retries} retries")


def downscale_to_portrait(img_1024: Image.Image, target: int = 256) -> Image.Image:
    """1024 → 256 with pixel-art-preserving chain."""
    img = img_1024.convert("RGBA")
    # Two-step: LANCZOS to 4x target for smoothing, then BOX to target for
    # crispness. Same chain used by the sprite pipeline.
    intermediate = target * 4
    img = img.resize((intermediate, intermediate), Image.LANCZOS)
    img = img.resize((target, target), Image.BOX)
    return img


def remove_flat_background(img: Image.Image, threshold: int = 240) -> Image.Image:
    """Make near-white background transparent."""
    img = img.convert("RGBA")
    px = img.load()
    W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return img


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs", nargs="+", default=list(ARTIST_REFS.keys()),
                        help="Which portraits to regen")
    parser.add_argument("--quality", choices=["low", "medium", "high"],
                        default="medium")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    portraits_dir = GAME_REPO / "assets/sprites/portraits"
    if not portraits_dir.exists():
        print(f"ERROR: portraits dir not found: {portraits_dir}", file=sys.stderr)
        return 1

    total_cost = 0.0
    unit = COST_PER_IMAGE[args.quality]

    if args.dry_run:
        print(f"DRY RUN — would regen {len(args.jobs)} portraits "
              f"at {args.quality} quality (~${unit * len(args.jobs):.3f})")
        for job in args.jobs:
            print(f"  {job}: ref={ARTIST_REFS[job].name}")
        return 0

    client = OpenAI()
    for job in args.jobs:
        ref = ARTIST_REFS.get(job)
        if not ref or not ref.exists():
            print(f"SKIP {job}: reference not found ({ref})")
            continue
        desc = JOB_DESC[job]
        prompt = f"{STYLE_PROMPT} Character: {desc}."

        print(f"[{job}] regenerating from {ref.name} (${unit:.3f}) ...")
        ref_bytes = load_reference(ref)
        img = call_gpt_image(client, prompt, ref_bytes, args.quality)
        # Save the raw 1024 for review
        raw_path = OUTPUT_DIR / f"{job}_1024_{args.quality}.png"
        img.save(raw_path)

        # Downscale + transparent bg
        portrait = downscale_to_portrait(img, 256)
        portrait = remove_flat_background(portrait)
        out_path = portraits_dir / f"{job}.png"
        portrait.save(out_path)
        print(f"  → {out_path} (raw at {raw_path})")

        total_cost += unit

    print(f"\nTotal spent: ${total_cost:.3f} on {len(args.jobs)} portraits")
    # Append to running log
    log_path = OUTPUT_DIR / "_cost.json"
    log = json.loads(log_path.read_text()) if log_path.exists() else {"sessions": [], "total": 0.0}
    log["sessions"].append({
        "quality": args.quality,
        "jobs": args.jobs,
        "cost": total_cost,
    })
    log["total"] = log.get("total", 0.0) + total_cost
    log_path.write_text(json.dumps(log, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
