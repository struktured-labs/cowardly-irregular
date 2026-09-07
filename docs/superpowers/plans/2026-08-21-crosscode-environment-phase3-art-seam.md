# CrossCode Environments — Phase 3 (artist tile-sheet seam) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let artist/AI tile sheets replace procedural tiles, cliff pieces, overlay pieces and props per world through one manifest section, with a partial-set contract: anything a sheet does not name falls through to the procedural drawer.

**Architecture:** `TileSheetManifest` (static, cached like `HybridSpriteLoader`) reads `data/sprite_manifest.json["tile_sheets"]` and hands out 32px-grid `Image` regions by `(sheet_key, section, name)` or `null`. `BaseTileGenerator.create_tileset`, `EnvironmentTileSets.build_*` and `VillageProp._ready` each ask for their region first and draw procedurally on `null`. A pure `validate()` lets a ratchet check the real manifest (paths load, regions in bounds, names known) with a fabricated-bad-entry control.

**Tech Stack:** Godot 4.4.1 / GDScript, `Image.blit_rect`, GUT via `tools/run_tests.sh <name>` (gate on a `Passing N` line AND `$?`).

**Spec:** `docs/superpowers/specs/2026-08-21-crosscode-environment-design.md` §3 (+ §8 "Manifest↔atlas contract").

## Global Constraints
- `.gd` comments 1 line max. Tests never write `user://` or `res://`; synthetic sheets are injected in memory via `TileSheetManifest.set_for_test(sheets, images)` + `reset_for_test()` in `after_each`.
- `tier` stays provenance metadata — nothing reads it to resolve. Artist protection is generation-time (cowir-sprites tooling), not here.
- Region coordinates are in **tile units** (`[col, row]`, props `[col, row, w, h]`); sheet cell size = entry `"tile"` (default 32).
- Partial sets never break a map: a sheet naming ONE tile builds a full tileset.

## Schema (authoritative copy lives in `TileSheetManifest.gd`'s header and `docs/art/tile-sheet-brief-medieval.md`)
```json
"tile_sheets": {
  "medieval": {
    "path": "res://assets/sprites/tiles/medieval.png", "tier": "T2", "tile": 32,
    "tiles":   { "VILLAGE_GRASS": [0,0], "VILLAGE_GRASS:1": [1,0], "VILLAGE_PATH": [2,0] },
    "cliff":   { "face": [0,4], "edge_1": [1,4], "edge_15": [15,4] },
    "overlay": { "fringe_1": [0,5], "stair": [16,5], "ramp": [17,5], "shadow": [18,5] },
    "props":   { "TREE": [0,8,1,3], "STALL": [1,8,2,2] }
  }
}
```
Sheet keys = generator keys: `medieval` (TileGenerator), `suburban`, `steampunk`, `industrial`, `futuristic`, `abstract`. Tile names = the generator's `TileType` enum key, `:N` = variant N. Cliff/overlay names = `EnvironmentTileSets` piece names. Prop names = `VillageProp.Kind` keys.

---

### Task 1: `TileSheetManifest` + contract validator
**Files:** create `src/exploration/TileSheetManifest.gd`; test `test/unit/test_tile_sheet_manifest_regression.gd`; modify `data/sprite_manifest.json` (add `"tile_sheets": {}`).
**Produces:** `static func region(key, section, name, size_tiles := Vector2i(1,1)) -> Image` (null on any miss; `push_warning` only for out-of-bounds/unloadable — a plain absence is silent by design); `has_sheet(key)`; `set_for_test(sheets: Dictionary, images: Dictionary)`; `reset_for_test()`; `static func validate(sheets: Dictionary, images: Dictionary = {}) -> Array` (strings naming each problem); `const GENERATOR_KEYS`.
Steps: failing test (region from injected sheet returns the painted pixels · unknown name → null, no warning · out-of-bounds → null + warning · one-entry sheet: other names null · `validate` = [] on the real manifest, ≥1 on a fabricated entry with a bad name / bad region / missing path) → implement → pass → commit.

### Task 2: generators consult the sheet
**Files:** modify `src/exploration/BaseTileGenerator.gd` (`create_tileset` loop, new virtuals `_get_sheet_key() -> String`, `_get_tile_type_name(type) -> String`), the six generators (one-liners), test `test/unit/test_tile_sheet_generator_fallthrough_regression.gd`.
Steps: inject `{"medieval": {tiles: {"VILLAGE_GRASS": [0,0], "VILLAGE_GRASS:1": [1,0]}}}` with a magenta/cyan image → `TileGenerator.new().create_tileset()` atlas pixel at id 30 is magenta, id 35 is cyan, id 31 (path) is NOT magenta (procedural) · a generator with key "" never consults the manifest · commit.

### Task 3: cliff / overlay pieces consult the sheet
**Files:** modify `src/exploration/EnvironmentTileSets.gd` (`build_cliff_tileset(palette, sheet_key := "")`, `build_overlay_tileset(palette, sheet_key := "")`, piece names `face`, `edge_<mask>`, `fringe_<mask>`, `stair`, `ramp`, `shadow`), `src/maps/villages/BaseVillage.gd` passes `tile_generator._get_sheet_key()`; extend `test_environment_tilesets_regression.gd`.
Steps: inject cliff `{"face": [0,0]}` magenta → face tile pixel magenta, `edge_1` still procedural, collision polygons UNCHANGED by art (the contract: art never moves colliders) · commit.

### Task 4: props consult the sheet
**Files:** modify `src/exploration/VillageProp.gd` (`sheet_key` member set by `BaseVillage._add_prop`; `_ready` tries `TileSheetManifest.region(sheet_key, "props", Kind.keys()[kind], SIZES[kind])`), extend `test_village_prop_regression.gd`.
Steps: inject props `{"TREE": [0,0,1,3]}` → tree sprite texture is the sheet region (size 32×96, magenta), BARREL still procedural; footprint/collider unchanged · commit.

### Task 5: brief + docs + gate + fold
**Files:** create `docs/art/tile-sheet-brief-medieval.md` (every name the engine will ask for, sizes, palette anchors from `TileGenerator.PALETTES`/`EnvironmentTileSets.DEFAULT_PALETTE`, the partial-set contract, the refusal rules); CLAUDE.md bullet; send the brief to cowir-sprites via intercom.
Steps: full gate in the background (capture `$?`), fold, tag `v3.33.209-alpha` (bump `Version.SEMVER`).
