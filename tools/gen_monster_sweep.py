#!/usr/bin/env python3
"""
Regenerate all monster battle sprites using v2 jrpg_pixel_style LoRA.

Generates 2048x256 horizontal strips (8 frames of 256x256) for each monster,
matching the format expected by HybridSpriteLoader.

Usage:
    uv run python tools/gen_monster_sweep.py
    uv run python tools/gen_monster_sweep.py --resume           # skip existing
    uv run python tools/gen_monster_sweep.py --monster slime    # single monster
    uv run python tools/gen_monster_sweep.py --install          # copy to game repo
"""

import argparse
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

import torch
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.pipeline.config import OUTPUT_DIR, FRAME_W, FRAME_H
from tools.pipeline.prompts import MONSTER_PROMPTS, build_monster_prompt, NEGATIVE_PROMPT
from tools.pipeline.loader import load_pipeline

PROJECT = Path(__file__).parent.parent
OUTPUT_BASE = PROJECT / "tmp" / "monster_sweep_v2"
GAME_REPO = Path("/home/struktured/projects/cowardly-irregular")
GAME_MONSTERS = GAME_REPO / "assets" / "sprites" / "monsters"

# Monster strip format: 8 frames of 256x256 in a horizontal strip (2048x256)
N_FRAMES = 8
GEN_SIZE = 768  # generate at 768x768, downscale to 256x256


def generate_monster_strip(pipe, monster_id: str, seed: int = 42) -> Image.Image:
    """Generate a horizontal strip of monster frames."""
    prompt = build_monster_prompt(monster_id)
    negative = NEGATIVE_PROMPT

    frames = []
    for i in range(N_FRAMES):
        frame_seed = seed + i * 100
        gen = torch.Generator("cuda").manual_seed(frame_seed)

        result = pipe(
            prompt=prompt,
            negative_prompt=negative,
            num_inference_steps=30,
            guidance_scale=8.0,
            width=GEN_SIZE,
            height=GEN_SIZE,
            generator=gen,
        )
        img = result.images[0]

        # Downscale to 256x256
        img = img.resize((FRAME_W, FRAME_H), Image.LANCZOS)
        frames.append(img)

    # Assemble horizontal strip
    strip = Image.new("RGBA", (FRAME_W * N_FRAMES, FRAME_H), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        frame = frame.convert("RGBA")
        strip.paste(frame, (i * FRAME_W, 0))

    return strip


def install_to_game(output_dir: Path):
    """Copy generated monster sprites to game repo and update manifest."""
    manifest_path = GAME_REPO / "data" / "sprite_manifest.json"

    with open(manifest_path) as f:
        manifest = json.load(f)

    monster_sheets = manifest.setdefault("monster_sheets", {})
    installed = 0

    for png in sorted(output_dir.glob("*.png")):
        monster_id = png.stem
        if monster_id == "sweep_results":
            continue

        dest = GAME_MONSTERS / png.name
        shutil.copy2(png, dest)
        installed += 1

        # Update manifest entry
        monster_sheets[monster_id] = {
            "path": f"res://assets/sprites/monsters/{monster_id}.png",
            "frame_width": 256,
            "frame_height": 256,
            "fps": 8,
            "animations": {
                "idle": {"start": 0, "end": 1},
                "attack": {"start": 2, "end": 3},
                "hit": {"start": 4, "end": 5},
                "dead": {"start": 6, "end": 7},
            },
            "tier": "T1",
            "generator": "gen_monster_sweep.py (v2 jrpg_pixel_style LoRA)",
        }

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"\n  Installed {installed} monster sprites to {GAME_MONSTERS}")
    print(f"  Manifest updated: {manifest_path}")


def main():
    parser = argparse.ArgumentParser(description="Monster sprite sweep with v2 LoRA")
    parser.add_argument("--monster", help="Generate a single monster")
    parser.add_argument("--resume", action="store_true", help="Skip already-generated")
    parser.add_argument("--install", action="store_true", help="Copy to game repo after")
    parser.add_argument("--seed", type=int, default=42, help="Base seed")
    args = parser.parse_args()

    OUTPUT_BASE.mkdir(parents=True, exist_ok=True)

    # Select monsters to generate
    if args.monster:
        monsters = [args.monster]
    else:
        monsters = list(MONSTER_PROMPTS.keys())

    print(f"{'#'*60}")
    print(f"  MONSTER SWEEP — {len(monsters)} monsters")
    print(f"  LoRA: jrpg_pixel_style v2")
    print(f"  Output: {OUTPUT_BASE}")
    print(f"{'#'*60}")

    # Load pipeline once
    print("\nLoading pipeline...")
    pipe = load_pipeline(
        use_ipadapter=False,
        lora_mode="style",
        use_controlnet=False,
    )

    start = datetime.now()
    results = {}

    for i, monster_id in enumerate(monsters):
        out_path = OUTPUT_BASE / f"{monster_id}.png"

        if args.resume and out_path.exists():
            print(f"  [{i+1}/{len(monsters)}] {monster_id}: SKIP (exists)")
            results[monster_id] = "skipped"
            continue

        print(f"\n  [{i+1}/{len(monsters)}] {monster_id}...")
        try:
            strip = generate_monster_strip(pipe, monster_id, seed=args.seed)
            strip.save(out_path)
            print(f"    Saved: {out_path} ({strip.size[0]}x{strip.size[1]})")
            results[monster_id] = "ok"
        except Exception as e:
            print(f"    ERROR: {e}")
            results[monster_id] = f"error: {e}"

    elapsed = datetime.now() - start

    # Save results
    meta = {
        "start": str(start),
        "elapsed": str(elapsed),
        "results": results,
        "ok": sum(1 for v in results.values() if v == "ok"),
        "total": len(results),
    }
    with open(OUTPUT_BASE / "sweep_results.json", "w") as f:
        json.dump(meta, f, indent=2)

    print(f"\n{'='*60}")
    print(f"  MONSTER SWEEP COMPLETE")
    print(f"  OK: {meta['ok']}/{meta['total']}")
    print(f"  Time: {elapsed}")
    print(f"{'='*60}")

    if args.install:
        install_to_game(OUTPUT_BASE)


if __name__ == "__main__":
    main()
