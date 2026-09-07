#!/usr/bin/env python3
"""
Export artist Aseprite files to game-ready 256x256 sprite strips.

Scaling Rule:
  1. Export per animation tag via aseprite CLI
  2. Remove background (alpha < 240 + color match, edge flood-fill)
  3. Crop to opaque bounding box
  4. Scale with NEAREST to fill 85% of 256px frame
  5. Center horizontally, foot-align at 92% (8% bottom padding)
  6. Assemble horizontal strip

Usage:
    uv run python tools/export_aseprite_sprites.py assets/sprites/jobs/aseprite/Cleric_extended.aseprite --output-dir assets/sprites/jobs/cleric_artist
    uv run python tools/export_aseprite_sprites.py "Mage Main design.aseprite" --tags idle cast walk --frame-size 256
    uv run python tools/export_aseprite_sprites.py *.aseprite --output-dir assets/sprites/jobs/{stem}
"""

import argparse
import subprocess
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

FRAME_SIZE = 256
FILL_RATIO = 0.85
BOTTOM_PAD_RATIO = 0.08
BG_ALPHA_THRESHOLD = 240
BG_COLOR_TOLERANCE = 50


def list_tags(aseprite_path: Path) -> list[str]:
    """List animation tags in an Aseprite file."""
    result = subprocess.run(
        ["aseprite", "-b", "--list-tags", str(aseprite_path)],
        capture_output=True, text=True,
    )
    tags = [t.strip() for t in result.stdout.strip().split("\n") if t.strip()]
    return tags


def export_tag_frames(aseprite_path: Path, tag: str, tmp_dir: Path) -> list[Path]:
    """Export all frames for a tag as individual PNGs."""
    tmp_dir.mkdir(parents=True, exist_ok=True)
    # Clean previous exports
    for old in tmp_dir.glob("frame_*.png"):
        old.unlink()

    subprocess.run(
        ["aseprite", "-b", str(aseprite_path),
         "--tag", tag,
         "--save-as", str(tmp_dir / "frame_{frame}.png")],
        capture_output=True,
    )
    return sorted(tmp_dir.glob("frame_*.png"))


def detect_bg_color(img: Image.Image) -> np.ndarray | None:
    """Detect the dominant background color from the border of an image."""
    arr = np.array(img.convert("RGBA"))
    h, w = arr.shape[:2]

    border_pixels = []
    for x in range(w):
        border_pixels.append(arr[0, x, :3])
        border_pixels.append(arr[h - 1, x, :3])
    for y in range(h):
        border_pixels.append(arr[y, 0, :3])
        border_pixels.append(arr[y, w - 1, :3])

    border_tuples = [tuple(int(v) for v in p) for p in border_pixels]
    counts = Counter(border_tuples)
    if not counts:
        return None
    return np.array(counts.most_common(1)[0][0], dtype=float)


def remove_background(img: Image.Image, alpha_threshold: int = BG_ALPHA_THRESHOLD,
                       color_tolerance: int = BG_COLOR_TOLERANCE,
                       bg_color: np.ndarray = None) -> Image.Image:
    """Remove background using alpha + color match with edge flood-fill.

    Args:
        bg_color: Pre-computed background color. If None, detected from borders.
    """
    arr = np.array(img.convert("RGBA")).copy()
    h, w = arr.shape[:2]

    # Detect or use provided bg color
    if bg_color is None:
        bg_color = detect_bg_color(img)
    if bg_color is None:
        return img

    # First: make fully transparent pixels (alpha=0) actually transparent
    # Then: within the opaque region, flood-fill remove bg-colored pixels
    # from the edges of the opaque bounding box

    opaque = arr[:, :, 3] > 10
    if not opaque.any():
        return img

    # Find bounding box of opaque content
    ys, xs = np.where(opaque)
    y0, y1 = ys.min(), ys.max() + 1
    x0, x1 = xs.min(), xs.max() + 1

    # Within the opaque region, remove ALL pixels matching bg color.
    # The artist's bg color (e.g. pink RGB 138,83,114) is distinct enough
    # from character colors that direct color matching is safe — no flood
    # fill needed. The character sits ON TOP of the bg, so flood fill from
    # edges can't reach bg pixels behind the character anyway.
    region = arr[y0:y1, x0:x1]
    region_rgb = region[:, :, :3].astype(float)
    color_dist = np.sqrt(((region_rgb - bg_color) ** 2).sum(axis=2))
    bg_pixels = color_dist < color_tolerance
    region[bg_pixels, 3] = 0
    arr[y0:y1, x0:x1] = region

    # Also ensure originally transparent pixels stay transparent
    arr[arr[:, :, 3] < alpha_threshold, 3] = 0

    return Image.fromarray(arr)


def crop_to_content(img: Image.Image) -> Image.Image:
    """Crop to bounding box of opaque pixels."""
    arr = np.array(img)
    mask = arr[:, :, 3] > 10
    if not mask.any():
        return img
    ys, xs = np.where(mask)
    return img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def center_on_canvas(sprite: Image.Image, frame_size: int = FRAME_SIZE,
                     fill_ratio: float = FILL_RATIO,
                     bottom_pad: float = BOTTOM_PAD_RATIO) -> Image.Image:
    """Scale and center sprite on transparent canvas, foot-aligned.

    - Scale with NEAREST to fill `fill_ratio` of the frame
    - Center horizontally
    - Foot-align vertically (bottom edge at `1 - bottom_pad` of canvas)
    """
    sw, sh = sprite.size
    if sw == 0 or sh == 0:
        return Image.new("RGBA", (frame_size, frame_size), (0, 0, 0, 0))

    target = int(frame_size * fill_ratio)
    scale = min(target / sw, target / sh)
    new_w = max(1, int(sw * scale))
    new_h = max(1, int(sh * scale))
    scaled = sprite.resize((new_w, new_h), Image.NEAREST)

    canvas = Image.new("RGBA", (frame_size, frame_size), (0, 0, 0, 0))
    x_off = (frame_size - new_w) // 2
    y_off = frame_size - new_h - int(frame_size * bottom_pad)
    y_off = max(0, y_off)
    canvas.paste(scaled, (x_off, y_off), scaled)
    return canvas


def process_tag(aseprite_path: Path, tag: str, output_dir: Path,
                frame_size: int = FRAME_SIZE,
                fill_ratio: float = FILL_RATIO,
                bg_tolerance: int = BG_COLOR_TOLERANCE) -> Path:
    """Export one animation tag to a horizontal strip PNG."""
    tmp_dir = output_dir / ".tmp" / tag
    frame_files = export_tag_frames(aseprite_path, tag, tmp_dir)

    if not frame_files:
        print(f"  SKIP {tag}: no frames exported")
        return None

    # Detect bg color from the OPAQUE CONTENT REGION borders across all frames.
    # The canvas borders are often transparent (alpha=0), so sampling them
    # gives (0,0,0) which is wrong. Instead, find the opaque bounding box
    # and sample from ITS edges.
    all_bg_colors = Counter()
    for fp in frame_files:
        img = Image.open(fp).convert("RGBA")
        arr = np.array(img)
        opaque = arr[:, :, 3] > 10
        if not opaque.any():
            continue
        ys, xs = np.where(opaque)
        y0, y1 = ys.min(), ys.max() + 1
        x0, x1 = xs.min(), xs.max() + 1
        region = arr[y0:y1, x0:x1]
        rh, rw = region.shape[:2]
        for x in range(rw):
            all_bg_colors[tuple(int(v) for v in region[0, x, :3])] += 1
            all_bg_colors[tuple(int(v) for v in region[rh-1, x, :3])] += 1
        for y in range(rh):
            all_bg_colors[tuple(int(v) for v in region[y, 0, :3])] += 1
            all_bg_colors[tuple(int(v) for v in region[y, rw-1, :3])] += 1

    shared_bg = np.array(all_bg_colors.most_common(1)[0][0], dtype=float) if all_bg_colors else None
    if shared_bg is not None:
        print(f"  Detected bg color: RGB({shared_bg[0]:.0f},{shared_bg[1]:.0f},{shared_bg[2]:.0f})")

    processed = []
    for fp in frame_files:
        img = Image.open(fp).convert("RGBA")
        clean = remove_background(img, color_tolerance=bg_tolerance, bg_color=shared_bg)
        cropped = crop_to_content(clean)
        centered = center_on_canvas(cropped, frame_size, fill_ratio)
        processed.append(centered)

    # Assemble horizontal strip
    strip = Image.new("RGBA", (frame_size * len(processed), frame_size), (0, 0, 0, 0))
    for i, frame in enumerate(processed):
        strip.paste(frame, (i * frame_size, 0))

    out_path = output_dir / f"{tag}.png"
    strip.save(out_path)

    # Verify transparency
    arr = np.array(strip)
    trans_pct = (arr[:, :, 3] == 0).sum() / (arr.shape[0] * arr.shape[1]) * 100
    print(f"  {tag}: {len(processed)} frames, {strip.size[0]}x{strip.size[1]}, {trans_pct:.0f}% transparent")
    return out_path


def main():
    parser = argparse.ArgumentParser(
        description="Export Aseprite files to game-ready 256x256 sprite strips."
    )
    parser.add_argument("aseprite_files", nargs="+", type=Path,
                        help="Aseprite file(s) to export")
    parser.add_argument("--output-dir", type=Path, default=None,
                        help="Output directory. Use {stem} for the input filename stem. "
                             "Default: tmp/exported/{stem}")
    parser.add_argument("--tags", nargs="+", default=None,
                        help="Specific tags to export (default: all tags in file)")
    parser.add_argument("--frame-size", type=int, default=FRAME_SIZE,
                        help=f"Output frame size in pixels (default: {FRAME_SIZE})")
    parser.add_argument("--fill-ratio", type=float, default=FILL_RATIO,
                        help=f"Character fill ratio (default: {FILL_RATIO})")
    parser.add_argument("--bg-tolerance", type=int, default=BG_COLOR_TOLERANCE,
                        help=f"Background color match tolerance (default: {BG_COLOR_TOLERANCE})")
    args = parser.parse_args()

    for aseprite_path in args.aseprite_files:
        if not aseprite_path.exists():
            print(f"ERROR: {aseprite_path} not found", file=sys.stderr)
            continue

        stem = aseprite_path.stem
        if args.output_dir:
            out_dir = Path(str(args.output_dir).replace("{stem}", stem))
        else:
            out_dir = Path(f"tmp/exported/{stem}")
        out_dir.mkdir(parents=True, exist_ok=True)

        tags = args.tags or list_tags(aseprite_path)
        if not tags:
            print(f"WARNING: no tags found in {aseprite_path}, exporting all frames as 'default'")
            tags = ["default"]

        print(f"\n{'=' * 60}")
        print(f"Exporting {aseprite_path.name} → {out_dir}")
        print(f"Tags: {tags}")
        print(f"Frame size: {args.frame_size}x{args.frame_size}, fill: {args.fill_ratio:.0%}")
        print(f"{'=' * 60}")

        exported = []
        for tag in tags:
            result = process_tag(aseprite_path, tag, out_dir, args.frame_size,
                                args.fill_ratio, args.bg_tolerance)
            if result:
                exported.append(result)

        # Clean up tmp
        tmp_dir = out_dir / ".tmp"
        if tmp_dir.exists():
            import shutil
            shutil.rmtree(tmp_dir)

        print(f"\nExported {len(exported)}/{len(tags)} animations to {out_dir}")


if __name__ == "__main__":
    main()
