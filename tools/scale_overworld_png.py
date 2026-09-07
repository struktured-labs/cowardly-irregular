#!/usr/bin/env python3
"""Scale an overworld PNG by an integer factor, keeping landmarks single-pixel.

Terrain upscales nearest-neighbour so the composition is preserved exactly.
A landmark pixel would otherwise become factor^2 pixels, so each is replaced by
its dominant neighbouring terrain and re-stamped once at the block's top-left.
"""
import sys, json, collections
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent


def load_palette(world="medieval"):
    """Decode tables for one world. A module-level entry point ON PURPOSE: while this
    lived inside main() the guard that runs every tool could not reach it, and scored
    green against a version of this file that could not read the palette at all."""
    pal = json.load(open(REPO / "data/maps/map_palette.json"))
    # Palette v2: sections live under worlds.<id>. Named, never defaulted silently --
    # decoding a map against the wrong world's table yields a plausible wrong map.
    if world not in pal["worlds"]:
        sys.exit(f"unknown world {world!r}; palette defines {sorted(pal['worlds'])}")
    wpal = pal["worlds"][world]
    rgb2char, char2rgb, landmark = {}, {}, set()
    for sec in ("terrain", "landmarks"):
        for ch, v in wpal[sec].items():
            rgb2char[tuple(v["rgb"])] = ch
            char2rgb[ch] = tuple(v["rgb"])
            if sec == "landmarks":
                landmark.add(ch)
    return rgb2char, char2rgb, landmark


def main():
    if len(sys.argv) < 4:
        sys.exit("usage: scale_overworld_png.py <in.png> <out.png> <factor> [world]")
    src, dst, factor = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3])
    rgb2char, char2rgb, landmark = load_palette(sys.argv[4] if len(sys.argv) > 4 else "medieval")

    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()
    grid = [[rgb2char[px[x, y]] for x in range(w)] for y in range(h)]

    def dominant_terrain(x, y):
        c = collections.Counter()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    ch = grid[ny][nx]
                    if ch not in landmark:
                        c[ch] += 1
        return c.most_common(1)[0][0] if c else "g"

    W, H = w * factor, h * factor
    out = [["g"] * W for _ in range(H)]
    for y in range(h):
        for x in range(w):
            ch = grid[y][x]
            fill = dominant_terrain(x, y) if ch in landmark else ch
            for dy in range(factor):
                for dx in range(factor):
                    out[y * factor + dy][x * factor + dx] = fill
            if ch in landmark:
                out[y * factor][x * factor] = ch

    img = Image.new("RGB", (W, H))
    ip = img.load()
    for y in range(H):
        for x in range(W):
            ip[x, y] = char2rgb[out[y][x]]
    img.save(dst)

    before = collections.Counter(c for row in grid for c in row)
    after = collections.Counter(c for row in out for c in row)
    print(f"{src.name} {w}x{h} -> {dst.name} {W}x{H} (factor {factor})")
    for ch in sorted(landmark):
        if before.get(ch, 0):
            print(f"  landmark {ch!r}: {before[ch]} -> {after.get(ch, 0)}"
                  f"{'  MISMATCH' if before[ch] != after.get(ch, 0) else ''}")


if __name__ == "__main__":
    main()
