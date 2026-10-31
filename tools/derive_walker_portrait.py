#!/usr/bin/env python3
"""Cut a dialogue portrait for an artist-drawn overworld villager from the artist's own walk sheet.

Rotha and Roy (the artist's villagers) spoke with the generic generated "villager" face: a different person. No
portrait was drawn for them, so theirs is cut from the sheet he did draw: the head and shoulders of the first
south-facing frame, scaled by a whole number with nearest neighbour (the only transform allowed on artist
pixels) and stood on the bottom of a 256x256 canvas, the size every dialogue portrait is.

Nothing is generated and no colour changes: every opaque pixel of the result is a colour of the sheet.

Usage:
    python3 tools/derive_walker_portrait.py            # write every listed portrait
    python3 tools/derive_walker_portrait.py --selftest
"""
import argparse
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SIZE = 256
# Share of the figure's height, from the top of the head, that makes the bust.
BUST_SHARE = 0.46
# Walkers whose hair stands tall enough that the default share ends at the eyes (Granny Kaya's bun, 2026-10-16).
BUST_SHARE_FOR = {"granny_kaya": 0.62}
# npc id -> cell size of its 4x4 walk sheet (row 0 = south).
WALKERS = {"rotha": 48, "roy": 64, "kid_acrees": 48, "granny_kaya": 48}


def bust(sheet: Image.Image, cell: int, share: float = BUST_SHARE) -> Image.Image:
    """The 256x256 portrait: head and shoulders of the first south frame, integer nearest scale, feet of the crop on the canvas floor."""
    frame = sheet.convert("RGBA").crop((0, 0, cell, cell))
    box = frame.getbbox()
    if box is None:
        raise ValueError("the first south frame is empty")
    x0, y0, x1, y1 = box
    crop = frame.crop((x0, y0, x1, y0 + max(1, round((y1 - y0) * share))))
    scale = max(1, min(SIZE // crop.width, SIZE // crop.height))
    big = crop.resize((crop.width * scale, crop.height * scale), Image.NEAREST)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(big, ((SIZE - big.width) // 2, SIZE - big.height))
    return out


def selftest() -> int:
    sheet = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    for y in range(4, 32):
        for x in range(10, 22):
            sheet.putpixel((x, y), (200, 150, 120, 255) if y < 14 else (30, 120, 90, 255))
    out = bust(sheet, 32)
    assert out.size == (SIZE, SIZE)
    colours = {p[:3] for p in out.getdata() if p[3] == 255}
    assert colours <= {(200, 150, 120), (30, 120, 90)}, "no colour the sheet does not hold"
    assert {p[3] for p in out.getdata()} <= {0, 255}, "hard alpha: nearest neighbour only"
    assert out.getbbox()[3] == SIZE, "the bust stands on the canvas floor"
    box = out.getbbox()
    assert (box[2] - box[0]) % 12 == 0 and (box[2] - box[0]) // 12 >= 2, "a whole-number scale of the 12px figure"
    try:
        bust(Image.new("RGBA", (128, 128), (0, 0, 0, 0)), 32)
        raise AssertionError("an empty frame is refused")
    except ValueError:
        pass
    print("selftest ok")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    for npc, cell in sorted(WALKERS.items()):
        src = ROOT / "assets" / "sprites" / "npcs" / npc / "overworld.png"
        dest = ROOT / "assets" / "sprites" / "portraits" / "npcs" / (npc + ".png")
        out = bust(Image.open(src), cell, BUST_SHARE_FOR.get(npc, BUST_SHARE))
        out.save(dest)
        print("%s: %s -> %s, bust %s" % (npc, src.relative_to(ROOT), dest.relative_to(ROOT), out.getbbox()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
