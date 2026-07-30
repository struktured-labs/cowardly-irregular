#!/usr/bin/env python3
"""Fix up-facing (row 3) top-edge density on archetype overworld sheets.

Cross-lane ask from cowir-overworld via cowir-main msg 2833: traveler +
monk sheets have 22-27 opaque pixels at cell y+0 of row 3, causing Mode
7 billboard head-clip near the horizon (Lost Pilgrim playtest cap). Other
archetypes are ≤14 (mostly ≤11).

Fix: for row 3 (y=96..127) of each 128x128 sheet, squash each 32x32 cell
vertically from 32 -> 29 rows (nearest-neighbor, preserves pixel-art
edges) and paste at y+3 within the cell. Result: 3-row transparent
margin at top, feet + silhouette bottom preserved.

Backs up originals to sprite-gen tmp/ (never next to shipping sheets —
followed the .pre_* leak-into-commits lesson).

Usage:
    uv run python tools/fix_uprow_headroom.py traveler monk
    uv run python tools/fix_uprow_headroom.py --check-only <archetype>...
"""
import argparse
import shutil
import sys
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path("/home/struktured/projects/cowardly-irregular-artist-ship")
NPCS = GAME_REPO / "assets" / "sprites" / "npcs"
BACKUP_DIR = PROJECT / "tmp" / "pre_uprow_headroom_backups"

CELL = 32
ROW3_Y = 3 * CELL  # 96 — top of row 3
SHRUNK = 29        # squash 32 -> 29 rows
SHIFT = CELL - SHRUNK  # 3px transparent margin at top


def top_density(img: Image.Image) -> list[int]:
    """Opaque pixel count at row_3 top edge (y=96) per column-cell."""
    px = img.load()
    return [
        sum(1 for x in range(col * CELL, (col + 1) * CELL) if px[x, ROW3_Y][3] > 0)
        for col in range(4)
    ]


def fix_sheet(sheet_path: Path) -> tuple[list[int], list[int]]:
    """Apply squash-and-shift to row 3. Returns (before, after) densities."""
    img = Image.open(sheet_path).convert("RGBA")
    before = top_density(img)

    # Extract row 3 (128 wide × 32 tall)
    row3 = img.crop((0, ROW3_Y, 128, ROW3_Y + CELL))

    # New row 3 canvas — start fully transparent
    new_row3 = Image.new("RGBA", (128, CELL), (0, 0, 0, 0))

    # Squash each 4-cell strip vertically, paste at y=SHIFT within row
    squashed = row3.resize((128, SHRUNK), Image.NEAREST)
    new_row3.paste(squashed, (0, SHIFT), squashed)

    # Splice back — paste WITHOUT alpha mask so the transparent top-3
    # rows of new_row3 unconditionally overwrite the original opaque
    # slab (using new_row3 as its own mask preserves the original
    # content wherever new_row3 has alpha=0, defeating the whole point).
    img.paste(new_row3, (0, ROW3_Y))

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    bak = BACKUP_DIR / (sheet_path.parent.name + "_" + sheet_path.name + ".bak")
    if not bak.exists():
        shutil.copy2(sheet_path, bak)

    img.save(sheet_path)
    after = top_density(img)
    return before, after


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("archetypes", nargs="+",
                    help="archetype folder names under assets/sprites/npcs/")
    ap.add_argument("--check-only", action="store_true",
                    help="just report current top-density, don't rewrite")
    args = ap.parse_args()

    for arch in args.archetypes:
        p = NPCS / arch / "overworld.png"
        if not p.exists():
            print(f"SKIP {arch}: not found at {p}", file=sys.stderr)
            continue
        if args.check_only:
            img = Image.open(p).convert("RGBA")
            print(f"[{arch}] row-3 y+0 densities: {top_density(img)}")
        else:
            before, after = fix_sheet(p)
            print(f"[{arch}] row-3 y+0: {before} -> {after}  (backup: "
                  f"{BACKUP_DIR / (arch + '_overworld.png.bak')})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
