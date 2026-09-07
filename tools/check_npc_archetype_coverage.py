#!/usr/bin/env python3
"""Walk every assets/sprites/npcs/<archetype>/overworld.png and check each
direction row (0=down, 1=left, 2=right, 3=up) at each frame for being mostly
transparent. Mostly-transparent frames in an archetype sheet cause the
WanderingNPC to silently render as invisible when facing that direction
(WanderingNPC._update_archetype_frame is a no-op when the sprite frame's
texture has no opaque pixels — the prior frame's texture just sticks).
Run: python3 tools/check_npc_archetype_coverage.py
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Install Pillow: pip install Pillow", file=sys.stderr)
    sys.exit(2)

NPCS_DIR = Path(__file__).resolve().parent.parent / "assets" / "sprites" / "npcs"
FRAME = 32
ROWS = ["down", "left", "right", "up"]
COLS = 4
OPACITY_THRESHOLD = 0.05  # 5% non-transparent pixels = "has content"


def check_sheet(path: Path) -> dict:
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    if w < FRAME * COLS or h < FRAME * len(ROWS):
        return {"error": f"sheet too small ({w}x{h}); expected at least {FRAME*COLS}x{FRAME*len(ROWS)}"}
    findings: dict = {"empty_frames": [], "empty_rows": []}
    for row_idx, row_name in enumerate(ROWS):
        row_empty = True
        for col in range(COLS):
            box = (col * FRAME, row_idx * FRAME, (col + 1) * FRAME, (row_idx + 1) * FRAME)
            frame = img.crop(box)
            alpha = frame.split()[-1]
            non_zero = sum(1 for px in alpha.getdata() if px > 0)
            ratio = non_zero / (FRAME * FRAME)
            if ratio < OPACITY_THRESHOLD:
                findings["empty_frames"].append(f"row {row_idx} ({row_name}) frame {col}: {ratio*100:.1f}% opaque")
            else:
                row_empty = False
        if row_empty:
            findings["empty_rows"].append(row_name)
    return findings


def main() -> int:
    if not NPCS_DIR.exists():
        print(f"NPCs dir not found: {NPCS_DIR}", file=sys.stderr)
        return 2
    rows = []
    for archetype_dir in sorted(NPCS_DIR.iterdir()):
        sheet = archetype_dir / "overworld.png"
        if not sheet.is_file():
            continue
        result = check_sheet(sheet)
        if "error" in result:
            rows.append((archetype_dir.name, "ERROR", result["error"]))
        elif result["empty_rows"]:
            rows.append((archetype_dir.name, "EMPTY_ROW", ",".join(result["empty_rows"])))
        elif result["empty_frames"]:
            rows.append((archetype_dir.name, "EMPTY_FRAMES", "; ".join(result["empty_frames"])))
        else:
            rows.append((archetype_dir.name, "OK", "all 4 directions populated"))
    width = max(len(r[0]) for r in rows) if rows else 12
    for arch, status, detail in rows:
        print(f"  {arch:<{width}}  {status:<13}  {detail}")
    bad = [r for r in rows if r[1] != "OK"]
    if bad:
        print(f"\n{len(bad)} sheet(s) with coverage gaps. Disappearing-NPC bug is real here.")
        return 1
    print("\nAll NPC archetype sheets have all 4 direction rows populated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
