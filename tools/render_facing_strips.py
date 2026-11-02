#!/usr/bin/env python3
"""Render each party walk sheet as a 4-direction review strip, for a human to check its facing.

struktured 2026-11-01: "blackmage walks backwards on the village if u select him as leader ... from left/right";
then "we need to stop that from happening". A sheet's facing cannot be measured (a silhouette compared against
the last reviewed sheet misjudged all six sheets tried), so a person looks: DOWN shows the face, UP the back of the
head, LEFT and RIGHT in profile toward the way they walk. The strips land in docs/art/facing/ (Godot-ignored,
so they never ship), and data/overworld_facing_review.json pins the sheet hash each review covered.

Usage:
    python3 tools/render_facing_strips.py                                   # every walk sheet
    python3 tools/render_facing_strips.py overworld_player_sheets/mage      # one sheet
    python3 tools/render_facing_strips.py --pin --note "who, what" overworld_player_sheets/mage   # after LOOKING
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
SCALE = 2
DIRS = ["DOWN", "LEFT", "RIGHT", "UP"]
## Every overworld walk sheet: the party, the villagers who walk around everywhere, and the roaming monsters.
SECTIONS = ("overworld_player_sheets", "overworld_npc_sheets", "overworld_monster_sheets")
## HybridSpriteLoader.overworld_walk_rows' default; a sheet declaring all four rows overrides it.
CONVENTION = {"walk_down": 0, "walk_left": 1, "walk_right": 2, "walk_up": 3}


def sheets() -> dict:
    """{"<section>/<id>": entry} for every walk sheet in every overworld section."""
    man = json.loads((ROOT / "data/sprite_manifest.json").read_text(encoding="utf-8"))
    return {f"{sec}/{k}": v for sec in SECTIONS for k, v in man[sec].items() if isinstance(v, dict)}


def walk_rows(entry: dict) -> list:
    """Row index per DIRS entry, as the loader resolves it."""
    a = entry.get("animations")
    if isinstance(a, dict) and all(isinstance(a.get(k), dict) and "row" in a[k] for k in CONVENTION):
        return [int(a[k]["row"]) for k in CONVENTION]
    return list(CONVENTION.values())


def strip(job: str, entry: dict) -> Path:
    f = int(entry.get("frame_height", 48))
    w = int(entry.get("frame_width", f))
    im = Image.open(ROOT / entry["path"].replace("res://", "")).convert("RGBA")
    out = Image.new("RGBA", (4 * (w * SCALE + 8) + 8, f * SCALE + 26), (54, 54, 64, 255))
    d = ImageDraw.Draw(out)
    for i, (name, r) in enumerate(zip(DIRS, walk_rows(entry))):
        cell = im.crop((0, r * f, w, (r + 1) * f)).resize((w * SCALE, f * SCALE), Image.NEAREST)
        out.alpha_composite(cell, (8 + i * (w * SCALE + 8), 20))
        d.text((8 + i * (w * SCALE + 8), 4), f"{job.split('/')[-1]} {name} (row {r})", fill=(255, 225, 120))
    dst = OUT / f"{job}.png"
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst)
    return dst


def pin(job: str, entry: dict, note: str) -> None:
    doc = json.loads(REVIEW.read_text(encoding="utf-8"))
    sha = hashlib.sha256((ROOT / entry["path"].replace("res://", "")).read_bytes()).hexdigest()
    doc["sheets"][job] = {"sheet_sha256": sha, "strip": f"res://docs/art/facing/{job}.png", "reviewed": note}
    doc["sheets"] = dict(sorted(doc["sheets"].items()))
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
            raise SystemExit(f"{j} is not a walk sheet (name it <section>/<id>, e.g. overworld_player_sheets/mage)")
        if args.pin:
            if not args.note:
                raise SystemExit("--pin needs --note: who looked at the strip and what they checked")
            pin(j, all_sheets[j], args.note)
        else:
            print(f"rendered {strip(j, all_sheets[j]).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
