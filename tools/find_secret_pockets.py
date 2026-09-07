#!/usr/bin/env python3
"""Find places on a world map where a HIDDEN PASSAGE would be a real secret.

WHY THIS IS NOT EYEBALLING. HiddenPassage's contract is subtle: the tile under the disguise
is ALREADY WALKABLE -- the sprite is pure visual deception, discovery is touch-triggered. So
dropping one on a random wall-adjacent tile produces a "secret" that leads nowhere, and
dropping one in the open produces a wall standing in a field. What makes a secret a secret
is that something is reachable ONLY through it.

That is an articulation point in the walkability graph: a walkable cell whose removal
disconnects a small pocket from the mainland. This finds them, ranks them, and reports the
disguise that matches the terrain actually surrounding each one -- so the wall you paint
looks like the wall it is pretending to be.

WHAT IT REFUSES TO CALL A CANDIDATE:
  - pockets bigger than MAX_POCKET (that is a region, not a secret)
  - pockets smaller than MIN_POCKET (nothing fits inside; the reward has nowhere to sit)
  - cells with no impassable neighbour (a disguise there is a wall in open ground)
  - cells already occupied by a landmark or an authored entity coordinate

Usage:  python3 tools/find_secret_pockets.py [world ...]        (default: all six)
"""
import json, subprocess, sys, collections
from pathlib import Path
from PIL import Image

REPO = Path(subprocess.run(["git", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True).stdout.strip())
PALETTE = REPO / "data/maps/map_palette.json"

MIN_POCKET = 4
MAX_POCKET = 70

# world -> (png, blocked chars, scene file, disguise by dominant neighbour char)
WORLDS = {
    "medieval":   ("overworld_w1.png", "~Ml",        "OverworldScene.gd"),
    "suburban":   ("overworld_w2.png", "htwfmyeb",   "SuburbanOverworld.gd"),
    "steampunk":  ("overworld_w3.png", "bpwinFfl",   "SteampunkOverworld.gd"),
    "industrial": ("overworld_w4.png", "bsChGdBpwk", "IndustrialOverworld.gd"),
    "futuristic": ("overworld_w5.png", "SPTAEGNV",   "FuturisticOverworld.gd"),
    "abstract":   ("overworld_w6.png", "BSED",       "AbstractOverworld.gd"),
}

# which disguise reads correctly beside which blocking terrain
DISGUISE = {
    "M": "mountain", "~": "mountain", "l": "mountain",
    "h": "brick", "t": "brick", "w": "brick", "i": "brick", "b": "brick",
    "f": "hedge", "e": "hedge", "y": "hedge", "m": "hedge",
    "p": "brick", "n": "brick", "F": "cave", "s": "brick", "C": "brick",
    "G": "brick", "d": "cave", "B": "cave", "k": "hedge",
    "S": "cave", "P": "brick", "T": "brick", "A": "cave", "E": "cave",
    "N": "brick", "V": "cave",
}


def load(world):
    png, blocked, scene = WORLDS[world]
    pal = json.loads(PALETTE.read_text())["worlds"][world]
    rgb2ch = {tuple(v["rgb"]): ch for sec in ("terrain", "landmarks") for ch, v in pal[sec].items()}
    im = Image.open(REPO / "data/maps" / png).convert("RGB")
    w, h = im.size
    px = im.load()
    g = [[rgb2ch[px[x, y]] for x in range(w)] for y in range(h)]
    return g, w, h, set(blocked), set(pal["landmarks"]), scene


def components(g, w, h, blocked, skip=None):
    seen = set()
    comps = []
    for sy in range(h):
        for sx in range(w):
            if g[sy][sx] in blocked or (sx, sy) in seen or (sx, sy) == skip:
                continue
            stack = [(sx, sy)]
            seen.add((sx, sy))
            cells = [(sx, sy)]
            while stack:
                x, y = stack.pop()
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    n = (x + dx, y + dy)
                    if (0 <= n[0] < w and 0 <= n[1] < h and n not in seen
                            and n != skip and g[n[1]][n[0]] not in blocked):
                        seen.add(n)
                        stack.append(n)
                        cells.append(n)
            comps.append(cells)
    return comps


def analyse(world, verbose=True):
    g, w, h, blocked, landmarks, scene = load(world)
    whole = components(g, w, h, blocked)
    whole.sort(key=len, reverse=True)
    main = set(whole[0])

    # Candidate cells: walkable, touching something impassable, not a landmark.
    cands = []
    for (x, y) in main:
        if g[y][x] in landmarks:
            continue
        nbrs = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
        walls = [g[ny][nx] for nx, ny in nbrs
                 if 0 <= nx < w and 0 <= ny < h and g[ny][nx] in blocked]
        if not walls:
            continue
        # A chokepoint has at most two open neighbours; anything more is open ground.
        opens = 4 - len(walls) - sum(1 for nx, ny in nbrs if not (0 <= nx < w and 0 <= ny < h))
        if opens > 2:
            continue
        cands.append(((x, y), walls))

    # THE ARTICULATION TEST, and the reason the first version of this file was wrong:
    # taking the second-largest component after the removal reports whatever OTHER region
    # the map already had. Medieval has five walkable components, so every candidate
    # "sealed" the same pre-existing 26-tile island and 194 false secrets scored identical.
    # The real question is whether removing THIS cell disconnects part of the MAIN
    # component from the rest of the main component.
    found = []
    seen_pockets = set()
    for (cell, walls) in cands:
        root = None
        for cand_root in main:
            if cand_root != cell:
                root = cand_root
                break
        if root is None:
            continue
        # flood the main component with `cell` removed
        reached = {root}
        stack = [root]
        while stack:
            x, y = stack.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy)
                if (n in main and n not in reached and n != cell):
                    reached.add(n)
                    stack.append(n)
        pocket = main - reached - {cell}
        if not (MIN_POCKET <= len(pocket) <= MAX_POCKET):
            continue
        # One physical pocket is sealed by every cell of its corridor; keep it once, entered
        # at the cell nearest the mainland, which is where a wall reads as a wall.
        key = frozenset(pocket)
        if key in seen_pockets:
            continue
        seen_pockets.add(key)
        pocket = sorted(pocket)
        wall_kind = collections.Counter(walls).most_common(1)[0][0]
        # place the reward at the pocket cell furthest from the entrance
        deepest = max(pocket, key=lambda p: abs(p[0] - cell[0]) + abs(p[1] - cell[1]))
        found.append({
            "world": world, "scene": scene,
            "passage": list(cell), "disguise": DISGUISE.get(wall_kind, "cave"),
            "wall_char": wall_kind, "pocket_size": len(pocket), "reward_at": list(deepest),
            "_pocket_set": set(pocket),
        })

    # NESTED POCKETS ARE ONE SECRET. Every cell along a dead-end corridor is an
    # articulation point, so a 70-tile corridor reports ~70 "secrets" whose pockets are
    # nested subsets. The real entrance is the one nearest the mainland -- the largest
    # pocket -- and everything inside it is the same place. Collapse by containment, not
    # by equality: equality alone reported 107 for W6's two corridors.
    found.sort(key=lambda f: -f["pocket_size"])
    kept = []
    kept_sets = []
    for f in found:
        ps = f["_pocket_set"]
        if any(ps <= k for k in kept_sets):
            continue
        kept.append(f)
        kept_sets.append(ps)
    found = kept
    for f in found:
        f.pop("_pocket_set", None)
    if verbose:
        print(f"  {world:11} map {w}x{h}  walkable comps {len(whole)}  candidates {len(cands)}  SECRETS {len(found)}")
        for f in found[:6]:
            print(f"     passage {tuple(f['passage'])} disguise={f['disguise']:8} "
                  f"seals {f['pocket_size']:3} tiles, reward at {tuple(f['reward_at'])}")
    return found


def main():
    worlds = [a for a in sys.argv[1:] if not a.startswith("-")] or list(WORLDS)
    all_found = []
    for wd in worlds:
        all_found += analyse(wd)
    out = REPO / "tmp/secret_pockets.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(all_found, indent=2))
    print(f"\n  {len(all_found)} candidate secrets -> {out.relative_to(REPO)}")


if __name__ == "__main__":
    main()
