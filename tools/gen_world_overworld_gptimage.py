#!/usr/bin/env python3
"""Per-world OVERWORLD walk grids via the shipped gpt-image-1 prompt.

Supersedes tools/gen_world_overworld.py (the PixelLab attempt), which is kept only for its
record of four measured failures. The working path was already in the repo:
`gen_overworld_gpt_image.PROMPT_TEMPLATE` + `assemble_game_grid`, which has shipped 27
named-NPC sheets. Measured on fighter/suburban, same metric as every failed attempt —
a correct sheet has NARROW side views:

  artist base (correct)              2050 / 1414 / 1414 / 2130
  THIS                               1946 / 1354 / 1354 / 1964   frame drift 8-17
  best PixelLab attempt              1952 / 1431 / 1460 / 1941   costume lost, drift 25-48

⚠️ The side rows are IDENTICAL by construction — assemble_game_grid mirrors row 1 into row 2,
exactly as the artist's own sheet does (1414/1414). Equal side rows here are correctness,
not the "one pose repeated" failure; that failure shows as all FOUR rows equal.

TWO references, mirroring gen_named_npc_overworld's pattern:
  1 identity — frame 0 of jobs/<job>/idle_<world>.png   the costume, from stage 1
  2 format   — jobs/<job>/overworld.png                 the artist's own chibi grid

  python3 tools/gen_world_overworld_gptimage.py --jobs fighter --worlds suburban --dry-run
  python3 tools/gen_world_overworld_gptimage.py --jobs fighter cleric --worlds suburban
"""
import argparse
import base64
import importlib.util
import io
import os
import sys
import time
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ow = _load("_ow", HERE / "gen_overworld_gpt_image.py")
gw = _load("_gw", HERE / "gen_world_job_sprites.py")

JOBS = gw.GAME_REPO / "assets" / "sprites" / "jobs"
COST = {"low": 0.011, "medium": 0.042, "high": 0.167}


def build_grid(client, job: str, world: str, quality: str):
    """One sheet. Returns (grid_128, raw_1024) or raises."""
    identity = Image.open(JOBS / job / f"idle_{world}.png").convert("RGBA").crop((0, 0, 256, 256))
    fmt = Image.open(JOBS / job / "overworld.png").convert("RGBA")
    char_desc = (f"{gw.JOB_CORE[job]} dressed in {gw.WORLD_DRESS[world]} "
                 f"Garments in {gw.JOB_SIGNATURE[job]}.")
    resp = client.images.edit(
        model="gpt-image-1",
        image=[("identity.png", ow.pad_to_square(identity), "image/png"),
               ("format.png", ow.pad_to_square(fmt), "image/png")],
        prompt=ow.PROMPT_TEMPLATE.format(char_desc=char_desc),
        size="1024x1024", quality=quality)
    raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json))).convert("RGBA")
    return ow.assemble_game_grid(raw, target=32), raw



## ⛔ THERE IS NO WORKING AUTOMATED ACCEPTANCE TEST FOR THESE SHEETS. Review by eye.
##
## I built one and it was worthless, which is worth recording so the next attempt does not
## rebuild it. gpt-image-1's grid compliance is inconsistent: fighter/suburban came back a
## clean, shippable 4x4; four cleric sheets came back with figures straddling cell
## boundaries, so assemble_game_grid sliced them mid-body.
##
## My hypothesis was that a compliant grid shows four separated content bands in the raw's
## vertical alpha density, and a bad one shows continuous density. Measured:
##   cleric/industrial (BAD)   1 content band  -> rejected  ✅
##   cleric/abstract   (BAD)   1 content band  -> rejected  ✅
##   fighter/suburban  (GOOD)  1 content band  -> REJECTED  🔴
## The control is what killed it. At ~70% cell fill the figures touch across cell edges in
## EVERY sheet, good or bad, so there are never gaps to count. The real difference is
## vertical OFFSET — the figures straddle boundaries rather than merge — and band counting
## cannot see offset.
##
## ⚠️ The row-count ratio below is also insufficient ON ITS OWN: cleric/industrial scored
## 0.56, a healthy side/front spread, while being visibly sliced in half. It catches
## "one pose repeated four times" and nothing else.
##
## So: generate, LOOK at every sheet, reroll the bad ones. Measured hit rate 1 of 5.

def row_counts(grid: Image.Image):
    a = grid.split()[3]
    return [sum(1 for q in a.crop((0, r * 32, 128, r * 32 + 32)).get_flattened_data() if q > 40)
            for r in range(4)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", nargs="+", required=True)
    ap.add_argument("--worlds", nargs="+", required=True)
    ap.add_argument("--quality", choices=list(COST), default="medium")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    bad = [j for j in args.jobs if j not in gw.JOB_CORE] + \
          [w for w in args.worlds if w not in gw.WORLD_DRESS]
    if bad:
        print(f"ERROR: unknown job/world: {bad}", file=sys.stderr)
        return 2
    gw._check_output_names(args.worlds)

    targets = []
    for job in args.jobs:
        for world in args.worlds:
            out = JOBS / job / f"overworld_{world}.png"
            if out.exists() and not args.force:
                continue
            # Both refs are required; a missing one silently changes what is generated.
            missing = [p.name for p in (JOBS / job / f"idle_{world}.png", JOBS / job / "overworld.png")
                       if not p.exists()]
            if missing:
                print(f"  SKIP {job}/{world}: missing ref(s) {missing}")
                continue
            targets.append((job, world, out))

    unit = COST[args.quality]
    print(f"{len(targets)} walk grid(s) at {args.quality} — est ${unit * len(targets):.2f}")
    if args.dry_run:
        for job, world, out in targets:
            print(f"  {job:<14}{world:<12}-> {out.relative_to(gw.GAME_REPO)}")
        return 0
    if not targets:
        return 0
    if not os.environ.get("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not set (source setenv.sh)", file=sys.stderr)
        return 1

    raw_dir = HERE.parent / "tmp" / "world_overworld_raw"
    raw_dir.mkdir(parents=True, exist_ok=True)
    from openai import OpenAI
    client = OpenAI()

    total, made, weak, rejected = 0.0, [], [], []
    for job, world, out in targets:
        t0 = time.time()
        print(f"[{job}/{world}] gpt-image-1 {args.quality} (${unit:.3f})...", end=" ", flush=True)
        try:
            grid, raw = build_grid(client, job, world, args.quality)
        except Exception as e:
            print(f"FAILED: {e}", file=sys.stderr)
            rejected.append(f"{job}/{world}")
            continue
        total += unit
        raw.save(raw_dir / f"{job}_{world}_raw.png")
        out.parent.mkdir(parents=True, exist_ok=True)
        grid.save(out)
        made.append(f"{job}/{world}")
        rc = row_counts(grid)
        # The failure this whole lane kept hitting: all four rows equal = one pose x4.
        # Side rows equal to EACH OTHER is correct (assemble_game_grid mirrors them).
        side, front = (rc[1] + rc[2]) / 2, (rc[0] + rc[3]) / 2
        ratio = side / front if front else 1.0
        flag = "  ⚠️ NO DIRECTIONAL SPREAD" if ratio > 0.92 else ""
        if flag:
            weak.append(f"{job}/{world} (ratio {ratio:.2f})")
        print(f"{rc} side/front {ratio:.2f}{flag}  {time.time()-t0:.0f}s")

    print(f"\nGenerated {len(made)}/{len(targets)} — spent ~${total:.2f}")
    if rejected:
        print(f"⛔ REJECTED (grid never came back clean): {rejected}", file=sys.stderr)
    if weak:
        print(f"⚠️ REVIEW THESE FIRST (no directional spread): {weak}", file=sys.stderr)
    if len(made) != len(targets):
        print(f"MISSING: {[f'{j}/{w}' for j, w, _ in targets if f'{j}/{w}' not in made]}",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
