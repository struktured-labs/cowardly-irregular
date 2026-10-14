#!/usr/bin/env python3
"""Redraw a generated dialogue portrait so it shows the person its walk sprite shows.

Found 2026-10-13 by laying all 31 villager sheets beside their portraits: the sprite and the face were generated
months apart from different prompts, and for some they are different people. The merchant walks bare-headed in a
green apron with dark hair and a moustache; his portrait wore a red beret and a red coat. About thirty keepers
and merchants speak with that face, and since .681 their shop screen shows it too.

The WALK SPRITE is the reference (it is what stands in the world): its first south frame, enlarged, is given to
gpt-image-1 with one shipped portrait as the style guide, and real alpha is asked for (no white key: the key is
what cost earlier portraits their eye whites and shirts). One image per run, medium, about $0.042. The raw is
kept in tmp/portrait_match/ so a rebuild needs no call. T1 only: never run on an artist-derived portrait.

Usage:
    uv run --with openai --with pillow --with numpy python tools/match_portrait_to_walker.py merchant
    uv run --with pillow --with numpy python tools/match_portrait_to_walker.py merchant --from-raw
    python3 tools/match_portrait_to_walker.py --selftest
"""
import argparse
import base64
import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "tmp" / "portrait_match"
STYLE = ROOT / "assets" / "sprites" / "portraits" / "npcs" / "blacksmith.png"
SIZE = 256
ALPHA = 128
PROMPT = (
    "Image 1 is the STYLE to match: a 16-bit JRPG pixel-art dialogue portrait bust, bold dark outlines, soft cel "
    "shading, head and shoulders facing the viewer. Image 2 is a tiny game sprite of a DIFFERENT character. Draw a "
    "new portrait bust, in the style of image 1, of the character in image 2: %s Take ONLY the hair, facial hair "
    "and clothing from image 2. Take the drawing from image 1: an adult face with the same fine pixel detail, the "
    "same proportions, detailed eyes with whites and pupils, a shaded nose; NOT a chibi, NOT dot eyes, NOT a big "
    "round head. Same framing and scale as image 1, "
    "shoulders filling the bottom of the frame edge to edge, solid filled shapes with no see-through areas inside "
    "the figure. Fully transparent background, no scenery, no text, no border."
)
# archetype -> what the sprite shows, in words, so the model does not have to read 32 pixels alone.
WHO = {
    "merchant": (
        "a friendly shopkeeper man with short dark-brown hair, NO hat, a dark moustache, light skin, wearing a "
        "green apron over a cream long-sleeved shirt with a brown belt."
    ),
}


def has_real_alpha(img: Image.Image) -> bool:
    a = np.asarray(img.convert("RGBA"))[..., 3]
    return float((a < 16).mean()) >= 0.10 and float((a > 240).mean()) >= 0.10


def finish(raw: Image.Image) -> Image.Image:
    """256x256, alpha hardened to on/off, and the bust dropped onto the frame's lower edge."""
    img = raw.convert("RGBA").resize((SIZE * 4, SIZE * 4), Image.LANCZOS).resize((SIZE, SIZE), Image.BOX)
    px = np.asarray(img).copy()
    px[..., 3] = np.where(px[..., 3] >= ALPHA, 255, 0)
    px[px[..., 3] == 0] = 0
    rows = np.nonzero((px[..., 3] > 0).any(axis=1))[0]
    out = np.zeros_like(px)
    if len(rows):
        drop = SIZE - 1 - int(rows.max())
        out[drop:] = px[:SIZE - drop]
    return Image.fromarray(out)


def selftest() -> int:
    raw = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    for y in range(200, 900):
        for x in range(300, 724):
            raw.putpixel((x, y), (60, 140, 80, 255))
    assert has_real_alpha(raw) and not has_real_alpha(Image.new("RGBA", (64, 64), (255, 255, 255, 255)))
    out = finish(raw)
    a = np.asarray(out)[..., 3]
    assert out.size == (SIZE, SIZE) and set(np.unique(a).tolist()) <= {0, 255}, "256px, hard alpha"
    assert a[SIZE - 1].any(), "the bust stands on the lower edge"
    assert not a[0].any(), "and the space it left is at the top"
    print("selftest ok")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("archetype", nargs="?", choices=sorted(WHO))
    ap.add_argument("--from-raw", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.archetype:
        ap.error("name an archetype")
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    raw_path = RAW_DIR / (args.archetype + "_raw.png")
    dest = ROOT / "assets" / "sprites" / "portraits" / "npcs" / (args.archetype + ".png")
    if args.from_raw:
        raw = Image.open(raw_path)
    else:
        from openai import OpenAI
        sheet = Image.open(ROOT / "assets" / "sprites" / "npcs" / args.archetype / "overworld.png").convert("RGBA")
        frame = sheet.crop((0, 0, 32, 32)).resize((1024, 1024), Image.NEAREST)
        refs = []
        for name, im in (("style.png", Image.open(STYLE).convert("RGBA").resize((1024, 1024), Image.NEAREST)), ("sprite.png", frame)):
            buf = io.BytesIO()
            im.save(buf, format="PNG")
            buf.name = name
            buf.seek(0)
            refs.append(buf)
        resp = OpenAI().images.edit(model="gpt-image-1", image=refs, prompt=PROMPT % WHO[args.archetype],
                                    size="1024x1024", quality="medium", background="transparent", n=1)
        raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json)))
        raw.save(raw_path)
        print("raw saved: %s (~$0.042)" % raw_path.relative_to(ROOT))
    if not has_real_alpha(raw):
        print("REFUSED: no real alpha in the raw (a painted ground); re-roll")
        return 1
    finish(raw).save(dest)
    print("wrote %s" % dest.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
