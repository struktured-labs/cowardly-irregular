import numpy as np
import torch
from PIL import Image

from .config import FRAME_W, FRAME_H
from .prompts import build_prompt, get_negative_prompt
from .postprocess import pixelize_frame, downscale_to_pixel_art, remove_background, center_character, _measure_char_height, snap_to_palette
from .validation import validate_single_character


def generate_frame(
    pipe,
    job: str,
    animation: str,
    seed: int = None,
    ref_palette: set = None,
    max_retries: int = 3,
    identity_embeds=None,
    use_pixeloe: bool = True,
    pixeloe_quant: bool = False,
    controlnet_image: Image.Image = None,
    controlnet_scale: float = 0.6,
    direct_downscale: bool = False,
) -> tuple:
    """Generate a single sprite frame with auto-retry on bad generations.

    controlnet_image: Optional pose skeleton PIL Image for ControlNet conditioning.
    controlnet_scale: ControlNet conditioning scale (0.0-1.0).
    Returns (transparent_image, seed_used).
    """
    prompt = build_prompt(job, animation)

    if seed is None:
        seed = torch.randint(0, 2**32, (1,)).item()

    for attempt in range(max_retries):
        current_seed = seed + (attempt * 7919)
        generator = torch.Generator("cuda").manual_seed(current_seed)

        if attempt > 0:
            print(f"  Retry {attempt}/{max_retries} with seed={current_seed}...")
        else:
            print(f"  Generating {job}/{animation} (seed={current_seed})...")

        gen_kwargs = dict(
            prompt=prompt,
            negative_prompt=get_negative_prompt(job),
            num_inference_steps=40,
            guidance_scale=9.0,
            width=768,
            height=768,
            generator=generator,
        )

        if identity_embeds is not None:
            gen_kwargs["ip_adapter_image_embeds"] = identity_embeds

        if controlnet_image is not None:
            gen_kwargs["image"] = controlnet_image
            gen_kwargs["controlnet_conditioning_scale"] = controlnet_scale

        result = pipe(**gen_kwargs).images[0]

        if direct_downscale:
            print(f"  Direct downscale 768→{FRAME_W} (LANCZOS, no quantize)...")
            pixelized = result.resize((FRAME_W, FRAME_H), Image.LANCZOS)
        elif not use_pixeloe:
            print(f"  Smart downscale 768→{FRAME_W} (BOX + k-means 128 colors)...")
            pixelized = downscale_to_pixel_art(result, target_size=FRAME_W, num_colors=128)
        else:
            print(f"  Pixelizing (PixelOE, quant={pixeloe_quant})...")
            pixelized = pixelize_frame(result, use_pixeloe=use_pixeloe, pixeloe_quant=pixeloe_quant)

        print(f"  Removing background...")
        transparent = remove_background(pixelized)

        centered = center_character(transparent)

        is_valid, reason = validate_single_character(transparent)
        if is_valid:
            print(f"  Validated: {reason}")
            break
        else:
            print(f"  REJECTED: {reason}")
            if attempt == max_retries - 1:
                print(f"  Using last attempt despite validation failure")

    return transparent, current_seed


def generate_strip(
    pipe,
    job: str,
    animation: str,
    n_frames: int,
    base_seed: int = None,
    ref_palette: set = None,
    identity_embeds=None,
    use_pixeloe: bool = True,
    pixeloe_quant: bool = False,
    controlnet_images: list = None,
    controlnet_scale: float = 0.6,
    direct_downscale: bool = False,
) -> tuple:
    """Generate a full animation strip with size-normalized frames.

    controlnet_images: Optional list of pose skeleton PIL Images, one per frame.
                       If shorter than n_frames, missing entries default to None.
    Returns (strip_image, seeds_list).
    """
    raw_frames = []
    seeds = []

    if base_seed is None:
        base_seed = torch.randint(0, 2**32, (1,)).item()

    if controlnet_images is None:
        controlnet_images = []

    for i in range(n_frames):
        pose_img = controlnet_images[i] if i < len(controlnet_images) else None
        frame, seed = generate_frame(
            pipe, job, animation,
            seed=base_seed + i,
            ref_palette=None,
            identity_embeds=identity_embeds,
            use_pixeloe=use_pixeloe,
            pixeloe_quant=pixeloe_quant,
            controlnet_image=pose_img,
            controlnet_scale=controlnet_scale,
            direct_downscale=direct_downscale,
        )
        raw_frames.append(frame)
        seeds.append(seed)

    heights = [_measure_char_height(f) for f in raw_frames]
    valid_heights = [h for h in heights if h > 20]
    if valid_heights:
        target_h = int(np.median(valid_heights))
        print(f"  Heights: {heights} -> normalizing to {target_h}px")
    else:
        target_h = None

    frames = []
    for frame in raw_frames:
        centered = center_character(frame, target_char_h=target_h)
        if ref_palette:
            centered = snap_to_palette(centered, ref_palette)
        frames.append(np.array(centered))

    strip = np.concatenate(frames, axis=1)
    return Image.fromarray(strip), seeds
