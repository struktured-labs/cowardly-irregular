# Tile-sheet brief — Medieval (Harmonia / W1 villages)

**For:** cowir-sprites · **Engine seam:** `TileSheetManifest` (`src/exploration/TileSheetManifest.gd`) · **Ships when:** any subset is ready — the seam is partial-set by contract.

## How it plugs in
1. One PNG on a 32-px grid: `assets/sprites/tiles/medieval.png` (any width/height; transparent background — an opaque backdrop is the known gpt-image-1 defect class, the validator cannot see it, the screenshot can).
2. Register it under `data/sprite_manifest.json` → `"tile_sheets"."medieval"` (schema below). Regions are in **tile units**. `tier` is provenance only.
3. Anything you do NOT name keeps its procedural drawing. Name one tile and the map still builds. Colliders and prop footprints are data — art never moves them.
4. Verify: `tools/run_tests.sh tile_sheet_manifest_regression` (names + bounds + path), then `tools/village_screenshot.sh harmonia` and look at `tmp/screens/harmonia_0.{07,30,65}.png`.

```json
"tile_sheets": {
  "medieval": {
    "path": "res://assets/sprites/tiles/medieval.png", "tier": "T2", "tile": 32,
    "tiles":   { "VILLAGE_GRASS": [0,0], "VILLAGE_GRASS:1": [1,0], "VILLAGE_GRASS:2": [2,0], "VILLAGE_PATH": [3,0] },
    "cliff":   { "face": [0,4], "edge_1": [1,4] },
    "overlay": { "stair": [0,5], "shadow": [1,5] },
    "props":   { "TREE": [0,8,1,3], "STALL": [1,8,2,2] }
  }
}
```

## Names the engine asks for (exact spelling)
**tiles** — `TileGenerator.TileType` keys; `:N` = variant N (only the variants listed exist in the atlas):
- Harmonia priority: `VILLAGE_GRASS`, `VILLAGE_GRASS:1`, `VILLAGE_GRASS:2`, `VILLAGE_PATH`, `VILLAGE_PATH:1`, `VILLAGE_DIRT`, `VILLAGE_DIRT:1`, `VILLAGE_FLOWER`, `VILLAGE_FLOWER:1`, `VILLAGE_HEDGE`, `WALL`, `WATER`, `WATER:1`…`WATER:4` (animation frames)
- The rest of the W1 vocabulary (overworld + caves): `GRASS`(+:1,:2), `FOREST`(+:1), `MOUNTAIN`(+:1), `PATH`, `BRIDGE`, `CAVE_ENTRANCE`, `VILLAGE_GATE`, `FLOOR`, `CAVE_FLOOR`, `CAVE_WALL`, `SAND`(+:1), `ICE`(+:1), `SNOW_TREE`, `SWAMP`, `DARK_GROUND`, `COAST`, `LAVA`(+:1)

**cliff** (32×32 each): `face` — the vertical ledge wall, drawn on the cell BELOW a tier edge; top 2-3 px read as the lit lip · `edge_1`…`edge_15` — transparent tiles with a thin lip/shadow on the flagged sides, bitmask **N=1 E=2 S=4 W=8** (e.g. `edge_3` = north+east). `edge_0` is never painted.

**overlay** (32×32, transparent except the art): `fringe_1`…`fringe_15` — grass tufts creeping onto a path/dirt cell from the flagged sides (same bitmask = which neighbours are grass) · `stair` (treads run north–south, one tile bridges one tier) · `ramp` · `shadow` (the ledge's cast shadow: ~12 px alpha gradient from the top edge, painted on the cell under a face).

**props** (transparent, origin = bottom-centre of the base row; the base row is the blocked footprint): `TREE` 1×3 · `LAMP_POST` 1×2 (glass head ≈50 px above the base — the PointLight2D parks there) · `BARREL` 1×1 · `CRATE` 1×1 · `STALL` 2×2 (awning on top row) · `FENCE` 1×1 · `WELL` 2×2 · `BANNER` 1×2 (hangs on a wall, no footprint) · `CART` 2×2 · `PLANTER` 1×1.

## Style anchors
- Same 16-bit read as the party/monster sheets (see `feedback_artist_style`); 32-px tiles at camera zoom 2 = 64 screen px, so 1-px detail survives.
- Procedural palette to stay near (so a half-finished sheet sits beside procedural neighbours): `TileGenerator.PALETTES[VILLAGE_*]` for ground; `EnvironmentTileSets.DEFAULT_PALETTE` — face_dark `(0.30,0.26,0.24)`, face_mid `(0.46,0.40,0.36)`, face_light `(0.60,0.54,0.48)`, lip `(0.82,0.78,0.66)`, grass `(0.38,0.62,0.28)`, stair_tread `(0.72,0.68,0.60)`.
- Depth is the whole point (CrossCode's hardest problem): faces need a bright top edge and a near-black foot; stairs must read as stairs from 2 tiles away.

## Rules (unchanged)
- Never overwrite an artist asset; new sheets are `tier: "T1"` until reviewed. `tools/audit_sprite_tiers.py` checks git, not the manifest.
- Later worlds reuse this exact name list under `suburban` / `steampunk` / `industrial` / `futuristic` / `abstract` with their own `TileType` vocabularies (`TileSheetManifest.GENERATOR_KEYS`).
