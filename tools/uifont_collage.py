#!/usr/bin/env python3
"""Before/after sheets for the font change: tools/uifont_collage.py SHOTS_DIR OUT_DIR
SHOTS_DIR holds one folder per variant (before, after_default, after_pixel, ...), each with the same NAME.png files.
Writes OUT_DIR/NAME.png (the variants side by side, labelled) and says which frames are missing or identical."""
import os, sys
from PIL import Image, ImageChops, ImageDraw

LABELS = {"before": "BEFORE (.792)", "after_default": "PIXEL FACE, reading text kept", "after_pixel": "PIXEL FACE everywhere"}

def main(shots, out):
    os.makedirs(out, exist_ok=True)
    variants = [v for v in ("before", "after_default", "after_pixel") if os.path.isdir(os.path.join(shots, v))]
    names = sorted({f for v in variants for f in os.listdir(os.path.join(shots, v)) if f.endswith(".png")})
    for name in names:
        ims = []
        for v in variants:
            p = os.path.join(shots, v, name)
            if not os.path.exists(p):
                print(f"MISSING {v}/{name}"); continue
            ims.append((v, Image.open(p).convert("RGB")))
        if len(ims) < 2:
            continue
        base = ims[0][1]
        for v, im in ims[1:]:
            same = im.size == base.size and ImageChops.difference(base, im).getbbox() is None
            print(f"{name}: {v} vs {ims[0][0]}: {'IDENTICAL (the face did not change this frame)' if same else 'differs'}")
        w, h = base.size
        bar = 28
        sheet = Image.new("RGB", (w * len(ims) + 8 * (len(ims) - 1), h + bar), (18, 16, 28))
        d = ImageDraw.Draw(sheet)
        for i, (v, im) in enumerate(ims):
            x = i * (w + 8)
            d.text((x + 8, 8), LABELS.get(v, v), fill=(240, 236, 220))
            sheet.paste(im, (x, bar))
        sheet.save(os.path.join(out, name))
        print("wrote", os.path.join(out, name), sheet.size)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
