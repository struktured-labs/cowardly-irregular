#!/usr/bin/env python3
"""Rebuild bard's non-artist battle anims from ARTIST frames only.

Live playtest bug (cowir-main msg 2355): bard's artist sprites flash to
the old AI male-swashbuckler bard during attack/hit. Root cause: only
idle/cast/attack are artist frames; walk/hit/dead/defend/item on disk
are pre-artist AI sheets and ARE loaded by HybridSpriteLoader (they're
in the manifest animations list). The gold-puppet ability sheets
(advance/defer/battle_hymn/discord/lullaby/inspiring_melody) are
unloaded today but one manifest edit away from regressing.

Fix per struktured's explicit rule ("prefer freezing on an artist
idle/attack frame over showing the old T1 art"): every non-artist bard
sheet becomes a composition of artist frames. Zero AI content anywhere
in the bard dir afterward. Deterministic, no API cost.

Composition map (artist sources: idle.png f0-3, cast.png f0-3,
attack.png f0-3 — all 256×256):
  walk   (6f): idle 0,1,2,3,2,1          — breathing stroll-in-place
  hit    (4f): idle 0 ×4                  — artist freeze (engine adds shake)
  dead   (4f): idle 0 ×4                  — freeze; proper artist dead pose
                                            is an artist ask, noted
  defend (4f): idle 0 ×4                  — brace freeze
  item   (4f): cast 0,1,2,3               — reach gesture reads item-use
  advance(4f): attack 0,1,2,3             — matches the engine fallback
  defer  (4f): idle 0 ×4
  battle_hymn / discord / lullaby / inspiring_melody (6f):
              cast 0,1,2,3,2,1            — song = sustained cast loop

Backups: <anim>.pre_artist_compose.png moved to game-repo tmp/ (gitignored).

Usage:
    uv run python tools/compose_bard_artist_anims.py [--dry-run]
"""
import argparse
import os
import shutil
import sys
from pathlib import Path

from PIL import Image

GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
BARD = GAME_REPO / "assets" / "sprites" / "jobs" / "bard"
BACKUP_DIR = GAME_REPO / "tmp" / "bard_pre_artist_compose"

FRAME = 256

# anim → (source anim, frame indices)
COMPOSITION = {
    "walk":              ("idle",   [0, 1, 2, 3, 2, 1]),
    "hit":               ("idle",   [0, 0, 0, 0]),
    "dead":              ("idle",   [0, 0, 0, 0]),
    "defend":            ("idle",   [0, 0, 0, 0]),
    "item":              ("cast",   [0, 1, 2, 3]),
    "advance":           ("attack", [0, 1, 2, 3]),
    "defer":             ("idle",   [0, 0, 0, 0]),
    "battle_hymn":       ("cast",   [0, 1, 2, 3, 2, 1]),
    "discord":           ("cast",   [0, 1, 2, 3, 2, 1]),
    "lullaby":           ("cast",   [0, 1, 2, 3, 2, 1]),
    "inspiring_melody":  ("cast",   [0, 1, 2, 3, 2, 1]),
}


def load_frames(anim: str) -> list[Image.Image]:
    img = Image.open(BARD / f"{anim}.png").convert("RGBA")
    n = img.width // FRAME
    return [img.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(n)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    sources = {a: load_frames(a) for a in ("idle", "cast", "attack")}
    for a, frames in sources.items():
        if len(frames) < 4:
            print(f"ERROR: artist source {a}.png has {len(frames)} frames, need 4")
            return 1

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    for anim, (src, idxs) in COMPOSITION.items():
        target = BARD / f"{anim}.png"
        if args.dry_run:
            print(f"would rebuild {anim}.png: {src} frames {idxs}")
            continue
        if target.exists():
            backup = BACKUP_DIR / f"{anim}.png"
            if not backup.exists():
                shutil.copy2(target, backup)
        strip = Image.new("RGBA", (FRAME * len(idxs), FRAME), (0, 0, 0, 0))
        for col, fi in enumerate(idxs):
            strip.paste(sources[src][fi], (col * FRAME, 0))
        strip.save(target)
        print(f"rebuilt {anim}.png ← {src}{idxs} ({len(idxs)}f)")
    if not args.dry_run:
        print(f"\nbackups: {BACKUP_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
