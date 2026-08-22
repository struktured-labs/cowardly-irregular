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
    # comment lines sit between the signature and the return in TileGenerator; a
    # \s*\n\s* bridge does not cross them and silently returned None for W1.
    m = re.search(r'func _get_impassable_types\(\) -> Array:(?:\s*(?:#[^\n]*)?\n)*?\s*return \[(.*?)\]', src, re.S)
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


def authored_sites(scene):
    """Sites this scan may legitimately classify: LANDMARK-bearing cells only.

    NOT spawn points and NOT transitions. Both were tried on 2026-08-22 and both produced
    false positives, because MODE7_GROUND_DISPLACEMENT_PX is 140.6 = 4x32 + 12.6 -- not a
    whole number of tiles. test_overworld_spawn_overlap_regression already records that
    "four grid models were tried against this question over one evening and all four were
    wrong"; a fifth is not better. Those questions belong to the body-probe tests
    (test_overworld_spawn_overlap_regression, test_transition_reachability_regression),
    which answer them with a physics query that has no grid parameter to get wrong.

    What a body probe CANNOT answer is global: a spawn can be perfectly clear and still sit
    on a 26-tile island. That is this tool's only job.
    """
    return []


def png_rows(path, world):
    """W1 ships as a PNG (1px/tile); read it the way the game does -- raw bytes, no importer."""
    import json, zlib, struct
    d = open(path, 'rb').read(); pos = 8; idat = b''
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]; typ = d[pos+4:pos+8]
        if typ == b'IHDR': w, h, _bd, ct = struct.unpack('>IIBB', d[pos+8:pos+18])
        elif typ == b'IDAT': idat += d[pos+8:pos+8+ln]
        pos += 12 + ln
    raw = zlib.decompress(idat); bpp = 4 if ct == 6 else 3; stride = w * bpp
    rows = []; prev = bytearray(stride); i = 0
    for y in range(h):
        f = raw[i]; i += 1; line = bytearray(raw[i:i+stride]); i += stride
        for x in range(stride):
            a = line[x-bpp] if x >= bpp else 0; b = prev[x]; c = prev[x-bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                pp = a + b - c; pa, pb, pc = abs(pp-a), abs(pp-b), abs(pp-c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line)); prev = line
    W = json.load(open('data/maps/map_palette.json'))['worlds'][world]
    rgb2ch = {}; lm = set()
    for sect in ('terrain', 'landmarks'):
        for ch, v in W[sect].items():
            rgb2ch[tuple(v['rgb'])] = ch
            if sect == 'landmarks': lm.add(ch)
    grid = [''.join(rgb2ch.get(tuple(rows[y][x*bpp:x*bpp+3]), '?') for x in range(w)) for y in range(h)]
    return grid, lm


def classify(comps, sites):
    """Which component holds each authored site? An island of scenery is cosmetic;
    an island holding a portal or entrance is the W1 dragon-cave bug again."""
    where = {}
    for name, tx, ty in sites:
        hit = next((n for n, c in enumerate(comps) if (tx, ty) in c), None)
        where.setdefault(hit, []).append(name)
    return where


def report(label, rows, block, comps, sites, extra=""):
    walk = sum(len(c) for c in comps)
    tot = len(rows) * len(rows[0])
    where = classify(comps, sites)
    stranded = {k: v for k, v in where.items() if k not in (0, None)}
    unplaced = where.get(None, [])
    sizes = [len(c) for c in comps]
    frag = "" if len(comps) <= 1 else "  %d island(s): %s" % (len(comps) - 1, sizes[1:][:8])
    print("%-16s %dx%d  block=%-11s walkable %d/%d (%d%%)  components=%d%s%s"
          % (label, len(rows[0]), len(rows), "".join(sorted(block)) or "(none)",
             walk, tot, walk * 100 // tot, len(comps), frag, extra))
    if not sites:
        # 0 sites classified is NOT a pass. W2-W6 carry no landmark glyphs, so this scan
        # has nothing to place and must say so rather than print a clean-looking OK.
        print("                 sites 0: NOT MEASURED -- this world has no landmark glyphs; "
              "island contents unclassified")
    else:
        print("                 sites %d: mainland %d · STRANDED %d · off-map/blocked %d  %s"
              % (len(sites), len(where.get(0, [])), sum(len(v) for v in stranded.values()), len(unplaced),
                 "OK" if not stranded else "<-- STRANDED: " + str(stranded)))
    if unplaced:
        print("                 not on any walkable cell: %s" % unplaced)


if __name__ == '__main__':
    # W1 ships as a PNG now; its landmark glyphs ARE its authored sites.
    g1, lm1 = png_rows("data/maps/overworld_w1.png", "medieval")
    imp1 = impassable_types("TileGenerator")
    if imp1 is None:
        raise SystemExit("W1 EXTRACTION FAILED: _get_impassable_types unreadable -- "
                         "refusing to report connectivity against an empty block set")
    ct1 = {}
    import json as _j
    _W = _j.load(open("data/maps/map_palette.json"))["worlds"]["medieval"]
    # derive W1 blocking from the same source the runtime uses
    _NAME2TYPE = {"water": "WATER", "mountain": "MOUNTAIN", "lava": "LAVA"}
    block1 = {ch for ch, v in _W["terrain"].items() if _NAME2TYPE.get(v["name"]) in imp1}
    sites1 = [(_W["landmarks"][ch]["name"], x, y)
              for y, r in enumerate(g1) for x, ch in enumerate(r) if ch in lm1]
    report("W1 medieval", g1, block1, components(g1, block1), sites1)

    for label, scene, gen in WORLDS:
        imp = impassable_types(gen); ct = char_types(scene); rows = map_rows(scene)
        if imp is None or ct is None or not rows:
            print("%-16s EXTRACTION FAILED imp=%s chars=%s rows=%d"
                  % (label, imp is not None, ct is not None, len(rows)))
            continue
        block = {c for c, t in ct.items() if t in imp}
        src = open("src/exploration/%s.gd" % scene).read()
        declared = dict(re.findall(r'const MAP_(WIDTH|HEIGHT): int = (\d+)', src))
        dw, dh = int(declared.get("WIDTH", 0)), int(declared.get("HEIGHT", 0))
        ragged = sorted({len(r) for r in rows})
        extra = ""
        if len(rows) != dh or ragged != [dw]:
            extra = "  SHAPE DISAGREES WITH ITS CONSTS (%d rows vs %d, widths %s vs %d)" % (
                len(rows), dh, ragged, dw)
        rows = [r.ljust(dw, "f")[:dw] for r in rows] + ["f" * dw] * max(0, dh - len(rows))
        unknown = {c for r in rows for c in r} - set(ct)
        report(label, rows, block, components(rows, block), authored_sites(scene), extra)
        if unknown:
            print("                 unmapped chars fall to the default arm: %s" % sorted(unknown))
