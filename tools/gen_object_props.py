#!/usr/bin/env python3
"""Draw the small static OBJECT sprites an OverworldNPC with is_object shows instead of a person.

Each object is described from its own dialogue in the game (the room it sits in tells you what it is), drawn by
gpt-image-2 on a transparent background, cropped to the object, fitted into one cell and palette-reduced so it reads
as pixel art beside the artist's villagers. T1: written to assets/sprites/objects/<id>.png, never over an existing
file unless --force, and every write is listed for the artist.

Usage:
    set -a; . ./setenv.sh; set +a
    uv run python tools/gen_object_props.py --list
    uv run python tools/gen_object_props.py cache_register incident_board ...   # staged under tmp/object_props/
    uv run python tools/gen_object_props.py --deploy cache_register ...          # copy staged files into assets
"""
from __future__ import annotations

import argparse
import base64
import io
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
STAGE = ROOT / "tmp/object_props"
OUT = ROOT / "assets/sprites/objects"
MODEL = "gpt-image-2"
CELL = 48
COLOURS = 24

STYLE = ("A single 16-bit SNES-era JRPG pixel-art PROP, seen from the front at a slight top-down angle like a "
         "classic overworld sprite. Crisp dark outline, limited palette, soft shading, no text or letters, no "
         "humans, no floor, no shadow, nothing else in the picture. The background is one flat, solid, pure magenta (#FF00FF) colour with no "
         "gradient. The object fills the frame and is centred.")

PROPS = {
    "cache_register": "A computer terminal on a small stand in a futuristic data cache: a glowing teal screen with "
                      "abstract readout bars, a squat metal casing, a few blinking status lights.",
    "incident_board": "An industrial whiteboard on two metal legs, ruled into columns with a few blue and red marker "
                      "scribbles (no readable words) and a small sign pinned to the corner.",
    "shelf_7": "A tall narrow brass-trimmed archive shelf of dark wood holding rolled scrolls and boxed files, with a "
               "small engraved brass tag on the front, steampunk style.",
    "graffiti_wall": "A short freestanding section of grimy industrial brick wall covered in colourful spray-paint "
                     "graffiti shapes and a crayon-like doodle of a map (no readable words).",
    "dog": "A friendly scruffy brown-and-white suburban mutt sitting upright, tail mid-wag, collar with a round tag, "
           "seen three-quarter from the front. An animal, not a person.",
    "potted_plant": "A leafy green potted plant in a dented grey industrial metal pot, slightly wilted, a little "
                    "out of place in a factory district.",
}


def key_out(img: Image.Image, tol: int = 90) -> Image.Image:
    """Clear the flat backdrop: flood from the border through pixels close to the sampled corner colour, so a
    backdrop-coloured pixel INSIDE the object (enclosed by it) survives."""
    import numpy as np
    from collections import deque
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


def fit(img: Image.Image) -> Image.Image:
    """Key out the backdrop, crop to the object, fit it into one CELL (bottom-aligned, centred), palette-reduce."""
    img = key_out(img)
    a = img.split()[3].point(lambda v: 255 if v >= 128 else 0)
    img.putalpha(a)
    box = a.getbbox()
    if box is None:
        raise SystemExit("the model returned an empty image")
    obj = img.crop(box)
    s = min((CELL - 2) / obj.width, (CELL - 2) / obj.height)
    obj = obj.resize((max(1, round(obj.width * s)), max(1, round(obj.height * s))), Image.LANCZOS)
    rgb = obj.convert("RGB").quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGB")
    alpha = obj.split()[3].point(lambda v: 255 if v >= 128 else 0)
    obj = rgb.convert("RGBA")
    obj.putalpha(alpha)
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cell.paste(obj, ((CELL - obj.width) // 2, CELL - 1 - obj.height), obj)
    return cell


def generate(pid: str) -> Path:
    from openai import OpenAI
    r = OpenAI().images.generate(model=MODEL, prompt=f"{STYLE}\n\nThe prop: {PROPS[pid]}", size="1024x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json)))
    STAGE.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / f"{pid}_raw.png")
    out = STAGE / f"{pid}.png"
    fit(raw).save(out)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--deploy", action="store_true", help="copy staged sprites into assets/sprites/objects")
    ap.add_argument("--force", action="store_true", help="allow replacing an existing object sprite")
    args = ap.parse_args()
    if args.list or not args.ids:
        for k, v in PROPS.items():
            print(f"{k:16} {v}")
        return 0
    bad = [i for i in args.ids if i not in PROPS]
    if bad:
        raise SystemExit(f"unknown prop id(s): {bad}")
    for pid in args.ids:
        if args.deploy:
            src, dst = STAGE / f"{pid}.png", OUT / f"{pid}.png"
            if not src.exists():
                raise SystemExit(f"{pid}: nothing staged at {src}")
            if dst.exists() and not args.force:
                raise SystemExit(f"{pid}: {dst} exists; refusing to overwrite without --force")
            shutil.copy2(src, dst)
            print(f"deployed {dst.relative_to(ROOT)} (T1, gpt-image-2 -- artist review pending)")
        else:
            print(f"staged {generate(pid).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
