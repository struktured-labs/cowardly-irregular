#!/usr/bin/env python3
"""Generate a world's cliff/overlay tile atlas from the BINDING VILLAGE'S OWN palette.

Why the palette comes from the village and not from a brief: a world sheet with
cliff art OVERRIDES `_get_cliff_palette()` (BaseVillage: manifest art wins over the
palette). So an atlas invented in new colours silently replaces hand-picked ones --
MapleHeights alone has nine. Deriving the atlas FROM that palette makes the override
a no-op in hue and a gain in detail: same colours, real bitmask edges instead of the
flat procedural drawer.

Geometry is not re-implemented. This imports gen_tile_sheet_medieval and swaps its
PAL, so every world draws the identical, already-side-checked bitmask tiles.

The palette is READ FROM THE VILLAGE SOURCE, never restated here, and the exact
values used are recorded in the manifest entry so a guard can catch the atlas going
stale when someone edits the village's colours.

Usage: tools/gen_tile_sheet_world.py --world suburban --game-repo .
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_tile_sheet_medieval as gen  # noqa: E402  (path set above)

# world -> the village that BINDS that world's sheet key. Only these four qualify:
# each defines height_data (so cliffs are drawn at all) and inherits BaseVillage's
# _get_cliff_sheet_key (so the sheet reaches it). Vertex is deliberately absent --
# it has no height_data, so an abstract atlas would be art nothing draws.
BINDING_VILLAGE = {
    "suburban": "MapleHeightsVillage",
    "steampunk": "BrasstonVillage",
    "industrial": "RivetRowVillage",
    "futuristic": "NodePrimeVillage",
}

# The palette keys the drawing code reads. A village supplying only some of them
# leans on EnvironmentTileSets.DEFAULT_PALETTE for the rest, exactly as the runtime
# does through _pal().
PALETTE_KEYS = list(gen.PAL.keys())


def _parse_gd_palette(text, func_name):
    """`"key": Color(r, g, b[, a])` pairs from one GDScript function body."""
    at = text.find("func %s" % func_name)
    if at < 0:
        return {}
    end = text.find("\nfunc ", at + 1)
    body = text[at:] if end < 0 else text[at:end]
    out = {}
    for m in re.finditer(r'"([a-z_]+)"\s*:\s*Color\(([^)]*)\)', body):
        parts = [p.strip() for p in m.group(2).split(",")]
        try:
            vals = [float(p) for p in parts]
        except ValueError:
            continue
        if len(vals) == 3:
            vals.append(1.0)
        if len(vals) == 4:
            out[m.group(1)] = tuple(vals)
    return out


def resolve_palette(repo, world):
    """Village palette over EnvironmentTileSets.DEFAULT_PALETTE, same order as the runtime."""
    village = BINDING_VILLAGE[world]
    vpath = repo / ("src/maps/villages/%s.gd" % village)
    dpath = repo / "src/exploration/EnvironmentTileSets.gd"
    if not vpath.exists():
        sys.exit("no such village source: %s" % vpath)
    defaults = _parse_gd_palette(dpath.read_text(encoding="utf-8"), "_pal") or {}
    if not defaults:
        # DEFAULT_PALETTE is a const, not a func -- read the const block.
        txt = dpath.read_text(encoding="utf-8")
        i = txt.find("const DEFAULT_PALETTE")
        defaults = _parse_gd_palette("func _x\n" + txt[i:txt.find("\n}", i)], "_x")
    village_pal = _parse_gd_palette(vpath.read_text(encoding="utf-8"), "_get_cliff_palette")
    if not village_pal:
        sys.exit("%s defines no _get_cliff_palette() -- nothing to derive from" % village)
    merged = dict(defaults)
    merged.update(village_pal)
    missing = [k for k in PALETTE_KEYS if k not in merged]
    if missing:
        sys.exit("palette incomplete for %s: missing %s" % (world, ", ".join(missing)))
    return village, village_pal, {k: merged[k] for k in PALETTE_KEYS}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--world", required=True, choices=sorted(BINDING_VILLAGE))
    ap.add_argument("--game-repo", default=os.environ.get("GAME_REPO", ""))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if not args.game_repo:
        sys.exit("pass --game-repo or set GAME_REPO")
    repo = Path(args.game_repo)
    if not repo.exists():
        sys.exit("no such repo: %s" % repo)

    village, village_pal, palette = resolve_palette(repo, args.world)
    print("=== %s: palette derived from %s ===" % (args.world, village))
    print("  %d of %d keys are the village's own; the rest fall back to DEFAULT_PALETTE"
          % (len([k for k in PALETTE_KEYS if k in village_pal]), len(PALETTE_KEYS)))

    gen.PAL = palette  # the ONE difference between worlds
    sheet, regions = gen.build()
    fails = gen.self_check(sheet, regions)
    print("=== bitmask self-check (30 tiles x 4 sides) ===")
    if fails:
        for f in fails:
            print("  FAIL", f)
        sys.exit("bitmask self-check failed -- refusing to write")
    print("  120/120 side assertions pass")

    out_png = repo / ("assets/sprites/tiles/%s.png" % args.world)
    mpath = repo / "data/sprite_manifest.json"
    if args.dry_run:
        print("dry run -- would write %s and register tile_sheets.%s" % (out_png, args.world))
        return

    out_png.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_png)
    print("wrote %s (%dx%d)" % (out_png, sheet.width, sheet.height))

    man = json.loads(mpath.read_text(encoding="utf-8"))
    man.setdefault("tile_sheets", {})[args.world] = {
        "path": "res://assets/sprites/tiles/%s.png" % args.world,
        "tier": "T1",
        "tile": gen.TILE,
        "cliff": regions["cliff"],
        "overlay": regions["overlay"],
        "derived_from": village,
        "derived_palette": {k: list(palette[k]) for k in PALETTE_KEYS},
        "generator": ("tools/gen_tile_sheet_world.py --world %s -- same bitmask geometry as "
                      "medieval, recoloured from %s._get_cliff_palette(). Manifest cliff art "
                      "OVERRIDES that palette, so deriving from it keeps the village's colours "
                      "and adds only detail. derived_palette records what was used: if the "
                      "village's colours change, this atlas is stale and the guard says so."
                      % (args.world, village)),
    }
    mpath.write_text(json.dumps(man, indent=2, ensure_ascii=False) + "\n")
    print("registered tile_sheets.%s (derived_from %s)" % (args.world, village))


if __name__ == "__main__":
    main()
