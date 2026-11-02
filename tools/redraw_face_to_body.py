#!/usr/bin/env python3
"""Redraw an NPC's dialogue PORTRAIT so it is the same person as the overworld BODY that walks under it (T1).

cowir-main 2026-11-01 (msg 20910, under struktured's reversibility rule): for the 10 pairs in
test_a_face_belongs_to_the_body_it_rides.PENDING_DECISION, redraw the FACE to match the BODY. A body sheet is
shared by several NPCs (one soldier sheet carries three knights); a portrait is one dialogue face.

gpt-image-2 gets two images: the current portrait (for the art style, framing and size) and the body's front
standing frame at 8x (for who the person is), plus a note of what the review found different. It answers on a
flat magenta backdrop, which is keyed out; the new bust is then scaled and placed onto the old portrait's own
bounding box, so it sits in the dialogue panel exactly where the old face did. Staged under tmp/face_redraw/;
--deploy copies staged portraits over the old ones (these are AI portraits, Batch B/D and f364f2992 -- never run
this on an artist file).

Usage:
    set -a; . ./setenv.sh; set +a
    uv run python tools/redraw_face_to_body.py knight            # stage one (or several, or none = all 10)
    uv run python tools/redraw_face_to_body.py --deploy knight   # copy the staged portrait into place
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import re
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_village_buildings import key_out  # noqa: E402  (same magenta key the buildings use)

ROOT = Path(__file__).resolve().parent.parent
STAGE = ROOT / "tmp/face_redraw"
MODEL = "gpt-image-2"

## face key -> (body sheet id, what must change so the face is the body's person)
PAIRS = {
    "nervous": ("young_woman", "a nervous YOUNG WOMAN (not a man): her hair colour and length and her dress from the "
                               "sprite; keep the worried look and the sweat drop"),
    "elder_theron": ("elder_theron", "the elder as the sprite shows him: his hair (or baldness) and his ORANGE-BROWN "
                                     "robe, not green"),
    "herbalist": ("priestess", "a priestess in the sprite's WHITE robes, with the sprite's hair colour and style"),
    "hooded_mage": ("scholar", "an ELDERLY grey-haired bespectacled scholar with no hood, as the sprite shows"),
    "adventurer": ("traveler", "a rugged MAN (masculine jaw and brow), the traveler as the sprite shows him: shoulder-"
                               "length hair, NO beard, his brown wide-brimmed hat and travel coat"),
    "apprentice": ("young_man", "the young man as the sprite shows him: DARK short hair and his facial hair and clothes"),
    "pilgrim": ("monk", "a BEARDLESS calm old monk in the sprite's orange hooded robe, his face clearly drawn under "
                        "the hood: eyes, eyebrows, nose and a gentle mouth all visible"),
    "knight": ("soldier", "a BEARDLESS soldier in the sprite's helmet and armour colours"),
    "innkeeper": ("innkeeper", "the innkeeper as the sprite shows him, WITH his moustache and his clothes"),
    "young_man": ("young_man", "the young man as the sprite shows him, with the light moustache his sprite has"),
}

PROMPT = ("Redraw the FIRST image, a 16-bit JRPG pixel-art dialogue portrait (head and shoulders), as a different "
          "person: the character in the SECOND image, a small overworld sprite of them. Keep the FIRST image's art "
          "style exactly: the same pixel-art rendering, outline weight, palette depth, lighting, bust framing, "
          "camera angle and size. Change only who it is, to match the sprite: {what}. Same sex, age, hair, facial hair "
          "and clothing colours as the sprite. No text. The background is one flat, solid, pure magenta (#FF00FF) "
          "colour with no gradient.")


def _portrait_path(face: str) -> Path:
    src = (ROOT / "src/cutscene/CutsceneDialogue.gd").read_text(encoding="utf-8")
    m = re.search(r'"%s":\s*"res://([^"]+)"' % re.escape(face), src)
    if not m:
        raise SystemExit(f"{face}: no PORTRAIT_SPRITES path in CutsceneDialogue.gd")
    return ROOT / m.group(1)


def _body_front(body: str) -> Image.Image:
    sheets = json.loads((ROOT / "data/sprite_manifest.json").read_text(encoding="utf-8"))["overworld_npc_sheets"]
    e = sheets[body]
    fh = int(e.get("frame_height", 48))
    fw = int(e.get("frame_width", fh))
    sheet = Image.open(ROOT / e["path"].replace("res://", "")).convert("RGBA")
    frame = sheet.crop((0, 0, fw, fh))
    out = Image.new("RGBA", (fw * 8 + 64, fh * 8 + 64), (255, 0, 255, 255))
    big = frame.resize((fw * 8, fh * 8), Image.NEAREST)
    out.alpha_composite(big, (32, 32))
    return out


def _png(img: Image.Image, name: str):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    buf.seek(0)
    return (name, buf, "image/png")


def redraw(face: str) -> Path:
    from openai import OpenAI
    body, what = PAIRS[face]
    old = Image.open(_portrait_path(face)).convert("RGBA")
    flat = Image.new("RGBA", old.size, (255, 0, 255, 255))
    flat.alpha_composite(old)
    r = OpenAI().images.edit(model=MODEL, image=[_png(flat, "portrait.png"), _png(_body_front(body), "sprite.png")],
                             prompt=PROMPT.format(what=what), size="1024x1024", n=1)
    raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json))).convert("RGBA")
    STAGE.mkdir(parents=True, exist_ok=True)
    raw.save(STAGE / f"{face}_raw.png")
    keyed = key_out(raw)
    bb_new = keyed.getbbox()
    bb_old = old.getbbox()
    bust = keyed.crop(bb_new)
    w_old, h_old = bb_old[2] - bb_old[0], bb_old[3] - bb_old[1]
    s = min(w_old / bust.width, h_old / bust.height)
    bust = bust.resize((max(1, round(bust.width * s)), max(1, round(bust.height * s))), Image.LANCZOS)
    bust.putalpha(bust.split()[3].point(lambda v: 255 if v >= 128 else 0))
    out = Image.new("RGBA", old.size, (0, 0, 0, 0))
    x = bb_old[0] + (w_old - bust.width) // 2
    y = bb_old[3] - bust.height  # bottom-aligned: the bust's shoulders sit where the old ones did
    out.alpha_composite(bust, (x, y))
    dst = STAGE / f"{face}.png"
    out.save(dst)
    return dst


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("faces", nargs="*", help="face keys (default: all 10 pending)")
    ap.add_argument("--deploy", action="store_true", help="copy the staged portrait(s) over the old one(s)")
    args = ap.parse_args()
    faces = args.faces or sorted(PAIRS)
    for f in faces:
        if f not in PAIRS:
            raise SystemExit(f"{f} is not one of the pending pairs")
        if args.deploy:
            src, dst = STAGE / f"{f}.png", _portrait_path(f)
            if not src.exists():
                raise SystemExit(f"{f}: nothing staged at {src}")
            dst.write_bytes(src.read_bytes())
            print(f"deployed {dst.relative_to(ROOT)}")
        else:
            print(f"staged {redraw(f).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
