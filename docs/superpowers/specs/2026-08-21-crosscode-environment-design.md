# CrossCode-Style Environments for Villages and Dungeons — Design

**Date:** 2026-08-21 · **Owner:** cowir-main · **Status:** approved by struktured (sections 1–9); phases 1–2 implemented on `feat/crosscode-environments-p1` (2026-08-21); phases 3–4 pending their own plans

## Context

struktured (2026-08-21): *"crosscode: learn from the amazing environment/art style — I'd like to use it for my dungeons and villages at the minimum … it has multiple levels/layers and if you go down stairs or up/down it slows the character down which is nice."*

What CrossCode actually does (Radical Fish devlogs, not fan analysis): height is the architecture. Their editor positions entities in 3D; maps have multiple walkable levels; **cliff faces are generated from a height map** by a tool that was later made terrain-aware; per-area tilesets are a shared cliff vocabulary with surface skins (Bergen Trail = Autumn Rise cliffs + new grass/snow). Towns are density + landmarks (Rookie Harbor: five large maps of buildings, NPCs, plazas, market stalls; interiors authored separately). Internal resolution 568×320 at 16 px tiles ≈ 35×20 tiles on screen. Movement between levels is a low auto-jump; dropping off a slope without jumping requires approaching slowly — speed and elevation are coupled. They name depth perception on a flat screen as their hardest readability problem.

What we have (survey 2026-08-21, verified in source): every village and dungeon is **one `TileMapLayer`** of per-pixel GDScript tiles (~16 k lines of `set_pixel`); `get_tile_id()` collapses every type to one atlas index, so the **16 authored variants are dead art**; no terrain transitions; **no elevation concept**; **no Y-sort** (a tall prop renders under the player); outdoor lighting is a fullscreen multiply `ColorRect` while interiors already run ~20 `PointLight2D`; props are 3–6 Sprite2D classes per village; **no artist-tile pipeline** (the treasure chest is the only hand-drawn environment object); dungeons are two grey tiles; every W2–W6 village is painted with the **medieval** generator while five per-world generators sit unused outside overworlds. The one seam every map funnels through is `BaseTileGenerator.create_tileset()`; the only artist-PNG-preferred precedent is `BattleBackground._try_load_artist_backdrop()`. Harmonia: 36×30 tiles, camera zoom 2.0 → 20×11 tiles on screen.

## Decisions (forks settled with struktured)

| Fork | Decision |
|---|---|
| Elevation depth | **Look + slope-speed, walk-only.** Real height data, cliffs, tiers, stairs that slow you. No jumping, no falling, no per-tier collision. |
| First target | **Harmonia** (W1 hub) — sets the tile vocabulary every village inherits. |
| Tile source | **Hybrid.** Engine work on procedural tiles as the universal fallback + a `tile_sheets` manifest seam for artist/AI sheets via the sprite lane. |
| Approach | **A — layer cake on the ASCII pipeline.** Keep text maps; add a parallel height grid; derive everything. |

## 1. Layer model

`map_data` (terrain legend) is unchanged. Each map gains a parallel `height_data: Array[String]` of digits `0–3`, same dimensions; absent → all `0` (today's behaviour, every existing map valid). At build time the two grids derive:

| Layer | Node | Content |
|---|---|---|
| Ground | `TileMapLayer` | terrain tiles; **terrain-set transitions** at type boundaries; **variant per cell** seeded by `(x, y)` (resurrects the dead variants) |
| Cliff | `TileMapLayer` | **derived**: wherever `h(cell) > h(south neighbour)` a cliff FACE on the high cell's south edge; lips on W/E/N edges of a higher tier; corners from the 8-neighbourhood. Never authored. |
| Overlay | `TileMapLayer` | stairs/ramps (the only tier connectors), decals |
| Props | `Node2D` with `y_sort_enabled` | buildings, trees, stalls… Sprite2D with base-anchored sort origin + blocked-cell footprint |
| Lights | `CanvasModulate` + `PointLight2D` | reused from the interior pattern |

Cliff derivation is a pure function `derive_cliffs(height_data) -> Dictionary[cell -> piece]`, unit-testable without a scene.

## 2. Elevation and movement

Walkability gains one rule: **a step from cell A to adjacent cell B is legal iff `h(A) == h(B)`, or B (or A) is a stair/ramp cell that connects those heights.** A height step with no stair is a wall — a cliff edge blocks by construction. `_is_cell_walkable(cell)` remains the game-wide authority (unchanged semantics: "cell is not solid"); a new `_can_step(from, to)` carries the height rule and is what movement and the path/flood-fill tests consult. Concretely: a stair/ramp cell is a `map_data` legend char (`^` stair, `/` ramp) whose own height digit is its LOWER end; `_can_step` permits `|h(A) - h(B)| == 1` only when A or B is such a cell, so one stair cell bridges exactly one tier. Stairs/ramps carry a speed modifier of **0.6** (same scale as mud/snow today) through the **existing terrain-speed system** (`_get_terrain_speed_modifier` seam); villages are flat (no Mode 7), so the authored-layer lookup is the correct layer there. Out of scope: jump, fall, per-tier collision layers, height indicators.

## 3. Tile vocabulary and the artist seam

`create_tileset()` consults a new `tile_sheets` section of `data/sprite_manifest.json` before drawing procedurally:

```json
"tile_sheets": {
  "medieval": {
    "path": "res://assets/sprites/tiles/medieval.png", "tier": "T2",
    "tiles":       { "VILLAGE_GRASS": [0,0], "VILLAGE_GRASS:1": [1,0], "VILLAGE_PATH": [2,0] },
    "cliff":       { "face": [0,4], "face_w": [1,4], "face_e": [2,4], "lip_n": [3,4], "corner_sw": [4,4], "stair": [5,4], "ramp": [6,4] },
    "transitions": { "VILLAGE_GRASS>VILLAGE_PATH": [[0,6],[1,6],[2,6]] }
  }
}
```

**Partial-set contract:** any tile, cliff piece, or transition the sheet does not name falls through to the procedural drawer. A half-finished sheet never breaks a map; W2–W6 get the procedural result until their sheets exist. `tier` is provenance only (nothing reads it); generation-time refusal protects artist work, per the sprite-lane rules. Atlas coordinates the rest of the game sees do not change — `_get_atlas_coords()` callers are untouched.

**First commission (Harmonia, via cowir-sprites):** medieval cliff set (9-slice faces + corners + stair + ramp ≈ 14), 4 variants each of grass/path/dirt/flower (16), grass↔path↔dirt↔water transitions (≈ 24 via terrain-set layout), ~12 props: market stall, lamp post, barrel, crate, tree (3 tiles tall), fence segment, hanging sign, awning, well, planter, banner, cart. ≈ 70 tiles + 12 props.

## 4. Props and Y-sort

`Props` (`Node2D`, `y_sort_enabled = true`) replaces the flat `buildings` container. A prop = Sprite2D + sort origin at its base + footprint of blocked cells merged into the walkability grid. Existing `VillageInn/Shop/Bar/Fountain` move in unchanged apart from origin + footprint. Enables the currently impossible: the player walks behind a tree; an awning occludes; a lamp stands in front of a wall.

## 5. Lighting and atmosphere

The fullscreen-multiply `DayNightOverlay` becomes a per-scene `CanvasModulate` driven by the same phase curve, so `PointLight2D` lamps and windows pierce the dusk instead of being multiplied into it. Dungeons drop the "caves are lightless" exclusion: per-cave modulate + torch/crystal point lights. `WeatherSystem` and `ZoneParticles` (overworld-only today) are wired for villages and dungeons. Accessibility masters (`reduce_flashes`) rank above any light flicker.

## 6. Harmonia rework (the proof)

Same 36×30 footprint, existing CastleVista on the north edge, three tiers authored as ~15 lines of digits:

- **Tier 2 — castle approach** (north): fountain, banners, two lamp posts.
- **Tier 1 — town** (middle): inn, shop, bar, houses; a **wide stair** down from tier 2; cliff faces along the tier edge with fence on the lip.
- **Tier 0 — market and gate** (south): stalls, crates, barrels, cart; exit `X` unmoved; a narrower stair down from the town so the gate reads as descent.

**Hard rule:** every staged-cutscene puppet path and NPC mark stays on same-height walkable cells, or the cutscene JSON is re-synced deliberately. The July-resize coord-sync regression test and the Harmonia staged-scene smoke are the canaries, run first.

## 7. Cheap broad win

`_get_tile_generator()` virtual on `BaseVillage._setup_scene` and `DragonCave._setup_scene` routes each map through its world's generator (the five finished per-world generators). Side dish: every later world looks like itself; the same seam the artist sheets plug into.

## 8. Verification

House-style, each mutation-proven with the count predicted first:
- **Height-grid integrity** — on every map, every height step between adjacent walkable cells has a connecting stair/ramp or is impassable (Section 2's rule, asserted over the corpus).
- **Cliff derivation** — pure-function tests: `2` beside `1` yields a face; removing the stair seals the tier; 8-neighbour corners.
- **Slope-speed** — stair cells return the modifier through the real terrain-speed path.
- **Manifest↔atlas contract** — every named region lies inside its PNG; unnamed tiles fall through (a sheet with ONE entry still builds a full tileset).
- **Y-sort** — `Props` has `y_sort_enabled`; every prop's sort origin at its base.
- **Parsers** — walkability / connectivity tests gain the height grid.
- **Canaries** — `test_staged_scene_live_geometry_smoke`, `test_harmonia_staged_scene_coord_sync_regression`, `test_village_reachability_framework`.
- **Pixels** — render-smoke screenshots of Harmonia at dawn/noon/night; the deliverable is visual, so the gate looks at pixels, not only asserts.

## 9. Phasing

1. **Engine** — layers, transitions, variants, height + cliff derivation, `_can_step` + slope-speed, Y-sort props, lighting; all on procedural tiles; suite green.
2. **Harmonia** — height grid, three tiers, props, lights, cutscene sync; screenshots.
3. **Art seam** — `tile_sheets` + fallthrough + manifest contract test; sprite-lane brief sent; sheets land when they land.
4. **Scale-out** — world generators for W2–W6 villages/dungeons; Whispering Cave as first dungeon (dark + pools of light).

Each phase independently shippable and gated. **Out of scope** (later specs if wanted): jumping/falling, per-tier collision, scene-authored maps, height-map-first authoring, height indicators.

## Risks

- Geometry tests parse ASCII legends; the height grid must be parsed by the same tests or they go blind to tier walls. Addressed in §8.
- Cutscene coordinates are hardcoded pixels (July resize precedent). Addressed by the §6 hard rule + canaries.
- `_is_cell_walkable` has 4+ dependants; its meaning is preserved, the height rule lives in `_can_step`.
- CrossCode's own unsolved problem — depth perception on a flat screen — applies here. Mitigation: cliff faces are tall and shaded, stairs are visually distinct, and tiers differ by at least one full cliff-face height; no attempt at height indicators.
