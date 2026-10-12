#!/usr/bin/env python3
"""Remove a painted near-white backdrop the white key left behind on a portrait.

The steampunk Tempo masterite's portrait was generated with a fake "transparency checkerboard"
painted behind him: a dither of near-white greys (235-239) and white blobs. The white key only
takes R,G,B >= 240, so it ate the blobs and left the dither, and he speaks from inside a pale
checkered square.

A backdrop pixel is one reachable from the image border through pixels that are already clear or
are pale and neutral (darkest channel >= PALE_MIN, channels within NEUTRAL of each other). The
figure's own dark outline stops the walk, and a cream or coloured highlight is not neutral, so
steam, brass and skin are left alone. Only portraits named in BACKDROPPED are touched.

Usage:
    python3 tools/strip_portrait_backdrop.py --audit
    python3 tools/strip_portrait_backdrop.py --apply
    python3 tools/strip_portrait_backdrop.py --selftest
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PORTRAITS = "assets/sprites/portraits"
ALPHA = 128
PALE_MIN = 215
NEUTRAL = 12
EDGE = 4
# A portrait whose top and upper side edges are at least this pale-and-opaque has a painted backdrop.
BACKDROP_SHARE = 0.02
# Portraits looked at and found to carry a painted backdrop.
BACKDROPPED = ("masterite_tempo_steampunk.png",)


def _pale(rgba: np.ndarray) -> np.ndarray:
    r, g, b = (rgba[..., i].astype(int) for i in range(3))
    lo = np.minimum(np.minimum(r, g), b)
    hi = np.maximum(np.maximum(r, g), b)
    return (rgba[..., 3] >= ALPHA) & (lo >= PALE_MIN) & (hi - lo <= NEUTRAL)


def backdrop_share(rgba: np.ndarray) -> float:
    """Share of the top edge and the upper halves of the side edges (EDGE px deep) that is opaque, pale and neutral."""
    h, w = rgba.shape[:2]
    edge = np.zeros((h, w), dtype=bool)
    edge[:EDGE, :] = True
    edge[:h // 2, :EDGE] = True
    edge[:h // 2, -EDGE:] = True
    return float((_pale(rgba) & edge).sum()) / float(edge.sum())


def strip(img: Image.Image):
    """(new image, pixels cleared): every pale neutral pixel reachable from the border through clear or pale ones."""
    rgba = np.asarray(img.convert("RGBA")).copy()
    h, w = rgba.shape[:2]
    passable = (rgba[..., 3] < ALPHA) | _pale(rgba)
    seen = np.zeros((h, w), dtype=bool)
    stack = [(y, x) for y in range(h) for x in (0, w - 1) if passable[y, x]]
    stack += [(y, x) for x in range(w) for y in (0, h - 1) if passable[y, x]]
    for y, x in stack:
        seen[y, x] = True
    while stack:
        y, x = stack.pop()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                stack.append((ny, nx))
    clear = seen & (rgba[..., 3] >= ALPHA)
    rgba[clear] = (0, 0, 0, 0)
    return Image.fromarray(rgba), int(clear.sum())


def selftest() -> int:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    for y in range(64):
        for x in range(64):
            if (x + y) % 2:
                px[x, y] = (236, 236, 236, 255)          # the dither
    for y in range(16, 64):
        for x in range(16, 48):
            px[x, y] = (20, 16, 10, 255)                 # the figure
    for y in range(30, 36):
        for x in range(24, 30):
            px[x, y] = (238, 238, 238, 255)              # a pale patch INSIDE the figure
    for y in range(8, 14):
        for x in range(4, 10):
            px[x, y] = (232, 222, 190, 255)              # cream steam in the backdrop
    assert backdrop_share(np.asarray(img)) > BACKDROP_SHARE, "a dithered backdrop is seen on the edges"
    out, n = strip(img)
    a = np.asarray(out)
    assert n > 500 and backdrop_share(a) == 0.0, "the backdrop is gone (%d px)" % n
    assert out.getpixel((26, 32)) == (238, 238, 238, 255), "a pale patch the figure encloses is kept"
    assert out.getpixel((6, 10)) == (232, 222, 190, 255), "cream steam is not neutral and is kept"
    assert out.getpixel((30, 50)) == (20, 16, 10, 255), "the figure is untouched"
    assert strip(out)[1] == 0, "a second pass clears nothing"
    print("selftest ok")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    for path in sorted((ROOT / PORTRAITS).rglob("*.png")):
        rel = path.relative_to(ROOT / PORTRAITS).as_posix()
        img = Image.open(path)
        share = backdrop_share(np.asarray(img.convert("RGBA")))
        if share < BACKDROP_SHARE:
            continue
        if rel not in BACKDROPPED:
            print("UNREVIEWED %s: %.0f%% of its edges are a pale backdrop; look at it, then add it to BACKDROPPED" % (rel, share * 100))
            continue
        out, n = strip(img)
        print("%s %s: %d px of backdrop (%.0f%% of its edges)" % ("STRIPPED" if args.apply else "CAN STRIP", rel, n, share * 100))
        if args.apply:
            out.save(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
