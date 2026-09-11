#!/usr/bin/env python3
"""Generate per-world overworld variants for the generic NPC archetypes.

struktured 2026-09-07 ("proc gen dude... in suburban"): the 29 archetype sheets
are medieval-only, and W2+ maps either show peasants on sidewalks or fall back
to procedural. Identity+format anchor is each archetype's OWN medieval grid —
the same corpus-guided chain that produced the shipped party walk grids.

Output: assets/sprites/npcs/<arch>/overworld_<suffix>.png (+ manifest entry
<arch>_<suffix> under overworld_npc_sheets — the sheet-audit ratchet requires
it). Resumable: existing outputs are skipped.

Usage:
    uv run python tools/gen_npc_world_variants.py --worlds suburban --limit 1
    uv run python tools/gen_npc_world_variants.py --worlds all
"""

from __future__ import annotations

import argparse
import base64
import importlib.util
import io
import json
import os
import sys
from pathlib import Path

from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
NPCS = PROJECT / "assets/sprites/npcs"
TMP = PROJECT / "tmp/npc_variants"
spec = importlib.util.spec_from_file_location("ow", PROJECT / "tools/gen_overworld_gpt_image.py")
ow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ow)

ROLL_ATTEMPTS = 3

WORLDS = {
    "suburban": "a cozy modern American suburb — casual contemporary clothes (jeans, hoodies, "
                "polos, sneakers), 16-bit EarthBound-adjacent palette",
    "steampunk": "a Victorian steampunk city — brass goggles, waistcoats, leather aprons, "
                 "gears and copper accents",
    "industrial": "a soot-and-steel industrial district — work overalls, hard hats, heavy "
                  "gloves, rivets and hazard stripes",
    "digital": "a neon digital/cyber world — sleek techwear, glowing circuit accents, "
               "holographic trim",
    "abstract": "a minimalist abstract void — simplified geometric clothing, flat muted "
                "tones, faint unreal glow",
}

# story principals stay medieval; only generic archetypes get world wardrobes
NAMED = {"bram", "marta", "elder_theron", "scholar_milo", "phil", "dr_temporal",
         "chancellor_mordaine", "boris", "brigadier_flux"}


def archetypes() -> list[str]:
    # a variant dir also holds overworld.png — without this guard a rerun generates variants-of-variants
    return sorted(d.name for d in NPCS.iterdir()
                  if d.is_dir() and (d / "overworld.png").exists() and d.name not in NAMED
                  and not any(d.name.endswith("_" + w) for w in WORLDS))


def gen_one(client: OpenAI, arch: str, world: str, quality: str) -> Path | None:
    out = NPCS / f"{arch}_{world}" / "overworld.png"
    out.parent.mkdir(exist_ok=True)
    if out.exists():
        return None
    ref = ow.pad_to_square(Image.open(NPCS / arch / "overworld.png").convert("RGBA"), 1024)
    desc = (f"the EXACT SAME character as the reference sheet (same face, hair colour, build, "
            f"silhouette and personality), re-dressed as a {arch.replace('_', ' ')} living in "
            f"{WORLDS[world]}. Keep them instantly recognisable as the reference person")
    TMP.mkdir(parents=True, exist_ok=True)
    # gpt-image-1 intermittently returns 2 content rows where the assembler needs 3; that is a bad
    # ROLL, not a bad prompt, so re-roll rather than abort the batch or ship the 3-way split of a
    # 2-row image (which is what produced 18 head-without-body sheets on 2026-09-07).
    last = None
    for attempt in range(1, ROLL_ATTEMPTS + 1):
        resp = client.images.edit(
            model="gpt-image-1",
            image=[("ref_identity_and_format.png", ref, "image/png")],
            prompt=ow.PROMPT_TEMPLATE.format(char_desc=desc),
            size="1024x1024",
            quality=quality,
            n=1,
        )
        raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json))).convert("RGBA")
        raw.save(TMP / f"{arch}_{world}_raw{'' if attempt == 1 else f'_try{attempt}'}.png")
        try:
            grid = ow.assemble_game_grid(raw, target=32)
        except ow.RowCountMismatch as e:
            last = e
            print(f"    re-roll {attempt}/{ROLL_ATTEMPTS} {arch} x {world}: {e}", flush=True)
            continue
        ow.refuse_hollow_grid(grid, f"{arch}_{world}")
        grid.save(out)
        break
    else:
        raise RuntimeError(f"{arch} x {world}: {ROLL_ATTEMPTS} rolls all unusable — {last}")
    register(arch, world)
    return out


def register(arch: str, world: str) -> None:
    mf = PROJECT / "data/sprite_manifest.json"
    m = json.loads(mf.read_text())
    key = f"{arch}_{world}"
    m.setdefault("overworld_npc_sheets", {})[key] = {
        "path": f"res://assets/sprites/npcs/{arch}_{world}/overworld.png",
        "frame_width": 32, "frame_height": 32, "tier": "T1",
        "source": f"gpt-image-1 world-variant, identity+format anchored to the {arch} medieval "
                  f"grid (2026-09-07 sweep; struktured's 'proc gen dude in suburban' report)",
    }
    mf.write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--worlds", default="suburban")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--only", default="", help="comma-separated <arch>_<world> keys; regenerate exactly these")
    ap.add_argument("--quality", default="medium")
    a = ap.parse_args()
    worlds = list(WORLDS) if a.worlds == "all" else a.worlds.split(",")
    # a repair run targets known-bad keys; iterating every archetype and relying on skip-if-exists
    # regenerates whatever else happens to be missing, which is not what a repair is
    only = {k.strip() for k in a.only.split(",") if k.strip()}
    client = OpenAI()
    done = fail = 0
    for world in worlds:
        for arch in archetypes():
            if a.limit and done >= a.limit:
                print(f"limit {a.limit} reached")
                return 0
            if only and f"{arch}_{world}" not in only:
                continue
            try:
                out = gen_one(client, arch, world, a.quality)
                if out:
                    done += 1
                    print(f"[{done}] {arch} x {world} -> {out.name}", flush=True)
            except Exception as e:
                fail += 1
                print(f"FAIL {arch} x {world}: {e}", flush=True)
                if fail >= 8:
                    print("too many failures, stopping")
                    return 1
    print(f"done={done} fail={fail}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
