#!/usr/bin/env python3
"""Generate JRPG-style character portraits for menu/battle UI.

Generates close-up face/bust portraits at 256x256, suitable for
downscaling to 32/48/64/96px in-game.

Usage:
    uv run python tools/gen_portraits.py
    uv run python tools/gen_portraits.py --jobs fighter cleric
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))
from tools.pipeline.config import FRAME_W, FRAME_H
from tools.pipeline.loader import load_pipeline
from tools.pipeline.identity import compute_identity_embeddings
from tools.pipeline.postprocess import downscale_to_pixel_art, remove_background

PORTRAIT_PROMPTS = {
    "fighter": {
        "prompt": "pixel art JRPG character portrait, close-up face and shoulders, young male warrior, brown spiky hair, determined blue eyes, red plate armor collar, strong jaw, battle-ready expression",
        "negative": "full body, legs, weapon, sword, shield, background scenery",
        "palette": "warm reds, steel gray armor, brown hair, fair skin, blue eyes",
    },
    "cleric": {
        "prompt": "pixel art JRPG character portrait, close-up face and shoulders, young priestess girl, silver-white braided hair, gentle kind eyes, white hooded robes, golden tiara headpiece, soft warm expression",
        "negative": "full body, legs, staff, weapon, background scenery",
        "palette": "white robes, soft pink, pale gold tiara, silver hair, warm skin",
    },
    "mage": {
        "prompt": "pixel art JRPG character portrait, close-up face and shoulders, mysterious male mage, dark shadowed face under tall blue pointed wizard hat, glowing cyan eyes, blue robes collar, arcane aura",
        "negative": "full body, legs, staff, weapon, background scenery",
        "palette": "deep blue hat and robes, cyan glowing eyes, dark shadows, silver trim",
    },
    "rogue": {
        "prompt": "pixel art JRPG character portrait, close-up face and shoulders, mysterious hooded figure, face hidden by deep hood and wrapped scarf, only sharp eyes visible in shadow, dark leather collar",
        "negative": "full body, legs, weapon, dagger, background scenery, clearly male, clearly female",
        "palette": "dark navy hood, dusty purple scarf, shadowed face, sharp amber eyes",
    },
    "bard": {
        "prompt": "pixel art JRPG character portrait, close-up face and shoulders, charming young female bard, tilted feathered beret with red feather, warm smile, gold-olive doublet collar, bright observant eyes",
        "negative": "full body, legs, instrument, lute, weapon, background scenery",
        "palette": "gold-olive doublet, red feather, warm brown hair, bright hazel eyes",
    },
}

NEGATIVE_BASE = (
    "multiple characters, sprite sheet, reference sheet, full body shot, "
    "blurry, photorealistic, 3D, text, watermark, deformed, "
    "background scenery, landscape, room"
)


def generate_portrait(pipe, job_id, seed, identity_embeds=None):
    """Generate a single portrait at 768x768, downscale to 256x256."""
    info = PORTRAIT_PROMPTS[job_id]
    prompt = f"{info['prompt']}, jrpg_pixel_style, 16-bit SNES style, {info['palette']}, black pixel outline"
    negative = f"{NEGATIVE_BASE}, {info['negative']}"

    pipe.set_ip_adapter_scale(0.4 if identity_embeds else 0.0)
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
        gen_kwargs["ip_adapter_image"] = Image.new("RGB", (768, 768), (128, 128, 128))

    result = pipe(**gen_kwargs).images[0]
    small = downscale_to_pixel_art(result, target_size=FRAME_W, num_colors=64)
    transparent = remove_background(small)
    return result, transparent


def main():
    parser = argparse.ArgumentParser(description="Generate character portraits")
    parser.add_argument("--jobs", nargs="+", default=list(PORTRAIT_PROMPTS.keys()))
    parser.add_argument("--output", default="tmp/generated/portraits")
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--variations", type=int, default=3,
                        help="Generate N variations per job, pick best")
    args = parser.parse_args()

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    print("Loading pipeline (style LoRA, IP-Adapter)...")
    pipe = load_pipeline(use_ipadapter=True, lora_mode="style", use_controlnet=False)

    for job_id in args.jobs:
        if job_id not in PORTRAIT_PROMPTS:
            print(f"SKIP: no portrait prompt for '{job_id}'")
            continue

        print(f"\n{'='*60}")
        print(f"Generating portrait: {job_id} ({args.variations} variations)")
        print(f"{'='*60}")

        # Generate first variation freely, use as identity reference for rest
        raw_ref, portrait0 = generate_portrait(pipe, job_id, args.seed)
        identity = compute_identity_embeddings(pipe, raw_ref)

        best = portrait0
        best_seed = args.seed
        variations = [(portrait0, args.seed)]

        for v in range(1, args.variations):
            seed = args.seed + v * 1000 + hash(job_id) % 1000
            _, portrait = generate_portrait(pipe, job_id, seed, identity)
            variations.append((portrait, seed))

        # Save all variations
        for i, (port, seed) in enumerate(variations):
            var_path = output_dir / f"{job_id}_v{i}.png"
            port.save(var_path)
            print(f"  Saved: {var_path} (seed={seed})")

        # Use first as the primary (identity-defining) one
        primary_path = output_dir / f"{job_id}.png"
        variations[0][0].save(primary_path)
        print(f"  Primary: {primary_path}")

    meta = {"tier": "T1", "generator": "gen_portraits.py",
            "lora_mode": "style", "size": "256x256",
            "jobs": args.jobs}
    (output_dir / "generation_meta.json").write_text(json.dumps(meta, indent=2))
    print(f"\nDone: {len(args.jobs)} portraits in {output_dir}")


if __name__ == "__main__":
    main()
