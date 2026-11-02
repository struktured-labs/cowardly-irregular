#!/usr/bin/env python3
"""Build a door-open strip for a drawn building from that building's OWN door pixels (T1, derived, no image model).

struktured 2026-11-01 (relayed, cowir-main 21319): "The doors need an opening animation I think." Each frame is the door
leaf of the building's art swinging inward on its hinge (a horizontal squash toward the hinge side), uncovering a dark,
lamp-warm interior. Nothing is redrawn, so the open door IS the drawn door, in every building's own palette.

The door LEAF is found inside a given rect (art pixels) by flood-filling from the rect's centre over colours close to the
leaf's own, so the stone arch and frame around it stay as they are. Rects come from the door probe (tmp/door_rects.json);
--rect overrides one by hand for a preview.

Output per building: a strip of FRAMES frames, each the size of the door rect, transparent outside the leaf + opening, so
it overlays the building art exactly at the rect's origin. Staged under tmp/door_strips/.

Usage:
    uv run python tools/gen_door_strips.py harmonia_library --rect 80,127,101,165 --preview
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
STAGE = ROOT / "tmp/door_strips"
FRAMES = 4
OPEN = (1.0, 0.62, 0.3, 0.0)  ## leaf width per frame: shut, swinging, mostly open, fully open (edge-on)
INSIDE_TOP = np.array([22, 15, 12], float)   ## the dark interior under the lintel
INSIDE_FLOOR = np.array([92, 58, 28], float)  ## lamp-warm floor glow toward the threshold


def building_art(key: str) -> Image.Image:
    m = json.loads((ROOT / "data/sprite_manifest.json").read_text())
    for sec in ("building_art", "prop_art"):
        e = m.get(sec, {}).get(key)
        if isinstance(e, dict) and e.get("path"):
            return Image.open(ROOT / str(e["path"]).replace("res://", "")).convert("RGBA")
    raise SystemExit(f"no building_art entry {key}")


def leaf_mask(rgba: np.ndarray, tol: float = 58.0) -> np.ndarray:
    """The door leaf inside a rect crop: every pixel reachable from the centre through colours near the leaf's median."""
    h, w = rgba.shape[:2]
    rgb = rgba[:, :, :3].astype(float)
    cy, cx = h * 2 // 3, w // 2
    seed = np.median(rgb[max(0, cy - 2):cy + 3, max(0, cx - 2):cx + 3].reshape(-1, 3), axis=0)
    near = (np.sqrt(((rgb - seed) ** 2).sum(axis=2)) < tol) | (rgb.sum(axis=2) < 140)  ## wood, and its dark iron/grain
    near &= rgba[:, :, 3] > 0
    mask = np.zeros((h, w), bool)
    q = deque([(cy, cx)])
    while q:
        y, x = q.popleft()
        if 0 <= y < h and 0 <= x < w and near[y, x] and not mask[y, x]:
            mask[y, x] = True
            q.extend(((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)))
    return mask


def leaf_at(art: Image.Image, x: float, base_y: float, tol: float = 58.0):
    """The door leaf the player walks into at art column x: flood from just above the base, and return its bounding rect
    (x0, y0, x1, y1), or None when what is there is not door-sized (a wall, a window, an open arch): at most 40% of the
    art's width (a flat wall floods wider), taller than wide, and reaching down to within 16px of the art's base."""
    a = np.asarray(art).astype(int)
    h, w = a.shape[:2]
    for t in (tol, 42.0, 75.0):
        for lift in (6, 10, 14, 3, 18):
            sy, sx = int(min(base_y, h) - lift), int(min(max(x, 0), w - 1))
            if sy < 0 or a[sy, sx, 3] == 0:
                continue
            seed = np.median(a[max(0, sy - 1):sy + 2, max(0, sx - 1):sx + 2, :3].reshape(-1, 3), axis=0)
            near = (np.sqrt(((a[:, :, :3] - seed) ** 2).sum(axis=2)) < t) & (a[:, :, 3] > 0)
            mask = np.zeros((h, w), bool)
            q = deque([(sy, sx)])
            while q:
                yy, xx = q.popleft()
                if 0 <= yy < h and 0 <= xx < w and near[yy, xx] and not mask[yy, xx]:
                    mask[yy, xx] = True
                    q.extend(((yy + 1, xx), (yy - 1, xx), (yy, xx + 1), (yy, xx - 1)))
            ys, xs = np.where(mask)
            if ys.size == 0:
                continue
            box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
            bw, bh = box[2] - box[0], box[3] - box[1]
            if 8 <= bw <= min(40, 0.4 * w) and 14 <= bh <= 64 and bh >= bw and h - box[3] <= 16:
                return box
    return None


def strip(art: Image.Image, rect: tuple, whole: bool = False) -> tuple:
    x0, y0, x1, y1 = rect
    crop = np.asarray(art.crop(rect)).copy()
    mask = (crop[:, :, 3] > 0) if whole else leaf_mask(crop)
    if not mask.any():  ## the rect IS the reviewed leaf box: when the colour flood misses, the leaf is its opaque pixels
        mask = crop[:, :, 3] > 0
    h, w = mask.shape
    cols = np.where(mask.any(axis=0))[0]
    lx0, lx1 = int(cols.min()), int(cols.max()) + 1
    lw = lx1 - lx0
    ## The opening: the leaf's own silhouette, filled with the interior, darker high and warmer toward the threshold.
    t = (np.arange(h, dtype=float) / max(h - 1, 1))[:, None, None] ** 1.6
    inside = (INSIDE_TOP * (1 - t) + INSIDE_FLOOR * t).repeat(w, axis=1)
    frames = []
    for f, frac in enumerate(OPEN):
        out = np.zeros((h, w, 4), np.uint8)
        out[mask, :3] = inside[mask].astype(np.uint8)
        out[mask, 3] = 255
        nw = max(1, round(lw * frac)) if frac > 0 else 0
        if nw:
            leaf = crop[:, lx0:lx1].copy()
            leaf[~mask[:, lx0:lx1], 3] = 0
            ## Swinging inward it turns away from the light: a squashed leaf, a little darker each step.
            sq = np.asarray(Image.fromarray(leaf).resize((nw, h), Image.NEAREST)).copy()
            sq[:, :, :3] = (sq[:, :, :3].astype(float) * (0.55 + 0.45 * frac)).astype(np.uint8)
            region = out[:, lx0:lx0 + nw]
            a = sq[:, :, 3] > 0
            region[a] = sq[a]
        ## Edge-on at the end: a one-pixel jamb line on the hinge side keeps the leaf readable as still there.
        if frac == 0.0:
            jamb = mask[:, lx0] if lx0 < w else np.zeros(h, bool)
            out[jamb, lx0, :3] = (crop[jamb, lx0, :3].astype(float) * 0.5).astype(np.uint8)
        frames.append(out)
    sheet = np.concatenate(frames, axis=1)
    return Image.fromarray(sheet, "RGBA"), {"rect": [x0, y0, x1, y1], "frames": FRAMES, "leaf_px": int(mask.sum())}


## Rects found from each building's art CENTRE (cowir-overworld snaps every entrance to the art's centre x, and measured
## every drawn door within ~11px of it), widening the seed column by 4px steps out to 24px. Each one was then looked at
## on the art (tmp/door_scan.png); only the ones that box the real door ship. The rest are listed with why, so a door is
## never animated on a window, a porch column or half a leaf.
REVIEWED = [
    "brasston_cottage", "brasston_forge", "brasston_house", "eldertree_inn", "frosthold_chapel", "frosthold_furs",
    "frosthold_lodge", "grimhollow_chapel", "grimhollow_inn", "harmonia_arcana", "harmonia_arms", "harmonia_chapel",
    "harmonia_house", "harmonia_library", "harmonia_tavern", "ironhaven_steamworks", "ironhaven_tavern", "maple_house",
    "maple_mart", "maple_moms_house", "nodeprime_cache", "nodeprime_inn", "sandrift_bazaar", "sandrift_inn",
    "vertex_exchange", "vertex_rest",
]
REFUSED = {
    "brasston_inn": "the flood boxed a window panel right of the door (the arched door is left of centre)",
    "ironhaven_inn": "boxed the wall right of the doorway",
    "maple_garage_sale_house": "boxed a porch column, not the green door",
    "grimhollow_curios": "a dark wall panel; not certain it is the door",
    "ironhaven_forge": "the forge's fire mouth, not a door",
    "brasston_shed": "the flood never isolated the arched leaf",
}
## Leaves the flood could not isolate, measured by eye on a pixel grid (tmp/door_hand.png) and checked drawn on the art:
## (x0, y0, x1, y1) in the art's own pixels. The whole rect is the leaf. cowir-overworld 21441: every harmonia_* entrance
## building needs a door record, and the remedies is his pinned case.
HAND = {
    "harmonia_inn": (86, 100, 112, 135),       # the iron-banded plank leaf between its lintel and its step
    "harmonia_remedies": (90, 113, 111, 146),  # the leaf under the transom window, between the potted plants
}
SHOP_WORDS = ("inn", "tavern", "mart", "bazaar", "arms", "remedies", "arcana", "curios", "furs", "forge", "steamworks",
              "cache", "exchange", "rest")


def deploy() -> int:
    import hashlib
    found = json.loads((ROOT / "tmp/door_rects.json").read_text())
    mp, lp = ROOT / "data/sprite_manifest.json", ROOT / "data/artist_sprite_ledger.json"
    m, ledger = json.loads(mp.read_text()), json.loads(lp.read_text())
    for key in REVIEWED + sorted(HAND):
        x0, y0, x1, y1 = HAND[key] if key in HAND else found[key]["rect"]
        img, _ = strip(building_art(key), (x0, y0, x1, y1), whole=key in HAND)
        art_path = str(m["building_art"][key]["path"]).replace("res://", "")
        rel = str(Path(art_path).parent / f"door_open_{key}.png")
        img.save(ROOT / rel)
        m["building_art"][key]["door"] = {
            "rect": [x0, y0, x1 - x0, y1 - y0], "open": f"res://{rel}", "frames": FRAMES,
            "style": "shop" if any(w in key for w in SHOP_WORDS) else "house"}
        ledger[rel] = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
        print(f"door {key}: rect {m['building_art'][key]['door']['rect']} -> {rel}")
    mp.write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
    lp.write_text(json.dumps(ledger, indent=1, sort_keys=True) + "\n")
    print(f"{len(REVIEWED) + len(HAND)} doors registered ({len(HAND)} by hand); refused {len(REFUSED)}: {sorted(REFUSED)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("buildings", nargs="*")
    ap.add_argument("--rect", help="x0,y0,x1,y1 in art pixels (overrides the probe's rect; one building only)")
    ap.add_argument("--deploy", action="store_true", help="build and register the REVIEWED doors")
    ap.add_argument("--from-probe", action="store_true", help="every building with an entrance in tmp/door_entrances.json")
    ap.add_argument("--preview", action="store_true", help="also write the frames composited on the building at 4x")
    args = ap.parse_args()
    if args.deploy:
        return deploy()
    probed = {}
    rp = ROOT / "tmp/door_rects.json"
    if rp.exists():
        probed = json.loads(rp.read_text())
    STAGE.mkdir(parents=True, exist_ok=True)
    if args.from_probe:
        found, refused = {}, []
        ent = json.loads((ROOT / "tmp/door_entrances.json").read_text())
        for key, b in sorted(ent.items()):
            for d in b["doors"]:
                art = building_art(key)
                r = leaf_at(art, float(d["art_x"]), float(b["base_y"]))
                if r is None:
                    refused.append(f"{key}:{d['node']}@x={d['art_x']:.0f}")
                    continue
                style = "shop" if d["class"] in ("VillageShop", "VillageInn", "VillageBar") else "house"
                found.setdefault(key, []).append({"rect": list(r), "style": style, "entrance": d["node"]})
        rp.write_text(json.dumps({k: v[0] | {"all": v} for k, v in found.items()}, indent=1))
        probed = json.loads(rp.read_text())
        print(f"doors found {sum(len(v) for v in found.values())} in {len(found)} buildings; refused {len(refused)}: {refused}")
        args.buildings = sorted(found)
    for key in args.buildings:
        rect = tuple(int(v) for v in args.rect.split(",")) if args.rect else tuple(probed[key]["rect"])
        art = building_art(key)
        img, meta = strip(art, rect)
        img.save(STAGE / f"door_open_{key}.png")
        (STAGE / f"door_open_{key}.json").write_text(json.dumps(meta))
        print(f"staged door_open_{key}.png {img.size} {meta}")
        if args.preview:
            fw = rect[2] - rect[0]
            pad = 24
            box = (max(0, rect[0] - pad), max(0, rect[1] - pad), min(art.width, rect[2] + pad), art.height)
            tiles = []
            for f in range(FRAMES):
                a = art.copy()
                a.alpha_composite(img.crop((f * fw, 0, (f + 1) * fw, img.height)), (rect[0], rect[1]))
                bg = Image.new("RGBA", a.size, (40, 40, 40, 255))
                bg.alpha_composite(a)
                tiles.append(bg.crop(box))
            pw = sum(t.width for t in tiles) + 6 * (FRAMES - 1)
            pv = Image.new("RGBA", (pw, tiles[0].height), (20, 20, 20, 255))
            x = 0
            for t in tiles:
                pv.alpha_composite(t, (x, 0))
                x += t.width + 6
            pv.resize((pv.width * 4, pv.height * 4), Image.NEAREST).save(STAGE / f"preview_{key}.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
