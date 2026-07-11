#!/usr/bin/env python3
"""Generate named-NPC overworld chibi sheets from their battle strips.

Work order (cowir-cutscenes msg 2342, struktured-approved): story
principals need their OWN 32px overworld walk sheets so staged
cutscenes read as THEM instead of generic archetypes.

Unlike gen_overworld_gpt_image.py (which anchors identity to artist
.aseprite files), named NPCs anchor to their existing 2048×256 battle
strips in the game repo — those ARE the identity canon.

Per NPC, two refs:
  1. identity — battle strip frame 0 (phil: traveler archetype sheet,
     he has no strip; persona carries the identity)
  2. format — the archetype overworld sheet the NPC currently renders
     as (byte-format anchor: 128×128 4×4 chibi grid)

Then: ow.PROMPT_TEMPLATE → gpt-image-1 → ow.assemble_game_grid →
assets/sprites/npcs/<name>/overworld.png (dr_temporal precedent —
path-convention loading, no manifest entry).

DON'T wire consumers: cowir-cutscenes flips HarmoniaVillage
sprite_archetype overrides + HARMONIA_NPC_CANON in one commit on ping.

Usage:
    uv run python tools/gen_named_npc_overworld.py elder_theron scholar_milo
    uv run python tools/gen_named_npc_overworld.py --all --quality high
    uv run python tools/gen_named_npc_overworld.py phil --dry-run
"""
import argparse
import base64
import io
import os
import sys
from pathlib import Path

from openai import OpenAI
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT))
from tools import gen_overworld_gpt_image as ow

GAME_REPO = Path(os.environ.get(
    "GAME_REPO",
    "/home/struktured/projects/cowardly-irregular-artist-ship"
))
NPCS = GAME_REPO / "assets" / "sprites" / "npcs"
OUT_TMP = PROJECT / "tmp" / "named_npc_overworld"
OUT_TMP.mkdir(parents=True, exist_ok=True)

COST = {"low": 0.011, "medium": 0.042, "high": 0.167}

# name → (identity anchor, format-archetype dir, char_desc)
# identity anchor: battle-strip filename in npcs/, or None (phil)
NAMED_NPCS = {
    "elder_theron": {
        "strip": "elder_theron.png",
        "archetype": "old_man",
        "char_desc": (
            "hunched village elder with white hair and a full white beard, "
            "long dark-green coat-robe down to his boots, leaning on a tall "
            "wooden walking staff, slow dignified posture"
        ),
    },
    "scholar_milo": {
        "strip": "scholar_milo.png",
        "archetype": "scholar",
        "char_desc": (
            "young scholar with a brown mop of hair and large black round "
            "glasses, light-blue ankle-length robe over white, clutching a "
            "small red book to his chest, brown shoes, earnest posture"
        ),
    },
    "phil": {
        "strip": None,  # no battle strip — traveler archetype + persona
        "archetype": "traveler",
        "char_desc": (
            "weary lost wanderer with a shabby brown traveling cloak, "
            "shapeless brown hat, small knapsack, walking stick, slightly "
            "confused hesitant posture — a man who is perpetually not "
            "quite sure this is the right road"
        ),
    },
    "bram": {
        "strip": "bram.png",
        "archetype": "blacksmith",
        "char_desc": (
            "burly cheerful blacksmith with short brown hair and a trimmed "
            "brown beard, white shirt with rolled-up sleeves, dark-brown "
            "leather apron from chest to knees, heavy boots, broad grin"
        ),
    },
    "marta": {
        "strip": "marta.png",
        "archetype": "innkeeper",
        "char_desc": (
            "kind innkeeper woman with brown hair tied back under a white "
            "headband kerchief, red short-sleeved blouse, long cream apron "
            "dress, dark shoes, warm attentive posture"
        ),
    },
}


def identity_ref_bytes(cfg: dict) -> bytes:
    if cfg["strip"]:
        strip = Image.open(NPCS / cfg["strip"]).convert("RGBA")
        H = strip.size[1]
        frame = strip.crop((0, 0, H, H))  # square frame 0
    else:
        # phil: the traveler archetype sheet is the closest identity canon
        frame = Image.open(NPCS / cfg["archetype"] / "overworld.png").convert("RGBA")
    return ow.pad_to_square(frame, 1024)


def format_ref_bytes(cfg: dict) -> bytes:
    sheet = Image.open(NPCS / cfg["archetype"] / "overworld.png").convert("RGBA")
    return ow.pad_to_square(sheet, 1024)


def gen_one(client, name: str, quality: str) -> None:
    cfg = NAMED_NPCS[name]
    prompt = ow.PROMPT_TEMPLATE.format(char_desc=cfg["char_desc"])
    print(f"[{name}] gpt-image-1 ({quality}, ${COST[quality]}) "
          f"anchor={'strip' if cfg['strip'] else 'archetype:' + cfg['archetype']}")
    resp = client.images.edit(
        model="gpt-image-1",
        image=[
            ("ref_identity.png", identity_ref_bytes(cfg), "image/png"),
            ("ref_chibi_format.png", format_ref_bytes(cfg), "image/png"),
        ],
        prompt=prompt,
        size="1024x1024",
        quality=quality,
        n=1,
    )
    raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json))).convert("RGBA")
    raw.save(OUT_TMP / f"{name}_raw_1024.png")

    grid = ow.assemble_game_grid(raw, target=32)
    dest_dir = NPCS / name
    dest_dir.mkdir(parents=True, exist_ok=True)
    out = dest_dir / "overworld.png"
    grid.save(out)
    print(f"  → {out.relative_to(GAME_REPO)}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*", help="named NPCs; --all for the full order")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="high")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    names = list(NAMED_NPCS.keys()) if args.all else args.names
    unknown = [n for n in names if n not in NAMED_NPCS]
    if unknown:
        print(f"ERROR: unknown NPCs {unknown}; known: {list(NAMED_NPCS)}")
        return 1
    if not names:
        print("nothing to do — pass names or --all")
        return 1

    if args.dry_run:
        for n in names:
            cfg = NAMED_NPCS[n]
            print(f"would gen {n}: anchor={cfg['strip'] or 'archetype'}, "
                  f"format={cfg['archetype']}, ${COST[args.quality]}")
        print(f"total ~${COST[args.quality] * len(names):.2f}")
        return 0

    client = OpenAI()
    for n in names:
        try:
            gen_one(client, n, args.quality)
        except Exception as e:
            print(f"  FAILED {n}: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
