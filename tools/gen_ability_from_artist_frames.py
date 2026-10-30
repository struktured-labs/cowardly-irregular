#!/usr/bin/env python3
"""Compose an ability animation from a job's OWN artist frames, by integer translation only.

WHY THIS SHAPE
--------------
13 starter "ability animations" are byte-identical copies of another animation (SHA256, so
copied rather than drawn): the rogue's backstab/flee/mug/steal ARE his walk.png, the cleric's
heal/buff/raise ARE her advance.png, the bard's four songs share one strip. A backstab that
plays a walk cycle is the defect; authored rhythm cannot fix it, because the motion is wrong.

Two generators were available and this picks neither blindly:
  gpt-image    failed 3/3 on bodies in motion (artist-drop-sync skill) and cannot hold frame
               coherence across a 256px battle strip -- the exact thing a battle anim needs.
  procedural   gen_fighter_all_animations.py composites pixel BANDS with rotation, 880 lines
               of per-job hardcoded row ranges. Correct, and not generalisable in one pass.

So: whole-frame INTEGER TRANSLATION of the job's own artist frames onto a new timeline. No
resampling, no rotation, no palette touch -- every opaque pixel in the output is a pixel the
artist drew, moved by a whole number. That is the strongest available reading of struktured's
"use the human artist's sprites as style references, never overwrite the artist's sprites".

⛔ WHAT THIS IS NOT: a new drawing. It is the artist's own poses on a different path and
timeline. It beats a walk cycle playing for a backstab and it is NOT final art -- every output
is T1 and flagged for an artist pass.

TWO REFUSALS, both before any write:
  1. tools.artist_guard.assert_writable  -- the fleet's guard, fail-closed
  2. _refuse_unless_placeholder          -- this file's own: refuse unless the target's CURRENT
     bytes are duplicated elsewhere in the same job dir. A byte-copy can be overwritten without
     losing a unique pixel, because the original still holds them; a UNIQUE sheet cannot.
     The guard answers "is this artist work"; this answers "is this the only copy of it".
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from tools.artist_guard import assert_writable  # noqa: E402

CELL = 256

# job -> anim -> [(source_anim, source_frame, dx, dy), ...]; one tuple per OUTPUT frame.
# Offsets are whole pixels. Designed against what each source strip actually shows.
RECIPES = {
    "rogue": {
        # attack f0-f3 is a real dagger slash. A backstab approaches LOW and lunges IN:
        # crouch, coil, drive forward on the slash frame, hold the hit, withdraw.
        "backstab": [("idle", 0, 0, 6), ("attack", 0, -10, 8), ("attack", 1, 16, 6),
                     ("attack", 2, 22, 4), ("attack", 3, 8, 2), ("idle", 0, 0, 4)],
        # mug: strike first, then snatch -- the slash, then the open hand held out.
        "mug": [("attack", 0, -6, 2), ("attack", 1, 10, 0), ("attack", 3, 14, 0),
                ("attack", 3, 6, -2), ("idle", 0, 0, 0)],
        # steal: no strike at all. Furtive reach from a crouch and straight back out.
        "steal": [("idle", 0, 0, 5), ("attack", 3, 12, 7), ("attack", 3, 18, 8),
                  ("idle", 0, 4, 5), ("idle", 0, 0, 0)],
        # flee: he leaves. Walk cycle carried progressively AWAY from the enemy side.
        "flee": [("walk", 0, 0, 0), ("walk", 1, -14, -2), ("walk", 2, -30, -3),
                 ("walk", 3, -48, -4), ("walk", 0, -68, -5)],
    },
    "cleric": {
        # cast f0-f2 build a blue orb, f4 is a WHITE BURST, f5-f8 a dissipating ring.
        # Three spells, three different beats of her own cast.
        "heal": [("cast", 5, 0, -4), ("cast", 6, 0, -2), ("cast", 7, 0, 0),
                 ("cast", 8, 0, 2), ("advance", 0, 0, 2), ("advance", 1, 0, 0)],
        "buff": [("cast", 0, 0, 2), ("cast", 1, 0, 0), ("cast", 2, 0, -2),
                 ("cast", 3, 0, -5), ("cast", 3, 0, -3), ("advance", 0, 0, 0)],
        "raise": [("cast", 3, 0, 2), ("cast", 4, 0, -6), ("cast", 4, 0, -8),
                  ("cast", 5, 0, -4), ("cast", 6, 0, -1), ("cast", 8, 0, 0)],
    },
    "bard": {
        # the four songs share ONE genuine performance strip (f3 = the sweep). discord borrows
        # her attack's jagged arcs; the others differ by the path the same performance takes.
        # ⛔ lullaby / battle_hymn / inspiring_melody are DELIBERATELY ABSENT. She has only two
        # distinct performance poses (cast, and the shared song strip) and they read alike, so
        # offsets cannot tell three songs apart -- rendered and judged by eye, not assumed.
        # Composing them anyway would replace artist bytes with near-identical composites AND
        # destroy the SHA256 duplicate signal that marks them as needing real art. They stay
        # byte-identical on purpose, as a standing artist ask. discord works because it borrows
        # her attack's arcs, which is art the other three have no equivalent of.
        # SIX frames, not five: bard/attack carries f0-f4, and the rhythm authored for discord
        # on the sibling branch is [60,55,60,105,180,290] -- three jagged beats, a fourth that
        # lands, then the two held song frames. A 5-frame sheet silently discards that rhythm
        # (HybridSpriteLoader only honours frame_durations_ms when size == frame_count).
        "discord": [("attack", 0, 0, 0), ("attack", 1, 6, -2), ("attack", 2, -4, 2),
                    ("attack", 3, 10, -1), ("lullaby", 4, 0, 0), ("lullaby", 5, 0, 0)],
        # battle_hymn and inspiring_melody move to her CAST strip so the four songs do not all
        # ride one set of frames -- offsets alone left three of them reading alike.
    },
}


def _strip(job: str, anim: str) -> list:
    p = ROOT / "assets" / "sprites" / "jobs" / job / f"{anim}.png"
    if not p.exists():
        raise SystemExit(f"[compose] missing source {p}")
    im = Image.open(p).convert("RGBA")
    return [im.crop((i * CELL, 0, (i + 1) * CELL, CELL)) for i in range(im.width // CELL)]


def _sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def _refuse_unless_placeholder(target: Path) -> str:
    """Refuse unless target's bytes are duplicated by another sheet in the same job dir."""
    if not target.exists():
        return "new file"
    mine = _sha(target)
    twins = sorted(q.stem for q in target.parent.glob("*.png")
                   if q != target and _sha(q) == mine)
    if not twins:
        raise SystemExit(
            f"[compose] REFUSING {target}: its bytes are UNIQUE in {target.parent.name}/ -- "
            "overwriting would destroy the only copy of those pixels. Only byte-duplicated "
            "placeholders may be replaced.")
    return "placeholder, byte-identical to: " + ", ".join(twins)


def compose(job: str, anim: str) -> Image.Image:
    recipe = RECIPES.get(job, {}).get(anim)
    if not recipe:
        raise SystemExit(f"[compose] no recipe for {job}/{anim}")
    cache = {}
    out = Image.new("RGBA", (CELL * len(recipe), CELL), (0, 0, 0, 0))
    for i, (src, idx, dx, dy) in enumerate(recipe):
        if src not in cache:
            cache[src] = _strip(job, src)
        frames = cache[src]
        if idx >= len(frames):
            raise SystemExit(f"[compose] {job}/{src} has {len(frames)} frames, recipe wants {idx}")
        layer = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        layer.paste(frames[idx], (int(dx), int(dy)))  # integer translate, no resample
        out.paste(layer, (i * CELL, 0))
    return out


def _assert_artist_pixels_only(built: Image.Image, job: str, anim: str) -> None:
    """Every opaque colour in the output must occur in the sources it was composed from."""
    src_colours = set()
    for src, _idx, _dx, _dy in RECIPES[job][anim]:
        for f in _strip(job, src):
            src_colours |= {p[:3] for p in f.getdata() if p[3] > 0}
    out_colours = {p[:3] for p in built.getdata() if p[3] > 0}
    stray = out_colours - src_colours
    if stray:
        raise SystemExit(f"[compose] {job}/{anim}: {len(stray)} colour(s) not in the artist sources")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", required=True)
    ap.add_argument("--anim", required=True)
    ap.add_argument("--write", action="store_true", help="write the sheet (default: preview only)")
    ap.add_argument("--preview", default="", help="write a scaled contact sheet here")
    a = ap.parse_args()

    target = ROOT / "assets" / "sprites" / "jobs" / a.job / f"{a.anim}.png"
    built = compose(a.job, a.anim)
    _assert_artist_pixels_only(built, a.job, a.anim)
    n = built.width // CELL
    print(f"[compose] {a.job}/{a.anim}: {n} frames, palette verified against artist sources")

    if a.preview:
        S = 150
        old = Image.open(target).convert("RGBA") if target.exists() else None
        rows = 2 if old else 1
        sheet = Image.new("RGBA", (max(n, (old.width // CELL) if old else 0) * S, rows * S), (70, 74, 92, 255))
        if old:
            for i in range(old.width // CELL):
                sheet.alpha_composite(old.crop((i * CELL, 0, (i + 1) * CELL, CELL)).resize((S, S), Image.NEAREST), (i * S, 0))
        for i in range(n):
            sheet.alpha_composite(built.crop((i * CELL, 0, (i + 1) * CELL, CELL)).resize((S, S), Image.NEAREST), (i * S, (rows - 1) * S))
        Path(a.preview).parent.mkdir(parents=True, exist_ok=True)
        sheet.save(a.preview)
        print(f"[compose] preview -> {a.preview} (top row = what ships today)")

    if not a.write:
        print("[compose] preview only; pass --write to replace the placeholder")
        return 0

    why = _refuse_unless_placeholder(target)          # refusal 2: only a duplicate may go
    assert_writable(target)                            # refusal 1: the fleet's artist guard
    print(f"[compose] target is a {why}")
    built.save(target)
    print(f"[compose] wrote {target.relative_to(ROOT)} ({n} frames)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
