#!/usr/bin/env python3
"""Regen bard's battle victory animation anchored to the artist bard.

Live playtest finding (user): victory.png is un-anchored April AI art
that reads as a random male character. Bard's artist canon (idle/cast/
attack, T2, from Bard Base sprite.aseprite) shows an orange-ponytail
female bard in crimson-and-plum leather with a piano-key scythe
instrument.

One gpt-image-1 call → 2×2 contact sheet of 4 victory poses sharing
identity → 4-frame 1024×256 strip matching the existing victory.png
shape. Artist files (idle/cast/attack) untouched.

Usage:
    uv run python tools/regen_bard_victory.py [--quality high]
"""
import argparse
import base64
import io
import os
import shutil
import sys
from pathlib import Path

from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
BARD_DIR = GAME_REPO / "assets" / "sprites" / "jobs" / "bard"
OUT_TMP = PROJECT / "tmp" / "bard_victory_regen"
OUT_TMP.mkdir(parents=True, exist_ok=True)

PROMPT = (
    "16-bit JRPG pixel-art battle sprite contact sheet. 2×2 grid layout, "
    "four VICTORY CELEBRATION poses of the SAME character — identical "
    "identity, palette, size, and lineart weight across all four tiles. "
    "Character (copy the reference sprite exactly): young female bard with "
    "long orange hair in a loose ponytail, crimson-and-plum leather doublet "
    "with dark purple accents, holding her piano-key-bladed scythe "
    "instrument. "
    "Top-left: triumphant pose, instrument raised overhead with one arm. "
    "Top-right: joyful strum flourish on the instrument, sparkle notes. "
    "Bottom-left: confident hip-cocked pose, instrument resting on shoulder. "
    "Bottom-right: mid-jump heel-click celebration, hair swinging. "
    "Match the reference's clean pixel-art shading discipline: bold "
    "outlines, soft cel shading, no anti-aliasing artifacts, no floating "
    "pixels, no duplicate limbs. Fully transparent background, no scenery, "
    "no shadows, no text. Each pose centered in its quadrant."
)


def load_ref() -> bytes:
    """Artist bard idle frame 0 as the identity anchor."""
    idle = Image.open(BARD_DIR / "idle.png").convert("RGBA")
    frame = idle.crop((0, 0, 256, 256))
    big = frame.resize((1024, 1024), Image.NEAREST)
    buf = io.BytesIO()
    big.save(buf, format="PNG")
    return buf.getvalue()


def downscale(tile: Image.Image, target: int = 256) -> Image.Image:
    img = tile.convert("RGBA")
    img = img.resize((target * 2, target * 2), Image.LANCZOS)
    img = img.resize((target, target), Image.BOX)
    return img


def make_transparent(img: Image.Image, threshold: int = 240) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return img


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="high")
    args = ap.parse_args()

    client = OpenAI()
    print(f"[bard victory] gpt-image-1 ({args.quality})")
    resp = client.images.edit(
        model="gpt-image-1",
        image=[("ref_bard_idle.png", load_ref(), "image/png")],
        prompt=PROMPT,
        size="1024x1024",
        quality=args.quality,
        n=1,
    )
    raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json))).convert("RGBA")
    raw.save(OUT_TMP / "victory_raw.png")

    half = 512
    tiles = [
        raw.crop((0, 0, half, half)),
        raw.crop((half, 0, 1024, half)),
        raw.crop((0, half, half, 1024)),
        raw.crop((half, half, 1024, 1024)),
    ]
    tiles = [make_transparent(downscale(t, 256)) for t in tiles]

    strip = Image.new("RGBA", (1024, 256), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        # 1px bob on odd frames — keeps idle-diff-class tests happy
        if i % 2 == 1:
            b = Image.new("RGBA", t.size, (0, 0, 0, 0))
            b.paste(t, (0, 1), t)
            t = b
        strip.paste(t, (i * 256, 0), t)

    out = BARD_DIR / "victory.png"
    backup = BARD_DIR / "victory.pre_artist_anchor.png"
    if not backup.exists():
        shutil.copy2(out, backup)
    strip.save(out)
    print(f"  → {out.relative_to(GAME_REPO)} (backup: {backup.name})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
