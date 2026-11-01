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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--style", nargs="+", choices=sorted(KINDS) + [k + "_front" for k in KINDS], help="stage style tiles for these kinds")
    args = ap.parse_args()
    for k in args.style or []:
        print(f"staged {generate(k).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
