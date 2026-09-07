#!/usr/bin/env python3
"""
Generate 4-direction overworld walk cycle sprites via PixelLab animate-with-text.

Pipeline:
  1. Load artist's idle frame from tagged aseprite (128x128 chibi)
  2. Downscale to 64x64 chibi reference (LANCZOS)
  3. Call PixelLab animate-with-text 4x — once per direction (down/left/right/up)
  4. Each call returns 4 frames at 64x64 → 16 total
  5. Build a tagged .aseprite via tools/build_overworld_aseprite.lua
  6. Compose a 128x128 4x4 grid PNG (game-side overworld.png format)
  7. Upload .aseprite to gdrive: cowir/.../<JOB>/claude/
  8. Deploy PNG to /home/struktured/projects/cowardly-irregular/assets/sprites/jobs/<job>/overworld.png

Idempotent: skips if outputs already exist (use --force to regenerate).

Usage:
    source setenv.sh
    uv run python tools/gen_overworld_pixellab.py --job fighter
    uv run python tools/gen_overworld_pixellab.py --job fighter --dry-run
    uv run python tools/gen_overworld_pixellab.py --job fighter --force
"""

import argparse
import base64
import io
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import httpx
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
DRIVE_LOCAL = REPO / "assets" / "sprites" / "drive_archive" / "Game graphics - Characters"
GAME_JOBS = Path(os.environ.get("GAME_REPO", "/home/struktured/projects/cowardly-irregular")) / "assets" / "sprites" / "jobs"
TMP = REPO / "tmp" / "overworld_pixellab"
TMP.mkdir(parents=True, exist_ok=True)

API_BASE = "https://api.pixellab.ai/v1"
API_TIMEOUT = 180

# Per-job: artist source aseprite + idle tag name
JOB_SOURCES = {
    "fighter": {
        "ase_rel": "FIGHTER/Main Fighter animations.aseprite",
        "idle_tag": "idle",
        "drive_dir": "FIGHTER/claude",
        "description": "fighter knight character with bronze helmet, sword, blue tunic, brown boots, chibi pixel art",
    },
    # Add cleric/rogue/mage when their tagged aseprites are normalized
}

DIRECTIONS = [
    ("walk_down",  "walking south, facing the viewer (front view), arms swinging naturally"),
    ("walk_left",  "walking west, side profile facing left, legs alternating"),
    ("walk_right", "walking east, side profile facing right, legs alternating"),
    ("walk_up",    "walking north, facing away from viewer (back view), arms swinging naturally"),
]


def export_idle_frame_to_png(ase_path: Path, idle_tag: str, out_png: Path) -> None:
    """Export frame 0 of the idle tag to a 128x128 PNG."""
    subprocess.run(
        ["aseprite", "-b", "--tag", idle_tag, "--frame-range", "0,0",
         "--sheet", str(out_png), str(ase_path)],
        check=True, capture_output=True,
    )


def load_reference_b64(idle_png: Path) -> str:
    """Resize idle frame to 64x64 chibi and return as base64 PNG."""
    img = Image.open(idle_png).convert("RGBA")
    img = img.resize((64, 64), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def call_pixellab_walk(
    client: httpx.Client, api_key: str,
    description: str, ref_b64: str, direction_clause: str, seed: int,
) -> tuple[list[Image.Image], float]:
    """One animate-with-text call for a single direction. Returns 4 frames + cost."""
    payload = {
        "image_size": {"width": 64, "height": 64},
        "description": f"{description}, {direction_clause}, top-down JRPG overworld view, 16-bit pixel art",
        "action": "walk",
        "reference_image": {"base64": ref_b64},
        "n_frames": 4,
        "seed": seed,
        "image_guidance_scale": 1.8,
    }
    resp = client.post(
        f"{API_BASE}/animate-with-text",
        json=payload,
        headers={"Authorization": f"Bearer {api_key}"},
        timeout=API_TIMEOUT,
    )
    if not resp.is_success:
        raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:300]}")
    data = resp.json()
    frames = [
        Image.open(io.BytesIO(base64.b64decode(item["base64"]))).convert("RGBA")
        for item in data.get("images", [])
    ]
    spent = data.get("usage", {}).get("usd", 0.0)
    return frames, spent


def build_strip_and_grid(direction_frames: dict[str, list[Image.Image]]) -> tuple[Image.Image, Image.Image]:
    """
    direction_frames maps tag_name -> list of 4 PIL images at 64x64.

    Returns:
      - strip_png:  512x32 horizontal sequential strip (16 frames @ 32x32, downscaled NEAREST from 64x64)
      - grid_png:   128x128 game-format 4x4 grid (rows: down/left/right/up; cols: stand/right-stride/stand/left-stride)
    """
    strip = Image.new("RGBA", (512, 32))
    grid = Image.new("RGBA", (128, 128))

    order = ["walk_down", "walk_left", "walk_right", "walk_up"]
    for row_idx, tag in enumerate(order):
        for col_idx, frame64 in enumerate(direction_frames[tag][:4]):
            frame32 = frame64.resize((32, 32), Image.NEAREST)
            # Strip: sequential layout
            seq_idx = row_idx * 4 + col_idx
            strip.paste(frame32, (seq_idx * 32, 0))
            # Grid: row=direction, col=walk-frame
            grid.paste(frame32, (col_idx * 32, row_idx * 32))

    return strip, grid


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", required=True, choices=list(JOB_SOURCES.keys()))
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true",
                    help="Regenerate even if outputs exist")
    args = ap.parse_args()

    cfg = JOB_SOURCES[args.job]
    api_key = os.environ.get("PIXELLAB_API_KEY", "")
    if not api_key and not args.dry_run:
        print("ERROR: PIXELLAB_API_KEY not set. Run: source setenv.sh")
        sys.exit(1)

    job_tmp = TMP / args.job
    job_tmp.mkdir(parents=True, exist_ok=True)
    idle_png = job_tmp / "idle_ref_128.png"
    strip_png = job_tmp / f"{args.job}_overworld_strip.png"
    grid_png = job_tmp / f"{args.job}_overworld_grid.png"
    aseprite_out = job_tmp / f"{args.job}_overworld.aseprite"
    cost_file = job_tmp / "_cost.json"

    if grid_png.exists() and aseprite_out.exists() and not args.force:
        print(f"outputs already exist — pass --force to regenerate")
        print(f"  {grid_png}")
        print(f"  {aseprite_out}")
        return

    # 1. Export artist idle reference
    ase_path = DRIVE_LOCAL / cfg["ase_rel"]
    if not ase_path.exists():
        print(f"ERROR: artist source missing: {ase_path}")
        sys.exit(1)
    print(f"[1] export idle from {cfg['ase_rel']} → {idle_png.name}")
    export_idle_frame_to_png(ase_path, cfg["idle_tag"], idle_png)
    ref_b64 = load_reference_b64(idle_png)

    if args.dry_run:
        print(f"[dry-run] would call PixelLab 4x with seed={args.seed}, ref 64x64 chibi from {cfg['ase_rel']}")
        for tag, dir_clause in DIRECTIONS:
            print(f"  - {tag}: {dir_clause}")
        return

    # 2-4. PixelLab calls
    print(f"[2] PixelLab animate-with-text x4 (seed={args.seed})")
    direction_frames: dict[str, list[Image.Image]] = {}
    total_cost = 0.0
    with httpx.Client() as client:
        for tag, dir_clause in DIRECTIONS:
            print(f"   - {tag}...", end=" ", flush=True)
            t0 = time.time()
            frames, cost = call_pixellab_walk(
                client, api_key, cfg["description"], ref_b64, dir_clause, args.seed,
            )
            elapsed = time.time() - t0
            total_cost += cost
            print(f"{len(frames)}f, ${cost:.3f}, {elapsed:.1f}s")
            direction_frames[tag] = frames
            # Save raw frames per direction for debugging
            for i, f in enumerate(frames):
                f.save(job_tmp / f"{tag}_f{i}_64.png")

    # 5-6. Build outputs
    print(f"[3] composing strip + grid PNGs")
    strip_img, grid_img = build_strip_and_grid(direction_frames)
    strip_img.save(strip_png, optimize=True)
    grid_img.save(grid_png, optimize=True)

    print(f"[4] building tagged aseprite via Lua script")
    build_aseprite_from_strip(strip_png, aseprite_out)

    # 7. Upload .aseprite to Drive
    print(f"[5] uploading {aseprite_out.name} → gdrive: .../{cfg['drive_dir']}/")
    upload_to_drive(aseprite_out, cfg["drive_dir"])

    # 8. Deploy PNG to game repo
    dest = GAME_JOBS / args.job / "overworld.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(grid_png.read_bytes())
    print(f"[6] deployed → {dest}")

    cost_file.write_text(json.dumps({"job": args.job, "seed": args.seed, "total_usd": total_cost}, indent=2))
    print(f"\nDONE — total cost: ${total_cost:.3f}")
    print(f"  game PNG:     {dest}")
    print(f"  aseprite:     {aseprite_out}")
    print(f"  drive:        gdrive: cowir/assets/sprites/Game graphics - Characters/{cfg['drive_dir']}/{aseprite_out.name}")


if __name__ == "__main__":
    main()
