"""Clear the generated image's light floor left INSIDE a monster sheet's silhouette (cowir-main 23431, the giant spider).

A gpt-image regen paints its subject on a light ground. Background removal flood-fills from the frame edge, so a
patch of that ground fenced in by legs survives as an opaque cream blob under the body, plus a light halo on the
silhouette's edge. This clears every connected LIGHT, near-colourless region of at least MIN_REGION pixels (so a
one-pixel eye glint survives), then erodes the light fringe beside what it cleared. Alpha only: no
colour is added or changed, so the palette is untouched. Usage: uv run python tools/clear_enclosed_floor.py <sheet>
"""
import sys
from collections import deque
from PIL import Image

LIGHT_MIN = 200
LIGHT_SAT = 30
FRINGE_MIN = 140
FRINGE_SAT = 35
MIN_REGION = 20
FRINGE_PASSES = 2
RIM_MIN = 120
SHADOW_MAX = 45


def _is(p, lo, sat):
    return p[3] > 0 and min(p[:3]) >= lo and (max(p[:3]) - min(p[:3])) < sat


def clear(im):
    w, h = im.size
    px = im.load()
    seen = set()
    cleared = 0
    gone = set()
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or not _is(px[x, y], LIGHT_MIN, LIGHT_SAT):
                continue
            region, q = [], deque([(x, y)])
            seen.add((x, y))
            while q:
                cx, cy = q.popleft()
                region.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and _is(px[nx, ny], LIGHT_MIN, LIGHT_SAT):
                        seen.add((nx, ny))
                        q.append((nx, ny))
            if len(region) >= MIN_REGION:
                for rx, ry in region:
                    px[rx, ry] = (0, 0, 0, 0)
                    gone.add((rx, ry))
                cleared += len(region)
    fringe = 0
    for _ in range(FRINGE_PASSES):
        ## Only beside what THIS tool cleared: a hole the art already had (an eye's own dark pupil) keeps its glint.
        kill = [(x, y) for y in range(h) for x in range(w) if _is(px[x, y], FRINGE_MIN, FRINGE_SAT) and any(
            (x + dx, y + dy) in gone for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        for x, y in kill:
            px[x, y] = (0, 0, 0, 0)
            gone.add((x, y))
        fringe += len(kill)
    ## The ground's anti-aliased rim on the drop SHADOW: a light pixel between the frame's transparency and the near-black
    ## shadow. A leg highlight sits on grey leg and an eye glint on red, so neither has a near-black neighbour AND a clear one.
    rim = [(x, y) for y in range(h) for x in range(w) if _is(px[x, y], RIM_MIN, FRINGE_SAT) and _touches(px, x, y, w, h, lambda q: q[3] == 0)
           and _touches(px, x, y, w, h, lambda q: q[3] > 0 and max(q[:3]) < SHADOW_MAX)]
    for x, y in rim:
        px[x, y] = (0, 0, 0, 0)
    return cleared, fringe + len(rim)


def _touches(px, x, y, w, h, pred):
    return any(0 <= x + dx < w and 0 <= y + dy < h and pred(px[x + dx, y + dy]) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))


if __name__ == "__main__":
    path = sys.argv[1]
    im = Image.open(path).convert("RGBA")
    c, f = clear(im)
    im.save(path)
    print(f"{path}: cleared {c} floor px, {f} fringe px")
