#!/usr/bin/env python3
"""
Full sprite generation sweep — all jobs + all monsters using v3 LoRA.
Uses artist references where available, text-only for the rest.
"""
import argparse
import subprocess
import sys
import json
import os
from pathlib import Path
from datetime import datetime

PROJECT = Path(__file__).parent.parent
OUTPUT_BASE = PROJECT / "tmp" / "full_sweep_v2_lora"
GAME_REPO = Path("/home/struktured/projects/cowardly-irregular")

# Artist reference images (where available)
ARTIST_REFS = {
    "fighter": str(PROJECT / "assets/sprites/jobs/fighter/idle.png"),
    "rogue": str(PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/ROGUE/Rogue Base sprite.png"),
    "mage": str(PROJECT / "assets/sprites/jobs/mage_artist/idle.png"),
    "cleric": str(PROJECT / "assets/sprites/drive_archive/Game graphics - Characters/CLERIC/Cleric Main design-Sheet.png"),
    "bard": "",  # no artist ref yet — text-only
}

# SACRED: never overwrite artist files during a sweep.
#
# This was a HARDCODED list of fighter + rogue, and it was correct the day it
# was written — 68b049d0 says so explicitly: "Other jobs (cleric/mage/bard/...)
# — no prior artist sprites to protect." Then cleric and mage artist art
# arrived (4cab90d0, c3d1b732) and nobody came back to the list.
#
# By 2026-07-29 it was silently wrong: 7 artist animations (cleric idle/
# attack/cast/walk, mage idle/attack/cast) were absent from it, so an
# --install would have overwritten them with LoRA output, underneath a
# comment saying SACRED.
#
# Same rot as the tier fields fixed the same night, one layer down: that was
# provenance METADATA going stale, this is the ENFORCEMENT copy of it. And
# it is cowir-sfx's incident-vs-property shape — the list recorded which jobs
# were artist-made at one moment, when the invariant is "whatever is
# artist-made right now must survive the sweep."
#
# So: derived from git, never enumerated. A new artist drop protects itself
# the moment it lands, with nobody remembering to edit this file.
# The legacy hand-written list is KEPT as a floor, never replaced. It is
# stale (it predates the cleric/mage drops) but it is not wrong — someone
# who knew wrote it down, and that is evidence the derivation does not have.
#
# Keeping it caught a live regression: the derivation DROPS rogue/cast,
# because that file's commit subject is "rogue + cleric clashing ML-gen
# anims -> artist idle placeholders". The classifier sees "ML-gen" and reads
# machine; the arrow means the file is the artist art that REPLACED the
# ML-gen. Swapping the list for the derivation would have un-protected a
# file the old list defended — a derivation is not automatically safer than
# an enumeration, it just fails differently.
#
# So: union, and protection can only ever GROW.
_LEGACY_PROTECTED = {
    "fighter": ["idle", "walk", "attack", "hit", "dead", "cast", "defend", "item", "victory",
                "advance", "defer", "cleave", "power_strike", "provoke", "slash"],
    "rogue": ["idle", "attack", "cast"],
}


def _protected_anims(job_id: str) -> list:
    """Animation names in this job that must survive a sweep.

    Union of what git can prove and what the legacy list asserts. Union
    rather than replacement because the two have different blind spots and
    the cost of missing one is destroying artist work.
    """
    try:
        sys.path.insert(0, str(PROJECT))
        from tools.audit_sprite_tiers import artist_evidence
    except ImportError as exc:
        # Fail CLOSED. Unable to determine provenance means unable to
        # promise we won't destroy it.
        raise SystemExit(
            f"cannot import artist_evidence ({exc}) — refusing to sweep, "
            f"because without it every artist animation is unprotected."
        )
    rel = f"assets/sprites/jobs/{job_id}"
    derived = {line.split(".png")[0] for line in artist_evidence(rel)}
    return sorted(derived | set(_LEGACY_PROTECTED.get(job_id, [])))

# Jobs with extended animations
EXTENDED_JOBS = ["rogue"]

# Monster generation uses a different script path
MONSTER_GEN_CMD = [
    sys.executable, str(PROJECT / "tools" / "gen_sprite_sdxl.py"),
]

JOB_GEN_CMD = [
    sys.executable, str(PROJECT / "tools" / "gen_sprite_sdxl.py"),
]


def gen_job(job, output_dir):
    """Generate all animations for a job."""
    cmd = list(JOB_GEN_CMD) + [
        "--job", job,
        "--all-animations",
        "--lora-mode", "style",
        "--no-controlnet",
        "--ipadapter-scale", "0.55",
        "--direct-downscale",
        "--output", str(output_dir / job),
        "--seed", "42",
    ]

    if job in EXTENDED_JOBS:
        cmd.append("--extended")

    if job in ARTIST_REFS and os.path.exists(ARTIST_REFS[job]):
        cmd.extend(["--reference-image", ARTIST_REFS[job]])

    print(f"\n{'='*60}")
    print(f"  JOB: {job.upper()}")
    print(f"  Ref: {ARTIST_REFS.get(job, 'none (text-only)')}")
    print(f"  Extended: {job in EXTENDED_JOBS}")
    print(f"{'='*60}")

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)

    # Count saved animations
    saved = [l for l in result.stdout.split('\n') if 'Saved:' in l]
    for s in saved:
        print(f"  {s.strip()}")

    if result.returncode != 0:
        print(f"  ERROR: {result.stderr[-300:]}")
        return False
    return True


def gen_monster(monster_id, output_dir):
    """Generate a monster sprite (idle animation only, 8 frames)."""
    # Monsters use the same pipeline but with monster prompts
    # We generate via text-only (no artist ref for monsters)
    cmd = list(MONSTER_GEN_CMD) + [
        "--job", monster_id,
        "--animation", "idle",
        "--lora-mode", "style",
        "--no-controlnet",  # no pose skeletons for monsters
        "--no-ipadapter",   # no reference images for monsters
        "--output", str(output_dir / "monsters" / monster_id),
        "--seed", "42",
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    saved = [l for l in result.stdout.split('\n') if 'Saved:' in l]
    if saved:
        print(f"  {monster_id}: {saved[0].strip()}")
    elif result.returncode != 0:
        # Monster IDs may not be in JOB_PROMPTS — that's expected
        # The pipeline will use the job ID as-is in the prompt
        err = result.stderr[-200:] if result.stderr else "unknown"
        print(f"  {monster_id}: SKIP ({err[-80:]})")
        return False
    return True


STANDARD_ANIMATIONS = ["idle", "walk", "attack", "hit", "dead", "cast", "defend", "item", "victory"]
FRAME_COUNTS = {
    "idle": 2, "walk": 6, "attack": 6, "hit": 4, "dead": 4,
    "cast": 4, "defend": 4, "item": 4, "victory": 4,
    "advance": 4, "defer": 4, "steal": 6, "backstab": 6, "mug": 6, "flee": 4,
}


def install_to_game(output_dir):
    """Copy generated sprites to game repo, respecting protected artist files."""
    import shutil

    game_sprites = GAME_REPO / "assets" / "sprites" / "jobs"
    manifest_path = GAME_REPO / "data" / "sprite_manifest.json"

    # Load existing manifest
    with open(manifest_path) as f:
        manifest = json.load(f)

    installed = 0
    skipped_protected = 0

    for job_dir in sorted(output_dir.iterdir()):
        if not job_dir.is_dir() or job_dir.name in ("monsters",):
            continue

        job_id = job_dir.name
        protected = _protected_anims(job_id)

        # Destination: use job_id directly (e.g. assets/sprites/jobs/cleric/)
        dest_dir = game_sprites / job_id
        dest_dir.mkdir(parents=True, exist_ok=True)

        anim_list = []
        for png in sorted(job_dir.glob("*.png")):
            anim_name = png.stem
            # Skip non-animation files
            if anim_name in ("hero_reference", "generation_meta"):
                continue
            # Skip variation suffixes
            if "_v" in anim_name:
                continue

            if anim_name in protected:
                print(f"  PROTECTED {job_id}/{anim_name}.png (artist file, skipping)")
                skipped_protected += 1
                # Still include in manifest (artist file is already there)
                anim_list.append(anim_name)
                continue

            dest_file = dest_dir / png.name
            shutil.copy2(png, dest_file)
            anim_list.append(anim_name)
            installed += 1

        # Update manifest — ensure all animations are listed
        if anim_list:
            manifest.setdefault("sheets", {})[job_id] = {
                "path": f"res://assets/sprites/jobs/{job_id}",
                "frame_width": 256,
                "frame_height": 256,
                "fps": 8,
                "animations": anim_list,
                "tier": "T1",
                "generator": "gen_full_sweep.py (v2 jrpg_pixel_style LoRA)",
            }
            print(f"  INSTALLED {job_id}: {len(anim_list)} animations ({len(protected)} protected)")

    # Write updated manifest
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"\n  Total installed: {installed} files")
    print(f"  Protected (skipped): {skipped_protected} files")
    print(f"  Manifest updated: {manifest_path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs-only", action="store_true", help="Only generate jobs, skip monsters")
    parser.add_argument("--monsters-only", action="store_true", help="Only generate monsters, skip jobs")
    parser.add_argument("--job", help="Generate a single job")
    parser.add_argument("--resume", action="store_true", help="Skip already-generated outputs")
    parser.add_argument("--install", action="store_true", help="Copy results to game repo (after generation)")
    args = parser.parse_args()

    output_dir = OUTPUT_BASE
    output_dir.mkdir(parents=True, exist_ok=True)

    start = datetime.now()
    results = {"jobs": {}, "monsters": {}, "start": str(start)}

    if not args.monsters_only:
        jobs = [args.job] if args.job else [
            "fighter", "cleric", "mage", "rogue", "bard",
            "guardian", "ninja", "summoner", "speculator",
        ]

        print(f"\n{'#'*60}")
        print(f"  GENERATING {len(jobs)} JOBS")
        print(f"{'#'*60}")

        for job in jobs:
            job_dir = output_dir / job
            if args.resume and job_dir.exists() and list(job_dir.glob("*.png")):
                print(f"  {job}: SKIP (already exists)")
                results["jobs"][job] = "skipped"
                continue
            ok = gen_job(job, output_dir)
            results["jobs"][job] = "ok" if ok else "error"

    if not args.jobs_only:
        # Import monster list
        sys.path.insert(0, str(PROJECT))
        from tools.pipeline.prompts import MONSTER_PROMPTS

        monsters = list(MONSTER_PROMPTS.keys())

        print(f"\n{'#'*60}")
        print(f"  GENERATING {len(monsters)} MONSTERS")
        print(f"{'#'*60}")

        for m in monsters:
            monster_file = output_dir / "monsters" / m / "idle.png"
            if args.resume and monster_file.exists():
                print(f"  {m}: SKIP")
                results["monsters"][m] = "skipped"
                continue
            ok = gen_monster(m, output_dir)
            results["monsters"][m] = "ok" if ok else "error"

    elapsed = datetime.now() - start
    results["elapsed"] = str(elapsed)
    results["end"] = str(datetime.now())

    meta_path = output_dir / "sweep_results.json"
    with open(meta_path, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\n{'='*60}")
    print(f"  SWEEP COMPLETE")
    print(f"  Jobs: {sum(1 for v in results['jobs'].values() if v == 'ok')}/{len(results['jobs'])}")
    print(f"  Monsters: {sum(1 for v in results['monsters'].values() if v == 'ok')}/{len(results['monsters'])}")
    print(f"  Time: {elapsed}")
    print(f"  Output: {output_dir}")
    print(f"{'='*60}")

    if args.install:
        print(f"\n{'#'*60}")
        print(f"  INSTALLING TO GAME REPO")
        print(f"{'#'*60}")
        install_to_game(output_dir)


if __name__ == "__main__":
    main()
