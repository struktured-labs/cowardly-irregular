#!/usr/bin/env python3
"""
SDXL + Pixel Art LoRA sprite generator for Cowardly Irregular.

Generates hero frames for job sprites using:
  1. SDXL base + pixel-art-xl LoRA for generation
  2. PixelOE for clean pixelization
  3. Palette snapping to match artist's reference

Usage:
  python tools/gen_sprite_sdxl.py --job bard --animation idle
  python tools/gen_sprite_sdxl.py --job guardian --animation idle --variations 4
  python tools/gen_sprite_sdxl.py --job bard --all-animations
  python tools/gen_sprite_sdxl.py --job fighter --lora-mode fighter --no-controlnet
  python tools/gen_sprite_sdxl.py --job rogue --lora-mode style --controlnet --controlnet-scale 0.7
"""

import argparse
import json
import os
import sys
from pathlib import Path

import torch
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.pipeline.config import (
    OUTPUT_DIR, REFERENCE_DIR, IPADAPTER_WEIGHTS, ANIMATIONS, FRAME_COUNTS, PROJECT_DIR,
)
from tools.pipeline.prompts import build_prompt, get_negative_prompt
from tools.pipeline.loader import load_pipeline
from tools.pipeline.identity import compute_identity_embeddings, save_embeddings
from tools.pipeline.controlnet_poses import load_pose_skeleton
from tools.pipeline.postprocess import extract_reference_palette
from tools.pipeline.generate import generate_strip


def main():
    parser = argparse.ArgumentParser(description="SDXL Sprite Generator")
    parser.add_argument("--job", required=True, help="Job ID (fighter, mage, bard, etc.)")
    parser.add_argument("--animation", default="idle", help="Animation name")
    parser.add_argument("--all-animations", action="store_true", help="Generate all 9 animations")
    parser.add_argument("--variations", type=int, default=1, help="Number of variations to generate")
    parser.add_argument("--seed", type=int, default=None, help="Base seed for reproducibility")
    parser.add_argument("--no-pixelize", action="store_true", help="Force manual downscale instead of PixelOE")
    parser.add_argument("--pixeloe-quant", action="store_true", help="Enable PixelOE color quantization (default: off, uses palette snap)")
    parser.add_argument("--no-palette-snap", action="store_true", help="Skip palette snapping")
    parser.add_argument("--no-ipadapter", action="store_true", help="Disable IP-Adapter identity lock")
    parser.add_argument("--reference-image", help="Path to reference character image for IP-Adapter")
    parser.add_argument("--ipadapter-scale", type=float, default=0.45, help="IP-Adapter strength (0.0-1.0)")
    parser.add_argument("--output", help="Output directory (default: tmp/generated/<job>/)")
    parser.add_argument(
        "--lora-mode",
        choices=["fighter", "style", "none"],
        default="fighter",
        help="LoRA to load: 'fighter' (fighter_ci_pixel_500), 'style' (jrpg_pixel_style), 'none'",
    )
    parser.add_argument(
        "--controlnet",
        action="store_true",
        default=False,
        dest="use_controlnet",
        help="Enable ControlNet openpose conditioning (loads pose skeletons from tools/pose_skeletons/)",
    )
    parser.add_argument(
        "--no-controlnet",
        action="store_false",
        dest="use_controlnet",
        help="Disable ControlNet (default)",
    )
    parser.add_argument(
        "--controlnet-scale",
        type=float,
        default=0.6,
        help="ControlNet conditioning scale (0.0-1.0, default: 0.6)",
    )
    args = parser.parse_args()

    output_dir = Path(args.output) if args.output else OUTPUT_DIR / args.job
    output_dir.mkdir(parents=True, exist_ok=True)

    use_ipadapter = not args.no_ipadapter
    pipe = load_pipeline(
        use_ipadapter=use_ipadapter,
        lora_mode=args.lora_mode,
        use_controlnet=args.use_controlnet,
    )

    if use_ipadapter:
        pipe.set_ip_adapter_scale(args.ipadapter_scale)
        print(f"IP-Adapter scale set to {args.ipadapter_scale}")

    identity_embeds = None
    if use_ipadapter and IPADAPTER_WEIGHTS.exists():
        if args.reference_image:
            ref_img = Image.open(args.reference_image).convert("RGB")
            print(f"Using provided reference: {args.reference_image}")
        else:
            hero_seed = args.seed if args.seed else 42
            print(f"\nGenerating hero reference frame (seed={hero_seed})...")
            gen = torch.Generator("cuda").manual_seed(hero_seed)
            prompt = build_prompt(args.job, "idle")
            pipe.set_ip_adapter_scale(0.0)
            ref_img = pipe(
                prompt=prompt,
                negative_prompt=get_negative_prompt(args.job),
                num_inference_steps=40,
                guidance_scale=9.0,
                width=768,
                height=768,
                generator=gen,
                ip_adapter_image=Image.new("RGB", (768, 768), (128, 128, 128)),
            ).images[0]
            pipe.set_ip_adapter_scale(args.ipadapter_scale)
            hero_path = output_dir / "hero_reference.png"
            ref_img.save(hero_path)
            print(f"  Hero saved: {hero_path}")

        identity_embeds = compute_identity_embeddings(pipe, ref_img)
        embeds_path = output_dir / "identity_embeds.pt"
        save_embeddings(identity_embeds, embeds_path)

    ref_palette = None
    hero_path = output_dir / "hero_reference.png"
    if not args.no_palette_snap:
        if hero_path.exists():
            print(f"Extracting palette from hero reference...")
            ref_palette = extract_reference_palette(str(hero_path))
        elif REFERENCE_DIR.exists():
            print("Extracting palette from fighter sprites (fallback)...")
            ref_palette = extract_reference_palette()
        if ref_palette:
            print(f"  {len(ref_palette)} reference colors loaded")

    animations = ANIMATIONS if args.all_animations else [args.animation]

    for anim in animations:
        n_frames = FRAME_COUNTS.get(anim, 4)
        print(f"\n{'='*60}")
        print(f"Generating {args.job}/{anim} ({n_frames} frames, {args.variations} variation(s))")
        print(f"{'='*60}")

        # Load pose skeletons for ControlNet if enabled
        controlnet_images = None
        if args.use_controlnet:
            controlnet_images = []
            for i in range(n_frames):
                pose = load_pose_skeleton(anim, i)
                controlnet_images.append(pose)
            loaded = sum(1 for p in controlnet_images if p is not None)
            print(f"  ControlNet poses: {loaded}/{n_frames} loaded from pose_skeletons/{anim}/")

        for v in range(args.variations):
            seed = (args.seed + v * 1000) if args.seed else None
            strip, seeds = generate_strip(
                pipe, args.job, anim, n_frames, seed, ref_palette,
                identity_embeds=identity_embeds,
                use_pixeloe=not args.no_pixelize,
                pixeloe_quant=args.pixeloe_quant,
                controlnet_images=controlnet_images,
                controlnet_scale=args.controlnet_scale,
            )

            suffix = f"_v{v}" if args.variations > 1 else ""
            out_path = output_dir / f"{anim}{suffix}.png"
            strip.save(out_path)
            print(f"  Saved: {out_path} ({strip.size[0]}x{strip.size[1]}, seeds={seeds})")

    meta = {
        "job": args.job,
        "tier": "T1",
        "generator": "gen_sprite_sdxl.py",
        "model": "SDXL 1.0 + pixel-art-xl LoRA + IP-Adapter Plus Face",
        "lora_mode": args.lora_mode,
        "controlnet": args.use_controlnet,
        "controlnet_scale": args.controlnet_scale if args.use_controlnet else None,
        "ip_adapter_scale": args.ipadapter_scale if use_ipadapter else None,
        "animations": {anim: str(output_dir / f"{anim}.png") for anim in animations},
    }
    meta_path = output_dir / "generation_meta.json"
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"\nMetadata: {meta_path}")

    print(f"\n{'='*60}")
    print("Running sprite linter on generated output...")
    print(f"{'='*60}")
    os.system(f"python3 {PROJECT_DIR}/tools/sprite_linter.py {output_dir} --reference {REFERENCE_DIR}")


if __name__ == "__main__":
    main()
