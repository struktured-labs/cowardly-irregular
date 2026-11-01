#!/usr/bin/env python3
"""Render each party walk sheet as a 4-direction review strip, for a human to check its facing.

struktured 2026-11-01: "blackmage walks backwards on the village if u select him as leader ... from left/right";
then "we need to stop that from happening". A sheet's facing cannot be measured (a silhouette compared against
the last reviewed sheet misjudged all six sheets tried), so a person looks: DOWN shows the face, UP the back of the
head, LEFT and RIGHT in profile toward the way they walk. The strips land in docs/art/facing/ (Godot-ignored,
so they never ship), and data/overworld_facing_review.json pins the sheet hash each review covered.

Usage:
    python3 tools/render_facing_strips.py              # all overworld_player_sheets
    python3 tools/render_facing_strips.py mage         # one sheet
    python3 tools/render_facing_strips.py --pin mage   # after LOOKING: record the sheet's new hash
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/art/facing"
REVIEW = ROOT / "data/overworld_facing_review.json"
SCALE = 3
DIRS = ["DOWN", "LEFT", "RIGHT", "UP"]  # HybridSpriteLoader.overworld_walk_rows' default convention


def sheets() -> dict:
    man = json.loads((ROOT / "data/sprite_manifest.json").read_text(encoding="utf-8"))
    return {k: v for k, v in man["overworld_player_sheets"].items() if isinstance(v, dict)}


def strip(job: str, entry: dict) -> Path:
    f = int(entry.get("frame_height", 48))
    im = Image.open(ROOT / entry["path"].replace("res://", "")).convert("RGBA")
    out = Image.new("RGBA", (4 * (f * SCALE + 8) + 8, f * SCALE + 26), (54, 54, 64, 255))
    d = ImageDraw.Draw(out)
    for r, name in enumerate(DIRS):
        cell = im.crop((0, r * f, f, (r + 1) * f)).resize((f * SCALE, f * SCALE), Image.NEAREST)
        out.alpha_composite(cell, (8 + r * (f * SCALE + 8), 20))
        d.text((8 + r * (f * SCALE + 8), 4), f"{job} {name} (row {r})", fill=(255, 225, 120))
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / f"{job}.png"
    out.save(dst)
    return dst


def pin(job: str, entry: dict, note: str) -> None:
    doc = json.loads(REVIEW.read_text(encoding="utf-8"))
    sha = hashlib.sha256((ROOT / entry["path"].replace("res://", "")).read_bytes()).hexdigest()
    doc["sheets"][job] = {"sheet_sha256": sha, "strip": f"res://docs/art/facing/{job}.png", "reviewed": note}
    REVIEW.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"pinned {job} at {sha[:12]}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("jobs", nargs="*")
    ap.add_argument("--pin", action="store_true", help="record the sheets' current hashes (only after looking)")
    ap.add_argument("--note", default="", help="who looked and what they checked (required with --pin)")
    args = ap.parse_args()
    all_sheets = sheets()
    for j in args.jobs or sorted(all_sheets):
        if j not in all_sheets:
            raise SystemExit(f"{j} is not in overworld_player_sheets")
        if args.pin:
            if not args.note:
                raise SystemExit("--pin needs --note: who looked at the strip and what they checked")
            pin(j, all_sheets[j], args.note)
        else:
            print(f"rendered {strip(j, all_sheets[j]).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
