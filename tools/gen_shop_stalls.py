#!/usr/bin/env python3
"""Draw the open-air shop STALLS a VillageShop stands as when no drawn building hosts it (T1).

struktured 2026-11-01 (relayed, cowir-main 21164), on the Harmonia pilot shots: "notice that crappy looking little what
looks like black magic shop ... and to the right of that I think is the holy magic but it's the wrong color set". A
VillageShop that no building block covers draws a procedural 2x2 awning stall; this tool draws the real ones, one per
shop type, in a palette that reads at a glance. VillageShop looks up prop_art "shop_stall_<type>_<world>" (world-keyed
ONLY, so a village in another world keeps its painted stall until that world's art exists) and stands the art with its
base where the painted stall's base was.

Staged under tmp/shop_stalls/; --deploy copies to assets/sprites/props/<world>/shop_stall_<type>.png.

Usage:
    set -a; . ./setenv.sh; set +a
    uv run python tools/gen_shop_stalls.py                    # stage all four (medieval)
    uv run python tools/gen_shop_stalls.py --deploy
"""
from __future__ import annotations

import argparse
import base64
import io
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_village_buildings import key_out  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
STAGE = ROOT / "tmp/shop_stalls"
MODEL = "gpt-image-2"
WIDTH = 72  # a little over the stall's 2-tile footprint, so the awning overhangs it
COLOURS = 64

STYLE = ("A single 16-bit SNES-era JRPG pixel-art OBJECT for a medieval fantasy village, seen straight-on from the front "
         "and a little above, like the market stalls in classic Square RPG towns: crisp dark outlines, rich shading, warm "
         "light, a limited palette. Only the stall, whole and centred, standing on nothing: no ground, no shadow on the "
         "ground, no people, no text or letters. The background is one flat, solid, pure magenta (#FF00FF) colour with "
         "no gradient.")

STALLS = {
    "white_magic": ("A holy magic stall: a white canvas awning with gold trim and pale blue stripes on carved white "
                    "wooden posts, a round golden SUN emblem sign on top, a white-clothed table with lit white candles, "
                    "a silver chalice, a stack of white-bound tomes and pale blue glass vials. Bright, clean and sacred."),
    "black_magic": ("A dark magic stall: a deep purple and black awning with tattered edges on black posts, a crystal orb "
                    "on a stand glowing arcane GREEN, a skull candle, chained grimoires and green rune light. Shadowy and "
                    "ominous."),
    "item": ("A potion and supplies stall: a green and cream striped awning on wooden posts, a table of coloured potion "
             "bottles, bundles of herbs and a basket of bread, a small crate beside it."),
    "blacksmith": ("A smithy stall: a dark canvas awning on sturdy posts, an anvil, a rack of swords and an axe, a round "
                   "shield and a small brazier of glowing coals."),
}
WORLD = "medieval"


def key_all_magenta(img: Image.Image, tol: int = 110) -> Image.Image:
    """Clear backdrop magenta the border flood cannot reach: a stall's frame encloses the backdrop behind its counter.

    No purple-cast greying (the props tool's see-through fix): the dark-magic stall is purple on purpose, and its
    purples sit far from #FF00FF, so only true backdrop pixels go."""
    import numpy as np
    a = np.array(img.convert("RGBA"))
    d = np.sqrt(((a[:, :, :3].astype(float) - np.array([255.0, 0.0, 255.0])) ** 2).sum(axis=2))
    a[d < tol, 3] = 0
    return Image.fromarray(a, "RGBA")


def draw(key: str) -> Path:
    from openai import OpenAI
    r = OpenAI().images.generate(model=MODEL, prompt=f"{STYLE}\n\nThe stall: {STALLS[key]}", size="1024x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json))).convert("RGBA")
    STAGE.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / f"{key}_raw.png")
    img = key_all_magenta(key_out(raw))
    obj = img.crop(img.split()[3].point(lambda v: 255 if v >= 128 else 0).getbbox())
    obj = obj.resize((WIDTH, max(1, round(obj.height * WIDTH / obj.width))), Image.LANCZOS)
    rgb = obj.convert("RGB").quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGBA")
    rgb.putalpha(obj.split()[3].point(lambda v: 255 if v >= 128 else 0))
    dst = STAGE / f"{key}.png"
    rgb.save(dst)
    return dst


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("stalls", nargs="*")
    ap.add_argument("--deploy", action="store_true")
    args = ap.parse_args()
    for k in args.stalls or sorted(STALLS):
        if k not in STALLS:
            raise SystemExit(f"unknown stall {k}")
        if args.deploy:
            dst = ROOT / f"assets/sprites/props/{WORLD}/shop_stall_{k}.png"
            dst.write_bytes((STAGE / f"{k}.png").read_bytes())
            print(f"deployed {dst.relative_to(ROOT)}")
        else:
            print(f"staged {draw(k).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
