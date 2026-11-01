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

## seam room -> piece -> (footprint (cols, rows), style tile, what to draw). Shelves are drawn STOCKED: one shelf_goods
## sprite cannot sit on both the 3-row and the 2-row unit, so a room whose shelf is drawn skips its painted goods.
PIECES = {
    "shop_item": {
        "counter": ((3, 2), "harmonia_item_shop",
                    "The shop counter seen from the customer's side and a little above: a dark polished wooden counter "
                    "with panelled front, a brass scale, an open ledger and a small bell on its top."),
        "shelf_tall": ((3, 3), "harmonia_item_shop",
                       "A tall wooden shelving unit seen straight-on, its three shelves crowded with coloured potion bottles, "
                       "jars and bundles of herbs, with a cupboard base."),
        "shelf_low": ((3, 2), "harmonia_item_shop",
                      "A low wooden display cabinet seen straight-on, drawers below and its top crowded with potion bottles, "
                      "jars and a basket of mushrooms."),
    },
    "shop_blacksmith": {
        "counter": ((3, 2), "harmonia_arms_shop",
                    "The shop counter seen from the customer's side and a little above: a thick oak slab counter with "
                    "iron-banded front, a steel helmet, a whetstone and an anvil-shaped paperweight on its top."),
        "shelf_tall": ((3, 3), "harmonia_arms_shop",
                       "A tall dark wooden weapon rack seen straight-on, holding swords, a spear, an axe and a round shield, "
                       "on an iron-bound base."),
        "shelf_low": ((3, 2), "harmonia_arms_shop",
                      "A low sturdy wooden armour bench seen straight-on, with iron corners, a breastplate, a pair of "
                      "gauntlets and a steel helmet laid on its top."),
    },
}


def wrap_seamless(patch: Image.Image, axes: tuple, band: int = 12) -> Image.Image:
    """Make a patch repeat without a seam, blending only a narrow BAND at each wrapped edge.

    Near an edge the pixels come from the half-offset copy, whose edges are the original's middle and so continue
    across the wrap. Blending only the band keeps the interior crisp: a whole-tile blend averaged two copies into
    every pixel and turned cobble to mud (measured on the arms shop's floor)."""
    a = np.asarray(patch.convert("RGB"), float)
    out = a.copy()
    h, w = a.shape[:2]

    def ramp(n: int) -> np.ndarray:
        d = np.minimum(np.arange(n), np.arange(n)[::-1]).astype(float)  # distance to the nearer edge
        return np.clip(d / band, 0.0, 1.0)

    if 1 in axes:
        wgt = ramp(w)[None, :, None]
        out = out * wgt + np.roll(out, w // 2, axis=1) * (1.0 - wgt)
    if 0 in axes:
        wgt = ramp(h)[:, None, None]
        out = out * wgt + np.roll(out, h // 2, axis=0) * (1.0 - wgt)
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


def key_all_magenta(img: Image.Image, tol: int = 110) -> Image.Image:
    """Clear backdrop magenta the border flood cannot reach (a scale's pans, a rack's frame enclose it)."""
    a = np.array(img.convert("RGBA"))
    d = np.sqrt(((a[:, :, :3].astype(float) - np.array([255.0, 0.0, 255.0])) ** 2).sum(axis=2))
    a[d < tol, 3] = 0
    return Image.fromarray(a, "RGBA")


def piece(room: str, name: str) -> Path:
    """One footprint piece: drawn isolated, keyed, fitted to its footprint, composited on the room's floor pattern
    (a counter or shelf CELL replaces the floor, so nothing may stay transparent), then rolled so each cell lands
    where the seam samples it."""
    from openai import OpenAI
    (cols, rows), style, what = PIECES[room][name]
    raw_path = STAGE / room / f"{name}_raw.png"
    raw_path.parent.mkdir(parents=True, exist_ok=True)
    if not raw_path.exists():
        ref = Image.open(STYLE_DIR / f"{style}.png").convert("RGB")
        r = OpenAI().images.edit(model=MODEL, image=[_png(ref)], prompt=f"{PIECE_STYLE}\n\nThe piece: {what}",
                                 size="1024x1024", n=1)
        Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json))).convert("RGBA").save(raw_path)
    img = key_all_magenta(key_out(Image.open(raw_path).convert("RGBA")))
    obj = img.crop(img.split()[3].point(lambda v: 255 if v >= 128 else 0).getbbox())
    w, h = cols * TILE, rows * TILE
    s = min(w / obj.width, h / obj.height)
    obj = obj.resize((max(1, round(obj.width * s)), max(1, round(obj.height * s))), Image.LANCZOS)
    obj.putalpha(obj.split()[3].point(lambda v: 255 if v >= 128 else 0))
    floor = Image.open(STAGE / room / "floor.png").convert("RGBA")
    cell = Image.new("RGBA", (w, h))
    for y in range(0, h, floor.height):
        for x in range(0, w, floor.width):
            cell.alpha_composite(floor, (x, y))
    cell.alpha_composite(obj, ((w - obj.width) // 2, h - obj.height))
    dst = STAGE / room / f"{name}.png"
    cell.convert("RGB").quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGBA").save(dst)
    return dst


## Where each tile kind's cells sit in ShopInterior.SHOP_LAYOUT, so a piece can be rolled into the seam's sampling:
## the seam reads cell (x mod cols, y mod rows), so a piece whose top-left is at (7, 3) must start at pattern cell
## (7 mod 3, 3 mod 2) = (1, 1).
COUNTER_AT = (7, 3)
SHELF_TALL_ROWS = (2, 4)
SHELF_LOW_ROWS = (6, 7)
SHELF_COL = 2  # the left blocks start at col 2; the right ones at col 11, and 11 mod 3 == 2 mod 3


def counter_pattern(room: str) -> Path:
    art = Image.open(piece(room, "counter")).convert("RGBA")
    ox, oy = COUNTER_AT[0] % 3, COUNTER_AT[1] % 2
    rolled = np.roll(np.asarray(art), (oy * TILE, ox * TILE), axis=(0, 1))
    dst = STAGE / room / "counter_pattern.png"
    Image.fromarray(rolled, "RGBA").save(dst)
    return dst


def shelf_pattern(room: str) -> Path:
    """One 3x6 image serves both display heights: the tall unit on rows 2-4 and the low unit on rows 6-7 (= 0-1 mod 6)."""
    tall = Image.open(piece(room, "shelf_tall")).convert("RGBA")
    low = Image.open(piece(room, "shelf_low")).convert("RGBA")
    pat = Image.new("RGBA", (3 * TILE, 6 * TILE))
    pat.paste(Image.open(STAGE / room / "floor.png").convert("RGBA").crop((0, 0, 3 * TILE, TILE)), (0, 5 * TILE))
    pat.paste(tall, (0, (SHELF_TALL_ROWS[0] % 6) * TILE))
    pat.paste(low, (0, (SHELF_LOW_ROWS[0] % 6) * TILE))
    ox = SHELF_COL % 3
    pat = Image.fromarray(np.roll(np.asarray(pat), ox * TILE, axis=1), "RGBA")
    dst = STAGE / room / "shelf_pattern.png"
    pat.save(dst)
    return dst


def floor_pattern(room: str) -> Path:
    from PIL import ImageEnhance
    recipe, style, arg = FLOORS[room]
    tile = Image.open(STYLE_DIR / f"{style}.png").convert("RGB")
    out_dir = STAGE / room
    out_dir.mkdir(parents=True, exist_ok=True)
    if recipe == "strips":
        pat = Image.new("RGB", (PATTERN, PATTERN))
        for i in range(PATTERN // TILE):
            x, y = arg[i % len(arg)]
            row = np.roll(np.asarray(tile.crop((x, y, x + PATTERN, y + TILE))), i * 44, axis=1)
            pat.paste(Image.fromarray(row), (0, i * TILE))
        pat = wrap_seamless(pat, (0, 1))
    else:
        raw_path = out_dir / "floor_raw.png"
        if not raw_path.exists():
            from openai import OpenAI
            r = OpenAI().images.edit(model=MODEL, image=[_png(tile)], prompt=FLOOR_REDRAW, size="1024x1024", n=1)
            Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json))).convert("RGB").save(raw_path)
        raw = Image.open(raw_path).convert("RGB")
        m = round(raw.width * (1.0 - arg) / 2)
        pat = wrap_seamless(raw.crop((m, m, raw.width - m, raw.height - m)).resize((PATTERN, PATTERN), Image.LANCZOS), (0, 1))
        pat = ImageEnhance.Contrast(pat).enhance(1.15)
    dst = out_dir / "floor.png"
    pat.quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGBA").save(dst)
    return dst


## Wall cells (the room's W cells: sides and bottom) as a 128x32 pattern cut from the approved tile, wrapped both ways
## since side walls stack it vertically: (style tile, x, y).
WALLS = {
    "shop_item": ("harmonia_item_shop", 380, 4),      # timber frame and plaster from the back wall's right end
    "shop_blacksmith": ("harmonia_arms_shop", 0, 342),  # dressed stone from the front wall, clear of its lanterns
}
## The back wall (InteriorArt back_wall: base-centred on the bottom of row 0, rising above the map edge), cut at full
## room width from the approved tile's top band: (style tile, y0, y1). The item shop stops above its shelf tops; the
## smithy keeps the forge hood, the racks' upper half and the shields, and skips the ceiling dark at the very top.
BACK_WALLS = {
    "shop_item": ("harmonia_item_shop", 0, 58),
    "shop_blacksmith": ("harmonia_arms_shop", 8, 72),
}


def walls(room: str) -> list:
    out_dir = STAGE / room
    out_dir.mkdir(parents=True, exist_ok=True)
    style, x, y = WALLS[room]
    tile = Image.open(STYLE_DIR / f"{style}.png").convert("RGB")
    wall = wrap_seamless(tile.crop((x, y, x + PATTERN, y + TILE)), (0, 1))
    wall.quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGBA").save(out_dir / "wall.png")
    style, y0, y1 = BACK_WALLS[room]
    tile = Image.open(STYLE_DIR / f"{style}.png").convert("RGB")
    back = tile.crop((0, y0, tile.width, y1))
    back.quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGBA").save(out_dir / "back_wall.png")
    return [out_dir / "wall.png", out_dir / "back_wall.png"]


## staged file -> seam kind. Registered as "<kind>_<room>_<village>": the pilot village only, so every other village's
## (and world's) shop keeps its painter until it is drawn.
DEPLOY = {"floor": "floor", "wall": "wall", "counter_pattern": "counter", "shelf_pattern": "shelf", "back_wall": "back_wall"}
NOTES = {
    "floor": "a 4x4 floor PATTERN cut from the approved style tile, edge-band wrapped",
    "wall": "a wall PATTERN cut from the approved style tile",
    "counter": "the 3x2 counter, drawn stocked on the room's floor, rolled to the seam's (x mod 3, y mod 2) sampling",
    "shelf": "a 3x6 shelf PATTERN: the tall stocked unit on rows 2-4, the low one on rows 0-1 (= layout rows 6-7)",
    "back_wall": "the room-wide back wall strip cut from the approved style tile",
}


def deploy(room: str, village: str) -> list:
    import hashlib
    import json
    manifest_path, ledger_path = ROOT / "data/sprite_manifest.json", ROOT / "data/artist_sprite_ledger.json"
    manifest, ledger = json.loads(manifest_path.read_text()), json.loads(ledger_path.read_text())
    out = []
    for staged, kind in DEPLOY.items():
        rel = f"assets/sprites/interiors/{village}/{kind}_{room}.png"
        dst = ROOT / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes((STAGE / room / f"{staged}.png").read_bytes())
        manifest["prop_art"][f"{kind}_{room}_{village}"] = {
            "path": f"res://{rel}", "tier": "T1",
            "source": f"gpt-image-2 + cut, {NOTES[kind]} (struktured 2026-11-01: the inside of village houses and shops "
                      f"need a major sprite rework) -- tools/gen_interior_pieces.py; T1, artist veto applies."}
        ledger[rel] = hashlib.sha256(dst.read_bytes()).hexdigest()
        out.append(dst)
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    ledger_path.write_text(json.dumps(ledger, indent=1, sort_keys=True) + "\n")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rooms", nargs="+")
    ap.add_argument("--deploy", metavar="VILLAGE", help="copy the staged pieces in and register them for this village")
    ap.add_argument("--pieces", action="store_true", help="draw the counter and shelf PATTERNS for these seam rooms")
    ap.add_argument("--floors", action="store_true", help="build the 4x4 floor PATTERNS for these seam rooms (FLOORS)")
    ap.add_argument("--only", nargs="*", help="limit to these pieces (floor/wall/counter/...)")
    args = ap.parse_args()
    if args.deploy:
        for room in args.rooms:
            for d in deploy(room, args.deploy):
                print(f"deployed {d.relative_to(ROOT)}")
        return 0
    if args.pieces:
        for room in args.rooms:
            for fn in (counter_pattern, shelf_pattern):
                print(f"staged {fn(room).relative_to(ROOT)}")
        return 0
    if args.floors:
        for room in args.rooms:
            print(f"staged {floor_pattern(room).relative_to(ROOT)}")
            for w in walls(room):
                print(f"staged {w.relative_to(ROOT)}")
        return 0
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
