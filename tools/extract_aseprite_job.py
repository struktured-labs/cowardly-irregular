"""
Generic aseprite-to-sprite-sheet extractor for job animations.

Reads an aseprite source with frameTags and exports each tag as a
separate horizontal sprite strip at 256x256 frames (2x NN upscale from
the 128x128 character region).

Usage:
    # 1) Export the aseprite sheet:
    aseprite --batch --list-tags --data tmp/<job>_tags.json \
             assets/sprites/jobs/aseprite/<File>.aseprite \
             --sheet tmp/aseprite_export/<job>_sheet.png

    # 2) Run extraction:
    python3 tools/extract_aseprite_job.py \
        --sheet tmp/aseprite_export/cleric_sheet.png \
        --tags tmp/cleric_tags.json \
        --out assets/sprites/jobs/cleric \
        --char-bbox 128 128 \
        --frame-stride 630 \
        --bg-color 138 83 114

Key parameters:
    --char-bbox W H      Character bounding box in source frame (default 128 128)
    --frame-stride N     Source frame stride in pixels (aseprite canvas width)
                         Default is --char-bbox width (i.e. tight packing).
    --bg-color R G B     Background color to strip (if canvas has fill bg);
                         omit to preserve alpha channel as-is.
    --bg-tolerance N     Manhattan-distance tolerance for bg stripping (default 25)
    --scale N            Output upscale factor (default 2 for 128->256)
    --tag-aliases JSON   Dict mapping tag names to output filenames
                         e.g. '{"cast":"attack.png","cast":"cast.png"}' to write cast twice

Produces one PNG per aseprite tag in the output directory.
"""
import argparse
import json
import os
import sys
from typing import Optional
from PIL import Image
import numpy as np


def strip_background(frame: Image.Image, bg: tuple[int, int, int], tol: int) -> Image.Image:
    """Replace a canvas background color with transparency."""
    arr = np.array(frame)
    r = arr[:, :, 0].astype(int)
    g = arr[:, :, 1].astype(int)
    b = arr[:, :, 2].astype(int)
    dist = np.abs(r - bg[0]) + np.abs(g - bg[1]) + np.abs(b - bg[2])
    bg_mask = dist < tol
    arr[:, :, 3] = np.where(bg_mask, 0, arr[:, :, 3])
    return Image.fromarray(arr, "RGBA")


def extract_frame(
    sheet: Image.Image,
    n: int,
    frame_stride: int,
    char_w: int,
    char_h: int,
    scale: int,
    bg: Optional[tuple[int, int, int]],
    bg_tol: int,
) -> Image.Image:
    """Crop the character region from frame n and upscale NN."""
    x0 = n * frame_stride
    frame = sheet.crop((x0, 0, x0 + char_w, char_h))
    if bg is not None:
        frame = strip_background(frame, bg, bg_tol)
    return frame.resize((char_w * scale, char_h * scale), Image.NEAREST)


def main():
    ap = argparse.ArgumentParser(description="Extract aseprite frames to per-tag PNG strips")
    ap.add_argument("--sheet", required=True, help="Input aseprite sheet PNG (exported via aseprite CLI)")
    ap.add_argument("--tags", required=True, help="JSON metadata file with frameTags (from aseprite --list-tags --data)")
    ap.add_argument("--out", required=True, help="Output directory for animation strips")
    ap.add_argument("--char-bbox", type=int, nargs=2, metavar=("W", "H"), default=[128, 128],
                    help="Character bbox in source frame (default 128 128)")
    ap.add_argument("--frame-stride", type=int, default=None,
                    help="Source frame stride (default = char-bbox width, for tight packing)")
    ap.add_argument("--bg-color", type=int, nargs=3, metavar=("R", "G", "B"), default=None,
                    help="Canvas background color to strip (default: none, preserve alpha)")
    ap.add_argument("--bg-tolerance", type=int, default=25,
                    help="Manhattan distance tolerance for bg stripping (default 25)")
    ap.add_argument("--scale", type=int, default=2,
                    help="NN upscale factor (default 2 for 128->256)")
    ap.add_argument("--tag-aliases", type=str, default=None,
                    help='JSON dict mapping tag names to filenames, e.g. \'{"cast":"attack.png"}\'')
    args = ap.parse_args()

    if not os.path.exists(args.sheet):
        print(f"ERROR: sheet not found: {args.sheet}", file=sys.stderr)
        return 1
    if not os.path.exists(args.tags):
        print(f"ERROR: tags file not found: {args.tags}", file=sys.stderr)
        return 1

    with open(args.tags) as f:
        meta = json.load(f)

    frame_tags = meta.get("meta", {}).get("frameTags", [])
    if not frame_tags:
        print("ERROR: No frameTags found in meta. Did you use --list-tags during export?", file=sys.stderr)
        return 1

    char_w, char_h = args.char_bbox
    frame_stride = args.frame_stride if args.frame_stride else char_w

    aliases: dict[str, list[str]] = {}
    if args.tag_aliases:
        raw = json.loads(args.tag_aliases)
        for k, v in raw.items():
            if isinstance(v, list):
                aliases[k] = v
            else:
                aliases[k] = [v]

    sheet = Image.open(args.sheet).convert("RGBA")
    os.makedirs(args.out, exist_ok=True)

    print(f"Extracting from {args.sheet} ({sheet.size[0]}x{sheet.size[1]}) -> {args.out}:")
    print(f"  char bbox {char_w}x{char_h}, stride {frame_stride}, scale {args.scale}x")

    bg = tuple(args.bg_color) if args.bg_color else None
    if bg:
        print(f"  stripping bg RGB{bg} (tol={args.bg_tolerance})")

    out_size = (char_w * args.scale, char_h * args.scale)
    for tag in frame_tags:
        name = tag["name"]
        frames = list(range(tag["from"], tag["to"] + 1))
        n = len(frames)
        strip = Image.new("RGBA", (out_size[0] * n, out_size[1]), (0, 0, 0, 0))
        for i, fi in enumerate(frames):
            frame_img = extract_frame(sheet, fi, frame_stride, char_w, char_h, args.scale, bg, args.bg_tolerance)
            strip.paste(frame_img, (i * out_size[0], 0))

        # Determine output filenames (primary + aliases)
        out_names = aliases.get(name, [f"{name}.png"])
        for fname in out_names:
            out_path = os.path.join(args.out, fname)
            strip.save(out_path)
            print(f"  {out_path:60s} {strip.size[0]}x{strip.size[1]}  ({n} frames, tag={name})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
