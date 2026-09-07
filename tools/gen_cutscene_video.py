#!/usr/bin/env python3
"""
Cutscene Video Generator for Cowardly Irregular
================================================
Animates pixel art backdrops into short cutscene video clips using
self-hosted AI video generation models on RTX 3090 (24GB VRAM).

Supported backends:
  - cogvideox  : CogVideoX-5b-I2V (text-guided, ~5GB INT8)
  - svd        : SVD-XT (image-only, <8GB, best pixel preservation)

Usage:
  python tools/gen_cutscene_video.py --backdrop prologue_forest --prompt "gentle wind, leaves rustling"
  python tools/gen_cutscene_video.py --backdrop cave_entrance --backend svd
  python tools/gen_cutscene_video.py --all --prompt "subtle ambient motion"

Output:
  assets/cutscene_videos/<backdrop_name>.mp4
"""

import argparse
import sys
from pathlib import Path
from typing import Optional

import numpy as np
from PIL import Image

# Paths
PROJECT_ROOT = Path(__file__).resolve().parent.parent
BACKDROP_DIR = PROJECT_ROOT / "assets" / "cutscene_backdrops"
OUTPUT_DIR = PROJECT_ROOT / "assets" / "cutscene_videos"
TMP_DIR = PROJECT_ROOT / "tmp"


def list_backdrops() -> list[str]:
    """List all available backdrop names (without extension)."""
    return sorted(
        p.stem for p in BACKDROP_DIR.glob("*.png")
        if not p.name.endswith(".import")
    )


def load_backdrop(name: str) -> Image.Image:
    """Load a backdrop PNG by name."""
    path = BACKDROP_DIR / f"{name}.png"
    if not path.exists():
        raise FileNotFoundError(f"Backdrop not found: {path}")
    return Image.open(path).convert("RGB")


def postprocess_pixel_art(
    frames: list[Image.Image],
    target_size: tuple[int, int],
    palette_image: Optional[Image.Image] = None,
) -> list[Image.Image]:
    """
    Post-process generated frames to preserve pixel art aesthetic.

    1. Downscale to target pixel art resolution (nearest-neighbor)
    2. Optionally snap colors to source palette
    3. Re-upscale with nearest-neighbor for crisp pixels
    """
    processed = []
    display_scale = 2  # 2x upscale for final output

    # Extract palette from source image if provided
    source_colors = None
    if palette_image is not None:
        arr = np.array(palette_image)
        pixels = arr.reshape(-1, 3)
        # Get unique colors
        source_colors = np.unique(pixels, axis=0)

    for frame in frames:
        # Step 1: Downscale to native pixel art resolution
        small = frame.resize(target_size, Image.Resampling.NEAREST)

        # Step 2: Palette snap (optional)
        if source_colors is not None:
            arr = np.array(small, dtype=np.float32)
            h, w, c = arr.shape
            flat = arr.reshape(-1, 3)

            # Find nearest palette color for each pixel
            dists = np.sum(
                (flat[:, np.newaxis, :] - source_colors[np.newaxis, :, :]) ** 2,
                axis=2,
            )
            nearest_idx = np.argmin(dists, axis=1)
            snapped = source_colors[nearest_idx].reshape(h, w, 3).astype(np.uint8)
            small = Image.fromarray(snapped)

        # Step 3: Re-upscale for display
        display_size = (target_size[0] * display_scale, target_size[1] * display_scale)
        crisp = small.resize(display_size, Image.Resampling.NEAREST)
        processed.append(crisp)

    return processed


def generate_cogvideox(
    image: Image.Image,
    prompt: str,
    negative_prompt: str,
    num_frames: int = 49,
    num_steps: int = 50,
    guidance_scale: float = 6.0,
    seed: int = 42,
    use_int8: bool = False,
) -> list[Image.Image]:
    """Generate video frames using CogVideoX-5b-I2V."""
    import torch
    from diffusers import CogVideoXImageToVideoPipeline

    model_id = "THUDM/CogVideoX-5b-I2V"
    print(f"Loading {model_id}...")

    if use_int8:
        try:
            from diffusers import AutoencoderKLCogVideoX, CogVideoXTransformer3DModel
            from transformers import T5EncoderModel
            from torchao.quantization import quantize_, int8_weight_only

            text_encoder = T5EncoderModel.from_pretrained(
                model_id, subfolder="text_encoder", torch_dtype=torch.bfloat16
            )
            quantize_(text_encoder, int8_weight_only())

            transformer = CogVideoXTransformer3DModel.from_pretrained(
                model_id, subfolder="transformer", torch_dtype=torch.bfloat16
            )
            quantize_(transformer, int8_weight_only())

            vae = AutoencoderKLCogVideoX.from_pretrained(
                model_id, subfolder="vae", torch_dtype=torch.bfloat16
            )
            quantize_(vae, int8_weight_only())

            pipe = CogVideoXImageToVideoPipeline.from_pretrained(
                model_id,
                text_encoder=text_encoder,
                transformer=transformer,
                vae=vae,
                torch_dtype=torch.bfloat16,
            )
        except ImportError:
            print("INT8 quantization unavailable, falling back to BF16...")
            use_int8 = False

    if not use_int8:
        pipe = CogVideoXImageToVideoPipeline.from_pretrained(
            model_id, torch_dtype=torch.bfloat16
        )

    # Use sequential offload for minimal VRAM (works even with other GPU processes)
    pipe.enable_sequential_cpu_offload()
    pipe.vae.enable_tiling()
    pipe.vae.enable_slicing()

    # CogVideoX expects 720x480 for the base model
    image_resized = image.resize((720, 480), Image.Resampling.LANCZOS)

    print(f"Generating {num_frames} frames ({num_frames/8:.1f}s @ 8fps)...")
    generator = torch.Generator(device="cpu").manual_seed(seed)

    output = pipe(
        prompt=prompt,
        negative_prompt=negative_prompt,
        image=image_resized,
        num_videos_per_prompt=1,
        num_inference_steps=num_steps,
        num_frames=num_frames,
        guidance_scale=guidance_scale,
        generator=generator,
    ).frames[0]

    # Convert to PIL images
    return [frame if isinstance(frame, Image.Image) else Image.fromarray(frame) for frame in output]


def generate_svd(
    image: Image.Image,
    num_frames: int = 25,
    motion_bucket_id: int = 40,
    noise_aug_strength: float = 0.02,
    fps: int = 7,
    seed: int = 42,
) -> list[Image.Image]:
    """Generate video frames using SVD-XT (no text prompt, image-only)."""
    import torch
    from diffusers import StableVideoDiffusionPipeline

    model_id = "stabilityai/stable-video-diffusion-img2vid-xt"
    print(f"Loading {model_id}...")

    pipe = StableVideoDiffusionPipeline.from_pretrained(
        model_id, torch_dtype=torch.float16, variant="fp16"
    )
    pipe.enable_model_cpu_offload()

    # SVD expects 1024x576
    image_resized = image.resize((1024, 576), Image.Resampling.LANCZOS)

    print(f"Generating {num_frames} frames (motion={motion_bucket_id})...")
    generator = torch.manual_seed(seed)

    output = pipe(
        image_resized,
        decode_chunk_size=8,
        generator=generator,
        num_frames=num_frames,
        fps=fps,
        motion_bucket_id=motion_bucket_id,
        noise_aug_strength=noise_aug_strength,
    ).frames[0]

    return [frame if isinstance(frame, Image.Image) else Image.fromarray(frame) for frame in output]


def export_video(frames: list[Image.Image], output_path: Path, fps: int = 8):
    """Export frames to MP4 using imageio."""
    import imageio.v3 as iio

    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Convert PIL images to numpy arrays
    frame_arrays = [np.array(f) for f in frames]

    iio.imwrite(
        str(output_path),
        frame_arrays,
        fps=fps,
        codec="libx264",
        plugin="pyav",
    )
    print(f"Exported: {output_path} ({len(frames)} frames, {fps}fps, {len(frames)/fps:.1f}s)")


def generate_backdrop_video(
    backdrop_name: str,
    prompt: Optional[str] = None,
    backend: str = "cogvideox",
    seed: int = 42,
    skip_postprocess: bool = False,
    palette_snap: bool = True,
):
    """Generate a cutscene video from a backdrop image."""
    print(f"\n{'='*60}")
    print(f"Generating: {backdrop_name} (backend={backend})")
    print(f"{'='*60}")

    # Load source
    source_image = load_backdrop(backdrop_name)
    native_size = source_image.size  # Original pixel art dimensions
    print(f"Source: {native_size[0]}x{native_size[1]}")

    # Default prompts per backdrop (can be overridden)
    default_prompts = {
        "prologue_forest": "gentle wind blowing through forest trees, leaves rustling, dappled sunlight shifting",
        "prologue_village": "quiet village scene, chimney smoke drifting, flickering window lights",
        "cave_entrance": "dark cave entrance, flickering torchlight, subtle shadow movement, dust motes",
        "throne_room": "grand throne room, torch flames flickering, curtains swaying gently",
        "steampunk_airship": "airship in flight, clouds drifting past, propellers spinning, steam venting",
        "steampunk_workshop": "workshop with gears turning, steam rising, sparks from welding",
        "suburban_neighborhood": "quiet suburban street, trees swaying in breeze, clouds drifting",
        "suburban_park": "park scene, grass swaying, birds flying overhead, peaceful",
        "suburban_school": "school building, flag waving, students walking",
        "industrial_factory": "factory with smoke stacks, machinery running, conveyor belts moving",
        "industrial_furnace": "blazing furnace, flames dancing, heat shimmer, molten metal glow",
        "vertex_village": "peaceful village, wind chimes, laundry flapping on lines",
        "node_prime": "futuristic node with pulsing energy, holographic displays flickering",
        "mechanism_interior": "clockwork mechanism, gears turning, pistons moving rhythmically",
        "director_office": "office scene, papers rustling in breeze, ceiling fan spinning",
        "maple_heights_street": "autumn street, falling leaves, street lamps flickering on",
        "calibrant_desk": "desk with papers, candle flame flickering, ink drying",
        "community_center": "community gathering space, warm lighting, gentle activity",
        "rivet_row_factory": "industrial row, smokestacks billowing, workers moving about",
        "brasston_square": "town square, fountain flowing, pigeons, people milling about",
    }

    if prompt is None:
        prompt = default_prompts.get(backdrop_name, "subtle ambient motion, gentle lighting changes")

    # Style anchoring for pixel art
    style_prefix = "pixel art, 16-bit SNES style, retro game scene, pixelated, "
    style_suffix = ", sharp pixel edges, no anti-aliasing"
    full_prompt = style_prefix + prompt + style_suffix
    negative_prompt = "smooth, realistic, 3D, anti-aliased, blurry, HD, photorealistic, modern, high resolution photograph"

    print(f"Prompt: {prompt}")

    # Generate
    if backend == "cogvideox":
        frames = generate_cogvideox(
            image=source_image,
            prompt=full_prompt,
            negative_prompt=negative_prompt,
            num_frames=49,  # 6s @ 8fps
            seed=seed,
        )
        fps = 8
    elif backend == "svd":
        frames = generate_svd(
            image=source_image,
            num_frames=25,  # 3.5s @ 7fps
            motion_bucket_id=40,  # Low motion for pixel art
            noise_aug_strength=0.02,
            seed=seed,
        )
        fps = 7
    else:
        raise ValueError(f"Unknown backend: {backend}")

    # Post-process to preserve pixel art
    if not skip_postprocess:
        print("Post-processing for pixel art preservation...")
        frames = postprocess_pixel_art(
            frames,
            target_size=native_size,
            palette_image=source_image if palette_snap else None,
        )

    # Export
    output_path = OUTPUT_DIR / f"{backdrop_name}.mp4"
    export_video(frames, output_path, fps=fps)

    # Also save a raw (unprocessed) version for comparison
    if not skip_postprocess:
        raw_path = TMP_DIR / "cutscene_raw" / f"{backdrop_name}_raw.mp4"
        raw_path.parent.mkdir(parents=True, exist_ok=True)
        # Re-generate would be wasteful, so we skip raw export unless debugging

    return output_path


def main():
    parser = argparse.ArgumentParser(
        description="Generate cutscene videos from pixel art backdrops"
    )
    parser.add_argument(
        "--backdrop", type=str,
        help="Backdrop name (e.g., prologue_forest). Use --list to see all."
    )
    parser.add_argument(
        "--all", action="store_true",
        help="Generate videos for all backdrops"
    )
    parser.add_argument(
        "--list", action="store_true",
        help="List all available backdrops"
    )
    parser.add_argument(
        "--prompt", type=str, default=None,
        help="Motion prompt (overrides default). Only used with cogvideox backend."
    )
    parser.add_argument(
        "--backend", type=str, default="cogvideox",
        choices=["cogvideox", "svd"],
        help="Video generation backend (default: cogvideox)"
    )
    parser.add_argument(
        "--seed", type=int, default=42,
        help="Random seed for reproducibility"
    )
    parser.add_argument(
        "--no-postprocess", action="store_true",
        help="Skip pixel art post-processing"
    )
    parser.add_argument(
        "--no-palette-snap", action="store_true",
        help="Skip palette color snapping"
    )

    args = parser.parse_args()

    if args.list:
        backdrops = list_backdrops()
        print(f"Available backdrops ({len(backdrops)}):")
        for name in backdrops:
            print(f"  - {name}")
        return

    if not args.backdrop and not args.all:
        parser.print_help()
        sys.exit(1)

    # Ensure output dirs exist
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    TMP_DIR.mkdir(parents=True, exist_ok=True)

    if args.all:
        backdrops = list_backdrops()
        print(f"Generating videos for {len(backdrops)} backdrops...")
        for name in backdrops:
            try:
                generate_backdrop_video(
                    backdrop_name=name,
                    prompt=args.prompt,
                    backend=args.backend,
                    seed=args.seed,
                    skip_postprocess=args.no_postprocess,
                    palette_snap=not args.no_palette_snap,
                )
            except Exception as e:
                print(f"ERROR generating {name}: {e}")
                continue
    else:
        generate_backdrop_video(
            backdrop_name=args.backdrop,
            prompt=args.prompt,
            backend=args.backend,
            seed=args.seed,
            skip_postprocess=args.no_postprocess,
            palette_snap=not args.no_palette_snap,
        )


if __name__ == "__main__":
    main()
