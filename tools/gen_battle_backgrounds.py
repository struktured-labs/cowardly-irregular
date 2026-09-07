#!/usr/bin/env python3
"""
Generate battle backgrounds for all 6 worlds.

SDXL + v2 jrpg_pixel_style LoRA, no IP-Adapter (no character), no ControlNet.
Output: 512x256 pixel art battle scene backgrounds.

World mapping:
  W1 medieval  - grassy plains, distant mountains
  W2 suburban  - tree-lined residential street, mailboxes
  W3 steampunk - factory interior with pipes and gears
  W4 industrial - warehouse floor, hazard stripes
  W5 digital   - wireframe cyberspace, flying code
  W6 abstract  - void with geometric shapes, minimalist
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

import torch
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.pipeline.loader import load_pipeline

PROJECT = Path(__file__).parent.parent
OUTPUT_DIR = PROJECT / "tmp" / "generated" / "battle_backgrounds"
GAME_BACKGROUNDS = Path("/home/struktured/projects/cowardly-irregular/assets/sprites/backgrounds")

WORLDS = {
    "world1_medieval": {
        "prompt": "wide JRPG battle background, medieval fantasy grassy plains with distant snow-capped mountains, green meadow foreground with flowers, scattered rocks, dawn sky with pink clouds, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
        "negative": "people, characters, creatures, monsters, warrior, soldier, party, ui, text, cursor, menu",
    },
    "world2_suburban": {
        "prompt": "wide JRPG battle background, quiet suburban residential street at dusk, manicured front lawns, white picket fences, mailboxes, leafy maple trees lining sidewalk, orange warm sunset sky, empty street, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
        "negative": "people, characters, creatures, monsters, warrior, pedestrian, dog, cat, ui, text, cursor, menu",
    },
    "world3_steampunk": {
        "prompt": "wide JRPG battle background, vast steampunk factory interior, brass pipes and rotating gears, steam venting from valves, gold and copper machinery, industrial cathedral ceiling, amber oil lamps glowing, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
        "negative": "people, characters, creatures, monsters, worker, robot, ui, text, cursor, menu",
    },
    "world4_industrial": {
        "prompt": "wide JRPG battle background, concrete warehouse floor with yellow hazard stripes, red industrial lockers and forklift silhouette, metal grating, exposed steel rafters with hanging chains, flickering fluorescent lights, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
        "negative": "people, characters, creatures, monsters, worker, robot, ui, text, cursor, menu",
    },
    "world5_digital": {
        "prompt": "wide JRPG battle background, cyberspace grid, neon magenta and cyan wireframe geometry, floating binary code fragments, receding digital horizon, scanlines, dark void between grid lines, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
        "negative": "people, characters, creatures, monsters, avatar, ui, text labels, cursor, menu",
    },
    "world6_abstract": {
        "prompt": "wide JRPG battle background, minimalist void space with floating geometric platonic solids, pure black and white, single red accent shape, dream-like abstract staging, mathematical emptiness, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
        "negative": "people, characters, creatures, monsters, avatar, ui, text, cursor, menu",
    },
}

GEN_W, GEN_H = 1024, 512  # 2:1 aspect, will downscale to 512x256


def generate_background(pipe, world_id: str, seed: int = 42):
    """Generate one battle background at 1024x512, downscale to 512x256."""
    info = WORLDS[world_id]
    prompt = info["prompt"]
    negative = info["negative"]

    gen = torch.Generator("cuda").manual_seed(seed)
    result = pipe(
        prompt=prompt,
        negative_prompt=negative,
        num_inference_steps=35,
        guidance_scale=7.5,
        width=GEN_W,
        height=GEN_H,
        generator=gen,
        ip_adapter_image=Image.new("RGB", (GEN_W, GEN_H), (128, 128, 128)),
    ).images[0]

    # Downscale to 512x256 for pixel-art crispness
    small = result.resize((512, 256), Image.LANCZOS)
    return result, small


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--worlds", nargs="+", default=list(WORLDS.keys()))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--install", action="store_true", help="Copy to game repo")
    args = parser.parse_args()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("Loading SDXL + v2 LoRA pipeline (no IP-Adapter, no ControlNet)...")
    # Must load with IP-Adapter since pipe requires it due to UNet config,
    # but we pass dummy gray image
    pipe = load_pipeline(use_ipadapter=True, lora_mode="style", use_controlnet=False)
    pipe.set_ip_adapter_scale(0.0)  # disable IP-Adapter influence

    for world_id in args.worlds:
        if world_id not in WORLDS:
            print(f"SKIP: unknown world '{world_id}'")
            continue

        print(f"\n{'='*60}\n  {world_id.upper()}\n{'='*60}")
        raw, small = generate_background(pipe, world_id, args.seed)

        raw_path = OUTPUT_DIR / f"{world_id}_raw.png"
        out_path = OUTPUT_DIR / f"{world_id}.png"
        raw.save(raw_path)
        small.save(out_path)
        print(f"  Saved: {out_path} ({small.size[0]}x{small.size[1]})")

    meta = {
        "tier": "T1",
        "generator": "gen_battle_backgrounds.py (v2 jrpg_pixel_style LoRA)",
        "size": "512x256",
        "worlds": args.worlds,
    }
    (OUTPUT_DIR / "generation_meta.json").write_text(json.dumps(meta, indent=2))

    if args.install:
        GAME_BACKGROUNDS.mkdir(parents=True, exist_ok=True)
        for world_id in args.worlds:
            src = OUTPUT_DIR / f"{world_id}.png"
            if src.exists():
                dest = GAME_BACKGROUNDS / f"battle_{world_id}.png"
                shutil.copy2(src, dest)
                print(f"  Installed: {dest}")
        print(f"\n  All backgrounds installed to {GAME_BACKGROUNDS}")


if __name__ == "__main__":
    main()
