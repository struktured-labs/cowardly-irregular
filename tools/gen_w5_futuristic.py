#!/usr/bin/env python3
"""Generate W5's digital cityscape at 165x135 (the 55x45 original at 3x, re-authored).

Fourth of the series. The futuristic idiom is a motherboard seen from above: server
farm rows in the north with cooling channels between them, a data plaza whose highways
run like bus traces and bend at right angles ONLY (nothing organic here -- W5's
character is precision, the opposite of W2's suburbs), stacked residential pod blocks
east off narrow corridors, a pixel garden south where the simulation grows something
green, scan gates on the highway chokepoints, glitch tiles fraying the far edge where
the world runs out -- foreshadowing W6, which is what W5 decays into.

Walkable: c d v f p X a. Blocked: S h P T A E G N V.
(HOLOGRAM_DISPLAY blocks per the tile generator? No -- h is NOT in the impassable
list; holograms are walk-through. Blocked set below is the generator's own.)
ENTITY_SPOTS: every coordinate in FuturisticOverworld.gd (old 55x45 tiles, x3 here).
"""
import json, random, sys
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
PALETTE = REPO / "data/maps/map_palette.json"
OUT = REPO / "data/maps/overworld_w5.png"
W, H = 165, 135
BLOCKED = set("SPTAEGNV")

ENTITY_SPOTS = [
    (8, 24), (14, 6), (15, 10), (20, 15), (20, 20), (20, 32), (22, 18), (22, 32),
    (24, 6), (25, 15), (25, 20), (25, 40), (26, 34), (27, 2), (27, 3), (27, 7),
    (27, 12), (27, 17), (27, 20), (27, 35), (27, 37), (27, 40), (27, 42), (30, 8),
    (30, 17), (30, 20), (30, 36), (32, 18), (35, 30), (35, 35), (35, 38), (40, 30),
    (40, 32), (40, 34), (40, 35), (44, 20), (44, 22), (45, 20), (45, 32), (47, 24),
    (49, 20),
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

    # --- neon perimeter ---
    rect(0, 0, W - 1, 0, "N")
    rect(0, H - 1, W - 1, H - 1, "N")
    rect(0, 0, 0, H - 1, "N")
    rect(W - 1, 0, W - 1, H - 1, "N")

    # --- data highways: bus traces, right angles only ---
    rect(2, 40, W - 3, 42, "d")
    rect(2, 96, 110, 98, "d")
    rect(80, 2, 82, 40, "d")
    rect(80, 42, 82, 132, "d")
    rect(30, 42, 32, 96, "d")
    rect(128, 2, 130, 40, "d")
    rect(128, 42, 130, 70, "d")
    rect(110, 68, 130, 70, "d")     # the east highway turns instead of continuing
    # scan gates at chokepoints: single-row arches the player passes under
    for (gx, gy) in ((81, 20), (31, 66), (129, 30)):
        g[gy][gx - 1] = "G"
        g[gy][gx + 2] = "G" if gx + 2 < W else g[gy][gx + 2]

    # --- north server farm: tower rows, cooling channels, fiber conduits ---
    for sy in (4, 12, 20, 28):
        x = 4
        while x < W - 8:
            if x < 78 or x > 84:    # leave the highway corridor
                wd = rng.choice([4, 5, 6])
                ok = all(g[y][xx] == "c" for y in range(sy, sy + 4) for xx in range(x, x + wd))
                if ok:
                    rect(x, sy, x + wd - 1, sy + 3, "S")
                    if rng.random() < 0.7:
                        g[sy + 3][x] = "v"
            x += rng.choice([7, 8, 9])
    for fy in (9, 17, 25, 33):
        for x in range(3, W - 3):
            if g[fy][x] == "c" and rng.random() < 0.5:
                g[fy][x] = "f"

    # --- data plaza: hologram displays, terminal hub, energy cells ---
    rect(52, 48, 112, 88, "c")
    rect(76, 62, 88, 72, "T")
    rect(80, 72, 84, 72, "c")       # hub entrance gap
    for _ in range(26):
        x, y = rng.randint(54, 110), rng.randint(48, 88)
        if g[y][x] == "c":
            g[y][x] = rng.choice(["h", "h", "E", "v"])

    # --- east residential pods: stacked blocks off narrow corridors ---
    for py in range(46, 126, 10):
        x = 136
        while x < W - 6:
            ok = all(g[y][xx] == "c" for y in range(py, py + 6) for xx in range(x, x + 5))
            if ok:
                rect(x, py, x + 4, py + 5, "P")
                g[py + 5][x + 2] = "a"     # access panel doorway
            x += 7
    # pods west of the corridor too, sparser
    for py in range(50, 120, 14):
        for x in (112, 120):
            ok = all(g[y][xx] == "c" for y in range(py, py + 5) for xx in range(x, x + 4))
            if ok and rng.random() < 0.7:
                rect(x, py, x + 3, py + 4, "P")
                g[py + 4][x + 1] = "a"

    # --- center-west: capacitor banks -- antenna clusters off the residential spine ---
    for by in (48, 62, 76):
        x = 8
        while x < 26:
            ok = all(g[y][xx] == "c" for y in range(by, by + 4) for xx in range(x, x + 4))
            if ok and rng.random() < 0.8:
                rect(x, by, x + 3, by + 3, "A")
                if rng.random() < 0.6:
                    g[by + 3][x - 1 if x > 8 else x + 4] = "v"
            x += 6
    for _ in range(30):
        x, y = rng.randint(36, 76), rng.randint(46, 92)
        if g[y][x] == "c":
            g[y][x] = rng.choice(["h", "E", "f", "v"])

    # --- south pixel garden: the simulation grows something green ---
    rect(8, 104, 70, 128, "p")
    for _ in range(40):
        x, y = rng.randint(8, 70), rng.randint(104, 128)
        if g[y][x] == "p" and rng.random() < 0.4:
            g[y][x] = rng.choice(["c", "E", "h"])

    # --- west of the garden and the far edges: the world frays ---
    for _ in range(120):
        x = rng.choice(list(range(2, 10)) + list(range(W - 10, W - 2)))
        y = rng.randint(2, H - 3)
        if g[y][x] == "c":
            g[y][x] = rng.choice(["X", "X", "V"])
    for _ in range(30):
        x, y = rng.randint(2, W - 3), rng.randint(H - 8, H - 2)
        if g[y][x] == "c":
            g[y][x] = "X"

    # --- resolve reservations ---
    for (ox, oy) in ENTITY_SPOTS:
        rx, ry = ox * 3, oy * 3
        final = "p" if 8 <= rx <= 70 and 104 <= ry <= 128 else "c"
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
                g[y][x] = "V"

    return g


def main():
    pal = json.load(open(PALETTE))["worlds"]["futuristic"]
    ch2rgb = {ch: tuple(v["rgb"]) for sec in ("terrain", "landmarks") for ch, v in pal[sec].items()}
    g = gen()
    used = sorted({c for row in g for c in row})
    unknown = [c for c in used if c not in ch2rgb]
    if unknown:
        sys.exit(f"characters with no futuristic palette entry: {unknown!r}")
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
