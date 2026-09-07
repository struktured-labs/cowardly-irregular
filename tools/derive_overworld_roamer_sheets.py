#!/usr/bin/env python3
"""Derive 32px overworld roamer walk-grids from battle idle frames.

RoamingMonster loads assets/sprites/monsters/overworld/<id>.png (128x128, a 4x4
grid: rows down/left/right/up, 4 frames each) and falls back to a hue-hashed
SQUARE when the sheet is absent — struktured's "monsters are just squares"
report. This fills every roaming-capable id mechanically from its battle sheet:
no generation cost, T1 placeholder quality, superseded whenever real walk grids
land.

Facing: on-disk battle art faces RIGHT when frame_height > 128 and LEFT when
<= 128 (the engine flips those in battle). The right-facing row mirrors
accordingly; down/up rows use the frames as-is.

Usage: uv run python tools/derive_overworld_roamer_sheets.py [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "assets/sprites/monsters/overworld"
CELL = 32
GRID = 128
ROW_DOWN, ROW_LEFT, ROW_RIGHT, ROW_UP = 0, 1, 2, 3


def roaming_ids() -> list[str]:
    pools = json.load(open(REPO / "data/enemy_pools.json"))
    monsters = set(json.load(open(REPO / "data/monsters.json")).keys())
    acc: set[str] = set()

    def walk(o):
        if isinstance(o, dict):
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for x in o:
                walk(x)
        elif isinstance(o, str):
            acc.add(o)

    walk(pools)
    return sorted(acc & monsters)


def idle_cells(entry: dict, sheet: Image.Image) -> list[Image.Image]:
    fw = int(entry.get("frame_width", 256))
    fh = int(entry.get("frame_height", 256))
    anims = entry.get("animations", {})
    if isinstance(anims, dict) and "idle" in anims:
        a, b = int(anims["idle"]["start"]), int(anims["idle"]["end"])
    else:
        a, b = 0, min(3, sheet.width // fw - 1)
    cells = []
    for i in range(a, b + 1):
        if (i + 1) * fw <= sheet.width:
            cells.append(sheet.crop((i * fw, 0, (i + 1) * fw, min(fh, sheet.height))))
    return cells or [sheet.crop((0, 0, fw, min(fh, sheet.height)))]


def shrink(cell: Image.Image) -> Image.Image:
    bb = cell.split()[3].point(lambda p: 255 if p > 10 else 0).getbbox()
    if bb:
        cell = cell.crop(bb)
    s = (CELL - 2) / max(cell.width, cell.height)
    small = cell.resize((max(1, round(cell.width * s)), max(1, round(cell.height * s))), Image.BOX)
    tile = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    tile.paste(small, ((CELL - small.width) // 2, CELL - 1 - small.height), small)
    return tile


def build_grid(tiles: list[Image.Image], faces_right: bool) -> Image.Image:
    grid = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    mirrored = [t.transpose(Image.FLIP_LEFT_RIGHT) for t in tiles]
    right_row = tiles if faces_right else mirrored
    left_row = mirrored if faces_right else tiles
    rows = {ROW_DOWN: tiles, ROW_LEFT: left_row, ROW_RIGHT: right_row, ROW_UP: tiles}
    for row, src in rows.items():
        for col in range(4):
            grid.paste(src[col % len(src)], (col * CELL, row * CELL))
    return grid


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    sheets = json.load(open(REPO / "data/sprite_manifest.json"))["monster_sheets"]
    made, skipped, kept = [], [], []
    for mid in roaming_ids():
        out = OUT / f"{mid}.png"
        if out.exists():
            kept.append(mid)
            continue
        entry = sheets.get(mid)
        path = REPO / str(entry.get("path", "")).replace("res://", "") if entry else None
        if not entry or not path.exists():
            skipped.append(mid)
            continue
        sheet = Image.open(path).convert("RGBA")
        tiles = [shrink(c) for c in idle_cells(entry, sheet)]
        faces_right = int(entry.get("frame_height", 256)) > 128
        if not args.dry_run:
            build_grid(tiles, faces_right).save(out)
        made.append(mid)
    print("derived %d · kept existing %d · no battle sheet %d" % (len(made), len(kept), len(skipped)))
    if skipped:
        print("still squares (no source):", ", ".join(skipped))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
