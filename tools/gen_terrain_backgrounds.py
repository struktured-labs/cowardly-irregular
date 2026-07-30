#!/usr/bin/env python3
"""
Generate per-terrain W1 battle backgrounds + shop/inn interiors.

Terrain backgrounds: 512x256 pixel art, same format as world backgrounds.
Interiors: 512x256 pixel art shop and inn scenes.

Usage:
    uv run python tools/gen_terrain_backgrounds.py
    uv run python tools/gen_terrain_backgrounds.py --install
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
OUTPUT_DIR = PROJECT / "tmp" / "generated" / "terrain_backgrounds"
GAME_BG = Path("/home/struktured/projects/cowardly-irregular/assets/sprites/backgrounds")

SCENES = {
    # W1 terrain sub-biomes
    "ice_battle": {
        "prompt": "wide JRPG battle background, frozen tundra landscape, snow-covered ground, icy blue glaciers, crystalline ice formations, aurora borealis in dark sky, snowflakes falling, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
    },
    "desert_battle": {
        "prompt": "wide JRPG battle background, vast sandy desert with rolling dunes, ancient ruins half-buried in sand, blazing orange sun, heat haze shimmer, scattered bones and dry brush, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
    },
    "swamp_battle": {
        "prompt": "wide JRPG battle background, murky dark swamp with twisted dead trees, glowing green toxic water, hanging moss and vines, fog rolling over marsh, eerie atmosphere, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
    },
    "coast_battle": {
        "prompt": "wide JRPG battle background, rocky ocean coastline, crashing waves against stone cliffs, sandy beach foreground, distant lighthouse, seagulls, sunset colors reflected in tide pools, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
    },
    "volcanic_battle": {
        "prompt": "wide JRPG battle background, volcanic hellscape, rivers of glowing orange lava flowing between black rock, erupting volcano in background, ash clouds, ember particles floating, red sky glow, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
    },
    "forest_battle": {
        "prompt": "wide JRPG battle background, deep enchanted forest, massive ancient oak trees with thick canopy, dappled sunlight filtering through leaves, mossy rocks, fern undergrowth, magical fireflies, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
    },
    # Interiors
    "shop_interior": {
        "prompt": "wide JRPG interior background, medieval item shop interior, wooden counter with potions and weapons displayed, shelves of goods, hanging lanterns, warm cozy lighting, wooden floor and walls, shopkeeper counter, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
    },
    "inn_interior": {
        "prompt": "wide JRPG interior background, cozy medieval inn common room, long wooden tables with mugs, roaring stone fireplace, candle chandelier, wooden stairs to upper floor, warm amber lighting, no characters, 16-bit SNES pixel art style, jrpg_pixel_style",
    },
}

NEGATIVE = "people, characters, creatures, monsters, warrior, ui, text, cursor, menu, blurry, photorealistic, 3D"

GEN_W, GEN_H = 1024, 512


def generate_scene(pipe, scene_id: str, seed: int = 42) -> Image.Image:
    prompt = SCENES[scene_id]["prompt"]
    gen = torch.Generator("cuda").manual_seed(seed)
    result = pipe(
        prompt=prompt,
        negative_prompt=NEGATIVE,
        num_inference_steps=35,
        guidance_scale=7.5,
        width=GEN_W,
        height=GEN_H,
        generator=gen,
        ip_adapter_image=Image.new("RGB", (GEN_W, GEN_H), (128, 128, 128)),
    ).images[0]
    return result.resize((512, 256), Image.LANCZOS)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--scenes", nargs="+", default=list(SCENES.keys()))
    args = parser.parse_args()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("Loading SDXL + v3.1 LoRA...")
    pipe = load_pipeline(use_ipadapter=True, lora_mode="style", use_controlnet=False)
    pipe.set_ip_adapter_scale(0.0)

    for scene_id in args.scenes:
        if scene_id not in SCENES:
            print(f"SKIP: unknown scene '{scene_id}'")
            continue
        print(f"\n  {scene_id}...")
        img = generate_scene(pipe, scene_id, args.seed)
        out = OUTPUT_DIR / f"{scene_id}.png"
        img.save(out)
        print(f"  Saved: {out}")

    if args.install:
        GAME_BG.mkdir(parents=True, exist_ok=True)
        for scene_id in args.scenes:
            src = OUTPUT_DIR / f"{scene_id}.png"
            if src.exists():
                shutil.copy2(src, GAME_BG / f"{scene_id}.png")
        print(f"\n  Installed to {GAME_BG}")


if __name__ == "__main__":
    main()
