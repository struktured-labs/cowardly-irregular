#!/usr/bin/env python3
"""Generate W2's suburb at 150x120 with real neighbourhood structure.

WHY NOT JUST SCALE. Upscaling the 50x40 original 3x gives a map that is three
times slower to cross and carries exactly the same content: roads become three
tiles wide, every house becomes a 3x3 block of the same tile. Bigger, not richer
-- the same outcome the W1 rescale produced before its ground pass.

WHY THE ORIGINAL READS FLAT. It is six horizontal bands with no vertical street
anywhere, so the whole world is stripes. The first version of this file fixed
that with evenly spaced avenues -- a subdivision plat. struktured 2026-08-29:
"think earthbound neighborhoods or mother3 for insrpiation". Onett and Tazmily
are not grids: streets jog and dead-end, blocks differ in size, buildings differ
in footprint, greenery grows in clumps. So avenue spacing varies, two avenues jog
at a road crossing, one dead-ends into a cul-de-sac, and trees cluster.

ZONE BANDS ARE PRESERVED AT 3x, DELIBERATELY. Chests, the save point, signposts
and transitions are hardcoded tile coordinates in SuburbanOverworld.gd. Scaling
those by 3 lands them in the same zone only if the zones sit where 3x says they
do, so the band table below is the original's comment header multiplied by 3 and
must stay that way. Entity placement is verified against the generated map
afterwards, not assumed.

Legend follows the scene's own: s=SIDEWALK r=ROAD h=HOUSE_WALL l=LAWN
t=STORE_FRONT d=HOUSE_DOOR w=HOUSE_WINDOW f=PICKET_FENCE m=MAILBOX y=FIRE_HYDRANT
p=PLAYGROUND k=PARKING_LOT e=SHADE_TREE b=PARK_BENCH c=BASKETBALL_COURT g=FLOWER_BED
"""
import json, random, sys
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
PALETTE = REPO / "data/maps/map_palette.json"
OUT = REPO / "data/maps/overworld_w2.png"
W, H = 150, 120
SCALE = 3  # the factor the scene's entity coordinates are multiplied by

# original band comments x3; rows are inclusive
BANDS = [
    ("residential", 0, 38),
    ("main_road", 39, 44),
    ("mall", 45, 62),
    ("side_road", 63, 68),
    ("park", 69, 98),
    ("south_edge", 99, 119),
]


# The scene's entity coordinates (chests, spawns, portals, NPC paths) are the old
# 50x40 tile positions x3. The map must leave those cells walkable, so each gets a
# reserved clearing: marked '_' during generation (nothing builds on non-lawn), then
# resolved to its final char at the end. (x, y, radius, final_char), scaled coords.
RESERVED = [
    (132, 12, 1, "l"),   # chest w2_backyard_gold
    (135, 60, 2, "s"),   # forward portal (objective + signpost + transition)
    (138, 60, 2, "s"),   # spawn from_industrial
    (69, 36, 1, "l"),    # spawn entrance / default / suburban_portal
    (45, 60, 1, "s"),    # NPC patrol corner
    (120, 15, 1, "l"),   # NPC Suspicious Dave
    (9, 60, 1, "s"),     # NPC Pizza Delivery Pete
]


def gen(seed=20260829):
    rng = random.Random(seed)
    g = [["l"] * W for _ in range(H)]

    for (rx, ry, rr, _final) in RESERVED:
        for y in range(ry - rr, ry + rr + 1):
            for x in range(rx - rr, rx + rr + 1):
                if 0 <= x < W and 0 <= y < H:
                    g[y][x] = "_"

    def rect(x0, y0, x1, y1, ch):
        for y in range(max(0, y0), min(H, y1 + 1)):
            for x in range(max(0, x0), min(W, x1 + 1)):
                g[y][x] = ch

    def road_v(x, y0, y1):
        rect(x, y0, x + 1, y1, "r")
        rect(x - 1, y0, x - 1, y1, "s")
        rect(x + 2, y0, x + 2, y1, "s")

    def road_h(y, x0, x1):
        rect(x0, y, x1, y + 1, "r")
        rect(x0, y - 1, x1, y - 1, "s")
        rect(x0, y + 2, x1, y + 2, "s")

    # --- streets. Irregular spacing, and two of them JOG partway down so no
    # avenue runs the full height dead straight; one ends in a cul-de-sac.
    road_h(39, 0, W - 1)          # main road, the one constant
    road_h(63, 0, W - 1)          # side road

    avenues = []                  # (x, y0, y1) segments actually painted
    road_v(18, 0, 41)
    road_v(14, 41, 65)            # jogs west below the main road, ends at the side road
    avenues += [(18, 0, 41), (14, 41, 65)]

    road_v(47, 0, H - 1)          # the one straight through-street
    avenues += [(47, 0, H - 1)]

    road_v(79, 0, 65)
    road_v(86, 65, H - 1)         # jogs east below the side road
    avenues += [(79, 0, 65), (86, 65, H - 1)]

    road_v(118, 0, 44)            # dead-ends into a cul-de-sac
    rect(112, 44, 124, 50, "r")
    rect(111, 43, 125, 43, "s")
    rect(111, 51, 125, 51, "s")
    avenues += [(118, 0, 44)]

    def near_street(x, y, pad=2):
        for (ax, y0, y1) in avenues:
            if y0 - pad <= y <= y1 + pad and ax - 1 - pad <= x <= ax + 2 + pad:
                return True
        return False

    # --- buildings. Three footprints, placed along the streets facing them.
    def build(hx, hy, wd, ht, kind="h"):
        for y in range(hy - 1, hy + ht + 1):
            for x in range(hx - 1, hx + wd + 1):
                if not (0 <= x < W and 0 <= y < H) or g[y][x] != "l":
                    return False
        rect(hx, hy, hx + wd - 1, hy + ht - 1, kind)
        for x in range(hx, hx + wd, 2):
            g[hy][x] = "w"
        g[hy + ht - 1][hx + wd // 2] = "d"
        if rng.random() < 0.7:
            for x in range(hx - 1, hx + wd + 1):
                if 0 <= x < W and hy - 1 >= 0 and g[hy - 1][x] == "l":
                    g[hy - 1][x] = "f"
        if hy + ht < H and g[hy + ht][hx] == "l":
            g[hy + ht][hx] = "m"
        return True

    placed = 0
    # residential rows, deliberately uneven: gaps and varied footprints
    for row_y in (4, 13, 22, 31):
        x = rng.choice([2, 3, 5])
        while x < W - 10:
            wd, ht = rng.choice([(5, 4), (6, 5), (7, 4), (9, 6)])
            yy = row_y + rng.choice([-2, -1, 0, 0, 1, 2])
            if rng.random() < 0.78 and not near_street(x, yy, 1) and build(x, yy, wd, ht):
                placed += 1
                x += wd + rng.choice([3, 4, 6, 9])
            else:
                x += rng.choice([3, 5, 7])

    # --- commercial strip: storefronts around a plaza, not a uniform row
    rect(0, 45, W - 1, 46, "s")
    rect(2, 47, W - 1, 54, "k")
    plaza = (56, 47, 74, 58)
    rect(*plaza, "s")
    for _ in range(30):
        x, y = rng.randrange(plaza[0], plaza[2]), rng.randrange(plaza[1], plaza[3])
        if g[y][x] == "s" and rng.random() < 0.25:
            g[y][x] = rng.choice(["b", "g", "e"])
    for x, wd in ((4, 12), (20, 9), (33, 14), (78, 11), (95, 16), (117, 10), (131, 13)):
        if near_street(x, 56, 0):
            continue
        if any(g[y][xx] == "_" for y in range(55, 61) for xx in range(x, x + wd) if xx < W):
            continue
        rect(x, 55, x + wd - 1, 60, "t")
        g[60][x + wd // 2] = "d"
    rect(0, 61, W - 1, 62, "s")

    # --- park: amenities placed off-centre, greenery in clumps
    rect(6, 72, 21, 82, "p")
    rect(60, 70, 80, 84, "c")
    rect(97, 78, 116, 90, "p")
    rect(30, 88, 44, 94, "c")

    def clump(x0, y0, x1, y1, ch, n, size):
        for _ in range(n):
            cx, cy = rng.randrange(x0, x1), rng.randrange(y0, y1)
            for _ in range(size):
                dx, dy = rng.randint(-3, 3), rng.randint(-3, 3)
                x, y = cx + dx, cy + dy
                if 0 <= x < W and 0 <= y < H and g[y][x] == "l":
                    g[y][x] = ch

    clump(0, 66, W, 99, "e", 26, 9)
    clump(0, 66, W, 99, "g", 14, 5)
    for _ in range(26):
        x, y = rng.randrange(W), rng.randrange(66, 99)
        if g[y][x] == "l":
            g[y][x] = "b"

    # --- south edge: a lane back out, woodland either side
    road_h(104, 0, W - 1)
    clump(0, 99, W, H, "e", 22, 10)
    clump(0, 99, W, H, "g", 9, 4)

    # --- residential greenery, clustered rather than sprinkled
    clump(0, 0, W, 39, "e", 24, 7)
    clump(0, 0, W, 39, "g", 12, 4)

    # --- hydrants on sidewalks, sparse
    for _ in range(40):
        x, y = rng.randrange(W), rng.randrange(H)
        if g[y][x] == "s" and rng.random() < 0.35:
            g[y][x] = "y"

    BLOCKED = set("htwfmyeb")
    for (rx, ry, rr, final) in RESERVED:
        for y in range(ry - rr, ry + rr + 1):
            for x in range(rx - rr, rx + rr + 1):
                if not (0 <= x < W and 0 <= y < H):
                    continue
                # '_' survives untouched ground; the impassable check catches cells a
                # road repainted first and a later scatter pass (hydrants) then built on
                if g[y][x] == "_" or g[y][x] in BLOCKED:
                    g[y][x] = final

    # a walkable cell with four impassable neighbours is a sealed 1-tile pocket;
    # roaming monsters can spawn on any walkable tile, so close them
    for y in range(H):
        for x in range(W):
            if g[y][x] in BLOCKED:
                continue
            nbrs = [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]
            if all(not (0 <= nx < W and 0 <= ny < H) or g[ny][nx] in BLOCKED for nx, ny in nbrs):
                g[y][x] = "e"

    return g, placed


def main():
    pal = json.load(open(PALETTE))["worlds"]["suburban"]
    ch2rgb = {ch: tuple(v["rgb"]) for sec in ("terrain", "landmarks") for ch, v in pal[sec].items()}
    g, placed = gen()

    used = sorted({c for row in g for c in row})
    unknown = [c for c in used if c not in ch2rgb]
    if unknown:
        sys.exit(f"characters with no suburban palette entry: {unknown!r}")

    counts = {c: sum(row.count(c) for row in g) for c in used}
    print(f"  {W}x{H} = {W*H} tiles   houses placed {placed}   chars {len(used)}")
    for c in sorted(counts, key=lambda k: -counts[k]):
        print(f"    {c!r} {counts[c]:6d}  {100*counts[c]/(W*H):5.1f}%")

    if "--dry-run" in sys.argv:
        print("  --dry-run: nothing written")
        return
    out = Path(sys.argv[sys.argv.index("--out") + 1]) if "--out" in sys.argv else OUT
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        for x in range(W):
            px[x, y] = ch2rgb[g[y][x]]
    im.save(out)
    print(f"  wrote {out}")


if __name__ == "__main__":
    main()
