"""Clear an unkeyed backdrop from ONE frame of a monster sheet (cowir-sprites audit 23682, S1).

A legacy sheet can carry a frame whose generated background was never removed, so the monster flashes a square.
This flood-fills from a BAND-pixel border (a backdrop can stop a pixel short of the cell edge) over pixels within TOL of
that border's own median colour and clears them, alpha
only: no colour is added or changed. Usage: uv run python tools/key_frame_backdrop.py <sheet.png> <frame> [frame_w]
"""
import sys
from collections import deque
from PIL import Image

TOL = 28
BAND = 6


def key(im, frame, fw):
    px = im.load()
    x0, h = frame * fw, im.height
    band = range(BAND)
    edge = [(x, y) for x in range(x0, x0 + fw) for d in band for y in (d, h - 1 - d)]
    edge += [(x, y) for y in range(h) for d in band for x in (x0 + d, x0 + fw - 1 - d)]
    opaque = [px[p] for p in edge if px[p][3] > 0]
    if len(opaque) < len(edge) // 2:
        return 0
    ref = tuple(sorted(c[i] for c in opaque)[len(opaque) // 2] for i in range(3))
    near = lambda c: c[3] > 0 and max(abs(c[i] - ref[i]) for i in range(3)) <= TOL
    seen, todo, n = set(), deque(p for p in edge if near(px[p])), 0
    while todo:
        x, y = todo.popleft()
        if (x, y) in seen or not (x0 <= x < x0 + fw and 0 <= y < h) or not near(px[x, y]):
            continue
        seen.add((x, y))
        r, g, b, _ = px[x, y]
        px[x, y] = (r, g, b, 0)
        n += 1
        todo.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return n


if __name__ == "__main__":
    path, frame = sys.argv[1], int(sys.argv[2])
    fw = int(sys.argv[3]) if len(sys.argv) > 3 else 256
    im = Image.open(path).convert("RGBA")
    print(f"{path} frame {frame}: cleared {key(im, frame, fw)} px")
    im.save(path)
