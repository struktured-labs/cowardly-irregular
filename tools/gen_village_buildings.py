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
    "maple_house": (4, "A wide, tidy suburban ranch house with a low second storey, a little wider than it is tall: mint-green siding, a grey shingle roof with a "
                       "chimney, a picture window with flower boxes, a mailbox and a basketball hoop over the front door."),
}

## W3 steampunk (Brasston): brass, rivets and steam. Its staggered 4x2 blocks want low wide art, or it climbs over row 12.
STYLE_STEAMPUNK = ("A single detailed 16-bit SNES-era JRPG pixel-art BUILDING for a Victorian steampunk city, a straight-on "
                   "front view with the roof seen from above and in front: soot-darkened brick and riveted brass panels, "
                   "copper pipes and pressure gauges, small chimneys or vents puffing steam, arched windows with iron "
                   "frames, a heavy front door at the bottom centre. Crisp dark outline, warm brass-and-brick palette, "
                   "soft top-left lighting. No people, no text or letters, no ground, no shadow on the ground, nothing "
                   "else in the picture. The background is one flat, solid, pure magenta (#FF00FF) colour with no "
                   "gradient. The building fills the frame and is centred.")
STEAMPUNK = {
    "brasston_house": (3, "A narrow two-storey brick townhouse with a brass-trimmed bay window, a copper drainpipe and "
                          "a tall chimney puffing steam."),
    "brasston_forge": (3, "Gearwright's Forge: a brick foundry with a big riveted brass door, a glowing furnace window, a "
                          "large cog mounted on the front wall and a hanging sign with a pictured hammer and gear (no letters)."),
    "brasston_inn": (3, "The Cog & Pillow inn: a cosy brick-and-brass inn with warm lit arched windows, a steam-powered "
                        "clock above the door and a hanging sign with a pictured cog and a pillow (no letters)."),
    "brasston_cottage": (4, "A long, very low, flat-roofed single-storey workshop, three times as wide as it is tall, seen "
                            "almost straight from the front so the roof is a thin strip: a round porthole window, a brass "
                            "door, pipes along the wall, one short stubby vent."),
    "brasston_shed": (4, "A very low single-storey brick boiler shed, about twice as wide as it is tall, with a shallow tin roof, a "
                         "stubby steam vent, pipes along the wall and a small iron door."),
}

## W5 futuristic (NodePrime): a digital city drawn as neon-lit architecture, still 16-bit pixel art.
STYLE_FUTURISTIC = ("A single detailed 16-bit SNES-era JRPG pixel-art BUILDING for a neon cyber city inside a computer, a "
                    "straight-on front view with the roof seen from above and in front: dark glossy panels, glowing cyan "
                    "and magenta neon trim, circuit-trace patterns, holographic screens, a sliding door at the bottom "
                    "centre. Crisp dark outline, deep navy palette with bright neon accents, soft top-left lighting. No "
                    "people, no text or letters, no ground, no shadow on the ground, nothing else in the picture. The "
                    "background is one flat, solid, pure magenta (#FF00FF) colour with no gradient. The building fills "
                    "the frame and is centred.")
FUTURISTIC = {
    "nodeprime_inn": (3, "Sleep.exe, the inn: a tall three-storey capsule hotel, taller than it is wide, with rows of glowing round pod windows, a "
                         "holographic sign with a pictured crescent moon and the letters Z Z Z as shapes (no words), and a "
                         "soft blue-lit sliding door."),
    "nodeprime_cache": (3, "The cache store: a two-storey data shop with a big glass storefront showing glowing floppy "
                           "disks and memory chips on shelves, a holographic sign with a pictured disk (no letters), and "
                           "cooling fans on the roof."),
}

## Village PROPS (struktured 2026-11-01: "any of that old school procgenylooking art needs to go"). Same style and
## straight-on view as the medieval buildings; width in tiles is the prop's drawn width.
STYLE_PROP = ("A single small 16-bit SNES-era JRPG pixel-art OBJECT -- not a building, no walls, no roof, no windows, "
              "no house -- seen from the front and a little above, like the props in the towns of classic Square RPGs. "
              "Rich hand-pixeled detail, crisp dark outline, warm limited palette, soft top-left lighting. No people, no "
              "text or letters, no ground, no grass, no shadow on the ground, nothing else in the picture. The background "
              "is one flat, solid, pure magenta (#FF00FF) colour with no gradient. The object fills the frame and is centred.")
PROPS = {
    "harmonia_fountain": (3, "Harmonia's plaza fountain: a round two-tier carved stone fountain basin, clear blue water "
                             "spilling from the upper bowl into the lower pool, and a small blossoming pink cherry tree "
                             "growing from the centre of the upper tier. Seen straight-on from the front and a little "
                             "above, so the front rim of the basin and the water surface are both visible."),
    "tree_medieval": (1, "A single tall slender village tree, like a poplar or a young cypress, about THREE times taller "
                         "than it is wide: a narrow brown trunk, a tall column of leafy green foliage with clumps of light "
                         "and shadow. It must stay narrow: it stands one step from doorways."),
    "tree_frosthold": (2, "A single snow-laden pine tree: a short dark trunk, layered dark-green boughs heavy with white "
                          "snow, a pointed top. Taller than it is wide."),
    "lamp_post_medieval": (1, "A single tall thin wrought-iron village street lamp: a slim black iron post on a small stone "
                              "base, topped by a four-paned lantern with a warm glowing candle flame. Very tall and narrow."),
    "lamp_post_suburban": (1, "A single tall thin 1990s suburban street lamp: a slim dark-green metal pole on a small concrete "
                              "base, topped by a round frosted-glass globe lamp glowing warm white. Very tall and narrow."),
    "lamp_post_steampunk": (1, "A single tall thin Victorian gas street lamp: a slim fluted brass-and-iron post with rivets, a "
                               "small gauge and a copper pipe, topped by a glass gas lantern glowing amber. Very tall and narrow."),
    "cart_medieval": (2, "A single wooden village hand cart with two big spoked wooden wheels and long handles, loaded with "
                         "a few sacks, a crate and some hay. Seen from the side and slightly above, wider than it is tall."),
    "cart_suburban": (2, "A single 1990s supermarket shopping cart: a silver wire-mesh basket with a red plastic handle on four "
                         "small swivel wheels, empty. Seen from the side and slightly above, wider than it is tall."),
    "cart_steampunk": (2, "A single Victorian steampunk handcart: riveted brass-and-iron body, two spoked iron wheels, a small "
                          "boiler with a pressure gauge and a copper pipe, carrying a crate of gears. Seen from the side and "
                          "slightly above, wider than it is tall."),
    "stall_medieval": (2, "A single small village market stall: a wooden counter under a striped red-and-cream cloth awning on "
                          "two posts, with baskets of apples, bread and pottery on the counter."),
    "stall_steampunk": (2, "A single small Victorian steampunk market stall: a brass-trimmed wooden counter under a riveted "
                           "copper canopy, a little steam pipe, with jars, cogs and pocket watches laid out for sale."),
    "well_medieval": (2, "A single round stone village well: a ring of grey fieldstone, a small peaked wooden roof on two posts "
                         "with a winch, a rope and a wooden bucket."),
    "barrel": (1, "A single sturdy wooden barrel with dark iron hoops, standing upright."),
    "crate": (1, "A single square wooden shipping crate with nailed planks and a darker frame."),
    "planter": (1, "A single wooden half-barrel planter overflowing with green leaves and small red flowers."),
    "planter_suburban": (1, "A single round terracotta flower pot full of bright red geraniums, 1990s front-porch style."),
    "planter_steampunk": (1, "A single riveted copper planter box on little iron feet, holding a small fern."),
    "fence": (1, "One short square section of a rustic wooden village fence, as tall as it is wide: two stout posts and "
                 "two horizontal rails, the rails running all the way off both the left and right edges so sections join."),
    "fence_suburban": (1, "One short square section of a white wooden picket fence, as tall as it is wide: tall pointed white "
                          "pickets on two rails, the rails running off both the left and right edges so sections join."),
    "banner": (1, "A single tall cloth village banner hanging from a wooden pole with a crossbar: deep red cloth with a "
                  "golden crest, a forked bottom edge. Tall and narrow."),
    "banner_steampunk": (1, "A single tall cloth banner hanging from a brass pole with a crossbar: dark green cloth with a "
                            "golden cog emblem, a straight fringed bottom edge. Tall and narrow."),
    "crate_futuristic": (1, "A single sleek sci-fi cargo crate: dark glossy panels with glowing cyan neon trim and a small "
                            "holographic label light (no letters)."),
    "crate_industrial": (1, "A single grey steel industrial shipping crate with riveted corners, a yellow-and-black hazard "
                            "stripe and stencil-style marks (no readable letters)."),
    "barrel_industrial": (1, "A single dented blue steel oil drum with ribbed bands and a small hazard sticker, standing upright."),
}
## See-through props (wire mesh): the border flood cannot reach backdrop enclosed by the wires, so key it everywhere.
KEY_EVERYWHERE = {"cart_suburban", "well_medieval", "fence", "fence_suburban"}
## Props whose art must stand a fixed height: the lamp's light anchor sits 50px above its base (VillageProp), and the
## TREE prop's footprint is 1x3, so 96px.
PROP_HEIGHT = {"lamp_post_medieval": 64, "lamp_post_suburban": 64, "lamp_post_steampunk": 64,
               "banner": 64, "banner_steampunk": 64, "tree_medieval": 96}

## Terrain TILES (32x32, opaque, edge to edge): drawn as a square patch of ground filling the whole frame.
TILE_STYLE = ("A single square 16-bit SNES-era JRPG pixel-art overworld TILE, seen from above at a slight angle, that "
              "fills the ENTIRE square frame edge to edge with no border, no frame and no background colour of its own. "
              "Rich hand-pixeled detail, crisp dark outlines, warm limited palette, soft top-left lighting. No people, "
              "no text.")
TILES = {
    "forest_0": "One round leafy deciduous tree, its canopy filling most of the square, on dark green forest undergrowth "
                "that reaches every edge.",
    "forest_1": "One tall leafy tree with a slightly different, lopsided canopy, on dark green forest undergrowth that "
                "reaches every edge.",
    "snow_tree_0": "One snow-covered pine tree, on white snowy ground with a few dark rocks, the snow reaching every edge.",
    "shade_tree_0": "One broad suburban shade tree with a full, bright summer-green leafy canopy (green, not autumn), "
                    "seen from slightly above, on a neat green lawn that reaches every edge.",
}


def tile_from_raw(raw: Image.Image) -> Image.Image:
    """Trim the model's edge band (it draws a faint frame that reads as a grid when tiled), then scale to one tile."""
    m = round(min(raw.size) * 0.08)
    raw = raw.crop((m, m, raw.width - m, raw.height - m))
    return raw.resize((TILE, TILE), Image.LANCZOS).quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGBA")


## Where each staged tile lands: world sheet, TileType key (":N" = variant N), [col, row] in tile units.
## Row 3 is past the generated cliff/overlay rows; gen_tile_sheet_*.py carry it across a regen.
TILE_SLOTS = {
    "forest_0": ("medieval", "FOREST", [0, 3]),
    "forest_1": ("medieval", "FOREST:1", [1, 3]),
    "snow_tree_0": ("medieval", "SNOW_TREE", [2, 3]),
    "shade_tree_0": ("suburban", "SHADE_TREE", [0, 3]),
}


def deploy_tiles(keys: list) -> None:
    """Paste staged tiles into their world sheet and register them under tile_sheets.<world>.tiles."""
    import json
    mpath = ROOT / "data/sprite_manifest.json"
    man = json.loads(mpath.read_text(encoding="utf-8"))
    for k in keys:
        world, tile_key, (col, row) = TILE_SLOTS[k]
        entry = man["tile_sheets"][world]
        png = ROOT / entry["path"].replace("res://", "")
        sheet = Image.open(png).convert("RGBA")
        if sheet.height < (row + 1) * TILE:
            grown = Image.new("RGBA", (sheet.width, (row + 1) * TILE), (0, 0, 0, 0))
            grown.paste(sheet, (0, 0))
            sheet = grown
        sheet.paste(Image.open(STAGE / f"tile_{k}.png").convert("RGBA"), (col * TILE, row * TILE))
        sheet.save(png)
        entry.setdefault("tiles", {})[tile_key] = [col, row]
        print(f"placed tile_{k} at {world}[{col},{row}] as {tile_key}")
    mpath.write_text(json.dumps(man, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def generate_tile(key: str) -> Path:
    """One opaque 32px terrain tile: no keying, the square is centre-cropped and scaled down."""
    from openai import OpenAI
    r = OpenAI().images.generate(model=MODEL, prompt=f"{TILE_STYLE}\n\nThe tile: {TILES[key]}", size="1024x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json))).convert("RGB")
    STAGE.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / f"tile_{key}_raw.png")
    out = tile_from_raw(raw)
    dst = STAGE / f"tile_{key}.png"
    out.save(dst)
    return dst
## W6 abstract (Vertex): the end of the visual ladder -- minimalist, existential, almost no detail left.
STYLE_ABSTRACT = ("A single 16-bit pixel-art BUILDING for a minimalist, existential last town at the edge of a game "
                  "world, a straight-on front view: pure flat geometric shapes, pale grey and off-white planes, one "
                  "muted accent colour, crisp dark outline, very few details, a plain rectangular doorway at the bottom "
                  "centre. Quiet and slightly uncanny, like a building remembered rather than seen. No people, no text "
                  "or letters, no ground, no shadow on the ground, nothing else in the picture. The background is one "
                  "flat, solid, pure magenta (#FF00FF) colour with no gradient. The building fills the frame and is centred.")
ABSTRACT = {
    "vertex_rest": (2, "The Rest, an inn: a plain pale cube with a single low gabled roof, one small square window glowing a "
                       "soft warm yellow, and a narrow doorway."),
    "vertex_exchange": (2, "The Exchange, a shop: a tall plain pale slab with a flat roof, a single horizontal slot of a "
                           "counter window lit muted teal, and a narrow doorway."),
}
BUILDINGS = {**HARMONIA, **W1, **SUBURBAN, **STEAMPUNK, **FUTURISTIC, **ABSTRACT, **PROPS}
## Where each pool's art deploys, and the style it is drawn in.
POOLS = {"harmonia": (HARMONIA, "medieval", None), "w1": (W1, "medieval", None), "suburban": (SUBURBAN, "suburban", STYLE_SUBURBAN),
         "steampunk": (STEAMPUNK, "steampunk", STYLE_STEAMPUNK), "futuristic": (FUTURISTIC, "futuristic", STYLE_FUTURISTIC),
         "abstract": (ABSTRACT, "abstract", STYLE_ABSTRACT), "props": (PROPS, "../props/medieval", STYLE_PROP)}


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


def drop_key_fringe(img: Image.Image) -> Image.Image:
    """Clear leftover magenta-ish edge pixels the border flood missed (a pink fringe on foliage)."""
    a = np.array(img.convert("RGBA"))
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    a[(r > 150) & (b > 120) & (g < r - 70) & (g < b - 40), 3] = 0
    return Image.fromarray(a, "RGBA")


def key_everywhere(img: Image.Image, tol: int = 110) -> Image.Image:
    """Clear EVERY backdrop-coloured pixel, not just the border-connected ones (for see-through art)."""
    a = np.array(img.convert("RGBA"))
    d = np.sqrt(((a[:, :, :3].astype(float) - np.array([255.0, 0.0, 255.0])) ** 2).sum(axis=2))
    a[d < tol, 3] = 0
    # Thin wires were antialiased against the magenta: pull any purple cast (red AND blue over green) back to grey.
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    cast = (r > g + 20) & (b > g + 20)
    grey = ((r + g + b) // 3).astype(np.uint8)
    for c in range(3):
        a[..., c] = np.where(cast, grey, a[..., c])
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
    return drop_key_fringe(out)


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
    style = next((st for pool, _, st in POOLS.values() if st and key in pool), STYLE)
    face = f"\n\n{FRONT}" if view == "front" else ""
    r = OpenAI().images.generate(model=MODEL, prompt=f"{style}{face}\n\nThe building: {what}", size="1024x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json)))
    STAGE.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / f"{key}_{view}_raw.png")
    if key in KEY_EVERYWHERE:
        raw = key_everywhere(raw)
    out = STAGE / f"{key}_{view}.png"
    img = fit(raw, width)
    if key in PROP_HEIGHT and img.height != PROP_HEIGHT[key]:
        h = PROP_HEIGHT[key]
        img = img.resize((max(1, round(img.width * h / img.height)), h), Image.LANCZOS)
        img.putalpha(img.split()[3].point(lambda v: 255 if v >= 128 else 0))
    img.save(out)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--style", nargs="+", choices=sorted(KINDS) + [k + "_front" for k in KINDS], help="stage style tiles for these kinds")
    ap.add_argument("--harmonia", nargs="*", help="stage these Harmonia buildings (no names = all)")
    ap.add_argument("--w1", nargs="*", help="stage these other-W1-village buildings (no names = all)")
    ap.add_argument("--suburban", nargs="*", help="stage these W2 Maple Heights buildings (no names = all)")
    ap.add_argument("--steampunk", nargs="*", help="stage these W3 Brasston buildings (no names = all)")
    ap.add_argument("--futuristic", nargs="*", help="stage these W5 NodePrime buildings (no names = all)")
    ap.add_argument("--props", nargs="*", help="stage these village props (no names = all)")
    ap.add_argument("--tiles", nargs="*", help="stage these 32px terrain tiles (no names = all)")
    ap.add_argument("--abstract", nargs="*", help="stage these W6 Vertex buildings (no names = all)")
    ap.add_argument("--view", choices=["front", "corner"], default="front", help="straight-on (B, default) or angled (A)")
    ap.add_argument("--deploy", action="store_true", help="copy staged Harmonia art into assets (never overwrites)")
    args = ap.parse_args()
    tile_keys = args.tiles if args.tiles else (sorted(TILES) if args.tiles is not None else [])
    for k in tile_keys:
        if k not in TILES:
            raise SystemExit(f"unknown tile {k}")
    if tile_keys and args.deploy:
        deploy_tiles(tile_keys)
    else:
        for k in tile_keys:
            print(f"staged {generate_tile(k).relative_to(ROOT)}")
    for k in args.style or []:
        print(f"staged {generate(k).relative_to(ROOT)}")
    for chosen, (pool, world, _) in ((args.harmonia, POOLS["harmonia"]), (args.w1, POOLS["w1"]), (args.suburban, POOLS["suburban"]), (args.steampunk, POOLS["steampunk"]),
                                      (args.futuristic, POOLS["futuristic"]),
                                      (args.abstract, POOLS["abstract"]), (args.props, POOLS["props"])):
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
