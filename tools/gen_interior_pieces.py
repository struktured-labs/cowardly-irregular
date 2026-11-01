#!/usr/bin/env python3
"""Cut and draw the real interior pieces from an APPROVED style tile (cowir-main 21147), for the InteriorArt seam.

The style tile (docs/art/interiors/<room>.png, tools/gen_interior_style_tiles.py) fixes the look at the room's real
size. The room's layout and collisions stay authoritative, so the art arrives as separate pieces:
- FLOOR and WALL come straight out of the approved tile, cut at a patch that shows only that surface and made to repeat
  (floor: a 32px tile that wraps both ways; wall: a strip, 32px wide by the wall's height, that wraps sideways).
  Cutting rather than redrawing means the shipped surfaces ARE the approved ones.
- FURNITURE (counter, displays, ...) is redrawn as an isolated piece on magenta by gpt-image-2, with the style tile
  as the image reference, keyed out and fitted to its footprint width. A piece may stand taller than its footprint;
  how much is the seam's rule, not this tool's.
Staged under tmp/interior_pieces/<room>/; nothing is registered until the seam's keys land.

Usage:
    set -a; . ./setenv.sh; set +a
    uv run python tools/gen_interior_pieces.py harmonia_item_shop
"""
from __future__ import annotations

import argparse
import base64
import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_village_buildings import key_out  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
STYLE_DIR = ROOT / "docs/art/interiors"
STAGE = ROOT / "tmp/interior_pieces"
MODEL = "gpt-image-2"
TILE = 32
COLOURS = 64

## Where each surface is cut from its style tile, in style-tile pixels (= game pixels).
## floor: one 32x32 patch showing only floor. wall: a 32px column and the horizontal BANDS stacked top to bottom into
## the strip. A bare wall cuts as one band; a wall the style tile covers with racks (the arms shop) is built from its
## coping band plus a bare stone course repeated, so every pixel is still the approved tile's own.
SURFACES = {
    "harmonia_item_shop": {"floor": (150, 280, 32, 32), "wall": (440, [(6, 56)])},
    "harmonia_arms_shop": {"floor": (300, 255, 32, 32), "wall": (400, [(4, 22), (22, 36), (22, 36), (22, 36)])},
}

PIECE_STYLE = ("Redraw ONE piece of furniture from the reference room, in exactly that room's 16-bit SNES JRPG pixel-art "
               "style, palette, outline weight and lighting, seen from the same 3/4 top-down angle. Only that object, "
               "whole and uncropped, standing on nothing. No floor, no rug, no wall, no shadow on the ground, no people, "
               "no text. The background is one flat, solid, pure magenta (#FF00FF) colour with no gradient.")

## room -> piece -> (footprint width in tiles, what to draw)
PIECES = {
    "harmonia_item_shop": {
        "counter": (3, "The shop counter: a dark polished wooden counter seen from the customer's side, with a brass "
                       "scale, an open ledger and a small bell on its top."),
        "display_tall": (3, "A tall wooden shelving unit crowded with coloured potion bottles and jars on three shelves, "
                            "with baskets of roots and herbs on the bottom shelf."),
        "display_low": (3, "A low wooden display cabinet with drawers, its top crowded with potion bottles, jars and a "
                           "basket of mushrooms."),
    },
    "harmonia_arms_shop": {
        "counter": (3, "The shop counter: a thick oak slab counter seen from the customer's side, with a steel "
                       "helmet, a whetstone and an anvil-shaped paperweight on its top."),
        "display_tall": (3, "A row of three suits of armour on wooden mannequin stands, steel, bronze and chainmail."),
        "display_low": (3, "A low wooden rack holding three longbows and a quiver of arrows."),
    },
}


def wrap_seamless(patch: Image.Image, axes: tuple) -> Image.Image:
    """Blend a patch with its half-offset copy along the given axes, so it repeats without a visible seam."""
    a = np.asarray(patch.convert("RGB"), float)
    out = a.copy()
    h, w = a.shape[:2]
    if 1 in axes:
        rolled = np.roll(out, w // 2, axis=1)
        r = np.abs(np.linspace(-1.0, 1.0, w))
        wgt = np.clip(1.0 - r, 0.0, 1.0)[None, :, None] ** 0.7
        out = out * wgt + rolled * (1.0 - wgt)
    if 0 in axes:
        rolled = np.roll(out, h // 2, axis=0)
        r = np.abs(np.linspace(-1.0, 1.0, h))
        wgt = np.clip(1.0 - r, 0.0, 1.0)[:, None, None] ** 0.7
        out = out * wgt + rolled * (1.0 - wgt)
    return Image.fromarray(out.astype(np.uint8))


def surfaces(room: str) -> list:
    """The style tile is already at game scale (32px per tile), so surfaces are CUT at size, never resized."""
    tile = Image.open(STYLE_DIR / f"{room}.png").convert("RGB")
    x, y, w, h = SURFACES[room]["floor"]
    floor = wrap_seamless(tile.crop((x, y, x + w, y + h)), (0, 1))
    x, bands = SURFACES[room]["wall"]
    parts = [tile.crop((x, y0, x + TILE, y1)) for y0, y1 in bands]
    wall = Image.new("RGB", (TILE, sum(pt.height for pt in parts)))
    y = 0
    for pt in parts:
        wall.paste(pt, (0, y))
        y += pt.height
    wall = wrap_seamless(wall, (1,))
    out = []
    for name, img in (("floor", floor), ("wall", wall)):
        dst = STAGE / room / f"{name}.png"
        dst.parent.mkdir(parents=True, exist_ok=True)
        img.quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGBA").save(dst)
        out.append(dst)
    return out


def _png(img: Image.Image):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    buf.seek(0)
    return ("reference.png", buf, "image/png")


def piece(room: str, name: str) -> Path:
    from openai import OpenAI
    width, what = PIECES[room][name]
    ref = Image.open(STYLE_DIR / f"{room}.png").convert("RGB")
    r = OpenAI().images.edit(model=MODEL, image=[_png(ref)], prompt=f"{PIECE_STYLE}\n\nThe piece: {what}",
                             size="1024x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json))).convert("RGBA")
    dst = STAGE / room / f"{name}.png"
    dst.parent.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / room / f"{name}_raw.png")
    img = key_out(raw)
    box = img.split()[3].point(lambda v: 255 if v >= 128 else 0).getbbox()
    obj = img.crop(box)
    w = width * TILE
    obj = obj.resize((w, max(1, round(obj.height * w / obj.width))), Image.LANCZOS)
    rgb = obj.convert("RGB").quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGBA")
    rgb.putalpha(obj.split()[3].point(lambda v: 255 if v >= 128 else 0))
    rgb.save(dst)
    return dst


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rooms", nargs="+")
    ap.add_argument("--only", nargs="*", help="limit to these pieces (floor/wall/counter/...)")
    args = ap.parse_args()
    for room in args.rooms:
        if room not in PIECES:
            raise SystemExit(f"unknown room {room}")
        if not args.only or {"floor", "wall"} & set(args.only):
            for p in surfaces(room):
                print(f"staged {p.relative_to(ROOT)}")
        for name in PIECES[room]:
            if args.only and name not in args.only:
                continue
            print(f"staged {piece(room, name).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
