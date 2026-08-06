#!/usr/bin/env python3
"""Generate per-world overworld walk grids from the world-dressed idle sheets.

STAGE 2 of the two-stage pipeline. Stage 1 (gpt-image-1, tools/gen_world_job_sprites.py)
produces a costumed 256x256 idle; this turns that idle into a 4-direction 128x128 walk
grid via PixelLab animate-with-text.

Why two stages: gpt-image-1 cannot produce a coherent 4-direction walk grid. Asked for
one it returns a head-and-shoulders portrait, and forcing "full body, head one third"
made it worse (face close-up plus failed transparency). PixelLab's animate-with-text is
purpose-built for exactly this and takes a reference image, so each tool does the job it
is actually good at: gpt-image-1 designs the costume, PixelLab animates it.

⛔ INCOMPLETE — animate-with-text ALONE CANNOT PRODUCE THE FOUR DIRECTIONS.
Measured twice, and the numbers are the whole story. Row opaque-pixel counts for
down/left/right/up, where a correct sheet must have NARROW side views:

  artist base (correct)      2050 / 1414 / 1414 / 2130
  battle idle as reference    441 /  440 /  459 /  445    unusable, wrong proportions too
  overworld chibi as ref     2265 / 2266 / 2265 / 2265    good art, all four rows IDENTICAL

The second attempt produced a genuinely nice chibi — readable face, correct proportions —
and still repeated one front-facing pose four times. Putting "walking west, side profile"
in the description does not rotate the subject; the endpoint animates whatever orientation
the reference already has.

✅ THE MISSING PIECE IS THE /rotate ENDPOINT, and it is verified working:
  Direction  enum: north north-east east south-east south south-west west north-west
  CameraView enum: side, low top-down, high top-down     <- "low top-down" is this game's

  rotate(south -> west/east/north, low top-down) on the artist fighter chibi:
    south (ref) 2259 | west 1524 | east 1407 | north 1851
  Side views narrow exactly as the artist's own sheet does, and the north result is a
  true back-of-head view. $0.011 per rotation.

REMAINING WORK to finish this: the rotate step has no description field, so it preserves
the costume it is given. The full chain therefore needs a re-dress of the SOUTH chibi
first (generate-image-bitforge or /inpaint, using the world idle as the style reference),
then 3 rotations, then 4 animate calls — roughly 8 calls and ~$0.09 per sheet.

  python3 tools/gen_world_overworld.py --jobs fighter --worlds suburban --dry-run
  python3 tools/gen_world_overworld.py --jobs fighter cleric --worlds suburban industrial
"""
import argparse
import base64
import importlib.util
import io
import json
import os
import sys
import time
from pathlib import Path

import httpx
from PIL import Image

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("_pl", HERE / "gen_overworld_pixellab.py")
_pl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_pl)

_spec2 = importlib.util.spec_from_file_location("_gw", HERE / "gen_world_job_sprites.py")
_gw = importlib.util.module_from_spec(_spec2)
_spec2.loader.exec_module(_gw)

GAME_JOBS = _gw.GAME_REPO / "assets" / "sprites" / "jobs"
TMP = HERE.parent / "tmp" / "world_overworld"
COST_PER_SHEET = 0.056


def reference_from_idle(job: str, world: str, ref_from: str = "overworld") -> str:
    """The 64x64 chibi PixelLab animates from.

    ⚠️ ref_from="battle" is kept to document a MEASURED failure, not as a real option.
    Feeding the world-dressed BATTLE idle produced an unusable grid: the battle sprite is
    a side-facing 3/4 view drawn facing RIGHT toward the enemy, and PixelLab preserved that
    orientation for all four directions instead of reorienting. Every row came out
    front-ish with splayed arms — opaque counts 441/440/459/445 across down/left/right/up,
    i.e. no directional differentiation whatsoever — and the figure kept the battle
    sprite's realistic proportions instead of the artist's chibi.

    The overworld sheet is the correct structural reference: frame (0,0) is the artist's
    own front-facing top-down chibi, so pose, framing and head-to-body ratio are already
    right and only the COSTUME has to change, which is what the description asks for.
    """
    if ref_from == "battle":
        src = GAME_JOBS / job / f"idle_{world}.png"
        if not src.exists():
            raise FileNotFoundError(f"no world idle sheet: {src}")
        img = Image.open(src).convert("RGBA").crop((0, 0, 256, 256))
    else:
        src = GAME_JOBS / job / "overworld.png"
        if not src.exists():
            raise FileNotFoundError(f"no overworld sheet: {src}")
        img = Image.open(src).convert("RGBA").crop((0, 0, 32, 32))
    buf = io.BytesIO()
    img.resize((64, 64), Image.LANCZOS).save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def describe(job: str, world: str) -> str:
    """Same identity + costume language stage 1 used, so the walk matches the idle."""
    return (f"{_gw.JOB_CORE[job]} RE-DRESSED in {_gw.WORLD_DRESS[world]} "
            f"Garments in {_gw.JOB_SIGNATURE[job]}. Keep the reference's chibi proportions, "
            f"large head and top-down framing exactly; change ONLY the clothing.")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", nargs="+", required=True)
    ap.add_argument("--worlds", nargs="+", required=True)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--ref-from", choices=["overworld", "battle"], default="overworld",
                    help="structural reference; 'battle' is a documented failure mode")
    args = ap.parse_args()

    bad = [j for j in args.jobs if j not in _gw.JOB_CORE] + \
          [w for w in args.worlds if w not in _gw.WORLD_DRESS]
    if bad:
        print(f"ERROR: unknown job/world: {bad}", file=sys.stderr)
        return 2

    targets = []
    for job in args.jobs:
        for world in args.worlds:
            out = GAME_JOBS / job / f"overworld_{world}.png"
            if out.exists() and not args.force:
                continue
            if not (GAME_JOBS / job / f"idle_{world}.png").exists():
                print(f"  SKIP {job}/{world}: no idle_{world}.png to animate from")
                continue
            targets.append((job, world, out))

    print(f"{len(targets)} walk grid(s) — est ${COST_PER_SHEET * len(targets):.2f} "
          f"({len(targets)} x 4 PixelLab calls)")
    if args.dry_run:
        for job, world, out in targets:
            print(f"  {job:<14}{world:<12}-> {out.relative_to(_gw.GAME_REPO)}")
        return 0
    if not targets:
        return 0

    api_key = os.environ.get("PIXELLAB_API_KEY", "")
    if not api_key:
        print("ERROR: PIXELLAB_API_KEY not set (source setenv.sh)", file=sys.stderr)
        return 1

    TMP.mkdir(parents=True, exist_ok=True)
    total, made = 0.0, []
    with httpx.Client() as client:
        for job, world, out in targets:
            print(f"[{job}/{world}]")
            try:
                ref = reference_from_idle(job, world, args.ref_from)
            except FileNotFoundError as e:
                print(f"  FAILED: {e}", file=sys.stderr)
                continue

            frames_by_dir, ok = {}, True
            for tag, clause in _pl.DIRECTIONS:
                print(f"   - {tag}...", end=" ", flush=True)
                t0 = time.time()
                try:
                    frames, cost = _pl.call_pixellab_walk(
                        client, api_key, describe(job, world), ref, clause, args.seed)
                except Exception as e:
                    print(f"FAILED: {e}", file=sys.stderr)
                    ok = False
                    break
                total += cost
                frames_by_dir[tag] = frames
                print(f"{len(frames)}f, ${cost:.3f}, {time.time()-t0:.1f}s")

            if not ok or len(frames_by_dir) != len(_pl.DIRECTIONS):
                print(f"  INCOMPLETE — not writing {out.name}", file=sys.stderr)
                continue

            _strip, grid = _pl.build_strip_and_grid(frames_by_dir)
            out.parent.mkdir(parents=True, exist_ok=True)
            grid.save(out)
            made.append(f"{job}/{world}")
            print(f"  -> {out.relative_to(_gw.GAME_REPO)}  {grid.size[0]}x{grid.size[1]}")

    (TMP / "_cost.json").write_text(json.dumps(
        {"sheets": made, "total_usd": round(total, 4)}, indent=2))
    print(f"\nGenerated {len(made)}/{len(targets)} — spent ~${total:.2f}")
    if len(made) != len(targets):
        print(f"MISSING: {[f'{j}/{w}' for j, w, _ in targets if f'{j}/{w}' not in made]}",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
