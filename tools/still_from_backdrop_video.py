#!/usr/bin/env python3
"""Redraw a placeholder cutscene backdrop still from a frame of its own .ogv (T1).

cowir-main ruled the backdrop .ogv videos RETIRED (2026-11-01). Seven stills were bare gradients or grids
whose real scenery lived only in the video, so each still becomes a mid-clip frame of that video (3s: the
early frames of calibrant_desk and node_prime are still fading in), box-scaled to the still's own size.
Overwrites only the listed placeholders, and refuses any other key.

Usage:
    uv run python tools/still_from_backdrop_video.py            # all seven
    uv run python tools/still_from_backdrop_video.py node_prime
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
AT_SECONDS = 3.0
## The stills that were placeholders (cowir-cutscenes, 2026-11-01): every other still already shows its scene.
PLACEHOLDERS = ("maple_heights_street", "brasston_square", "rivet_row_factory", "director_office",
                "community_center", "calibrant_desk", "node_prime")


def redraw(key: str) -> Path:
    if key not in PLACEHOLDERS:
        raise SystemExit(f"{key} is not a placeholder still; refusing to overwrite it")
    video = ROOT / f"assets/cutscene_videos/{key}.ogv"
    still = ROOT / f"assets/cutscene_backdrops/{key}.png"
    size = Image.open(still).size
    with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as d:
        frame = Path(d) / "frame.png"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", str(AT_SECONDS), "-i", str(video),
                        "-frames:v", "1", str(frame)], check=True)
        img = Image.open(frame).convert("RGB").resize(size, Image.BOX).convert("RGBA")
    img.save(still)
    return still


def main() -> int:
    (ROOT / "tmp").mkdir(exist_ok=True)
    for key in sys.argv[1:] or PLACEHOLDERS:
        print(f"redrew {redraw(key).relative_to(ROOT)} from its video at {AT_SECONDS}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
