#!/usr/bin/env python3
"""Generate the medieval cliff/overlay tile atlas for the TileSheetManifest seam.

Brief: docs/art/tile-sheet-brief-medieval.md. The seam (src/exploration/
TileSheetManifest.gd) has shipped EMPTY -- `tile_sheets` is {} on main, so
every cell is still procedural. It is partial-set by contract: name one
region and the rest keeps its procedural drawing.

SCOPE -- deliberately the COMBINATORIAL half, and nothing else:

    cliff    face + edge_1..edge_15      16 regions
    overlay  fringe_1..fringe_15         15 regions
             stair · ramp · shadow        3 regions
                                        ---
                                         34

`edge_N` and `fringe_N` are a BITMASK (N=1 E=2 S=4 W=8). Those 30 tiles are
pure geometry -- the same lip or the same tuft repeated on whichever sides
the mask flags. Hand-drawing 30 combinations invites exactly one transposed
mask that nobody sees until a ledge has a gap in it, and prompting an image
model for them is worse: it cannot count to fifteen in binary. Generating
them from the mask is correct by construction, and the ARM- check at the
bottom proves each tile touches its flagged edges and only those.

NOT IN SCOPE, on purpose:
  * ground tiles (VILLAGE_GRASS etc.) -- TileGenerator already draws these
    and a programmatic sheet would only reproduce its own output.
  * the 10 props (TREE/WELL/CART/...) -- representational objects, the half
    of the brief that actually wants an artist. Routed, not generated.

GEOMETRY IS MATCHED TO THE PROCEDURAL, NOT IMPROVED ON: 2px lip + 1px inner
shadow, 4 stair steps of 5px tread + 3px riser, a 12px shadow falloff. The
brief asks a partial sheet to sit beside procedural neighbours, so the
silhouettes must agree; what this upgrades is the pixel craft inside them
(masonry courses instead of sine striations, tapered grass blades instead of
2px bars, dithered gradients instead of banded ones, and corner joins that
don't double-darken where two lips meet).

Collision is unchanged and untouchable: EDGE_THICKNESS 4.0 strips and the
face's full-cell box are set by id in EnvironmentTileSets. Art never moves a
collider.

Output: assets/sprites/tiles/medieval.png (512x96) + a manifest entry.
"""
import argparse
import json
import os
import sys
from pathlib import Path

from PIL import Image

TILE = 32
COLS = 16

# src/exploration/EnvironmentTileSets.gd DEFAULT_PALETTE, read from source not the brief
PAL = {
    "face_dark":   (0.30, 0.26, 0.24, 1.0),
    "face_mid":    (0.46, 0.40, 0.36, 1.0),
    "face_light":  (0.60, 0.54, 0.48, 1.0),
    "lip":         (0.82, 0.78, 0.66, 1.0),
    "lip_shadow":  (0.22, 0.19, 0.17, 0.85),
    "grass":       (0.38, 0.62, 0.28, 1.0),
    "grass_light": (0.50, 0.74, 0.34, 1.0),
    "stair_tread": (0.72, 0.68, 0.60, 1.0),
    "stair_riser": (0.40, 0.36, 0.32, 1.0),
}
N, E, S, W = 1, 2, 4, 8


def c(key, mul=1.0, alpha=None):
    r, g, b, a = PAL[key]
    out = tuple(max(0, min(255, int(round(v * mul * 255)))) for v in (r, g, b))
    return out + (int(round((a if alpha is None else alpha) * 255)),)


def lerp(c1, c2, t):
    return tuple(int(round(a + (b - a) * t)) for a, b in zip(c1, c2))


def h(*args):
    """Deterministic small hash -- no Math.random, same sheet every run."""
    v = 2166136261
    for a in args:
        v = ((v ^ (a & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    return v


def new_tile():
    return Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))


# ---------------------------------------------------------------- cliff face
def draw_face():
    """A ledge reads as a ledge only with a lit top, a darkening body and a
    black foot. Procedural does that with sine striations; this does it with
    staggered masonry courses, which is the same value structure with a
    medieval read."""
    img = new_tile()
    px = img.load()
    light, mid, dark = c("face_light"), c("face_mid"), c("face_dark")
    for y in range(TILE):
        t = y / (TILE - 1)
        base = lerp(lerp(light, mid, min(1.0, t * 1.6)), dark, max(0.0, min(1.0, (t - 0.55) * 2.2)))
        for x in range(TILE):
            px[x, y] = base
    # staggered stone courses, 7px tall, mortar at the course line
    course_h = 7
    mortar = tuple(int(v * 0.62) for v in dark[:3]) + (255,)
    for ci, y0 in enumerate(range(3, TILE - 3, course_h)):
        offset = (ci % 2) * 6
        for x in range(TILE):
            if 0 <= y0 < TILE:
                px[x, y0] = mortar
        bx = -offset
        while bx < TILE:
            w = 11 + (h(ci, bx) % 5)
            edge = bx + w
            for y in range(y0 + 1, min(TILE - 3, y0 + course_h)):
                if 0 <= edge < TILE:
                    px[edge, y] = mortar
            # per-stone value jitter so the courses don't read as a grid
            j = ((h(ci, bx, 7) % 5) - 2) * 0.035
            for y in range(y0 + 1, min(TILE - 3, y0 + course_h)):
                for x in range(max(0, bx), min(TILE, edge)):
                    r, g, b, a = px[x, y]
                    px[x, y] = (max(0, min(255, int(r * (1 + j)))),
                                max(0, min(255, int(g * (1 + j)))),
                                max(0, min(255, int(b * (1 + j)))), a)
            # lit top-left chamfer on each stone
            for x in range(max(0, bx + 1), min(TILE, edge)):
                if y0 + 1 < TILE - 3:
                    r, g, b, a = px[x, y0 + 1]
                    px[x, y0 + 1] = lerp((r, g, b, a), light, 0.35)
            bx += w
    # lit lip on top (2px) + highlight row -- matches procedural exactly
    for x in range(TILE):
        px[x, 0] = c("lip")
        px[x, 1] = c("lip")
        px[x, 2] = light
    # near-black foot (3px)
    foot = tuple(int(v * 0.55) for v in dark[:3]) + (255,)
    for y in range(TILE - 3, TILE):
        for x in range(TILE):
            px[x, y] = foot
    return img


# ---------------------------------------------------------------- cliff edges
def draw_edge(mask):
    """Lip on each flagged side: 2px lip + 1px inner shadow, matching
    _draw_edge_tile's geometry. Improvement is the corner join -- procedural
    overlaps rectangles so two adjacent lips double-darken where the shadow
    rows cross; here the shadow is written only where no lip already sits."""
    img = new_tile()
    px = img.load()
    lip, sh = c("lip"), c("lip_shadow")
    lip_hi = lerp(lip, (255, 255, 255, 255), 0.35)
    lip_cells, shadow_cells = set(), set()
    if mask & N:
        lip_cells |= {(x, y) for x in range(TILE) for y in (0, 1)}
        shadow_cells |= {(x, 2) for x in range(TILE)}
    if mask & S:
        lip_cells |= {(x, y) for x in range(TILE) for y in (TILE - 2, TILE - 1)}
        shadow_cells |= {(x, TILE - 3) for x in range(TILE)}
    if mask & W:
        lip_cells |= {(x, y) for y in range(TILE) for x in (0, 1)}
        shadow_cells |= {(2, y) for y in range(TILE)}
    if mask & E:
        lip_cells |= {(x, y) for y in range(TILE) for x in (TILE - 2, TILE - 1)}
        shadow_cells |= {(TILE - 3, y) for y in range(TILE)}
    for (x, y) in shadow_cells - lip_cells:
        px[x, y] = sh
    for (x, y) in lip_cells:
        px[x, y] = lip
    # 1px specular on the outermost row of each lip, dithered so it reads as
    # stone catching light rather than a drawn line
    def spec(pts):
        for i, (x, y) in enumerate(pts):
            if (h(x, y) % 3) != 0:
                px[x, y] = lip_hi
    if mask & N: spec([(x, 0) for x in range(TILE)])
    if mask & S: spec([(x, TILE - 1) for x in range(TILE)])
    if mask & W: spec([(0, y) for y in range(TILE)])
    if mask & E: spec([(TILE - 1, y) for y in range(TILE)])
    return img


# ------------------------------------------------------------------- fringes
def draw_fringe(mask):
    """Grass creeping onto a path cell from the flagged sides. Procedural
    draws 2px bars; these are tapered blades, which is what sells it at
    zoom 2."""
    img = new_tile()
    px = img.load()
    g, gl = c("grass"), c("grass_light")
    gd = tuple(int(v * 0.72) for v in g[:3]) + (255,)

    def blade(ax, ay, dx, dy, length, seed):
        """Grow a blade inward from (ax,ay) along (dx,dy), tapering."""
        col = [gd, g, gl][h(seed) % 3]
        for i in range(length):
            x, y = ax + dx * i, ay + dy * i
            if not (0 <= x < TILE and 0 <= y < TILE):
                return
            px[x, y] = col
            # widen the base: the first 40% of the blade gets a second pixel
            if i < max(1, int(length * 0.4)):
                wx, wy = (x + dy, y + dx)
                if 0 <= wx < TILE and 0 <= wy < TILE:
                    px[wx, wy] = col
            # lean near the tip
            if i > length * 0.6 and (h(seed, i) % 2):
                ax += dy
                ay += dx

    # Blades start INSET from the corners. Two reasons, and the second is the
    # one that showed up as a self-check failure: a west blade rooted at row 0
    # grows east straight through the north sample band, and where two fringe
    # tiles meet, corner tufts from both stack into a visible dense clump.
    for i in range(4, TILE - 4, 3):
        ln = 3 + (h(i, mask) % 5)
        if mask & N: blade(i, 0, 0, 1, ln, h(i, mask, 1))
        if mask & S: blade(i, TILE - 1, 0, -1, ln, h(i, mask, 2))
        if mask & W: blade(0, i, 1, 0, ln, h(i, mask, 3))
        if mask & E: blade(TILE - 1, i, -1, 0, ln, h(i, mask, 4))
    return img


# --------------------------------------------------------------------- stair
def draw_stair():
    """Treads run north-south, one tile bridges one tier. 4 steps of 5px
    tread + 3px riser, matching procedural; adds a lit nosing on each tread
    so the steps read as steps from two tiles away (the brief's bar)."""
    img = new_tile()
    px = img.load()
    tread, riser = c("stair_tread"), c("stair_riser")
    nosing = lerp(tread, (255, 255, 255, 255), 0.40)
    riser_dark = tuple(int(v * 0.75) for v in riser[:3]) + (255,)
    for step in range(4):
        y = step * 8
        for yy in range(y, min(TILE, y + 5)):
            for x in range(2, TILE - 2):
                px[x, yy] = tread
        for x in range(2, TILE - 2):
            if y < TILE:
                px[x, y] = nosing
        for yy in range(y + 5, min(TILE, y + 8)):
            for x in range(2, TILE - 2):
                px[x, yy] = riser if yy == y + 5 else riser_dark
    # side rails, bevelled
    for y in range(TILE):
        px[0, y] = riser_dark
        px[1, y] = riser
        px[TILE - 2, y] = riser
        px[TILE - 1, y] = riser_dark
    return img


# ---------------------------------------------------------------------- ramp
def draw_ramp():
    """An incline bridging one tier. The procedural draws diagonal riser lines
    on a flat fill, which at zoom 2 reads as hatching rather than slope -- the
    diagonals carry the texture but nothing carries the HEIGHT. Same diagonals
    here, softened, over a strong dark-at-the-bottom gradient so the value
    ramp does the depth work and the lines only say "traction"."""
    img = new_tile()
    px = img.load()
    tread, riser = c("stair_tread"), c("stair_riser")
    top = lerp(tread, (255, 255, 255, 255), 0.18)
    for y in range(TILE):
        t = y / (TILE - 1)
        shade = lerp(top, riser, t * 0.92)
        for x in range(TILE):
            px[x, y] = shade
    # traction lines, low contrast against the local value so they never
    # out-shout the gradient
    for d in range(0, TILE * 2, 5):
        for x in range(TILE):
            y = d - x
            if 0 <= y < TILE:
                r, g, b, a = px[x, y]
                px[x, y] = (int(r * 0.86), int(g * 0.86), int(b * 0.86), a)
    # side rails tie it to the stair tile so the two read as one family
    rail = tuple(int(v * 0.75) for v in riser[:3]) + (255,)
    for y in range(TILE):
        px[0, y] = rail
        px[TILE - 1, y] = rail
    return img


# -------------------------------------------------------------------- shadow
def draw_shadow():
    """The ledge's cast shadow, painted on the cell under a face. 12px
    falloff as specified. Ordered dither on the tail -- a straight alpha ramp
    bands visibly against flat procedural ground at zoom 2."""
    img = new_tile()
    px = img.load()
    BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    for y in range(12):
        t = y / 12.0
        a = 0.55 * (1.0 - t)
        a = a * a + 0.08 * (1.0 - t)
        for x in range(TILE):
            av = a * 255.0
            thr = (BAYER[y % 4][x % 4] + 0.5) / 16.0 * 26.0
            px[x, y] = (13, 10, 20, int(max(0, min(255, av + (thr - 13)))))
    return img


# ------------------------------------------------------------------- assembly
def build():
    """Layout: row0 = face + edge_1..15, row1 = fringe_1..15 + stair,
    row2 = ramp, shadow."""
    sheet = Image.new("RGBA", (COLS * TILE, 3 * TILE), (0, 0, 0, 0))
    regions = {"cliff": {}, "overlay": {}}

    def place(img, col, row, section, name):
        sheet.paste(img, (col * TILE, row * TILE))
        regions[section][name] = [col, row]

    place(draw_face(), 0, 0, "cliff", "face")
    for m in range(1, 16):
        place(draw_edge(m), m, 0, "cliff", "edge_%d" % m)
    for m in range(1, 16):
        place(draw_fringe(m), m - 1, 1, "overlay", "fringe_%d" % m)
    place(draw_stair(), 15, 1, "overlay", "stair")
    place(draw_ramp(), 0, 2, "overlay", "ramp")
    place(draw_shadow(), 1, 2, "overlay", "shadow")
    return sheet, regions


def self_check(sheet, regions):
    """ARM-: every edge/fringe must have ink on its flagged sides and NONE on
    its unflagged ones. A transposed bitmask is the one defect this whole
    approach exists to prevent, so it is checked rather than trusted."""
    fails = []
    SIDES = {N: "N", E: "E", S: "S", W: "W"}

    def side_ink(img, bit):
        """Sample the MIDDLE of a side, never the corners. A north lip spans the
        full tile width, so its first 3 columns legitimately sit inside the WEST
        sample band -- a naive full-length band reports exactly 18 stray px on
        every two-sided mask and calls correct art broken. That false positive
        fired on the first run of this file and nearly got the ART 'fixed'."""
        px = img.load()
        band, span = range(3), range(6, TILE - 6)
        if bit == N:   pts = [(x, y) for x in span for y in band]
        elif bit == S: pts = [(x, TILE - 1 - y) for x in span for y in band]
        elif bit == W: pts = [(y, x) for x in span for y in band]
        else:          pts = [(TILE - 1 - y, x) for x in span for y in band]
        return sum(1 for (x, y) in pts if px[x, y][3] > 0)

    for section, prefix, n in (("cliff", "edge_", 16), ("overlay", "fringe_", 16)):
        for m in range(1, n):
            col, row = regions[section]["%s%d" % (prefix, m)]
            img = sheet.crop((col * TILE, row * TILE, (col + 1) * TILE, (row + 1) * TILE))
            for bit, lab in SIDES.items():
                ink = side_ink(img, bit)
                if (m & bit) and ink == 0:
                    fails.append("%s%d: side %s FLAGGED but blank" % (prefix, m, lab))
                if not (m & bit) and ink > 0:
                    fails.append("%s%d: side %s UNFLAGGED but has %d px" % (prefix, m, lab, ink))
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game-repo", default=os.environ.get("GAME_REPO", ""))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if not args.game_repo:
        sys.exit("pass --game-repo or set GAME_REPO")
    repo = Path(args.game_repo)
    if not repo.exists():
        sys.exit("no such repo: %s" % repo)

    sheet, regions = build()
    fails = self_check(sheet, regions)
    print("=== bitmask self-check (30 tiles x 4 sides) ===")
    if fails:
        for f in fails:
            print("  FAIL", f)
        sys.exit("bitmask self-check failed -- refusing to write")
    print("  120/120 side assertions pass")

    out_png = repo / "assets/sprites/tiles/medieval.png"
    if args.dry_run:
        print("DRY RUN -- would write %s (%dx%d) and %d regions"
              % (out_png, sheet.size[0], sheet.size[1],
                 sum(len(v) for v in regions.values())))
        return 0
    out_png.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_png)
    print("wrote %s  %dx%d" % (out_png, *sheet.size))

    mpath = repo / "data/sprite_manifest.json"
    man = json.loads(mpath.read_text())
    man.setdefault("tile_sheets", {})["medieval"] = {
        "path": "res://assets/sprites/tiles/medieval.png",
        "tier": "T1",
        "tile": TILE,
        "cliff": regions["cliff"],
        "overlay": regions["overlay"],
        "generator": ("tools/gen_tile_sheet_medieval.py -- cliff+overlay only. "
                      "Ground tiles stay procedural (TileGenerator already draws them); "
                      "the 10 props are routed to the artist. Bitmask tiles are generated "
                      "from the mask and side-checked, never hand-placed."),
    }
    mpath.write_text(json.dumps(man, indent=2) + "\n")
    print("registered tile_sheets.medieval: %d cliff + %d overlay regions"
          % (len(regions["cliff"]), len(regions["overlay"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
