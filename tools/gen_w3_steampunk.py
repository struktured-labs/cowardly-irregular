#!/usr/bin/env python3
"""Generate W3's steampunk city at 180x150 (the 60x50 original at 3x, re-authored).

Same programme as gen_w2_suburb.py: the old map is six zones read in seconds; pure
scaling makes it slower, not richer. The steampunk idiom is worked brass and steam --
a city that grew around its machines: a central gear plaza with the fountain, wide
boulevards with lamppost rows, terraced brick residential in the west, an industrial
quarter in the east where pipes cross the streets, a rail line sweeping the south
into a station, alleys threading the blocks, manholes venting on the asphalt.

Zone map (the original's, x3, entity coordinates depend on it):
  top strip     portal approach          rows 0-14
  center        plaza + fountain         rows ~40-70
  west          residential terraces     cols 0-60
  east          industrial               cols 120-179
  south         rail + station           rows 120-140
  southwest     park                     rows 105-135, cols 0-50

Walkable chars: c a m g d r y h. Blocked: b p w i n F f l.
The scene's entity coordinates are old tiles x3; RESERVED keeps each clear.
"""
import json, random, sys
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
PALETTE = REPO / "data/maps/map_palette.json"
OUT = REPO / "data/maps/overworld_w3.png"
W, H = 180, 150
BLOCKED = set("bpwinFfl")

# EVERY entity coordinate in SuburbanOverworld's sibling scene (SteampunkOverworld.gd),
# extracted 2026-08-29, OLD 60x50 tile coords -- scaled x3 here. The complete list lives
# in the generator so a partial batch can never reshuffle the seeded RNG mid-iteration:
# spots are pre-marked before any feature is placed and reclaimed after the last pass.
# test_overworld_map_shape_regression pins the PNG rectangle; the entity-walkability
# guard instantiates the real scene.
ENTITY_SPOTS = [
    (4, 26), (5, 10), (6, 35), (8, 22), (11, 26), (14, 26), (15, 33), (15, 35),
    (16, 35), (18, 18), (19, 19), (22, 17), (22, 20), (22, 40), (22, 43), (25, 20),
    (25, 25), (25, 40), (25, 43), (26, 19), (27, 1), (27, 2), (27, 3), (27, 6),
    (27, 43), (28, 19), (28, 44), (30, 20), (30, 25), (30, 40), (40, 10), (40, 15),
    (42, 15), (45, 8), (45, 10), (45, 15), (45, 30), (46, 16), (46, 30), (47, 9),
    (48, 10), (48, 12), (48, 30), (50, 9), (50, 11), (50, 20), (52, 18),
]


def gen(seed=20260829):
    rng = random.Random(seed)
    g = [["c"] * W for _ in range(H)]

    def rect(x0, y0, x1, y1, ch):
        for y in range(max(0, y0), min(H, y1 + 1)):
            for x in range(max(0, x0), min(W, x1 + 1)):
                g[y][x] = ch

    for (ox, oy) in ENTITY_SPOTS:
        rect(ox * 3 - 1, oy * 3 - 1, ox * 3 + 1, oy * 3 + 1, "_")

    # --- city wall ring: brick, with gaps where boulevards leave ---
    rect(0, 0, W - 1, 1, "b")
    rect(0, H - 2, W - 1, H - 1, "b")
    rect(0, 0, 1, H - 1, "b")
    rect(W - 2, 0, W - 1, H - 1, "b")

    # --- boulevards: asphalt, radiating from the plaza, with jogs ---
    def road_h(y, x0, x1, wd=3):
        rect(x0, y, x1, y + wd - 1, "a")

    def road_v(x, y0, y1, wd=3):
        rect(x, y0, x + wd - 1, y1, "a")

    road_v(87, 2, 147)                 # the portal boulevard, top to rail
    road_h(52, 2, 177)                 # plaza east-west
    road_h(20, 2, 120)                 # north crosstown, stops short of industry
    road_v(30, 20, 118)                # west residential spine
    road_v(138, 2, 52)                 # industrial feeder, ends at the plaza road
    road_v(150, 52, 120)               # jogs east below it
    road_h(100, 30, 177)               # south crosstown

    # --- plaza: metal ring, gear-round fountain ---
    rect(72, 40, 104, 68, "m")
    cx, cy, r = 88, 54, 6
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                g[y][x] = "F"

    # --- residential west: brick terraces with doors/windows, alleys between ---
    def terrace(x0, y0, limit, depth=5, neon=0.35):
        x = x0
        while x < limit:
            wd = rng.choice([6, 7, 8, 9])
            ok = x + wd <= limit and all(
                g[y][xx] == "c" for y in range(y0 - 1, y0 + depth + 1) for xx in range(x - 1, x + wd + 1)
                if 0 <= y < H and 0 <= xx < W)
            if ok and rng.random() < 0.85:
                rect(x, y0, x + wd - 1, y0 + depth - 1, "w")
                for xx in range(x + 1, x + wd - 1, 2):
                    g[y0][xx] = "i"
                g[y0 + depth - 1][x + wd // 2] = "d"
                if rng.random() < neon:
                    g[y0 + depth - 1][x + 1] = "n"
                x += wd + rng.choice([2, 2, 3, 5])
            else:
                x += rng.choice([2, 3, 4])

    # west of the industrial quarter the city is terraced; frontage nearer the
    # plaza gets more neon (commercial), the far west stays residential
    for ty in (5, 14, 25, 34, 45, 58, 71, 82, 93, 106):
        terrace(rng.choice([3, 4, 6]), ty, 116, neon=0.25 if ty < 45 else 0.5)

    # --- industrial east: metal aprons, pipe runs, brick works ---
    rect(120, 4, 176, 96, "m")
    for py in (10, 24, 38, 62, 76, 90):
        y = py + rng.choice([-2, 0, 2])
        seg_x = 122
        while seg_x < 175:
            seg = rng.randint(6, 16)
            rect(seg_x, y, min(seg_x + seg, 175), y, "p")
            seg_x += seg + rng.randint(3, 7)     # gaps let the player cross
    for _ in range(9):
        bx, by = rng.randint(122, 164), rng.randint(6, 84)
        bw, bh = rng.randint(6, 12), rng.randint(5, 9)
        if all(g[y][x] == "m" for y in range(by, min(by + bh, 96)) for x in range(bx, min(bx + bw, 176))):
            rect(bx, by, bx + bw - 1, by + bh - 1, "b")
            g[min(by + bh - 1, 95)][bx + bw // 2] = "d"

    # --- rail: a sweep across the south into a station ---
    for x in range(2, W - 2):
        y = 128 + (x // 24) % 2      # gentle stagger, reads as a curve at tile scale
        rect(x, y, x, y + 1, "r")
    rect(70, 120, 110, 126, "m")     # station platform
    rect(72, 118, 108, 119, "w")
    for xx in range(74, 107, 4):
        g[118][xx] = "i"
    g[119][90] = "d"

    # --- park southwest: grass, fountain pond, fences on the street edge ---
    rect(4, 108, 52, 138, "g")
    rect(20, 118, 27, 124, "F")
    for x in range(4, 53):
        if g[107][x] == "c" and rng.random() < 0.6:
            g[107][x] = "f"

    # --- alleys threading the residential blocks ---
    for ay in (12, 22, 42, 66, 79, 101):
        for x in range(4, 116):
            if g[ay][x] == "c":
                g[ay][x] = "y"

    # --- street furniture: lampposts line the boulevards, manholes dot them ---
    for y in range(2, H - 2):
        for x in range(2, W - 2):
            if g[y][x] != "c":
                continue
            beside_road = any(g[y + dy][x + dx] == "a" for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if beside_road and (x + y) % 9 == 0 and rng.random() < 0.5:
                g[y][x] = "l"
    for _ in range(50):
        x, y = rng.randrange(W), rng.randrange(H)
        if g[y][x] == "a" and rng.random() < 0.5:
            g[y][x] = "h"

    # --- resolve reservations; reclaim any cell later passes built over.
    # Final char is zone-appropriate: metal in the industrial quarter, grass in the
    # park, concrete elsewhere -- deterministic, no RNG.
    for (ox, oy) in ENTITY_SPOTS:
        rx, ry = ox * 3, oy * 3
        final = "m" if rx >= 120 and ry <= 96 else ("g" if rx <= 52 and ry >= 108 else "c")
        for y in range(ry - 1, ry + 2):
            for x in range(rx - 1, rx + 2):
                if 0 <= x < W and 0 <= y < H and (g[y][x] == "_" or g[y][x] in BLOCKED):
                    g[y][x] = final

    # --- close sealed 1-tile pockets ---
    for y in range(H):
        for x in range(W):
            if g[y][x] in BLOCKED:
                continue
            nbrs = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            if all(not (0 <= nx < W and 0 <= ny < H) or g[ny][nx] in BLOCKED for nx, ny in nbrs):
                g[y][x] = "b"

    return g


def main():
    pal = json.load(open(PALETTE))["worlds"]["steampunk"]
    ch2rgb = {ch: tuple(v["rgb"]) for sec in ("terrain", "landmarks") for ch, v in pal[sec].items()}
    g = gen()
    used = sorted({c for row in g for c in row})
    unknown = [c for c in used if c not in ch2rgb]
    if unknown:
        sys.exit(f"characters with no steampunk palette entry: {unknown!r}")
    counts = {c: sum(row.count(c) for row in g) for c in used}
    print(f"  {W}x{H} = {W*H} tiles   chars {len(used)}")
    for c in sorted(counts, key=lambda k: -counts[k]):
        print(f"    {c!r} {counts[c]:6d}  {100*counts[c]/(W*H):5.1f}%")
    if "--dry-run" in sys.argv:
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
