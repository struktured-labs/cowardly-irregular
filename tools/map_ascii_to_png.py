#!/usr/bin/env python3
"""Export a GDScript ASCII map literal to a 1px-per-tile PNG, losslessly.

The ASCII literal does not survive the scale-up: W1 is 70 rows x 100 chars today, and a
4x map is 140 rows x 200 hand-aligned characters where every row must be exactly 200 wide.
IndustrialOverworld already carries that bug -- rows of 59 AND 60 -- silently.

WHY THE PIXEL ENCODES THE CHARACTER, NOT THE TILE TYPE:
_char_to_tile_type collapses 25 characters into ~12 visual types. "1", "2", "3" and "4" all
return CAVE_ENTRANCE; "W", "E", "G", "D", "I" all return VILLAGE_GATE. But _register_spawn_point
keys on the CHARACTER. A tile-type image would render identically and silently erase every
dragon cave's and every village's spawn identity. So the palette is char-keyed and the loader
is strict.

The palette lives in data/maps/map_palette.json and is read by BOTH this tool and
src/exploration/MapImageLoader.gd. Do not transcribe it into either.
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PALETTE = REPO / "data" / "maps" / "map_palette.json"


def load_palette():
    p = json.loads(PALETTE.read_text())
    char_to_rgb = {}
    for section in ("terrain", "landmarks"):
        for ch, spec in p[section].items():
            if len(ch) != 1:
                die(f"palette key {ch!r} is not a single character")
            char_to_rgb[ch] = tuple(spec["rgb"])
    # CONTROL: colours must be pairwise distinct, or two chars decode to one and the
    # round-trip silently picks whichever the reverse map saw last.
    seen = {}
    for ch, rgb in char_to_rgb.items():
        if rgb in seen:
            die(f"palette collision: {ch!r} and {seen[rgb]!r} share rgb {rgb}")
        seen[rgb] = ch
    return char_to_rgb


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def extract_map_rows(gd_path: Path):
    """Structural extraction: from the array's opening bracket to its matching close.

    NOT a line-count window. A truncated extraction returns real rows, correctly parsed,
    from an incomplete region, and nothing in the output says it was cut.
    """
    src = gd_path.read_text()
    open_m = re.search(r'var map_data\s*:\s*Array\[String\]\s*=\s*\[', src)
    if not open_m:
        die(f"no `var map_data: Array[String] = [` in {gd_path.name}")
    start = open_m.end()
    depth = 1
    i = start
    while i < len(src) and depth:
        if src[i] == "[":
            depth += 1
        elif src[i] == "]":
            depth -= 1
        i += 1
    if depth:
        die("map_data array never closes -- extraction would have been truncated")
    block = src[start : i - 1]
    rows = re.findall(r'"([^"]*)"', block)
    if not rows:
        die("map_data block parsed but yielded zero rows")
    return rows


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        print("usage: map_ascii_to_png.py <SceneFile.gd> <out.png> [--verify-only]")
        sys.exit(2)
    gd = REPO / sys.argv[1] if not Path(sys.argv[1]).is_absolute() else Path(sys.argv[1])
    out = REPO / sys.argv[2] if not Path(sys.argv[2]).is_absolute() else Path(sys.argv[2])
    verify_only = "--verify-only" in sys.argv

    palette = load_palette()
    rows = extract_map_rows(gd)

    widths = sorted({len(r) for r in rows})
    print(f"source      {gd.name}")
    print(f"rows        {len(rows)}")
    print(f"row widths  {widths}")
    if len(widths) != 1:
        die(f"RAGGED MAP: rows are not all the same width ({widths}). "
            f"Fix the source before exporting, or the image encodes the bug.")
    w, h = widths[0], len(rows)

    # declared dims must agree with the literal -- a mismatch means the engine reads a
    # different grid than the author sees
    src = gd.read_text()
    dw = re.search(r'const MAP_WIDTH: int = (\d+)', src)
    dh = re.search(r'const MAP_HEIGHT: int = (\d+)', src)
    if dw and dh:
        if (int(dw.group(1)), int(dh.group(1))) != (w, h):
            die(f"declared {dw.group(1)}x{dh.group(1)} but literal is {w}x{h}")
        print(f"declared    {w}x{h}  (agrees with the literal)")

    used = sorted(set("".join(rows)))
    unknown = [c for c in used if c not in palette]
    if unknown:
        die(f"characters with no palette entry: {unknown!r}. "
            f"Add them to {PALETTE.relative_to(REPO)} rather than letting them decode to grass.")
    print(f"chars used  {len(used)} of {len(palette)} in palette")

    unused = sorted(set(palette) - set(used))
    if unused:
        print(f"  (palette entries not used by this map: {unused!r})")

    from PIL import Image

    img = Image.new("RGB", (w, h))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            px[x, y] = palette[ch]

    # ROUND-TRIP IN THE EXPORTER ITSELF: decode what we just encoded and compare to source.
    # Without this, "the file was written" is the only thing proven.
    rev = {v: k for k, v in palette.items()}
    decoded = ["".join(rev[px[x, y]] for x in range(w)) for y in range(h)]
    if decoded != rows:
        bad = next(i for i, (a, b) in enumerate(zip(decoded, rows)) if a != b)
        die(f"round-trip FAILED at row {bad}\n  src: {rows[bad]}\n  dec: {decoded[bad]}")
    print("round-trip  OK -- decoded image is byte-identical to the source literal")

    if verify_only:
        print("(--verify-only: nothing written)")
        return

    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG")
    print(f"wrote       {out.relative_to(REPO)}  ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
