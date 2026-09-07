"""
Extract cleric sprite frames from Cleric_extended.aseprite source.

Aseprite tags (verified via `aseprite --batch --list-tags`):
    idle  : frames 0-3  (pingpong)
    cast  : frames 4-9  (forward)
    walk  : frames 10-15 (forward)

Each source frame is 630x400 with the character occupying the top-left 128x128
region; the rest is purple (138, 83, 114) background fill from the aseprite canvas.

Output: per-animation PNG strips in assets/sprites/jobs/cleric/ at 256x256 frame
size (2x NN upscale from 128x128 source). Background stripped to transparency.

Run from repo root after exporting the aseprite sheet:
    aseprite --batch assets/sprites/jobs/aseprite/Cleric_extended.aseprite \
             --sheet tmp/aseprite_export/Cleric_extended_sheet.png
    python3 tools/extract_cleric_aseprite.py
"""
from PIL import Image
import numpy as np
import sys
import os

SRC = "tmp/aseprite_export/Cleric_extended_sheet.png"
OUT_DIR = "assets/sprites/jobs/cleric"
FRAME_W = 128  # character bbox width in source
FRAME_H = 128  # character bbox height in source
SRC_FRAME_STRIDE = 630  # source cell width (630x400 canvases)

# Aseprite canvas background (approx)
BG_R, BG_G, BG_B = 138, 83, 114
BG_TOLERANCE = 25  # Manhattan distance for anti-aliased edges

# Aseprite tag -> (frames list, output filename)
ANIMATIONS = {
    "idle":   (list(range(0, 4)),   "idle.png"),
    "attack": (list(range(4, 10)),  "attack.png"),  # No dedicated attack — cast doubles
    "cast":   (list(range(4, 10)),  "cast.png"),
    "walk":   (list(range(10, 16)), "walk.png"),
}


def strip_background(frame: Image.Image) -> Image.Image:
    """Replace purple bg with transparency."""
    arr = np.array(frame)
    r = arr[:, :, 0].astype(int)
    g = arr[:, :, 1].astype(int)
    b = arr[:, :, 2].astype(int)
    dist = np.abs(r - BG_R) + np.abs(g - BG_G) + np.abs(b - BG_B)
    bg_mask = dist < BG_TOLERANCE
    arr[:, :, 3] = np.where(bg_mask, 0, arr[:, :, 3])
    return Image.fromarray(arr, "RGBA")


def extract_frame(sheet: Image.Image, n: int) -> Image.Image:
    """Extract character region from frame N and scale 2x NN."""
    crop = sheet.crop(
        (n * SRC_FRAME_STRIDE, 0,
         n * SRC_FRAME_STRIDE + FRAME_W, FRAME_H)
    )
    crop = strip_background(crop)
    return crop.resize((256, 256), Image.NEAREST)


def build_strip(sheet: Image.Image, frame_indices: list, out_path: str) -> None:
    n = len(frame_indices)
    strip = Image.new("RGBA", (256 * n, 256), (0, 0, 0, 0))
    for i, fi in enumerate(frame_indices):
        strip.paste(extract_frame(sheet, fi), (i * 256, 0))
    strip.save(out_path)
    print(f"  {out_path:55s} {strip.size[0]:5d}x256  ({n} frames)")


def main() -> int:
    if not os.path.exists(SRC):
        print(f"ERROR: {SRC} not found. Run aseprite export first:", file=sys.stderr)
        print("  aseprite --batch assets/sprites/jobs/aseprite/Cleric_extended.aseprite \\",
              file=sys.stderr)
        print(f"           --sheet {SRC}", file=sys.stderr)
        return 1

    sheet = Image.open(SRC).convert("RGBA")
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Extracting cleric sprites (source: {SRC}):")
    for name, (frames, out_name) in ANIMATIONS.items():
        build_strip(sheet, frames, os.path.join(OUT_DIR, out_name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
