# CrossCode Environments — Phase 1 (engine) + Phase 2 (Harmonia) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give villages real elevation (tiers, derived cliffs, stairs that slow you), Y-sorted props, per-cell tile variants, grass-fringe transitions and outdoor point lighting — all on procedural tiles — and carve Harmonia into three tiers as the proof.

**Architecture:** Villages stay ASCII `map_data`; each gains a parallel `height_data` digit grid. A pure module (`HeightGrid`) derives cliff faces/edge colliders and owns the walk-only step rule; `BaseVillage` paints three `TileMapLayer`s (Ground / Cliffs / Overlay) from it, keeps `_is_cell_walkable` as the authority and adds `_can_step`. Props are a Y-sorted `VillageProp` node with a footprint; lighting is a per-scene `CanvasModulate` + `PointLight2D` lamps driven by the existing day-phase curve. Slope speed rides the existing terrain-speed seam through one early-return hook.

**Tech Stack:** Godot 4.4.1 / GDScript, TileMapLayer + TileSetAtlasSource (procedural `Image` atlases), CanvasModulate + PointLight2D, GUT tests via `tools/run_tests.sh <name>`.

**Spec:** `docs/superpowers/specs/2026-08-21-crosscode-environment-design.md` (sections 1, 2, 4, 5, 6, 8, 9 — phases 1 and 2). Sections 3 and 7 (art seam, world generators) are later plans. Two deliberate narrowings inside phase 1: terrain transitions ship as a procedural grass-fringe overlay (the full terrain-set blob arrives with artist sheets in phase 3), and weather/zone particles for villages + dungeon lighting move to phase 4 with the dungeon work.

## Global Constraints

- `.gd` comments are **1 line max** (`##` doc comments included).
- Tests must **never write `user://`**; builders must not save debug PNGs.
- Never divide durations or speeds by battle speed; speed modifiers multiply.
- `_is_cell_walkable(cell)` keeps its meaning ("cell is not solid"); the height rule lives in `_can_step(from, to)`.
- Cliff faces are **derived, never authored**. Stair chars: `^` (stair), `/` (ramp); a stair cell's own height digit is its LOWER end; `_can_step` permits `|Δh| == 1` only when one end is a stair/ramp. Stair speed modifier = **0.6**.
- `height_data` absent → all heights 0 → existing behaviour (every existing map stays valid).
- Staged-cutscene puppet marks and walk paths must stay on same-height walkable cells (or cross only via stairs) — `world1_chapter1.json` and `world1_harmonia_after_cave.json`.
- Accessibility: no light flicker; `reduce_flashes` / `screen_shake_enabled` untouched.
- Run single tests with `tools/run_tests.sh <name>` (name = file without `test_`/`.gd`). Gate the full suite in the background: `tools/run_tests.sh > tmp/gate.log 2>&1; EC=$?` then `grep -E "^  (Passing|Failing)" tmp/gate.log` and `test $EC -eq 0`.
- New `class_name` files need `godot --headless --audio-driver Dummy --import --quit` before tests can see them.
- Feature branch, never main: `git worktree add ../cowir-crosscode -b feat/crosscode-environments-p1` (or work on a branch in this checkout if no other lane shares it). Commit per task.

---

## File Map

| File | Responsibility |
|---|---|
| `src/exploration/HeightGrid.gd` (new) | Pure static math: parse digit rows, `height_at`, `stair_cells`, `can_step`, `derive` (faces + edge masks). No scene access. |
| `src/exploration/EnvironmentTileSets.gd` (new) | Builds the Cliff TileSet (16 edge-mask tiles with strip colliders + 1 full-collision face) and the Overlay TileSet (16 grass-fringe masks + stair + ramp). |
| `src/exploration/VillageProp.gd` (new) | Y-sorted procedural prop: origin at base, footprint → StaticBody2D. |
| `src/exploration/VillageLighting.gd` (new) | CanvasModulate tracking `GameState.day_phase` via `DayNightOverlay.tint_for_phase`; `add_lamp()` PointLight2D that fades in with dusk. |
| `src/maps/villages/BaseVillage.gd` (modify) | Three layers, Y-sort containers, `_build_derived_layers`, `_is_cell_walkable` + `_can_step`, `get_terrain_speed_at`, `_add_prop`, `_setup_lighting`, `_atlas_for`. |
| `src/exploration/TileGenerator.gd` (modify) | `VARIANT_IDS` + `get_tile_id_variant(type, salt)`. |
| `src/exploration/OverworldPlayer.gd` (modify) | 3-line early return in `_get_terrain_speed_modifier` delegating to the parent when it has `get_terrain_speed_at`. |
| `src/GameLoop.gd` (modify) | Overlay tint off for scenes that report `has_scene_lighting()`; day-clock unchanged. |
| `src/maps/villages/HarmoniaVillage.gd` (modify) | `height_data`, stair chars, 4 NPC relocations, props, lamps, `_build_derived_layers` call, variant atlas coords. |
| `test/unit/helpers/village_grid_source.gd` (new) | Test-side parser for `map_data` / `height_data` / blocked chars shared by the source audits. |
| `test/unit/test_height_grid_derivation.gd` (new) | Pure-function tests for `HeightGrid`. |
| `test/unit/test_environment_tilesets_regression.gd` (new) | Tile counts, collision strips per mask, face full collision, stair no collision. |
| `test/unit/test_village_layers_regression.gd` (new) | Synthetic village: layers exist, faces block, `_can_step` matrix, fringe masks, height-less village unchanged. |
| `test/unit/test_slope_speed_regression.gd` (new) | Stair cell → 0.6 through the player's real seam; non-village parent untouched. |
| `test/unit/test_tile_variants_regression.gd` (new) | Deterministic per-cell variant, spread, type-correct ids. |
| `test/unit/test_village_prop_regression.gd` (new) | Y-sort containers, base origin, footprint blocks walkability + physics. |
| `test/unit/test_village_lighting_regression.gd` (new) | Modulate equals overlay tint per phase; lamps dark at noon, lit at night; GameLoop hands off. |
| `test/unit/test_village_height_grid_integrity.gd` (new) | Every village with `height_data`: dims match, no `|Δh| ≥ 2` between open cells, faces never on stairs/marks. |
| `test/unit/test_harmonia_tiers_regression.gd` (new) | Harmonia: three tiers, 8 stair cells, staged marks/paths legal, runtime flood fill reaches every NPC. |
| `test/unit/test_village_npc_connectivity.gd` (modify) | Height-aware 4-connectivity via the helper. |
| `test/unit/test_village_placement_walkability.gd` (modify) | Marks must not sit on derived face cells. |
| `test/unit/test_village_map_data_ragged_row_lint.gd` (modify) | `height_data` rows match `MAP_WIDTH`/`MAP_HEIGHT`. |
| `test/unit/test_staged_scene_live_geometry_smoke.gd` (modify) | Walk segments consult `_can_step` between successive cells. |

---

### Task 1: HeightGrid — pure derivation module

**Files:**
- Create: `src/exploration/HeightGrid.gd`
- Test: `test/unit/test_height_grid_derivation.gd`

**Interfaces:**
- Produces (all `static`):
  - `HeightGrid.parse(rows: Array) -> Array` — `Array` of `Array[int]`, one per row.
  - `HeightGrid.height_at(grid: Array, cell: Vector2i) -> int` — `-1` off-grid.
  - `HeightGrid.stair_cells(map_rows: Array) -> Dictionary` — `{Vector2i: "^"|"/"}`.
  - `HeightGrid.can_step(grid: Array, stairs: Dictionary, from: Vector2i, to: Vector2i) -> bool`.
  - `HeightGrid.derive(grid: Array, stairs: Dictionary, walls: Dictionary = {}) -> Dictionary` — `{"faces": {Vector2i: true}, "edges": {Vector2i: int_mask}}`.
  - Constants `EDGE_N = 1, EDGE_E = 2, EDGE_S = 4, EDGE_W = 8`, `STAIR_CHARS = ["^", "/"]`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## HeightGrid is the pure math under village elevation: faces hang SOUTH of a step onto
## the lower cell, every other illegal step is an edge bit on the higher cell, and stairs
## are the only one-tier connectors. Scene-free so it can be exhaustive.

const HG := preload("res://src/exploration/HeightGrid.gd")


func _grid(rows: Array) -> Array:
	return HG.parse(rows)


func test_parse_and_height_at() -> void:
	var g := _grid(["012", "333"])
	assert_eq(HG.height_at(g, Vector2i(2, 0)), 2)
	assert_eq(HG.height_at(g, Vector2i(0, 1)), 3)
	assert_eq(HG.height_at(g, Vector2i(5, 0)), -1, "off-grid x reads -1")
	assert_eq(HG.height_at(g, Vector2i(0, 9)), -1, "off-grid y reads -1")
	assert_eq(HG.parse([]).size(), 0, "empty height data parses to an empty grid")


func test_stair_cells_reads_both_chars() -> void:
	var s := HG.stair_cells(["g^g", "g/g"])
	assert_eq(s.size(), 2)
	assert_eq(s[Vector2i(1, 0)], "^")
	assert_eq(s[Vector2i(1, 1)], "/")


func test_can_step_same_height_true_and_cliff_false() -> void:
	var g := _grid(["22", "11"])
	assert_true(HG.can_step(g, {}, Vector2i(0, 0), Vector2i(1, 0)), "same height is walkable")
	assert_false(HG.can_step(g, {}, Vector2i(0, 0), Vector2i(0, 1)), "a one-tier drop with no stair is a wall")
	assert_false(HG.can_step(g, {}, Vector2i(0, 1), Vector2i(0, 0)), "and so is the climb")
	assert_false(HG.can_step(g, {}, Vector2i(0, 0), Vector2i(0, -1)), "off-grid is never steppable")


func test_stair_bridges_exactly_one_tier() -> void:
	var g := _grid(["2", "1", "0"])
	var stairs := {Vector2i(0, 1): "^"}
	assert_true(HG.can_step(g, stairs, Vector2i(0, 0), Vector2i(0, 1)), "2 -> stair@1 legal")
	assert_true(HG.can_step(g, stairs, Vector2i(0, 1), Vector2i(0, 2)), "stair@1 -> 0 same height legal")
	var two := _grid(["3", "1"])
	assert_false(HG.can_step(two, {Vector2i(0, 1): "^"}, Vector2i(0, 0), Vector2i(0, 1)), "a stair never bridges two tiers")


func test_south_step_paints_face_on_lower_cell() -> void:
	var g := _grid(["222", "111"])
	var out := HG.derive(g, {})
	assert_eq(out["faces"].size(), 3, "every lower cell under the ledge gets a face")
	assert_true(out["faces"].has(Vector2i(1, 1)))
	assert_eq(out["edges"].size(), 0, "a pure south step needs no edge strips")


func test_stair_cell_gets_no_face_and_wall_cell_gets_no_face() -> void:
	var g := _grid(["222", "111"])
	var out := HG.derive(g, {Vector2i(1, 1): "^"}, {Vector2i(2, 1): true})
	assert_false(out["faces"].has(Vector2i(1, 1)), "stair is the connector, never a face")
	assert_false(out["faces"].has(Vector2i(2, 1)), "a wall already blocks; no face overdraw")
	assert_true(out["faces"].has(Vector2i(0, 1)))


func test_west_east_north_steps_become_edge_bits_on_the_higher_cell() -> void:
	# A raised 1x1 plaza in a field: its W/E/N sides are lips, its S side is a face.
	var g := _grid(["000", "010", "000"])
	var out := HG.derive(g, {})
	var c := Vector2i(1, 1)
	assert_eq(int(out["edges"].get(c, 0)), HG.EDGE_N | HG.EDGE_E | HG.EDGE_W, "three lips on the high cell")
	assert_true(out["faces"].has(Vector2i(1, 2)), "south face on the lower cell")
	assert_false(out["edges"].has(Vector2i(0, 1)), "lower cells carry no bits — the high cell owns the edge")


func test_flat_grid_derives_nothing() -> void:
	var out := HG.derive(_grid(["000", "000"]), {})
	assert_eq(out["faces"].size(), 0)
	assert_eq(out["edges"].size(), 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tools/run_tests.sh height_grid_derivation`
Expected: exit 3 / parse failure — `res://src/exploration/HeightGrid.gd` does not exist.

- [ ] **Step 3: Write the module**

```gdscript
class_name HeightGrid
extends RefCounted
## Pure height-grid math for villages: digit rows in, cliff pieces + the walk-only step rule out. No scene access.

const EDGE_N := 1
const EDGE_E := 2
const EDGE_S := 4
const EDGE_W := 8
const STAIR_CHARS := ["^", "/"]
const DIRS := {EDGE_N: Vector2i(0, -1), EDGE_E: Vector2i(1, 0), EDGE_S: Vector2i(0, 1), EDGE_W: Vector2i(-1, 0)}


static func parse(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var line: Array[int] = []
		var s := str(r)
		for i in range(s.length()):
			line.append(int(s[i]))
		out.append(line)
	return out


static func height_at(grid: Array, cell: Vector2i) -> int:
	if cell.y < 0 or cell.y >= grid.size():
		return -1
	var row: Array = grid[cell.y]
	if cell.x < 0 or cell.x >= row.size():
		return -1
	return int(row[cell.x])


static func stair_cells(map_rows: Array) -> Dictionary:
	var out := {}
	for y in range(map_rows.size()):
		var row := str(map_rows[y])
		for x in range(row.length()):
			if row[x] in STAIR_CHARS:
				out[Vector2i(x, y)] = row[x]
	return out


## Same height, or a ONE-tier step where either end is a stair/ramp.
static func can_step(grid: Array, stairs: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	var a := height_at(grid, from)
	var b := height_at(grid, to)
	if a < 0 or b < 0:
		return false
	if a == b:
		return true
	return absi(a - b) == 1 and (stairs.has(from) or stairs.has(to))


## A south step paints a FACE onto the lower cell (unless it is a wall or stair); every other illegal step becomes an edge bit on the HIGHER cell.
static func derive(grid: Array, stairs: Dictionary, walls: Dictionary = {}) -> Dictionary:
	var faces := {}
	var edges := {}
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var c := Vector2i(x, y)
			var h := height_at(grid, c)
			for bit in DIRS:
				var n: Vector2i = c + DIRS[bit]
				var hn := height_at(grid, n)
				if hn < 0 or hn >= h or can_step(grid, stairs, c, n):
					continue
				if bit == EDGE_S:
					if not walls.has(n) and not stairs.has(n):
						faces[n] = true
				else:
					edges[c] = int(edges.get(c, 0)) | bit
	return {"faces": faces, "edges": edges}
```

- [ ] **Step 4: Import, run, verify pass**

Run: `godot --headless --audio-driver Dummy --import --quit >/dev/null 2>&1; tools/run_tests.sh height_grid_derivation`
Expected: `Passing 8 · Failing 0`, exit 0.

- [ ] **Step 5: Mutation check, then commit**

Flip `hn >= h` to `hn > h` in `derive`, rerun: `test_flat_grid_derives_nothing` and the face test must go red. Revert.

```bash
git add src/exploration/HeightGrid.gd src/exploration/HeightGrid.gd.uid test/unit/test_height_grid_derivation.gd
git commit -m "feat(env): HeightGrid — pure cliff derivation + walk-only step rule"
```

---

### Task 2: EnvironmentTileSets — cliff and overlay tilesets

**Files:**
- Create: `src/exploration/EnvironmentTileSets.gd`
- Test: `test/unit/test_environment_tilesets_regression.gd`

**Interfaces:**
- Produces (all `static`):
  - `EnvironmentTileSets.build_cliff_tileset(palette: Dictionary = {}) -> TileSet` — atlas ids 0–15 edge masks (collision strip per set bit), `FACE_ID = 16` full collision.
  - `EnvironmentTileSets.build_overlay_tileset(palette: Dictionary = {}) -> TileSet` — ids 0–15 grass fringe masks, `STAIR_ID = 16`, `RAMP_ID = 17`, no collision anywhere.
  - `EnvironmentTileSets.atlas_coords(id: int) -> Vector2i` — single-row atlas: `Vector2i(id, 0)`.
  - `TILE = 32`, `EDGE_THICKNESS = 4.0`.
- Consumes: `HeightGrid.EDGE_*` bit meanings (N=1 E=2 S=4 W=8).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## The two derived-layer tilesets. Collision geometry is the contract: a mask tile carries
## exactly one 4px strip per set bit on the matching side, the face blocks the whole cell,
## and nothing on the overlay sheet blocks anything.

const ETS := preload("res://src/exploration/EnvironmentTileSets.gd")
const HG := preload("res://src/exploration/HeightGrid.gd")


func _source(ts: TileSet) -> TileSetAtlasSource:
	return ts.get_source(ts.get_source_id(0)) as TileSetAtlasSource


func test_cliff_tileset_has_17_tiles_and_a_physics_layer() -> void:
	var ts := ETS.build_cliff_tileset()
	assert_eq(ts.get_physics_layers_count(), 1)
	assert_eq(ts.get_physics_layer_collision_layer(0), 1, "walls live on physics layer 1 (player mask)")
	var src := _source(ts)
	assert_eq(src.get_tiles_count(), 17)
	for id in range(17):
		assert_true(src.has_tile(ETS.atlas_coords(id)), "tile %d present" % id)


func test_mask_tiles_carry_one_strip_per_bit_on_the_right_side() -> void:
	var src := _source(ETS.build_cliff_tileset())
	var half := ETS.TILE / 2.0
	for mask in range(16):
		var td := src.get_tile_data(ETS.atlas_coords(mask), 0)
		var bits := 0
		for b in [1, 2, 4, 8]:
			if mask & b:
				bits += 1
		assert_eq(td.get_collision_polygons_count(0), bits, "mask %d has %d strips" % [mask, bits])
	# Side check on the single-bit tiles: every vertex of the N strip sits in the top 4px, etc.
	var checks := {HG.EDGE_N: func(p: Vector2) -> bool: return p.y <= -half + ETS.EDGE_THICKNESS,
		HG.EDGE_S: func(p: Vector2) -> bool: return p.y >= half - ETS.EDGE_THICKNESS,
		HG.EDGE_W: func(p: Vector2) -> bool: return p.x <= -half + ETS.EDGE_THICKNESS,
		HG.EDGE_E: func(p: Vector2) -> bool: return p.x >= half - ETS.EDGE_THICKNESS}
	for bit in checks:
		var td := src.get_tile_data(ETS.atlas_coords(bit), 0)
		for p in td.get_collision_polygon_points(0, 0):
			assert_true(checks[bit].call(p), "bit %d vertex %s on its side" % [bit, p])


func test_mask_zero_and_face() -> void:
	var src := _source(ETS.build_cliff_tileset())
	assert_eq(src.get_tile_data(ETS.atlas_coords(0), 0).get_collision_polygons_count(0), 0, "mask 0 is inert")
	var face := src.get_tile_data(ETS.atlas_coords(ETS.FACE_ID), 0)
	assert_eq(face.get_collision_polygons_count(0), 1)
	var pts := face.get_collision_polygon_points(0, 0)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	assert_eq(r.size, Vector2(ETS.TILE, ETS.TILE), "face blocks the whole cell")


func test_overlay_tileset_is_walkable_everywhere() -> void:
	var ts := ETS.build_overlay_tileset()
	var src := _source(ts)
	assert_eq(src.get_tiles_count(), 18)
	for id in range(18):
		assert_eq(src.get_tile_data(ETS.atlas_coords(id), 0).get_collision_polygons_count(0), 0, "overlay %d never blocks" % id)


func test_face_and_stair_tiles_are_not_blank() -> void:
	var cliff := _source(ETS.build_cliff_tileset()).texture.get_image()
	var face_px := cliff.get_pixel(ETS.FACE_ID * ETS.TILE + 16, 16)
	assert_gt(face_px.a, 0.9, "face tile is painted")
	var overlay := _source(ETS.build_overlay_tileset()).texture.get_image()
	var stair_px := overlay.get_pixel(ETS.STAIR_ID * ETS.TILE + 16, 16)
	assert_gt(stair_px.a, 0.9, "stair tile is painted")
	var blank := overlay.get_pixel(16, 16)
	assert_eq(blank.a, 0.0, "fringe mask 0 is transparent in the middle")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tools/run_tests.sh environment_tilesets_regression`
Expected: fails — script missing.

- [ ] **Step 3: Write the builder**

```gdscript
class_name EnvironmentTileSets
extends RefCounted
## Builds the Cliff and Overlay TileSets villages paint derived elevation onto; single-row atlases, ids fixed here.

const TILE := 32
const FACE_ID := 16
const STAIR_ID := 16
const RAMP_ID := 17
const CLIFF_COUNT := 17
const OVERLAY_COUNT := 18
const EDGE_THICKNESS := 4.0

const DEFAULT_PALETTE := {
	"face_dark": Color(0.30, 0.26, 0.24),
	"face_mid": Color(0.46, 0.40, 0.36),
	"face_light": Color(0.60, 0.54, 0.48),
	"lip": Color(0.82, 0.78, 0.66),
	"lip_shadow": Color(0.22, 0.19, 0.17, 0.85),
	"grass": Color(0.38, 0.62, 0.28),
	"grass_light": Color(0.50, 0.74, 0.34),
	"stair_tread": Color(0.72, 0.68, 0.60),
	"stair_riser": Color(0.40, 0.36, 0.32),
}


static func atlas_coords(id: int) -> Vector2i:
	return Vector2i(id, 0)


static func _pal(palette: Dictionary, key: String) -> Color:
	return palette.get(key, DEFAULT_PALETTE[key])


static func _make_atlas(images: Array) -> TileSetAtlasSource:
	var sheet := Image.create(TILE * images.size(), TILE, false, Image.FORMAT_RGBA8)
	for i in range(images.size()):
		sheet.blit_rect(images[i], Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, 0))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(sheet)
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in range(images.size()):
		src.create_tile(atlas_coords(i))
	return src


static func _edge_strip(bit: int, half: float) -> PackedVector2Array:
	var t := EDGE_THICKNESS
	match bit:
		1: return PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, -half + t), Vector2(-half, -half + t)])
		2: return PackedVector2Array([Vector2(half - t, -half), Vector2(half, -half), Vector2(half, half), Vector2(half - t, half)])
		4: return PackedVector2Array([Vector2(-half, half - t), Vector2(half, half - t), Vector2(half, half), Vector2(-half, half)])
		_: return PackedVector2Array([Vector2(-half, -half), Vector2(-half + t, -half), Vector2(-half + t, half), Vector2(-half, half)])


static func build_cliff_tileset(palette: Dictionary = {}) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)
	var images: Array = []
	for mask in range(16):
		images.append(_draw_edge_tile(mask, palette))
	images.append(_draw_face_tile(palette))
	var src := _make_atlas(images)
	ts.add_source(src)
	var half := TILE / 2.0
	for mask in range(1, 16):
		var td := src.get_tile_data(atlas_coords(mask), 0)
		for bit in [1, 2, 4, 8]:
			if mask & bit:
				var idx := td.get_collision_polygons_count(0)
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, idx, _edge_strip(bit, half))
	var face := src.get_tile_data(atlas_coords(FACE_ID), 0)
	face.add_collision_polygon(0)
	face.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]))
	return ts


static func build_overlay_tileset(palette: Dictionary = {}) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)
	var images: Array = []
	for mask in range(16):
		images.append(_draw_fringe_tile(mask, palette))
	images.append(_draw_stair_tile(palette))
	images.append(_draw_ramp_tile(palette))
	ts.add_source(_make_atlas(images))
	return ts


static func _draw_edge_tile(mask: int, palette: Dictionary) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var lip := _pal(palette, "lip")
	var shadow := _pal(palette, "lip_shadow")
	if mask & 1:
		img.fill_rect(Rect2i(0, 0, TILE, 2), lip)
		img.fill_rect(Rect2i(0, 2, TILE, 1), shadow)
	if mask & 4:
		img.fill_rect(Rect2i(0, TILE - 2, TILE, 2), lip)
		img.fill_rect(Rect2i(0, TILE - 3, TILE, 1), shadow)
	if mask & 8:
		img.fill_rect(Rect2i(0, 0, 2, TILE), lip)
		img.fill_rect(Rect2i(2, 0, 1, TILE), shadow)
	if mask & 2:
		img.fill_rect(Rect2i(TILE - 2, 0, 2, TILE), lip)
		img.fill_rect(Rect2i(TILE - 3, 0, 1, TILE), shadow)
	return img


static func _draw_face_tile(palette: Dictionary) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var dark := _pal(palette, "face_dark")
	var mid := _pal(palette, "face_mid")
	var light := _pal(palette, "face_light")
	img.fill(mid)
	img.fill_rect(Rect2i(0, 0, TILE, 3), _pal(palette, "lip"))
	img.fill_rect(Rect2i(0, 3, TILE, 4), dark)
	for y in range(8, TILE, 6):
		var jitter := int(sin(y * 1.7) * 3.0)
		img.fill_rect(Rect2i(0, y, TILE, 1), dark)
		img.fill_rect(Rect2i(4 + jitter, y + 2, 10, 1), light)
		img.fill_rect(Rect2i(20 - jitter, y + 3, 8, 1), light)
	img.fill_rect(Rect2i(0, TILE - 2, TILE, 2), dark)
	return img


static func _draw_fringe_tile(mask: int, palette: Dictionary) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var g := _pal(palette, "grass")
	var gl := _pal(palette, "grass_light")
	for i in range(0, TILE, 3):
		var h := 2 + int(abs(sin(i * 2.3 + mask))) * 2
		if mask & 1:
			img.fill_rect(Rect2i(i, 0, 2, h), g if i % 2 == 0 else gl)
		if mask & 4:
			img.fill_rect(Rect2i(i, TILE - h, 2, h), g if i % 2 == 0 else gl)
		if mask & 8:
			img.fill_rect(Rect2i(0, i, h, 2), g if i % 2 == 0 else gl)
		if mask & 2:
			img.fill_rect(Rect2i(TILE - h, i, h, 2), g if i % 2 == 0 else gl)
	return img


static func _draw_stair_tile(palette: Dictionary) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var tread := _pal(palette, "stair_tread")
	var riser := _pal(palette, "stair_riser")
	for step in range(4):
		var y := step * 8
		img.fill_rect(Rect2i(2, y, TILE - 4, 5), tread)
		img.fill_rect(Rect2i(2, y + 5, TILE - 4, 3), riser)
	img.fill_rect(Rect2i(0, 0, 2, TILE), riser)
	img.fill_rect(Rect2i(TILE - 2, 0, 2, TILE), riser)
	return img


static func _draw_ramp_tile(palette: Dictionary) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var tread := _pal(palette, "stair_tread")
	var riser := _pal(palette, "stair_riser")
	img.fill(tread)
	for d in range(0, TILE * 2, 6):
		for x in range(TILE):
			var y := d - x
			if y >= 0 and y < TILE:
				img.set_pixel(x, y, riser)
	return img
```

- [ ] **Step 4: Import, run, verify pass**

Run: `godot --headless --audio-driver Dummy --import --quit >/dev/null 2>&1; tools/run_tests.sh environment_tilesets_regression`
Expected: `Passing 5 · Failing 0`.

- [ ] **Step 5: Mutation check, then commit**

Swap the `1:` and `4:` bodies in `_edge_strip` → the side check fails for N and S. Revert.

```bash
git add src/exploration/EnvironmentTileSets.gd src/exploration/EnvironmentTileSets.gd.uid test/unit/test_environment_tilesets_regression.gd
git commit -m "feat(env): EnvironmentTileSets — cliff edge/face and overlay fringe/stair tilesets"
```

---

### Task 3: BaseVillage layers, `_build_derived_layers`, `_can_step`

**Files:**
- Modify: `src/maps/villages/BaseVillage.gd` (`_setup_scene` ~line 266, `_is_cell_walkable` ~line 189, `_validate_patrol` ~line 238, new members/functions)
- Test: `test/unit/test_village_layers_regression.gd`

**Interfaces:**
- Consumes: `HeightGrid.*`, `EnvironmentTileSets.*` (Tasks 1–2).
- Produces on `BaseVillage`:
  - `var cliff_map: TileMapLayer` (name `"Cliffs"`), `var overlay_map: TileMapLayer` (name `"Overlay"`).
  - `func _build_derived_layers(map_rows: Array, height_rows: Array) -> void` — subclasses call at the end of `_generate_map`.
  - `func _is_cell_walkable(cell: Vector2i) -> bool` — now also false on face cells and prop-blocked cells.
  - `func _can_step(from: Vector2i, to: Vector2i) -> bool`.
  - `func _tile_is_open(cell: Vector2i) -> bool` — the old tile-collision-only check.
  - `func _ground_type(cell: Vector2i) -> int` — TileType of the ground tile at cell, `-1` if none.
  - `func _get_cliff_palette() -> Dictionary` (virtual, default `{}`).
  - members `_height_grid: Array`, `_stair_cells: Dictionary`, `_face_cells: Dictionary`, `_prop_blocked: Dictionary`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## A synthetic 6x6 village with two tiers and one stair proves the BaseVillage layer build
## end to end: faces paint onto the Cliffs layer and block, stairs paint onto Overlay and
## connect, _can_step carries the height rule, and a village with NO height data is unchanged.

const TILE := 32


class TierVillage extends BaseVillage:
	var height: Array[String] = [
		"WWWWWW",
		"W2222W",
		"W2222W",
		"W1111W",
		"W1111W",
		"WWWWWW",
	]
	var layout: Array[String] = [
		"WWWWWW",
		"WggggW",
		"WggggW",
		"Wg^ggW",
		"WgpggW",
		"WWWWWW",
	]
	var use_height := true
	func _get_area_id() -> String: return "tier_test_village"
	func _get_map_pixel_size() -> Vector2i: return Vector2i(6 * TILE_SIZE, 6 * TILE_SIZE)
	func _generate_map() -> void:
		for y in range(6):
			for x in range(6):
				var ch: String = layout[y][x]
				var t: int = TileGeneratorScript.TileType.WALL if ch == "W" else (TileGeneratorScript.TileType.VILLAGE_PATH if ch in ["p", "^"] else TileGeneratorScript.TileType.VILLAGE_GRASS)
				tile_map.set_cell(Vector2i(x, y), 0, TileGeneratorScript.get_atlas_coords_for_id(TileGeneratorScript.get_tile_id(t)))
		spawn_points["default"] = Vector2(1.5 * TILE, 4.5 * TILE)
		var h: Array[String] = []
		if use_height:
			for r in height:
				h.append(r.replace("W", "0"))
		_build_derived_layers(layout, h)


var _v: TierVillage


func _build(with_height: bool = true) -> TierVillage:
	var v := TierVillage.new()
	v.use_height = with_height
	add_child_autofree(v)
	return v


func test_three_layers_exist_in_order() -> void:
	_v = _build()
	assert_not_null(_v.tile_map)
	assert_not_null(_v.cliff_map)
	assert_not_null(_v.overlay_map)
	assert_eq(_v.cliff_map.name, "Cliffs")
	assert_eq(_v.overlay_map.name, "Overlay")
	assert_lt(_v.tile_map.get_index(), _v.cliff_map.get_index(), "ground under cliffs")
	assert_lt(_v.cliff_map.get_index(), _v.overlay_map.get_index(), "cliffs under overlay")


func test_faces_paint_on_row_3_except_the_stair() -> void:
	_v = _build()
	assert_true(_v._face_cells.has(Vector2i(1, 3)), "face under the ledge")
	assert_true(_v._face_cells.has(Vector2i(3, 3)))
	assert_true(_v._face_cells.has(Vector2i(4, 3)))
	assert_false(_v._face_cells.has(Vector2i(2, 3)), "the stair cell is the connector")
	assert_ne(_v.cliff_map.get_cell_source_id(Vector2i(1, 3)), -1, "face tile painted on Cliffs")
	assert_eq(_v.cliff_map.get_cell_source_id(Vector2i(2, 3)), -1, "nothing on Cliffs at the stair")
	assert_ne(_v.overlay_map.get_cell_source_id(Vector2i(2, 3)), -1, "stair painted on Overlay")


func test_is_cell_walkable_blocks_faces_and_keeps_tiles() -> void:
	_v = _build()
	assert_true(_v._tile_is_open(Vector2i(1, 3)), "the GROUND tile under a face is open grass")
	assert_false(_v._is_cell_walkable(Vector2i(1, 3)), "but the cell is not walkable — the face occupies it")
	assert_true(_v._is_cell_walkable(Vector2i(2, 3)), "stair walkable")
	assert_true(_v._is_cell_walkable(Vector2i(1, 1)), "upper tier walkable")
	assert_false(_v._is_cell_walkable(Vector2i(0, 0)), "perimeter wall")


func test_can_step_matrix() -> void:
	_v = _build()
	assert_true(_v._can_step(Vector2i(1, 1), Vector2i(2, 1)), "along the upper tier")
	assert_true(_v._can_step(Vector2i(2, 2), Vector2i(2, 3)), "down onto the stair")
	assert_true(_v._can_step(Vector2i(2, 3), Vector2i(2, 4)), "off the stair onto the lower tier")
	assert_false(_v._can_step(Vector2i(1, 2), Vector2i(1, 3)), "straight off the ledge is blocked (face)")
	assert_false(_v._can_step(Vector2i(3, 2), Vector2i(3, 3)), "so is the next column")
	assert_false(_v._can_step(Vector2i(1, 1), Vector2i(0, 1)), "into a wall")


func test_village_without_height_data_has_empty_derived_layers() -> void:
	_v = _build(false)
	assert_eq(_v._face_cells.size(), 0)
	assert_eq(_v.cliff_map.get_used_cells().size(), 0, "no cliffs without height data")
	assert_true(_v._is_cell_walkable(Vector2i(1, 3)), "flat village: every open tile walkable")
	assert_true(_v._can_step(Vector2i(1, 2), Vector2i(1, 3)), "flat village: every open step legal")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tools/run_tests.sh village_layers_regression`
Expected: parse errors — `cliff_map` / `_build_derived_layers` undefined.

- [ ] **Step 3: Implement in BaseVillage**

Add preloads + members near the existing ones:

```gdscript
const HeightGridScript = preload("res://src/exploration/HeightGrid.gd")
const EnvTileSetsScript = preload("res://src/exploration/EnvironmentTileSets.gd")

var cliff_map: TileMapLayer
var overlay_map: TileMapLayer
var _height_grid: Array = []
var _stair_cells: Dictionary = {}
var _face_cells: Dictionary = {}
var _prop_blocked: Dictionary = {}
```

In `_setup_scene`, right after `add_child(tile_map)`:

```gdscript
	cliff_map = TileMapLayer.new()
	cliff_map.name = "Cliffs"
	cliff_map.tile_set = EnvTileSetsScript.build_cliff_tileset(_get_cliff_palette())
	add_child(cliff_map)

	overlay_map = TileMapLayer.new()
	overlay_map.name = "Overlay"
	overlay_map.tile_set = EnvTileSetsScript.build_overlay_tileset(_get_cliff_palette())
	add_child(overlay_map)
```

Replace `_is_cell_walkable` with the split authority + the step rule:

```gdscript
## Open = the ground tile carries no collision polygons (inherits every generator's _get_impassable_types()).
func _tile_is_open(cell: Vector2i) -> bool:
	if tile_map == null:
		return true
	var td := tile_map.get_cell_tile_data(cell)
	if td == null:
		return false
	return td.get_collision_polygons_count(0) == 0


## Game-wide walkability authority: open tile, not consumed by a derived cliff face, not under a prop footprint.
func _is_cell_walkable(cell: Vector2i) -> bool:
	return _tile_is_open(cell) and not _face_cells.has(cell) and not _prop_blocked.has(cell)


## Height rule on top of walkability: same tier, or a one-tier step via a stair/ramp (flat villages: always true).
func _can_step(from: Vector2i, to: Vector2i) -> bool:
	if not _is_cell_walkable(from) or not _is_cell_walkable(to):
		return false
	if _height_grid.is_empty():
		return true
	return HeightGridScript.can_step(_height_grid, _stair_cells, from, to)


func _get_cliff_palette() -> Dictionary:
	return {}


func _ground_type(cell: Vector2i) -> int:
	if tile_map == null or tile_map.get_cell_source_id(cell) == -1:
		return -1
	var ac := tile_map.get_cell_atlas_coords(cell)
	var order: Array = tile_generator._get_tile_order()
	var id := ac.y * tile_generator._get_atlas_dimensions().x + ac.x
	return int(order[id]) if id >= 0 and id < order.size() else -1


## Derive cliffs/stairs from the height grid and paint them; call at the end of _generate_map. Empty height rows = flat village, nothing painted.
func _build_derived_layers(map_rows: Array, height_rows: Array) -> void:
	_stair_cells = HeightGridScript.stair_cells(map_rows)
	_height_grid = HeightGridScript.parse(height_rows)
	for c in _stair_cells:
		var id: int = EnvTileSetsScript.RAMP_ID if _stair_cells[c] == "/" else EnvTileSetsScript.STAIR_ID
		overlay_map.set_cell(c, 0, EnvTileSetsScript.atlas_coords(id))
	if _height_grid.is_empty():
		return
	var walls := {}
	for y in range(_height_grid.size()):
		for x in range(_height_grid[y].size()):
			var c := Vector2i(x, y)
			if not _tile_is_open(c):
				walls[c] = true
	var pieces: Dictionary = HeightGridScript.derive(_height_grid, _stair_cells, walls)
	_face_cells = pieces["faces"]
	for c in _face_cells:
		cliff_map.set_cell(c, 0, EnvTileSetsScript.atlas_coords(EnvTileSetsScript.FACE_ID))
	for c in pieces["edges"]:
		cliff_map.set_cell(c, 0, EnvTileSetsScript.atlas_coords(int(pieces["edges"][c])))
```

In `_validate_patrol`, make the leg clip height-aware — replace the inner sample loop's check:

```gdscript
		var last_cell := Vector2i(int(floor(a.x / TILE_SIZE)), int(floor(a.y / TILE_SIZE)))
		for s in range(1, steps + 1):
			var sample := a.lerp(b, float(s) / float(steps))
			var cell := Vector2i(int(floor(sample.x / TILE_SIZE)), int(floor(sample.y / TILE_SIZE)))
			if not _is_cell_walkable(cell) or (cell != last_cell and not _can_step(last_cell, cell)):
				pts[j] = last_clear
				changed = true
				break
			last_clear = sample
			last_cell = cell
```

- [ ] **Step 4: Run, verify pass**

Run: `tools/run_tests.sh village_layers_regression`
Expected: `Passing 5 · Failing 0`.

- [ ] **Step 5: Canary sweep + commit**

Run: `for t in village_constructs_at_runtime village_reachability_framework staged_scene_live_geometry_smoke village_placement_walkability; do tools/run_tests.sh $t > tmp/$t.log 2>&1; echo "$t $?"; done`
Expected: all `0` (no village passes height data yet, so nothing changes).

```bash
git add src/maps/villages/BaseVillage.gd test/unit/test_village_layers_regression.gd
git commit -m "feat(env): BaseVillage paints derived Cliffs/Overlay layers; _can_step carries the height rule"
```

---

### Task 4: Slope speed through the real seam

**Files:**
- Modify: `src/maps/villages/BaseVillage.gd` (add `STAIR_SPEED`, `get_terrain_speed_at`)
- Modify: `src/exploration/OverworldPlayer.gd:314-318` (`_get_terrain_speed_modifier`)
- Test: `test/unit/test_slope_speed_regression.gd`

**Interfaces:**
- Produces: `BaseVillage.STAIR_SPEED: float = 0.6`; `BaseVillage.get_terrain_speed_at(pos: Vector2) -> float`.
- `OverworldPlayer._get_terrain_speed_modifier()` returns the parent's value when the parent has `get_terrain_speed_at`; otherwise the existing atlas logic runs unchanged (a sibling lane is editing that logic — touch only the top of the function).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## Stairs slow you through the player's REAL terrain-speed path (spec: 0.6, same scale as
## mud/snow), and a parent that is not a village keeps the legacy atlas lookup untouched.

const TILE := 32
const PlayerScript := preload("res://src/exploration/OverworldPlayer.gd")


class StairVillage extends BaseVillage:
	func _get_area_id() -> String: return "stair_speed_village"
	func _get_map_pixel_size() -> Vector2i: return Vector2i(5 * TILE_SIZE, 5 * TILE_SIZE)
	func _generate_map() -> void:
		var layout := ["WWWWW", "WgggW", "Wg^gW", "WgggW", "WWWWW"]
		for y in range(5):
			for x in range(5):
				var t: int = TileGeneratorScript.TileType.WALL if layout[y][x] == "W" else TileGeneratorScript.TileType.VILLAGE_GRASS
				tile_map.set_cell(Vector2i(x, y), 0, TileGeneratorScript.get_atlas_coords_for_id(TileGeneratorScript.get_tile_id(t)))
		spawn_points["default"] = Vector2(1.5 * TILE, 1.5 * TILE)
		_build_derived_layers(layout, ["00000", "02220", "01110", "01110", "00000"])


func test_village_reports_stair_speed_only_on_stair_cells() -> void:
	var v := StairVillage.new()
	add_child_autofree(v)
	assert_almost_eq(v.get_terrain_speed_at(Vector2(2.5 * TILE, 2.5 * TILE)), 0.6, 0.001, "stair cell")
	assert_almost_eq(v.get_terrain_speed_at(Vector2(1.5 * TILE, 1.5 * TILE)), 1.0, 0.001, "plain grass")
	assert_almost_eq(BaseVillage.STAIR_SPEED, 0.6, 0.001, "spec value")


func test_player_inside_a_village_uses_the_village_seam() -> void:
	var v := StairVillage.new()
	add_child_autofree(v)
	v.player.position = Vector2(2.5 * TILE, 2.5 * TILE)
	assert_almost_eq(v.player._get_terrain_speed_modifier(), 0.6, 0.001, "player on the stair is slowed")
	v.player.position = Vector2(3.5 * TILE, 3.5 * TILE)
	assert_almost_eq(v.player._get_terrain_speed_modifier(), 1.0, 0.001, "player off the stair is not")


func test_player_under_a_plain_node_keeps_legacy_path() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var p := PlayerScript.new()
	host.add_child(p)
	assert_almost_eq(p._get_terrain_speed_modifier(), 1.0, 0.001, "no TileMap, no village: legacy default")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tools/run_tests.sh slope_speed_regression`
Expected: `get_terrain_speed_at` missing → red.

- [ ] **Step 3: Implement**

BaseVillage (near `TILE_SIZE`):

```gdscript
## Stairs/ramps slow the walk (spec 2026-08-21: 0.6, the mud/snow scale) — read by OverworldPlayer through its terrain-speed seam.
const STAIR_SPEED: float = 0.6
```

and a public function:

```gdscript
func get_terrain_speed_at(pos: Vector2) -> float:
	var cell := Vector2i(int(floor(pos.x / TILE_SIZE)), int(floor(pos.y / TILE_SIZE)))
	return STAIR_SPEED if _stair_cells.has(cell) else 1.0
```

OverworldPlayer `_get_terrain_speed_modifier`, FIRST lines of the body (keep everything below untouched):

```gdscript
func _get_terrain_speed_modifier() -> float:
	"""Check tile under player and apply speed penalty for rough terrain."""
	var parent = get_parent()
	# Villages own their slope speed (stairs/ramps); overworld keeps the atlas lookup below
	if parent and parent.has_method("get_terrain_speed_at"):
		return parent.get_terrain_speed_at(global_position)
	if not parent or not parent.has_node("TileMap"):
		return 1.0
```

- [ ] **Step 4: Run, verify pass**

Run: `tools/run_tests.sh slope_speed_regression`
Expected: `Passing 3 · Failing 0`.

- [ ] **Step 5: Mutation + commit**

Delete the two new lines in OverworldPlayer → `test_player_inside_a_village_uses_the_village_seam` must fail (village tiles are not ids 1/2/3, so legacy returns 1.0). Restore.

```bash
git add src/maps/villages/BaseVillage.gd src/exploration/OverworldPlayer.gd test/unit/test_slope_speed_regression.gd
git commit -m "feat(env): stairs slow the walk (0.6) through the terrain-speed seam"
```

Ping cowir-overworld (intercom) that the hook is a 3-line early return at the top of `_get_terrain_speed_modifier` and their atlas-stride fix below it merges independently.

---

### Task 5: Per-cell tile variants

**Files:**
- Modify: `src/exploration/TileGenerator.gd` (after `get_tile_id`, ~line 3005)
- Modify: `src/maps/villages/BaseVillage.gd` (add `_atlas_for`)
- Test: `test/unit/test_tile_variants_regression.gd`

**Interfaces:**
- Produces: `TileGenerator.VARIANT_IDS: Dictionary` (TileType → Array of atlas ids, base first); `static func get_tile_id_variant(type: TileType, salt: int) -> int`; `BaseVillage._atlas_for(tile_type: int, cell: Vector2i) -> Vector2i` (uses `_cell_salt(cell)`).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## The atlas has carried 16 variant tiles since day one and get_tile_id collapsed every type to
## ONE of them. Variants are now chosen per cell: deterministic (same cell → same tile across
## rebuilds), spread (a field uses more than one), and always the right TYPE.

const TG := preload("res://src/exploration/TileGenerator.gd")


func test_variant_ids_are_all_the_requested_type() -> void:
	var gen := TG.new()
	autofree(gen)
	var order: Array = gen._get_tile_order()
	for type in TG.VARIANT_IDS:
		for id in TG.VARIANT_IDS[type]:
			assert_eq(int(order[id]), int(type), "atlas id %d is type %d" % [id, type])
	assert_false(TG.VARIANT_IDS.has(TG.TileType.WATER), "water frames are ANIMATION, not variants")


func test_variant_is_deterministic_and_spread() -> void:
	var seen := {}
	for x in range(12):
		for y in range(12):
			var salt := x * 73856093 ^ y * 19349663
			var a := TG.get_tile_id_variant(TG.TileType.VILLAGE_GRASS, salt)
			var b := TG.get_tile_id_variant(TG.TileType.VILLAGE_GRASS, salt)
			assert_eq(a, b, "same salt, same tile")
			seen[a] = true
	assert_gt(seen.size(), 1, "a 12x12 field uses more than one grass tile")
	for id in seen:
		assert_true(id in TG.VARIANT_IDS[TG.TileType.VILLAGE_GRASS], "only grass ids")


func test_types_without_variants_fall_back_to_get_tile_id() -> void:
	assert_eq(TG.get_tile_id_variant(TG.TileType.WALL, 12345), TG.get_tile_id(TG.TileType.WALL))
	assert_eq(TG.get_tile_id_variant(TG.TileType.WATER, 7), TG.get_tile_id(TG.TileType.WATER))


func test_base_village_atlas_for_is_stable_per_cell() -> void:
	var v := BaseVillage.new()
	add_child_autofree(v)
	var c := Vector2i(4, 9)
	assert_eq(v._atlas_for(TG.TileType.VILLAGE_PATH, c), v._atlas_for(TG.TileType.VILLAGE_PATH, c))
	var ac := v._atlas_for(TG.TileType.VILLAGE_PATH, c)
	var id := ac.y * 5 + ac.x
	assert_true(id in TG.VARIANT_IDS[TG.TileType.VILLAGE_PATH], "resolves to a path tile")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tools/run_tests.sh tile_variants_regression`
Expected: `VARIANT_IDS` undefined → red.

- [ ] **Step 3: Implement**

TileGenerator, directly after `get_tile_id`:

```gdscript
## Atlas ids per type, base id first; derived from _get_tile_order (water frames excluded — they animate).
const VARIANT_IDS := {
	TileType.GRASS: [0, 12, 13],
	TileType.FOREST: [1, 14],
	TileType.MOUNTAIN: [2, 19],
	TileType.SAND: [20, 27],
	TileType.ICE: [21, 28],
	TileType.LAVA: [26, 29],
	TileType.VILLAGE_GRASS: [30, 30, 35, 39],
	TileType.VILLAGE_PATH: [31, 36],
	TileType.VILLAGE_DIRT: [32, 37],
	TileType.VILLAGE_FLOWER: [33, 38],
}


## Per-cell variant pick; callers pass a cell-derived salt so the choice is stable across rebuilds.
static func get_tile_id_variant(type: TileType, salt: int) -> int:
	var ids: Array = VARIANT_IDS.get(type, [])
	if ids.is_empty():
		return get_tile_id(type)
	return int(ids[absi(salt) % ids.size()])
```

BaseVillage:

```gdscript
func _cell_salt(cell: Vector2i) -> int:
	return cell.x * 73856093 ^ cell.y * 19349663


## Atlas coords for a tile type at a cell, variant chosen per cell (5-column TileGenerator atlas).
func _atlas_for(tile_type: int, cell: Vector2i) -> Vector2i:
	return TileGeneratorScript.get_atlas_coords_for_id(TileGeneratorScript.get_tile_id_variant(tile_type, _cell_salt(cell)))
```

- [ ] **Step 4: Run, verify pass**

Run: `tools/run_tests.sh tile_variants_regression`
Expected: `Passing 4 · Failing 0`. Also `tools/run_tests.sh tile_palette_key_integrity` stays green.

- [ ] **Step 5: Commit**

```bash
git add src/exploration/TileGenerator.gd src/maps/villages/BaseVillage.gd test/unit/test_tile_variants_regression.gd
git commit -m "feat(env): per-cell tile variants — resurrect the 16 dead atlas variants"
```

---

### Task 6: Grass-fringe transitions on the Overlay layer

**Files:**
- Modify: `src/maps/villages/BaseVillage.gd` (`_build_derived_layers` gains fringe painting; new `_fringe_mask`)
- Test: add cases to `test/unit/test_village_layers_regression.gd`

**Interfaces:**
- Produces: `BaseVillage._fringe_mask(cell: Vector2i) -> int` — bits (N=1 E=2 S=4 W=8) where the neighbour's ground type is `VILLAGE_GRASS` or `GRASS`; painted for every open, non-grass, non-stair, non-face cell with a non-zero mask.

- [ ] **Step 1: Add the failing tests** (append to `test_village_layers_regression.gd`)

```gdscript
func test_fringe_mask_points_at_grass_neighbours() -> void:
	_v = _build()
	# (2,4) is the path cell under the stair: grass E and W, stair (PATH ground) N, wall S.
	var m: int = _v._fringe_mask(Vector2i(2, 4))
	assert_eq(m, 2 | 8, "grass east + west only")
	assert_eq(_v._fringe_mask(Vector2i(1, 1)), 2 | 4, "(1,1): wall N and W, grass E and S")


func test_fringe_tiles_paint_only_on_open_non_grass_cells() -> void:
	_v = _build()
	assert_ne(_v.overlay_map.get_cell_source_id(Vector2i(2, 4)), -1, "path beside grass gets a fringe tile")
	assert_eq(_v.overlay_map.get_cell_atlas_coords(Vector2i(2, 4)), Vector2i(2 | 8, 0), "fringe id IS the mask")
	assert_eq(_v.overlay_map.get_cell_source_id(Vector2i(1, 1)), -1, "grass never fringes itself")
	assert_eq(_v.overlay_map.get_cell_source_id(Vector2i(0, 0)), -1, "walls never fringe")
	assert_eq(_v.overlay_map.get_cell_source_id(Vector2i(3, 3)), -1, "a face cell is never fringed")
	assert_eq(_v.overlay_map.get_cell_atlas_coords(Vector2i(2, 3)).x, 16, "the stair keeps its stair tile")
```

- [ ] **Step 2: Run to verify they fail**

Run: `tools/run_tests.sh village_layers_regression`
Expected: `_fringe_mask` undefined.

- [ ] **Step 3: Implement**

BaseVillage — add and call from the end of `_build_derived_layers` (AFTER `_face_cells` is set; also run the fringe pass when `_height_grid` is empty, so move the early `return` into an `if`):

```gdscript
const FRINGE_GRASS_TYPES := [TileGeneratorScript.TileType.VILLAGE_GRASS, TileGeneratorScript.TileType.GRASS]


func _fringe_mask(cell: Vector2i) -> int:
	var mask := 0
	for bit in HeightGridScript.DIRS:
		if _ground_type(cell + HeightGridScript.DIRS[bit]) in FRINGE_GRASS_TYPES:
			mask |= bit
	return mask


## Grass tufts creep onto neighbouring path/dirt — the cheap half of terrain transitions.
func _paint_fringe() -> void:
	for c in tile_map.get_used_cells():
		if not _tile_is_open(c) or _face_cells.has(c) or _stair_cells.has(c):
			continue
		if _ground_type(c) in FRINGE_GRASS_TYPES:
			continue
		var m := _fringe_mask(c)
		if m != 0:
			overlay_map.set_cell(c, 0, EnvTileSetsScript.atlas_coords(m))
```

Restructure `_build_derived_layers` so the tail reads:

```gdscript
	if not _height_grid.is_empty():
		... (walls / derive / paint faces + edges, unchanged)
	_paint_fringe()
```

- [ ] **Step 4: Run, verify pass**

Run: `tools/run_tests.sh village_layers_regression`
Expected: `Passing 7 · Failing 0`.

- [ ] **Step 5: Commit**

```bash
git add src/maps/villages/BaseVillage.gd test/unit/test_village_layers_regression.gd
git commit -m "feat(env): grass-fringe transition tiles on the Overlay layer"
```

---

### Task 7: VillageProp + Y-sorted containers

**Files:**
- Create: `src/exploration/VillageProp.gd`
- Modify: `src/maps/villages/BaseVillage.gd` (`_setup_scene`: `y_sort_enabled`, `props` container; new `_add_prop`)
- Test: `test/unit/test_village_prop_regression.gd`

**Interfaces:**
- Produces:
  - `VillageProp.Kind { TREE, LAMP_POST, BARREL, CRATE, STALL, FENCE, WELL, BANNER, CART, PLANTER }`
  - `static func VillageProp.create(kind: int, base_cell: Vector2i) -> VillageProp` — origin at bottom-centre of `base_cell`.
  - `VillageProp.FOOTPRINTS: Dictionary` (kind → Array of `Vector2i` offsets from the base cell; BANNER empty).
  - `func footprint_cells(base_cell: Vector2i) -> Array`.
  - `var light_anchor: Vector2` — local point a lamp should sit at (lamp posts: the head).
  - `BaseVillage.props: Node2D` (name `"Props"`, `y_sort_enabled`), `BaseVillage.y_sort_enabled = true`, `npcs.y_sort_enabled = true`.
  - `BaseVillage._add_prop(kind: int, base_cell: Vector2i) -> VillageProp` — adds to `props`, registers footprint in `_prop_blocked`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## Props are the first thing in a village the player can walk BEHIND. Pins: the containers
## are Y-sorted, a prop's origin is the bottom-centre of its base cell, its footprint blocks
## walkability AND physics, and zero-footprint props (banners) block nothing.

const TILE := 32
const VP := preload("res://src/exploration/VillageProp.gd")


class PropVillage extends BaseVillage:
	func _get_area_id() -> String: return "prop_test_village"
	func _get_map_pixel_size() -> Vector2i: return Vector2i(6 * TILE_SIZE, 6 * TILE_SIZE)
	func _generate_map() -> void:
		for y in range(6):
			for x in range(6):
				var wall := x == 0 or y == 0 or x == 5 or y == 5
				var t: int = TileGeneratorScript.TileType.WALL if wall else TileGeneratorScript.TileType.VILLAGE_GRASS
				tile_map.set_cell(Vector2i(x, y), 0, TileGeneratorScript.get_atlas_coords_for_id(TileGeneratorScript.get_tile_id(t)))
		spawn_points["default"] = Vector2(1.5 * TILE, 1.5 * TILE)
	func _setup_buildings() -> void:
		_add_prop(VP.Kind.TREE, Vector2i(2, 2))
		_add_prop(VP.Kind.STALL, Vector2i(3, 4))
		_add_prop(VP.Kind.BANNER, Vector2i(1, 3))


func test_containers_are_y_sorted() -> void:
	var v := PropVillage.new()
	add_child_autofree(v)
	assert_true(v.y_sort_enabled, "village root sorts children by y")
	assert_true(v.props.y_sort_enabled, "props sort among themselves")
	assert_true(v.npcs.y_sort_enabled, "NPCs sort with the player")
	assert_eq(v.props.name, "Props")


func test_prop_origin_is_bottom_centre_of_base_cell() -> void:
	var p := VP.create(VP.Kind.TREE, Vector2i(2, 2))
	assert_eq(p.position, Vector2(2.5 * TILE, 3 * TILE))
	assert_eq(p.footprint_cells(Vector2i(2, 2)), [Vector2i(2, 2)])
	assert_eq(VP.create(VP.Kind.STALL, Vector2i(3, 4)).footprint_cells(Vector2i(3, 4)), [Vector2i(3, 4), Vector2i(4, 4)])
	assert_eq(VP.create(VP.Kind.BANNER, Vector2i(1, 3)).footprint_cells(Vector2i(1, 3)), [])


func test_footprint_blocks_walkability_and_physics() -> void:
	var v := PropVillage.new()
	add_child_autofree(v)
	assert_false(v._is_cell_walkable(Vector2i(2, 2)), "tree trunk cell blocked")
	assert_true(v._is_cell_walkable(Vector2i(2, 1)), "the cell BEHIND the tree stays walkable (canopy only)")
	assert_false(v._is_cell_walkable(Vector2i(4, 4)), "stall second cell blocked")
	assert_true(v._is_cell_walkable(Vector2i(1, 3)), "banner blocks nothing")
	var bodies := 0
	for p in v.props.get_children():
		for c in p.get_children():
			if c is StaticBody2D:
				bodies += 1
				assert_eq((c as StaticBody2D).collision_layer, 1, "props are walls to the player")
	assert_eq(bodies, 2, "tree + stall carry bodies, banner does not")


func test_sprite_extends_upward_from_the_origin() -> void:
	var p := VP.create(VP.Kind.LAMP_POST, Vector2i(1, 1))
	add_child_autofree(p)
	var spr: Sprite2D = p.get_node("Sprite")
	assert_not_null(spr)
	assert_lt(spr.position.y, 0.0, "drawn above the base")
	assert_lt(p.light_anchor.y, -TILE, "lamp head sits at least a tile up")
```

- [ ] **Step 2: Run to verify it fails**

Run: `tools/run_tests.sh village_prop_regression`
Expected: VillageProp missing.

- [ ] **Step 3: Write VillageProp**

```gdscript
class_name VillageProp
extends Node2D
## Y-sorted procedural prop: origin at the bottom-centre of its base cell, art drawn upward, footprint cells become a StaticBody2D on the wall layer.

enum Kind { TREE, LAMP_POST, BARREL, CRATE, STALL, FENCE, WELL, BANNER, CART, PLANTER }

const TILE := 32

## Footprint offsets from the base cell; (w, h) = drawn size in tiles
const FOOTPRINTS := {
	Kind.TREE: [Vector2i(0, 0)], Kind.LAMP_POST: [Vector2i(0, 0)], Kind.BARREL: [Vector2i(0, 0)],
	Kind.CRATE: [Vector2i(0, 0)], Kind.STALL: [Vector2i(0, 0), Vector2i(1, 0)], Kind.FENCE: [Vector2i(0, 0)],
	Kind.WELL: [Vector2i(0, 0), Vector2i(1, 0)], Kind.BANNER: [], Kind.CART: [Vector2i(0, 0), Vector2i(1, 0)],
	Kind.PLANTER: [Vector2i(0, 0)],
}
const SIZES := {
	Kind.TREE: Vector2i(1, 3), Kind.LAMP_POST: Vector2i(1, 2), Kind.BARREL: Vector2i(1, 1), Kind.CRATE: Vector2i(1, 1),
	Kind.STALL: Vector2i(2, 2), Kind.FENCE: Vector2i(1, 1), Kind.WELL: Vector2i(2, 2), Kind.BANNER: Vector2i(1, 2),
	Kind.CART: Vector2i(2, 2), Kind.PLANTER: Vector2i(1, 1),
}

const WOOD := Color(0.45, 0.30, 0.16)
const WOOD_LIGHT := Color(0.62, 0.44, 0.24)
const IRON := Color(0.22, 0.22, 0.26)
const LEAF := Color(0.22, 0.50, 0.20)
const LEAF_LIGHT := Color(0.36, 0.66, 0.28)
const STONE := Color(0.58, 0.56, 0.52)
const STONE_DARK := Color(0.38, 0.36, 0.34)
const CLOTH_A := Color(0.80, 0.22, 0.20)
const CLOTH_B := Color(0.92, 0.88, 0.80)
const GLASS := Color(1.0, 0.85, 0.50)

var kind: int = Kind.BARREL
var light_anchor: Vector2 = Vector2.ZERO


static func create(k: int, base_cell: Vector2i) -> VillageProp:
	var p := VillageProp.new()
	p.kind = k
	p.name = "Prop_%s_%d_%d" % [Kind.keys()[k], base_cell.x, base_cell.y]
	p.position = Vector2((base_cell.x + 0.5) * TILE, (base_cell.y + 1) * TILE)
	return p


func footprint_cells(base_cell: Vector2i) -> Array:
	var out: Array = []
	for off in FOOTPRINTS[kind]:
		out.append(base_cell + off)
	return out


func _ready() -> void:
	var size: Vector2i = SIZES[kind]
	var img := Image.create(size.x * TILE, size.y * TILE, false, Image.FORMAT_RGBA8)
	_paint(img, size)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.centered = false
	spr.texture = ImageTexture.create_from_image(img)
	spr.position = Vector2(-size.x * TILE / 2.0, -size.y * TILE)
	add_child(spr)
	if not FOOTPRINTS[kind].is_empty():
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for off in FOOTPRINTS[kind]:
			var cs := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(TILE, TILE)
			cs.shape = rect
			cs.position = Vector2(off.x * TILE, -TILE / 2.0)
			body.add_child(cs)
		add_child(body)


func _paint(img: Image, size: Vector2i) -> void:
	var w := size.x * TILE
	var h := size.y * TILE
	match kind:
		Kind.TREE:
			img.fill_rect(Rect2i(w / 2 - 3, h - 22, 6, 22), WOOD)
			_disc(img, Vector2i(w / 2, h - 44), 15, LEAF)
			_disc(img, Vector2i(w / 2 - 6, h - 56), 11, LEAF)
			_disc(img, Vector2i(w / 2 + 7, h - 58), 12, LEAF)
			_disc(img, Vector2i(w / 2 + 2, h - 68), 10, LEAF_LIGHT)
		Kind.LAMP_POST:
			img.fill_rect(Rect2i(w / 2 - 4, h - 4, 8, 4), IRON)
			img.fill_rect(Rect2i(w / 2 - 1, h - 44, 3, 40), IRON)
			img.fill_rect(Rect2i(w / 2 - 6, h - 56, 12, 12), IRON)
			img.fill_rect(Rect2i(w / 2 - 4, h - 54, 8, 8), GLASS)
			light_anchor = Vector2(0, -50.0)
		Kind.BARREL:
			img.fill_rect(Rect2i(6, 4, 20, 26), WOOD)
			img.fill_rect(Rect2i(6, 8, 20, 2), IRON)
			img.fill_rect(Rect2i(6, 22, 20, 2), IRON)
			img.fill_rect(Rect2i(10, 6, 3, 22), WOOD_LIGHT)
		Kind.CRATE:
			img.fill_rect(Rect2i(4, 6, 24, 24), WOOD)
			img.fill_rect(Rect2i(4, 6, 24, 2), WOOD_LIGHT)
			img.fill_rect(Rect2i(4, 6, 2, 24), WOOD_LIGHT)
			for i in range(24):
				img.set_pixel(4 + i, 6 + i, IRON)
		Kind.STALL:
			img.fill_rect(Rect2i(4, h - 22, w - 8, 22), WOOD)
			img.fill_rect(Rect2i(4, h - 22, w - 8, 3), WOOD_LIGHT)
			img.fill_rect(Rect2i(6, h - 44, 3, 22), WOOD)
			img.fill_rect(Rect2i(w - 9, h - 44, 3, 22), WOOD)
			for i in range(0, w, 8):
				img.fill_rect(Rect2i(i, h - 52, 8, 10), CLOTH_A if (i / 8) % 2 == 0 else CLOTH_B)
		Kind.FENCE:
			img.fill_rect(Rect2i(2, 10, 4, 22), WOOD)
			img.fill_rect(Rect2i(26, 10, 4, 22), WOOD)
			img.fill_rect(Rect2i(0, 14, 32, 3), WOOD_LIGHT)
			img.fill_rect(Rect2i(0, 24, 32, 3), WOOD_LIGHT)
		Kind.WELL:
			img.fill_rect(Rect2i(8, h - 26, w - 16, 26), STONE)
			img.fill_rect(Rect2i(8, h - 26, w - 16, 3), STONE_DARK)
			img.fill_rect(Rect2i(14, h - 20, w - 28, 14), IRON)
			img.fill_rect(Rect2i(10, h - 56, 3, 32), WOOD)
			img.fill_rect(Rect2i(w - 13, h - 56, 3, 32), WOOD)
			img.fill_rect(Rect2i(6, h - 62, w - 12, 8), WOOD_LIGHT)
		Kind.BANNER:
			img.fill_rect(Rect2i(w / 2 - 8, 2, 16, 3), WOOD)
			img.fill_rect(Rect2i(w / 2 - 6, 5, 12, 40), CLOTH_A)
			img.fill_rect(Rect2i(w / 2 - 3, 14, 6, 6), CLOTH_B)
		Kind.CART:
			img.fill_rect(Rect2i(6, h - 30, w - 12, 16), WOOD)
			img.fill_rect(Rect2i(6, h - 30, w - 12, 3), WOOD_LIGHT)
			_disc(img, Vector2i(14, h - 10), 8, IRON)
			_disc(img, Vector2i(w - 14, h - 10), 8, IRON)
			img.fill_rect(Rect2i(w - 8, h - 22, 10, 3), WOOD)
		Kind.PLANTER:
			img.fill_rect(Rect2i(4, 16, 24, 14), STONE)
			img.fill_rect(Rect2i(4, 16, 24, 2), STONE_DARK)
			_disc(img, Vector2i(10, 12), 5, LEAF)
			_disc(img, Vector2i(18, 10), 6, LEAF_LIGHT)
			_disc(img, Vector2i(24, 13), 4, CLOTH_A)


func _disc(img: Image, c: Vector2i, r: int, col: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				var px := c + Vector2i(x, y)
				if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height():
					img.set_pixel(px.x, px.y, col)
```

(Collider maths: the origin is the bottom-centre of the base cell, so cell `base + off` is centred at local `(off.x * TILE, -TILE / 2)`.)

BaseVillage `_setup_scene` — set Y-sort and add the container after `npcs`:

```gdscript
	y_sort_enabled = true
	npcs.y_sort_enabled = true

	props = Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	add_child(props)
```

(plus `var props: Node2D` among the containers, and `const VillagePropScript = preload("res://src/exploration/VillageProp.gd")`), and:

```gdscript
## Place a Y-sorted prop by its base cell; its footprint joins the walkability grid and the physics world.
func _add_prop(kind: int, base_cell: Vector2i) -> VillageProp:
	var p: VillageProp = VillagePropScript.create(kind, base_cell)
	for c in p.footprint_cells(base_cell):
		_prop_blocked[c] = true
	props.add_child(p)
	return p
```

- [ ] **Step 4: Import, run, verify pass**

Run: `godot --headless --audio-driver Dummy --import --quit >/dev/null 2>&1; tools/run_tests.sh village_prop_regression`
Expected: `Passing 4 · Failing 0`.

- [ ] **Step 5: Canary + commit**

Run: `for t in village_constructs_at_runtime village_reachability_framework staged_scene_live_geometry_smoke harmonia_after_cave_gate_regression; do tools/run_tests.sh $t > tmp/$t.log 2>&1; echo "$t $?"; done` — expect all 0 (Y-sort on the root changes draw order only).

```bash
git add src/exploration/VillageProp.gd src/exploration/VillageProp.gd.uid src/maps/villages/BaseVillage.gd test/unit/test_village_prop_regression.gd
git commit -m "feat(env): VillageProp — Y-sorted props with footprints; villages Y-sort player/NPCs/props"
```

---

### Task 8: VillageLighting + GameLoop hand-off

**Files:**
- Create: `src/exploration/VillageLighting.gd`
- Modify: `src/maps/villages/BaseVillage.gd` (`_ready` calls `_setup_lighting()`; `has_scene_lighting()`; `_add_lamp`)
- Modify: `src/GameLoop.gd:3670-3673`
- Test: `test/unit/test_village_lighting_regression.gd`

**Interfaces:**
- Produces:
  - `VillageLighting extends CanvasModulate`; `func add_lamp(pos: Vector2, color: Color = Color(1.0, 0.85, 0.55), radius: int = 96, energy: float = 0.9) -> PointLight2D`; `func tint_now() -> Color`; `static func lamp_energy_for(tint: Color, max_energy: float) -> float`.
  - `BaseVillage.lighting: VillageLighting`; `func has_scene_lighting() -> bool` (true when `lighting != null`); `func _uses_scene_lighting() -> bool` virtual (default `true`); `func _add_lamp(pos: Vector2, color := ..., radius := 96, energy := 0.9) -> PointLight2D`.
  - GameLoop: `_day_night_overlay.set_outdoor(outdoor_scene and not scene_lit)`; `_day_clock` keeps `outdoor_scene`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## Outdoor lighting moves from a fullscreen multiply rect to a per-scene CanvasModulate so
## PointLight2D lamps can pierce the dusk. Pins: the modulate colour is the SAME curve the
## overlay used (no look change at any phase), lamps are dark at noon and lit at night, and
## GameLoop stops tinting a scene that lights itself (no double darkening).

const VL := preload("res://src/exploration/VillageLighting.gd")


func test_modulate_tracks_the_overlay_curve() -> void:
	for p in [0.0, 0.07, 0.3, 0.57, 0.75, 0.95]:
		assert_eq(VL.tint_for(p), DayNightOverlay.tint_for_phase(p), "phase %.2f matches the overlay" % p)


func test_lamp_energy_is_zero_at_noon_and_full_at_night() -> void:
	assert_almost_eq(VL.lamp_energy_for(Color(1, 1, 1), 0.9), 0.0, 0.001, "noon: lamps off")
	assert_almost_eq(VL.lamp_energy_for(Color(0.45, 0.50, 0.78), 0.9), 0.9, 0.001, "deep night: full")
	var dusk := VL.lamp_energy_for(Color(1.0, 0.78, 0.62), 0.9)
	assert_gt(dusk, 0.0)
	assert_lt(dusk, 0.9)


func test_add_lamp_builds_a_point_light_with_a_texture() -> void:
	var l := VL.new()
	add_child_autofree(l)
	var lamp := l.add_lamp(Vector2(100, 50))
	assert_true(lamp is PointLight2D)
	assert_not_null(lamp.texture, "radial texture generated")
	assert_eq(lamp.position, Vector2(100, 50))
	assert_eq(lamp.get_parent(), l, "lamps live under the lighting node")
	l.phase_override = 0.75
	assert_eq(l.tint_now(), DayNightOverlay.tint_for_phase(0.75), "override pins the phase for tooling")


func test_base_village_lights_itself_by_default() -> void:
	var v := BaseVillage.new()
	add_child_autofree(v)
	assert_true(v.has_scene_lighting())
	assert_true(v.lighting is CanvasModulate)


func test_game_loop_hands_the_tint_to_scene_lit_villages() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var i := src.find("var outdoor_scene: bool =")
	assert_gt(i, -1)
	var window := src.substr(i, 600)
	assert_true("has_scene_lighting" in window, "GameLoop asks the scene whether it lights itself")
	assert_true("_day_night_overlay.set_outdoor(outdoor_scene and not scene_lit)" in window, "overlay off for scene-lit maps")
	assert_true("_day_clock.set_outdoor(outdoor_scene)" in window, "the day clock still knows it is outdoors")
```

- [ ] **Step 2: Run to verify it fails**

Run: `tools/run_tests.sh village_lighting_regression`
Expected: VillageLighting missing.

- [ ] **Step 3: Implement**

`src/exploration/VillageLighting.gd`:

```gdscript
class_name VillageLighting
extends CanvasModulate
## Per-scene day/night modulate (same curve as DayNightOverlay) so PointLight2D lamps pierce the dusk instead of being multiplied into it.

const LAMP_FADE_START := 0.95
const LAMP_FADE_SPAN := 0.30

var _lamps: Array = []
var _light_tex: ImageTexture
## Tooling hook (screenshots): >= 0 pins the phase instead of reading GameState
var phase_override: float = -1.0


static func tint_for(phase: float) -> Color:
	return DayNightOverlay.tint_for_phase(fposmod(phase, 1.0))


## Lamps come up as the tint loses luminance: off in daylight, full by deep dusk.
static func lamp_energy_for(tint: Color, max_energy: float) -> float:
	return max_energy * clampf((LAMP_FADE_START - tint.get_luminance()) / LAMP_FADE_SPAN, 0.0, 1.0)


func _ready() -> void:
	color = Color.WHITE
	_light_tex = _make_light_texture(96)


func _process(_delta: float) -> void:
	color = tint_now()
	for l in _lamps:
		if is_instance_valid(l):
			l.energy = lamp_energy_for(color, float(l.get_meta("max_energy", 0.9)))


func tint_now() -> Color:
	if phase_override >= 0.0:
		return tint_for(phase_override)
	var gs = get_node_or_null("/root/GameState")
	if gs == null or not ("day_phase" in gs):
		return Color.WHITE
	return tint_for(float(gs.day_phase))


func add_lamp(pos: Vector2, lamp_color: Color = Color(1.0, 0.85, 0.55), radius: int = 96, energy: float = 0.9) -> PointLight2D:
	var l := PointLight2D.new()
	l.position = pos
	l.color = lamp_color
	l.texture = _light_tex if radius == 96 else _make_light_texture(radius)
	l.energy = lamp_energy_for(color, energy)
	l.set_meta("max_energy", energy)
	add_child(l)
	_lamps.append(l)
	return l


static func _make_light_texture(radius: int) -> ImageTexture:
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size / 2
	for y in range(size):
		for x in range(size):
			var dist := Vector2(x - center, y - center).length()
			var alpha := clampf(1.0 - dist / float(center), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))
	return ImageTexture.create_from_image(img)
```

BaseVillage — add `const VillageLightingScript = preload("res://src/exploration/VillageLighting.gd")`, `var lighting: VillageLighting`, call `_setup_lighting()` in `_ready` right after `_setup_save_point()`, and:

```gdscript
func _uses_scene_lighting() -> bool:
	return true


func has_scene_lighting() -> bool:
	return lighting != null


func _setup_lighting() -> void:
	if not _uses_scene_lighting():
		return
	lighting = VillageLightingScript.new()
	lighting.name = "Lighting"
	add_child(lighting)


func _add_lamp(pos: Vector2, lamp_color: Color = Color(1.0, 0.85, 0.55), radius: int = 96, energy: float = 0.9) -> PointLight2D:
	return lighting.add_lamp(pos, lamp_color, radius, energy) if lighting else null
```

GameLoop 3670-3675 becomes:

```gdscript
	# Day/night tint follows the map class: outdoors only (interiors have PR-153's modulate, caves are lightless)
	var outdoor_scene: bool = exploration_scene is OverworldScene or exploration_scene is BaseVillage
	# A scene that lights itself (VillageLighting CanvasModulate) must not ALSO be multiplied by the overlay
	var scene_lit: bool = exploration_scene.has_method("has_scene_lighting") and bool(exploration_scene.has_scene_lighting())
	if _day_night_overlay:
		_day_night_overlay.set_outdoor(outdoor_scene and not scene_lit)
	if _day_clock:
		_day_clock.set_outdoor(outdoor_scene)
```

- [ ] **Step 4: Import, run, verify pass**

Run: `godot --headless --audio-driver Dummy --import --quit >/dev/null 2>&1; tools/run_tests.sh village_lighting_regression`
Expected: `Passing 5 · Failing 0`. Also `tools/run_tests.sh day_night_clock_regression` and `tools/run_tests.sh battle_background_day_night_wiring_regression` → green.

- [ ] **Step 5: Commit**

```bash
git add src/exploration/VillageLighting.gd src/exploration/VillageLighting.gd.uid src/maps/villages/BaseVillage.gd src/GameLoop.gd test/unit/test_village_lighting_regression.gd
git commit -m "feat(env): per-scene VillageLighting (CanvasModulate + lamps); GameLoop hands off the overlay tint"
```

---

### Task 9: Teach the source-level geometry audits the height grid

**Files:**
- Create: `test/unit/helpers/village_grid_source.gd`
- Modify: `test/unit/test_village_npc_connectivity.gd` (`_rows`, `_walkable`, `_components`)
- Modify: `test/unit/test_village_placement_walkability.gd` (face cells count as blocked)
- Modify: `test/unit/test_village_map_data_ragged_row_lint.gd` (lint `height_data` too)
- Modify: `test/unit/test_staged_scene_live_geometry_smoke.gd` (walk segments use `_can_step`)
- Create: `test/unit/test_village_height_grid_integrity.gd`

**Interfaces:**
- Produces (helper, all `static`): `rows(src: String) -> Array` (map_data), `height_rows(src: String) -> Array`, `blocked_chars(src: String, impassable_types: Array) -> Dictionary`, `face_cells(src: String, impassable_types: Array) -> Dictionary` (derived via `HeightGrid.derive` with walls = blocked chars), `stairs(src: String) -> Dictionary`, `grid(src) -> Array`.

- [ ] **Step 1: Write the helper**

```gdscript
extends RefCounted
## Shared SOURCE parser for village grids so every source-level geometry audit reads map_data, height_data and the legend the same way.

const HG := preload("res://src/exploration/HeightGrid.gd")
const MAP_ANCHOR := "var map_data: Array[String] = ["
const HEIGHT_ANCHOR := "var height_data: Array[String] = ["


static func _rows_after(src: String, anchor: String) -> Array:
	var start := src.find(anchor)
	if start < 0:
		return []
	var open := start + anchor.length()
	var block := src.substr(open, src.find("]", open) - open)
	var out: Array = []
	for m in RegEx.create_from_string("\"([^\"]+)\"").search_all(block):
		out.append(m.get_string(1))
	return out


static func rows(src: String) -> Array:
	return _rows_after(src, MAP_ANCHOR)


static func height_rows(src: String) -> Array:
	return _rows_after(src, HEIGHT_ANCHOR)


static func grid(src: String) -> Array:
	return HG.parse(height_rows(src))


static func stairs(src: String) -> Dictionary:
	return HG.stair_cells(rows(src))


static func blocked_chars(src: String, impassable_types: Array) -> Dictionary:
	var b := {}
	var ch := RegEx.create_from_string("\"(.)\"")
	for line in src.split("\n"):
		if not (line.contains("return") and line.contains("TileType.")):
			continue
		var blocking := false
		for t in impassable_types:
			if line.contains("TileType." + t):
				blocking = true
				break
		if not blocking:
			continue
		for m in ch.search_all(line):
			b[m.get_string(1)] = true
	return b


## Derived face cells for a source file (empty for flat villages).
static func face_cells(src: String, impassable_types: Array) -> Dictionary:
	var g := grid(src)
	if g.is_empty():
		return {}
	var r := rows(src)
	var blocked := blocked_chars(src, impassable_types)
	var walls := {}
	for y in range(r.size()):
		for x in range(str(r[y]).length()):
			if blocked.has(str(r[y])[x]):
				walls[Vector2i(x, y)] = true
	return HG.derive(g, stairs(src), walls)["faces"]
```

- [ ] **Step 2: Write the integrity test (fails until Harmonia exists? No — passes vacuously on zero grids, so it carries a CONTROL)**

```gdscript
extends GutTest

## Every village that declares height_data must be internally consistent: same dims as map_data,
## no two-tier jump between open cells, no face landing on a stair or an authored mark.
## CONTROL: the Harmonia grid must be present once Task 10 lands — the count assert below keeps
## this audit from passing on an empty corpus.

const GS := preload("res://test/unit/helpers/village_grid_source.gd")
const HG := preload("res://src/exploration/HeightGrid.gd")
const IMPASSABLE := ["WALL", "WATER", "VILLAGE_HEDGE", "CAVE_WALL", "LAVA", "MOUNTAIN"]
const LIT := "Vector2\\(\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^,]*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^)]*\\)"
const MARK_LINES := ["_create_npc(", "_place_chicken(", "spawn_points[", ".position = Vector2(", "_add_interior_door("]


func _sources() -> Dictionary:
	var out := {}
	var dir := DirAccess.open("res://src/maps/villages")
	for f in dir.get_files():
		if f.ends_with(".gd") and f != "BaseVillage.gd":
			var src := FileAccess.get_file_as_string("res://src/maps/villages/" + f)
			if not GS.height_rows(src).is_empty():
				out[f] = src
	return out


func test_at_least_one_village_declares_height_data() -> void:
	assert_gt(_sources().size(), 0, "CONTROL: Harmonia must carry height_data (Task 10)")


func test_height_rows_match_map_dims() -> void:
	var srcs := _sources()
	for f in srcs:
		var src: String = srcs[f]
		var m := GS.rows(src)
		var h := GS.height_rows(src)
		assert_eq(h.size(), m.size(), "%s: height rows == map rows" % f)
		for i in range(mini(h.size(), m.size())):
			assert_eq(str(h[i]).length(), str(m[i]).length(), "%s row %d width" % [f, i])
			assert_true(RegEx.create_from_string("^[0-3]+$").search(str(h[i])) != null, "%s row %d digits 0-3 only" % [f, i])


func test_no_two_tier_jump_between_open_cells() -> void:
	var srcs := _sources()
	for f in srcs:
		var src: String = srcs[f]
		var g := GS.grid(src)
		var blocked := GS.blocked_chars(src, IMPASSABLE)
		var rows := GS.rows(src)
		for y in range(g.size()):
			for x in range(g[y].size()):
				if blocked.has(str(rows[y])[x]):
					continue
				for d in [Vector2i(1, 0), Vector2i(0, 1)]:
					var n := Vector2i(x, y) + d
					var hn := HG.height_at(g, n)
					if hn < 0 or blocked.has(str(rows[n.y])[n.x]):
						continue
					assert_lt(absi(hn - HG.height_at(g, Vector2i(x, y))), 2, "%s: %s -> %s jumps two tiers with no way to bridge it" % [f, Vector2i(x, y), n])


func test_faces_never_land_on_stairs_or_marks() -> void:
	var re := RegEx.create_from_string(LIT)
	var srcs := _sources()
	for f in srcs:
		var src: String = srcs[f]
		var faces := GS.face_cells(src, IMPASSABLE)
		assert_gt(faces.size(), 0, "%s: a tiered village derives at least one face" % f)
		for s in GS.stairs(src):
			assert_false(faces.has(s), "%s: stair %s consumed by a face" % [f, s])
		for line in src.split("\n"):
			var marked := false
			for k in MARK_LINES:
				if line.contains(k):
					marked = true
			if not marked:
				continue
			for m in re.search_all(line):
				var cell := Vector2i(int(floor(float(m.get_string(1)))), int(floor(float(m.get_string(2)))))
				assert_false(faces.has(cell), "%s: mark at %s sits on a derived cliff face: %s" % [f, cell, line.strip_edges()])
```

- [ ] **Step 3: Run it — expect the CONTROL to fail (no village has height data yet)**

Run: `tools/run_tests.sh village_height_grid_integrity`
Expected: `Failing 1` (the control) — correct until Task 10.

- [ ] **Step 4: Make the three existing audits height-aware**

`test_village_npc_connectivity.gd` — add two preloads under the existing consts:

```gdscript
const GS := preload("res://test/unit/helpers/village_grid_source.gd")
const HG := preload("res://src/exploration/HeightGrid.gd")
```

Replace `_rows`, `_blocked`, `_walkable` and `_components` (lines 30-93) with a context-carrying version — same algorithm, plus faces and the step rule:

```gdscript
func _ctx(src: String) -> Dictionary:
	return {"rows": GS.rows(src), "blocked": GS.blocked_chars(src, IMPASSABLE_TYPES),
		"grid": GS.grid(src), "stairs": GS.stairs(src), "faces": GS.face_cells(src, IMPASSABLE_TYPES)}


func _walkable(ctx: Dictionary, x: int, y: int) -> bool:
	var rows: Array = ctx["rows"]
	if y < 0 or y >= rows.size():
		return false
	var row: String = rows[y]
	if x < 0 or x >= row.length():
		return false
	return not ctx["blocked"].has(row[x]) and not ctx["faces"].has(Vector2i(x, y))


## Flat village: every open neighbour connects. Tiered: only same height or via a stair.
func _step_ok(ctx: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	if (ctx["grid"] as Array).is_empty():
		return true
	return HG.can_step(ctx["grid"], ctx["stairs"], a, b)


## 4-connected components over walkable cells. Returns {cell_key: component_id}
## and {component_id: size}.
func _components(ctx: Dictionary) -> Array:
	var rows: Array = ctx["rows"]
	var owner := {}
	var sizes := {}
	var next_id := 0
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var key := Vector2i(x, y)
			if not _walkable(ctx, x, y) or owner.has(key):
				continue
			next_id += 1
			var n := 0
			var queue: Array[Vector2i] = [key]
			owner[key] = next_id
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				n += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nb: Vector2i = c + d
					if _walkable(ctx, nb.x, nb.y) and _step_ok(ctx, c, nb) and not owner.has(nb):
						owner[nb] = next_id
						queue.append(nb)
			sizes[next_id] = n
	return [owner, sizes]
```

and in `test_every_village_npc_stands_in_the_reachable_region` replace the three lines

```gdscript
		var rows := _rows(src)
		if rows.is_empty():
			continue
		var blocked := _blocked(src)
```
with
```gdscript
		var ctx := _ctx(src)
		var rows: Array = ctx["rows"]
		if rows.is_empty():
			continue
		var blocked: Dictionary = ctx["blocked"]
```
and `var parts := _components(rows, blocked)` with `var parts := _components(ctx)`. Nothing else in the function changes.

`test_village_placement_walkability.gd` — add `const GS := preload("res://test/unit/helpers/village_grid_source.gd")` and a member `var _faces: Dictionary = {}`; in `test_every_village_placement_is_walkable` set `_faces = GS.face_cells(src, IMPASSABLE_TYPES)` on the line before `_audit_file(f, src, rows, blocked)`; extend `_check_cell`:

```gdscript
func _check_cell(fname: String, where: String, rows: Array, blocked: Dictionary, cx: int, cy: int) -> void:
	var ch := _char_at(rows, cx, cy)
	assert_false(blocked.has(ch),
		"%s %s places on impassable '%s' at cell (%d,%d)" % [fname, where, ch, cx, cy])
	assert_false(_faces.has(Vector2i(cx, cy)),
		"%s %s places on a DERIVED cliff face at cell (%d,%d) — move the mark or the tier line" % [fname, where, cx, cy])
```

`test_village_map_data_ragged_row_lint.gd`: add to `_lint_dir`, after the map_data checks:

```gdscript
		var hrows := GS.height_rows(src)
		if not hrows.is_empty():
			if mw > 0:
				for i in range(hrows.size()):
					if str(hrows[i]).length() != mw:
						offenders_w.append("%s height row %d: len=%d != MAP_WIDTH=%d" % [f, i, str(hrows[i]).length(), mw])
			if hrows.size() != rows.size():
				offenders_h.append("%s: %d height rows vs %d map rows" % [f, hrows.size(), rows.size()])
```

`test_staged_scene_live_geometry_smoke.gd` — `_first_blocked_on_segment` (line ~164) gains the step rule between successive distinct cells:

```gdscript
func _step_ok(a: Vector2i, b: Vector2i) -> bool:
	if _village == null or not _village.has_method("_can_step"):
		return true
	return a == b or _village._can_step(a, b)


func _first_blocked_on_segment(from: Vector2, to: Vector2) -> Vector2:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return Vector2.INF
	# Half-tile stepping — fine enough that a 1-tile pillar can't slip between samples.
	var steps := int(ceil(dist / (TILE_SIZE * 0.5)))
	var last := Vector2i(int(floor(from.x / TILE_SIZE)), int(floor(from.y / TILE_SIZE)))
	for i in range(steps + 1):
		var p := from.lerp(to, float(i) / float(steps))
		var cell := Vector2i(int(floor(p.x / TILE_SIZE)), int(floor(p.y / TILE_SIZE)))
		# A legal cell reached off a ledge is still a blocked walk — tiers connect only via stairs
		if not _walkable(p) or not _step_ok(last, cell):
			return p
		last = cell
	return Vector2.INF
```

- [ ] **Step 5: Run the four modified audits**

Run: `for t in village_npc_connectivity village_placement_walkability village_map_data_ragged_row_lint staged_scene_live_geometry_smoke; do tools/run_tests.sh $t > tmp/$t.log 2>&1; echo "$t $?"; done`
Expected: all `0` (no village has height data yet; behaviour identical).

- [ ] **Step 6: Commit**

```bash
git add test/unit/helpers/village_grid_source.gd test/unit/test_village_height_grid_integrity.gd test/unit/test_village_npc_connectivity.gd test/unit/test_village_placement_walkability.gd test/unit/test_village_map_data_ragged_row_lint.gd test/unit/test_staged_scene_live_geometry_smoke.gd
git commit -m "test(env): source geometry audits read height_data; height-grid integrity ratchet (control red until Harmonia)"
```

---

### Task 10: Harmonia — three tiers

**Files:**
- Modify: `src/maps/villages/HarmoniaVillage.gd` (`_generate_map` lines 46-120, `_char_to_tile_type`, `_get_atlas_coords`, NPC positions at lines 337/348/523/536)
- Test: `test/unit/test_harmonia_tiers_regression.gd`

**Interfaces:**
- Consumes: `_build_derived_layers`, `_atlas_for`, `_can_step`, `_is_cell_walkable`.
- Produces: Harmonia `height_data` (rows 0-7 = `2`, 8-18 = `1`, 19-29 = `0`), stairs at `(11,8) (12,8) (22,8) (23,8) (12,19) (13,19) (22,19) (23,19)`; Theron → `(11,9)`, Milo → `(19,9)`, Bram → `(27,9)`, sword → `(29,9)`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

## Harmonia is the proof map for elevation: castle approach (tier 2) / town (tier 1) /
## market + gate (tier 0). Pins the stair cells, proves both staged scenes still walk legal
## ground, and flood-fills the LIVE village so every NPC is reachable from the entrance.

const HARMONIA_TSCN := "res://src/maps/villages/HarmoniaVillage.tscn"
const TILE := 32
const STAIRS := [Vector2i(11, 8), Vector2i(12, 8), Vector2i(22, 8), Vector2i(23, 8),
	Vector2i(12, 19), Vector2i(13, 19), Vector2i(22, 19), Vector2i(23, 19)]
const SCENES := ["res://data/cutscenes/world1_chapter1.json", "res://data/cutscenes/world1_harmonia_after_cave.json"]

var _v: Node


func before_each() -> void:
	_v = (load(HARMONIA_TSCN) as PackedScene).instantiate()
	add_child_autofree(_v)
	await get_tree().process_frame
	await get_tree().process_frame


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


func test_three_tiers_and_eight_stairs() -> void:
	var HG := preload("res://src/exploration/HeightGrid.gd")
	assert_eq(HG.height_at(_v._height_grid, Vector2i(18, 4)), 2, "castle approach")
	assert_eq(HG.height_at(_v._height_grid, Vector2i(18, 13)), 1, "town")
	assert_eq(HG.height_at(_v._height_grid, Vector2i(18, 22)), 0, "market")
	assert_eq(_v._stair_cells.size(), STAIRS.size())
	for s in STAIRS:
		assert_true(_v._stair_cells.has(s), "stair at %s" % s)
		assert_true(_v._is_cell_walkable(s), "stair %s walkable" % s)
	assert_gt(_v._face_cells.size(), 30, "two cliff lines derive faces")
	assert_false(_v._is_cell_walkable(Vector2i(6, 8)), "row 8 face blocks")
	assert_false(_v._is_cell_walkable(Vector2i(15, 19)), "row 19 face blocks")


func test_stairs_connect_and_ledges_do_not() -> void:
	assert_true(_v._can_step(Vector2i(11, 7), Vector2i(11, 8)), "down the west stair")
	assert_true(_v._can_step(Vector2i(23, 8), Vector2i(23, 9)), "off the east stair into town")
	assert_true(_v._can_step(Vector2i(12, 18), Vector2i(12, 19)), "town -> market stair")
	assert_false(_v._can_step(Vector2i(9, 7), Vector2i(9, 8)), "straight off the ledge")
	assert_false(_v._can_step(Vector2i(20, 18), Vector2i(20, 19)), "straight off the lower ledge")


func test_staged_marks_are_walkable_and_paths_never_leave_a_tier_without_a_stair() -> void:
	for path in SCENES:
		var scene = JSON.parse_string(FileAccess.get_file_as_string(path))
		var where := {}
		var idx := 0
		for step in scene.get("steps", []):
			if step is Dictionary:
				var id := str(step.get("id", ""))
				if step.get("type") == "spawn_actor" and step.get("at") is Array:
					var at: Vector2 = Vector2(float(step["at"][0]), float(step["at"][1]))
					assert_true(_v._is_cell_walkable(_cell(at)), "%s[%d] %s spawns on walkable %s" % [path.get_file(), idx, id, _cell(at)])
					where[id] = at
				elif step.get("type") == "move_actor" and step.get("to") is Array and where.has(id):
					var to: Vector2 = Vector2(float(step["to"][0]), float(step["to"][1]))
					var from: Vector2 = where[id]
					var steps := int(ceil(from.distance_to(to) / (TILE * 0.5)))
					var last := _cell(from)
					for s in range(1, steps + 1):
						var c := _cell(from.lerp(to, float(s) / float(steps)))
						if c != last:
							assert_true(_v._can_step(last, c), "%s[%d] %s walks %s -> %s illegally" % [path.get_file(), idx, id, last, c])
							last = c
					where[id] = to
			idx += 1


func test_every_npc_is_reachable_from_the_entrance() -> void:
	var start := _cell(_v.spawn_points["default"])
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and _v._can_step(c, n):
				seen[n] = true
				queue.append(n)
	assert_gt(seen.size(), 300, "the three tiers are one connected walk")
	for n in _v.npcs.get_children():
		if not ("npc_name" in n):
			continue
		var c := _cell(n.position)
		var near := false
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if seen.has(c + d):
				near = true
		assert_true(near, "'%s' at %s is reachable from the entrance" % [n.npc_name, c])
	for sp in ["exit", "entrance", "bar_exit", "chapel_exit", "library_exit", "cartographer_exit"]:
		assert_true(seen.has(_cell(_v.spawn_points[sp])), "spawn '%s' reachable" % sp)
```

- [ ] **Step 2: Run to verify it fails**

Run: `tools/run_tests.sh harmonia_tiers_regression`
Expected: red — `_height_grid` empty, no stairs.

- [ ] **Step 3: Author the tiers**

In `HarmoniaVillage._generate_map`, change exactly these rows of `map_data` (row index → new string; every row stays 36 chars):

```
row 8:  "W...gfgggdd^^FFFFFFggd^^ggfgfggg...W"
row 19: "W...gggHHHgd^^ggfggfgg^^gggfgfgg...W"
```

Add `height_data` directly after `map_data`:

```gdscript
	# Elevation: castle approach (2) / town (1) / market + gate (0); cliffs are DERIVED, stairs are the '^' cells above
	var height_data: Array[String] = [
		"222222222222222222222222222222222222",
		"222222222222222222222222222222222222",
		"222222222222222222222222222222222222",
		"222222222222222222222222222222222222",
		"222222222222222222222222222222222222",
		"222222222222222222222222222222222222",
		"222222222222222222222222222222222222",
		"222222222222222222222222222222222222",
		"111111111111111111111111111111111111",
		"111111111111111111111111111111111111",
		"111111111111111111111111111111111111",
		"111111111111111111111111111111111111",
		"111111111111111111111111111111111111",
		"111111111111111111111111111111111111",
		"111111111111111111111111111111111111",
		"111111111111111111111111111111111111",
		"111111111111111111111111111111111111",
		"111111111111111111111111111111111111",
		"111111111111111111111111111111111111",
		"000000000000000000000000000000000000",
		"000000000000000000000000000000000000",
		"000000000000000000000000000000000000",
		"000000000000000000000000000000000000",
		"000000000000000000000000000000000000",
		"000000000000000000000000000000000000",
		"000000000000000000000000000000000000",
		"000000000000000000000000000000000000",
		"000000000000000000000000000000000000",
		"000000000000000000000000000000000000",
		"000000000000000000000000000000000000",
	]
```

In the paint loop replace `var atlas_coords = _get_atlas_coords(tile_type)` with `var atlas_coords = _atlas_for(tile_type, Vector2i(x, y))`, and after the loop (before the spawn-point lines) add `_build_derived_layers(map_data, height_data)`.

`_char_to_tile_type`: add `"^", "/": return TileGeneratorScript.TileType.VILLAGE_PATH  # stair/ramp ground`. Delete the now-unused `_get_atlas_coords` only if nothing else in the file calls it (grep first).

NPC relocations (one tile south, off the new row-8 cliff face):

```gdscript
var elder = _create_npc("Elder Theron", "elder", Vector2(11 * TILE_SIZE,9 * TILE_SIZE), ...)
var scholar = _create_npc("Scholar Milo", "villager", Vector2(19 * TILE_SIZE,9 * TILE_SIZE), [
var bram = _create_npc("Bram Smith", "blacksmith", Vector2(27 * TILE_SIZE,9 * TILE_SIZE), [
		sword.position = Vector2(29 * TILE_SIZE,9 * TILE_SIZE)
```

- [ ] **Step 4: Run the new test + every Harmonia/geometry canary**

Run: `for t in harmonia_tiers_regression village_height_grid_integrity village_npc_connectivity village_placement_walkability village_map_data_ragged_row_lint staged_scene_live_geometry_smoke harmonia_staged_scene_coord_sync_regression village_reachability_framework village_constructs_at_runtime harmonia_chapel_wiring harmonia_library_wiring harmonia_cartographer_interior_regression harmonia_after_cave_gate_regression theron_intro_no_duplicate_source_regression bram_shield_wiring_regression; do tools/run_tests.sh $t > tmp/$t.log 2>&1; echo "$t $?"; done`
Expected: all `0`. If `village_npc_connectivity` reports a split component, the stair placement is wrong — fix the map, never the test.

- [ ] **Step 5: Commit**

```bash
git add src/maps/villages/HarmoniaVillage.gd test/unit/test_harmonia_tiers_regression.gd
git commit -m "feat(harmonia): three tiers — castle approach / town / market, two stair pairs, NPCs off the cliff line"
```

---

### Task 11: Harmonia dressing — props and lamps

**Files:**
- Modify: `src/maps/villages/HarmoniaVillage.gd` (`_setup_buildings` tail)
- Test: add to `test/unit/test_harmonia_tiers_regression.gd`

**Interfaces:**
- Consumes: `_add_prop`, `_add_lamp`, `VillageProp.Kind`, `VillageProp.light_anchor`.

- [ ] **Step 1: Add the failing test**

```gdscript
func test_harmonia_is_dressed_and_lit() -> void:
	assert_gte(_v.props.get_child_count(), 12, "market stalls, trees, lamps, crates, cart")
	var lamps := 0
	for c in _v.lighting.get_children():
		if c is PointLight2D:
			lamps += 1
	assert_gte(lamps, 4, "lamp posts light the approach and the gate")
	for p in _v.props.get_children():
		for cell in p.footprint_cells(_cell(p.position - Vector2(0, 1))):
			assert_false(_v._face_cells.has(cell), "prop %s stands on a cliff face" % p.name)
			assert_false(_v._stair_cells.has(cell), "prop %s blocks a stair" % p.name)
	assert_true(_v._is_cell_walkable(_cell(_v.spawn_points["default"])), "entrance spawn kept clear")
```

- [ ] **Step 2: Run to verify it fails**

Run: `tools/run_tests.sh harmonia_tiers_regression` → the new test red (`props` empty).

- [ ] **Step 3: Dress the map** — append to `_setup_buildings` (every cell below is `g`/`d`/`p` ground on its tier, checked against the map rows; none is an NPC mark, stair, face, or the `(18,20)` entrance):

```gdscript
	# === TIER DRESSING (CrossCode pass 2026-08-21) ===
	# Castle approach (tier 2): lamps flank the top path, trees soften the corners
	_add_lamp_post(Vector2i(6, 3))
	_add_lamp_post(Vector2i(12, 3))
	_add_prop(VillagePropScript.Kind.TREE, Vector2i(4, 5))
	_add_prop(VillagePropScript.Kind.TREE, Vector2i(31, 5))
	_add_prop(VillagePropScript.Kind.PLANTER, Vector2i(20, 3))
	# Town (tier 1): trees at the edges, barrels behind the smithy
	_add_prop(VillagePropScript.Kind.TREE, Vector2i(4, 12))
	_add_prop(VillagePropScript.Kind.TREE, Vector2i(31, 12))
	_add_prop(VillagePropScript.Kind.BARREL, Vector2i(30, 9))
	_add_prop(VillagePropScript.Kind.CRATE, Vector2i(31, 9))
	_add_prop(VillagePropScript.Kind.FENCE, Vector2i(9, 14))
	# Market + gate (tier 0): stalls either side of the entrance, a cart, crates, lamps on the road
	_add_prop(VillagePropScript.Kind.STALL, Vector2i(14, 21))
	_add_prop(VillagePropScript.Kind.STALL, Vector2i(21, 21))
	_add_prop(VillagePropScript.Kind.CART, Vector2i(27, 21))
	_add_prop(VillagePropScript.Kind.CRATE, Vector2i(24, 24))
	_add_prop(VillagePropScript.Kind.BARREL, Vector2i(25, 24))
	_add_lamp_post(Vector2i(12, 25))
	_add_lamp_post(Vector2i(23, 25))
```

with the preload `const VillagePropScript = preload("res://src/exploration/VillageProp.gd")` at the top of HarmoniaVillage and this helper in **BaseVillage** (so later villages reuse it):

```gdscript
## A lamp post prop with its PointLight2D parked at the lamp head.
func _add_lamp_post(base_cell: Vector2i) -> VillageProp:
	var p := _add_prop(VillagePropScript.Kind.LAMP_POST, base_cell)
	_add_lamp(p.position + p.light_anchor, Color(1.0, 0.85, 0.55), 96, 0.9)
	return p
```

Note `light_anchor` is set inside `VillageProp._ready()` (during `add_child`), so it is valid by the time `_add_lamp` reads it.

- [ ] **Step 4: Run the canaries again**

Run the same loop as Task 10 step 4. Expected all `0`. A `village_reachability_framework` red means a prop footprint blocked a door approach — move the prop.

- [ ] **Step 5: Commit**

```bash
git add src/maps/villages/HarmoniaVillage.gd src/maps/villages/BaseVillage.gd test/unit/test_harmonia_tiers_regression.gd
git commit -m "feat(harmonia): tier dressing — lamps, trees, stalls, cart, crates"
```

---

### Task 12: Look at it — screenshots at three phases

**Files:**
- Create: `tools/village_screenshot.gd` (run script), `tools/village_screenshot.sh`

- [ ] **Step 1: Write the capture script**

```gdscript
extends SceneTree
## Loads a village scene, forces a day phase, renders 3 frames and writes tmp/screens/<village>_<phase>.png. Needs a real renderer (xvfb-run).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var village := "harmonia"
	var phase := 0.3
	for a in args:
		if a.begins_with("--village="):
			village = a.get_slice("=", 1)
		elif a.begins_with("--phase="):
			phase = float(a.get_slice("=", 1))
	var path := "res://src/maps/villages/%sVillage.tscn" % village.capitalize()
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("no scene at %s" % path)
		quit(2)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	if "lighting" in scene and scene.lighting != null:
		scene.lighting.phase_override = phase
	for i in range(6):
		await process_frame
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tmp/screens")
	var out := "res://tmp/screens/%s_%.2f.png" % [village, phase]
	img.save_png(out)
	print("[SCREEN] wrote %s" % out)
	quit(0)
```

```bash
#!/usr/bin/env bash
# Render Harmonia (or --village=<name>) at dawn/noon/night into tmp/screens/. Needs xvfb-run + a GL driver.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:-harmonia}"
command -v xvfb-run >/dev/null || { echo "xvfb-run missing — launch the game instead and take a cap (F12)"; exit 3; }
for P in 0.07 0.30 0.65; do
  xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 \
    -s tools/village_screenshot.gd -- "--village=$V" "--phase=$P" 2>&1 | command grep -a -E "SCREEN|ERROR" || true
done
ls -la tmp/screens/
```

- [ ] **Step 2: Run it, look at every PNG**

Run: `chmod +x tools/village_screenshot.sh && tools/village_screenshot.sh harmonia`
Then `Read` each `tmp/screens/harmonia_*.png`. Check: two cliff lines visible with lips; stairs read as stairs; grass fringe on path edges; lamps dark at 0.30, glowing at 0.65; props in front of/behind the player correctly (player spawns at the market). If `xvfb-run` is absent: `setsid godot < /dev/null > tmp/godot.stdout 2>&1 &`, walk to Harmonia, F12, and read the cap from the screenshots dir (memory: `project_f12_screenshot_path`).

- [ ] **Step 3: Tune palette/props from what you see** (commit any tweak with the screenshot it responds to in the message), then:

```bash
git add tools/village_screenshot.gd tools/village_screenshot.sh
git commit -m "tools: village_screenshot — render a village at three day phases for visual gating"
```

---

### Task 13: Full gate, docs, fold, tag

- [ ] **Step 1: Quiet gate** — check no other suite is running (`pgrep -af gut_cmdln || true`), then background the full suite:

```bash
tools/run_tests.sh > tmp/gate.log 2>&1; echo "EC=$?" >> tmp/gate.log
```

Poll with `tail -3 tmp/gate.log`; when `EC=` appears: `grep -E "^  (Passing|Failing)|EC=" tmp/gate.log`. Expected `Failing 0`, `EC=0`. Any red: rerun that file alone 3× — a physics test green in isolation and non-repeating is the documented suite-ordering flake; a repeatable red is yours.

- [ ] **Step 2: Docs** — in `CLAUDE.md`, add one bullet under Project Status after "Interiors":

```
- **Village elevation (CrossCode pass, 2026-08-21)**: villages carry an optional `height_data` digit grid beside `map_data`; cliff faces/edge colliders are DERIVED (`HeightGrid`), `^`/`/` are the only tier connectors and slow the walk to 0.6 through `get_terrain_speed_at`; `_is_cell_walkable` stays the authority, `_can_step` carries the height rule; Y-sorted `VillageProp`s with footprints; per-scene `VillageLighting` (CanvasModulate + lamps) replaces the overlay tint for villages. Harmonia = 3 tiers (castle approach / town / market). Spec: `docs/superpowers/specs/2026-08-21-crosscode-environment-design.md`.
```

Update the spec's Status line to `phases 1–2 implemented <sha>; phases 3–4 pending`.

- [ ] **Step 3: Fold + tag**

```bash
git fetch origin && git merge origin/main --no-edit   # re-gate if anything merged
git log --oneline -1 && git rev-parse HEAD             # HEAD identity you are about to push
git push origin HEAD:main
NEXT=$(git tag --sort=-creatordate | head -1 | awk -F'[.-]' '{printf "v%s.%s.%d-alpha", substr($1,2), $2, $3+1}')
git tag "$NEXT" && git push origin "$NEXT"
```

(Tags follow the live `v3.33.N-alpha` line — bump `Version.SEMVER` to match BEFORE the gate (find the file with `git ls-files | grep -i version.gd`) and confirm with `tools/run_tests.sh version_string_regression`.)

- [ ] **Step 4: Report** — to struktured: what shipped, the screenshots, the four NPC moves, and the two open threads (Phase 3 art seam brief for cowir-sprites; Phase 4 world generators).
