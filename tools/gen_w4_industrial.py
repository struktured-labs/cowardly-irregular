#!/usr/bin/env python3
"""Generate W4's factory district at 180x135 (the 60x45 original at 3x, re-authored).

Same programme as gen_w2_suburb.py / gen_w3_steampunk.py. The industrial idiom is the
Mother 3 factory chapter: oppressive, mechanical, repetitive ON PURPOSE but at a scale
where the repetition has rhythm -- rail yard with container rows the player weaves
through, a factory heart of conveyor lines and smokestack clusters, cramped identical
worker terraces east, the chemical west bank behind warning signs, the guarded gate
south. The hidden break room survives, still tucked inside the factory.

Walkable: f g c r v R. Blocked: b s C h G d B p w k.
ENTITY_SPOTS: every coordinate in IndustrialOverworld.gd (old 60x45 tiles, x3 here),
complete list so reservations never reshuffle the seeded RNG (the W3 lesson).
"""
import json, random, sys
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
PALETTE = REPO / "data/maps/map_palette.json"
OUT = REPO / "data/maps/overworld_w4.png"
W, H = 180, 135
BLOCKED = set("bsChGdBpwk")

ENTITY_SPOTS = [
    (4, 14), (5, 20), (6, 20), (7, 12), (7, 13), (7, 23), (8, 11), (8, 23),
    (10, 25), (10, 35), (12, 17), (13, 13), (13, 23), (14, 25), (19, 7), (20, 10),
    (20, 15), (20, 20), (20, 22), (22, 16), (25, 15), (25, 17), (25, 20), (26, 5),
    (26, 17), (28, 20), (29, 38), (29, 41), (30, 1), (30, 3), (30, 6), (30, 20),
    (30, 34), (30, 35), (30, 36), (30, 38), (31, 27), (35, 4), (35, 25), (35, 30),
    (36, 19), (36, 20), (36, 22), (40, 25), (40, 30), (42, 22), (45, 30), (48, 17),
    (50, 18), (50, 20), (51, 17), (52, 16), (54, 28),
]


def gen(seed=20260829):
    rng = random.Random(seed)
    g = [["f"] * W for _ in range(H)]

    def rect(x0, y0, x1, y1, ch):
        for y in range(max(0, y0), min(H, y1 + 1)):
            for x in range(max(0, x0), min(W, x1 + 1)):
                g[y][x] = ch

    for (ox, oy) in ENTITY_SPOTS:
        rect(ox * 3 - 1, oy * 3 - 1, ox * 3 + 1, oy * 3 + 1, "_")

    # --- perimeter wall ---
    rect(0, 0, W - 1, 1, "b")
    rect(0, H - 2, W - 1, H - 1, "b")
    rect(0, 0, 1, H - 1, "b")
    rect(W - 2, 0, W - 1, H - 1, "b")

    # --- north rail yard: parallel tracks, container rows with gaps ---
    for ty in (6, 12, 18, 24):
        rect(3, ty, W - 4, ty, "r")
    for cy in (8, 14, 20):
        x = rng.randint(4, 10)
        while x < W - 14:
            ln = rng.randint(4, 9)
            rect(x, cy, x + ln, cy + 1, "C")
            x += ln + rng.randint(4, 9)

    # --- central factory: grating floor, conveyor lines, smokestack clusters ---
    rect(4, 32, W - 5, 72, "g")
    for vy in (38, 50, 62):
        y = vy + rng.choice([-1, 0, 1])
        seg_x = 8
        while seg_x < W - 12:
            seg = rng.randint(10, 22)
            rect(seg_x, y, min(seg_x + seg, W - 12), y, "c")
            seg_x += seg + rng.randint(4, 8)
    for _ in range(14):
        sx, sy = rng.randint(8, W - 16), rng.randint(34, 66)
        if all(g[y][x] == "g" for y in range(sy, sy + 3) for x in range(sx, sx + 3)):
            rect(sx, sy, sx + 2, sy + 2, "s")
            for dx, dy in ((-1, 1), (3, 1)):
                if g[sy + dy][sx + dx] == "g" and rng.random() < 0.6:
                    g[sy + dy][sx + dx] = "v"

    # --- hidden break room, x3 of the original rows 18-20 cols 35-38 ---
    rect(104, 53, 117, 62, "b")
    rect(106, 55, 115, 60, "R")
    rect(110, 61, 110, 62, "R")   # the doorway column -- one tile left y=61 brick and sealed the room

    # --- east worker terraces: cramped, identical, rhythmically so ---
    for hy in range(36, 100, 8):
        x = 126
        while x < W - 8:
            rect(x, hy, x + 5, hy + 4, "h")
            g[hy + 4][x + 2] = "f"      # each terrace keeps a doorway gap
            x += 8
    for ky in range(41, 100, 8):
        for x in range(124, W - 4):
            if g[ky][x] == "f" and rng.random() < 0.25:
                g[ky][x] = "k"

    # --- west chemical bank: drainage canal, barrels, warning signs ---
    rect(6, 34, 10, 100, "d")
    rect(14, 36, 40, 98, "f")
    for _ in range(40):
        x, y = rng.randint(14, 40), rng.randint(36, 98)
        if g[y][x] == "f":
            g[y][x] = rng.choice(["B", "B", "w"])
    for y in range(34, 101, 6):
        if g[y][12] == "f":
            g[y][12] = "w"

    # --- south gate: checkpoint lane between guard posts ---
    rect(4, 105, W - 5, 106, "k")
    rect(84, 103, 96, 110, "f")
    rect(80, 104, 82, 108, "G")
    rect(98, 104, 100, 108, "G")
    for x in range(4, W - 4, 12):
        if g[112][x] == "f":
            g[112][x] = "G" if rng.random() < 0.3 else g[112][x]

    # --- mid-south: a spur line to the gate, storage aprons, vent stacks ---
    for x in range(30, 150):
        g[86 + (x // 30) % 2][x] = "r"
    for cy in (80, 92, 98):
        x = rng.randint(20, 30)
        while x < 160:
            ln = rng.randint(3, 7)
            if all(g[cy][xx] == "f" for xx in range(x, min(x + ln + 1, W))):
                rect(x, cy, x + ln, cy, "C")
            x += ln + rng.randint(8, 16)
    for _ in range(30):
        x, y = rng.randint(44, 124), rng.randint(74, 102)
        if g[y][x] == "f":
            g[y][x] = rng.choice(["v", "g", "g"])

    # --- resolve reservations; deterministic zone-appropriate finals ---
    for (ox, oy) in ENTITY_SPOTS:
        rx, ry = ox * 3, oy * 3
        final = "g" if 32 <= ry <= 72 else "f"
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
    pal = json.load(open(PALETTE))["worlds"]["industrial"]
    ch2rgb = {ch: tuple(v["rgb"]) for sec in ("terrain", "landmarks") for ch, v in pal[sec].items()}
    g = gen()
    used = sorted({c for row in g for c in row})
    unknown = [c for c in used if c not in ch2rgb]
    if unknown:
        sys.exit(f"characters with no industrial palette entry: {unknown!r}")
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
