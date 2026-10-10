#!/usr/bin/env python3
"""Export an artist's 4-direction overworld walk .aseprite into the game's 4x4 walk grid, at NATIVE size.

The artist draws on a 128x128 canvas with direction TAGS (South/East/West/North, 4 frames each) and a figure
taller than the 32px AI placeholders (Rotha, 2026-10-08: 24x47). Artist pixels are never resampled, so the
sheet keeps his size: every frame is cut with ONE fixed window (his frame-to-frame registration survives),
feet on the cell's bottom row, and the manifest declares the cell size for the overworld renderers.

Rows are written in the game's order: walk_down, walk_left, walk_right, walk_up.

⚠️ LOOK at the result: Rotha's "West" tag faces RIGHT and her "East" faces LEFT, so she is exported with
--left-tag East --right-tag West. A tag is a label; the row must hold the frames that face that way.

  python3 tools/export_artist_overworld_walker.py --aseprite <file> --npc-id rotha --ignore-layer "Layer 13" \
      --left-tag East --right-tag West
"""
import argparse, json, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tools.artist_guard import assert_writable

PROJECT = Path(__file__).resolve().parent.parent
ROWS = [("walk_down", "south"), ("walk_left", "west"), ("walk_right", "east"), ("walk_up", "north")]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--aseprite", required=True)
    ap.add_argument("--npc-id", required=True)
    ap.add_argument("--ignore-layer", action="append", default=[], help="backdrop layers to leave out")
    ap.add_argument("--left-tag", default="west", help="tag whose frames FACE LEFT; check by eye, a file can mislabel them")
    ap.add_argument("--right-tag", default="east", help="tag whose frames FACE RIGHT")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with tempfile.TemporaryDirectory(dir=PROJECT / "tmp") as td:
        sheet, data = Path(td) / "s.png", Path(td) / "s.json"
        cmd = ["aseprite", "-b", "--list-tags"]  # without it the JSON carries no frameTags
        for layer in args.ignore_layer:
            cmd += ["--ignore-layer", layer]  # must precede the file or aseprite ignores it
        cmd += [args.aseprite, "--sheet", str(sheet), "--data", str(data), "--format", "json-array"]
        subprocess.run(cmd, check=True, capture_output=True)
        meta = json.loads(data.read_text())
        im = Image.open(sheet).convert("RGBA")
    fw = meta["frames"][0]["sourceSize"]["w"]
    fh = meta["frames"][0]["sourceSize"]["h"]
    tags = {t["name"].lower(): (t["from"], t["to"]) for t in meta["meta"]["frameTags"]}
    rows = [("walk_down", "south"), ("walk_left", args.left_tag.lower()), ("walk_right", args.right_tag.lower()), ("walk_up", "north")]
    missing = [d for _, d in rows if d not in tags]
    if missing:
        print(f"ERROR: no tag for {missing}; the file has {sorted(tags)}", file=sys.stderr)
        return 2
    frames = [im.crop((i * fw, 0, i * fw + fw, fh)) for i in range(len(meta["frames"]))]
    boxes = [f.getbbox() for f in frames]
    if any(b is None for b in boxes) or any(b == (0, 0, fw, fh) for b in boxes):
        print("ERROR: a frame is empty or fully opaque -- a backdrop layer is still visible (--ignore-layer)", file=sys.stderr)
        return 2
    x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    x1, y1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
    cell = max(32, -(-max(x1 - x0, y1 - y0) // 16) * 16)  # the figure's box, rounded up to 16px
    left = (x0 + x1) // 2 - cell // 2
    top = y1 - cell  # feet on the cell's bottom row
    out = Image.new("RGBA", (cell * 4, cell * 4), (0, 0, 0, 0))
    for row, (_, direction) in enumerate(rows):
        a, b = tags[direction]
        if b - a + 1 != 4:
            print(f"ERROR: tag {direction} has {b - a + 1} frames, the walk grid takes 4", file=sys.stderr)
            return 2
        for col in range(4):
            out.paste(frames[a + col].crop((left, top, left + cell, top + cell)), (col * cell, row * cell))
    dest = PROJECT / "assets" / "sprites" / "npcs" / args.npc_id / "overworld.png"
    print(f"{args.npc_id}: figure {x1 - x0}x{y1 - y0} in a {fw}x{fh} canvas -> {cell}px cells, sheet {out.size}, "
          f"{len(set(out.getdata()))} colours -> {dest.relative_to(PROJECT)}")
    if args.dry_run:
        return 0
    dest.parent.mkdir(parents=True, exist_ok=True)
    assert_writable(dest)
    out.save(dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
