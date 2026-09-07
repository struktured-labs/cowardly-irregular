#!/usr/bin/env python3
"""Export a tagged artist .aseprite monster/boss into a game-ready sheet.

ARTIST-CANON TOOL. Every frame it writes comes from the artist's file.
It NEVER generates, substitutes, or repaints pixels — the only permitted
transform is integer nearest-neighbour upscale (pixel-exact, reversible).

Pipeline:
  1. Probe tags via `aseprite -b --list-tags --data ... --format json-array`
  2. Export the FULL frame sequence as one horizontal strip (native size)
  3. Optional integer nearest-neighbour upscale (default 2x: 128 -> 256)
  4. Emit the sprite_manifest.json monster_sheets entry with frame ranges
     derived from the artist's own tag boundaries

Animation mapping follows the shipped slime precedent (the T2 artist
reference already in the manifest): required game animations that the
artist did not author are mapped to REUSED artist frame sub-ranges, never
to synthesized frames. `--map` records the intent explicitly so the
reuse is visible in the manifest `source` string rather than implied.

Usage:
  uv run python tools/export_artist_monster.py \\
      --aseprite "assets/sprites/drive_archive/.../Mordaine animations.aseprite" \\
      --monster-id chancellor_mordaine \\
      --map idle=Idle --map attack='summon 1:0-8' \\
      --map hit='summon 1:9-10' --map dead='summon 1:11-12' \\
      --scale 2 --tier T2
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path("/home/struktured/projects/cowardly-irregular-artist-ship")


def probe_tags(ase: Path) -> tuple[dict, list[dict], int]:
    """Return (meta, frames, frame_count) with frameTags populated."""
    with tempfile.TemporaryDirectory() as td:
        data = Path(td) / "probe.json"
        sheet = Path(td) / "probe.png"
        subprocess.run(
            ["aseprite", "-b", "--list-tags", str(ase),
             "--data", str(data), "--format", "json-array",
             "--sheet", str(sheet)],
            check=True, capture_output=True,
        )
        d = json.loads(data.read_text())
    return d["meta"], d["frames"], len(d["frames"])


def export_strip(ase: Path, dest: Path, scale: int) -> tuple[int, int, int]:
    """Export all frames as one horizontal strip. Returns (w, h, n_frames)."""
    with tempfile.TemporaryDirectory() as td:
        raw = Path(td) / "strip.png"
        subprocess.run(["aseprite", "-b", str(ase), "--sheet", str(raw)],
                       check=True, capture_output=True)
        img = Image.open(raw).convert("RGBA")
    if scale != 1:
        # Integer nearest-neighbour ONLY — pixel-exact, no resampling,
        # no palette shift. Any other filter would alter artist pixels.
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest)
    frame_h = img.height
    return img.width, frame_h, img.width // frame_h


def parse_map(specs: list[str], tags: dict[str, tuple[int, int]]) -> dict:
    """Parse --map anim=Tag  or  --map anim='Tag:lo-hi' (tag-relative)."""
    out = {}
    for spec in specs:
        anim, _, rhs = spec.partition("=")
        anim, rhs = anim.strip(), rhs.strip()
        if ":" in rhs:
            tag_name, _, rng = rhs.rpartition(":")
            lo_s, _, hi_s = rng.partition("-")
            if tag_name not in tags:
                raise SystemExit(f"unknown tag {tag_name!r}; have {list(tags)}")
            base = tags[tag_name][0]
            lo = base + int(lo_s)
            hi = base + int(hi_s or lo_s)
            if hi > tags[tag_name][1]:
                raise SystemExit(
                    f"{anim}: {tag_name}:{rng} exceeds tag range "
                    f"{tags[tag_name]}")
            out[anim] = {"start": lo, "end": hi, "_tag": tag_name,
                         "_authored": False}
        else:
            if rhs not in tags:
                raise SystemExit(f"unknown tag {rhs!r}; have {list(tags)}")
            lo, hi = tags[rhs]
            out[anim] = {"start": lo, "end": hi, "_tag": rhs,
                         "_authored": True}
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--aseprite", required=True, type=Path)
    ap.add_argument("--monster-id", required=True)
    ap.add_argument("--map", action="append", default=[], dest="maps",
                    help="anim=Tag (whole tag) or anim='Tag:lo-hi' (tag-relative reuse)")
    ap.add_argument("--scale", type=int, default=2,
                    help="integer nearest-neighbour upscale (default 2)")
    ap.add_argument("--fps", type=int, default=8)
    ap.add_argument("--tier", default="T2")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--write-manifest", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    ase = args.aseprite
    if not ase.exists():
        print(f"ERROR: {ase} not found", file=sys.stderr)
        return 1

    meta, frames, n = probe_tags(ase)
    tags = {t["name"]: (t["from"], t["to"]) for t in meta.get("frameTags", [])}
    src_w = frames[0]["sourceSize"]["w"]
    src_h = frames[0]["sourceSize"]["h"]

    print(f"[{args.monster_id}] {ase.name}")
    print(f"  native frame: {src_w}x{src_h}   frames: {n}   scale: {args.scale}x"
          f"  -> {src_w*args.scale}x{src_h*args.scale}")
    for name, (lo, hi) in tags.items():
        print(f"  tag {name!r}: {lo}..{hi}  ({hi-lo+1} frames)")

    if not args.maps:
        print("\n(no --map given; probe only)")
        return 0

    anims = parse_map(args.maps, tags)
    print("\n  animation mapping:")
    for a, v in anims.items():
        kind = "AUTHORED" if v["_authored"] else "reused"
        print(f"    {a:8s} {v['start']:2d}..{v['end']:<2d}  [{kind} from {v['_tag']!r}]")

    out = args.out or (GAME_REPO / "assets" / "sprites" / "monsters"
                       / f"{args.monster_id}.png")

    if args.dry_run:
        print(f"\nDRY RUN — would write {out}")
        return 0

    w, h, nf = export_strip(ase, out, args.scale)
    print(f"\n  -> {out}  ({w}x{h}, {nf} frames)")

    authored = sorted({v["_tag"] for v in anims.values() if v["_authored"]})
    reused = sorted({v["_tag"] for v in anims.values() if not v["_authored"]})
    src_note = (f"artist aseprite — {ase.parent.name}/{ase.name}; "
                f"tags authored: {', '.join(authored) or 'none'}"
                + (f"; frames reused for un-authored anims from: "
                   f"{', '.join(reused)}" if reused else ""))

    entry = {
        "path": f"res://assets/sprites/monsters/{args.monster_id}.png",
        "frame_width": src_w * args.scale,
        "frame_height": src_h * args.scale,
        "fps": args.fps,
        "animations": {a: {"start": v["start"], "end": v["end"]}
                       for a, v in anims.items()},
        "tier": args.tier,
        "source": src_note,
    }

    print("\n  manifest entry:")
    print(json.dumps({args.monster_id: entry}, indent=2))

    if args.write_manifest:
        mpath = GAME_REPO / "data" / "sprite_manifest.json"
        m = json.loads(mpath.read_text())
        m.setdefault("monster_sheets", {})[args.monster_id] = entry
        mpath.write_text(json.dumps(m, indent=2) + "\n")
        print(f"\n  manifest updated: {mpath}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
