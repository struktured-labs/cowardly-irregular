#!/usr/bin/env python3
"""Draw STYLE TILES for the interior rework: one whole-room mockup per room, for approval before the real tiles/props.

struktured 2026-11-01 (relayed, cowir-main 21096/21097/21101): "the inside of village houses and shops need a major
sprite rework ... use songmaster for influence again (but the inside of shops)". A style tile is a CONCEPT, not shipped
art: it fixes the look (wall height and texture, floor, counter, shelving, clutter, light) at the room's real size and
layout, so the per-tile floor/wall art and the per-piece furniture that follow (through cowir-overworld's InteriorArt
seam) are drawn to an approved target.

The Song Master references are described in words only and are never passed to the model: we take their qualities
(3/4 top-down room, a tall textured back wall with shelves on it, plank or cobble floor, furniture with volume, a
counter that reads as a counter, warm and dense but legible), never their assets.

Staged under tmp/interior_style/ at the room's pixel size (ShopInterior is 16x12 tiles of 32px = 512x384).

Usage:
    set -a; . ./setenv.sh; set +a
    uv run python tools/gen_interior_style_tiles.py harmonia_item_shop harmonia_arms_shop
"""
from __future__ import annotations

import argparse
import base64
import io
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
STAGE = ROOT / "tmp/interior_style"
MODEL = "gpt-image-2"
COLOURS = 96

STYLE = ("A 16-bit SNES-era JRPG pixel-art INTERIOR, seen from above at a 3/4 angle like the towns of classic Square "
         "RPGs: the whole room fills the frame edge to edge, a TALL back wall with real height and texture along the top "
         "of the picture, thick outer walls framing the room, the floor seen from above. Crisp dark outlines, rich "
         "hand-pixeled detail, warm saturated colours, soft lantern light, furniture with volume and cast shadows. Dense "
         "and lived-in but readable: every object is clear. Original art: no text, no letters, no logos, no UI, NO people "
         "or creatures (the game places its own characters).")

## The room's real layout, so the mockup can be laid over the playable grid (ShopInterior.SHOP_LAYOUT).
SHOP_LAYOUT = ("The room is 16 tiles wide and 12 tall. The back wall spans the top row. A shop COUNTER, three tiles wide "
               "and two deep, stands just below the back wall in the top centre, with the shopkeeper's side behind it. "
               "Two tall display blocks, each three tiles wide, stand against the left wall and two against the right "
               "wall, upper and middle. The lower third of the room is open floor, and the ENTRANCE door is in the middle "
               "of the bottom wall.")

ROOMS = {
    "harmonia_item_shop": ("Mystic Remedies, the village item and potion shop. Warm honey-coloured wood-plank floor with "
                           "a deep green woven rug before the counter. The back wall is timber-framed plaster with "
                           "floor-to-ceiling shelves CROWDED with coloured potion bottles, jars, wrapped herbs and "
                           "scrolls; bundles of drying herbs hang from a beam. The counter is dark polished wood with "
                           "a brass scale, a ledger and a bell on it. Side displays: wooden cabinets of labelled-looking "
                           "(but letterless) bottles, baskets of roots and mushrooms, a small cauldron. Crates and a "
                           "barrel by the door, a hanging lantern, a window letting in a shaft of daylight."),
    "harmonia_arms_shop": ("The village weapon and armour shop with a smithy at the back. Grey cobblestone floor with a "
                           "worn red rug before the counter. The back wall is heavy stone with a glowing forge and "
                           "chimney hood on one side and wall racks of swords, axes and spears on the other; shields "
                           "hang on hooks. The counter is a thick oak slab with an anvil-shaped paperweight, a whetstone "
                           "and a helmet on it. Side displays: armour on wooden mannequin stands, a barrel of spears, a "
                           "rack of bows, a grindstone. Coal sacks and an iron-banded chest by the door, iron lanterns, "
                           "warm orange forge light against cool stone."),
}

SIZES = {"harmonia_item_shop": (512, 384), "harmonia_arms_shop": (512, 384)}


def draw(key: str) -> Path:
    from openai import OpenAI
    r = OpenAI().images.generate(model=MODEL, prompt=f"{STYLE}\n\n{SHOP_LAYOUT}\n\nThe room: {ROOMS[key]}",
                                 size="1536x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json))).convert("RGB")
    STAGE.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / f"{key}_raw.png")
    w, h = SIZES[key]
    ch = round(raw.width * h / w)  # centre-crop the 3:2 paint to the room's 4:3
    if ch > raw.height:
        cw = round(raw.height * w / h)
        raw = raw.crop(((raw.width - cw) // 2, 0, (raw.width + cw) // 2, raw.height))
    else:
        raw = raw.crop((0, (raw.height - ch) // 2, raw.width, (raw.height + ch) // 2))
    out = raw.resize((w, h), Image.LANCZOS).quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGB")
    dst = STAGE / f"{key}.png"
    out.save(dst)
    return dst


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rooms", nargs="*")
    args = ap.parse_args()
    for k in args.rooms or sorted(ROOMS):
        if k not in ROOMS:
            raise SystemExit(f"unknown room {k}")
        print(f"staged {draw(k).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
