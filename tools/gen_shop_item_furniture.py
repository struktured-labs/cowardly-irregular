#!/usr/bin/env python3
"""Harmonia item shop: the stock that stands on its floor, drawn to sit with the shop's drawn wall, shelves and counter
(T1, placed by this script, no image model). Same method and helpers as tools/gen_inn_furniture.py (main 24425).

The shop's shelves, counter, floor and back wall are drawn; what was left procedural or missing is the floor stock.
Every wood tone is a percentile of floor_shop_item.png / shelf_shop_item.png, so the pieces cannot drift from the room.

  barrels 64x64 (the procedural cluster's own size: three casks, one open and full of apples) · sacks 48x40 (two grain
  sacks, one slumped) · crate_produce 36x34 (an open crate of roots and greens) · mat 96x40 (a striped runner before
  the counter) · door_mat 64x24

Usage:
    uv run --with pillow --with numpy python tools/gen_shop_item_furniture.py            # writes the PNGs
    uv run --with pillow --with numpy python tools/gen_shop_item_furniture.py --check    # exit 1 if any differs
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_inn_furniture import ART, Canvas, ramp, scaled  # noqa: E402


def cask(c: Canvas, x0: int, y0: int, staves, iron, lid, ink, open_top=None):
    """One barrel, 28 wide and 38 tall, its top-left at (x0, y0). `open_top` = a drawing callback for what fills it."""
    def belly(x, y):
        x, y = x - x0, y - y0
        bulge = 2 if 12 <= y <= 30 else (1 if 8 <= y <= 34 else 0)
        return 3 - bulge <= x <= 24 + bulge and 6 <= y <= 36
    c.lit(x0 + 1, y0 + 6, x0 + 26, y0 + 36, staves, mask=belly)
    for sx in (7, 12, 17, 22):
        for y in range(y0 + 8, y0 + 36):
            if belly(x0 + sx, y):
                c.put(x0 + sx, y, ink)
    for hy in (11, 31):
        for x in range(x0, x0 + 28):
            if belly(x, y0 + hy):
                c.put(x, y0 + hy, iron[2] if x - x0 > 14 else iron[1])
                c.put(x, y0 + hy + 1, iron[0])
    c.ellipse(x0 + 13.5, y0 + 6, 10.5, 3.5, lid[0])
    c.ellipse(x0 + 13.5, y0 + 6, 8, 2.2, lid[1] if open_top is None else ink)
    if open_top is not None:
        open_top(x0 + 13.5, y0 + 5.5)


def build() -> dict[str, Image.Image]:
    floor = ramp(ART / "floor_shop_item.png")
    shelf = ramp(ART / "shelf_shop_item.png")
    ink = scaled(shelf[0], 0.7)
    honey = scaled(floor[5], 1.12)
    top = (floor[1], floor[4], honey, scaled(honey, 1.14))
    face = (ink, shelf[0], shelf[1], shelf[3])
    staves = (shelf[0], shelf[1], shelf[2], floor[4])
    iron = (scaled(shelf[0], 0.55), (58, 54, 52), (86, 80, 76), (120, 112, 104))
    burlap = ((78, 60, 36), (112, 90, 56), (144, 120, 78), (170, 148, 102))
    apple = ((120, 26, 22), (170, 40, 30), (214, 78, 52))
    green = ((36, 66, 34), (60, 100, 48), (96, 138, 70))
    root = ((150, 84, 30), (198, 120, 44), (226, 160, 76))
    out = {}

    # --- three casks: two against the wall, one in front, open and full of apples
    b = Canvas(64, 64, 211)
    cask(b, 3, 2, staves, iron, (top[2], top[1]), ink)
    cask(b, 33, 4, staves, iron, (top[2], top[1]), ink)

    def apples(cx, cy):
        for dx, dy in ((-5, 0), (-1, -1), (3, 0), (6, 1), (-3, 1), (1, 1)):
            b.ellipse(cx + dx, cy + dy, 2.2, 1.8, apple[1])
            b.put(int(cx + dx), int(cy + dy - 1), apple[2])
            b.put(int(cx + dx + 1), int(cy + dy + 1), apple[0])
    cask(b, 17, 24, staves, iron, (top[2], top[1]), ink, open_top=apples)
    b.outline(ink)
    out["barrels_shop_item"] = b.image()

    # --- two grain sacks: one upright and tied, one slumped against it
    s = Canvas(48, 40, 223)
    s.lit(4, 10, 26, 37, burlap, mask=lambda x, y: ((x - 15) / 11.5) ** 2 + ((y - 25) / 13.0) ** 2 <= 1.0 or (y > 25 and 5 <= x <= 25))
    s.lit(10, 3, 20, 10, burlap, mask=lambda x, y: abs(x - 15) <= 2 + (10 - y) * 0.45)      # the gathered neck
    s.rect(11, 9, 19, 10, (120, 84, 40))                                                    # its tie
    s.lit(22, 20, 45, 37, burlap, mask=lambda x, y: ((x - 33.5) / 12.0) ** 2 + ((y - 30) / 8.5) ** 2 <= 1.0 or (y > 30 and 23 <= x <= 44))
    for x in range(8, 24, 5):                                                               # the weave's shadow lines
        for y in range(14, 36, 3):
            s.put(x, y, burlap[0])
    for x in range(26, 44, 5):
        for y in range(25, 36, 3):
            s.put(x, y, burlap[0])
    s.ellipse(40, 26, 3, 2, (226, 204, 150))                                                # spilled grain at the slumped mouth
    s.outline(ink)
    out["sacks_shop_item"] = s.image()

    # --- an open crate of roots and greens
    c = Canvas(36, 34, 227)
    c.wood(2, 12, 33, 31, face, vertical=True, boards=5)
    c.rect(2, 12, 33, 13, shelf[3])
    c.rect(2, 30, 33, 31, shelf[0])
    c.rect(3, 6, 32, 11, ink)                                                               # the dark inside, above the front
    for i, cx in enumerate((7, 13, 19, 25, 30)):
        tone = root if i % 2 == 0 else green
        c.ellipse(cx, 8 + (i % 2), 3.2, 3.0, tone[1])
        c.put(cx - 1, 6 + (i % 2), tone[2])
        c.put(cx + 1, 10 + (i % 2), tone[0])
    for cx in (7, 19, 30):                                                                  # leafy tops on the roots
        c.put(cx, 3, green[2]); c.put(cx - 1, 4, green[1]); c.put(cx + 1, 4, green[1]); c.put(cx, 5, green[0])
    c.outline(ink)
    out["crate_produce_shop_item"] = c.image()

    # --- a striped runner before the counter: lies IN the floor (no outline)
    stripe = ((58, 84, 64), (86, 118, 88), scaled(honey, 0.9), (132, 52, 40))
    m = Canvas(96, 40, 229)
    m.rect(3, 1, 92, 38, stripe[0])
    for y in range(3, 37):
        band = (y - 3) // 4
        tone = stripe[1] if band % 3 == 0 else (stripe[2] if band % 3 == 1 else stripe[3])
        for x in range(5, 91):
            m.put(x, y, tone if (x + y) % 5 else scaled(tone, 0.86))
    for y in range(2, 38, 2):                                                               # fringe at both ends
        for x in (0, 1, 2, 93, 94, 95):
            m.put(x, y, stripe[2])
    out["mat_shop_item"] = m.image()

    # --- door mat: woven straw with a bound edge
    straw = (scaled(honey, 0.62), scaled(honey, 0.8), honey)
    dm = Canvas(64, 24, 233)
    dm.rect(1, 1, 62, 22, scaled(honey, 0.5))
    dm.rect(2, 2, 61, 21, straw[0])
    for y in range(3, 21):
        for x in range(3, 61):
            dm.put(x, y, straw[2] if ((x // 3) + (y // 2)) % 2 == 0 else (straw[1] if dm.rng.random() < 0.8 else straw[0]))
    out["door_mat_shop_item"] = dm.image()
    return out


def main() -> int:
    built = build()
    if "--check" in sys.argv:
        bad = [n for n, img in built.items()
               if not (ART / f"{n}.png").exists() or Image.open(ART / f"{n}.png").convert("RGBA").tobytes() != img.tobytes()]
        print("item shop furniture: %s" % ("matches the generator" if not bad else "DIFFERS: " + ", ".join(bad)))
        return 1 if bad else 0
    for name, img in built.items():
        img.save(ART / f"{name}.png")
        print("wrote %s %dx%d" % (name, img.width, img.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
