#!/usr/bin/env python3
"""Surgically regenerate the left/right walk rows of a job's overworld sheet.

The overworld generator's known defect class: rows 2-3 (left/right walk)
come back with oversized heads and smeared bodies while rows 1/4
(down/up) are clean. Full-sheet regen would discard the good rows the
player has already seen — this tool regenerates ONLY the side view.

Pipeline (one gpt-image-1 call per job, ~$0.042 medium):
  1. Reference = artist battle idle (identity) + the sheet's own good
     down row upscaled (format/palette anchor)
  2. Prompt for a 4-frame SIDE-VIEW walk cycle facing left, single row
  3. Slice frames via the overworld module's blob-detection helpers
  4. head_lock_row(0.65) — same stabilization the base pipeline uses
  5. Row "left" = new frames; row "right" = horizontal mirror
  6. Paste into the existing sheet; rows down/up stay byte-identical

Usage:
    uv run python tools/fix_overworld_side_rows.py fighter
    uv run python tools/fix_overworld_side_rows.py fighter cleric --quality high
    uv run python tools/fix_overworld_side_rows.py fighter --dry-run
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
OUT_TMP = PROJECT / "tmp" / "overworld_side_fix"
OUT_TMP.mkdir(parents=True, exist_ok=True)

COST = {"low": 0.011, "medium": 0.042, "high": 0.167}

# 4x4 grid rows in the game sheets
ROW_DOWN, ROW_LEFT, ROW_RIGHT, ROW_UP = 0, 1, 2, 3

SIDE_PROMPT = (
    "16-bit JRPG overworld walk-cycle sprite strip: exactly 4 frames in a "
    "single horizontal row, all showing the SAME character in strict SIDE "
    "PROFILE walking to the LEFT. Frame sequence: contact pose (left foot "
    "forward), passing pose (legs together, slight rise), contact pose "
    "(right foot forward), passing pose again. Consistent identity, "
    "silhouette, and volume across all 4 frames — the head must stay the "
    "same size as the down-facing reference (head ≈ 40%% of total height, "
    "NOT oversized), full torso and legs clearly drawn, arms swinging "
    "naturally. Character: {char_desc}. Match the reference sprites' "
    "palette, proportions, and clean pixel-art shading exactly. Fully "
    "transparent background, no scenery, no shadows, no text. Generous "
    "spacing between the 4 frames."
)


def build_refs(job: str, sheet: Image.Image) -> list[tuple]:
    """Two refs: artist battle idle (identity) + good down row (format)."""
    cfg = ow.ENTITY_SOURCES[job]
    artist_png = OUT_TMP / f"{job}_ref_artist.png"
    ase_path = ow.DRIVE_LOCAL / cfg["ase_rel"]
    if not ase_path.exists():
        raise RuntimeError(f"artist source missing: {ase_path}")
    ow.export_idle_frame(ase_path, cfg["idle_tag"], artist_png)
    artist_bytes = ow.pad_to_square(Image.open(artist_png), 1024)

    W, H = sheet.size
    fh = H // 4
    down_row = sheet.crop((0, ROW_DOWN * fh, W, (ROW_DOWN + 1) * fh))
    down_big = down_row.resize((W * 4, fh * 4), Image.NEAREST)
    down_bytes = ow.pad_to_square(down_big, 1024)

    return [
        ("ref_artist.png", artist_bytes, "image/png"),
        ("ref_down_row.png", down_bytes, "image/png"),
    ]


def _despeck(cell: Image.Image, keep_ratio: float = 0.05) -> Image.Image:
    """Drop connected components smaller than keep_ratio × largest.

    Stray generation specks inflate the cell bbox, which makes
    _cell_to_chibi square-pad around dead space and shrink the figure
    to a fraction of the 32px cell. Detached-but-real details (hair
    curls, scythe hilt) are well above 5% of the body and survive."""
    import numpy as np
    from scipy import ndimage

    arr = np.array(cell)
    mask = arr[:, :, 3] > 32
    # Sub-threshold haze (alpha 1-32) isn't part of any component but
    # still counts toward PIL getbbox() — zero it or the figure shrinks.
    arr[~mask] = (0, 0, 0, 0)
    labeled, n = ndimage.label(mask)
    if n <= 1:
        return Image.fromarray(arr, "RGBA")
    sizes = ndimage.sum_labels(mask, labeled, range(1, n + 1))
    biggest = sizes.max()
    drop = np.isin(labeled, [i + 1 for i, s in enumerate(sizes)
                             if s < biggest * keep_ratio])
    arr[drop] = (0, 0, 0, 0)
    return Image.fromarray(arr, "RGBA")


def slice_side_frames(raw: Image.Image, target: int = 32) -> list[Image.Image]:
    """Split the content bbox into 4 equal x-quarters, despeck each,
    then normalize to target-px chibi cells.

    Quarter-splitting (vs blob detection) is robust to touching figures
    and to stray specks between them; despeck keeps per-cell bboxes
    tight so figures fill the cell after scaling."""
    bbox = raw.getbbox()
    if bbox is None:
        raise RuntimeError("empty generation")
    x0, y0, x1, y1 = bbox
    quarter = (x1 - x0) / 4.0
    frames = []
    for i in range(4):
        cell = raw.crop((int(x0 + i * quarter), y0,
                         int(x0 + (i + 1) * quarter), y1))
        cell = _despeck(cell)
        frames.append(ow._cell_to_chibi(cell, target))
    return frames


def hsv_match_side_rows(sheet: Image.Image) -> Image.Image:
    """Histogram-match rows 1-2 (left/right) to rows 0/3 (down/up) in HSV.

    gpt-image-1 side regens drift warm (crimson armor → orange). Content
    is the same character at the same scale, so per-channel CDF matching
    maps the color masses back onto the sheet's real palette."""
    import numpy as np

    def match_channel(src, ref):
        s_vals, s_counts = np.unique(src, return_counts=True)
        r_vals, r_counts = np.unique(ref, return_counts=True)
        s_cdf = np.cumsum(s_counts).astype(float); s_cdf /= s_cdf[-1]
        r_cdf = np.cumsum(r_counts).astype(float); r_cdf /= r_cdf[-1]
        interp = np.interp(s_cdf, r_cdf, r_vals)
        lut = dict(zip(s_vals, interp))
        return np.vectorize(lut.get)(src)

    a = np.array(sheet.convert("RGBA"))
    H, W = a.shape[:2]
    fh = H // 4
    hsv = np.array(Image.fromarray(a[:, :, :3], "RGB").convert("HSV"))

    good = np.zeros((H, W), bool)
    good[0:fh] = a[0:fh, :, 3] > 128
    good[3*fh:4*fh] = a[3*fh:4*fh, :, 3] > 128
    new = np.zeros((H, W), bool)
    new[fh:3*fh] = a[fh:3*fh, :, 3] > 128
    if not good.any() or not new.any():
        return sheet

    out_hsv = hsv.copy()
    for c in range(3):
        out_hsv[:, :, c][new] = np.clip(
            match_channel(hsv[:, :, c][new], hsv[:, :, c][good]), 0, 255
        ).astype(np.uint8)
    matched = np.array(Image.fromarray(out_hsv, "HSV").convert("RGB"))
    a[:, :, :3] = np.where(new[:, :, None], matched, a[:, :, :3])
    return Image.fromarray(a, "RGBA")


def paste_rows(sheet: Image.Image, left_frames: list[Image.Image]) -> Image.Image:
    """Write left row + mirrored right row into a copy of the sheet."""
    out = sheet.copy()
    W, H = out.size
    fw, fh = W // 4, H // 4
    right_frames = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in left_frames]
    for col in range(4):
        for row_idx, frames in ((ROW_LEFT, left_frames), (ROW_RIGHT, right_frames)):
            cell = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
            f = frames[col]
            cell.paste(f, ((fw - f.width) // 2, fh - f.height), f)
            out.paste(cell, (col * fw, row_idx * fh))
    return out


def fix_job(client, job: str, quality: str, hsv_match: bool = True) -> None:
    dest_root = ow.ENTITY_SOURCES[job].get("dest_root", ow.DEFAULT_DEST_ROOT)
    sheet_path = GAME_REPO / "assets" / "sprites" / dest_root / job / "overworld.png"
    if not sheet_path.exists():
        print(f"  SKIP {job}: no overworld.png")
        return
    sheet = Image.open(sheet_path).convert("RGBA")
    cfg = ow.ENTITY_SOURCES[job]
    prompt = SIDE_PROMPT.format(char_desc=cfg["char_desc"])
    refs = build_refs(job, sheet)

    print(f"[{job}] gpt-image-1 side-walk regen (${COST[quality]})")
    resp = client.images.edit(
        model="gpt-image-1",
        image=refs,
        prompt=prompt,
        size="1024x1024",
        quality=quality,
        n=1,
    )
    raw = Image.open(io.BytesIO(base64.b64decode(resp.data[0].b64_json))).convert("RGBA")
    raw.save(OUT_TMP / f"{job}_side_raw.png")

    raw = ow._strip_white_bg(raw)
    frames = slice_side_frames(raw, target=32)
    frames = ow.head_lock_row(frames, head_frac=0.65)

    fixed = paste_rows(sheet, frames)
    if hsv_match:
        fixed = hsv_match_side_rows(fixed)
    backup = sheet_path.with_name("overworld.pre_side_fix.png")
    if not backup.exists():
        sheet.save(backup)
    fixed.save(sheet_path)
    print(f"  → {sheet_path.relative_to(GAME_REPO)} (backup: {backup.name})")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("jobs", nargs="+")
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="medium")
    ap.add_argument("--no-hsv", action="store_true",
                    help="skip HSV palette match (when it corrupts colors)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.dry_run:
        for job in args.jobs:
            print(f"would fix {job} (${COST[args.quality]})")
        return 0

    client = OpenAI()
    for job in args.jobs:
        try:
            fix_job(client, job, args.quality, hsv_match=not args.no_hsv)
        except Exception as e:
            print(f"  FAILED {job}: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
