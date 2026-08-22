#!/usr/bin/env python3
"""Compose W1: heal the sealed enclaves, then interrupt the west-east straight line.

Two jobs, deliberately in one tool because they pull against each other -- every
wall added to force routing is a chance to strand something, and the only honest
way to add walls is to re-measure connectivity in the same breath.
"""
import json, sys, collections
from collections import deque
from PIL import Image

PAL = json.load(open('data/maps/map_palette.json'))
CH2RGB = {k: tuple(v['rgb']) for k, v in {**PAL['terrain'], **PAL['landmarks']}.items()}
RGB2CH = {v: k for k, v in CH2RGB.items()}
LANDMARK = set(PAL['landmarks'])
BLOCK = set('~Ml')          # WATER / MOUNTAIN / LAVA -- TileGenerator._get_impassable_types()


def load(path):
    im = Image.open(path).convert('RGB')
    W, H = im.size
    px = im.load()
    return [[RGB2CH[px[x, y]] for x in range(W)] for y in range(H)], W, H


def save(g, path):
    H, W = len(g), len(g[0])
    im = Image.new('RGB', (W, H))
    im.putdata([CH2RGB[g[y][x]] for y in range(H) for x in range(W)])
    im.save(path)


def components(g, W, H):
    seen, comps = set(), []
    for y in range(H):
        for x in range(W):
            if (x, y) in seen or g[y][x] in BLOCK:
                continue
            c, q = {(x, y)}, deque([(x, y)])
            seen.add((x, y))
            while q:
                cx, cy = q.popleft()
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    n = (cx + dx, cy + dy)
                    if 0 <= n[0] < W and 0 <= n[1] < H and n not in seen and g[n[1]][n[0]] not in BLOCK:
                        seen.add(n); c.add(n); q.append(n)
            comps.append(c)
    return sorted(comps, key=len, reverse=True)


def flood(g, W, H, starts):
    dist = {s: 0 for s in starts}
    q = deque(starts)
    while q:
        cur = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (cur[0] + dx, cur[1] + dy)
            if 0 <= n[0] < W and 0 <= n[1] < H and n not in dist and g[n[1]][n[0]] not in BLOCK:
                dist[n] = dist[cur] + 1; q.append(n)
    return dist


def measure(g, W, H, label):
    comps = components(g, W, H)
    dist = flood(g, W, H, [(0, y) for y in range(H) if g[y][0] not in BLOCK])
    east = [dist[(W - 1, y)] for y in range(H) if (W - 1, y) in dist]
    best = min(east) if east else None
    ratio = best / (W - 1) if best else None
    main = comps[0]
    stranded = [f"{g[y][x]}@{x},{y}" for y in range(H) for x in range(W)
                if g[y][x] in LANDMARK and (x, y) not in main]
    print(f"  [{label}] ratio={ratio if ratio is None else round(ratio,3)} "
          f"crossing={best} components={len(comps)} stranded={len(stranded)} {stranded}")
    return ratio, stranded


def carve(g, cells, ch):
    """Paint ch, never over a landmark pixel -- landmarks are single-pixel and irreplaceable."""
    n = 0
    for x, y in cells:
        if 0 <= y < len(g) and 0 <= x < len(g[0]) and g[y][x] not in LANDMARK:
            g[y][x] = ch; n += 1
    return n


def rect(x0, y0, x1, y1):
    return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]


if __name__ == '__main__':
    g, W, H = load('data/maps/overworld_w1.png')
    print(f"map {W}x{H}")
    measure(g, W, H, 'before')


def heal(g):
    """Open the three sealed enclaves along their own cheapest wall, 3 tiles wide.
    Width is not cosmetic: struktured widened W1's corridors in April 2026 precisely
    because 1-tile gaps fight Mode 7's visual-vs-physics mismatch."""
    n = 0
    n += carve(g, rect(13, 27, 15, 29), 'B')       # causeway to the frozen north (2-cell water wall)
    n += carve(g, rect(10, 5, 12, 7), '.')         # pass to the hidden passage (1-cell mountain wall)
    n += carve(g, rect(162, 104, 164, 107), '.')   # pass down through the ridge above the caldera
    n += carve(g, rect(162, 108, 164, 111), 'B')   # causeway over the lava to Pyrroth and Ironhaven
    return n


def barrier(g, x0, x1, ch, gap_y0, gap_y1, amp=0, period=41.0):
    """Paint a continental barrier down the whole column, leaving one gap.

    The centre MEANDERS -- a range drawn at a constant x reads as a machine
    artifact the moment you look at the map. The offset is a sine of the row, so
    it is deterministic and reproducible; no RNG is involved, because the map has
    to regenerate identically or the golden census is meaningless.

    Cells that already block are left alone, so an existing sea stays a sea
    rather than growing a mountain range through it."""
    import math
    H = len(g)
    W = len(g[0])
    n = 0
    for y in range(2, H):
        if gap_y0 <= y <= gap_y1:
            continue
        off = int(round(amp * math.sin(y / period)))
        for x in range(x0 + off, x1 + off + 1):
            if 0 <= x < W and g[y][x] not in BLOCK and g[y][x] not in LANDMARK:
                g[y][x] = ch; n += 1
    return n


def _old_barrier(g, x0, x1, ch, gap_y0, gap_y1):
    """Paint a continental barrier down the whole column, leaving one gap.
    Cells that already block are left alone, so an existing sea stays a sea
    rather than growing a mountain range through it."""
    H = len(g)
    n = 0
    for y in range(2, H):
        if gap_y0 <= y <= gap_y1:
            continue
        for x in range(x0, x1 + 1):
            if g[y][x] not in BLOCK and g[y][x] not in LANDMARK:
                g[y][x] = ch; n += 1
    return n


def compose(g):
    """The authored composition. Kept in one function so the map regenerates identically.

    Rivers run UNBROKEN and are crossed by a bridge; a river that simply stops for five
    rows reads as a drawing mistake rather than a ford. The mountain range keeps a plain
    gap, because a gap in a range is a pass and that is exactly what it looks like.
    The three gaps sit at OFFSET latitudes on purpose -- with one barrier the crossing
    just starts on the gap's row and the detour is zero; the zigzag is what costs steps.
    """
    n = heal(g)
    n += barrier(g, 50, 54, '~', -1, -1, 6, 37.0)
    n += carve(g, rect(44, 68, 62, 72), 'B')       # the west ford
    n += barrier(g, 100, 104, 'M', 38, 42, 6, 43.0)
    n += barrier(g, 126, 130, '~', -1, -1, 6, 31.0)
    n += carve(g, rect(120, 68, 138, 72), 'B')     # the east ford
    return n
