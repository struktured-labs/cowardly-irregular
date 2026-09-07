#!/usr/bin/env python3
"""
Generate massive LoRA training dataset using the PixelLab animate-with-text API.

Generates hundreds of consistent JRPG pixel art battle sprites across three character
classes (rogue, mage, cleric), 18 actions each, with varied seeds and guidance scales.

Output: tools/lora_training/style_dataset/15_pixellab/
  - {job}_{action}_{seed}_f{frame}.png  — individual 64x64 RGBA frames
  - {job}_{action}_{seed}_f{frame}.txt  — caption text for LoRA training

Budget: ~$2.00 max (hard stop at $1.95)

Usage:
    uv run python tools/gen_pixellab_training_data.py
    uv run python tools/gen_pixellab_training_data.py --dry-run
    uv run python tools/gen_pixellab_training_data.py --jobs rogue mage
    uv run python tools/gen_pixellab_training_data.py --resume
"""

import argparse
import base64
import io
import json
import os
import sys
import time
from pathlib import Path
from typing import Optional

import httpx
from PIL import Image

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = PROJECT_ROOT / "tools/lora_training/style_dataset/15_pixellab"
PROGRESS_FILE = OUTPUT_DIR / "_progress.json"

REFERENCE_IMAGES = {
    "rogue": PROJECT_ROOT / "assets/sprites/drive_archive/Game graphics - Characters/ROGUE/Rogue Base sprite.png",
    "mage": PROJECT_ROOT / "tmp/mage_artist/mage_design.png",
    "cleric": PROJECT_ROOT / "assets/sprites/drive_archive/Game graphics - Characters/CLERIC/Cleric Main design-Sheet.png",
}

# ---------------------------------------------------------------------------
# Generation plan
# ---------------------------------------------------------------------------
ACTIONS = [
    "idle",
    "walk",
    "attack",
    "cast",
    "defend",
    "hit",
    "dead",
    "item",
    "victory",
    "run",
    "jump",
    "dodge",
    "block",
    "channel",
    "taunt",
    "kneel",
    "pray",
    "charge",
]

# Per-job description prefixes to vary the style slightly
JOB_DESCRIPTIONS = {
    "rogue": [
        "jrpg_pixel_style, pixel art battle sprite, rogue thief character with hooded cloak and dagger, {action} pose, side view, SNES 16-bit style, black outline",
        "jrpg_pixel_style, pixel art RPG sprite, sneaky rogue assassin character in dark leather armor, {action} animation frame, side-scrolling view, 16-bit pixel art",
        "jrpg_pixel_style, SNES-era pixel art, rogue character with knife and dark hood, {action} battle stance, classic JRPG side view",
    ],
    "mage": [
        "jrpg_pixel_style, pixel art battle sprite, mage wizard character in blue robes with staff, {action} pose, side view, SNES 16-bit style, black outline",
        "jrpg_pixel_style, pixel art RPG sprite, spellcaster black mage in pointed hat, {action} animation frame, side-scrolling view, 16-bit pixel art",
        "jrpg_pixel_style, SNES-era pixel art, mage character with glowing magic orb, {action} battle stance, classic JRPG side view",
    ],
    "cleric": [
        "jrpg_pixel_style, pixel art battle sprite, cleric healer character in white robes with holy symbol, {action} pose, side view, SNES 16-bit style, black outline",
        "jrpg_pixel_style, pixel art RPG sprite, white mage cleric with healing staff, {action} animation frame, side-scrolling view, 16-bit pixel art",
        "jrpg_pixel_style, SNES-era pixel art, cleric character in armor with mace, {action} battle stance, classic JRPG side view",
    ],
}

# Seeds to cycle through per (job, action) combination
# Using higher seeds to avoid potential API queueing contention on low seeds
SEEDS_PER_COMBO = [42, 777]  # 2 seeds = 108 total calls, ~$1.73

# image_guidance_scale values to cycle through (keeps visual identity close to reference)
GUIDANCE_SCALES = [2.0, 1.8]  # one per seed

# Frames per call — always 4 to maximize output per dollar
N_FRAMES = 4

# Hard spend limit
BUDGET_USD = 1.95

# PixelLab API
API_BASE = "https://api.pixellab.ai/v1"
API_TIMEOUT = 150  # seconds per attempt — balance between waiting and giving up
API_MAX_RETRIES = 2  # 1 initial + 1 retry = 300s max per call (vs 540s with 3 retries)
API_RETRY_WAIT = 3  # seconds between retries


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_reference_image(job: str) -> str:
    """Load and resize reference image to 64x64, return as base64 PNG string."""
    path = REFERENCE_IMAGES[job]
    img = Image.open(path).convert("RGBA")

    # For cleric sheet: use only the first 128x128 frame
    if job == "cleric":
        img = img.crop((0, 0, 128, 128))

    img = img.resize((64, 64), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def build_caption(job: str, action: str) -> str:
    """Build LoRA training caption for a frame."""
    return (
        f"jrpg_pixel_style, pixel art battle sprite, {job} character, "
        f"{action} pose, side view, SNES 16-bit style, black outline"
    )


def load_progress() -> dict:
    """Load completed/skipped job tracking from disk."""
    if PROGRESS_FILE.exists():
        with open(PROGRESS_FILE) as f:
            data = json.load(f)
        # Ensure skipped key exists for older progress files
        data.setdefault("skipped", [])
        return data
    return {"completed": [], "skipped": [], "total_spent_usd": 0.0, "frame_count": 0}


def save_progress(progress: dict) -> None:
    with open(PROGRESS_FILE, "w") as f:
        json.dump(progress, f, indent=2)


def call_key(job: str, action: str, seed: int) -> str:
    return f"{job}__{action}__{seed}"


def count_existing_frames() -> int:
    return len(list(OUTPUT_DIR.glob("*.png")))


# ---------------------------------------------------------------------------
# API call
# ---------------------------------------------------------------------------

def generate_frames(
    client: httpx.Client,
    api_key: str,
    job: str,
    action: str,
    description: str,
    ref_b64: str,
    seed: int,
    guidance_scale: float,
    dry_run: bool = False,
) -> Optional[list[Image.Image]]:
    """Call animate-with-text, return list of PIL Images or None on error."""

    payload = {
        "image_size": {"width": 64, "height": 64},
        "description": description,
        "action": action,
        "reference_image": {"base64": ref_b64},
        "n_frames": N_FRAMES,
        "seed": seed,
        "image_guidance_scale": guidance_scale,
    }

    if dry_run:
        print(f"  [DRY-RUN] Would POST to {API_BASE}/animate-with-text")
        print(f"    action={action!r} seed={seed} guidance={guidance_scale}")
        return None

    last_error = None
    for attempt in range(1, API_MAX_RETRIES + 1):
        try:
            resp = client.post(
                f"{API_BASE}/animate-with-text",
                json=payload,
                headers={"Authorization": f"Bearer {api_key}"},
                timeout=API_TIMEOUT,
            )
            last_error = None
            break
        except httpx.TimeoutException as e:
            last_error = f"TIMEOUT (attempt {attempt}/{API_MAX_RETRIES})"
            print(f"\n  [{last_error}]", end=" ", flush=True)
            if attempt < API_MAX_RETRIES:
                time.sleep(API_RETRY_WAIT)
        except httpx.RequestError as e:
            last_error = f"NET ERROR: {e}"
            print(f"\n  [{last_error}]", end=" ", flush=True)
            if attempt < API_MAX_RETRIES:
                time.sleep(API_RETRY_WAIT)

    if last_error:
        print(f"\n  [FAILED after {API_MAX_RETRIES} retries: {last_error}] {job}/{action}/seed={seed} — skipping")
        return None

    if not resp.is_success:
        print(f"  [HTTP {resp.status_code}] {job}/{action}/seed={seed}: {resp.text[:200]}")
        return None

    data = resp.json()
    spent = data.get("usage", {}).get("usd", 0.0)
    images_raw = data.get("images", [])

    frames = []
    for img_item in images_raw:
        raw_bytes = base64.b64decode(img_item["base64"])
        frames.append(Image.open(io.BytesIO(raw_bytes)).convert("RGBA"))

    return frames, spent


# ---------------------------------------------------------------------------
# Main generation loop
# ---------------------------------------------------------------------------

def run_generation(
    jobs: list[str],
    resume: bool,
    dry_run: bool,
    retry_failed: bool = False,
) -> None:
    api_key = os.environ.get("PIXELLAB_API_KEY", "")
    if not api_key:
        print("ERROR: PIXELLAB_API_KEY not set. Run: source setenv.sh")
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    if resume or retry_failed:
        progress = load_progress()
    else:
        progress = {"completed": [], "skipped": [], "total_spent_usd": 0.0, "frame_count": 0}

    # Pre-load all reference images
    print("Loading reference images...")
    refs = {}
    for job in jobs:
        refs[job] = load_reference_image(job)
        print(f"  {job}: loaded {REFERENCE_IMAGES[job].name}")

    # Build full generation plan
    plan = []
    for job in jobs:
        descs = JOB_DESCRIPTIONS[job]
        for action in ACTIONS:
            for i, seed in enumerate(SEEDS_PER_COMBO):
                guidance = GUIDANCE_SCALES[i % len(GUIDANCE_SCALES)]
                desc = descs[i % len(descs)].format(action=action)
                plan.append((job, action, seed, guidance, desc))

    total_planned = len(plan)
    already_done = set(progress["completed"])
    already_skipped = set(progress.get("skipped", []))

    if retry_failed:
        # Only retry previously skipped calls
        remaining = [p for p in plan if call_key(p[0], p[1], p[2]) in already_skipped]
        # Remove them from skipped so they get a fresh attempt
        progress["skipped"] = [k for k in progress["skipped"] if k not in {call_key(p[0], p[1], p[2]) for p in remaining}]
        print(f"  Retrying {len(remaining)} previously skipped calls")
    else:
        # Normal run: skip completed AND skipped (skipped get retried via --retry-failed)
        remaining = [p for p in plan if call_key(p[0], p[1], p[2]) not in already_done and call_key(p[0], p[1], p[2]) not in already_skipped]

    print(f"\nGeneration plan:")
    print(f"  Jobs: {jobs}")
    print(f"  Actions per job: {len(ACTIONS)}")
    print(f"  Seeds per combo: {SEEDS_PER_COMBO}")
    print(f"  Total calls planned: {total_planned}")
    print(f"  Already completed: {len(already_done)}")
    print(f"  Previously skipped (timed out): {len(already_skipped)}")
    print(f"  Remaining calls: {len(remaining)}")
    print(f"  Frames per call: {N_FRAMES}")
    print(f"  Estimated frames: {len(remaining) * N_FRAMES}")
    print(f"  Estimated cost: ${len(remaining) * 0.016:.2f} (rough estimate)")
    print(f"  Budget limit: ${BUDGET_USD:.2f}")
    print(f"  Current spend so far: ${progress['total_spent_usd']:.4f}")
    print()

    if dry_run:
        print("[DRY-RUN MODE] No API calls will be made.\n")
        for job, action, seed, guidance, desc in remaining[:5]:
            print(f"  Would generate: {job}/{action}/seed={seed} guidance={guidance}")
            print(f"    desc: {desc[:80]}...")
        if len(remaining) > 5:
            print(f"  ... and {len(remaining) - 5} more")
        return

    # Estimate if this will exceed budget
    remaining_budget = BUDGET_USD - progress["total_spent_usd"]
    estimated_cost = len(remaining) * 0.016
    if estimated_cost > remaining_budget:
        affordable = int(remaining_budget / 0.016)
        print(f"WARNING: Estimated cost ${estimated_cost:.2f} exceeds remaining budget ${remaining_budget:.2f}")
        print(f"  Will generate up to {affordable} calls ({affordable * N_FRAMES} frames)")
        remaining = remaining[:affordable]
        print()

    completed_this_run = 0
    frames_this_run = 0
    spent_this_run = 0.0

    with httpx.Client(timeout=httpx.Timeout(connect=30, read=API_TIMEOUT, write=60, pool=10)) as client:
        for idx, (job, action, seed, guidance, desc) in enumerate(remaining, 1):
            key = call_key(job, action, seed)
            prefix = f"[{idx}/{len(remaining)}]"

            # Budget guard
            if progress["total_spent_usd"] + spent_this_run >= BUDGET_USD:
                print(f"{prefix} Budget limit reached. Stopping.")
                break

            print(f"{prefix} {job}/{action} seed={seed} guidance={guidance:.1f} ...", end=" ", flush=True)

            result = generate_frames(
                client, api_key, job, action, desc, refs[job], seed, guidance, dry_run
            )

            if result is None:
                print("SKIPPED (recording for --retry-failed)")
                progress["skipped"].append(key)
                save_progress(progress)
                time.sleep(1)
                continue

            frames, call_cost = result
            spent_this_run += call_cost
            frames_this_run += len(frames)
            completed_this_run += 1

            # Save frames
            caption = build_caption(job, action)
            for fi, frame in enumerate(frames):
                stem = f"{job}_{action}_{seed}_f{fi}"
                png_path = OUTPUT_DIR / f"{stem}.png"
                txt_path = OUTPUT_DIR / f"{stem}.txt"
                frame.save(png_path)
                txt_path.write_text(caption)

            print(f"OK ({len(frames)} frames, ${call_cost:.4f})")

            # Update progress
            progress["completed"].append(key)
            progress["total_spent_usd"] += call_cost
            progress["frame_count"] += len(frames)
            save_progress(progress)

            # Brief rate-limit pause every 10 calls
            if completed_this_run % 10 == 0:
                time.sleep(0.5)

    # Final summary
    total_frames = count_existing_frames()
    skipped_total = len(progress.get("skipped", []))
    print()
    print("=" * 60)
    print("Generation complete!")
    print(f"  Calls this run: {completed_this_run}")
    print(f"  Frames this run: {frames_this_run}")
    print(f"  Spent this run: ${spent_this_run:.4f}")
    print(f"  Total dataset frames: {total_frames}")
    print(f"  Total spent (all runs): ${progress['total_spent_usd']:.4f}")
    print(f"  Skipped/failed calls: {skipped_total} (run with --retry-failed to retry)")
    print(f"  Output: {OUTPUT_DIR}")
    print("=" * 60)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Generate PixelLab training dataset for JRPG sprite LoRA",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--jobs",
        nargs="+",
        default=["rogue", "mage", "cleric"],
        choices=["rogue", "mage", "cleric"],
        help="Which jobs to generate (default: all three)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be generated without making API calls",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume from previous progress (skip already-completed calls)",
    )
    parser.add_argument(
        "--actions",
        nargs="+",
        help="Override action list (default: all 18 actions)",
    )
    parser.add_argument(
        "--retry-failed",
        action="store_true",
        help="Retry only previously skipped/timed-out calls",
    )

    args = parser.parse_args()

    if args.actions:
        global ACTIONS
        ACTIONS = args.actions

    run_generation(
        jobs=args.jobs,
        resume=args.resume,
        dry_run=args.dry_run,
        retry_failed=args.retry_failed,
    )


if __name__ == "__main__":
    main()
