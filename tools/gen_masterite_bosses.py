#!/usr/bin/env python3
"""Generate battle sprites for 18 Masterite bosses across worlds 2-6.

Each boss gets an 8-frame horizontal strip (2048x256) using IP-Adapter
identity lock (frame 0 free, frames 1-7 locked at 0.4).

Batches by world with appropriate LoRA modes:
  - W2 Suburban (4 bosses, lora=style, seed=5000)
  - W3 Steampunk/Industrial (4 bosses, lora=style, seed=6000)
  - W4 Futuristic (4 bosses, lora=none, seed=7000)
  - W5 Abstract (4 bosses, lora=none, seed=8000)

W6 is not included (no W6 masterites specified).

Usage:
    uv run python tools/gen_masterite_bosses.py
    uv run python tools/gen_masterite_bosses.py --batch suburban
    uv run python tools/gen_masterite_bosses.py --batch futuristic --seed 7000
    uv run python tools/gen_masterite_bosses.py --skip-cleanup
"""
import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import torch
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.pipeline.config import FRAME_W, FRAME_H, PROJECT_DIR
from tools.pipeline.loader import load_pipeline
from tools.pipeline.prompts import build_monster_prompt, NEGATIVE_PROMPT
from tools.pipeline.identity import compute_identity_embeddings
from tools.pipeline.postprocess import downscale_to_pixel_art, remove_background, center_character
from tools.pipeline.cleanup import cleanup_strip

# ── Batch definitions ───────────────────────────────────────────────────────
BATCHES = {
    "suburban": {
        "lora_mode": "style",
        "seed": 5000,
        "monsters": [
            "masterite_warden_suburban",
            "masterite_arbiter_suburban",
            "masterite_tempo_suburban",
            "masterite_curator_suburban",
        ],
    },
    "industrial": {
        "lora_mode": "style",
        "seed": 6000,
        "monsters": [
            "masterite_warden_industrial",
            "masterite_arbiter_industrial",
            "masterite_tempo_industrial",
            "masterite_curator_industrial",
        ],
    },
    "futuristic": {
        "lora_mode": "none",
        "seed": 7000,
        "monsters": [
            "masterite_warden_futuristic",
            "masterite_arbiter_futuristic",
            "masterite_tempo_futuristic",
            "masterite_curator_futuristic",
        ],
    },
    "abstract": {
        "lora_mode": "none",
        "seed": 8000,
        "monsters": [
            "masterite_warden_abstract",
            "masterite_arbiter_abstract",
            "masterite_tempo_abstract",
            "masterite_curator_abstract",
        ],
    },
}

MONSTER_NEGATIVE = (
    NEGATIVE_PROMPT +
    ", multiple characters, multiple views, sprite sheet, reference sheet, "
    "turnaround, model sheet, concept art, collage, grid, tiled"
)

# Humanoid bosses (suburban, some industrial) get a lighter humanoid penalty
HUMANOID_NEGATIVE = MONSTER_NEGATIVE
# Robotic/abstract bosses get the full monster negative
NONHUMAN_NEGATIVE = (
    MONSTER_NEGATIVE +
    ", humanoid, human, person, player character, warrior, knight"
)

# Which batches are humanoid (use lighter negative prompt)
HUMANOID_BATCHES = {"suburban"}

N_FRAMES = 8


def generate_single(pipe, prompt, negative, seed, identity_embeds=None, ip_scale=0.0):
    """Generate one 768x768 frame, downscale to 256x256."""
    pipe.set_ip_adapter_scale(ip_scale)

    gen = torch.Generator("cuda").manual_seed(seed)
    gen_kwargs = dict(
        prompt=prompt,
        negative_prompt=negative,
        num_inference_steps=40,
        guidance_scale=9.0,
        width=768, height=768,
        generator=gen,
    )
    if identity_embeds is not None:
        gen_kwargs["ip_adapter_image_embeds"] = identity_embeds
    else:
        # IP-Adapter requires an image even at scale 0.0 when loaded
        gen_kwargs["ip_adapter_image"] = Image.new("RGB", (768, 768), (128, 128, 128))

    result = pipe(**gen_kwargs).images[0]
    small = downscale_to_pixel_art(result, target_size=FRAME_W, num_colors=128)
    transparent = remove_background(small)
    centered = center_character(transparent)
    return result, centered


def generate_boss(pipe, monster_id, base_seed, negative):
    """Generate consistent boss strip using IP-Adapter identity lock."""
    prompt = build_monster_prompt(monster_id)
    print(f"  Prompt: {prompt[:100]}...")
    print(f"  Reference frame (seed={base_seed}, no identity lock)...")

    raw_ref, frame0 = generate_single(pipe, prompt, negative, base_seed, ip_scale=0.0)

    identity = compute_identity_embeddings(pipe, raw_ref)

    frames = [np.array(frame0)]
    for i in range(1, N_FRAMES):
        seed = base_seed + i
        print(f"  Frame {i}/{N_FRAMES} (seed={seed}, identity locked @ 0.4)...")
        _, frame = generate_single(pipe, prompt, negative, seed,
                                    identity_embeds=identity, ip_scale=0.4)
        frames.append(np.array(frame))

    strip = np.concatenate(frames, axis=1)
    return Image.fromarray(strip)


def run_batch(batch_name, batch_info, output_dir, skip_cleanup=False, seed_override=None):
    """Run a single batch: load pipeline, generate all monsters, cleanup."""
    lora_mode = batch_info["lora_mode"]
    base_seed = seed_override or batch_info["seed"]
    monsters = batch_info["monsters"]
    negative = HUMANOID_NEGATIVE if batch_name in HUMANOID_BATCHES else NONHUMAN_NEGATIVE

    print(f"\n{'#'*70}")
    print(f"# BATCH: {batch_name.upper()} ({len(monsters)} bosses)")
    print(f"# LoRA: {lora_mode}, Base seed: {base_seed}")
    print(f"{'#'*70}")

    print(f"\nLoading pipeline (lora={lora_mode}, IP-Adapter=ON)...")
    pipe = load_pipeline(use_ipadapter=True, lora_mode=lora_mode, use_controlnet=False)

    all_seeds = {}
    cleanup_reports = {}
    batch_start = time.time()

    for idx, mid in enumerate(monsters):
        monster_seed = base_seed + idx * 100
        print(f"\n{'='*60}")
        print(f"[{batch_name}] {mid} ({idx+1}/{len(monsters)})")
        print(f"{'='*60}")

        t0 = time.time()
        strip = generate_boss(pipe, mid, monster_seed, negative)
        gen_time = time.time() - t0
        print(f"  Generation time: {gen_time:.1f}s")

        # Save raw strip
        raw_path = output_dir / f"{mid}_raw.png"
        strip.save(raw_path)
        print(f"  Raw saved: {raw_path}")

        # Cleanup bad frames
        if not skip_cleanup:
            # Humanoid sprites fragment into many components (limbs, accessories)
            # Use higher threshold for humanoid batches to avoid false positives
            threshold = 8 if batch_name in HUMANOID_BATCHES else 5
            cleaned, report = cleanup_strip(strip, frame_w=FRAME_W, max_objects=threshold)
            if report:
                print(f"  Cleanup: fixed {len(report)} bad frame(s)")
                for r in report:
                    print(f"    Frame {r['bad_frame']}: {r['objects_found']} objects -> replaced with frame {r['replaced_with']}")
                cleanup_reports[mid] = report
            else:
                print(f"  Cleanup: all frames clean")
                cleaned = strip
        else:
            cleaned = strip

        out_path = output_dir / f"{mid}.png"
        cleaned.save(out_path)
        print(f"  Final saved: {out_path} ({cleaned.size[0]}x{cleaned.size[1]})")

        all_seeds[mid] = list(range(monster_seed, monster_seed + N_FRAMES))

    batch_time = time.time() - batch_start
    print(f"\n  Batch '{batch_name}' done in {batch_time:.1f}s ({batch_time/60:.1f}m)")

    # Free GPU memory before next batch
    del pipe
    torch.cuda.empty_cache()

    return all_seeds, cleanup_reports


def main():
    parser = argparse.ArgumentParser(description="Generate Masterite boss sprites (W2-W6)")
    parser.add_argument("--batch", nargs="*", default=None,
                        choices=list(BATCHES.keys()),
                        help="Specific batches to run (default: all)")
    parser.add_argument("--output", default="tmp/generated/masterites_v2",
                        help="Output directory")
    parser.add_argument("--seed", type=int, default=None,
                        help="Override base seed for all batches")
    parser.add_argument("--skip-cleanup", action="store_true",
                        help="Skip bad-frame cleanup pass")
    args = parser.parse_args()

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    batches_to_run = args.batch if args.batch else list(BATCHES.keys())

    total_monsters = sum(len(BATCHES[b]["monsters"]) for b in batches_to_run)
    print(f"Generating {total_monsters} Masterite bosses across {len(batches_to_run)} batch(es)")
    print(f"Output: {output_dir}")

    all_meta = {
        "tier": "T1",
        "generator": "gen_masterite_bosses.py",
        "ip_adapter": True,
        "method": "frame0 free, frames 1-7 identity-locked at 0.4",
        "frame_size": f"{FRAME_W}x{FRAME_H}",
        "frames_per_boss": N_FRAMES,
        "generated_at": datetime.now().isoformat(),
        "batches": {},
        "seeds": {},
        "cleanup": {},
    }

    total_start = time.time()

    for batch_name in batches_to_run:
        batch_info = BATCHES[batch_name]
        seed_override = args.seed + list(BATCHES.keys()).index(batch_name) * 1000 if args.seed else None

        seeds, cleanup = run_batch(
            batch_name, batch_info, output_dir,
            skip_cleanup=args.skip_cleanup,
            seed_override=seed_override,
        )

        all_meta["batches"][batch_name] = {
            "lora_mode": batch_info["lora_mode"],
            "base_seed": seed_override or batch_info["seed"],
            "monsters": batch_info["monsters"],
        }
        all_meta["seeds"].update(seeds)
        if cleanup:
            all_meta["cleanup"].update(cleanup)

    total_time = time.time() - total_start

    all_meta["total_time_seconds"] = round(total_time, 1)
    meta_path = output_dir / "generation_meta.json"
    with open(meta_path, "w") as f:
        json.dump(all_meta, f, indent=2)

    print(f"\n{'='*70}")
    print(f"ALL DONE: {total_monsters} bosses in {total_time:.1f}s ({total_time/60:.1f}m)")
    print(f"Metadata: {meta_path}")
    print(f"Output:   {output_dir}")
    if all_meta["cleanup"]:
        n_fixed = sum(len(v) for v in all_meta["cleanup"].values())
        print(f"Cleanup:  {n_fixed} bad frame(s) fixed across {len(all_meta['cleanup'])} boss(es)")
    print(f"{'='*70}")


if __name__ == "__main__":
    main()
