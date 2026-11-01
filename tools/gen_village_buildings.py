#!/usr/bin/env python3
"""Draw detailed 3/4-view village BUILDING facades (T1) to replace the procedural blocks VillageProp paints.

struktured 2026-11-01 (via cowir-main): "did the village changes land with the buildings redrawn? i dont see
anything substantial" -- he wants the Song Master DX village feel: hand-pixeled facades with textured, overhanging
shingle or thatch roofs, timber frames, stone footings, shuttered windows with sills, hanging signs, flower boxes,
chimneys. Each building is drawn by gpt-image-2 on a flat magenta backdrop (the model refuses
background=transparent), keyed by a border flood, cropped, scaled so its WIDTH spans its block (TILE px per tile)
and palette-reduced. Staged under tmp/village_buildings/; nothing is written into assets until --deploy, and that
never overwrites an existing file.

Usage:
    set -a; . ./setenv.sh; set +a
    uv run python tools/gen_village_buildings.py --style house shop inn       # stage style tiles
    uv run python tools/gen_village_buildings.py --w1 [keys] [--deploy]      # the other W1 villages
    uv run python tools/gen_village_buildings.py --suburban [keys] [--deploy]  # W2 Maple Heights
"""
from __future__ import annotations

import argparse
import base64
import io
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
STAGE = ROOT / "tmp/village_buildings"
MODEL = "gpt-image-2"
TILE = 32
COLOURS = 40

STYLE = ("A single detailed 16-bit SNES-era JRPG pixel-art BUILDING for a medieval fantasy village, drawn in a "
         "three-quarter top-down view like the towns of classic Square RPGs: the front wall faces the viewer and the "
         "roof is seen from above at an angle. Rich hand-pixeled detail: a textured roof with visible shingle or "
         "thatch rows and an overhanging eave, timber framing, a stone footing, windows with sills and shutters, "
         "a wooden front door at the bottom centre. Crisp dark outline, warm limited palette, soft top-left lighting. "
         "No people, no text or letters, no ground, no grass, no shadow on the ground, nothing else in the picture. "
         "The background is one flat, solid, pure magenta (#FF00FF) colour with no gradient. The building fills the "
         "frame and is centred.")

FRONT = ("Draw it STRAIGHT-ON and symmetric, like the towns of Final Fantasy VI: the front wall faces the viewer "
         "squarely, the roof is seen from above and in front, no side wall is visible and nothing is drawn at a corner angle.")

KINDS = {
    "house": "A cosy two-storey village cottage: red clay shingle roof with a brick chimney, cream plaster walls in "
             "dark timber framing, a flower box of red flowers under one window.",
    "shop": "A village item shop: blue slate roof, a striped cloth awning over the front window, a hanging wooden "
            "sign with a pictured potion bottle (no letters), crates and a barrel by the door.",
    "inn": "A welcoming village inn, a little wider than a house: thatched straw roof with two dormer windows, warm "
           "lit windows, a hanging wooden sign with a pictured mug and a sleeping slime (no letters), a lantern by "
           "the door, flower boxes.",
}


## Harmonia, one entry per building block (HarmoniaVillage.BUILDING_ART): key -> (width in tiles, what it is).
HARMONIA = {
    "harmonia_library": (3, "The town library: a two-storey building of pale cut stone with a grey slate roof, tall arched "
                            "windows, ivy climbing one corner, and a hanging sign with a pictured open book (no letters)."),
    "harmonia_arcana": (3, "A magic shop: a violet-tiled roof with a small dormer, a hanging sign with a pictured crescent "
                           "moon and star, crystal orbs and spell scrolls in the front window, wisteria over the door."),
    "harmonia_arms": (3, "A weapon and armour shop and smithy, wider than it is tall, with a small attic window in a dark "
                         "slate roof and a stone chimney, a hanging sign with a pictured sword and shield (no letters), "
                         "a weapon rack and an anvil by the door."),
    "harmonia_inn": (3, "The Sleepy Slime Inn: thatched straw roof with two dormer windows, warm lit windows, a hanging "
                        "sign with a pictured mug and a sleeping slime (no letters), a lantern by the door, flower boxes."),
    "harmonia_remedies": (3, "Mystic Remedies, an item and potion shop: a green-tiled roof, a striped awning over a window "
                             "full of coloured potion bottles, a hanging sign with a pictured potion (no letters), herb "
                             "pots by the door."),
    "harmonia_chapel": (3, "A small stone village chapel with a short bell tower and a visible bell above the entrance, an "
                           "arched stained-glass window, double wooden doors, a slate roof."),
    "harmonia_tavern": (3, "The Dancing Tonberry tavern: brown shingle roof, warm lit windows, a hanging sign with a pictured "
                           "small hooded creature holding a lantern (no letters), barrels stacked by the door."),
    "harmonia_house": (3, "A modest village cottage: green shingle roof with a brick chimney, cream plaster walls in dark "
                          "timber framing, a flower box of yellow flowers under one window."),
}


## The other W1 villages, same seam (<Village>Village.BUILDING_ART). Ironhaven's forge block is 3x4, still 3 wide.
W1 = {
    "frosthold_lodge": (3, "A snowbound mountain lodge that serves as the inn: a steep roof heavy with snow and icicles on "
                           "the eave, thick log walls, warm lit windows, a hanging sign with a pictured bed (no letters), "
                           "firewood stacked by the door."),
    "frosthold_chapel": (3, "A small frost-covered stone chapel: snow on a steep slate roof, a short bell tower with a "
                            "bell, a round pale-blue stained-glass window, double wooden doors."),
    "frosthold_furs": (3, "A fur trader's hut: snow on a shingle roof, pelts and furs hung on a rack beside the door, a "
                          "hanging sign with a pictured bear paw (no letters), a sled leaning on the wall."),
    "grimhollow_inn": (3, "A gloomy, crooked village inn in a haunted hamlet: a sagging dark shingle roof, a leaning "
                          "chimney, dim greenish lit windows, a hanging sign with a pictured sleeping ghost (no letters), "
                          "a lantern with a pale flame."),
    "grimhollow_chapel": (3, "A decrepit old chapel: cracked grey stone, a broken bell tower with a crooked bell, a "
                             "boarded window, moss and dead vines, a sagging wooden door."),
    "grimhollow_curios": (3, "A cursed curio shop: a purple-black shingle roof, a crooked dormer, a window full of skulls, "
                             "jars and candles, a hanging sign with a pictured eye (no letters), a raven on the sign."),
    "ironhaven_inn": (3, "A sturdy mining-town inn: a dark slate roof, soot-stained brick walls, iron-banded shutters, "
                         "warm lit windows, a hanging sign with a pictured pickaxe and a bed (no letters)."),
    "ironhaven_forge": (3, "The master forge, taller than it is wide: a big stone chimney billowing smoke, a glowing "
                           "furnace mouth by the open door, an anvil and a rack of hammers outside, a dark iron roof, a "
                           "hanging sign with a pictured hammer (no letters)."),
    "ironhaven_steamworks": (3, "A steamworks workshop: riveted iron walls, brass pipes and a pressure gauge on the front, "
                                "two small chimneys venting steam, a big gear over the door, a dark slate roof."),
    "ironhaven_tavern": (3, "A miner's tavern: a low dark shingle roof, rough stone walls, warm lit windows, a hanging "
                            "sign with a pictured mug and a pickaxe (no letters), barrels and a mine cart by the door."),
    "eldertree_inn": (3, "A canopy inn built into the trunk of a giant tree: a round wooden door in the bark, round "
                         "windows with warm light, a leafy roof of branches above, a hanging sign with a pictured leaf "
                         "(no letters), lanterns hung from roots."),
    "sandrift_inn": (3, "An oasis inn in a desert village: sun-baked adobe walls, a flat roof with a striped cloth canopy "
                        "and potted palms, a round arched doorway with a hanging curtain, warm lit windows, a hanging "
                        "sign with a pictured palm tree and a bed (no letters), water jars by the door."),
    "sandrift_bazaar": (3, "A desert bazaar stall-house: sandstone walls, a flat roof under a colourful striped awning, "
                           "rugs and baskets of spices and pottery displayed at the front, a hanging sign with a pictured "
                           "coin (no letters), lanterns."),
}

## W2 suburbia (Maple Heights): same seam, its own style -- a 16-bit 90s-America JRPG town, not a medieval one.
STYLE_SUBURBAN = ("A single detailed 16-bit SNES-era JRPG pixel-art BUILDING for a sunny 1990s American suburb, in the "
                  "style of quirky suburban JRPG towns: a straight-on front view, the roof seen from above and in front. "
                  "Rich hand-pixeled detail: asphalt or clapboard shingles in visible rows, painted siding, white trim, "
                  "windows with shutters or blinds, a front door at the bottom centre with a small step or porch. Crisp dark "
                  "outline, warm saturated palette, soft top-left lighting. No people, no text or letters, no ground, no "
                  "grass, no shadow on the ground, nothing else in the picture. The background is one flat, solid, pure "
                  "magenta (#FF00FF) colour with no gradient. The building fills the frame and is centred.")
SUBURBAN = {
    "maple_garage_sale_house": (3, "A two-storey suburban family house with pale yellow siding and a brown shingle roof, an "
                                   "attached garage with its door open and folding tables of junk for a garage sale in front, "
                                   "a hand-painted cardboard sign with a pictured price tag (no letters)."),
    "maple_mart": (3, "A two-storey suburban convenience mart, taller than it is wide, with an apartment window above: a flat roof with a boxy backlit sign showing a pictured shopping "
                      "basket (no letters), big glass shop windows with posters and shelves visible, a striped awning, a "
                      "newspaper box and an ice chest by the glass door."),
    "maple_moms_house": (3, "A cosy suburban home that rents its guest room: blue siding, a red shingle roof with a dormer, a "
                            "wide covered front porch with a swing and potted ferns, a welcome mat and a little hanging sign "
                            "with a pictured bed and a heart (no letters)."),
    "maple_house": (3, "A tidy two-storey suburban house, taller than it is wide: mint-green siding, a grey shingle roof with a "
                       "chimney, a picture window with flower boxes, a mailbox and a basketball hoop over the front door."),
}
BUILDINGS = {**HARMONIA, **W1, **SUBURBAN}
## Where each pool's art deploys, and the style it is drawn in.
POOLS = {"harmonia": (HARMONIA, "medieval", None), "w1": (W1, "medieval", None), "suburban": (SUBURBAN, "suburban", STYLE_SUBURBAN)}


def key_out(img: Image.Image, tol: int = 90) -> Image.Image:
    """Flood from the border through backdrop-coloured pixels, so magenta INSIDE the building survives."""
    a = np.array(img.convert("RGBA"))
    h, w = a.shape[:2]
    corners = np.array([a[0, 0, :3], a[0, w - 1, :3], a[h - 1, 0, :3], a[h - 1, w - 1, :3]], dtype=float)
    bg = np.median(corners, axis=0)
    near = np.sqrt(((a[:, :, :3].astype(float) - bg) ** 2).sum(axis=2)) < tol
    seen = np.zeros((h, w), bool)
    q = deque([(y, x) for x in range(w) for y in (0, h - 1)] + [(y, x) for y in range(h) for x in (0, w - 1)])
    while q:
        y, x = q.popleft()
        if y < 0 or x < 0 or y >= h or x >= w or seen[y, x] or not near[y, x]:
            continue
        seen[y, x] = True
        q.extend(((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)))
    a[seen, 3] = 0
    return Image.fromarray(a, "RGBA")


def fit(img: Image.Image, width_tiles: int) -> Image.Image:
    """Crop to the building and scale its width to the block it stands on (TILE px per tile)."""
    img = key_out(img)
    alpha = img.split()[3].point(lambda v: 255 if v >= 128 else 0)
    box = alpha.getbbox()
    if box is None:
        raise SystemExit("the model returned an empty image")
    obj = img.crop(box)
    w = width_tiles * TILE
    h = max(1, round(obj.height * w / obj.width))
    obj = obj.resize((w, h), Image.LANCZOS)
    rgb = obj.convert("RGB").quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGB")
    a = obj.split()[3].point(lambda v: 255 if v >= 128 else 0)
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def generate(kind: str, width_tiles: int = 3) -> Path:
    from openai import OpenAI
    base = kind.removesuffix("_front")
    view = f"\n\n{FRONT}" if kind.endswith("_front") else ""
    r = OpenAI().images.generate(model=MODEL, prompt=f"{STYLE}{view}\n\nThe building: {KINDS[base]}", size="1024x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json)))
    STAGE.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / f"{kind}_raw.png")
    out = STAGE / f"{kind}.png"
    fit(raw, width_tiles).save(out)
    return out


def generate_harmonia(key: str, view: str) -> Path:
    """One village building (Harmonia or W1), straight-on ("front", struktured's pick B) or corner-angled ("corner", A)."""
    from openai import OpenAI
    width, what = BUILDINGS[key]
    style = STYLE_SUBURBAN if key in SUBURBAN else STYLE
    face = f"\n\n{FRONT}" if view == "front" else ""
    r = OpenAI().images.generate(model=MODEL, prompt=f"{style}{face}\n\nThe building: {what}", size="1024x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json)))
    STAGE.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / f"{key}_{view}_raw.png")
    out = STAGE / f"{key}_{view}.png"
    fit(raw, width).save(out)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--style", nargs="+", choices=sorted(KINDS) + [k + "_front" for k in KINDS], help="stage style tiles for these kinds")
    ap.add_argument("--harmonia", nargs="*", help="stage these Harmonia buildings (no names = all)")
    ap.add_argument("--w1", nargs="*", help="stage these other-W1-village buildings (no names = all)")
    ap.add_argument("--suburban", nargs="*", help="stage these W2 Maple Heights buildings (no names = all)")
    ap.add_argument("--view", choices=["front", "corner"], default="front", help="straight-on (B, default) or angled (A)")
    ap.add_argument("--deploy", action="store_true", help="copy staged Harmonia art into assets (never overwrites)")
    args = ap.parse_args()
    for k in args.style or []:
        print(f"staged {generate(k).relative_to(ROOT)}")
    for chosen, (pool, world, _) in ((args.harmonia, POOLS["harmonia"]), (args.w1, POOLS["w1"]), (args.suburban, POOLS["suburban"])):
        if chosen is None:
            continue
        for k in chosen or sorted(pool):
            if k not in pool:
                raise SystemExit(f"unknown building {k}")
            if args.deploy:
                src, dst = STAGE / f"{k}_{args.view}.png", ROOT / f"assets/sprites/buildings/{world}/{k}.png"
                if not src.exists():
                    raise SystemExit(f"{k}: nothing staged at {src}")
                if dst.exists():
                    raise SystemExit(f"{k}: {dst} exists; refusing to overwrite")
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_bytes(src.read_bytes())
                print(f"deployed {dst.relative_to(ROOT)} (T1, gpt-image-2, view={args.view})")
            else:
                print(f"staged {generate_harmonia(k, args.view).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
