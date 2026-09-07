#!/usr/bin/env python3
"""PILOT: per-world overworld walk grid via the EXISTING gpt-image-1 prompt.

⚠️ THIS EXISTS BECAUSE I ASSERTED THE OPPOSITE AND WAS WRONG.
tools/gen_world_overworld.py's docstring says gpt-image-1 "cannot produce a coherent
4-direction walk grid". That was measured against MY prompt. `gen_overworld_gpt_image.
PROMPT_TEMPLATE` has shipped 27 named-NPC sheets using gpt-image-1, and it differs from
mine in exactly the ways my failures needed:

  - explicit 4x4 grid with per-ROW semantics (mine described directions in prose)
  - TWO references: identity (the costumed battle sprite) + FORMAT (an existing chibi grid)
  - a non-negotiable back-view clause for row 3 — someone hit "every row came out
    front-facing" before me and fixed it in the prompt rather than in the pipeline
  - assemble_game_grid() then does head-lock and side-row mirroring

So the identity/format split I built by hand for PixelLab already existed here, tuned.
Look for the existing instrument before declaring a tool incapable.

Refs, mirroring gen_named_npc_overworld's two-ref pattern:
  1 identity — frame 0 of jobs/<job>/idle_<world>.png   the costume, already generated
  2 format   — jobs/<job>/overworld.png                 the artist's own chibi grid
"""
import importlib.util
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


ow = _load("_ow", HERE / "gen_overworld_gpt_image.py")
gw = _load("_gw", HERE / "gen_world_job_sprites.py")

JOB, WORLD = "fighter", "suburban"
JOBS = gw.GAME_REPO / "assets" / "sprites" / "jobs"
OUT = HERE.parent / "tmp" / "review" / "gptimage_grid.png"


def main():
    if not os.environ.get("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not set", file=sys.stderr)
        return 1

    identity = JOBS / JOB / f"idle_{WORLD}.png"
    fmt = JOBS / JOB / "overworld.png"
    for p in (identity, fmt):
        if not p.exists():
            print(f"ERROR: missing {p}", file=sys.stderr)
            return 1

    char_desc = (f"{gw.JOB_CORE[JOB]} dressed in {gw.WORLD_DRESS[WORLD]} "
                 f"Garments in {gw.JOB_SIGNATURE[JOB]}.")
    prompt = ow.PROMPT_TEMPLATE.format(char_desc=char_desc)

    ident_img = Image.open(identity).convert("RGBA").crop((0, 0, 256, 256))
    fmt_img = Image.open(fmt).convert("RGBA")

    from openai import OpenAI
    client = OpenAI()
    print(f"[{JOB}/{WORLD}] gpt-image-1 medium, 2 refs (identity + format)...", flush=True)
    resp = client.images.edit(
        model="gpt-image-1",
        image=[("identity.png", ow.pad_to_square(ident_img), "image/png"),
               ("format.png", ow.pad_to_square(fmt_img), "image/png")],
        prompt=prompt,
        size="1024x1024",
        quality="medium")
    import base64, io
    raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json))).convert("RGBA")
    raw.save(HERE.parent / "tmp" / "review" / "gptimage_raw.png")

    grid = ow.assemble_game_grid(raw, target=32)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    grid.save(OUT)

    a = grid.split()[3]
    rows = [sum(1 for q in a.crop((0, r * 32, 128, r * 32 + 32)).get_flattened_data() if q > 40)
            for r in range(4)]
    print(f"  -> {OUT}  {grid.size}")
    print(f"row opaque: {rows}")
    print(f"artist base: [2050, 1414, 1414, 2130]   (side views MUST be narrower)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
