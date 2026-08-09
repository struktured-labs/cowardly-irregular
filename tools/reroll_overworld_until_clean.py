#!/usr/bin/env python3
"""Reroll sliced world walk grids, KEEPING THE BEST attempt rather than the last.

gpt-image-1 places the figures off-grid maybe 1 run in 5 and assemble_game_grid then cuts
them mid-body, leaving one row nearly empty. A plain --force reroll overwrites, so a good
attempt is lost the moment the next one is worse. This keeps the lowest row-imbalance seen.

Acceptance is row mass: max(row)/min(row) over the four rows' opaque pixels. The five ARTIST
sheets score 1.07-1.57, so 1.96 clears all known-good work — see the generator's docstring.
⛔ It catches SLICING and is blind to a mangled-but-full-size row. Still look at the output.

  uv run --with pillow --with openai python tools/reroll_overworld_until_clean.py \
      --pairs fighter/digital rogue/industrial --attempts 3
"""
import argparse
import importlib.util
import os
import shutil
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gw = _load("_gw", HERE / "gen_world_overworld_gptimage.py")
JOBS = gw.gw.GAME_REPO / "assets" / "sprites" / "jobs"


def imbalance(path: Path) -> float:
    return gw.row_imbalance(Image.open(path).convert("RGBA"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pairs", nargs="+", required=True, help="job/world")
    ap.add_argument("--attempts", type=int, default=3)
    ap.add_argument("--quality", default="medium")
    args = ap.parse_args()
    if not os.environ.get("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not set", file=sys.stderr)
        return 1

    from openai import OpenAI
    client = OpenAI()
    spent, still_bad = 0.0, []
    for pair in args.pairs:
        job, world = pair.split("/")
        dest = JOBS / job / f"overworld_{world}.png"
        best = imbalance(dest) if dest.exists() else 999.0
        print(f"[{pair}] starting imbalance {best:.2f}")
        for n in range(args.attempts):
            if best <= gw.SLICE_THRESHOLD:
                break
            try:
                grid, _raw = gw.build_grid(client, job, world, args.quality)
            except Exception as e:
                print(f"  attempt {n+1} FAILED: {e}", file=sys.stderr)
                continue
            spent += gw.COST[args.quality]
            tmp = dest.with_suffix(".candidate.png")
            grid.save(tmp)
            cand = imbalance(tmp)
            keep = cand < best
            print(f"  attempt {n+1}: imbalance {cand:.2f} -> {'KEEP' if keep else 'discard'}")
            if keep:
                shutil.move(str(tmp), str(dest))
                best = cand
            else:
                tmp.unlink(missing_ok=True)
        status = "ok" if best <= gw.SLICE_THRESHOLD else "STILL SLICED"
        if best > gw.SLICE_THRESHOLD:
            still_bad.append(f"{pair} ({best:.2f})")
        print(f"[{pair}] final {best:.2f} — {status}")

    print(f"\nspent ~${spent:.2f}")
    if still_bad:
        print(f"🔴 still sliced after {args.attempts} attempts: {still_bad}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
