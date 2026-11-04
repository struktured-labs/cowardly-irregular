#!/usr/bin/env python3
"""Animate the drawn Harmonia fountain with water that TRAVELS (T1, derived from the drawn fountain, no image model).

struktured 2026-11-01 (relayed, cowir-main 21340/21341): "the water animation can be even more dynamic looking ... looks
like just lighting right now". The shipped strip was one painting with its water pixels' brightness cycled, so nothing
moved. This keeps that painting (frame 0) and draws motion on it, in its own water palette:
- each of the three streams carries bright segments falling down it;
- where a stream meets the basin, droplets arc out and fall back, and a ring spreads outward on the surface;
- a few specular glints drift across the basin water.
The jets and the basin are MEASURED from the art (the pixels that were cycling, and the blue water mask), not typed.

Writes FRAMES frames as a horizontal strip, staged under tmp/fountain_motion/; --deploy copies it over the prop and
sets its manifest entry's frames and fps.

Usage:
    uv run python tools/gen_fountain_motion.py --preview
    uv run python tools/gen_fountain_motion.py --deploy
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/sprites/props/medieval/fountain.png"
STAGE = ROOT / "tmp/fountain_motion"
CELL = 96
FRAMES = 12
FPS = 12  ## one second per loop
BASIN_TOP = 60  ## the streams' impact row: the first row of basin water under them


def base_frame() -> np.ndarray:
    strip = np.asarray(Image.open(SRC).convert("RGBA"))
    return strip[:, :CELL].copy()


def water_mask(f: np.ndarray) -> np.ndarray:
    r, g, b, a = (f[..., i].astype(int) for i in range(4))
    return (b > r + 40) & (b > g) & (a > 0)


def jets(water: np.ndarray) -> list:
    """Each stream as (x0, x1, top): contiguous runs of columns holding water above the basin."""
    cols = [x for x in range(CELL) if np.count_nonzero(water[:BASIN_TOP, x]) > 3]
    runs, cur = [], []
    for x in cols:
        if cur and x != cur[-1] + 1:
            runs.append(cur)
            cur = []
        cur.append(x)
    if cur:
        runs.append(cur)
    out = []
    for r in runs:
        if len(r) < 2:  ## a 1px run is a highlight on the stone, not a stream
            continue
        top = min(int(np.where(water[:BASIN_TOP, x])[0].min()) for x in r)
        out.append((r[0], r[-1] + 1, top))
    return out


def impact_row(f: np.ndarray, x0: int, x1: int, top: int) -> int:
    """Where a stream meets the basin: the last row of its bright falling water (gaps of up to 2 rows allowed)."""
    cx = (x0 + x1 - 1) // 2
    rgb = f[..., :3].astype(int)
    lit = (rgb.sum(axis=2) > 420) & (rgb[..., 2] - rgb[..., 0] > 20)
    y, last, gap = top, top, 0
    while y < CELL and gap <= 2:
        if lit[y, cx]:
            last, gap = y, 0
        else:
            gap += 1
        y += 1
    return last + 1


def palette(f: np.ndarray, water: np.ndarray) -> dict:
    px = f[water][:, :3].astype(int)
    lum = px.sum(axis=1)
    order = np.argsort(lum)
    pick = lambda q: tuple(int(v) for v in px[order[int(q * (len(order) - 1))]])
    return {"deep": pick(0.15), "mid": pick(0.5), "light": pick(0.9), "foam": (236, 246, 255)}


def put(img: np.ndarray, x: float, y: float, rgb: tuple, a: float = 1.0, mask: np.ndarray | None = None) -> None:
    xi, yi = int(round(x)), int(round(y))
    if not (0 <= xi < CELL and 0 <= yi < CELL) or a <= 0:
        return
    if mask is not None and not mask[yi, xi]:
        return
    c = img[yi, xi, :3].astype(float)
    img[yi, xi, :3] = (c * (1 - a) + np.array(rgb, float) * a).astype(np.uint8)
    img[yi, xi, 3] = max(int(img[yi, xi, 3]), int(255 * a))


def frame(base: np.ndarray, water: np.ndarray, js: list, pal: dict, i: int) -> np.ndarray:
    img = base.copy()
    rgb = base[..., :3].astype(int)
    lit = (rgb.sum(axis=2) > 380) & (rgb[..., 2] - rgb[..., 0] > 20)
    t = i / FRAMES
    for k, (x0, x1, top, hit) in enumerate(js):
        cx = (x0 + x1 - 1) / 2.0
        off = k / max(len(js), 1)
        ## Falling segments over the WHOLE stream: a 6px period moving exactly 2px down per frame (a whole-pixel step
        ## every frame, never a sub-pixel stall), 4 periods per loop so frame 12 lands back on frame 0.
        period = 6
        shift = (i * 2) % period
        ## The stream is repainted OPAQUE from spout to impact, so the static painting under it no longer shows through.
        band = (pal["foam"], pal["light"], pal["light"], pal["mid"], pal["mid"], pal["deep"])
        for y in range(top, hit):
            c = band[int((y - top - shift) % period)]
            for x in range(x0, x1):
                edge = x in (x0, x1 - 1) and x1 - x0 > 2
                put(img, x, y, c if not edge else pal["mid"], 1.0)
        ## Splash droplets: four per stream, 2px wide, each on its own phase, arcing out and falling back to the surface.
        for d, (vx, vy) in enumerate(((-7.0, 8.0), (6.5, 7.0), (-2.5, 10.0), (3.0, 9.0))):
            u = (t + off + d / 4.0) % 1.0
            x = cx + vx * u
            y = hit - 1 - vy * u + 12.0 * u * u
            if y <= hit + 1:
                a = 1.0 - 0.45 * u
                put(img, x, y, pal["foam"], a)
                put(img, x + (1 if vx >= 0 else -1), y, pal["light"], a * 0.7)
        ## Rings spreading on the surface from the impact: two staggered, foam-bright, fading as they widen, on water only.
        for ring in range(2):
            u = (t + off + ring / 2.0) % 1.0
            rx = 2.0 + 10.0 * u
            ry = rx * 0.4
            a = 0.95 * (1 - u) ** 0.8
            steps = int(10 + 30 * u)
            for sidx in range(steps):
                ang = 2 * math.pi * sidx / steps
                put(img, cx + rx * math.cos(ang), hit + ry * math.sin(ang), pal["foam"], a, water)
    ## Specular glints drifting across the basin, each twinkling once per loop.
    basin = water.copy()
    basin[:BASIN_TOP] = False
    ys, xs = np.where(basin)
    if xs.size:
        lo, hi = int(xs.min()), int(xs.max())
        for g, (gy, speed, ph) in enumerate(((66, 1.0, 0.0), (70, -1.0, 0.33), (73, 1.0, 0.66), (64, -1.0, 0.5))):
            u = (t + ph) % 1.0
            x = lo + ((g * 17 + speed * u * (hi - lo)) % (hi - lo))
            tw = max(0.0, math.sin(math.pi * ((t * 2 + ph) % 1.0)))
            put(img, x, gy, pal["foam"], tw, basin)
            put(img, x + 1, gy, pal["light"], 0.6 * tw, basin)
    return img


def build() -> tuple:
    base = base_frame()
    water = water_mask(base)
    js = [(x0, x1, top, impact_row(base, x0, x1, top)) for x0, x1, top in jets(water)]
    pal = palette(base, water)
    frames = [frame(base, water, js, pal, i) for i in range(FRAMES)]
    return np.concatenate(frames, axis=1), js, pal


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--deploy", action="store_true")
    args = ap.parse_args()
    STAGE.mkdir(parents=True, exist_ok=True)
    sheet, js, pal = build()
    Image.fromarray(sheet, "RGBA").save(STAGE / "fountain.png")
    print(f"jets {js} palette {pal} -> {sheet.shape[1]}x{sheet.shape[0]} ({FRAMES} frames @ {FPS} fps)")
    if args.preview:
        cells = [Image.fromarray(sheet[:, i * CELL:(i + 1) * CELL], "RGBA") for i in range(FRAMES)]
        bg = (64, 112, 168, 255)
        tiles = []
        for c in cells:
            b = Image.new("RGBA", (CELL, CELL), bg)
            b.alpha_composite(c)
            tiles.append(b.crop((0, 40, CELL, 84)).resize((CELL * 4, 44 * 4), Image.NEAREST))
        cs = Image.new("RGBA", (tiles[0].width * 4, tiles[0].height * 3), (20, 20, 20, 255))
        for i, tl in enumerate(tiles):
            cs.alpha_composite(tl, ((i % 4) * tl.width, (i // 4) * tl.height))
        cs.save(STAGE / "preview_contact.png")
        gif = [Image.new("RGBA", (CELL, CELL), bg) for _ in cells]
        for g, c in zip(gif, cells):
            g.alpha_composite(c)
        gif = [g.resize((CELL * 4, CELL * 4), Image.NEAREST).convert("RGB") for g in gif]
        gif[0].save(STAGE / "preview.gif", save_all=True, append_images=gif[1:], duration=int(1000 / FPS), loop=0)
    if args.deploy:
        SRC.write_bytes((STAGE / "fountain.png").read_bytes())
        mp = ROOT / "data/sprite_manifest.json"
        m = json.loads(mp.read_text())
        e = m["prop_art"]["fountain_medieval"]
        e["frames"], e["fps"] = FRAMES, FPS
        e["source"] = ("gpt-image-2 painting (tools/gen_village_buildings.py --props) + MOTION drawn on it by "
                       "tools/gen_fountain_motion.py: falling stream segments, splash droplets, spreading surface rings, "
                       f"drifting glints; {FRAMES} frames of 96x96 at {FPS} fps (struktured 2026-11-01: 'looks like just "
                       "lighting right now'); T1, artist veto applies.")
        mp.write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
        print("deployed", SRC.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
