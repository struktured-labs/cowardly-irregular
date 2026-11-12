#!/usr/bin/env python3
"""Harmonia inn furniture, drawn to sit with the room's drawn wall, floor and hearth (T1, placed by this script, no image model).

struktured 2026-11-01: "the inside of village houses and shops need a major sprite rework". The inn's back wall, floor and
hearth are drawn; its armchairs, table, desk, coat rack and lanterns were still flat procedural fills beside them
(overworld 24349, main 24354). These five are built here from the ROOM'S OWN colours: every wood tone is a percentile of
floor_inn.png / back_wall_inn.png, so the furniture cannot drift from the room it stands in.

Each piece is the size of the procedural one it replaces (InnInterior.gd), so it stands on the same cells:
  table 256x64 · desk 96x64 · bench 224x20 · table_things 256x64 (an overlay on the table's rect: what stands ON it)
and four are new or larger, their footprints agreed with the room's owner (main 24363):
  armchair 60x66, a wing-back lit from its right (the room flips the second one, so both are lit from the hearth
  between them) · rug 160x96 · coat_rack 24x44 · barrel 28x38 · crate 30x30
The four free-hanging lanterns of the first draft are gone: the wall art has its own.

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

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    self.put(x, y, c)

    def lit(self, x0, y0, x1, y1, tones, light_from_right=True, mask=None):
        """A rounded, lit surface: four tones across its width, darkest on the far side, the steps broken by an ordered
        dither so the form turns instead of banding. `mask(x, y)` keeps only the pixels of the shape."""
        w = max(1, x1 - x0)
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if mask is not None and not mask(x, y):
                    continue
                f = (x - x0) / w
                if not light_from_right:
                    f = 1.0 - f
                v = f * 3.2 - 0.25 + (0.22 if (x + y) % 2 else -0.22)
                self.put(x, y, tones[max(0, min(3, int(round(v))))])

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

    # --- wing-back armchair, 60x66: oxblood leather, lit from its right (the hearth's side); the room flips the other
    leather = ((66, 16, 16), (108, 28, 24), (152, 46, 36), (198, 84, 58))
    a = Canvas(60, 66, 37)

    def back(x, y):                                           # a tall back with a rounded crown
        if not (9 <= x <= 50 and 4 <= y <= 44):
            return False
        return y >= 12 or ((x - 29.5) / 21.0) ** 2 + ((y - 12) / 8.5) ** 2 <= 1.0
    a.lit(9, 4, 50, 44, leather, mask=back)
    for wx0, wx1, right in ((4, 12, False), (47, 55, True)):  # the wings, flaring forward of the back
        a.lit(wx0, 10, wx1, 46, leather if right else (leather[0], leather[0], leather[1], leather[2]),
              mask=lambda x, y, r=right: y >= 10 + (2 if (x in (4, 55)) else 0))
    for bx, by in ((20, 18), (30, 15), (40, 18), (25, 26), (35, 26), (20, 34), (30, 33), (40, 34)):   # deep buttoning
        a.put(bx, by, leather[0])
        a.put(bx + 1, by, leather[0])
        a.put(bx, by - 1, leather[3])
    a.lit(11, 40, 48, 50, (leather[1], leather[2], leather[3], leather[3]))        # the seat cushion, catching the light
    for x in range(12, 48):
        a.put(x, 50, leather[0])
    for ax0, ax1, right in ((2, 13, False), (46, 57, True)):  # rolled arms: a round front and a lit top
        tones = leather if right else (leather[0], leather[0], leather[1], leather[2])
        a.lit(ax0, 34, ax1, 56, tones)
        a.ellipse((ax0 + ax1) / 2.0, 37, 5.5, 4.0, tones[3] if right else tones[2])
        a.ellipse((ax0 + ax1) / 2.0, 37, 2.5, 1.8, tones[1])
    a.lit(8, 51, 51, 60, (leather[0], leather[1], leather[1], leather[2]))         # the front skirt, in the seat's shadow
    for x in range(10, 50, 4):
        a.put(x, 60, (150, 120, 60))                          # brass nail heads along the skirt
    for x0 in (6, 49):
        a.rect(x0, 61, x0 + 4, 64, deep[2])                   # turned feet
    a.outline(ink)
    out["armchair_inn"] = a.image()

    # --- hearth rug, 5x3 cells: a worn red field, a gold key border, fringe at both ends
    red = ((84, 22, 22), (122, 34, 28), (150, 48, 36))
    gold = (scaled(honey, 0.9), honey)
    r = Canvas(160, 96, 61)
    r.rect(4, 2, 155, 93, red[0])
    r.rect(8, 6, 151, 89, gold[0])
    r.rect(10, 8, 149, 87, red[0])
    r.rect(13, 11, 146, 84, red[1])
    for y in range(11, 85):
        for x in range(13, 147):
            u, v = (x - 13) % 22, (y - 11) % 18
            if abs(u - 11) * 9 + abs(v - 9) * 11 in range(86, 100):            # a lattice of diamonds
                r.put(x, y, gold[0])
            elif abs(u - 11) + abs(v - 9) < 3:
                r.put(x, y, red[2])
            elif r.rng.random() < 0.05:
                r.put(x, y, red[0])                                             # wear
    for x in range(10, 150, 6):                                                 # the key border
        r.rect(x, 7, x + 2, 7, gold[1])
        r.rect(x + 3, 88, x + 5, 88, gold[1])
    for y in range(3, 93, 2):                                                   # fringe
        for x in (1, 2, 3, 156, 157, 158):
            r.put(x, y, gold[1] if x in (2, 157) else gold[0])
    out["rug_inn"] = r.image()                                                  # no outline: a rug lies IN the floor

    # --- bench, 7 cells long: a lit board, its edge, three legs
    bn = Canvas(224, 20, 67)
    bn.wood(1, 1, 222, 9, top, plank=74)
    bn.rect(1, 10, 222, 11, ink)
    for x0 in (6, 106, 208):
        bn.wood(x0, 12, x0 + 9, 18, deep, vertical=True)
    bn.outline(ink)
    out["bench_inn"] = bn.image()

    # --- what stands on the table: plates, mugs, a loaf, a candle (drawn onto a transparent 7-cell strip)
    cream = wall[5]
    pewter = ((70, 68, 70), (116, 114, 116), (160, 158, 156))
    crust = (floor[2], honey)
    th = Canvas(256, 64, 71)   # an overlay on the table's own rect: everything sits on its top (rows 3-36)
    OX, OY = 16, 10

    _put = th.put                                             # rect() and ellipse() draw through put(), so one shift moves all
    th.put = lambda x, y, c, a=255: _put(x + OX, y + OY, c, a)

    def plate(cx):
        th.ellipse(cx, 11, 7, 3, scaled(cream, 0.72))
        th.ellipse(cx, 10, 7, 3, cream)
        th.ellipse(cx, 10, 4, 1.4, scaled(cream, 0.86))

    def mug(x):
        th.rect(x, 6, x + 4, 12, pewter[1])
        th.rect(x + 4, 6, x + 4, 12, pewter[0])
        th.rect(x, 6, x, 12, pewter[2])
        th.rect(x, 5, x + 4, 5, pewter[2])
        th.put(x + 5, 8, pewter[0]); th.put(x + 6, 9, pewter[0]); th.put(x + 5, 10, pewter[0])

    def loaf(x):
        th.ellipse(x + 6, 10, 6.5, 3, crust[0])
        th.ellipse(x + 6, 9, 5.5, 2, crust[1])
        for i in (3, 6, 9):
            th.put(x + i, 9, crust[0])

    def candle(x):
        th.rect(x - 2, 12, x + 3, 13, pewter[0])
        th.rect(x, 5, x + 1, 11, cream)
        th.put(x + 1, 6, scaled(cream, 0.8))
        th.put(x, 3, flame); th.put(x + 1, 3, glow); th.put(x, 2, glow); th.put(x, 1, flame); th.put(x + 1, 4, ember)

    for cx in (18, 78, 146, 204):
        plate(cx)
    for x in (32, 92, 124, 182):
        mug(x)
    loaf(48)
    loaf(158)
    candle(110)
    th.put = _put
    th.outline(ink)
    out["table_things_inn"] = th.image()

    # --- barrel, 28x38: staves that turn with the light, two iron hoops, a lit lid
    staves = (wall[0], floor[1], floor[2], floor[4])
    bl = Canvas(28, 38, 73)

    def belly(x, y):
        bulge = 2 if 12 <= y <= 30 else (1 if 8 <= y <= 34 else 0)
        return 3 - bulge <= x <= 24 + bulge and 6 <= y <= 36
    bl.lit(1, 6, 26, 36, staves, mask=belly)
    for x in (7, 12, 17, 22):
        for y in range(8, 36):
            if belly(x, y):
                bl.put(x, y, ink)
    for hy in (11, 31):
        for x in range(0, 28):
            if belly(x, hy):
                bl.put(x, hy, iron[2] if x > 14 else iron[1])
                bl.put(x, hy + 1, iron[0])
    bl.ellipse(13.5, 6, 10.5, 3.5, top[2])
    bl.ellipse(13.5, 6, 8, 2.2, top[1])
    bl.outline(ink)
    out["barrel_inn"] = bl.image()

    # --- crate, 30x30: a lit top, a slatted front with one brace
    cr = Canvas(30, 30, 79)
    cr.wood(2, 2, 27, 9, top, plank=13)
    cr.rect(2, 10, 27, 10, ink)
    cr.wood(2, 11, 27, 27, face, vertical=True, boards=4)
    for i in range(16):
        cr.put(4 + i * 22 // 16, 12 + i, floor[3])           # the brace's lit edge
        cr.put(5 + i * 22 // 16, 12 + i, wall[0])
    cr.rect(2, 11, 27, 12, floor[1])
    cr.rect(2, 26, 27, 27, wall[0])
    cr.outline(ink)
    out["crate_inn"] = cr.image()

    # --- coat rack, 24x44: a turned pole, pegs, two travelling cloaks that hang in folds, a hat on the finial
    c = Canvas(24, 44, 41)
    c.wood(11, 4, 12, 39, deep, vertical=True)
    c.rect(4, 8, 19, 8, deep[2])                              # the peg bar
    c.rect(5, 40, 18, 41, deep[2])
    c.rect(3, 42, 20, 42, deep[1])
    plum = ((44, 28, 64), (70, 46, 98), (98, 68, 132), (128, 96, 160))
    moss = ((30, 50, 34), (50, 80, 50), (76, 110, 70), (108, 140, 96))
    for cloak, x0, w, y1 in ((plum, 1, 10, 33), (moss, 13, 9, 28)):
        for y in range(9, y1 + 1):
            spread = min(2, (y - 9) // 7)                     # the cloth widens as it falls
            for x in range(x0 - (spread if x0 < 12 else 0), x0 + w + (spread if x0 >= 12 else 0)):
                fold = (x - x0 + (1 if y > 20 else 0)) % 4     # a fold every four pixels: light ridge, dark valley
                tone = cloak[3] if fold == 0 else (cloak[2] if fold == 1 else (cloak[1] if fold == 2 else cloak[0]))
                if y >= y1 - 1 and fold == 3:
                    continue                                   # a scalloped hem
                c.put(x, y, tone)
        c.rect(x0 + 2, 9, x0 + w - 3, 10, cloak[3])           # the collar over the peg
    c.ellipse(11.5, 3.5, 6, 1.6, floor[1])                     # a felt hat's brim
    c.ellipse(11.5, 2, 3, 2, wall[0])
    c.outline(ink)
    out["coat_rack_inn"] = c.image()
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
