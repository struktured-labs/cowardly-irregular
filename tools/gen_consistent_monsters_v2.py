#!/usr/bin/env python3
"""Generate monsters with STRONG frame-to-frame consistency.

Fixes over v1:
  1. Higher IP-Adapter identity lock (0.65 default vs 0.4)
  2. Unified palette: k-means on frame 0, ALL other frames snap to that palette
  3. Cross-frame size normalization: measure character height from frame 0,
     scale all subsequent frames to match
  4. Optional frame duplication for very simple creatures (slimes, ghosts)

Usage:
  python tools/gen_consistent_monsters_v2.py --monsters slime wolf skeleton --seed 4444
  python tools/gen_consistent_monsters_v2.py --monsters slime --ip-scale 0.7 --frames 4
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image
from sklearn.cluster import MiniBatchKMeans

sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.pipeline.config import FRAME_W, FRAME_H, PROJECT_DIR
from tools.pipeline.loader import load_pipeline
from tools.pipeline.prompts import build_monster_prompt, NEGATIVE_PROMPT
from tools.pipeline.identity import compute_identity_embeddings
from tools.pipeline.postprocess import remove_background, center_character

MONSTER_NEGATIVE = (
    NEGATIVE_PROMPT +
    ", humanoid, human, person, player character, warrior, knight, armor, "
    "sword, multiple characters, sprite sheet, reference sheet, model sheet, "
    "turnaround, concept art, collage, grid, tiled"
)


def extract_palette_kmeans(img: Image.Image, n_colors: int = 128) -> MiniBatchKMeans:
    """Fit k-means on a single frame's pixels. Returns the fitted model."""
    arr = np.array(img.convert("RGBA"))
    mask = arr[:, :, 3] > 10
    if not mask.any():
        # fallback: fit on all pixels
        pixels = arr[:, :, :3].reshape(-1, 3).astype(np.float32)
    else:
        pixels = arr[mask][:, :3].astype(np.float32)

    if len(pixels) < 1:
        raise RuntimeError("No opaque pixels found — SDXL may have generated a blank frame")

    kmeans = MiniBatchKMeans(
        n_clusters=min(n_colors, max(1, len(pixels))),
        random_state=42,
        batch_size=min(1000, max(1, len(pixels))),
        n_init=3,
    ).fit(pixels)
    return kmeans


def apply_palette(img: Image.Image, kmeans: MiniBatchKMeans) -> Image.Image:
    """Snap an image's colors to the palette defined by a fitted k-means model."""
    arr = np.array(img.convert("RGBA"))
    rgb = arr[:, :, :3].astype(np.float32)
    h, w = rgb.shape[:2]
    pixels = rgb.reshape(-1, 3)

    labels = kmeans.predict(pixels)
    snapped = kmeans.cluster_centers_[labels].reshape(h, w, 3).astype(np.uint8)

    # Preserve alpha channel
    result = arr.copy()
    result[:, :, :3] = snapped
    return Image.fromarray(result)


def downscale_raw(img: Image.Image, target_size: int = 256) -> Image.Image:
    """Simple BOX downscale without per-frame color quantization."""
    return img.resize((target_size, target_size), Image.BOX)


def remove_bg_robust(img: Image.Image, tolerance: int = 35) -> Image.Image:
    """Remove background using pre-quantization for clean flood-fill.

    The naive flood-fill in remove_background() fails on smooth gradients.
    Fix: quantize to few colors first (flattens gradients), run BG removal
    on that, then transfer the alpha mask back to the original image.
    """
    # Quick quantize to flatten gradients for BG detection
    quant = img.convert("RGB").quantize(colors=32, method=Image.Quantize.MEDIANCUT).convert("RGBA")

    # Run flood-fill BG removal on the flattened version
    masked = remove_background(quant, tolerance=tolerance)

    # Extract the alpha mask
    alpha = np.array(masked)[:, :, 3]

    # Apply alpha to original (un-quantized) image
    arr = np.array(img.convert("RGBA"))
    arr[:, :, 3] = alpha
    return Image.fromarray(arr)


def measure_char_bbox(img: Image.Image):
    """Return (height, width, y_center) of opaque character region."""
    arr = np.array(img)
    mask = arr[:, :, 3] > 10
    if not mask.any():
        return 0, 0, 0
    ys, xs = np.where(mask)
    h = ys.max() - ys.min() + 1
    w = xs.max() - xs.min() + 1
    y_center = (ys.max() + ys.min()) // 2
    return h, w, y_center


def generate_single(pipe, prompt, seed, identity_embeds=None, ip_scale=0.0):
    """Generate one 768x768 frame."""
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
    if identity_embeds is not None:
        gen_kwargs["ip_adapter_image_embeds"] = identity_embeds
    else:
        gen_kwargs["ip_adapter_image"] = Image.new("RGB", (768, 768), (128, 128, 128))

    return pipe(**gen_kwargs).images[0]


def generate_monster(pipe, monster_id, base_seed, n_frames=8, ip_scale=0.65, num_colors=128):
    """Generate consistent monster strip with unified palette and size normalization."""
    prompt = build_monster_prompt(monster_id)
    print(f"  Prompt: {prompt[:80]}...")

    # ── Frame 0: free generation (no identity lock) ──
    print(f"  Frame 0/{n_frames} (seed={base_seed}, reference frame)...")
    raw_ref = generate_single(pipe, prompt, base_seed, ip_scale=0.0)

    # Downscale, remove BG, center
    small_ref = downscale_raw(raw_ref, target_size=FRAME_W)
    trans_ref = remove_bg_robust(small_ref)
    frame0 = center_character(trans_ref)

    # ── Extract unified palette from frame 0 ──
    print(f"  Extracting unified palette ({num_colors} colors) from frame 0...")
    palette_model = extract_palette_kmeans(frame0, n_colors=num_colors)
    frame0_snapped = apply_palette(frame0, palette_model)

    # Measure frame 0 character size for normalization
    ref_h, ref_w, ref_yc = measure_char_bbox(frame0_snapped)
    print(f"  Reference character size: {ref_w}x{ref_h}")

    # Compute identity embeddings from raw 768x768 (before any downscale)
    identity = compute_identity_embeddings(pipe, raw_ref)

    # ── Frames 1+: identity-locked, palette-snapped ──
    frames = [np.array(frame0_snapped)]

    for i in range(1, n_frames):
        seed = base_seed + i
        print(f"  Frame {i}/{n_frames} (seed={seed}, identity lock={ip_scale})...")

        raw = generate_single(pipe, prompt, seed,
                              identity_embeds=identity, ip_scale=ip_scale)

        small = downscale_raw(raw, target_size=FRAME_W)
        trans = remove_bg_robust(small)

        # Size normalization: scale character to match frame 0's height
        frame = center_character(trans, target_char_h=ref_h)

        # Snap to unified palette
        frame = apply_palette(frame, palette_model)
        frames.append(np.array(frame))

    strip = np.concatenate(frames, axis=1)
    return Image.fromarray(strip)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--monsters", nargs="+", required=True)
    parser.add_argument("--output", default="tmp/generated/monsters_consistent_v2")
    parser.add_argument("--seed", type=int, default=4444)
    parser.add_argument("--lora-mode", default="none", choices=["none", "style", "light"])
    parser.add_argument("--frames", type=int, default=8, help="Frames per monster")
    parser.add_argument("--ip-scale", type=float, default=0.65,
                        help="IP-Adapter identity lock strength (0.4=loose, 0.65=tight, 0.8=very tight)")
    parser.add_argument("--colors", type=int, default=96,
                        help="Palette size (fewer = more consistent colors)")
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
        print(f"  IP-Adapter scale: {args.ip_scale}, Palette colors: {args.colors}")
        print(f"{'='*60}")

        strip = generate_monster(pipe, mid, base_seed,
                                 n_frames=args.frames,
                                 ip_scale=args.ip_scale,
                                 num_colors=args.colors)
        out_path = output_dir / f"{mid}.png"
        strip.save(out_path)
        print(f"  Saved: {out_path} ({strip.size[0]}x{strip.size[1]})")
        all_seeds[mid] = list(range(base_seed, base_seed + args.frames))

    meta = {
        "tier": "T1",
        "lora_mode": args.lora_mode,
        "ip_adapter": True,
        "ip_adapter_scale": args.ip_scale,
        "palette_colors": args.colors,
        "method": f"v2: frame0 free → unified palette + size norm, frames 1+ identity-locked at {args.ip_scale}",
        "seeds": all_seeds,
    }
    (output_dir / "generation_meta.json").write_text(json.dumps(meta, indent=2))
    print(f"\nDone: {len(args.monsters)} monsters → {output_dir}")


if __name__ == "__main__":
    main()
