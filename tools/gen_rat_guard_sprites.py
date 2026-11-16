#!/usr/bin/env python3
"""Redraw the Rat Guard (T1) in the Cave Rat King's livery, anchored on the King's own idle frame.

struktured 2026-11-15 (via cowir-main 26105): "the rat king minions looked much worse than rat king
himself". The old rat_guard sheet is a legacy AI sheet in olive/khaki at a coarser pixel grain with a
tan ground plate; the King is grey fur, purple and gold. This draws the guard ONCE as a 3x2 pose grid
in a single gpt-image-2 edit call, with the King's frame 0 (mirrored to face right, the way an
unflipped 256px enemy sheet is authored) as the identity/style anchor.

Output: assets/sprites/monsters/rat_guard.png, 8 frames of 256x256 in the existing layout
(idle 0-1, attack 2-3, hit 4-5, dead 6-7), so the manifest's ranges and BattleScene are unchanged.
Neither the King's sheet nor any T2/T3 sheet is read for anything but the anchor, and none is written.

  uv run python tools/gen_rat_guard_sprites.py --dry-run        # prompt, anchor, cost
  uv run python tools/gen_rat_guard_sprites.py                  # one paid call, raw kept in tmp/
  uv run python tools/gen_rat_guard_sprites.py --from-raw PATH  # re-cut a kept raw, $0
"""
import argparse
import base64
import io
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MON = ROOT / "assets" / "sprites" / "monsters"
RAW_DIR = ROOT / "tmp" / "rat_guard_regen"
MODEL = "gpt-image-2"
SIZE = "1536x1024"
COST_HIGH = 0.25  # gpt-image high quality at 1536x1024, upper estimate; the response's usage is logged too
FRAME = 256
KEY = (255, 0, 255)

# Grid cells, left-to-right then top-to-bottom.
POSES = [
    "standing guard at attention, spear held upright beside him, butt on the ground",
    "the same stance one breath later, chest risen very slightly (an idle bob)",
    "winding up: spear drawn back over his shoulder, weight on the back foot, still upright",
    "thrusting: spear jabbed forward at chest height, lunging onto the front foot, still upright",
    "flinching from a blow while STILL STANDING: rocked back on his heels, spear clutched across "
    "his body, eyes squeezed shut. A stagger, not a fall: head at the top of the cell",
    "beaten: sunk onto ONE KNEE, head bowed, leaning on the planted spear. KNEELING and VERTICAL, "
    "never lying flat",
]

PROMPT = (
    "16-bit JRPG pixel-art battle sprite sheet: a 3x2 grid of six equal cells on a flat solid magenta "
    "(#FF00FF) background, one figure per cell, nothing else. The reference image is the CAVE RAT "
    "KING. Draw his ROYAL GUARD in the same art style: the SAME grey fur, the SAME pink ears and "
    "whiskers, the SAME dark outline weight, the SAME soft cel shading and pixel grain, and his "
    "colours: a deep purple tabard trimmed in gold over a short grey mail shirt, a small gold "
    "buckle, a plain round steel helm with a short purple plume (NO crown, NO cape: he is a "
    "soldier, not a king), and a SMALL SHORT SPEAR with a plain steel head (not a greatsword, not a "
    "halberd). A smaller, leaner rat than the King. Every cell shows the same guard FACING RIGHT, "
    "full body, upright, feet on the same baseline near the bottom of the cell, the same size in "
    "every cell. No ground plane, no shadow, no text, no border. Poses: "
    + " ".join(f"Cell {i + 1}: {p}." for i, p in enumerate(POSES))
)


def anchor_png() -> bytes:
    king = Image.open(MON / "cave_rat_king.png").convert("RGBA").crop((0, 0, FRAME, FRAME))
    king = king.transpose(Image.FLIP_LEFT_RIGHT)
    bg = Image.new("RGBA", king.size, KEY + (255,))
    bg.alpha_composite(king)
    buf = io.BytesIO()
    bg.resize((1024, 1024), Image.NEAREST).save(buf, format="PNG")
    return buf.getvalue()


def key_out(img: Image.Image) -> Image.Image:
    """Magenta and its anti-aliased fringe go fully transparent; everything else fully opaque."""
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, _ = px[x, y]
            if r > 150 and b > 150 and g < 120 and abs(r - b) < 90:
                px[x, y] = (0, 0, 0, 0)
    return img


def figures(raw: Image.Image) -> list:
    """The six figures as (keyed image, bbox), found as blobs, not grid cells: a thrust's spear crosses its cell."""
    import numpy as np
    from scipy import ndimage
    keyed = key_out(raw)
    mask = np.asarray(keyed.getchannel("A")) > 0
    labels, n = ndimage.label(ndimage.binary_dilation(mask, iterations=6))
    blobs = []
    for i, sl in enumerate(ndimage.find_objects(labels), start=1):
        area = int((labels[sl] == i).sum())
        if area > 4000:
            blobs.append((sl, i))
    if len(blobs) != 6:
        raise SystemExit(f"found {len(blobs)} figures, want 6")
    rows = sorted(blobs, key=lambda b: (b[0][0].start + b[0][0].stop) / 2)
    ordered = sorted(rows[:3], key=lambda b: b[0][1].start) + sorted(rows[3:], key=lambda b: b[0][1].start)
    out = []
    for sl, i in ordered:
        own = Image.fromarray(((labels == i) & mask).astype("uint8") * 255)
        fig = Image.new("RGBA", keyed.size, (0, 0, 0, 0))
        fig.paste(keyed, (0, 0), own)
        out.append((fig, own.getbbox()))
    return out


def cut(raw: Image.Image, body_h: int, baseline: int, colours: int, feet_x: int) -> list:
    """Six figures -> six 256 frames, every figure scaled by ONE factor and stood on one baseline."""
    found = figures(raw)
    cells = [f for f, _ in found]
    boxes = [b for _, b in found]
    ref_h = boxes[0][3] - boxes[0][1]  # the idle figure sets the scale for all six
    s = body_h / ref_h
    frames = []
    for c, b in zip(cells, boxes):
        fig = c.crop(b)
        fig = fig.resize((max(1, round(fig.width * s)), max(1, round(fig.height * s))), Image.LANCZOS)
        a = fig.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
        fig.putalpha(a)
        # Stand every frame on its FEET, not its bbox centre, so a thrust's spear does not slide the body.
        feet = a.crop((0, int(fig.height * 0.88), fig.width, fig.height)).getbbox()
        x = round(feet_x - (feet[0] + feet[2]) / 2)
        y = baseline - fig.height
        if y < 0 or fig.width > FRAME:
            raise SystemExit(f"figure {len(frames)} cannot fit ({fig.width}x{fig.height}): lower --body-h")
        if not 0 <= x <= FRAME - fig.width:
            fit = min(max(x, 0), FRAME - fig.width)
            print(f"  figure {len(frames)} steps {fit - x:+d}px to stay in its frame")
            x = fit
        fr = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        fr.alpha_composite(fig, (x, y))
        frames.append(fr)
    # One shared palette for all six, so no frame shifts colour from the next.
    strip = Image.new("RGBA", (FRAME * 6, FRAME), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.alpha_composite(f, (i * FRAME, 0))
    alpha = strip.getchannel("A")
    q = strip.convert("RGB").quantize(colors=colours, method=Image.MEDIANCUT).convert("RGBA")
    q.putalpha(alpha)
    return [q.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(6)]


def assemble(frames: list) -> Image.Image:
    """idle 0-1, attack 2-3, hit 4-5, dead 6-7 -> the manifest's existing ranges."""
    idle, bob, wind, thrust, flinch, kneel = frames
    order = [idle, bob, wind, thrust, flinch, idle, kneel, kneel]
    out = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    for i, f in enumerate(order):
        out.alpha_composite(f, (i * FRAME, 0))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--from-raw", type=Path)
    ap.add_argument("--body-h", type=int, default=176, help="idle figure height in px (the King's is 204)")
    ap.add_argument("--baseline", type=int, default=231, help="feet row, matched to the King's")
    ap.add_argument("--colours", type=int, default=48)
    ap.add_argument("--feet-x", type=int, default=112, help="column every frame's feet are centred on")
    ap.add_argument("--out", type=Path, default=MON / "rat_guard.png")
    args = ap.parse_args()

    if args.dry_run:
        print(PROMPT)
        print(f"\nmodel {MODEL} {SIZE} high, one call, <= ${COST_HIGH:.2f}")
        return 0
    if args.from_raw:
        raw = Image.open(args.from_raw)
    else:
        from openai import OpenAI
        RAW_DIR.mkdir(parents=True, exist_ok=True)
        r = OpenAI().images.edit(model=MODEL, image=("anchor.png", anchor_png(), "image/png"),
                                 prompt=PROMPT, size=SIZE, quality="high", n=1)
        print(f"usage: {getattr(r, 'usage', None)}")
        raw = Image.open(io.BytesIO(base64.b64decode(r.data[0].b64_json)))
        n = len(list(RAW_DIR.glob("raw*.png")))
        dst = RAW_DIR / f"raw{n}.png"
        raw.save(dst)
        print(f"raw kept: {dst.relative_to(ROOT)}")
    sheet = assemble(cut(raw, args.body_h, args.baseline, args.colours, args.feet_x))
    sheet.save(args.out)
    print(f"wrote {args.out} {sheet.size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
