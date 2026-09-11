#!/usr/bin/env python3
"""Phase 2 of the 2026-09-07 sweep: archetypes maps request but that never had a
sheet (masterite faces, elder, mysterious), plus a cartographer_wraith battle
strip to replace the generic specter placeholder. Anchored to existing corpus
art; Leo's versions supersede all of it."""

from __future__ import annotations

import argparse
import base64
import importlib.util
import io
import json
import sys
from pathlib import Path

from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
NPCS = PROJECT / "assets/sprites/npcs"
MON = PROJECT / "assets/sprites/monsters"
spec = importlib.util.spec_from_file_location("ow", PROJECT / "tools/gen_overworld_gpt_image.py")
ow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ow)

# name -> (identity ref path, format ref grid, char_desc)
ARCHES = {
    "arbiter": (MON / "masterite_arbiter_medieval.png",
                "monk", "the Masterite Arbiter — a stern judicial figure in layered robes, matching the reference's colours and regalia"),
    "curator": (MON / "masterite_curator_medieval.png",
                "scholar", "the Masterite Curator — a meticulous archivist, matching the reference's colours and regalia"),
    "tempo": (MON / "masterite_tempo_medieval.png",
              "young_woman", "the Masterite Tempo — a rhythmic, poised figure, matching the reference's colours and regalia"),
    "warden": (MON / "masterite_warden_medieval.png",
               "guard", "the Masterite Warden — an imposing keeper, matching the reference's colours and armour"),
    "elder": (NPCS / "old_man" / "overworld.png",
              "old_man", "a village elder — long grey beard, ceremonial robe, walking staff"),
    "mysterious": (NPCS / "traveler" / "overworld.png",
                   "traveler", "a mysterious hooded figure — face fully in shadow under a deep cowl, muted grey-violet cloak"),
}


def frame0_square(path: Path) -> bytes:
    im = Image.open(path).convert("RGBA")
    side = im.height
    return ow.pad_to_square(im.crop((0, 0, min(side, im.width), side)), 1024)


ROLL_ATTEMPTS = 3


def _assemble_with_rerolls(client, name, ident, fmt, desc, raw):
    """gpt-image-1 intermittently returns 2 content rows where the assembler needs 3; that is a bad
    ROLL, not a bad prompt. Measured 4 of ~39 rolls on 2026-09-11."""
    for attempt in range(1, ROLL_ATTEMPTS + 1):
        try:
            return ow.assemble_game_grid(raw, target=32)
        except ow.RowCountMismatch as e:
            print(f"    re-roll {attempt}/{ROLL_ATTEMPTS} {name}: {e}", flush=True)
            if attempt == ROLL_ATTEMPTS:
                raise
            resp = client.images.edit(
                model="gpt-image-1",
                image=[("ref_identity.png", frame0_square(ident), "image/png"),
                       ("ref_chibi_format.png", frame0_square(NPCS / fmt / "overworld.png"), "image/png")],
                prompt=ow.PROMPT_TEMPLATE.format(char_desc=desc),
                size="1024x1024", quality="medium", n=1,
            )
            raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json))).convert("RGBA")


def gen_archetype(client: OpenAI, name: str) -> None:
    ident, fmt, desc = ARCHES[name]
    out = NPCS / name / "overworld.png"
    out.parent.mkdir(exist_ok=True)
    if out.exists():
        print(f"[skip] {name}")
        return
    resp = client.images.edit(
        model="gpt-image-1",
        image=[("ref_identity.png", frame0_square(ident), "image/png"),
               ("ref_chibi_format.png", frame0_square(NPCS / fmt / "overworld.png"), "image/png")],
        prompt=ow.PROMPT_TEMPLATE.format(char_desc=desc),
        size="1024x1024", quality="medium", n=1,
    )
    raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json))).convert("RGBA")
    grid = _assemble_with_rerolls(client, name, ident, fmt, desc, raw)
    ow.refuse_hollow_grid(grid, name)
    grid.save(out)
    m = json.loads((PROJECT / "data/sprite_manifest.json").read_text())
    m["overworld_npc_sheets"][name] = {
        "path": f"res://assets/sprites/npcs/{name}/overworld.png",
        "frame_width": 32, "frame_height": 32, "tier": "T1",
        "source": f"gpt-image-1, identity anchored to {ident.name} (2026-09-07 phase 2; archetype was requested by maps but had NO sheet — rendered procedural)",
    }
    (PROJECT / "data/sprite_manifest.json").write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
    print(f"[ok] {name} <- {ident.name}")


WRAITH_PROMPT = """Generate a battle sprite sheet for a CARTOGRAPHER WRAITH — a spectral ghost
surveyor that redraws maps: translucent teal-grey shroud, glowing unrolled chart clutched in
wispy hands, a floating compass rose, faint quill-line trails. 16-bit JRPG style matching the
reference monsters' pixel density and palette discipline.

Output format — match exactly:
  - 1024x1024 canvas, TRANSPARENT background, a 2-row by 4-column GRID of 256x256 cells
  - Row 0 (top): 4 IDLE frames — hovering bob, chart held, FACING RIGHT in profile
  - Row 1 (bottom): 4 ATTACK frames — it sweeps the chart forward and map-lines lash out,
    still FACING RIGHT
  - The creature fills ~80% of each cell; consistent identity across all 8 frames"""


def gen_wraith(client: OpenAI) -> None:
    out = MON / "cartographer_wraith.png"
    resp = client.images.edit(
        model="gpt-image-1",
        image=[("ref_style_a.png", frame0_square(MON / "skeleton.png"), "image/png"),
               ("ref_style_b.png", frame0_square(MON / "data_wraith.png"), "image/png")],
        prompt=WRAITH_PROMPT, size="1024x1024", quality="high", n=1,
    )
    raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json))).convert("RGBA")
    (PROJECT / "tmp").mkdir(exist_ok=True)
    raw.save(PROJECT / "tmp/wraith_raw.png")
    strip = Image.new("RGBA", (256 * 8, 256), (0, 0, 0, 0))
    for i in range(8):
        r, c = divmod(i, 4)
        strip.paste(raw.crop((c * 256, r * 512 // 2, (c + 1) * 256, r * 512 // 2 + 512 // 2)).resize((256, 256)), (i * 256, 0))
    print("[wraith] raw saved; strip assembly happens after visual review")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma-separated archetype names; default is all missing")
    ap.add_argument("--wraith", action="store_true",
                    help="also roll a cartographer_wraith BATTLE raw. OFF by default: it is a "
                         "high-quality call (~$0.19) that writes no sheet — it saves a raw for "
                         "manual review — and cartographer_wraith.png already shipped. It ran on "
                         "EVERY invocation until 2026-09-11, so regenerating one archetype cost "
                         "$0.19 on a roll nobody asked for.")
    a = ap.parse_args()
    only = {n.strip() for n in a.only.split(",") if n.strip()}
    unknown = only - set(ARCHES)
    if unknown:
        print(f"ERROR: unknown archetype(s): {sorted(unknown)}; known: {sorted(ARCHES)}")
        return 2
    client = OpenAI()
    for name in ARCHES:
        if only and name not in only:
            continue
        try:
            gen_archetype(client, name)
        except Exception as e:
            print(f"FAIL {name}: {e}")
    if a.wraith:
        try:
            gen_wraith(client)
        except Exception as e:
            print(f"FAIL wraith: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
