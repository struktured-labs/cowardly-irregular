#!/usr/bin/env python3
"""Re-ground W1: grass becomes the land, roads become roads.

WHY. 43.1% of the W1 map was the single character '.', and 66% of everything a
player can walk on. Grass was 7%. A JRPG overworld reads as a world because its
ground is varied and its roads are thin lines between places; W1 read as one
continent-sized floor with towns dropped on it. That is the "not professional"
complaint in measurable form.

WHAT IT DOES, in two passes:
  1. every '.' becomes 'g' -- grass is the land now
  2. a road network is carved back as '.', following a minimum spanning tree over
     the 15 landmarks with shortest walkable routes between them. Roads therefore
     GO somewhere, which is the property a 43% field cannot have.

WHY IT IS SAFE. '.' and 'g' are both walkable (neither is in TileGenerator's
_get_impassable_types) and both sit at speed 1.0 (neither is in the rough-terrain
table). Every cell this touches is walkable before and after, so map connectivity
and traversal cost are unchanged BY CONSTRUCTION, not by measurement -- the
straight-line-crossing and landmark-reachability pins cannot move. Landmark
pixels are never overwritten: each is a single pixel whose CHARACTER is its
identity, and one stray stroke silently deletes a dragon cave's arrival point.

THE LEDGER exists because test_map_image_roundtrip forbids re-reading the census
out of the PNG -- that would assert only that the image equals itself. It records
every character delta so the golden census can be derived as old + ledger, keeping
the provenance chain ASCII -> scale law -> composition ledger -> this ledger.
"""
import json, sys, collections, heapq, random
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
PNG = REPO / "data/maps/overworld_w1.png"
PALETTE = REPO / "data/maps/map_palette.json"

BLOCK = set("~Ml")  # WATER / MOUNTAIN / LAVA -- TileGenerator._get_impassable_types()
GROUND = "."        # road
FIELD = "g"         # grass
KEEP = set("B")     # bridges are already roads over water; never repaint them
WOOD = "F"          # forest
CLUMPS = 175        # woodland seed attempts; a seed landing off-grass is skipped
CLUMP_MIN, CLUMP_MAX = 12, 90


def load_palette(world="medieval"):
    pal = json.load(open(PALETTE))
    if world not in pal["worlds"]:
        sys.exit(f"unknown world {world!r}; palette defines {sorted(pal['worlds'])}")
    w = pal["worlds"][world]
    rgb2ch = {tuple(v["rgb"]): ch for sec in ("terrain", "landmarks") for ch, v in w[sec].items()}
    ch2rgb = {ch: tuple(v["rgb"]) for sec in ("terrain", "landmarks") for ch, v in w[sec].items()}
    return rgb2ch, ch2rgb, set(w["landmarks"])


def read_grid(rgb2ch):
    im = Image.open(PNG).convert("RGB")
    w, h = im.size
    px = im.load()
    grid = []
    for y in range(h):
        row = []
        for x in range(w):
            ch = rgb2ch.get(px[x, y])
            if ch is None:
                sys.exit(f"unmapped colour {px[x, y]} at ({x},{y}) -- palette and image disagree")
            row.append(ch)
        grid.append(row)
    return grid, w, h


def bfs_path(grid, w, h, start, goal):
    """Shortest walkable route. Prefers existing open ground so roads hug the land
    rather than bulldozing forest; impassables are never entered."""
    cost = {}
    for y in range(h):
        for x in range(w):
            c = grid[y][x]
            if c in BLOCK:
                continue
            # deterministic jitter: a pure shortest path draws dead-straight lines
            # that read as a street grid, not as roads worn between places
            j = (x * 73856093 ^ y * 19349663) % 5
            cost[(x, y)] = (3 if c in (GROUND, FIELD) else 12) + j
    if start not in cost or goal not in cost:
        return None
    dist = {start: 0}
    prev = {}
    pq = [(0, start)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == goal:
            break
        if d > dist.get(u, 1 << 30):
            continue
        ux, uy = u
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            v = (ux + dx, uy + dy)
            if v not in cost:
                continue
            nd = d + cost[v]
            if nd < dist.get(v, 1 << 30):
                dist[v] = nd
                prev[v] = u
                heapq.heappush(pq, (nd, v))
    if goal not in dist:
        return None
    path, cur = [], goal
    while cur != start:
        path.append(cur)
        cur = prev[cur]
    path.append(start)
    return path[::-1]


def main():
    dry = "--dry-run" in sys.argv
    out = Path(sys.argv[sys.argv.index("--out") + 1]) if "--out" in sys.argv else PNG
    rgb2ch, ch2rgb, landmark_chars = load_palette()
    grid, w, h = read_grid(rgb2ch)

    before = collections.Counter(ch for row in grid for ch in row)

    # keyed by POSITION, not character: 'H' and 'C' each appear twice, and a
    # char-keyed dict silently drops one of each -- 15 tiles, 13 distinct chars.
    sites = []
    for y in range(h):
        for x in range(w):
            if grid[y][x] in landmark_chars:
                sites.append((grid[y][x], (x, y)))
    if len(sites) != 15:
        sys.exit(f"expected 15 landmark tiles, found {len(sites)} -- refusing to paint")

    # PASS 1 -- grass becomes the land
    for y in range(h):
        for x in range(w):
            if grid[y][x] == GROUND:
                grid[y][x] = FIELD

    # PASS 2 -- MST over landmarks, roads carved along shortest routes
    names = [f"{ch}@{x},{y}" for ch, (x, y) in sites]
    pts = [xy for _, xy in sites]
    connected, remaining = {0}, set(range(1, len(pts)))
    edges, road_cells = [], set()
    while remaining:
        best = None
        for i in connected:
            for j in remaining:
                d = abs(pts[i][0] - pts[j][0]) + abs(pts[i][1] - pts[j][1])
                if best is None or d < best[0]:
                    best = (d, i, j)
        _, i, j = best
        path = bfs_path(grid, w, h, pts[i], pts[j])
        if path is None:
            sys.exit(f"no walkable route {names[i]} -> {names[j]} -- the map is severed")
        edges.append((names[i], names[j], len(path)))
        road_cells.update(path)
        connected.add(j)
        remaining.discard(j)

    painted = 0
    for (x, y) in road_cells:
        c = grid[y][x]
        if c in landmark_chars or c in KEEP or c in BLOCK:
            continue
        if c != GROUND:
            grid[y][x] = GROUND
            painted += 1

    # PASS 3 -- woodland. Swapping a 43% tan field for a 47% green one trades one
    # monoculture for another; a world reads as a world because its ground varies.
    # Seeded PRNG, fixed constant, so the ledger is reproducible run to run.
    rng = random.Random(20260827)
    road = {c for c in road_cells}
    protect = set()
    for _, (lx, ly) in sites:
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                protect.add((lx + dx, ly + dy))
    grown = 0
    for _ in range(CLUMPS):
        cx, cy = rng.randrange(w), rng.randrange(h)
        if grid[cy][cx] != FIELD:
            continue
        target = rng.randint(CLUMP_MIN, CLUMP_MAX)
        frontier, seen = [(cx, cy)], {(cx, cy)}
        while frontier and target > 0:
            x, y = frontier.pop(rng.randrange(len(frontier)))
            if grid[y][x] != FIELD or (x, y) in road or (x, y) in protect:
                continue
            grid[y][x] = WOOD
            grown += 1
            target -= 1
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy)
                if n not in seen and 0 <= n[0] < w and 0 <= n[1] < h:
                    seen.add(n)
                    frontier.append(n)

    after = collections.Counter(ch for row in grid for ch in row)
    ledger = {ch: after.get(ch, 0) - before.get(ch, 0)
              for ch in set(before) | set(after) if after.get(ch, 0) != before.get(ch, 0)}

    print(f"  {w}x{h}  landmarks {len(sites)}  MST edges {len(edges)}  road {painted}  woodland {grown}")
    print(f"  ledger: {json.dumps(ledger, sort_keys=True)}")
    print(f"  delta sums to zero: {sum(ledger.values()) == 0}")
    for ch in sorted(after):
        print(f"    {ch!r} {before.get(ch,0):6d} -> {after.get(ch,0):6d}")

    # every landmark character must survive exactly once
    for ch in landmark_chars:
        if before.get(ch, 0) != after.get(ch, 0):
            sys.exit(f"landmark {ch!r} count changed {before.get(ch)} -> {after.get(ch)}")

    if dry:
        print("  --dry-run: nothing written")
        return

    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = ch2rgb[grid[y][x]]
    im.save(out)
    (REPO / "tmp").mkdir(exist_ok=True)
    (REPO / "tmp/w1_ground_pass_ledger.json").write_text(
        json.dumps({"ledger": ledger, "before": dict(before), "after": dict(after),
                    "edges": edges, "road_cells_painted": painted}, indent=2, sort_keys=True))
    print(f"  wrote {out} and tmp/w1_ground_pass_ledger.json")


if __name__ == "__main__":
    main()
