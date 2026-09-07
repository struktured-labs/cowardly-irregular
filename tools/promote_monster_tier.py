#!/usr/bin/env python3
"""Promote monster manifest entries from T1 to T2 after artist-style regen.

Reads the cost log from tools/regen_monster_artist_style.py to identify
which monsters were successfully regen'd, then updates each entry in
data/sprite_manifest.json:

  tier: T1 → T2
  generator: <old> → source: "gpt-image-1 anchored to artist <ref> ref"

Preserves anim ranges, frame_width/height, fps, path. Only touches the
`tier` field and swaps `generator` for `source`.

Usage:
    uv run python tools/promote_monster_tier.py             # all successful regens
    uv run python tools/promote_monster_tier.py --monsters cave_rat wolf
    uv run python tools/promote_monster_tier.py --dry-run
"""
import argparse
import json
import os
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
sys.path.insert(0, str(PROJECT))
from tools.pipeline.reference_library import refs_for

MANIFEST = GAME_REPO / "data" / "sprite_manifest.json"
COST_LOG = PROJECT / "tmp" / "monster_artist_regen" / "_cost.json"


def successful_from_cost_log() -> set[str]:
    if not COST_LOG.exists():
        return set()
    log = json.loads(COST_LOG.read_text())
    ok = set()
    for s in log.get("sessions", []):
        for r in s.get("results", []):
            if r.get("status") == "ok":
                ok.add(r["monster"])
    return ok


def promote(entry: dict, monster_id: str) -> tuple[bool, str]:
    if entry.get("tier") == "T2":
        return False, "already T2"
    entry["tier"] = "T2"
    entry.pop("generator", None)
    refs = refs_for(monster_id)
    ref_name = refs[0].stem.split()[0].lower() if refs else "artist"
    entry["source"] = (
        f"gpt-image-1 4-pose contact-sheet anchored to artist {ref_name} reference "
        f"(tools/regen_monster_artist_style.py)"
    )
    return True, "T1→T2"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--monsters", nargs="*",
                        help="explicit ids; default = all successful from cost log")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    mss = manifest.get("monster_sheets", {})

    if args.monsters:
        targets = args.monsters
    else:
        targets = sorted(successful_from_cost_log())

    if not targets:
        print("No monsters to promote (empty cost log and no --monsters)")
        return 1

    n_promoted = n_skipped = 0
    for mid in targets:
        entry = mss.get(mid)
        if not entry:
            print(f"  SKIP {mid}: not in manifest monster_sheets")
            n_skipped += 1
            continue
        promoted, note = promote(entry, mid)
        if promoted:
            print(f"  {'DRY ' if args.dry_run else ''}PROMOTE {mid}: {note}")
            n_promoted += 1
        else:
            print(f"  SKIP {mid}: {note}")
            n_skipped += 1

    print(f"\n{'Would promote' if args.dry_run else 'Promoted'}: {n_promoted}, skipped {n_skipped}")

    if n_promoted > 0 and not args.dry_run:
        MANIFEST.write_text(json.dumps(manifest, indent=2))
        print(f"Wrote {MANIFEST}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
