#!/usr/bin/env python3
"""Give dialogue portraits back the whites of their eyes.

The AI portraits were generated on a white backdrop and keyed on near-white (R,G,B >= 240). The key
took the backdrop and, with it, everything else that white: the whites of the eyes, teeth, the glint
on a lens. 102 of 165 portraits have see-through holes inside the figure, so in a conversation the
speaker's eyes show the dialogue panel through them.

A hole here is a clear region the figure fully encloses. What the key removed was near-white, so:
- a hole of 5..MAX_HOLE px (an eye white, a row of teeth) is filled near-white;
- a speck of up to 4 px takes the commonest colour on its own rim (a white dot in dark hair would
  be a new defect, and a speck that small is a lost highlight of its surroundings);
- a hole listed in EYES_LEFT_CLEAR is skipped: a whole eye with no pupil left, which white would blind;
- a hole larger than MAX_HOLE is LEFT and reported: a whole keyed face or veil needs an eye on it,
  and a real opening (staff to body) must not be painted shut. REVIEWED_LARGE raises the cap for the
  portraits that were looked at one by one; LEFT_OPEN names the ones deliberately not filled.
Portraits cut from the artist's own sheets are never touched (ARTIST_DERIVED): a hole in those is his.

Usage:
    python3 tools/fill_portrait_key_holes.py --audit
    python3 tools/fill_portrait_key_holes.py --apply
    python3 tools/fill_portrait_key_holes.py --selftest
"""
import argparse
import glob
import os
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PORTRAITS = "assets/sprites/portraits"
ALPHA = 128
MAX_HOLE = 160
SPECK = 4
KEYED_WHITE = (246, 246, 246)
NEIGHBOURS = ((-1, 0), (1, 0), (0, -1), (0, 1))
# Holes above MAX_HOLE, zoomed one portrait at a time on 2026-10-12 and found to be keyed white (eye whites just
# over the cap, teeth, a white veil, hood lining, collar or hair): the largest hole each may have filled.
REVIEWED_LARGE = {
    "bossbinder.png": 492, "cleric_abstract.png": 5398, "cleric_digital.png": 397,
    "cleric_industrial.png": 785, "cleric_steampunk.png": 954, "cleric_suburban.png": 2056,
    "keepers/brutus.png": 200, "keepers/lenora.png": 2527, "masterite_arbiter_medieval.png": 1197,
    "ninja.png": 295, "npcs/boris.png": 328, "npcs/bram.png": 175,
    "npcs/child.png": 251, "npcs/dr_temporal.png": 246, "npcs/elder.png": 247,
    "npcs/guard.png": 196, "npcs/knight.png": 176, "npcs/nervous.png": 271,
    "npcs/pilgrim.png": 892, "npcs/pip.png": 198, "npcs/rowan.png": 426,
    "npcs/shopkeeper.png": 340, "npcs/villager_f.png": 351, "npcs/young_woman.png": 173,
    "scriptweaver.png": 337, "skiptrotter.png": 193, "speculator_abstract.png": 181,
    "summoner_suburban.png": 221, "time_mage.png": 295, "time_mage_industrial.png": 344,
    "time_mage_steampunk.png": 195, "time_mage_suburban.png": 333,
}
# Whole EYES the key took, pupil and all: nothing of the eye survives, and painted white they read as blind
# (seen on the elder, Brutus and Boris after the second pass, 2026-10-12). Left clear, where the dark dialogue
# panel reads as a dark eye, until the portrait is redrawn. Each point is the centre of a hole to skip.
EYES_LEFT_CLEAR = {
    "bossbinder.png": ((91, 66), (162, 65)),
    "keepers/brutus.png": ((102, 103), (153, 103)),
    "keepers/mortimer.png": ((104, 109), (150, 108)),
    "ninja.png": ((100, 122), (153, 122)),
    "npcs/boris.png": ((105, 113), (151, 113)),
    "npcs/child.png": ((96, 102), (152, 102), (101, 122), (151, 122), (85, 124), (166, 123)),
    "npcs/elder.png": ((103, 106), (151, 106)),
    "npcs/rowan.png": ((105, 87), (150, 87), (104, 101), (151, 101)),
    "npcs/shopkeeper.png": ((102, 112), (153, 112)),
    "npcs/villager.png": ((103, 128), (154, 128)),
    "npcs/villager_f.png": ((106, 93), (152, 93), (106, 109), (151, 109), (83, 114), (175, 114)),
}
EYE_MATCH = 5
# Left open on purpose: a real gap between a staff and a body, or a whole face whose fill is an art decision.
LEFT_OPEN = ("mage_abstract.png", "mage_industrial.png", "mage_suburban.png", "masterite_curator_medieval.png",
             "ninja.png", "npcs/fairy.png", "npcs/hooded_mage.png", "npcs/mysterious.png")
# Busts cut from the artist's battle sheets (the five starters, Mordaine and her other face): never filled.
ARTIST_DERIVED = ("fighter.png", "cleric.png", "mage.png", "rogue.png", "bard.png", "mordaine.png",
                  "chancellor_mordaine.png", "calibrant.png")


def holes(rgba: np.ndarray) -> list:
    """[(pixels, rim pixels)] for every clear region the figure fully encloses (4-connected)."""
    opaque = rgba[..., 3] >= ALPHA
    h, w = opaque.shape
    seen = np.zeros((h, w), dtype=bool)
    out = []
    for sy in range(h):
        for sx in range(w):
            if opaque[sy, sx] or seen[sy, sx]:
                continue
            seen[sy, sx] = True
            stack, region, rim, enclosed = [(sy, sx)], [], set(), True
            while stack:
                y, x = stack.pop()
                region.append((y, x))
                for dy, dx in NEIGHBOURS:
                    ny, nx = y + dy, x + dx
                    if ny < 0 or nx < 0 or ny >= h or nx >= w:
                        enclosed = False
                    elif opaque[ny, nx]:
                        rim.add((ny, nx))
                    elif not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if enclosed and rim:
                out.append((region, rim))
    return out


def _is_listed_eye(region: list, eyes: tuple) -> bool:
    cy = sum(y for y, _ in region) / len(region)
    cx = sum(x for _, x in region) / len(region)
    return any(abs(cx - ex) <= EYE_MATCH and abs(cy - ey) <= EYE_MATCH for ex, ey in eyes)


def fill(img: Image.Image, cap: int = MAX_HOLE, eyes: tuple = ()):
    """(new image, pixels filled, [sizes of holes left as too large]). cap is the largest hole to fill; eyes are skipped."""
    rgba = np.asarray(img.convert("RGBA")).copy()
    filled, left = 0, []
    for region, rim in holes(rgba):
        if _is_listed_eye(region, eyes):
            continue
        if len(region) > cap:
            left.append(len(region))
            continue
        if len(region) <= SPECK:
            colour = Counter(tuple(int(v) for v in rgba[y, x, :3]) for y, x in rim).most_common(1)[0][0]
        else:
            colour = KEYED_WHITE
        for y, x in region:
            rgba[y, x] = (*colour, 255)
        filled += len(region)
    return Image.fromarray(rgba), filled, left


def portraits() -> list:
    """Every portrait a fill may touch: all of them but the artist-derived busts."""
    found = sorted(os.path.relpath(p, ROOT) for p in glob.glob(str(ROOT / PORTRAITS / "**" / "*.png"), recursive=True))
    return [p for p in found if os.path.basename(p) not in ARTIST_DERIVED]


def selftest() -> int:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    for y in range(8, 56):
        for x in range(8, 56):
            px[x, y] = (200, 150, 120, 255)
    for y in range(20, 24):
        for x in range(16, 24):
            px[x, y] = (0, 0, 0, 0)          # an eye white: 32 px
    px[40, 40] = (0, 0, 0, 0)                # a speck
    for y in range(30, 50):
        for x in range(28, 48):
            px[x, y] = (0, 0, 0, 0) if (x, y) != (40, 40) and x >= 30 else px[x, y]   # a 360 px opening
    out, n, left = fill(img)
    assert out.getpixel((18, 21)) == (*KEYED_WHITE, 255), "an eye-sized hole comes back near-white"
    assert left and left[0] > MAX_HOLE and out.getpixel((35, 45))[3] == 0, "a large opening is left and reported (%s)" % left
    edge = Image.new("RGBA", (64, 64), (200, 150, 120, 255))
    edge.putpixel((0, 30), (0, 0, 0, 0))
    assert fill(edge)[1] == 0, "a notch open to the image edge is not a hole"
    speck = Image.new("RGBA", (64, 64), (30, 20, 20, 255))
    speck.putpixel((30, 30), (0, 0, 0, 0))
    out2, n2, _ = fill(speck)
    assert n2 == 1 and out2.getpixel((30, 30)) == (30, 20, 20, 255), "a speck takes its rim's colour, not white"
    assert fill(out)[1] == 0, "a second pass fills nothing"
    wide, n3, left3 = fill(img, 400)
    assert not left3 and wide.getpixel((35, 45)) == (*KEYED_WHITE, 255), "a reviewed cap fills the larger hole too"
    assert not set(REVIEWED_LARGE) & set(ARTIST_DERIVED), "no artist bust is on the reviewed list"
    kept, n4, _ = fill(img, 400, ((19.5, 21.5),))
    assert kept.getpixel((18, 21))[3] == 0 and kept.getpixel((35, 45)) == (*KEYED_WHITE, 255), "a listed eye is left clear, the rest is filled"
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
    total = files = 0
    for rel in portraits():
        img = Image.open(ROOT / rel)
        key = os.path.relpath(rel, PORTRAITS)
        out, n, left = fill(img, max(MAX_HOLE, REVIEWED_LARGE.get(key, 0)), EYES_LEFT_CLEAR.get(key, ()))
        if left:
            print("LEFT %s: %d hole(s) too large to fill blind, %s px" % (rel, len(left), sorted(left, reverse=True)[:4]))
        if not n:
            continue
        files += 1
        total += n
        print("%s %s: %d px" % ("FILLED" if args.apply else "CAN FILL", rel, n))
        if args.apply:
            out.save(ROOT / rel)
    print("%d portrait(s), %d px %s" % (files, total, "filled" if args.apply else "fillable"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
