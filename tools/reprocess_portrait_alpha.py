#!/usr/bin/env python3
"""Re-cut portrait alpha from saved RAW images — no API cost.

regen_archetype_portraits.transparent_bg() clears EVERY pixel brighter than a
threshold, anywhere in the frame. That is fine for a dark subject and destructive
for a light one: the priestess's white vestments were erased along with the
background, leaving a floating head.

This flood-fills from the border instead, so only background-CONNECTED white is
cleared and interior white (robes, veils, highlights) survives. Reads the raws
the generator already saved, so re-cutting is free.

  python3 tools/reprocess_portrait_alpha.py --dry-run
  python3 tools/reprocess_portrait_alpha.py --ids priestess
"""
import argparse, os, sys
from collections import deque
from pathlib import Path
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path(os.environ.get("GAME_REPO", str(PROJECT)))
RAW_DIR = PROJECT / "tmp" / "missing_portrait_gen"
NPC_DIR = GAME_REPO / "assets" / "sprites" / "portraits" / "npcs"
JOB_DIR = GAME_REPO / "assets" / "sprites" / "portraits"
JOB_IDS = {"bossbinder", "necromancer", "scriptweaver", "skiptrotter",
           "time_mage", "guardian", "ninja", "summoner", "speculator"}


def border_transparent(img: Image.Image, thresh: int = 236) -> Image.Image:
    """Clear only near-white pixels reachable from the border."""
    img = img.convert("RGBA")
    W, H = img.size
    px = img.load()

    def light(x, y):
        r, g, b, _ = px[x, y]
        return r >= thresh and g >= thresh and b >= thresh

    seen = bytearray(W * H)
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            if light(x, y) and not seen[y * W + x]:
                seen[y * W + x] = 1; q.append((x, y))
    for y in range(H):
        for x in (0, W - 1):
            if light(x, y) and not seen[y * W + x]:
                seen[y * W + x] = 1; q.append((x, y))

    while q:
        x, y = q.popleft()
        px[x, y] = (px[x, y][0], px[x, y][1], px[x, y][2], 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and not seen[ny * W + nx] and light(nx, ny):
                seen[ny * W + nx] = 1; q.append((nx, ny))
    return img


def opaque_ratio(img: Image.Image) -> float:
    a = img.convert("RGBA").getchannel("A")
    return sum(1 for v in a.getdata() if v > 8) / float(a.size[0] * a.size[1])


def dest_for(pid: str) -> Path:
    return (JOB_DIR if pid in JOB_IDS else NPC_DIR) / f"{pid}.png"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", nargs="+")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    raws = sorted(RAW_DIR.glob("*_raw.png"))
    if not raws:
        print(f"ERROR: no raws in {RAW_DIR}", file=sys.stderr)
        return 1
    ids = args.ids or [p.name[:-len("_raw.png")] for p in raws]

    print(f"{len(ids)} portrait(s) to re-cut from raw (no API cost)")
    changed = []
    for pid in ids:
        raw_p = RAW_DIR / f"{pid}_raw.png"
        out = dest_for(pid)
        if not raw_p.exists():
            print(f"  {pid:22s} SKIP (no raw)"); continue
        before = opaque_ratio(Image.open(out)) if out.exists() else 0.0
        cut = border_transparent(Image.open(raw_p))
        small = cut.resize((256, 256), Image.BOX)
        after = opaque_ratio(small)
        delta = after - before
        mark = "  <-- RECOVERED" if delta > 0.02 else ""
        print(f"  {pid:22s} opaque {before:.3f} -> {after:.3f} ({delta:+.3f}){mark}")
        if not args.dry_run:
            small.save(out)
        if delta > 0.02:
            changed.append(pid)
    print(f"\n{'would recover' if args.dry_run else 'recovered'} pixels on {len(changed)}: {changed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
