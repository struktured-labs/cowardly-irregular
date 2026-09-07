#!/usr/bin/env python3
"""Generate W6's void at 80x70 (the 40x35 original at 2x -- NOT 3x, deliberately).

W6 is the minimalist-existential endgame; scaling it like a city would dilute the
one thing it is about. 2x gives it presence without filling it: the composition is
ISLANDS IN VOID -- the Catalog, the Remnant, the Echo Chamber and the Origin Point
survive as floating plates of gray connected by exposed grid-line skeleton over
impassable black, geometry dissolving north through the Threshold, the Question
still burning at the centre. Crossing W6 means walking the grid lines and feeling
how little floor is left.

Walkable: w g L G K C T O X H Q F. Blocked: B S E D.
ENTITY_SPOTS: every coordinate in AbstractOverworld.gd (old 40x35 tiles, x2 here).
"""
import json, random, sys
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
PALETTE = REPO / "data/maps/map_palette.json"
OUT = REPO / "data/maps/overworld_w6.png"
W, H = 80, 70
SCALE = 2
BLOCKED = set("BSED")

ENTITY_SPOTS = [
    (3, 8), (3, 12), (3, 16), (5, 16), (5, 18), (5, 20), (7, 16), (15, 13),
    (15, 15), (15, 20), (15, 25), (16, 4), (16, 19), (18, 28), (19, 4), (19, 6),
    (19, 14), (19, 16), (19, 18), (19, 19), (19, 28), (19, 30), (19, 31), (19, 32),
    (19, 33), (20, 7), (20, 10), (20, 15), (20, 20), (22, 18), (22, 28), (25, 18),
    (31, 16), (34, 14), (34, 16), (35, 12), (35, 20),
]


def gen(seed=20260829):
    rng = random.Random(seed)
    g = [["B"] * W for _ in range(H)]

    def rect(x0, y0, x1, y1, ch):
        for y in range(max(0, y0), min(H, y1 + 1)):
            for x in range(max(0, x0), min(W, x1 + 1)):
                g[y][x] = ch

    def plate(x0, y0, x1, y1, ch="g"):
        rect(x0, y0, x1, y1, ch)
        # ragged edges: the void eats corners
        for _ in range((x1 - x0 + y1 - y0)):
            ex = rng.choice([x0, x1]); ey = rng.randint(y0, y1)
            if rng.random() < 0.5:
                ex = rng.randint(x0, x1); ey = rng.choice([y0, y1])
            g[ey][ex] = "B"

    for (ox, oy) in ENTITY_SPOTS:
        rect(ox * 2 - 1, oy * 2 - 1, ox * 2 + 1, oy * 2 + 1, "_")

    # --- the floating plates ---
    plate(6, 20, 22, 50, "g")            # the Catalog (west)
    plate(30, 24, 52, 44, "w")           # the Remnant (center, white)
    plate(58, 18, 75, 48, "g")           # the Echo Chamber (east)
    plate(30, 56, 52, 66, "g")           # the Origin Point (south)
    plate(34, 6, 48, 14, "w")            # the Threshold shard (north)

    # --- grid-line skeleton: thin bridges over the black ---
    def gridline_h(y, x0, x1):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            if g[y][x] == "B":
                g[y][x] = "L"

    def gridline_v(x, y0, y1):
        for y in range(min(y0, y1), max(y0, y1) + 1):
            if g[y][x] == "B":
                g[y][x] = "L"

    gridline_h(32, 22, 30)               # Catalog -> Remnant
    gridline_h(34, 52, 58)               # Remnant -> Echo Chamber
    gridline_v(41, 44, 56)               # Remnant -> Origin
    gridline_v(41, 14, 24)               # Threshold -> Remnant
    gridline_h(60, 14, 30)               # Catalog south spur -> Origin
    gridline_v(14, 50, 60)
    gridline_h(24, 66, 75)               # Echo Chamber loose end, going nowhere
    gridline_v(66, 48, 62)               # Echo -> void, stops short: a broken line

    # --- the Threshold: dissolving north ---
    for y in range(2, 16):
        for x in range(2, W - 2):
            if g[y][x] == "B" and rng.random() < (16 - y) / 40.0:
                g[y][x] = rng.choice(["T", "T", "H"])

    # --- Catalog furniture: shelf rows with aisles, remnant doors ---
    for sy in range(24, 47, 5):
        for x in range(8, 20):
            if g[sy][x] == "g" and x % 5 != 0:
                g[sy][x] = "S"
    for (dx, dy) in ((10, 21), (16, 49)):
        if g[dy][dx] != "_":
            g[dy][dx] = "D"

    # --- Remnant: memory fragments floating in white ---
    for _ in range(26):
        x, y = rng.randint(31, 51), rng.randint(25, 43)
        if g[y][x] == "w":
            g[y][x] = rng.choice(["G", "K", "C", "F", "X"])

    # --- Echo Chamber: repeating wall pattern with one break per row ---
    for ey in range(22, 45, 4):
        gap = rng.randint(60, 73)
        for x in range(60, 74):
            if g[ey][x] == "g" and abs(x - gap) > 1:
                g[ey][x] = "E"

    # --- the Question, at the centre of the Remnant ---
    rect(40, 32, 41, 33, "O")
    g[33][41] = "Q"

    # --- Origin Point: structured, the way back ---
    for x in range(32, 51, 2):
        if g[58][x] == "g":
            g[58][x] = "L"
    for _ in range(8):
        x, y = rng.randint(31, 51), rng.randint(57, 65)
        if g[y][x] == "g":
            g[y][x] = "F"

    # --- static and shadow: scattered decay everywhere the floor survives ---
    for _ in range(30):
        x, y = rng.randrange(W), rng.randrange(H)
        if g[y][x] in ("g", "w") and rng.random() < 0.5:
            g[y][x] = rng.choice(["X", "H"])

    # --- resolve reservations ---
    for (ox, oy) in ENTITY_SPOTS:
        rx, ry = ox * 2, oy * 2
        final = "w" if 30 <= rx <= 52 and 24 <= ry <= 44 else "g"
        for y in range(ry - 1, ry + 2):
            for x in range(rx - 1, rx + 2):
                if 0 <= x < W and 0 <= y < H and (g[y][x] == "_" or g[y][x] in BLOCKED):
                    g[y][x] = final

    # --- connectivity repair: every plate must reach the Origin. The void plates
    # are ragged by RNG, so bridge any stranded region to the main component with
    # a grid line -- the repair itself reads as authored skeleton.
    def components():
        seen, comps = set(), []
        for sy in range(H):
            for sx in range(W):
                if g[sy][sx] in BLOCKED or (sx, sy) in seen:
                    continue
                stack = [(sx, sy)]; seen.add((sx, sy)); cells = [(sx, sy)]
                while stack:
                    x, y = stack.pop()
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        n = (x + dx, y + dy)
                        if 0 <= n[0] < W and 0 <= n[1] < H and n not in seen and g[n[1]][n[0]] not in BLOCKED:
                            seen.add(n); stack.append(n); cells.append(n)
                comps.append(cells)
        return sorted(comps, key=len, reverse=True)

    comps = components()
    while len(comps) > 1:
        main_set = set(comps[0])
        cells = comps[1]
        best = None
        for (x, y) in cells:
            for (mx, my) in list(main_set)[:4000]:
                d = abs(x - mx) + abs(y - my)
                if best is None or d < best[0]:
                    best = (d, (x, y), (mx, my))
        _, (x1, y1), (x2, y2) = best
        gridline_h(y1, x1, x2)
        gridline_v(x2, y1, y2)
        comps = components()

    return g


def main():
    pal = json.load(open(PALETTE))["worlds"]["abstract"]
    ch2rgb = {ch: tuple(v["rgb"]) for sec in ("terrain", "landmarks") for ch, v in pal[sec].items()}
    g = gen()
    used = sorted({c for row in g for c in row})
    unknown = [c for c in used if c not in ch2rgb]
    if unknown:
        sys.exit(f"characters with no abstract palette entry: {unknown!r}")
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
