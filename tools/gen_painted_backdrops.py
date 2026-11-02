#!/usr/bin/env python3
"""Paint cutscene backdrops (T1) in the buildings' style, replacing procedural gradients and video-frame stills.

struktured 2026-11-01: "any of that old school procgenylooking art needs to go"; cowir-main 20863 BACKDROP STYLE
RULING: rich 16-bit painted scenes in the same palette and straight-on look as the buildings, 1280x720, NO
baked-in characters (scenes puppet their own). The director's TextureRect is KEEP_ASPECT_COVERED, so 16:9 is safe.

gpt-image-2 paints at 1536x1024; the frame is centre-cropped to 16:9 and scaled to 1280x720. A redraw keeps its
filename (assets/cutscene_backdrops/<key>.png), so it shows with no wiring; a NEW key needs cowir-cutscenes to
re-point its scenes. Staged under tmp/painted_backdrops/; --deploy copies (overwriting a redraw is the point
here, and every current still is T1: procedural or a frame of an AI video -- never run this on artist art).

Usage:
    set -a; . ./setenv.sh; set +a
    uv run python tools/gen_painted_backdrops.py prologue_village       # stage (no names = all)
    uv run python tools/gen_painted_backdrops.py --deploy prologue_village
"""
from __future__ import annotations

import argparse
import base64
import io
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
STAGE = ROOT / "tmp/painted_backdrops"
OUT = ROOT / "assets/cutscene_backdrops"
MODEL = "gpt-image-2"
W, H = 1280, 720
COLOURS = 96

STYLE = ("A wide 16-bit SNES-era JRPG pixel-art cutscene BACKGROUND painting, in the rich hand-pixeled style of the "
         "towns and interiors of classic Square RPGs: crisp outlines, layered depth, detailed textures, a limited but "
         "warm palette, readable shapes. A straight-on view of an empty stage for a scene: absolutely NO people, no "
         "characters, no animals in the foreground, no text, no letters, no UI. Leave the lower middle open, like a "
         "stage floor where characters will stand.")

BACKDROPS = {
    # -- the procedural ones
    "prologue_village": "A small medieval village at dawn: thatched cottages with smoking chimneys, a dirt square with a "
                        "well, fences and flower boxes, rolling hills and a pink-and-gold sunrise sky.",
    "prologue_forest": "A quiet forest path in the morning: tall old trees, ferns, mossy roots, golden shafts of light "
                       "through the canopy, the path running away into the woods.",
    "cave_entrance": "The mouth of a great rocky cave in a mountainside: jagged stone, a dark opening, two iron torches "
                     "burning beside it, scattered boulders, a cool blue-grey dusk sky.",
    "throne_room": "The throne room of a medieval castle: a long red carpet to a raised stone dais with a tall throne, "
                   "stone pillars with banners, stained-glass windows, braziers, dim and imposing.",
    "mechanism_interior": "Inside a giant clockwork mechanism: enormous brass gears and cogs turning, catwalks and iron "
                          "railings, pipes venting steam, warm amber lamplight, a gear-train room.",
    "vertex_village": "A minimalist, existential last town: a few plain pale geometric buildings on a flat grey plain "
                      "under a pale empty sky, very sparse, quiet and slightly uncanny.",
    # -- the seven stills redrawn from their retired videos (f8f025779)
    "maple_heights_street": "A sunny 1990s American suburban street: tidy houses with lawns, picket fences, mailboxes, "
                            "a maple tree, a quiet asphalt road with a sidewalk, warm afternoon light.",
    "brasston_square": "The town square of a Victorian steampunk city: brick buildings with brass trim, a clock tower, "
                       "gas lamps, cobblestones, pipes and steam, an overcast amber sky.",
    "rivet_row_factory": "An industrial factory district: smokestacks, corrugated metal sheds, conveyor gantries, "
                         "stacked crates and oil drums, a smoggy dusk sky.",
    "director_office": "A corporate director's office: a large wooden desk with a leather chair, filing cabinets, a "
                       "window with blinds, framed certificates, fluorescent light, neat and cold.",
    "community_center": "An EMPTY suburban community center hall: folding tables and stacked chairs, a bulletin board "
                        "with flyers, a coffee urn, linoleum floor, fluorescent light, nobody there.",
    "calibrant_desk": "A vast dark digital void with a single desk floating in it: a glowing terminal, papers, a "
                      "desk lamp, faint blue grid lines receding into the dark.",
    "node_prime": "The heart of a neon cyber city inside a computer: a glowing central data core tower, circuit-trace "
                  "streets, cyan and magenta neon, a dark navy sky of grid lines.",
    # -- new keys (cowir-cutscenes re-points their scenes)
    "harmonia_square": "Harmonia's town square at mid-morning: a stone plaza with a cherry-tree fountain in the centre, "
                       "the Sleepy Slime Inn frontage with a notice nailed to its door, timber-framed houses, a "
                       "castle on the ridge behind under a clear blue sky.",
    "harmonia_square_portal": "Harmonia's town square at dusk, the same plaza, fountain and timber houses, with a "
                              "humming brass device in the square and a shimmering portal hanging in the air that "
                              "shows parking lots and picket fences inside it.",
    "harmonia_inn": "Inside the Sleepy Slime Inn: a cosy tavern room with wooden tables, a hearth with a fire, "
                    "lanterns, a staircase, and the good table by the window with sunlight coming in.",
    "harmonia_shop": "Inside a medieval village shop: a counter, a rack of swords and shields on one wall, and a shelf "
                     "of wrapped, labelled spell scrolls on the other, lanterns and crates.",
}


def paint(key: str) -> Path:
    from openai import OpenAI
    r = OpenAI().images.generate(model=MODEL, prompt=f"{STYLE}\n\nThe scene: {BACKDROPS[key]}", size="1536x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json))).convert("RGB")
    STAGE.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / f"{key}_raw.png")
    h = round(raw.width * 9 / 16)
    top = (raw.height - h) // 2
    img = raw.crop((0, top, raw.width, top + h)).resize((W, H), Image.LANCZOS)
    img = img.quantize(colors=COLOURS, method=Image.MEDIANCUT).convert("RGBA")
    dst = STAGE / f"{key}.png"
    img.save(dst)
    return dst


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="*", help="backdrop keys (no names = all)")
    ap.add_argument("--deploy", action="store_true", help="copy staged backdrops into assets/cutscene_backdrops/")
    args = ap.parse_args()
    for k in args.keys or sorted(BACKDROPS):
        if k not in BACKDROPS:
            raise SystemExit(f"unknown backdrop {k}")
        if args.deploy:
            src = STAGE / f"{k}.png"
            if not src.exists():
                raise SystemExit(f"{k}: nothing staged at {src}")
            (OUT / f"{k}.png").write_bytes(src.read_bytes())
            print(f"deployed assets/cutscene_backdrops/{k}.png")
        else:
            print(f"staged {paint(k).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
