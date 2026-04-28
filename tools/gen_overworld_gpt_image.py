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
            "blonde-haired knight fighter in red tunic, leather belt, brown boots, "
            "cradling a sword, slightly armored shoulders"
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


def grid_to_strip(grid_128: Image.Image) -> Image.Image:
    """Convert a 128x128 4x4 grid to a 512x32 horizontal sequential strip."""
    strip = Image.new("RGBA", (512, 32))
    for row in range(4):
        for col in range(4):
            cell = grid_128.crop((col * 32, row * 32, (col + 1) * 32, (row + 1) * 32))
            strip.paste(cell, ((row * 4 + col) * 32, 0))
    return strip


def _cell_to_chibi_32(cell: Image.Image) -> Image.Image:
    """Square-pad and downscale a per-cell crop to 32x32 chibi (LANCZOS→NEAREST)."""
    bbox = cell.getbbox()
    if bbox:
        cell = cell.crop(bbox)
    cw, ch = cell.size
    side = max(cw, ch)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(cell, ((side - cw) // 2, (side - ch) // 2), cell)
    return sq.resize((80, 80), Image.LANCZOS).resize((32, 32), Image.NEAREST)


def assemble_game_grid(raw_1024: Image.Image) -> Image.Image:
    """
    GPT-Image-1 reliably produces 3 rows × 4 cols (front / side / back) — east side is
    omitted because it's the mirror of west. Slice as 3×4, downscale each cell to 32x32,
    and assemble the game's 4-row 128x128 grid by mirroring the side row to fill east.
    """
    from PIL import ImageOps
    W, H = raw_1024.size
    NUM_ROWS, NUM_COLS = 3, 4
    row_h, col_w = H // NUM_ROWS, W // NUM_COLS

    grid = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    for col in range(4):
        # row 0: front (walk_down)
        grid.paste(_cell_to_chibi_32(raw_1024.crop((col*col_w, 0, (col+1)*col_w, row_h))),
                   (col*32, 0))
        # rows 1+2: side / mirrored side (walk_left / walk_right)
        side = _cell_to_chibi_32(raw_1024.crop((col*col_w, row_h, (col+1)*col_w, 2*row_h)))
        grid.paste(side, (col*32, 32))
        grid.paste(ImageOps.mirror(side), (col*32, 64))
        # row 3: back (walk_up)
        grid.paste(_cell_to_chibi_32(raw_1024.crop((col*col_w, 2*row_h, (col+1)*col_w, 3*row_h))),
                   (col*32, 96))
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

    # 3. Slice 3-row GPT output → 4-row game grid (mirror side row for east)
    print(f"[3] assemble 3-row GPT 1024 → 4-row 128 game grid (mirror east)")
    grid_128 = assemble_game_grid(raw_img)
    grid_128.save(grid_out)
    strip_512 = grid_to_strip(grid_128)
    strip_512.save(strip_out)

    # 4. Build aseprite
    print(f"[4] build tagged aseprite")
    build_aseprite_from_strip(strip_out, aseprite_out)

    # 5. Upload to Drive
    if not args.no_upload:
        print(f"[5] upload {aseprite_out.name} → gdrive: .../{cfg['drive_dir']}/")
        upload_to_drive(aseprite_out, cfg["drive_dir"])
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
