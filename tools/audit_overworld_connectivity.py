#!/usr/bin/env python3
"""How fragmented is each world's walkable space, and does anything important sit in a fragment?

W1's shipped map had SIX walkable components and two elemental dragon bosses sealed inside
two of them. Nothing caught it because every existing guard asks a LOCAL question -- is this
spawn cell solid, is this trigger box standable -- and a 100-cell island answers all of them
correctly. Connectivity is a global property and needs a global probe.

Blocking chars are DERIVED per world, never guessed: _char_to_tile_type gives char -> type
and the world's own _get_impassable_types() gives the blocking types.
"""
import re, sys, collections
from collections import deque

WORLDS = [
    ("W2 suburban",   "SuburbanOverworld",   "SuburbanTileGenerator"),
    ("W3 steampunk",  "SteampunkOverworld",  "SteampunkTileGenerator"),
    ("W4 industrial", "IndustrialOverworld", "IndustrialTileGenerator"),
    ("W5 futuristic", "FuturisticOverworld", "FuturisticTileGenerator"),
    ("W6 abstract",   "AbstractOverworld",   "AbstractTileGenerator"),
]


def impassable_types(gen):
    src = open(f"src/exploration/{gen}.gd").read()
    m = re.search(r'func _get_impassable_types\(\) -> Array:\s*\n\s*return \[(.*?)\]', src, re.S)
    if not m:
        return None
    return set(re.findall(r'TileType\.([A-Z_]+)', m.group(1)))


def char_types(scene):
    src = open(f"src/exploration/{scene}.gd").read()
    m = re.search(r'func _char_to_tile_type\(.*?\n(.*?)\n\s*func ', src, re.S)
    if not m:
        return None
    out = {}
    for line in m.group(1).splitlines():
        mm = re.match(r'\s*((?:"[^"]"\s*,?\s*)+):\s*return .*?TileType\.([A-Z_]+)', line)
        if mm:
            for c in re.findall(r'"([^"])"', mm.group(1)):
                out[c] = mm.group(2)
    return out


def map_rows(scene):
    """Read the map's OWN const block. A 'longest run of equal-length lines' heuristic
    silently drops the rest of the map when one row has a typo -- W4 has exactly that
    (row 33 is 59 chars, not 60) and the heuristic returned 33 rows of a 45-row map."""
    src = open(f"src/exploration/{scene}.gd").read()
    m = re.search(r'(?:var|const) map_data: Array\[String\] = \[(.*?)\n\t\]', src, re.S)
    if not m:
        return []
    return re.findall(r'"([^"]*)"', m.group(1))


def components(rows, block):
    H, W = len(rows), len(rows[0])
    seen, comps = set(), []
    for y in range(H):
        for x in range(W):
            if (x, y) in seen or rows[y][x] in block: continue
            c, q = {(x, y)}, deque([(x, y)]); seen.add((x, y))
            while q:
                cx, cy = q.popleft()
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    n = (cx+dx, cy+dy)
                    if 0 <= n[0] < W and 0 <= n[1] < H and n not in seen and rows[n[1]][n[0]] not in block:
                        seen.add(n); c.add(n); q.append(n)
            comps.append(c)
    return sorted(comps, key=len, reverse=True)


if __name__ == '__main__':
    for label, scene, gen in WORLDS:
        imp = impassable_types(gen); ct = char_types(scene); rows = map_rows(scene)
        if imp is None or ct is None or not rows:
            print(f"{label:16s} EXTRACTION FAILED imp={imp is not None} chars={ct is not None} rows={len(rows)}")
            continue
        block = {c for c, t in ct.items() if t in imp}
        declared = dict(re.findall(r'const MAP_(WIDTH|HEIGHT): int = (\d+)', open(f"src/exploration/{scene}.gd").read()))
        dw, dh = int(declared.get('WIDTH', 0)), int(declared.get('HEIGHT', 0))
        ragged = sorted({len(r) for r in rows})
        if len(rows) != dh or ragged != [dw]:
            print(f"{label:16s} ⚠️ AUTHORED SHAPE DISAGREES WITH ITS OWN CONSTS: "
                  f"{len(rows)} rows (MAP_HEIGHT={dh}), row lengths {ragged} (MAP_WIDTH={dw})")
        # the runtime pads short rows/maps with the default char, so measure what SHIPS
        rows = [r.ljust(dw, 'f')[:dw] for r in rows] + ['f' * dw] * max(0, dh - len(rows))
        # a char in the map that _char_to_tile_type never names falls to its default arm
        unknown = {c for r in rows for c in r} - set(ct)
        comps = components(rows, block)
        walk = sum(len(c) for c in comps)
        tot = len(rows) * len(rows[0])
        sizes = [len(c) for c in comps]
        frag = '' if len(comps) <= 1 else f"  ⚠️ {len(comps)-1} island(s): {sizes[1:][:8]}"
        print(f"{label:16s} {len(rows[0])}x{len(rows)}  block={''.join(sorted(block)) or '(none)'}  "
              f"walkable {walk}/{tot} ({walk*100//tot}%)  components={len(comps)}{frag}")
        if unknown:
            print(f"                 unmapped chars fall to the default arm: {sorted(unknown)}")


def authored_sites(scene):
    """Every tile a scene explicitly places something at: Vector2(TX*TILE_SIZE+…, TY*TILE_SIZE+…).
    These are the AUTHORED intents -- where a designer said a portal or entrance goes."""
    src = open(f"src/exploration/{scene}.gd").read()
    out = []
    # tile-space:  x.position = Vector2(TX * TILE_SIZE + .., TY * TILE_SIZE + ..)
    for m in re.finditer(r'(\w+)\.position = Vector2\((\d+) \* TILE_SIZE[^,]*, (\d+) \* TILE_SIZE', src):
        out.append((m.group(1), int(m.group(2)), int(m.group(3))))
    # pixel-space: x.position = spawn_points.get("key", Vector2(PX, PY))
    # W3 uses this form for 3 of its 4 transitions, so a tile-space-only scan under-counts
    # it 2:4 and reports a clean result about half the sites.
    for m in re.finditer(r'(\w+)\.position = spawn_points\.get\([^,]+,\s*Vector2\(([\d.]+),\s*([\d.]+)\)', src):
        out.append((m.group(1), int(float(m.group(2))) // 32, int(float(m.group(3))) // 32))
    return out
