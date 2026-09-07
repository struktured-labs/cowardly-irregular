#!/usr/bin/env python3
"""Generate monsters with IP-Adapter identity lock for frame consistency.

Strategy: generate frame 0 freely, then use it as IP-Adapter reference
for frames 1-7. This ensures all frames look like the same creature
without LoRA humanoid bias.
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
from tools.pipeline.identity import compute_identity_embeddings
from tools.pipeline.postprocess import downscale_to_pixel_art, remove_background, center_character

MONSTER_NEGATIVE = (
    NEGATIVE_PROMPT +
    ", humanoid, human, person, player character, warrior, knight, armor, "
    "sword, multiple characters, sprite sheet, reference sheet, model sheet, "
    "turnaround, concept art, collage, grid, tiled"
)

N_FRAMES = 8


def generate_single(pipe, prompt, seed, identity_embeds=None, ip_scale=0.0):
    """Generate one 768x768 frame, downscale to 256x256."""
    pipe.set_ip_adapter_scale(ip_scale)

    gen = torch.Generator("cuda").manual_seed(seed)
    gen_kwargs = dict(
        prompt=prompt,
        negative_prompt=MONSTER_NEGATIVE,
        num_inference_steps=40,
        guidance_scale=9.0,
        width=768, height=768,
        generator=gen,
    )
    # IP-Adapter requires embeddings in every call once loaded
    if identity_embeds is not None:
        gen_kwargs["ip_adapter_image_embeds"] = identity_embeds
    else:
        gen_kwargs["ip_adapter_image"] = Image.new("RGB", (768, 768), (128, 128, 128))

    result = pipe(**gen_kwargs).images[0]
    small = downscale_to_pixel_art(result, target_size=FRAME_W, num_colors=128)
    transparent = remove_background(small)
    centered = center_character(transparent)
    return result, centered


def generate_monster(pipe, monster_id, base_seed):
    """Generate consistent monster strip using IP-Adapter identity lock."""
    prompt = build_monster_prompt(monster_id)
    print(f"  Generating reference frame (seed={base_seed}, no identity lock)...")

    # Frame 0: free generation (IP-Adapter at 0.0)
    raw_ref, frame0 = generate_single(pipe, prompt, base_seed, ip_scale=0.0)

    # Compute identity embeddings from the raw 768x768 reference
    identity = compute_identity_embeddings(pipe, raw_ref)

    # Frames 1-7: identity-locked to frame 0
    frames = [np.array(frame0)]
    for i in range(1, N_FRAMES):
        seed = base_seed + i
        print(f"  Frame {i}/{N_FRAMES} (seed={seed}, identity locked)...")
        _, frame = generate_single(pipe, prompt, seed,
                                    identity_embeds=identity, ip_scale=0.4)
        frames.append(np.array(frame))

    strip = np.concatenate(frames, axis=1)
    return Image.fromarray(strip)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--monsters", nargs="+", required=True)
    parser.add_argument("--output", default="tmp/generated/monsters_consistent")
    parser.add_argument("--seed", type=int, default=9999)
    parser.add_argument("--lora-mode", default="none", choices=["none", "style", "light"])
    args = parser.parse_args()

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Loading pipeline (lora={args.lora_mode}, IP-Adapter=ON)...")
    pipe = load_pipeline(use_ipadapter=True, lora_mode=args.lora_mode, use_controlnet=False)

    all_seeds = {}
    for idx, mid in enumerate(args.monsters):
        base_seed = args.seed + idx * 100
        print(f"\n{'='*60}")
        print(f"{mid} ({idx+1}/{len(args.monsters)})")
        print(f"{'='*60}")

        strip = generate_monster(pipe, mid, base_seed)
        out_path = output_dir / f"{mid}.png"
        strip.save(out_path)
        print(f"  Saved: {out_path}")
        all_seeds[mid] = list(range(base_seed, base_seed + N_FRAMES))

    meta = {"tier": "T1", "lora_mode": args.lora_mode, "ip_adapter": True,
            "method": "frame0 free, frames 1-7 identity-locked at 0.4",
            "seeds": all_seeds}
    (output_dir / "generation_meta.json").write_text(json.dumps(meta, indent=2))
    print(f"\nDone: {len(args.monsters)} monsters")


if __name__ == "__main__":
    main()
