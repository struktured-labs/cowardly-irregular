#!/usr/bin/env python3
"""Detect + fix sprite content bleeding across 4x4 overworld cell rows.

struktured, live playtest 2026-07-25: "mage overworld sprite is double
vertically slightly so its feet is tiling on the top."

Cause: a figure drawn taller than its 32px cell. The overflow lands in
the NEXT row's cell, and Godot's slicer renders it at that cell's TOP
edge — so every row shows the previous row's feet floating above its
own sprite.

Fix: per row, take the cell band plus a lookahead window, find the real
content bbox, and re-seat it wholly inside the 32px cell (bottom-aligned
with a 1px floor margin). Squashes only if the content genuinely exceeds
32px; otherwise it is a pure translation and pixels are untouched.

Backups go to sprite-gen tmp/, never beside the shipping sheet.

Usage:
    uv run python tools/fix_overworld_row_bleed.py --audit-all
    uv run python tools/fix_overworld_row_bleed.py jobs/mage
    uv run python tools/fix_overworld_row_bleed.py jobs/mage --apply
"""
import argparse
import shutil
import sys
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path("/home/struktured/projects/cowardly-irregular-artist-ship")
SPRITES = GAME_REPO / "assets" / "sprites"
BACKUP_DIR = PROJECT / "tmp" / "pre_row_bleed_backups"

CELL = 32
ROWS = 4
LOOKAHEAD = 6  # how far past a cell's bottom to search for its own overflow


def row_opaque(img: Image.Image, y: int) -> int:
    px = img.load()
    return sum(1 for x in range(img.width) if px[x, y][3] > 0)


def audit(path: Path) -> list[dict]:
    """Return per-row bleed reports for a 128x128 4x4 sheet."""
    img = Image.open(path).convert("RGBA")
    if img.size != (128, 128):
        return [{"row": -1, "note": f"unexpected size {img.size}"}]
    out = []
    for r in range(ROWS):
        top = r * CELL
        bot = top + CELL
        # bleed = opaque rows at or past the cell's bottom line, before the
        # next sprite's own content resumes (a gap of >=1 empty row).
        bleed = 0
        for y in range(bot, min(128, bot + LOOKAHEAD)):
            if row_opaque(img, y) == 0:
                break
            bleed += 1
        # DISCRIMINATOR — do not skip this, it is the whole point:
        #   bounded (bleed < LOOKAHEAD)  -> content tapered to a GAP before
        #       the next sprite began. That overflow belongs to THIS row and
        #       is genuine bleed. (mage: 40->28->0)
        #   saturated (bleed == LOOKAHEAD) -> content ran continuously into
        #       the next cell, i.e. the next sprite simply fills its cell.
        #       NOT a defect. fighter/cleric/rogue/bard all read this way and
        #       are known-good in play.
        # Bulk-fixing on the raw count without this split would rewrite ~33
        # healthy sheets (the 2026-07-02 bulk-regen mistake, again).
        out.append({"row": r, "bleed": bleed,
                    "saturated": bleed >= LOOKAHEAD})
    return out


def sprite_blocks(img: Image.Image) -> list[tuple[int, int]]:
    """All contiguous opaque vertical bands in the sheet, as [start, end)."""
    blocks = []
    y = 0
    while y < img.height:
        if row_opaque(img, y) > 0:
            start = y
            while y < img.height and row_opaque(img, y) > 0:
                y += 1
            blocks.append((start, y))
        else:
            y += 1
    return blocks


def row_sprite_extent(img: Image.Image, top: int):
    """Vertical extent of the sprite BELONGING to the cell starting at `top`.

    Starts at the cell's top, skips leading empty rows, then collects the
    first CONTIGUOUS opaque block. Stopping at the gap is what keeps the
    next row's sprite out of this row's band — a fixed lookahead window
    swallows it and squashes two sprites into one cell.
    """
    y = top
    limit = min(img.height, top + CELL + LOOKAHEAD)
    while y < limit and row_opaque(img, y) == 0:
        y += 1
    if y >= limit:
        return None
    start = y
    while y < limit and row_opaque(img, y) > 0:
        y += 1
    return (start, y)  # [start, end)


def fix(path: Path, apply: bool) -> bool:
    img = Image.open(path).convert("RGBA")
    if img.size != (128, 128):
        print(f"  SKIP {path}: size {img.size}")
        return False

    reports = audit(path)
    if all(r.get("bleed", 0) == 0 for r in reports):
        return False

    # Find the sprite blocks across the WHOLE sheet, then assign one per row.
    # Per-cell scanning cannot work: a bled sprite's tail sits at the TOP of
    # the next cell with no empty row before it, so a cell-local scan reads
    # that tail as the next row's sprite.
    blocks = sprite_blocks(img)
    if len(blocks) != ROWS:
        print(f"  SKIP {path.name}: found {len(blocks)} sprite blocks, "
              f"expected {ROWS} — needs eyes, not a script")
        return False

    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    changed = []
    for r, (y0, y1) in enumerate(blocks):
        h = y1 - y0
        top = r * CELL
        content = img.crop((0, y0, img.width, y1))
        if h > CELL:
            content = content.resize((img.width, CELL), Image.NEAREST)
            new_y = top
            changed.append(f"row{r}: squash {h}->{CELL}")
        else:
            # Bottom-align inside the cell with a 1px floor margin.
            new_y = top + (CELL - h) - 1
            if new_y != y0:
                changed.append(f"row{r}: y{y0}->{new_y} (h={h}, fits)")
        out.paste(content, (0, new_y))

    if not changed:
        return False

    print(f"  {path.relative_to(SPRITES)}: " + "; ".join(changed))
    if apply:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        bak = BACKUP_DIR / (path.parent.name + "_" + path.name + ".bak")
        if not bak.exists():
            shutil.copy2(path, bak)
        out.save(path)
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("targets", nargs="*",
                    help="relative to assets/sprites, e.g. jobs/mage")
    ap.add_argument("--audit-all", action="store_true")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    if args.audit_all:
        paths = sorted(SPRITES.glob("*/*/overworld.png"))
    else:
        paths = [SPRITES / t / "overworld.png" for t in args.targets]

    hits = 0
    for p in paths:
        if not p.exists():
            print(f"  MISSING {p}")
            continue
        reports = audit(p)
        real = [r for r in reports
                if r.get("bleed", 0) > 0 and not r.get("saturated")]
        if real:
            hits += 1
            detail = ", ".join(f"row{r['row']}+{r['bleed']}px" for r in real)
            print(f"BLEED {p.relative_to(SPRITES)}: {detail}")
            if args.apply or args.targets:
                fix(p, args.apply)
    print(f"\n{hits} sheet(s) with REAL (bounded) row bleed"
          + ("" if args.apply else "  (dry run — pass --apply to fix)")
          + "\nSaturated-lookahead sheets are excluded: continuous content"
            " into the next cell is a tall sprite, not a defect.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
