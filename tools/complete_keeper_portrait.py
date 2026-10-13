#!/usr/bin/env python3
"""Give a shop keeper's portrait the body its generation left out, keeping the face it already has.

Mortimer, the black-magic dealer, shipped as a floating face: his July generation drew a face and a few
wisps of hair on a transparent ground and no neck, shoulders or robe, though the prompt asked for all
three. On the shop's near-black panel only the face shows.

This asks gpt-image-1 to COMPLETE the shipped portrait (the portrait itself is the reference), then lays
the shipped portrait's own opaque pixels back on top, so the face the player knows is pixel-identical and
only what was missing is new. Real alpha is required from the model; nothing is keyed.

One image per run (medium, ~$0.042). The raw is kept in tmp/keeper_portrait_regen/ so a rebuild needs no call.

Usage:
    uv run --with openai --with pillow --with numpy python tools/complete_keeper_portrait.py mortimer
    uv run --with pillow --with numpy python tools/complete_keeper_portrait.py mortimer --from-raw
    python3 tools/complete_keeper_portrait.py --selftest
"""
import argparse
import base64
import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
KEEPERS = ROOT / "assets" / "sprites" / "portraits" / "keepers"
RAW_DIR = ROOT / "tmp" / "keeper_portrait_regen"
SIZE = 256
ALPHA = 128
# Eye whites: every channel at least this, and at least this many of them, or there is nothing to align on.
WHITE = 200
MIN_WHITES = 20
# What each keeper's generation left out, in the words of its own July prompt.
MISSING = {
    "mortimer": (
        "Complete this 16-bit JRPG pixel-art character portrait bust. KEEP the face exactly as it is: same "
        "position, same size, same dark brown skin, same narrow eyes, same smirk, same cyan earring. ADD what is "
        "missing: a neck, shoulders, and a high-collared deep-black merchant's robe with pale silver stitching at "
        "the neckline, filling the bottom of the frame; and FULL long straight midnight-blue hair framing the face "
        "and falling past the shoulders as solid opaque locks, not thin wisps. Bold dark outlines, soft cel "
        "shading, solid filled shapes with no see-through areas inside the figure. Fully transparent background, "
        "no scenery, no text."
    ),
}


def has_real_alpha(img: Image.Image) -> bool:
    """The model returned a cut-out, not a figure on a painted ground."""
    a = np.asarray(img.convert("RGBA"))[..., 3]
    return float((a < 16).mean()) >= 0.10 and float((a > 240).mean()) >= 0.10


def downscale(img: Image.Image, target: int = SIZE) -> Image.Image:
    img = img.convert("RGBA").resize((target * 4, target * 4), Image.LANCZOS)
    return img.resize((target, target), Image.BOX)


def eye_centre(img: Image.Image):
    """(x, y) centre of the whites of the eyes, or None when the portrait shows none."""
    a = np.asarray(img.convert("RGBA")).astype(int)
    ys, xs = np.nonzero((a[..., :3].min(axis=2) >= WHITE) & (a[..., 3] >= ALPHA))
    if len(xs) < MIN_WHITES:
        return None
    return float(xs.mean()), float(ys.mean())


def aligned(shipped: Image.Image, generated: Image.Image) -> Image.Image:
    """The generated bust moved so its eyes sit where the shipped eyes are; else its own face shows around the old one."""
    small = downscale(generated)
    was, now = eye_centre(shipped), eye_centre(small)
    if was is None or now is None:
        return small
    out = Image.new("RGBA", small.size, (0, 0, 0, 0))
    out.paste(small, (round(was[0] - now[0]), round(was[1] - now[1])))
    return out


def complete(shipped: Image.Image, generated: Image.Image) -> Image.Image:
    """The generated body with the shipped portrait's opaque pixels laid back on top, alpha hardened to on/off."""
    base = np.asarray(aligned(shipped, generated)).copy()
    base[..., 3] = np.where(base[..., 3] >= ALPHA, 255, 0)
    base[base[..., 3] == 0] = 0
    old = np.asarray(shipped.convert("RGBA"))
    keep = old[..., 3] >= ALPHA
    base[keep] = old[keep]
    base[keep, 3] = 255
    return Image.fromarray(base)


def selftest() -> int:
    shipped = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    for y in range(80, 150):
        for x in range(100, 156):
            shipped.putpixel((x, y), (120, 70, 40, 255))
    shipped.putpixel((60, 60), (10, 10, 60, 60))                      # a wisp: not opaque, not kept
    gen = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    for y in range(240, 1024):
        for x in range(200, 824):
            gen.putpixel((x, y), (12, 12, 20, 255))
    assert has_real_alpha(gen), "a cut-out with a clear ground has real alpha"
    assert not has_real_alpha(Image.new("RGBA", (64, 64), (200, 200, 200, 255))), "a painted ground is refused"
    out = complete(shipped, gen)
    assert out.getpixel((128, 100)) == (120, 70, 40, 255), "the shipped face is kept exactly"
    assert out.getpixel((128, 220))[:3] == (12, 12, 20) and out.getpixel((128, 220))[3] == 255, "the new body shows below it"
    assert out.getpixel((10, 10))[3] == 0, "the ground stays clear"
    assert out.getpixel((60, 60))[3] in (0, 255), "alpha is on or off, never half"
    a = np.asarray(out)[..., 3]
    assert set(np.unique(a).tolist()) <= {0, 255}, "no semi-transparent pixel ships"
    eyed = shipped.copy()
    for x in range(110, 146):
        for y in range(100, 104):
            eyed.putpixel((x, y), (250, 250, 250, 255))
    gen_high = gen.copy()
    for x in range(440, 584):
        for y in range(320, 336):                                    # the same eyes drawn 20px too high (at 256)
            gen_high.putpixel((x, y), (250, 250, 250, 255))
    moved = aligned(eyed, gen_high)
    assert abs(eye_centre(moved)[1] - eye_centre(eyed)[1]) <= 1.0, "the generated eyes are moved onto the shipped ones"
    assert eye_centre(shipped) is None, "a portrait with no whites has nothing to align on"
    print("selftest ok")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("keeper", nargs="?", choices=sorted(MISSING))
    ap.add_argument("--from-raw", action="store_true", help="rebuild from the kept raw, no API call")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.keeper:
        ap.error("name a keeper")
    path = KEEPERS / (args.keeper + ".png")
    shipped = Image.open(path).convert("RGBA")
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    raw_path = RAW_DIR / (args.keeper + "_body_raw.png")
    if args.from_raw:
        raw = Image.open(raw_path)
    else:
        from openai import OpenAI
        ref = io.BytesIO()
        shipped.resize((1024, 1024), Image.NEAREST).save(ref, format="PNG")
        ref.name = "portrait.png"
        ref.seek(0)
        resp = OpenAI().images.edit(model="gpt-image-1", image=ref, prompt=MISSING[args.keeper],
                                    size="1024x1024", quality="medium", background="transparent", n=1)
        raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json)))
        raw.save(raw_path)
        print("raw saved: %s (~$0.042)" % raw_path.relative_to(ROOT))
    if not has_real_alpha(raw):
        print("REFUSED: the raw has no real alpha (a painted ground); nothing is keyed here, re-roll")
        return 1
    out = complete(shipped, raw)
    out.save(path)
    print("wrote %s" % path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
