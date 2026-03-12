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
"""

import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image

# Paths
COMFYUI_DIR = Path("/home/struktured/projects/ComfyUI")
PROJECT_DIR = Path("/home/struktured/projects/cowardly-irregular-sprite-gen")
MODELS_DIR = COMFYUI_DIR / "models"
OUTPUT_DIR = PROJECT_DIR / "tmp" / "generated"
REFERENCE_DIR = PROJECT_DIR / "assets" / "sprites" / "jobs" / "fighter"

SDXL_CHECKPOINT = MODELS_DIR / "checkpoints" / "sd_xl_base_1.0.safetensors"
PIXEL_ART_LORA = MODELS_DIR / "loras" / "fighter_ci_pixel_500.safetensors"

# Generation constants
FRAME_W = 256
FRAME_H = 256
ANIMATIONS = ["idle", "walk", "attack", "hit", "dead", "cast", "defend", "item", "victory"]

# Frame counts per animation (matching existing sprite conventions)
FRAME_COUNTS = {
    "idle": 2,
    "walk": 6,
    "attack": 6,
    "hit": 4,
    "dead": 4,
    "cast": 4,
    "defend": 4,
    "item": 4,
    "victory": 4,
}

# ── Job Descriptions ────────────────────────────────────────────────────────
# These drive the prompt. Each job has a visual description and color palette hint.

JOB_PROMPTS = {
    "fighter": {
        "desc": "medieval warrior in red and steel armor, broadsword, sturdy stance, brown hair",
        "palette_hint": "warm reds, steel grays, brown leather, orange accents",
    },
    "mage": {
        "desc": "mysterious mage in deep blue robes, tall pointed wizard hat, crystal-tipped staff, glowing cyan eyes",
        "palette_hint": "deep blues, cyan glow, silver trim, dark shadows",
    },
    "cleric": {
        "desc": "young white mage healer girl, warm kind expression, flowing white robe with pink and gold trim, golden staff with crystal orb, classic Final Fantasy white mage aesthetic, soft features, gentle but determined, hood with ribbon detail",
        "palette_hint": "white, soft pink, pale gold, cream, light blue, warm pastel tones",
    },
    "rogue": {
        "desc": "stealthy rogue in dark leather armor, short green cloak, dual curved daggers, bandana, athletic build",
        "palette_hint": "dark brown leather, charcoal, dark green, silver blades",
    },
    "bard": {
        "desc": "charming bard in gold-olive doublet with half-cape, feathered beret with red feather, lute on back, rapier at hip",
        "palette_hint": "gold, olive green, red feather, warm browns, cream shirt",
    },
    "guardian": {
        "desc": "heavily armored guardian knight, massive tower shield, full plate armor, stoic protector, visor helmet",
        "palette_hint": "steel blue, silver, dark iron, gold trim, cape blue",
    },
    "ninja": {
        "desc": "swift ninja in dark wrappings, face mask, kunai daggers, crouched ready pose, minimal armor",
        "palette_hint": "blacks, dark purple, steel gray, red sash accent",
    },
    "summoner": {
        "desc": "ethereal summoner in flowing robes with arcane symbols, horned circlet, floating grimoire, mystical aura",
        "palette_hint": "deep purple, gold arcane symbols, teal energy, dark cloth",
    },
    "speculator": {
        "desc": "90s wall street speculator in pinstripe suit, round spectacles, pocket watch chain, confident smirk, briefcase",
        "palette_hint": "navy pinstripe, white shirt, gold accents, black shoes",
    },
}

# ── Animation Pose Descriptions ────────────────────────────────────────────
ANIMATION_POSES = {
    "idle": "standing neutral ready pose, slight breathing motion",
    "walk": "walking forward mid-stride",
    "attack": "swinging weapon in aggressive strike",
    "hit": "recoiling from being hit, pained expression",
    "dead": "collapsed on ground, defeated",
    "cast": "channeling magic with raised hand, energy gathering",
    "defend": "blocking with shield or defensive stance",
    "item": "holding up a potion or item",
    "victory": "triumphant celebration pose, weapon raised",
}


def build_prompt(job: str, animation: str, frame_idx: int = 0) -> str:
    """Build the generation prompt for a specific job + animation."""
    job_info = JOB_PROMPTS.get(job, {"desc": job, "palette_hint": "muted fantasy colors"})
    pose = ANIMATION_POSES.get(animation, "neutral pose")

    # Keep prompt under 77 tokens for CLIP — front-load the important stuff
    prompt = (
        f"pixel art RPG battle sprite of a {job_info['desc']}, "
        f"{pose}, "
        f"fighter_ci_pixel, 16-bit SNES style, {job_info['palette_hint']}, "
        f"black outline, white background, isolated character"
    )
    return prompt


NEGATIVE_PROMPT = (
    "multiple characters, multiple views, sprite sheet, reference sheet, "
    "turnaround, model sheet, concept art, collage, grid, tiled, pattern, "
    "background scenery, landscape, room, floor, wall, "
    "blurry, photorealistic, 3D, text, watermark, deformed, sword, blade, knife, "
    "oversexualized, revealing armor, bikini armor, cleavage, "
    "multiple characters, multiple views, sprite sheet, reference sheet"
)


IPADAPTER_DIR = COMFYUI_DIR / "models" / "ipadapter"
IPADAPTER_WEIGHTS = IPADAPTER_DIR / "sdxl_models" / "ip-adapter-plus_sdxl_vit-h.safetensors"
CLIP_ENCODER_DIR = IPADAPTER_DIR / "models" / "image_encoder"


def load_pipeline(use_ipadapter: bool = True):
    """Load SDXL + LoRA + IP-Adapter pipeline."""
    from diffusers import StableDiffusionXLPipeline, DDIMScheduler

    if use_ipadapter and CLIP_ENCODER_DIR.exists():
        from transformers import CLIPVisionModelWithProjection
        print("Loading CLIP ViT-H image encoder...")
        image_encoder = CLIPVisionModelWithProjection.from_pretrained(
            str(CLIP_ENCODER_DIR),
            torch_dtype=torch.float16,
        )
    else:
        image_encoder = None

    print(f"Loading SDXL from {SDXL_CHECKPOINT}...")
    pipe = StableDiffusionXLPipeline.from_single_file(
        str(SDXL_CHECKPOINT),
        image_encoder=image_encoder,
        torch_dtype=torch.float16,
        use_safetensors=True,
    )

    # DDIM scheduler recommended for IP-Adapter face models
    if use_ipadapter:
        pipe.scheduler = DDIMScheduler.from_config(pipe.scheduler.config)

    # Load IP-Adapter BEFORE LoRA
    if use_ipadapter and IPADAPTER_WEIGHTS.exists():
        print("Loading IP-Adapter Plus Face...")
        pipe.load_ip_adapter(
            str(IPADAPTER_DIR),
            subfolder="sdxl_models",
            weight_name="ip-adapter-plus_sdxl_vit-h.safetensors",
        )
        pipe.set_ip_adapter_scale(0.45)
        print("  IP-Adapter scale: 0.45")
    else:
        if use_ipadapter:
            print("WARNING: IP-Adapter weights not found, generating without identity lock")

    # Load LoRA AFTER IP-Adapter
    if PIXEL_ART_LORA.exists():
        print("Loading custom fighter_ci_pixel LoRA...")
        pipe.load_lora_weights(str(PIXEL_ART_LORA.parent), weight_name=PIXEL_ART_LORA.name)
        pipe.fuse_lora(lora_scale=0.5)
    else:
        print("WARNING: pixel-art-xl LoRA not found")

    # Memory optimization LAST (after all adapters loaded)
    pipe.enable_model_cpu_offload()
    pipe.enable_vae_slicing()

    return pipe


def compute_identity_embeddings(pipe, reference_image: Image.Image):
    """Pre-compute IP-Adapter embeddings from a reference image.

    These embeddings encode the character's visual identity and can be
    reused across all frame generations for consistency.
    """
    print("Computing identity embeddings from reference...")
    embeds = pipe.prepare_ip_adapter_image_embeds(
        ip_adapter_image=reference_image,
        ip_adapter_image_embeds=None,
        device="cuda",
        num_images_per_prompt=1,
        do_classifier_free_guidance=True,
    )
    print(f"  Embedding shape: {[e.shape for e in embeds]}")
    return embeds


def pixelize_frame(img: Image.Image, pixel_size: int = 12, num_colors: int = 32,
                   use_pixeloe: bool = True, pixeloe_quant: bool = False) -> Image.Image:
    """Apply PixelOE pixelization then upscale back to target frame size.

    pixel_size: how many input pixels become 1 pixel art pixel.
                For 768→64 effective resolution, use 12 (768/64=12).
    """
    try:
        if not use_pixeloe:
            raise RuntimeError("PixelOE disabled, using manual downscale")
        from pixeloe.torch.pixelize import pixelize

        # Convert PIL -> torch tensor (B, C, H, W) float [0, 1]
        arr = np.array(img.convert("RGB"))
        tensor = torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0).float() / 255.0
        tensor = tensor.cuda()

        # Pixelize
        pix_kwargs = dict(pixel_size=pixel_size, thickness=1, mode="contrast")
        if pixeloe_quant:
            pix_kwargs.update(do_quant=True, num_colors=num_colors, quant_mode="kmeans")
        else:
            pix_kwargs["do_quant"] = False
        result = pixelize(tensor, **pix_kwargs)

        # Convert back: (B, C, H, W) -> PIL
        out_arr = (result.squeeze(0).permute(1, 2, 0).cpu().numpy() * 255).astype(np.uint8)
        pix_img = Image.fromarray(out_arr)

        # Resize to frame size with nearest neighbor (crisp pixels)
        final = pix_img.resize((FRAME_W, FRAME_H), Image.NEAREST)
        return final
    except Exception as e:
        print(f"  PixelOE failed ({e}), using manual downscale")
        import traceback; traceback.print_exc()
        # Fallback: simple downscale + nearest upscale
        effective = img.size[0] // pixel_size
        small = img.resize((effective, effective), Image.LANCZOS)
        small = small.quantize(colors=num_colors, method=Image.Quantize.MEDIANCUT).convert("RGBA")
        return small.resize((FRAME_W, FRAME_H), Image.NEAREST)


def extract_reference_palette(source_path: str = None) -> set:
    """Extract palette from a reference image or artist's fighter sprites.

    If source_path is given (e.g. hero_reference.png), extract from that.
    Otherwise fall back to fighter sprite sheets.
    """
    from collections import Counter
    all_colors = Counter()

    if source_path and Path(source_path).exists():
        img = Image.open(source_path).convert("RGBA")
        arr = np.array(img)
        mask = arr[:, :, 3] > 10
        pixels = arr[mask][:, :3]
        for p in pixels:
            all_colors[tuple(int(c) for c in p)] += 1
        print(f"  Extracted {len(all_colors)} colors from {source_path}")
    else:
        for anim in ANIMATIONS:
            path = REFERENCE_DIR / f"{anim}.png"
            if path.exists():
                img = Image.open(path).convert("RGBA")
                arr = np.array(img)
                mask = arr[:, :, 3] > 10
                pixels = arr[mask][:, :3]
                for p in pixels:
                    all_colors[tuple(int(c) for c in p)] += 1

    # Return top colors by frequency (skip rare noise)
    min_count = max(1, len(all_colors) * 0.001)
    return set(c for c, cnt in all_colors.items() if cnt >= min_count)


def snap_to_palette(img: Image.Image, palette: set, threshold: float = 60.0) -> Image.Image:
    """Snap colors to nearest reference palette color.

    Higher threshold = more aggressive snapping (forces artist's colors).
    """
    arr = np.array(img.convert("RGBA"))
    palette_arr = np.array(list(palette))  # (N, 3)

    mask = arr[:, :, 3] > 10
    ys, xs = np.where(mask)

    for y, x in zip(ys, xs):
        c = arr[y, x, :3].astype(float)
        dists = np.sqrt(((palette_arr - c) ** 2).sum(axis=1))
        min_idx = dists.argmin()
        if dists[min_idx] < threshold:
            arr[y, x, :3] = palette_arr[min_idx]

    return Image.fromarray(arr)


def remove_background(img: Image.Image, tolerance: int = 35) -> Image.Image:
    """Remove background using flood-fill from all edges.

    Strategy: sample the entire border (all 4 edges), find the dominant
    color(s), then flood-fill from every border pixel that matches.
    This handles non-uniform backgrounds (slight gradients, dither patterns).
    """
    from scipy import ndimage

    arr = np.array(img.convert("RGBA"))
    h, w = arr.shape[:2]
    rgb = arr[:, :, :3].astype(float)

    # Sample ALL border pixels
    border_pixels = []
    for x in range(w):
        border_pixels.append(rgb[0, x])
        border_pixels.append(rgb[1, x])
        border_pixels.append(rgb[h-1, x])
        border_pixels.append(rgb[h-2, x])
    for y in range(h):
        border_pixels.append(rgb[y, 0])
        border_pixels.append(rgb[y, 1])
        border_pixels.append(rgb[y, w-1])
        border_pixels.append(rgb[y, w-2])

    border_arr = np.array(border_pixels)

    # Cluster border colors (usually 1-3 bg colors due to dithering/gradient)
    from collections import Counter
    border_tuples = [tuple(int(v) for v in p) for p in border_arr]
    color_counts = Counter(border_tuples)

    # Take all colors that appear in >5% of border pixels as background candidates
    min_count = len(border_tuples) * 0.03
    bg_colors = [np.array(c) for c, cnt in color_counts.items() if cnt > min_count]

    if not bg_colors:
        bg_colors = [np.array(color_counts.most_common(1)[0][0])]

    # Create background mask: pixel is bg if close to ANY bg color
    bg_mask = np.zeros((h, w), dtype=bool)
    for bg_color in bg_colors:
        dist = np.sqrt(((rgb - bg_color.astype(float)) ** 2).sum(axis=2))
        bg_mask |= (dist < tolerance)

    # Flood-fill from edges only — don't remove interior pixels that happen
    # to be similar to bg (like skin tones near beige backgrounds)
    edge_seed = np.zeros((h, w), dtype=bool)
    edge_seed[0, :] = True
    edge_seed[-1, :] = True
    edge_seed[:, 0] = True
    edge_seed[:, -1] = True

    # Connected component from edges through bg_mask
    flood_mask = ndimage.binary_fill_holes(~bg_mask)
    # Actually: label connected bg regions, keep only those touching edges
    labeled, n_labels = ndimage.label(bg_mask)

    # Find which labels touch the border
    edge_labels = set()
    edge_labels.update(labeled[0, :].flatten())
    edge_labels.update(labeled[-1, :].flatten())
    edge_labels.update(labeled[:, 0].flatten())
    edge_labels.update(labeled[:, -1].flatten())
    edge_labels.discard(0)  # 0 = not background

    # Remove only bg regions connected to edges
    final_bg = np.zeros((h, w), dtype=bool)
    for label_id in edge_labels:
        final_bg |= (labeled == label_id)

    arr[final_bg, 3] = 0
    return Image.fromarray(arr)


def center_character(img: Image.Image, target_w: int = FRAME_W, target_h: int = FRAME_H,
                     target_char_h: int = None) -> Image.Image:
    """Center the non-transparent character within the target frame size.

    Args:
        target_char_h: If provided, scale character to this exact pixel height.
                       Used for cross-frame normalization.
    """
    arr = np.array(img)
    mask = arr[:, :, 3] > 10

    if not mask.any():
        return img

    ys, xs = np.where(mask)
    y_min, y_max = ys.min(), ys.max()
    x_min, x_max = xs.min(), xs.max()

    # Crop to bounding box
    cropped = arr[y_min:y_max+1, x_min:x_max+1]
    ch, cw = cropped.shape[:2]

    if target_char_h and ch > 0:
        # Scale to exact target height (for cross-frame consistency)
        scale = target_char_h / ch
        # Clamp: don't upscale more than 2x (would look awful) or exceed frame
        scale = min(scale, 2.0, (target_h * 0.85) / ch, (target_w * 0.70) / cw)
        scale = max(scale, 0.3)  # don't shrink below 30%
    else:
        # Fit within frame bounds
        max_char_h = int(target_h * 0.85)
        max_char_w = int(target_w * 0.70)
        scale = min(max_char_w / max(1, cw), max_char_h / max(1, ch), 1.0)

    if abs(scale - 1.0) > 0.01:
        new_w = max(1, int(cw * scale))
        new_h = max(1, int(ch * scale))
        cropped_img = Image.fromarray(cropped).resize((new_w, new_h), Image.NEAREST)
        cropped = np.array(cropped_img)
        ch, cw = cropped.shape[:2]

    # Create transparent canvas — feet anchored near bottom
    canvas = np.zeros((target_h, target_w, 4), dtype=np.uint8)
    x_offset = (target_w - cw) // 2
    y_offset = target_h - ch - int(target_h * 0.08)  # 8% margin from bottom
    y_offset = max(0, min(y_offset, target_h - ch))
    x_offset = max(0, min(x_offset, target_w - cw))

    canvas[y_offset:y_offset+ch, x_offset:x_offset+cw] = cropped

    return Image.fromarray(canvas)


def validate_single_character(img: Image.Image) -> tuple[bool, str]:
    """Check if the image contains a single character (not multiple or a sheet).

    Returns (is_valid, reason).
    """
    from scipy import ndimage

    arr = np.array(img)
    mask = arr[:, :, 3] > 10  # opaque pixels

    if not mask.any():
        return False, "empty frame"

    # Find connected components (8-connectivity)
    labeled, n_components = ndimage.label(mask, structure=ndimage.generate_binary_structure(2, 2))

    if n_components == 0:
        return False, "no character found"

    # Get component sizes
    component_sizes = []
    for i in range(1, n_components + 1):
        component_sizes.append((labeled == i).sum())
    component_sizes.sort(reverse=True)

    total_pixels = mask.sum()
    largest = component_sizes[0]

    # The main character should be >60% of all opaque pixels
    if largest < total_pixels * 0.5:
        return False, f"largest component is only {largest/total_pixels:.0%} of pixels — likely multiple characters"

    # If there's a second component that's >20% of the largest, it's probably another character
    if len(component_sizes) > 1 and component_sizes[1] > largest * 0.2:
        return False, f"second component is {component_sizes[1]/largest:.0%} of main — likely multiple characters"

    return True, "single character"


def generate_frame(pipe, job: str, animation: str, seed: int = None,
                   ref_palette: set = None, max_retries: int = 3,
                   identity_embeds=None, use_pixeloe: bool = True,
                   pixeloe_quant: bool = False) -> Image.Image:
    """Generate a single sprite frame with auto-retry on bad generations."""
    prompt = build_prompt(job, animation)

    if seed is None:
        seed = torch.randint(0, 2**32, (1,)).item()

    for attempt in range(max_retries):
        current_seed = seed + (attempt * 7919)  # prime offset for retries
        generator = torch.Generator("cuda").manual_seed(current_seed)

        if attempt > 0:
            print(f"  Retry {attempt}/{max_retries} with seed={current_seed}...")
        else:
            print(f"  Generating {job}/{animation} (seed={current_seed})...")

        # Build generation kwargs
        gen_kwargs = dict(
            prompt=prompt,
            negative_prompt=NEGATIVE_PROMPT,
            num_inference_steps=40,
            guidance_scale=9.0,
            width=768,
            height=768,
            generator=generator,
        )

        # Add identity lock if available
        if identity_embeds is not None:
            gen_kwargs["ip_adapter_image_embeds"] = identity_embeds

        result = pipe(**gen_kwargs).images[0]

        # Pixelize
        print(f"  Pixelizing (PixelOE={'on' if use_pixeloe else 'off'}, quant={pixeloe_quant})...")
        pixelized = pixelize_frame(result, use_pixeloe=use_pixeloe, pixeloe_quant=pixeloe_quant)

        # Remove background
        print(f"  Removing background...")
        transparent = remove_background(pixelized)

        # Center character in frame
        centered = center_character(transparent)

        # Validate single character
        is_valid, reason = validate_single_character(transparent)
        if is_valid:
            print(f"  Validated: {reason}")
            break
        else:
            print(f"  REJECTED: {reason}")
            if attempt == max_retries - 1:
                print(f"  Using last attempt despite validation failure")

    # Return the transparent (bg-removed) image — centering happens in generate_strip
    return transparent, current_seed


def _measure_char_height(img: Image.Image) -> int:
    """Measure the height of the character (bounding box of opaque pixels)."""
    arr = np.array(img)
    mask = arr[:, :, 3] > 10
    if not mask.any():
        return 0
    ys = np.where(mask.any(axis=1))[0]
    return ys[-1] - ys[0] + 1 if len(ys) > 0 else 0


def generate_strip(pipe, job: str, animation: str, n_frames: int,
                   base_seed: int = None, ref_palette: set = None,
                   identity_embeds=None, use_pixeloe: bool = True,
                   pixeloe_quant: bool = False) -> Image.Image:
    """Generate a full animation strip with size-normalized frames."""
    raw_frames = []
    seeds = []

    if base_seed is None:
        base_seed = torch.randint(0, 2**32, (1,)).item()

    # Pass 1: Generate all raw frames (transparent, not yet centered)
    for i in range(n_frames):
        frame, seed = generate_frame(
            pipe, job, animation,
            seed=base_seed + i,
            ref_palette=None,  # palette snap after centering
            identity_embeds=identity_embeds,
            use_pixeloe=use_pixeloe,
            pixeloe_quant=pixeloe_quant,
        )
        raw_frames.append(frame)
        seeds.append(seed)

    # Pass 2: Measure all character heights and normalize to median
    heights = [_measure_char_height(f) for f in raw_frames]
    valid_heights = [h for h in heights if h > 20]
    if valid_heights:
        target_h = int(np.median(valid_heights))
        print(f"  Heights: {heights} → normalizing to {target_h}px")
    else:
        target_h = None

    # Pass 3: Center all frames at normalized height, then palette snap
    frames = []
    for frame in raw_frames:
        centered = center_character(frame, target_char_h=target_h)
        if ref_palette:
            centered = snap_to_palette(centered, ref_palette)
        frames.append(np.array(centered))
        seeds.append(seed)

    # Concatenate horizontally
    strip = np.concatenate(frames, axis=1)
    return Image.fromarray(strip), seeds


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
    args = parser.parse_args()

    output_dir = Path(args.output) if args.output else OUTPUT_DIR / args.job
    output_dir.mkdir(parents=True, exist_ok=True)

    # Reference palette loaded after hero generation (uses hero colors, not fighter)

    # Load pipeline
    use_ipadapter = not args.no_ipadapter
    pipe = load_pipeline(use_ipadapter=use_ipadapter)

    if use_ipadapter:
        pipe.set_ip_adapter_scale(args.ipadapter_scale)
        print(f"IP-Adapter scale set to {args.ipadapter_scale}")

    # Generate or load reference hero image for identity lock
    identity_embeds = None
    if use_ipadapter and IPADAPTER_WEIGHTS.exists():
        if args.reference_image:
            ref_img = Image.open(args.reference_image).convert("RGB")
            print(f"Using provided reference: {args.reference_image}")
        else:
            # Auto-generate a hero frame as reference (disable IP-Adapter for this)
            hero_seed = args.seed if args.seed else 42
            print(f"\nGenerating hero reference frame (seed={hero_seed})...")
            gen = torch.Generator("cuda").manual_seed(hero_seed)
            prompt = build_prompt(args.job, "idle")
            # Temporarily zero out IP-Adapter so we can generate without image_embeds
            pipe.set_ip_adapter_scale(0.0)
            ref_img = pipe(
                prompt=prompt,
                negative_prompt=NEGATIVE_PROMPT,
                num_inference_steps=40,
                guidance_scale=9.0,
                width=768,
                height=768,
                generator=gen,
                ip_adapter_image=Image.new("RGB", (768, 768), (128, 128, 128)),
            ).images[0]
            # Restore IP-Adapter scale
            pipe.set_ip_adapter_scale(args.ipadapter_scale)
            hero_path = output_dir / "hero_reference.png"
            ref_img.save(hero_path)
            print(f"  Hero saved: {hero_path}")

        identity_embeds = compute_identity_embeddings(pipe, ref_img)
        # Save embeddings for reuse
        embeds_path = output_dir / "identity_embeds.pt"
        torch.save(identity_embeds, embeds_path)
        print(f"  Identity embeddings saved: {embeds_path}")

    # Extract palette from hero reference (uses the character's own colors, not fighter)
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

        for v in range(args.variations):
            seed = (args.seed + v * 1000) if args.seed else None
            strip, seeds = generate_strip(
                pipe, args.job, anim, n_frames, seed, ref_palette,
                identity_embeds=identity_embeds,
                use_pixeloe=not args.no_pixelize,
                pixeloe_quant=args.pixeloe_quant,
            )

            suffix = f"_v{v}" if args.variations > 1 else ""
            out_path = output_dir / f"{anim}{suffix}.png"
            strip.save(out_path)
            print(f"  Saved: {out_path} ({strip.size[0]}x{strip.size[1]}, seeds={seeds})")

    # Save generation metadata
    meta = {
        "job": args.job,
        "tier": "T1",
        "generator": "gen_sprite_sdxl.py",
        "model": "SDXL 1.0 + pixel-art-xl LoRA + IP-Adapter Plus Face",
        "ip_adapter_scale": args.ipadapter_scale if use_ipadapter else None,
        "animations": {anim: str(output_dir / f"{anim}.png") for anim in animations},
    }
    meta_path = output_dir / "generation_meta.json"
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"\nMetadata: {meta_path}")

    # Run linter on output
    print(f"\n{'='*60}")
    print("Running sprite linter on generated output...")
    print(f"{'='*60}")
    os.system(f"python3 {PROJECT_DIR}/tools/sprite_linter.py {output_dir} --reference {REFERENCE_DIR}")


if __name__ == "__main__":
    main()
