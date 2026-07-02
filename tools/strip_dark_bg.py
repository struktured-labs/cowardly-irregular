#!/usr/bin/env python3
"""Strip dark (near-black) or near-white backgrounds from monster sheets.

Complements the transparent-bg wash inside regen_monster_artist_style.py
which only handled the near-white case. Some gpt-image-1 outputs come
back with a dark background instead (dark themes, high-contrast prompts).

Detects the corner-pixel color; if the four corners agree on a near-
black or near-white value, floods the connected background region and
sets alpha to 0. Uses seed-fill from all four corners so it doesn't
destroy dark pixels that are legitimately part of the character.

Usage:
    uv run python tools/strip_dark_bg.py fighter_skeleton_knight
    uv run python tools/strip_dark_bg.py --all-t2 --dry-run
"""
import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
MANIFEST = GAME_REPO / "data/sprite_manifest.json"


def detect_bg_color(img: np.ndarray, corner_agree_threshold: int = 24) -> tuple[int, int, int] | None:
    """Sample the 4 corners. Skip transparent pixels (alpha < 32) since
    the regen-tool's 1px bob leaves transparent edges. Take the median
    of remaining opaque corners; if all opaque corners agree, use it."""
    H, W = img.shape[:2]
    corners = [img[0, 0], img[0, W - 1], img[H - 1, 0], img[H - 1, W - 1]]
    opaque = [c for c in corners if c[3] >= 32]
    if not opaque:
        return None
    ref = opaque[0][:3].astype(int)
    for c in opaque[1:]:
        if np.max(np.abs(c[:3].astype(int) - ref)) > corner_agree_threshold:
            return None
    return tuple(int(x) for x in ref)


def strip_bg_seeded(img_arr: np.ndarray, bg: tuple[int, int, int],
                    tolerance: int = 40) -> np.ndarray:
    """Flood-fill background regions connected to any edge pixel that
    matches bg within tolerance. Sets alpha=0 for those pixels. Leaves
    interior pixels alone."""
    rgb = img_arr[:, :, :3].astype(int)
    bg_arr = np.array(bg)
    dist = np.max(np.abs(rgb - bg_arr), axis=2)
    bg_mask = dist <= tolerance

    # Seed from all edge pixels that match bg
    seeds = np.zeros_like(bg_mask)
    seeds[0, :] = bg_mask[0, :]
    seeds[-1, :] = bg_mask[-1, :]
    seeds[:, 0] = bg_mask[:, 0]
    seeds[:, -1] = bg_mask[:, -1]

    # Label connected components of the bg_mask; the ones touching seeds
    # are actual background, interior islands are character features.
    labeled, n = ndimage.label(bg_mask)
    seed_labels = set(labeled[seeds].tolist()) - {0}
    keep_bg = np.isin(labeled, list(seed_labels))

    out = img_arr.copy()
    out[keep_bg, 3] = 0
    return out


def strip_file(path: Path, dry_run: bool = False) -> dict:
    img = Image.open(path).convert("RGBA")
    arr = np.array(img)
    bg = detect_bg_color(arr)
    if bg is None:
        return {"path": path.name, "status": "corners disagree — no strip"}
    r, g, b = bg
    # Skip if the "background" is already transparent — the alpha of the
    # corner pixel tells us that
    corner_a = int(arr[0, 0, 3])
    if corner_a < 32:
        return {"path": path.name, "status": "already transparent"}
    kind = "dark" if r + g + b < 200 else ("light" if r + g + b > 640 else "mid")
    if kind == "mid":
        return {"path": path.name, "status": f"mid-tone bg ({r},{g},{b}) — refusing"}
    if dry_run:
        return {"path": path.name, "status": f"would strip {kind} bg=({r},{g},{b})"}
    stripped = strip_bg_seeded(arr, bg)
    Image.fromarray(stripped, "RGBA").save(path)
    return {"path": path.name, "status": f"STRIPPED {kind} bg=({r},{g},{b})"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("monsters", nargs="*")
    parser.add_argument("--all-t2", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.all_t2:
        manifest = json.loads(MANIFEST.read_text())
        mss = manifest.get("monster_sheets", {})
        targets = [mid for mid, meta in mss.items() if meta.get("tier") == "T2"]
    else:
        targets = args.monsters

    if not targets:
        print("No monsters to process")
        return 1

    monsters_dir = GAME_REPO / "assets" / "sprites" / "monsters"
    for mid in targets:
        p = monsters_dir / f"{mid}.png"
        if not p.exists():
            print(f"  SKIP {mid}: missing file")
            continue
        r = strip_file(p, dry_run=args.dry_run)
        print(f"  {r['path']}: {r['status']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
