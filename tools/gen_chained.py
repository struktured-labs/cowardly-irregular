#!/usr/bin/env python3
"""
Chained img2img experiment for temporal frame coherence.

Each frame N uses frame N-1 as its IP-Adapter identity reference, with
ControlNet openpose skeleton for pose control. Frame 0 uses the artist's
reference sprite as anchor.

The hypothesis: frame N+1 literally "looks at" frame N as "the same character,
new pose", which should cut frame-to-frame drift dramatically compared to
generating each frame independently.

Usage:
    uv run python tools/gen_chained.py --job rogue --animation walk
    uv run python tools/gen_chained.py --job rogue --animation walk --compare
"""

import argparse
import json
import sys
from pathlib import Path

import torch
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.pipeline.config import OUTPUT_DIR, FRAME_COUNTS, PROJECT_DIR
from tools.pipeline.prompts import build_prompt, get_negative_prompt
from tools.pipeline.loader import load_pipeline
from tools.pipeline.identity import compute_identity_embeddings
from tools.pipeline.controlnet_poses import load_pose_skeleton

PROJECT = Path(__file__).parent.parent

# Artist references per job
ARTIST_REFS = {
    "fighter": PROJECT / "assets/sprites/jobs/fighter/idle.png",
    "rogue":   PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/ROGUE/Rogue Base sprite.png",
    "cleric":  PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/CLERIC/Cleric Main design-Sheet.png",
    "mage":    PROJECT / "assets/sprites/jobs/mage_artist/idle.png",
}

GEN_SIZE = 768
FRAME_SIZE = 256


def generate_frame(pipe, prompt, negative, pose_skeleton, ref_image,
                   ip_scale: float, controlnet_scale: float, seed: int,
                   steps: int = 35, guidance: float = 8.0):
    """Generate a single frame using the given reference image."""
    pipe.set_ip_adapter_scale(ip_scale)
    gen = torch.Generator("cuda").manual_seed(seed)

    # Ensure ref is RGB 768x768
    ref_768 = ref_image.convert("RGB").resize((GEN_SIZE, GEN_SIZE), Image.LANCZOS)

    # Pose skeleton
    if pose_skeleton is None:
        pose_skeleton = Image.new("RGB", (GEN_SIZE, GEN_SIZE), (0, 0, 0))

    result = pipe(
        prompt=prompt,
        negative_prompt=negative,
        image=pose_skeleton,  # ControlNet conditioning
        ip_adapter_image=ref_768,
        num_inference_steps=steps,
        guidance_scale=guidance,
        width=GEN_SIZE,
        height=GEN_SIZE,
        controlnet_conditioning_scale=controlnet_scale,
        generator=gen,
    ).images[0]

    return result


def extract_frame_from_ref(ref_path: Path, frame_idx: int = 0,
                           frame_w: int = None, frame_h: int = None) -> Image.Image:
    """Extract a single frame from an artist reference image.
    If it's a strip, take the requested frame; otherwise return as-is."""
    img = Image.open(ref_path).convert("RGBA")
    w, h = img.size
    if w >= 2 * h:
        # Horizontal strip
        fh = frame_h or h
        fw = frame_w or fh
        x = frame_idx * fw
        if x < w:
            return img.crop((x, 0, x + fw, fh))
    return img


def downscale_to_frame(img: Image.Image) -> Image.Image:
    """Downscale 768x768 → 256x256 for sprite output."""
    return img.resize((FRAME_SIZE, FRAME_SIZE), Image.LANCZOS)


def run_chained(pipe, job: str, animation: str, n_frames: int,
                output_dir: Path, seed: int = 42,
                ip_scale_anchor: float = 0.7, ip_scale_chain: float = 0.85,
                controlnet_scale: float = 0.55):
    """Chain-generate all frames using frame N as IP-Adapter ref for frame N+1."""
    print(f"\n{'='*60}")
    print(f"  CHAINED: {job} / {animation} ({n_frames} frames)")
    print(f"  IP anchor scale: {ip_scale_anchor} (frame 0)")
    print(f"  IP chain  scale: {ip_scale_chain} (frames 1+)")
    print(f"  ControlNet:      {controlnet_scale}")
    print(f"{'='*60}\n")

    # Load artist reference
    ref_path = ARTIST_REFS.get(job)
    if ref_path is None or not ref_path.exists():
        print(f"  WARN: No artist ref for {job}, using gray")
        anchor_ref = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (128, 128, 128, 255))
    else:
        anchor_ref = extract_frame_from_ref(ref_path, 0)
        print(f"  Artist ref: {ref_path.name} ({anchor_ref.size})")

    negative = get_negative_prompt(job)
    frames_768 = []  # keep at 768 for chaining
    frames_final = []  # downscaled output

    current_ref = anchor_ref
    current_ip_scale = ip_scale_anchor

    for i in range(n_frames):
        prompt = build_prompt(job, animation, frame_idx=i)
        pose = load_pose_skeleton(animation, i)
        frame_seed = seed + i * 1000

        print(f"  Frame {i}/{n_frames-1}: seed={frame_seed}, ip_scale={current_ip_scale:.2f}, pose={pose is not None}")

        frame_768 = generate_frame(
            pipe, prompt, negative, pose,
            current_ref, current_ip_scale, controlnet_scale,
            frame_seed
        )

        frames_768.append(frame_768)
        small = downscale_to_frame(frame_768)
        frames_final.append(small)

        # Chain: next frame uses this frame as identity reference
        current_ref = frame_768
        current_ip_scale = ip_scale_chain

    # Assemble horizontal strip
    strip = Image.new("RGBA", (FRAME_SIZE * n_frames, FRAME_SIZE), (0, 0, 0, 0))
    for i, f in enumerate(frames_final):
        strip.paste(f.convert("RGBA"), (i * FRAME_SIZE, 0))

    out_path = output_dir / f"{animation}_chained.png"
    strip.save(out_path)
    print(f"\n  Saved chained: {out_path}")
    return strip


def run_unchained_baseline(pipe, job: str, animation: str, n_frames: int,
                           output_dir: Path, seed: int = 42,
                           ip_scale: float = 0.55, controlnet_scale: float = 0.55):
    """Baseline: generate all frames independently using only the artist anchor."""
    print(f"\n{'='*60}")
    print(f"  BASELINE (unchained): {job} / {animation}")
    print(f"{'='*60}\n")

    ref_path = ARTIST_REFS.get(job)
    anchor_ref = extract_frame_from_ref(ref_path, 0) if ref_path and ref_path.exists() else None
    if anchor_ref is None:
        anchor_ref = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (128, 128, 128, 255))

    negative = get_negative_prompt(job)
    frames = []

    for i in range(n_frames):
        prompt = build_prompt(job, animation, frame_idx=i)
        pose = load_pose_skeleton(animation, i)
        frame_seed = seed + i * 1000

        print(f"  Frame {i}: seed={frame_seed}")
        frame_768 = generate_frame(
            pipe, prompt, negative, pose,
            anchor_ref, ip_scale, controlnet_scale,
            frame_seed
        )
        frames.append(downscale_to_frame(frame_768))

    strip = Image.new("RGBA", (FRAME_SIZE * n_frames, FRAME_SIZE), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f.convert("RGBA"), (i * FRAME_SIZE, 0))

    out_path = output_dir / f"{animation}_baseline.png"
    strip.save(out_path)
    print(f"\n  Saved baseline: {out_path}")
    return strip


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", default="rogue", help="Job ID")
    parser.add_argument("--animation", default="walk")
    parser.add_argument("--compare", action="store_true",
                        help="Also generate non-chained baseline for comparison")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--ip-anchor", type=float, default=0.7)
    parser.add_argument("--ip-chain", type=float, default=0.85)
    parser.add_argument("--controlnet-scale", type=float, default=0.55)
    args = parser.parse_args()

    n_frames = FRAME_COUNTS.get(args.animation, 4)
    output_dir = PROJECT / "tmp" / "chained_experiment" / args.job
    output_dir.mkdir(parents=True, exist_ok=True)

    print("Loading pipeline (v2 LoRA + IP-Adapter + ControlNet)...")
    pipe = load_pipeline(use_ipadapter=True, lora_mode="style", use_controlnet=True)

    # Chained run
    chained = run_chained(
        pipe, args.job, args.animation, n_frames, output_dir,
        seed=args.seed,
        ip_scale_anchor=args.ip_anchor,
        ip_scale_chain=args.ip_chain,
        controlnet_scale=args.controlnet_scale,
    )

    if args.compare:
        baseline = run_unchained_baseline(
            pipe, args.job, args.animation, n_frames, output_dir,
            seed=args.seed,
            ip_scale=args.ip_anchor,
            controlnet_scale=args.controlnet_scale,
        )

        # Stack baseline above chained for visual comparison
        cw, ch = chained.size
        comparison = Image.new("RGBA", (cw, ch * 2 + 20), (30, 30, 30, 255))
        comparison.paste(baseline.convert("RGBA"), (0, 0))
        comparison.paste(chained.convert("RGBA"), (0, ch + 20))
        cmp_path = output_dir / f"{args.animation}_comparison.png"
        comparison.save(cmp_path)
        print(f"\n  Comparison saved: {cmp_path}")
        print(f"    (top = baseline/independent, bottom = chained)")

    # Meta
    meta = {
        "job": args.job,
        "animation": args.animation,
        "n_frames": n_frames,
        "ip_scale_anchor": args.ip_anchor,
        "ip_scale_chain": args.ip_chain,
        "controlnet_scale": args.controlnet_scale,
        "seed": args.seed,
        "chained": True,
        "compare": args.compare,
    }
    (output_dir / f"{args.animation}_meta.json").write_text(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
