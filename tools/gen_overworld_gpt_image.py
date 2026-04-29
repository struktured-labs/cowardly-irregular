#!/usr/bin/env python3
"""
Generate 4-direction overworld walk-cycle sprites via GPT-Image-1
with TWO reference images:

  1. Artist battle sprite (idle frame) → character identity (palette, equipment)
  2. Proc-gen chibi (existing overworld.png) → format/scale/angle (4x4 grid layout)

GPT-Image returns a 1024x1024 image organized as a 4x4 grid; we downscale to
128x128 game format and split into a 16-frame strip for aseprite assembly.

Pipeline (mirrors gen_overworld_pixellab.py but uses gpt-image-1):
  1. Load + pad both refs to 1024x1024
  2. Call client.images.edit with both refs + structured prompt
  3. Receive 1024x1024 output
  4. Downscale 1024→128 (LANCZOS for quality, then NEAREST step for crispness)
  5. Build tagged aseprite via tools/build_overworld_aseprite.lua
  6. Upload .aseprite to gdrive: cowir/.../<JOB>/claude/
  7. Deploy 128x128 PNG to game repo's assets/sprites/jobs/<job>/overworld.png

Cost: ~$0.07 (medium) or ~$0.19 (high) per call. Idempotent unless --force.

Usage:
    source setenv.sh
    uv run python tools/gen_overworld_gpt_image.py --job fighter
    uv run python tools/gen_overworld_gpt_image.py --job fighter --quality high
    uv run python tools/gen_overworld_gpt_image.py --job fighter --dry-run
"""

import argparse
import base64
import io
import json
import os
import subprocess
import sys
from pathlib import Path

from openai import OpenAI
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
DRIVE_LOCAL = REPO / "assets" / "sprites" / "drive_archive" / "Game graphics - Characters"
GAME_JOBS = Path(os.environ.get("GAME_REPO", "/home/struktured/projects/cowardly-irregular")) / "assets" / "sprites" / "jobs"
TMP = REPO / "tmp" / "overworld_gpt_image"
TMP.mkdir(parents=True, exist_ok=True)

JOB_SOURCES = {
    "fighter": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "FIGHTER/claude",
        "char_desc": (
            "dark-brown-haired knight fighter in deep red tunic with leather/copper "
            "shoulder armor, cradling a steel sword, dark leather boots and gloves"
        ),
    },
    "cleric": {
        "ase_rel": "CLERIC/Cleric Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "CLERIC/claude",
        "char_desc": (
            "white-robed cleric healer holding EXACTLY ONE ornate golden ankh-tipped "
            "staff in one hand, soft gentle aura, hooded head, simple boots — only one "
            "staff, no extra floating staffs or duplicate weapons in the frame"
        ),
    },
    "rogue": {
        "ase_rel": "ROGUE/Rogue Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "ROGUE/claude",
        "char_desc": (
            "agile rogue archer with bow, dark leather armor, slim build, "
            "brown/gray earth-tone colors, light boots"
        ),
    },
    "mage": {
        "ase_rel": "MAGE/Mage Main design.aseprite",
        "idle_tag": "idle",
        "drive_dir": "MAGE/claude",
        "char_desc": (
            "young wizard mage with VISIBLE pale skin face and small dark eyes "
            "(NOT a shadowed silhouette face — face must be clearly drawn with "
            "skin tones), wearing deep teal/navy robes with purple pointed hat, "
            "holding a wooden staff topped with a golden flame, friendly JRPG "
            "chibi style"
        ),
    },
}

PROMPT_TEMPLATE = """Generate a 4-direction walk-cycle sprite sheet for a {char_desc}.

Output format — match this exactly:
  - 1024x1024 canvas, transparent background, organized as a 4-row by 4-column GRID of 256x256 cells
  - Each cell contains ONE frame of the character at chibi scale (the character should fill ~70% of the cell vertically)
  - Top-down 3/4 JRPG overworld view (camera angle ~30 degrees above horizon, similar to classic 16-bit RPGs)

Row layout (top to bottom):
  Row 0: walking SOUTH (facing the viewer, front view)
  Row 1: walking WEST (side profile facing left)
  Row 2: walking EAST (side profile facing right, mirror of row 1)
  Row 3: walking NORTH (facing away from viewer, back view)

Column layout (left to right) — standard 4-frame walk cycle:
  Col 0: standing pose (legs together)
  Col 1: right-foot-forward stride
  Col 2: standing pose (legs together)
  Col 3: left-foot-forward stride

Style:
  - 16-bit JRPG pixel-art aesthetic (think Final Fantasy V, Chrono Trigger, EarthBound overworld sprites)
  - Crisp pixel boundaries, NO anti-aliasing, NO smooth gradients
  - Character identity (palette, hair, equipment) MUST match Reference Image 1 (the artist's battle sprite)
  - Frame format, chibi proportions, and viewing angle MUST match Reference Image 2 (the existing chibi reference)
  - Transparent background (alpha channel)
  - Each cell is 256x256, character roughly centered, no overflow between cells

Return only the 4x4 grid sprite sheet — no labels, no borders, no annotations."""


def pad_to_square(img: Image.Image, size: int = 1024) -> bytes:
    """Pad image with transparency to a square of the given size, return PNG bytes."""
    img = img.convert("RGBA")
    w, h = img.size
    scale = min(size / w, size / h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    img = img.resize((nw, nh), Image.NEAREST)
    sq = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sq.paste(img, ((size - nw) // 2, (size - nh) // 2), img)
    buf = io.BytesIO()
    sq.save(buf, format="PNG")
    return buf.getvalue()


def export_idle_frame(ase_path: Path, idle_tag: str, out_png: Path) -> None:
    subprocess.run(
        ["aseprite", "-b", "--tag", idle_tag, "--frame-range", "0,0",
         "--sheet", str(out_png), str(ase_path)],
        check=True, capture_output=True,
    )


def get_proc_gen_chibi(job: str, out_png: Path) -> bool:
    """Recover the proc-gen 128x128 chibi reference from git HEAD of the game repo."""
    game_repo = Path(os.environ.get("GAME_REPO", "/home/struktured/projects/cowardly-irregular"))
    rel = f"assets/sprites/jobs/{job}/overworld.png"
    res = subprocess.run(
        ["git", "show", f"HEAD:{rel}"],
        cwd=game_repo, capture_output=True,
    )
    if res.returncode != 0:
        return False
    out_png.write_bytes(res.stdout)
    return True


def build_aseprite_from_strip(strip_png: Path, out_aseprite: Path) -> None:
    subprocess.run(
        ["aseprite", "-b", "--script-param", f"strip={strip_png}",
         "--script-param", f"out={out_aseprite}",
         "--script", str(REPO / "tools" / "build_overworld_aseprite.lua")],
        check=True, capture_output=True,
    )


def upload_to_drive(local_file: Path, drive_subdir: str) -> None:
    drive_path = f"gdrive: cowir/assets/sprites/Game graphics - Characters/{drive_subdir}"
    subprocess.run(
        ["rclone", "copy", str(local_file), drive_path],
        check=True, capture_output=True,
    )


def grid_to_strip(grid: Image.Image) -> Image.Image:
    """Convert an N×4 by N×4 grid (frame size N inferred from height/4) to a (16N)×N strip."""
    N = grid.height // 4
    strip = Image.new("RGBA", (16 * N, N))
    for row in range(4):
        for col in range(4):
            cell = grid.crop((col * N, row * N, (col + 1) * N, (row + 1) * N))
            strip.paste(cell, ((row * 4 + col) * N, 0))
    return strip


def _strip_white_bg(img: Image.Image, threshold: int = 235) -> Image.Image:
    """Convert near-white opaque pixels to transparent.

    GPT-Image-1 frequently ships an opaque white background even when the prompt
    requests transparency. Pixels where all of R, G, B are >= threshold are
    flipped to alpha=0. White character highlights (typically smaller and
    color-tinted) survive because they have at least one channel below threshold
    or are preserved by the post-NEAREST step.
    """
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a > 0 and r >= threshold and g >= threshold and b >= threshold:
                pixels[x, y] = (0, 0, 0, 0)
    return img


def _binarize_alpha(img: Image.Image, threshold: int = 128) -> Image.Image:
    """Snap alpha to 0 or 255 — kills LANCZOS halos for crisp pixel-art edges."""
    r, g, b, a = img.split()
    a = a.point(lambda v: 255 if v >= threshold else 0)
    return Image.merge("RGBA", (r, g, b, a))


def _cell_to_chibi(cell: Image.Image, target: int = 32) -> Image.Image:
    """Strip near-white BG, square-pad, downscale to target×target chibi (LANCZOS→NEAREST), binarize alpha."""
    cell = _strip_white_bg(cell.copy())
    bbox = cell.getbbox()
    if bbox:
        cell = cell.crop(bbox)
    cw, ch = cell.size
    side = max(cw, ch)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(cell, ((side - cw) // 2, (side - ch) // 2), cell)
    intermediate = max(target, target * 2 + target // 2)  # e.g. 80 for target=32, 160 for target=64
    chibi = sq.resize((intermediate, intermediate), Image.LANCZOS).resize((target, target), Image.NEAREST)
    return _binarize_alpha(chibi)


def _cell_to_chibi_32(cell: Image.Image) -> Image.Image:
    """Backwards-compatible alias for the 32×32 path."""
    return _cell_to_chibi(cell, 32)


def _detect_chibi_x_ranges(row_band: Image.Image, min_blob_width: int = 40) -> list[tuple[int, int]]:
    """
    Find x-ranges of distinct chibis in a horizontal band.
    Two-stage: try density-gap detection first (works when chibis have gaps); fall
    back to local-minima split (works when chibis are touching).
    """
    import numpy as np
    arr = np.array(row_band)  # H x W x 4
    col_density = (arr[:, :, 3] > 0).sum(axis=0).astype(float)
    smoothed = np.convolve(col_density, np.ones(8) / 8, mode="same")
    W = len(smoothed)

    # Stage 1: density-gap detection (chibis separated by clear empty gutters)
    threshold = max(5.0, float(smoothed.max()) * 0.15)
    gap_blobs: list[tuple[int, int]] = []
    in_blob, start = False, 0
    for x in range(W):
        if smoothed[x] > threshold and not in_blob:
            start, in_blob = x, True
        elif smoothed[x] <= threshold and in_blob:
            if x - start >= min_blob_width:
                gap_blobs.append((start, x))
            in_blob = False
    if in_blob and W - start >= min_blob_width:
        gap_blobs.append((start, W))

    # If gap detection produced multiple chibis, trust it.
    if len(gap_blobs) >= 2:
        return gap_blobs

    # Stage 2: chibis are touching with shallow valleys between them.
    # Find density peaks (chibi centers) by looking for local maxima, then split
    # the row at the midpoints between consecutive peaks.
    if not gap_blobs:
        return []
    full = gap_blobs[0]
    blob_start, blob_end = full
    inside_density = smoothed[blob_start:blob_end]
    if len(inside_density) < min_blob_width * 2:
        return [full]

    big_smooth = np.convolve(col_density, np.ones(40) / 40, mode="same")[blob_start:blob_end]
    peaks: list[int] = []
    window = min_blob_width
    peak_threshold = float(big_smooth.max()) * 0.7
    for x in range(window, len(big_smooth) - window):
        if big_smooth[x] < peak_threshold:
            continue
        lo, hi = max(0, x - window), min(len(big_smooth), x + window)
        if big_smooth[x] >= big_smooth[lo:hi].max() - 1e-6:
            if not peaks or x - peaks[-1] >= min_blob_width:
                peaks.append(x)

    if len(peaks) < 2:
        return [full]

    # Cut at midpoints between consecutive peaks
    cuts = [(peaks[i] + peaks[i + 1]) // 2 for i in range(len(peaks) - 1)]

    out: list[tuple[int, int]] = []
    prev = 0
    for c in cuts:
        if c - prev >= min_blob_width:
            out.append((blob_start + prev, blob_start + c))
            prev = c
    if len(big_smooth) - prev >= min_blob_width:
        out.append((blob_start + prev, blob_end))

    return out if len(out) >= 2 else [full]


def _extract_row_chibis(raw: Image.Image, y0: int, y1: int, target: int = 32) -> list[Image.Image]:
    """
    Detect chibi positions in a horizontal band and return a target×target chibi for each.
    Strips white BG before detection so positions are accurate.
    """
    band = raw.crop((0, y0, raw.width, y1))
    band_stripped = _strip_white_bg(band.copy())
    ranges = _detect_chibi_x_ranges(band_stripped)
    chibis: list[Image.Image] = []
    for x0, x1 in ranges:
        # Pad a bit horizontally so we don't clip outline edges
        pad = 8
        x0p = max(0, x0 - pad)
        x1p = min(raw.width, x1 + pad)
        chibis.append(_cell_to_chibi(band.crop((x0p, 0, x1p, band.height)), target))
    return chibis


def _build_4frame_walk(chibis: list[Image.Image]) -> list[Image.Image]:
    """
    Pad the detected chibis to a 4-frame walk cycle [F0, F1, F0, F2] — classic
    stand/right-stride/stand/left-stride. Whatever GPT produced becomes:
      3 chibis  → [c0, c1, c0, c2]   ← typical case
      2 chibis  → [c0, c1, c0, c1]
      1 chibi   → [c0, c0, c0, c0]   ← static, fallback
      4+ chibis → first 4
    """
    if not chibis:
        empty = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        return [empty] * 4
    if len(chibis) == 1:
        return [chibis[0]] * 4
    if len(chibis) == 2:
        return [chibis[0], chibis[1], chibis[0], chibis[1]]
    if len(chibis) >= 3:
        return [chibis[0], chibis[1], chibis[0], chibis[2]]
    return chibis[:4]


def assemble_game_grid(raw_1024: Image.Image, target: int = 32) -> Image.Image:
    """
    Build a 4-row N×N walk-cycle grid (N = target * 4) from GPT's 3-row chibi output.
    Side row is mirrored to fill east. Frames within each row use a
    [F0, F1, F0, F2] stand/right/stand/left cycle.
    """
    from PIL import ImageOps
    H = raw_1024.height
    NUM_ROWS = 3
    row_h = H // NUM_ROWS
    sheet_w = target * 4
    sheet_h = target * 4

    grid = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))

    # Row 0: walk_down (front)
    front = _build_4frame_walk(_extract_row_chibis(raw_1024, 0, row_h, target))
    for col, frame in enumerate(front):
        grid.paste(frame, (col * target, 0))

    # Rows 1+2: walk_left / walk_right (side, mirrored)
    side = _build_4frame_walk(_extract_row_chibis(raw_1024, row_h, 2 * row_h, target))
    for col, frame in enumerate(side):
        grid.paste(frame, (col * target, target))
        grid.paste(ImageOps.mirror(frame), (col * target, target * 2))

    # Row 3: walk_up (back)
    back = _build_4frame_walk(_extract_row_chibis(raw_1024, 2 * row_h, 3 * row_h, target))
    for col, frame in enumerate(back):
        grid.paste(frame, (col * target, target * 3))

    return grid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", required=True, choices=list(JOB_SOURCES.keys()))
    ap.add_argument("--quality", choices=["low", "medium", "high"], default="medium")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--no-upload", action="store_true",
                    help="Skip Drive upload (for local testing)")
    args = ap.parse_args()

    cfg = JOB_SOURCES[args.job]
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        print("ERROR: OPENAI_API_KEY not set. Run: source setenv.sh")
        sys.exit(1)

    job_tmp = TMP / args.job
    job_tmp.mkdir(parents=True, exist_ok=True)
    artist_png = job_tmp / "ref_artist_battle.png"
    chibi_png = job_tmp / "ref_procgen_chibi.png"
    raw_out = job_tmp / "gpt_raw_1024.png"
    grid_out = job_tmp / f"{args.job}_overworld_grid.png"
    strip_out = job_tmp / f"{args.job}_overworld_strip.png"
    aseprite_out = job_tmp / f"{args.job}_overworld.aseprite"

    if grid_out.exists() and aseprite_out.exists() and not args.force:
        print("outputs exist — pass --force to regenerate")
        return

    # 1. Prepare references
    print("[1] preparing references")
    ase_path = DRIVE_LOCAL / cfg["ase_rel"]
    if not ase_path.exists():
        print(f"ERROR: artist source missing: {ase_path}")
        sys.exit(1)
    export_idle_frame(ase_path, cfg["idle_tag"], artist_png)
    if not get_proc_gen_chibi(args.job, chibi_png):
        print(f"ERROR: cannot recover proc-gen chibi ref for {args.job} from game repo HEAD")
        sys.exit(1)

    artist_bytes = pad_to_square(Image.open(artist_png), 1024)
    chibi_bytes = pad_to_square(Image.open(chibi_png), 1024)

    prompt = PROMPT_TEMPLATE.format(char_desc=cfg["char_desc"])
    if args.dry_run:
        print(f"[dry-run] would call gpt-image-1 (quality={args.quality}) with 2 refs:")
        print(f"  ref 1: {artist_png}")
        print(f"  ref 2: {chibi_png}")
        print(f"--- prompt ---\n{prompt}\n--- end prompt ---")
        return

    # 2. Call gpt-image-1
    print(f"[2] gpt-image-1 edit (quality={args.quality}, 2 refs, 1024x1024)")
    client = OpenAI(api_key=api_key)
    resp = client.images.edit(
        model="gpt-image-1",
        image=[
            ("ref_artist.png", artist_bytes, "image/png"),
            ("ref_chibi.png", chibi_bytes, "image/png"),
        ],
        prompt=prompt,
        size="1024x1024",
        quality=args.quality,
        n=1,
    )
    raw_b64 = resp.data[0].b64_json
    raw_img = Image.open(io.BytesIO(base64.b64decode(raw_b64))).convert("RGBA")
    raw_img.save(raw_out)
    print(f"   saved raw: {raw_out}")

    # 3. Build TWO outputs: 32px game PNG + 64px high-detail master
    print(f"[3] assemble dual outputs (32px game + 64px master)")
    grid_32 = assemble_game_grid(raw_img, target=32)
    grid_32.save(grid_out)
    strip_32 = grid_to_strip(grid_32)
    strip_32.save(strip_out)

    grid_64 = assemble_game_grid(raw_img, target=64)
    grid64_out = job_tmp / f"{args.job}_overworld_grid_64.png"
    strip64_out = job_tmp / f"{args.job}_overworld_strip_64.png"
    grid_64.save(grid64_out)
    strip_64 = grid_to_strip(grid_64)
    strip_64.save(strip64_out)

    # 4. Build BOTH aseprite files (32px small + 64px master)
    print(f"[4] build tagged aseprites (32px small + 64px master)")
    build_aseprite_from_strip(strip_out, aseprite_out)
    aseprite_master = job_tmp / f"{args.job}_overworld_64.aseprite"
    build_aseprite_from_strip(strip64_out, aseprite_master)

    # 5. Upload BOTH aseprites to Drive (small + master)
    if not args.no_upload:
        print(f"[5] upload aseprites → gdrive: .../{cfg['drive_dir']}/")
        upload_to_drive(aseprite_out, cfg["drive_dir"])
        upload_to_drive(aseprite_master, cfg["drive_dir"])
    else:
        print("[5] skipping upload (--no-upload)")

    # 6. Deploy to game
    dest = GAME_JOBS / args.job / "overworld.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(grid_out.read_bytes())
    print(f"[6] deployed → {dest}")

    cost = {"low": 0.02, "medium": 0.07, "high": 0.19}.get(args.quality, 0.07)
    print(f"\nDONE — ~${cost:.2f} estimated")
    print(f"  raw 1024:   {raw_out}")
    print(f"  game PNG:   {dest}")
    print(f"  aseprite:   {aseprite_out}")


if __name__ == "__main__":
    main()
