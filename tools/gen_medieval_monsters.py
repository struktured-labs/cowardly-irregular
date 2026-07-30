#!/usr/bin/env python3
"""Generate battle sprites for medieval monsters missing from the game.

Each monster gets an 8-frame idle animation strip (2048x256).
Uses the artist-trained jrpg_pixel_style LoRA.

Usage:
    uv run python tools/gen_medieval_monsters.py
    uv run python tools/gen_medieval_monsters.py --monsters ice_wolf treasure_mimic
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.pipeline.config import FRAME_W, FRAME_H, PROJECT_DIR
from tools.pipeline.loader import load_pipeline
from tools.pipeline.prompts import build_monster_prompt, NEGATIVE_PROMPT
from tools.pipeline.postprocess import downscale_to_pixel_art, remove_background, center_character

MISSING_MEDIEVAL = [
    "fungoid", "viper", "elemental", "corrupted_sprite",
    "giant_bat", "diseased_rat", "cave_rat_king",
    "ice_wolf", "specter", "treasure_mimic",
    "ironback_beetle", "cursed_armor", "blood_wolf_alpha",
    "crystal_golem", "elder_mushroom", "corrupted_guardian",
    "masterite_warden_medieval", "masterite_arbiter_medieval",
    "masterite_tempo_medieval", "masterite_curator_medieval",
]

N_FRAMES = 8  # match existing monster sheets (2048x256)


def generate_monster_frame(pipe, monster_id, seed):
    prompt = build_monster_prompt(monster_id)
    generator = torch.Generator("cuda").manual_seed(seed)

    result = pipe(
        prompt=prompt,
        negative_prompt=NEGATIVE_PROMPT + ", humanoid, human, person, character, player",
        num_inference_steps=40,
        guidance_scale=9.0,
        width=768,
        height=768,
        generator=generator,
    ).images[0]

    small = downscale_to_pixel_art(result, target_size=FRAME_W, num_colors=128)
    transparent = remove_background(small)
    centered = center_character(transparent)
    return centered


def generate_monster_strip(pipe, monster_id, base_seed):
    frames = []
    for i in range(N_FRAMES):
        seed = base_seed + i
        print(f"  Frame {i}/{N_FRAMES} (seed={seed})...")
        frame = generate_monster_frame(pipe, monster_id, seed)
        frames.append(np.array(frame))

    strip = np.concatenate(frames, axis=1)
    return Image.fromarray(strip)


def main():
    parser = argparse.ArgumentParser(description="Generate medieval monster sprites")
    parser.add_argument("--monsters", nargs="+", default=None,
                        help="Specific monster IDs (default: all missing medieval)")
    parser.add_argument("--output", default="tmp/generated/monsters",
                        help="Output directory")
    parser.add_argument("--seed", type=int, default=42, help="Base seed")
    args = parser.parse_args()

    monsters = args.monsters or MISSING_MEDIEVAL
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Loading pipeline (style LoRA, no ControlNet, no IP-Adapter)...")
    pipe = load_pipeline(use_ipadapter=False, lora_mode="style", use_controlnet=False)

    all_seeds = {}
    for idx, monster_id in enumerate(monsters):
        base_seed = args.seed + idx * 100
        print(f"\n{'='*60}")
        print(f"Generating {monster_id} ({idx+1}/{len(monsters)})")
        print(f"{'='*60}")

        strip = generate_monster_strip(pipe, monster_id, base_seed)
        out_path = output_dir / f"{monster_id}.png"
        strip.save(out_path)
        print(f"  Saved: {out_path} ({strip.size[0]}x{strip.size[1]})")
        all_seeds[monster_id] = list(range(base_seed, base_seed + N_FRAMES))

    meta = {
        "tier": "T1",
        "generator": "gen_medieval_monsters.py",
        "lora_mode": "style",
        "frame_size": f"{FRAME_W}x{FRAME_H}",
        "frames_per_monster": N_FRAMES,
        "monsters": list(monsters),
        "seeds": all_seeds,
    }
    meta_path = output_dir / "generation_meta.json"
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"\nMetadata: {meta_path}")
    print(f"Generated {len(monsters)} monster sprites in {output_dir}")


if __name__ == "__main__":
    main()
