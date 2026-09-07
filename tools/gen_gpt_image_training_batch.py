#!/usr/bin/env python3
"""
Batch-generate 200 artist-anchored training images using gpt-image-1.

For each of 4 jobs with artist references (fighter, rogue, cleric, mage),
generate 50 variations covering the full animation set. Uses the artist
sprite as style reference, so the resulting images are anchored to the
artist's actual style rather than generic "pixel art."

Resume-safe: skips any image where the output file already exists.
Cost tracking in tmp/gpt_image_batch/_cost.json.

Usage:
    uv run python tools/gen_gpt_image_training_batch.py
    uv run python tools/gen_gpt_image_training_batch.py --quality medium  # cheaper
    uv run python tools/gen_gpt_image_training_batch.py --jobs rogue  # just one job
    uv run python tools/gen_gpt_image_training_batch.py --num-per-job 10 --dry-run
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
OUTPUT_DIR = PROJECT / "tmp" / "gpt_image_batch"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

COST_PER_IMAGE = {"low": 0.011, "medium": 0.042, "high": 0.167}

ARTIST_REFS = {
    "fighter": PROJECT / "assets/sprites/jobs/fighter/idle.png",
    "rogue":   PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/ROGUE/Rogue Base sprite.png",
    "cleric":  PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/CLERIC/Cleric Main design-Sheet.png",
    "mage":    PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/MAGE/Mage IDLE.png",
}

# Per-job character description (reinforces identity alongside the reference image)
JOB_DESC = {
    "fighter": "a medieval warrior in red plate armor with brown hair and a broadsword",
    "rogue":   "a hooded rogue in dark navy leather with red accents and long brown hair",
    "cleric":  "a priestess in white and gold hooded robes with a golden star staff",
    "mage":    "a dark wizard mage in teal-navy robes, purple pointed hat with brim, golden flame staff, brown boots, flowing cape",
}

# Pose library — these build the variation prompts
POSES = [
    # Standard 9 animations
    "standing in a neutral idle battle stance",
    "taking a slight breath with weight shifted, idle breathing frame",
    "walking forward mid-stride, front view",
    "walking with left leg forward, side view mid-step",
    "walking with right leg forward, side view",
    "running full speed toward the viewer",
    "swinging weapon in an aggressive downward strike",
    "weapon windup over the shoulder, ready to attack",
    "mid-swing horizontal slash",
    "thrusting weapon forward with full extension",
    "recoiling backward after being hit, pained expression",
    "knocked sideways by a hit, staggering",
    "collapsed face-down on the ground, defeated",
    "kneeling with one knee down, low health",
    "channeling magic with one hand raised, energy gathering",
    "casting a spell with both hands forward and glowing energy",
    "chanting with eyes closed, preparing a spell",
    "defending with arm raised to block",
    "crouched defensive stance, bracing for impact",
    "holding up a potion bottle, about to drink",
    "reaching into a pouch for an item",
    "triumphant celebration pose, weapon raised overhead",
    "fist pump victory pose",
    "confident stance after battle, weapon sheathed",
    # Varied angles
    "three-quarter back view, looking forward",
    "three-quarter turning pose",
    "diagonal forward-leaning action shot",
    "crouched low pose, ready to spring",
    "jumping in the air with weapon ready",
    "landing from a jump, knees bent",
    "dashing forward with motion blur trail",
    "spinning attack, body in mid-rotation",
    "pointing weapon at the viewer",
    "turning to look over shoulder",
    # Job-specific / situational
    "taunting the enemy with a gesture",
    "cautious advance with weight on back foot",
    "aggressive advance with weight on front foot",
    "evasive sidestep pose",
    "falling backward mid-air",
    "stunned pose, seeing stars",
    "celebrating a level up, sparkles around body",
    "charging up an ultimate attack, glowing aura",
    "battle-ready stance at start of combat",
    "holding a glowing weapon with energy",
    "reaching forward to cast a healing spell",
    "summoning a magical effect, arms wide",
    "parrying an incoming strike",
    "dodging to one side, body leaning",
    "full-body portrait pose, facing forward",
    "action hero landing pose, one knee down",
]

BASE_PROMPT = (
    "A 16-bit JRPG pixel art battle sprite of {desc}, {pose}. "
    "Match the exact character design, color palette, proportions, and pixel art style "
    "of the reference image — same outfit, same face/hair, same weapons. "
    "Transparent background, isolated character sprite, hard pixel outlines, "
    "no anti-aliasing, no text, no sprite sheet, no multiple characters."
)


def prepare_reference(ref_path: Path) -> bytes:
    """Prepare an artist reference for the API — scale to 1024 via nearest-neighbor."""
    img = Image.open(ref_path).convert("RGBA")
    w, h = img.size
    target = 1024
    scale = min(target / w, target / h)
    new_w, new_h = max(1, int(w * scale)), max(1, int(h * scale))
    img = img.resize((new_w, new_h), Image.NEAREST)
    square = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    square.paste(img, ((target - new_w) // 2, (target - new_h) // 2), img)
    buf = io.BytesIO()
    square.save(buf, format="PNG")
    buf.seek(0)
    return buf.getvalue()


def call_gpt_image(client, prompt, ref_bytes, quality, max_retries=3):
    """Call gpt-image-1 with retry on rate limit."""
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
            elif "billing" in msg or "quota" in msg or "insufficient" in msg:
                raise  # fatal
            else:
                print(f"    Error: {e}; retry {attempt+1}/{max_retries}")
                time.sleep(5)
    raise RuntimeError(f"Failed after {max_retries} retries")


def load_cost_log():
    p = OUTPUT_DIR / "_cost.json"
    if p.exists():
        return json.loads(p.read_text())
    return {"total_cost_usd": 0.0, "total_images": 0, "sessions": []}


def save_cost_log(data):
    (OUTPUT_DIR / "_cost.json").write_text(json.dumps(data, indent=2))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs", nargs="+", default=list(ARTIST_REFS.keys()))
    parser.add_argument("--num-per-job", type=int, default=50)
    parser.add_argument("--quality", default="high", choices=["low", "medium", "high"])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--max-budget", type=float, default=40.0, help="Hard cap on spend in $")
    args = parser.parse_args()

    cost_per = COST_PER_IMAGE[args.quality]
    total_planned = sum(args.num_per_job for _ in args.jobs)
    est_cost = total_planned * cost_per

    print(f"{'='*60}")
    print(f"  gpt-image-1 batch: {len(args.jobs)} jobs × {args.num_per_job} images")
    print(f"  Quality: {args.quality}  (${cost_per}/image)")
    print(f"  Planned: {total_planned} images  Est: ${est_cost:.2f}")
    print(f"  Hard budget cap: ${args.max_budget}")
    print(f"{'='*60}\n")

    if args.dry_run:
        print("DRY RUN — exiting.")
        return

    if est_cost > args.max_budget:
        print(f"ERROR: est ${est_cost:.2f} exceeds budget ${args.max_budget}. Aborting.")
        sys.exit(1)

    if not os.environ.get("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not set.")
        sys.exit(1)

    client = OpenAI()
    cost_log = load_cost_log()
    session = {
        "started_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "quality": args.quality,
        "jobs": args.jobs,
        "num_per_job": args.num_per_job,
        "images_ok": 0,
        "images_skipped_existing": 0,
        "images_failed": 0,
        "cost_usd": 0.0,
    }

    for job in args.jobs:
        ref_path = ARTIST_REFS.get(job)
        if not ref_path or not ref_path.exists():
            print(f"SKIP {job}: no artist ref")
            continue

        job_dir = OUTPUT_DIR / job
        job_dir.mkdir(parents=True, exist_ok=True)

        print(f"\n--- {job.upper()} (ref: {ref_path.name}) ---")
        ref_bytes = prepare_reference(ref_path)

        desc = JOB_DESC[job]

        for i in range(args.num_per_job):
            # Check budget before each call
            # cost_log["total_cost_usd"] already includes session["cost_usd"] from prior increments
            if cost_log["total_cost_usd"] + cost_per > args.max_budget:
                print(f"  STOP: hard budget cap ${args.max_budget} would be exceeded.")
                session["halt_reason"] = "budget_cap"
                break

            pose = POSES[i % len(POSES)]
            out_path = job_dir / f"{job}_{i:03d}.png"

            if out_path.exists():
                session["images_skipped_existing"] += 1
                print(f"  [{i+1}/{args.num_per_job}] SKIP (exists): {out_path.name}")
                continue

            prompt = BASE_PROMPT.format(desc=desc, pose=pose)
            print(f"  [{i+1}/{args.num_per_job}] {pose[:55]}...")

            try:
                img = call_gpt_image(client, prompt, ref_bytes, args.quality)
                img.save(out_path)
                session["images_ok"] += 1
                session["cost_usd"] += cost_per
                cost_log["total_cost_usd"] += cost_per
                cost_log["total_images"] += 1
                # Flush cost log periodically
                if session["images_ok"] % 5 == 0:
                    save_cost_log(cost_log)
            except Exception as e:
                print(f"    FATAL: {e}")
                session["images_failed"] += 1
                if "billing" in str(e).lower() or "quota" in str(e).lower():
                    session["halt_reason"] = "billing"
                    break

        if session.get("halt_reason"):
            break

    cost_log["sessions"].append(session)
    save_cost_log(cost_log)

    print(f"\n{'='*60}")
    print(f"  DONE")
    print(f"  Generated:    {session['images_ok']}")
    print(f"  Skipped:      {session['images_skipped_existing']}")
    print(f"  Failed:       {session['images_failed']}")
    print(f"  Session cost: ${session['cost_usd']:.2f}")
    print(f"  Lifetime:     ${cost_log['total_cost_usd']:.2f}")
    print(f"  Output:       {OUTPUT_DIR}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
