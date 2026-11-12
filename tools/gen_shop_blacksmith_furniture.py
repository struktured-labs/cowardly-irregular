#!/usr/bin/env python3
"""Harmonia blacksmith shop: what stands on its floor, drawn to sit with the shop's drawn wall, racks and counter
(T1, placed by this script, no image model). Same method and helpers as tools/gen_inn_furniture.py (main 24425).

Wood tones are percentiles of counter_shop_blacksmith.png; the steel is sampled from shelf_shop_blacksmith.png (its
racks of blades and helms), so the anvil is the same metal as the stock around it.

  anvil 64x40 (on its stump; the procedural anvil's own size) · weapon_crates 64x44 (two crates, hilts showing; the
  procedural pile's size) · bellows 40x20 (its size) · quench_barrel 28x38 (a cask of water) · coal_bin 72x40 ·
  door_mat 64x24 · forge 64x64, the BODY under the room's animated flames (main 24436).

Usage:
    uv run --with pillow --with numpy python tools/gen_shop_blacksmith_furniture.py [--check]
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_inn_furniture import ART, Canvas, ramp, scaled  # noqa: E402
from gen_shop_item_furniture import cask  # noqa: E402


def build() -> dict[str, Image.Image]:
    wood_r = ramp(ART / "counter_shop_blacksmith.png")
    metal_r = ramp(ART / "shelf_shop_blacksmith.png", pcts=(3, 20, 45, 70, 90, 98))
    ink = scaled(wood_r[0], 0.6)
    top = (wood_r[1], wood_r[3], wood_r[4], wood_r[5])
    face = (ink, wood_r[0], wood_r[1], wood_r[3])
    staves = (wood_r[0], wood_r[1], wood_r[2], wood_r[4])
    # greys only: take the shelf art's value steps, drop its wood hue
    def grey(c, k=1.0):
        v = int(round((0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) * k))
        return (max(0, min(255, v - 2)), max(0, min(255, v)), max(0, min(255, v + 6)))
    steel = (grey(metal_r[0], 0.8), grey(metal_r[2], 0.9), grey(metal_r[4], 1.0), grey(metal_r[5], 1.12))
    iron = (steel[0], steel[0], steel[1], steel[2])
    leather = ((60, 34, 20), (96, 56, 30), (132, 84, 44), (164, 112, 62))
    out = {}

    # --- the anvil on its stump: horn to the left, heel to the right, a lit face
    a = Canvas(64, 40, 311)
    a.lit(20, 22, 43, 37, staves)                                   # the stump
    for x in (26, 32, 38):
        for y in range(24, 37):
            a.put(x, y, ink)
    a.ellipse(31.5, 22, 12, 3, top[2])
    a.ellipse(31.5, 22, 8, 1.6, top[1])
    a.rect(24, 16, 39, 21, steel[1])                                # the waist
    a.rect(22, 20, 41, 22, steel[0])                                # the feet
    a.rect(14, 8, 52, 15, steel[1])                                 # the body
    a.rect(14, 8, 52, 9, steel[3])                                  # the face, lit
    a.rect(14, 10, 52, 10, steel[2])
    for i in range(12):                                             # the horn, tapering left
        h = max(1, 6 - i // 2)
        a.rect(13 - i, 9 + (6 - h) // 2, 13 - i, 9 + (6 - h) // 2 + h - 1, steel[1])
        a.put(13 - i, 9 + (6 - h) // 2, steel[3])
    a.rect(53, 9, 58, 13, steel[1])                                 # the heel
    a.rect(53, 9, 58, 9, steel[3])
    a.put(47, 8, ink)                                               # the hardy hole
    a.rect(44, 4, 51, 6, steel[2])                                  # a hammer left on the face
    a.rect(47, 1, 48, 7, wood_r[3])
    a.outline(ink)
    out["anvil_shop_blacksmith"] = a.image()

    # --- two weapon crates, one on the other, hilts and a spear shaft showing
    c = Canvas(64, 44, 313)
    c.wood(2, 22, 61, 41, face, vertical=True, boards=8)
    c.rect(2, 22, 61, 23, wood_r[3])
    c.rect(2, 40, 61, 41, wood_r[0])
    c.wood(10, 8, 49, 21, face, vertical=True, boards=5)
    c.rect(10, 8, 49, 9, wood_r[3])
    for x0 in (14, 24, 34, 44):                                     # sword hilts standing out of the upper crate
        c.rect(x0, 1, x0 + 1, 7, leather[1])
        c.rect(x0 - 2, 5, x0 + 3, 6, steel[2])
        c.put(x0, 0, steel[3]); c.put(x0 + 1, 0, steel[2])
    c.rect(54, 3, 55, 21, wood_r[4])                                # a spear leant in the corner
    c.put(54, 1, steel[3]); c.put(55, 1, steel[2]); c.put(54, 2, steel[2]); c.put(55, 2, steel[1]); c.put(54, 0, steel[3])
    c.outline(ink)
    out["weapon_crates_shop_blacksmith"] = c.image()

    # --- bellows: two boards, pleated leather between, a nozzle toward the forge
    b = Canvas(40, 20, 317)
    b.wood(4, 3, 30, 6, top)
    b.wood(4, 13, 30, 16, top)
    for x in range(5, 30):
        for y in range(7, 13):
            pleat = (x - 5) % 4
            b.put(x, y, leather[3] if pleat == 0 else (leather[2] if pleat == 1 else (leather[1] if pleat == 2 else leather[0])))
    b.rect(31, 8, 37, 11, steel[1])
    b.rect(31, 8, 37, 8, steel[3])
    b.rect(0, 9, 3, 10, wood_r[3])                                  # the handle
    b.outline(ink)
    out["bellows_shop_blacksmith"] = b.image()

    # --- quench barrel: a cask of dark water with a glint
    q = Canvas(28, 38, 331)

    def water(cx, cy):
        q.ellipse(cx, cy, 8, 2.2, (34, 52, 66))
        q.rect(int(cx) - 4, int(cy) - 1, int(cx) - 1, int(cy) - 1, (120, 160, 180))
    cask(q, 0, 0, staves, iron, (top[2], top[1]), ink, open_top=water)
    q.outline(ink)
    out["quench_barrel_shop_blacksmith"] = q.image()

    # --- coal bin: a low plank bin heaped with coal, the lumps nearest the fire catching it (the forge is to its right)
    coal = ((16, 15, 18), (36, 34, 40), (62, 60, 68), (96, 92, 100))
    ember = ((150, 50, 20), (214, 96, 40), (250, 170, 70))
    p = Canvas(72, 40, 337)
    for (cx, cy, rx, ry) in ((20, 18, 14, 9), (38, 13, 16, 11), (54, 19, 13, 8), (36, 22, 26, 6)):
        p.ellipse(cx, cy, rx, ry, coal[1])
    for _ in range(90):                                             # lumps: a lit edge and a dark underside each
        x, y = int(p.rng.integers(8, 66)), int(p.rng.integers(4, 26))
        if p.px[y, x, 3] and p.px[y - 1, x, 3]:
            p.put(x, y, coal[2]); p.put(x + 1, y, coal[1]); p.put(x, y + 1, coal[0])
            if p.rng.random() < 0.35:
                p.put(x, y - 1, coal[3])
    for x, y in ((58, 12), (61, 16), (54, 9), (63, 20), (50, 14), (57, 19)):    # embers on the forge's side
        if p.px[y, x, 3]:
            p.put(x, y, ember[1]); p.put(x + 1, y, ember[0]); p.put(x, y - 1, ember[2])
    p.wood(3, 24, 68, 37, face, vertical=True, boards=9)            # the bin's front, over the heap's foot
    p.rect(3, 24, 68, 25, wood_r[3])
    p.rect(3, 36, 68, 37, wood_r[0])
    p.rect(1, 22, 3, 38, wood_r[1]); p.rect(68, 22, 70, 38, wood_r[1])           # corner posts
    p.outline(ink)
    out["coal_bin_shop_blacksmith"] = p.image()

    # --- door mat: woven rush with a bound edge, the inn's own treatment in this room's wood tones (lies in the floor)
    rush = (scaled(wood_r[4], 0.62), scaled(wood_r[4], 0.82), wood_r[4])
    dm = Canvas(64, 24, 341)
    dm.rect(1, 1, 62, 22, scaled(wood_r[4], 0.5))
    dm.rect(2, 2, 61, 21, rush[0])
    for y in range(3, 21):
        for x in range(3, 61):
            dm.put(x, y, rush[2] if ((x // 3) + (y // 2)) % 2 == 0 else (rush[1] if dm.rng.random() < 0.8 else rush[0]))
    out["door_mat_shop_blacksmith"] = dm.image()

    # --- the forge's BODY, 64x64: a dressed-stone hearth with an arched mouth and a coal bed; the room's animated
    #     flames play over the mouth (its centre is at (32, 34) in this image)
    stone_r = ramp(ART / "wall_shop_blacksmith.png", pcts=(4, 25, 50, 72, 90, 98))
    stone = (scaled(stone_r[0], 0.8), stone_r[1], stone_r[3], stone_r[5])
    f = Canvas(64, 64, 347)
    f.rect(3, 10, 60, 61, stone[1])
    for row, y0 in enumerate(range(10, 62, 9)):                     # courses of blocks, joints staggered
        for x in range(3, 61):
            f.put(x, y0, stone[0])
        off = 0 if row % 2 else 7
        for x0 in range(3 + off, 61, 14):
            for y in range(y0, min(62, y0 + 9)):
                f.put(x0, y, stone[0])
        for x in range(4, 60):
            if f.px[y0 + 1, x, 3] and tuple(f.px[y0 + 1, x][:3]) == stone[1] and (x * 5 + row * 3) % 9 < 5:
                f.put(x, y0 + 1, stone[2])                           # each block's lit top edge
    for _ in range(70):
        x, y = int(f.rng.integers(4, 60)), int(f.rng.integers(12, 60))
        if tuple(f.px[y, x][:3]) == stone[1]:
            f.put(x, y, stone[2] if f.rng.random() < 0.5 else stone[0])
    f.rect(1, 5, 62, 10, stone[2])                                  # the mantel slab
    f.rect(1, 5, 62, 6, stone[3])
    f.rect(1, 10, 62, 10, stone[0])
    for y in range(22, 50):                                         # the arched mouth
        for x in range(14, 50):
            inside = (y >= 32 and 16 <= x <= 47) or ((x - 31.5) / 16.0) ** 2 + ((y - 32) / 10.0) ** 2 <= 1.0
            if inside:
                f.put(x, y, (18, 12, 12))
    for x in range(13, 51):                                         # the arch's voussoirs, lit
        for y in range(19, 34):
            d = ((x - 31.5) / 18.5) ** 2 + ((y - 32) / 12.5) ** 2
            if 0.86 <= d <= 1.0 and y <= 32:
                f.put(x, y, stone[3] if (x // 5) % 2 == 0 else stone[2])
    for x in range(17, 47):                                         # the coal bed: dark lumps, a glow along its top
        for y in range(43, 50):
            f.put(x, y, coal[1] if (x + y) % 3 else coal[0])
        f.put(x, 43, ember[1] if x % 3 else ember[2])
        f.put(x, 44, ember[0] if x % 2 else coal[1])
    f.rect(12, 50, 51, 52, stone[2])                                # the hearth's sill
    f.rect(12, 50, 51, 50, stone[3])
    f.outline(scaled(stone[0], 0.7))
    out["forge_shop_blacksmith"] = f.image()
    return out


def main() -> int:
    built = build()
    if "--check" in sys.argv:
        bad = [n for n, img in built.items()
               if not (ART / f"{n}.png").exists() or Image.open(ART / f"{n}.png").convert("RGBA").tobytes() != img.tobytes()]
        print("blacksmith furniture: %s" % ("matches the generator" if not bad else "DIFFERS: " + ", ".join(bad)))
        return 1 if bad else 0
    for name, img in built.items():
        img.save(ART / f"{name}.png")
        print("wrote %s %dx%d" % (name, img.width, img.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
