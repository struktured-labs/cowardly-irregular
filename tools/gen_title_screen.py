#!/usr/bin/env python3
"""
Generate title screen key art for Cowardly Irregular.

Approach: generate a large portrait-orientation pixel art scene using SDXL + v2 LoRA.
The game logo text is rendered separately via PIL so it's crisp and readable.

Output:
  - key_art.png (960x720) — the illustrated background scene
  - logo.png (512x128)    — stylized game title with drop shadow
  - title_screen.png (960x720) — composite of key art + logo
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

import torch
from PIL import Image, ImageDraw, ImageFont, ImageFilter

sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.pipeline.loader import load_pipeline

PROJECT = Path(__file__).parent.parent
OUTPUT_DIR = PROJECT / "tmp" / "generated" / "title_screen"
GAME_UI = Path("/home/struktured/projects/cowardly-irregular/assets/sprites/ui")

KEY_ART_PROMPT = (
    "epic 16-bit JRPG title screen key art, pixel art, silhouette of 5 heroes "
    "standing on a cliff edge at dusk looking over sprawling medieval valley below, "
    "distant castle on far mountain, dramatic purple and orange sunset sky with stars, "
    "wisps of clouds, cinematic wide shot, heroic composition, jrpg_pixel_style, "
    "16-bit SNES style, Final Fantasy VI / Chrono Trigger aesthetic"
)

KEY_ART_NEGATIVE = (
    "ui, text, title, logo, hud, menu, close-up face, "
    "blurry, photorealistic, 3D, modern, realistic photo"
)


def generate_key_art(pipe, seed: int = 7777):
    gen = torch.Generator("cuda").manual_seed(seed)
    result = pipe(
        prompt=KEY_ART_PROMPT,
        negative_prompt=KEY_ART_NEGATIVE,
        num_inference_steps=40,
        guidance_scale=8.5,
        width=1024,
        height=576,
        generator=gen,
        ip_adapter_image=Image.new("RGB", (1024, 576), (128, 128, 128)),
    ).images[0]

    # Upscale/resize to 960x540 (16:9) for title screen
    return result.resize((960, 540), Image.LANCZOS)


def make_logo(size=(640, 160)):
    """Generate a stylized 'COWARDLY IRREGULAR' logo with drop shadow + outline."""
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Try multiple font paths
    font_candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]
    font = None
    for f in font_candidates:
        if Path(f).exists():
            try:
                font = ImageFont.truetype(f, size=72)
                break
            except Exception:
                continue
    if font is None:
        font = ImageFont.load_default()

    text_main = "COWARDLY"
    text_sub = "IRREGULAR"

    def text_w(t, fnt):
        bbox = draw.textbbox((0, 0), t, font=fnt)
        return bbox[2] - bbox[0], bbox[3] - bbox[1]

    # Layout
    w_main, h_main = text_w(text_main, font)
    w_sub, h_sub = text_w(text_sub, font)
    x_main = (w - w_main) // 2
    y_main = 8
    x_sub = (w - w_sub) // 2
    y_sub = y_main + h_main + 4

    # Drop shadow
    shadow_color = (0, 0, 0, 180)
    offset = 5
    draw.text((x_main + offset, y_main + offset), text_main, font=font, fill=shadow_color)
    draw.text((x_sub + offset, y_sub + offset), text_sub, font=font, fill=shadow_color)

    # Outline (4-direction)
    outline_color = (30, 20, 10, 255)
    for ox in (-2, 0, 2):
        for oy in (-2, 0, 2):
            if ox or oy:
                draw.text((x_main + ox, y_main + oy), text_main, font=font, fill=outline_color)
                draw.text((x_sub + ox, y_sub + oy), text_sub, font=font, fill=outline_color)

    # Main fill with gradient-ish (warm gold for COWARDLY, silver for IRREGULAR)
    gold = (235, 195, 80, 255)
    silver = (200, 200, 215, 255)
    draw.text((x_main, y_main), text_main, font=font, fill=gold)
    draw.text((x_sub, y_sub), text_sub, font=font, fill=silver)

    return img


def make_composite(key_art, logo, output_path):
    """Composite key art + logo onto final title screen."""
    w, h = key_art.size
    composite = key_art.copy()

    # Slight darken at top for logo legibility
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(overlay)
    for y in range(0, 280):
        alpha = int(140 * (1 - y / 280))
        odraw.rectangle([0, y, w, y + 1], fill=(0, 0, 0, alpha))
    composite = Image.alpha_composite(composite.convert("RGBA"), overlay)

    # Center logo near top
    lw, lh = logo.size
    lx = (w - lw) // 2
    ly = 40
    composite.paste(logo, (lx, ly), logo)

    # Press Start hint at bottom
    font_candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    ]
    hint_font = None
    for f in font_candidates:
        if Path(f).exists():
            try:
                hint_font = ImageFont.truetype(f, size=28)
                break
            except Exception:
                continue

    if hint_font is not None:
        draw = ImageDraw.Draw(composite)
        hint = "PRESS START"
        bbox = draw.textbbox((0, 0), hint, font=hint_font)
        hw = bbox[2] - bbox[0]
        hx = (w - hw) // 2
        hy = h - 80
        # Shadow
        draw.text((hx + 2, hy + 2), hint, font=hint_font, fill=(0, 0, 0, 200))
        # Outline
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                if ox or oy:
                    draw.text((hx + ox, hy + oy), hint, font=hint_font, fill=(20, 20, 20, 255))
        draw.text((hx, hy), hint, font=hint_font, fill=(255, 240, 180, 255))

    composite.save(output_path)
    return composite


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=7777)
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--skip-key-art", action="store_true",
                        help="Skip SDXL generation, use existing key_art.png")
    args = parser.parse_args()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    key_art_path = OUTPUT_DIR / "key_art.png"
    logo_path = OUTPUT_DIR / "logo.png"
    title_path = OUTPUT_DIR / "title_screen.png"

    if args.skip_key_art and key_art_path.exists():
        print(f"Loading existing key art: {key_art_path}")
        key_art = Image.open(key_art_path)
    else:
        print("Loading SDXL + v2 LoRA...")
        pipe = load_pipeline(use_ipadapter=True, lora_mode="style", use_controlnet=False)
        pipe.set_ip_adapter_scale(0.0)
        print("\nGenerating key art...")
        key_art = generate_key_art(pipe, args.seed)
        key_art.save(key_art_path)
        print(f"  Saved: {key_art_path}")

    print("\nGenerating logo...")
    logo = make_logo()
    logo.save(logo_path)
    print(f"  Saved: {logo_path}")

    print("\nCompositing title screen...")
    make_composite(key_art, logo, title_path)
    print(f"  Saved: {title_path}")

    if args.install:
        GAME_UI.mkdir(parents=True, exist_ok=True)
        shutil.copy2(title_path, GAME_UI / "title_screen.png")
        shutil.copy2(logo_path, GAME_UI / "logo.png")
        shutil.copy2(key_art_path, GAME_UI / "title_key_art.png")
        print(f"\n  Installed to {GAME_UI}")


if __name__ == "__main__":
    main()
