#!/usr/bin/env python3
"""Grow a village's buildings by DUPLICATING map columns/rows inside their spans, and move every absolute
coordinate in the village script with the same transform, so nothing placed on the map drifts.

struktured 2026-11-01: "we can redesign the village maps as needed" (houses looked small beside the party).

  tools/stretch_village.py <Village.gd> --cols 6,7,8 --rows 5,10 [--write]
  tools/stretch_village.py --cols ... --rows ... --point 352,384   # map one absolute pixel point (cutscene marks)

A column listed twice is tripled. Cells (Vector2i literals) map to the FIRST copy of their column; continuous
coordinates (N * TILE_SIZE, cell centres, raw pixels) stretch linearly through a duplicated cell, so a thing centred
on a duplicated cell stays centred on the doubled span.
"""
import argparse
import re
import sys

TILE = 32


def index_map(j, dups):
    return j + sum(1 for k in dups if k < j)


def cont(x, dups):
    return x + sum(min(max(x - k, 0.0), 1.0) for k in dups)


def fmt(v):
    v = round(v, 4)
    return str(int(v)) if v == int(v) else ("%g" % v)


NUM = r"-?[0-9]+(?:\.[0-9]+)?"
TERM = rf"(?:({NUM}) \* TILE_SIZE \+ TILE_SIZE / 2|({NUM}) \* TILE_SIZE|({NUM}))"
VEC2 = re.compile(rf"Vector2\(\s*{TERM}\s*,\s*{TERM}\s*\)")
VEC2I = re.compile(rf"Vector2i\(\s*(-?[0-9]+)\s*,\s*(-?[0-9]+)\s*\)")


def map_term(groups, dups):
    centre, tiles, raw = groups
    if centre is not None:
        return "%s * TILE_SIZE + TILE_SIZE / 2" % fmt(cont(float(centre) + 0.5, dups) - 0.5)
    if tiles is not None:
        return "%s * TILE_SIZE" % fmt(cont(float(tiles), dups))
    if float(raw) == 0.0:
        return raw
    return fmt(cont(float(raw) / TILE, dups) * TILE)


def stretch_rows(rows, cols, rws):
    out = []
    for y, row in enumerate(rows):
        wide = "".join(ch * (1 + cols.count(i)) for i, ch in enumerate(row))
        out.extend([wide] * (1 + rws.count(y)))
    return out


def rewrite_array(src, name, cols, rws):
    m = re.search(rf"(var {name}: Array\[String\] = \[\n)(.*?)(\n\t\])", src, re.S)
    if m is None:
        return src, None
    rows = re.findall(r'"([^"]*)"', m.group(2))
    indent = re.match(r"(\s*)", m.group(2)).group(1)
    new = stretch_rows(rows, cols, rws)
    body = "\n".join('%s"%s",' % (indent, r) for r in new)
    return src[: m.start(2)] + body + src[m.end(2):], new


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("script", nargs="?")
    ap.add_argument("--cols", default="")
    ap.add_argument("--rows", default="")
    ap.add_argument("--point")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()
    cols = [int(c) for c in a.cols.split(",") if c != ""]
    rws = [int(r) for r in a.rows.split(",") if r != ""]
    if a.point:
        x, y = (float(v) for v in a.point.split(","))
        print("%s,%s" % (fmt(cont(x / TILE, cols) * TILE), fmt(cont(y / TILE, rws) * TILE)))
        return 0
    src = open(a.script).read()
    src, grid = rewrite_array(src, "map_data", cols, rws)
    src, hgrid = rewrite_array(src, "height_data", cols, rws)
    if grid is None:
        print("no map_data array found", file=sys.stderr)
        return 2
    if hgrid is not None and (len(hgrid) != len(grid) or {len(r) for r in hgrid} != {len(r) for r in grid}):
        print("height_data no longer matches map_data", file=sys.stderr)
        return 2
    counts = {"vec2": 0, "vec2i": 0}

    def sub2(m):
        counts["vec2"] += 1
        return "Vector2(%s, %s)" % (map_term(m.groups()[0:3], cols), map_term(m.groups()[3:6], rws))

    def sub2i(m):
        counts["vec2i"] += 1
        return "Vector2i(%d, %d)" % (index_map(int(m.group(1)), cols), index_map(int(m.group(2)), rws))

    src = VEC2.sub(sub2, src)
    src = VEC2I.sub(sub2i, src)
    src = re.sub(r"const MAP_WIDTH: int = [0-9]+", "const MAP_WIDTH: int = %d" % len(grid[0]), src)
    src = re.sub(r"const MAP_HEIGHT: int = [0-9]+", "const MAP_HEIGHT: int = %d" % len(grid), src)
    print("map %dx%d · %d Vector2 · %d Vector2i moved" % (len(grid[0]), len(grid), counts["vec2"], counts["vec2i"]))
    if a.write:
        open(a.script, "w").write(src)
    else:
        print("\n".join(grid))
    return 0


if __name__ == "__main__":
    sys.exit(main())
