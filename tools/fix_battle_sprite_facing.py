#!/usr/bin/env python3
"""Mirror generated battle sheets to the ARTIST'S facing convention.

struktured 2026-08-08, playing: "some sprites are bckwards such as industrial or steampunk
world facing wrong dir in battle (ur chars)" ... "think im in abstract and its also
backwards facing just check across board."

ROOT CAUSE, and it is in a comment someone already wrote in BattleScene:980 —

    "Procedural sprites are drawn facing right and need flip_h to face the enemy line;
     artist sheets are already authored facing LEFT and the flip rotates them BACK to
     wrong-way. Detect via the same large-frame heuristic used for scale."

    sprite.flip_h = not _is_artist_sheet      # _is_artist_sheet = frame height > 128

So the shipped convention is **battle sheets face LEFT**. My generation prompt said
"facing RIGHT toward the enemy" — inherited into every batch — and because the output is
256px it is DETECTED as an artist sheet and receives no flip. The sheets therefore render
facing right while the artist's face left. Verified by eye against the T2 sheets: fighter,
cleric, mage, rogue and bard all face left; every sheet this lane generated faces right.

⚠️ NOT a code fix. `flip_h` is correct and shared with real artist art — changing the
heuristic would flip the artist's own sheets to wrong-way, which is the exact regression
the comment above records someone already fixing. The generated art is what disagrees with
the convention, so the art is what changes.

Mirrors PER FRAME, never the whole strip: a whole-image flip also REVERSES FRAME ORDER,
turning a facing bug into an animation bug. Sheets are horizontal strips of 256px frames
(2 for generated idles, up to 7 for the artist's own).

⚠️ ONE-TIME MIGRATION, NOT IDEMPOTENT. Mirroring is its own inverse, so a second --apply
puts every sheet back to facing wrong and reports success. A stamp file records the run and
the tool refuses to repeat without --force. If sheets ever face wrong again the cause is a
NEW batch generated from a stale prompt, not this — fix the prompt and mirror only the new
files.

  python3 tools/fix_battle_sprite_facing.py --dry-run
  python3 tools/fix_battle_sprite_facing.py --apply
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageOps

HERE = Path(__file__).resolve().parent
GAME = HERE.parent
JOBS = GAME / "assets" / "sprites" / "jobs"
FRAME = 256

WORLDS = ["suburban", "steampunk", "industrial", "digital", "abstract"]
## TRACKED, not tmp/: a gitignored stamp is absent on a fresh clone, so the guard
## would pass there and double-mirror art that is already correct in git.
STAMP = HERE / "battle_facing_mirrored.stamp"

## Base idle sheets THIS LANE generated (gen_meta_job_idle.py, same "facing RIGHT" prompt).
## The other nine jobs' base sheets are artist or older-tier art and are NOT touched —
## never mirror art this lane did not author.
GENERATED_BASES = ["scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter",
                   ## ninja is an OLDER T1 base this lane did not author, added 2026-08-08.
                   ## It faces RIGHT like the generated ones, and mirroring only its world
                   ## variants left it flipping between W1 and W2-W6 — an inconsistency this
                   ## fix CREATED. T1 is AI art and mutable; the four T2 artist bases
                   ## (fighter/cleric/mage/rogue/bard) already face left and are never targeted.
                   ## guardian/summoner/speculator are frontal-symmetric: no flip needed, and
                   ## mirroring a symmetric sprite is a no-op that would still dirty the file.
                   "ninja"]


def targets() -> list:
    jobs = sorted(json.load(open(GAME / "data" / "jobs.json")).keys())
    out = []
    for job in jobs:
        for w in WORLDS:
            p = JOBS / job / f"idle_{w}.png"
            if p.exists():
                out.append(p)
    for job in GENERATED_BASES:
        p = JOBS / job / "idle.png"
        if p.exists():
            out.append(p)
    return out


def mirror_frames(path: Path) -> tuple:
    """Mirror each 256px frame in place. Returns (frames, changed)."""
    im = Image.open(path).convert("RGBA")
    if im.height != FRAME or im.width % FRAME:
        return (0, False)
    n = im.width // FRAME
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    for i in range(n):
        frame = im.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME))
        out.paste(ImageOps.mirror(frame), (i * FRAME, 0))
    out.save(path)
    return (n, True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true",
                    help="re-run despite the stamp — mirroring is its own inverse, so this "
                         "UNDOES a previous run unless you know the sheets are unmirrored")
    args = ap.parse_args()

    t = targets()
    print(f"{len(t)} generated battle sheet(s) to mirror "
          f"({len([p for p in t if p.name != 'idle.png'])} world + "
          f"{len([p for p in t if p.name == 'idle.png'])} generated base)")
    if not args.apply or args.dry_run:
        for p in t[:6]:
            print(f"  {p.relative_to(GAME)}")
        if len(t) > 6:
            print(f"  ... and {len(t)-6} more")
        print("\n(dry run — pass --apply to write)")
        return 0

    if STAMP.exists() and not args.force:
        print(f"ALREADY RUN ({STAMP.read_text().strip()}). Mirroring is its own inverse — "
              f"re-running would face every sheet the WRONG way and report success.\n"
              f"Pass --force only if you know the sheets are currently unmirrored.",
              file=sys.stderr)
        return 2

    frames = 0
    for p in t:
        n, ok = mirror_frames(p)
        if not ok:
            print(f"  SKIP {p.relative_to(GAME)} — unexpected geometry", file=sys.stderr)
            continue
        frames += n
    STAMP.parent.mkdir(parents=True, exist_ok=True)
    STAMP.write_text(f"{len(t)} sheets / {frames} frames mirrored to the LEFT-facing convention")
    print(f"mirrored {len(t)} sheets / {frames} frames")
    return 0


if __name__ == "__main__":
    sys.exit(main())
