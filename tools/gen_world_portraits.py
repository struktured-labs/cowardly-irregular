#!/usr/bin/env python3
"""Per-world DIALOGUE PORTRAITS — the party's faces change with the world.

struktured 2026-08-08: "the portraits have to change from one world to another in addition
to the character sprites (which cowir-sprites already did)."

⚠️ THE WORLD-DRESSED BUST PATH ALREADY EXISTED AND WAS ALREADY CORRECT. Driven across all
six worlds, _create_bust_from_job_sheet resolves idle.png / idle_suburban.png / … and every
one loads. It was UNREACHABLE: _create_portrait tries PORTRAIT_SPRITES first, and all 14
jobs have painted portrait art, so the bust ran for 0 of them. A correct mechanism behind a
rung that always wins is indistinguishable from a missing one — which is why he saw static
faces while the battle sprites transformed.

So rung 1 now probes <portrait>_<world>.png, and this fills that art in.

TWO anchors, mirroring the battle-idle batch:
  1 identity/style — the job's EXISTING painted portrait. Keeps the face the same person
                     and the rendering consistent with the artist-tier busts.
  2 costume        — frame 0 of jobs/<job>/idle_<world>.png, the world dress already shipped.
                     The portrait must agree with the body on screen beside it.

  python3 tools/gen_world_portraits.py --jobs fighter --worlds suburban --dry-run
  python3 tools/gen_world_portraits.py --worlds suburban --quality medium
"""
import argparse
import importlib.util
import json
import os
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_rap = _load("_rap", HERE / "regen_archetype_portraits.py")
_gw = _load("_gw", HERE / "gen_world_job_sprites.py")

GAME = _rap.GAME_REPO
JOBS = GAME / "assets" / "sprites" / "jobs"
PORTRAITS = GAME / "assets" / "sprites" / "portraits"

PREFIX = (
    "16-bit SNES-era JRPG dialogue portrait — a BUST (head and shoulders, upper chest), "
    "front-facing, centred, on a fully transparent background. Clean pixel art with bold "
    "dark outlines, soft cel shading, limited palette, no anti-aliasing fuzz. "
    "CRITICAL — Reference Image 1 is THE SAME CHARACTER: keep their face, hair, skin tone, "
    "eye colour, age and expression EXACTLY. This is that person in different clothes, not "
    "a new person. Match Reference 1's rendering style, line weight and framing precisely. "
    "Reference Image 2 shows the OUTFIT to put them in — take the garments, materials and "
    "palette from it, and nothing else. "
)


def targets(jobs, worlds, force):
    out = []
    for job in jobs:
        base = PORTRAITS / f"{job}.png"
        for w in worlds:
            costume = JOBS / job / f"idle_{w}.png"
            dest = PORTRAITS / f"{job}_{w}.png"
            if dest.exists() and not force:
                continue
            missing = [p.name for p in (base, costume) if not p.exists()]
            if missing:
                print(f"  SKIP {job}/{w}: missing anchor(s) {missing}")
                continue
            out.append((job, w, base, costume, dest))
    return out


def main() -> int:
    all_jobs = sorted(json.load(open(GAME / "data" / "jobs.json")).keys())
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", nargs="+", default=all_jobs)
    ap.add_argument("--worlds", nargs="+", default=list(_gw.WORLD_DRESS))
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="medium")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    bad = [j for j in args.jobs if j not in all_jobs] + \
          [w for w in args.worlds if w not in _gw.WORLD_DRESS]
    if bad:
        print(f"ERROR: unknown job/world: {bad}", file=sys.stderr)
        return 2
    # Same pre-spend check as the battle sheets: a suffix the runtime never asks for
    # produces art that loads, imports, and is never requested.
    _gw._check_output_names(args.worlds)

    t = targets(args.jobs, args.worlds, args.force)
    unit = _rap.COST[args.quality]
    print(f"{len(t)} portrait(s) at {args.quality} — est ${unit*len(t):.2f}")
    if args.dry_run:
        for job, w, _b, _c, dest in t[:8]:
            print(f"  {job:<14}{w:<12}-> {dest.relative_to(GAME)}")
        if len(t) > 8:
            print(f"  ... and {len(t)-8} more")
        return 0
    if not t:
        return 0
    if not os.environ.get("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not set (source setenv.sh)", file=sys.stderr)
        return 1

    from openai import OpenAI
    client = OpenAI()
    total, made = 0.0, []
    for job, w, base, costume, dest in t:
        print(f"[{job}/{w}] gpt-image-1 {args.quality} (${unit:.3f})...", end=" ", flush=True)
        ident = Image.open(base).convert("RGBA")
        dress = Image.open(costume).convert("RGBA").crop((0, 0, 256, 256))
        prompt = (PREFIX + f"The character is {_gw.JOB_CORE[job]}. "
                  f"Their outfit is {_gw.WORLD_DRESS[w]} "
                  f"Garments in {_gw.JOB_SIGNATURE[job]}.")
        try:
            raw = _rap.call_gpt(client, prompt, [
                ("ref_identity.png", _rap_bytes(ident), "image/png"),
                ("ref_costume.png", _rap_bytes(dress), "image/png"),
            ], args.quality)
        except Exception as e:
            print(f"FAILED: {e}", file=sys.stderr)
            continue
        total += unit
        img = _rap.transparent_bg(_rap.downscale(raw, 256))
        dest.parent.mkdir(parents=True, exist_ok=True)
        img.save(dest)
        made.append(f"{job}/{w}")
        print(f"-> {dest.name}")

    print(f"\nGenerated {len(made)}/{len(t)} — spent ~${total:.2f}")
    if len(made) != len(t):
        print(f"MISSING: {[f'{j}/{w}' for j, w, *_ in t if f'{j}/{w}' not in made]}",
              file=sys.stderr)
        return 1
    return 0


def _rap_bytes(img: Image.Image) -> bytes:
    import io
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    buf = io.BytesIO()
    canvas.resize((1024, 1024), Image.NEAREST).save(buf, format="PNG")
    return buf.getvalue()


if __name__ == "__main__":
    sys.exit(main())
