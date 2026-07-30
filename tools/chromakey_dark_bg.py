#!/usr/bin/env python3
"""Chromakey a dark/black background to transparent on a monster sheet.

Uses corner-sample color-distance + connected-component flood-fill from the
corners of each 256×256 frame. This preserves internal dark shadow (a wing
scale that HAPPENS to be dark stays opaque, only connected-to-corner darkness
becomes transparent).

Reason: gpt-image-1 sometimes returns a near-black background (~RGB 0-15)
instead of white/transparent, and the regen tool's default chromakey only
keys near-white (>=240). Downstream battle rendering then shows an ugly
black rectangle around the sprite.

Usage:
    uv run python tools/chromakey_dark_bg.py assets/sprites/monsters/lightning_dragon.png
    uv run python tools/chromakey_dark_bg.py <path> --frame-w 256 --threshold 40
"""
import argparse, shutil, sys
from collections import deque
from pathlib import Path
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
BACKUP_DIR = PROJECT / "tmp" / "pre_chromakey_backups"


def flood_key_frame(img: Image.Image, threshold: int = 40) -> Image.Image:
    """Flood-fill from all 4 corners any pixel whose color-distance to the
    corner sample is <= threshold, setting alpha=0. Preserves interior
    dark regions that aren't connected to the corners."""
    img = img.convert("RGBA")
    W, H = img.size
    px = img.load()

    seeds = [(0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)]
    visited = [[False] * H for _ in range(W)]

    def color_near(a, b):
        return (abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])) <= threshold

    for sx, sy in seeds:
        sr, sg, sb, sa = px[sx, sy]
        if sa == 0:
            continue
        seed_color = (sr, sg, sb)
        q = deque([(sx, sy)])
        while q:
            x, y = q.popleft()
            if x < 0 or x >= W or y < 0 or y >= H:
                continue
            if visited[x][y]:
                continue
            r, g, b, a = px[x, y]
            if a == 0:
                visited[x][y] = True
                continue
            if not color_near((r, g, b), seed_color):
                continue
            visited[x][y] = True
            px[x, y] = (r, g, b, 0)
            q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return img


def process_strip(path: Path, frame_w: int, threshold: int, backup: bool):
    img = Image.open(path).convert("RGBA")
    W, H = img.size
    n_frames = W // frame_w
    if W % frame_w != 0:
        print(f"WARN {path.name}: {W}px width not divisible by frame_w={frame_w}",
              file=sys.stderr)
    print(f"[{path.name}] {W}x{H}, {n_frames} frames of {frame_w}px, threshold={threshold}")

    if backup:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        bak = BACKUP_DIR / (path.stem + ".pre_chromakey" + path.suffix)
        if not bak.exists():
            shutil.copy2(path, bak)
            print(f"  backup: {bak}")

    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for i in range(n_frames):
        frame = img.crop((i * frame_w, 0, (i + 1) * frame_w, H))
        keyed = flood_key_frame(frame, threshold=threshold)
        out.paste(keyed, (i * frame_w, 0), keyed)
    out.save(path)
    print(f"  → {path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", type=Path)
    ap.add_argument("--frame-w", type=int, default=256)
    ap.add_argument("--threshold", type=int, default=40,
                    help="max color-channel-sum distance from corner sample")
    ap.add_argument("--no-backup", action="store_true")
    args = ap.parse_args()
    for p in args.paths:
        process_strip(p, args.frame_w, args.threshold, backup=not args.no_backup)
    return 0


if __name__ == "__main__":
    sys.exit(main())
