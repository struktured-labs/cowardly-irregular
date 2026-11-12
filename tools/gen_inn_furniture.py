#!/usr/bin/env python3
"""Harmonia inn furniture, drawn to sit with the room's drawn wall, floor and hearth (T1, placed by this script, no image model).

struktured 2026-11-01: "the inside of village houses and shops need a major sprite rework". The inn's back wall, floor and
hearth are drawn; its armchairs, table, desk, coat rack and lanterns were still flat procedural fills beside them
(overworld 24349, main 24354). These five are built here from the ROOM'S OWN colours: every wood tone is a percentile of
floor_inn.png / back_wall_inn.png, so the furniture cannot drift from the room it stands in.

Each piece is the size of the procedural one it replaces (InnInterior.gd), so it stands on the same cells:
  armchair 40x44 (one PNG; the second chair is the room's flip) · table 256x64 · desk 96x64 · coat_rack 20x40 · lantern 14x22

Usage:
    uv run --with pillow --with numpy python tools/gen_inn_furniture.py            # writes the five PNGs
    uv run --with pillow --with numpy python tools/gen_inn_furniture.py --check    # exit 1 if any PNG on disk differs
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets/sprites/interiors/harmonia"
PIECES = ["armchair_inn", "table_inn", "desk_inn", "coat_rack_inn", "lantern_inn"]


def ramp(path: Path, pcts=(4, 22, 45, 68, 88, 97)) -> list[tuple[int, int, int]]:
    """Six tones of a drawn image, darkest first: the mean colour of its pixels around each luminance percentile."""
    a = np.asarray(Image.open(path).convert("RGBA")).reshape(-1, 4).astype(float)
    a = a[a[:, 3] > 200][:, :3]
    lum = a @ np.array([0.2126, 0.7152, 0.0722])
    out = []
    for p in pcts:
        lo, hi = np.percentile(lum, max(0, p - 3)), np.percentile(lum, min(100, p + 3))
        sel = a[(lum >= lo) & (lum <= hi)]
        out.append(tuple(int(round(v)) for v in sel.mean(axis=0)))
    return out


def scaled(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c)


class Canvas:
    def __init__(self, w: int, h: int, seed: int):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 4), dtype=np.uint8)
        self.rng = np.random.default_rng(seed)   # fixed seed: the grain is the same pixels on every run

    def put(self, x, y, c, a=255):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y, x] = (*c[:3], a)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def wood(self, x0, y0, x1, y1, tones, plank=0, vertical=False, boards=0):
        """A wooden face: one flat tone, short grain strokes running with the board, a lit leading edge, a shaded far edge.
        `plank` = seam spacing ACROSS the grain's run (board ends); `boards` = how many boards deep the face is."""
        dark, shade, mid, light = tones
        self.rect(x0, y0, x1, y1, mid)
        w, h = x1 - x0 + 1, y1 - y0 + 1
        for _ in range(max(2, (w * h) // 46)):                # grain: sparse 3-7 px strokes, never single-pixel noise
            n = int(self.rng.integers(3, 8))
            gx, gy = int(self.rng.integers(x0, x1 + 1)), int(self.rng.integers(y0 + 1, max(y0 + 2, y1)))
            tone = shade if self.rng.random() < 0.7 else light
            for i in range(n):
                px, py = (gx, gy + i) if vertical else (gx + i, gy)
                if x0 < px < x1 and y0 < py < y1:
                    self.put(px, py, tone)
        if boards > 1:
            for b in range(1, boards):
                if vertical:
                    bx = x0 + (w * b) // boards
                    for y in range(y0, y1 + 1):
                        self.put(bx, y, dark)
                        self.put(bx + 1, y, light)
                else:
                    by = y0 + (h * b) // boards
                    for x in range(x0, x1 + 1):
                        self.put(x, by, dark)
                        self.put(x, by + 1, light)
        if plank:
            row_h = h // max(1, boards)
            for r in range(max(1, boards)):
                off = (plank // 2) if r % 2 else 0
                for sx in range(x0 + plank - off, x1 - 2, plank):
                    for y in range(y0 + r * row_h + 1, min(y1, y0 + (r + 1) * row_h)):
                        self.put(sx, y, dark)
        for x in range(x0, x1 + 1):
            self.put(x, y0, light)
            self.put(x, y1, shade)
        for y in range(y0, y1 + 1):
            self.put(x0, y, light)
            self.put(x1, y, shade)

    def outline(self, c):
        """One dark pixel around everything opaque (4-neighbour), like the drawn set's own edges."""
        solid = self.px[:, :, 3] > 0
        edge = np.zeros_like(solid)
        edge[1:, :] |= solid[:-1, :]
        edge[:-1, :] |= solid[1:, :]
        edge[:, 1:] |= solid[:, :-1]
        edge[:, :-1] |= solid[:, 1:]
        edge &= ~solid
        self.px[edge] = (*c, 255)

    def image(self) -> Image.Image:
        return Image.fromarray(self.px, "RGBA")


def build() -> dict[str, Image.Image]:
    floor = ramp(ART / "floor_inn.png")
    wall = ramp(ART / "back_wall_inn.png")
    hearth = ramp(ART / "hearth_inn.png", pcts=(4, 30, 60, 85, 94, 99))
    ink = scaled(wall[0], 0.7)
    honey = scaled(floor[5], 1.22)
    top = (floor[1], floor[4], honey, scaled(honey, 1.16))  # a worn, waxed top: lighter than the floor it stands on
    face = (ink, wall[0], floor[1], floor[3])               # a front face: the beams' dark, so it reads against the planks
    deep = (ink, scaled(wall[0], 0.85), wall[0], floor[1])  # legs and insets
    iron = (scaled(wall[0], 0.55), (58, 54, 52), (86, 80, 76), (120, 112, 104))
    ember, flame, glow = hearth[3], hearth[4], hearth[5]
    out = {}

    # --- communal table, 8x2 cells: a top three boards deep seen from above, an apron and three trestles under its edge
    t = Canvas(256, 64, 11)
    t.wood(2, 3, 253, 36, top, plank=58, boards=3)
    t.rect(2, 37, 253, 38, ink)                              # the top's thickness, in shadow
    t.wood(5, 39, 250, 46, face)
    for x0 in (12, 121, 231):
        t.wood(x0, 47, x0 + 12, 59, deep, vertical=True)
        t.rect(x0 - 2, 59, x0 + 14, 60, deep[2])             # a foot
    t.outline(ink)
    out["table_inn"] = t.image()

    # --- registration desk, 3x2 cells: a counter with a lit top and three inset panels
    d = Canvas(96, 64, 23)
    d.wood(2, 3, 93, 20, top, plank=40, boards=2)
    d.rect(2, 21, 93, 22, ink)
    d.wood(3, 23, 92, 60, face)
    for x0 in (8, 37, 66):
        d.rect(x0, 28, x0 + 21, 54, ink)                     # the panel's recess
        d.wood(x0 + 1, 29, x0 + 20, 53, deep, vertical=True)
        for y in range(29, 54):
            d.put(x0 + 21, y, face[3])                       # the recess's lit far wall
        for x in range(x0, x0 + 22):
            d.put(x, 54, face[3])
    d.rect(3, 58, 92, 60, deep[1])                           # skirting
    d.outline(ink)
    out["desk_inn"] = d.image()

    # --- wing-back armchair, 40x44: oxblood leather, the hearth's warm side lit
    leather = ((74, 20, 18), (112, 30, 26), (150, 44, 36), (186, 72, 54))
    a = Canvas(40, 44, 37)
    for y in range(3, 27):                                    # the back: a rounded top
        inset = max(0, 5 - (y - 3)) if y < 8 else 0
        for x in range(8 + inset, 32 - inset):
            a.put(x, y, leather[2] if x < 27 else leather[1])
    for y in range(6, 13):                                    # a highlight across the top of the back
        for x in range(12, 22):
            if (x + y) % 3:
                a.put(x, y, leather[3])
    for bx, by in ((14, 14), (20, 12), (26, 14), (17, 19), (23, 19)):   # button tufts
        a.put(bx, by, leather[0])
        a.put(bx, by - 1, leather[3])
    for y in range(8, 33):                                    # the wings and arms
        for x in list(range(4, 9)) + list(range(31, 36)):
            a.put(x, y, leather[1] if x >= 31 else leather[2])
    for x in list(range(3, 10)) + list(range(30, 37)):        # arm rests' rolled tops
        a.put(x, 20, leather[3])
        a.put(x, 21, leather[2])
    for y in range(26, 33):                                   # the seat cushion
        for x in range(9, 31):
            a.put(x, y, leather[3] if y == 26 else (leather[2] if y < 31 else leather[1]))
    for y in range(33, 40):                                   # the front skirt
        for x in range(4, 36):
            a.put(x, y, leather[1] if y > 34 else leather[2])
    for x0 in (5, 31):                                        # turned feet
        a.rect(x0, 40, x0 + 3, 42, deep[2])
    a.outline(ink)
    out["armchair_inn"] = a.image()

    # --- coat rack, 20x40: a turned pole, four pegs, two travelling cloaks
    c = Canvas(20, 40, 41)
    c.wood(9, 2, 10, 35, deep, vertical=True)
    c.rect(8, 1, 11, 2, deep[3])                              # the finial
    for x in (4, 5, 6, 13, 14, 15):
        c.put(x, 6, deep[2])                                  # pegs
    c.rect(4, 36, 15, 37, deep[2])                            # the foot
    c.rect(2, 38, 17, 38, deep[1])
    plum = ((52, 34, 74), (78, 52, 108), (104, 74, 138))
    moss = ((38, 62, 40), (58, 90, 56), (84, 118, 76))
    for cloak, x0, y1 in ((plum, 2, 28), (moss, 12, 24)):
        for y in range(7, y1):
            w = 5 + (1 if y > 14 else 0)
            for x in range(x0, x0 + w):
                tone = cloak[2] if x == x0 else (cloak[0] if x == x0 + w - 1 or (x + y) % 5 == 0 else cloak[1])
                c.put(x, y, tone)
    c.outline(ink)
    out["coat_rack_inn"] = c.image()

    # --- hanging lantern, 14x22: iron cage, amber glass, the hearth's own flame colours
    l = Canvas(14, 22, 53)
    for y in range(0, 5):
        l.put(6 + (y % 2), y, iron[2])                        # chain links
    l.rect(4, 5, 9, 5, iron[3])                               # cap
    l.rect(3, 6, 10, 7, iron[1])
    for y in range(8, 17):
        for x in range(4, 10):
            dist = abs(x - 6.5) + abs(y - 12) * 0.6
            l.put(x, y, scaled(glow, 1.08) if dist < 2.2 else (glow if dist < 3.4 else flame))
        l.put(3, y, iron[2])
        l.put(10, y, iron[1])
    for y in range(8, 17):
        l.put(6, y, iron[1]) if y in (8, 16) else None        # the cage's cross bars
    l.rect(3, 17, 10, 18, iron[1])
    l.rect(5, 19, 8, 19, iron[2])
    l.outline(iron[0])
    out["lantern_inn"] = l.image()
    return out


def main() -> int:
    built = build()
    if "--check" in sys.argv:
        bad = []
        for name, img in built.items():
            p = ART / f"{name}.png"
            if not p.exists() or Image.open(p).convert("RGBA").tobytes() != img.tobytes():
                bad.append(name)
        print("inn furniture: %s" % ("matches the generator" if not bad else "DIFFERS: " + ", ".join(bad)))
        return 1 if bad else 0
    for name, img in built.items():
        img.save(ART / f"{name}.png")
        print("wrote %s %dx%d" % (name, img.width, img.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
