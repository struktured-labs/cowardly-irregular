extends Node2D
class_name BaseVillage

## Shared base class for all village exploration scenes.
##
## Eliminates ~150 lines of duplicated boilerplate across ~11 VillageScene
## scripts (scene setup, camera/controller wiring, save point, public API).
##
## Subclasses MUST override:
##   _get_area_id()              — "harmonia_village", etc (also used for config key)
##   _get_village_display_name() — human name used in save-log message
##   _get_map_pixel_size()       — Vector2i(MAP_WIDTH, MAP_HEIGHT) * TILE_SIZE for camera limits
##   _generate_map()             — populate tile_map, set spawn_points["default"]/["exit"]
##   _setup_transitions()        — create AreaTransition portals
##   _setup_buildings()          — inn/shop/bar/etc
##   _setup_treasures()          — chests
##   _setup_npcs()               — Area2D NPCs with dialogue
##
## Subclasses MAY override:
##   _get_save_point_position()  — defaults to (10,8) * TILE_SIZE
##   _get_player_spawn_fallback() — position used if spawn_points["default"] missing
##
## The base class owns:
##   exploration_ready / battle_triggered / area_transition signals
##   scene components (tile_map, player, camera, controller, tile_generator, spawn_points)
##   containers (transitions, npcs, buildings, treasures)
##   public API: spawn_player_at / resume / pause / set_player_job / set_player_appearance
##   helpers: _setup_transition_collision / _create_npc

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const OverworldNPCScript = preload("res://src/exploration/OverworldNPC.gd")
const WanderingNPCScript = preload("res://src/exploration/WanderingNPC.gd")
const HeightGridScript = preload("res://src/exploration/HeightGrid.gd")
const EnvTileSetsScript = preload("res://src/exploration/EnvironmentTileSets.gd")
const VillagePropScript = preload("res://src/exploration/VillageProp.gd")
const VillageLightingScript = preload("res://src/exploration/VillageLighting.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Tile size (consistent across all villages)
const TILE_SIZE: int = 32
const FRINGE_GRASS_TYPES := [TileGeneratorScript.TileType.VILLAGE_GRASS, TileGeneratorScript.TileType.GRASS]
## Stairs/ramps slow the walk (spec 2026-08-21: 0.6, the mud/snow scale) — read by OverworldPlayer through its terrain-speed seam
const STAIR_SPEED: float = 0.6

## Scene components
var tile_map: TileMapLayer
var cliff_map: TileMapLayer
var overlay_map: TileMapLayer
var player: Node2D
var _weather: WeatherSystem
var camera: Camera2D
var controller: Node
var tile_generator: Node

## Containers
var transitions: Node2D
var npcs: Node2D
var buildings: Node2D
var treasures: Node2D
var props: Node2D
var lighting: VillageLighting

## Spawn points (populated by subclass _generate_map)
var spawn_points: Dictionary = {}

## Elevation state, filled by _build_derived_layers (empty = flat village, today's behaviour)
var _height_grid: Array = []
## The village's own glyph rows, captured where every village already hands them over.
var _map_rows: Array = []
var _stair_cells: Dictionary = {}
var _face_cells: Dictionary = {}
var _prop_blocked: Dictionary = {}


func _ready() -> void:
	# Villages are never Mode 7 — clear the static so the overworld boost cannot leak in.
	Mode7Overlay.is_active = false
	Mode7Overlay.camera_angle = 0.0  # Defense-in-depth: OverworldPlayer reads this UNCONDITIONALLY, so a leaked non-zero angle would rotate village movement.
	_setup_scene()
	_setup_lighting()
	_generate_map()
	_setup_transitions()
	_setup_buildings()
	_setup_treasures()
	_setup_npcs()
	_place_authored_examines()
	_add_ambient_walkers(_get_ambient_walkers())
	_validate_placements()
	_setup_player()
	_setup_camera()
	_setup_controller()
	_setup_save_point()
	_setup_weather()

	if SoundManager:
		SoundManager.play_area_music(_get_music_area_id())
	var ambient_key := _get_ambient_key()
	if ambient_key != "" and SoundManager and SoundManager.has_method("play_ambient"):
		SoundManager.play_ambient(ambient_key)

	# Tick 279: ratchet visited_<village> story_flag. Pre-fix the
	# *Overworld scripts read visited_maple_heights / visited_brasston /
	# visited_rivet_row / visited_node_prime to switch the objective
	# arrow from "go to <village>" → "head to the forward portal", but
	# NOTHING anywhere set these flags. Result: the arrow stayed pointed
	# at the village even after the player had already been there.
	# Derived flag name = area_id minus the "_village" suffix so the
	# existing reads (visited_brasston, etc.) just work.
	if GameState:
		var aid: String = _get_area_id()
		if aid.ends_with("_village"):
			GameState.set_story_flag("visited_" + aid.replace("_village", ""), true)

	exploration_ready.emit()


## ---- Virtual hooks — subclasses override ----

func _get_area_id() -> String:
	return "village"


## Tick 92: per-village music routing. Default returns "village"
## which SoundManager.play_area_music maps to Harmonia medieval
## music (correct for W1 villages without their own track). W2-W6
## village subclasses MUST override this to return their manifest
## key (maple_heights_village / brasston_village / rivet_row_village
## / node_prime_village / vertex_village) — otherwise stepping into
## Maple Heights plays Harmonia medieval music instead of the
## suburban village track that was specifically composed for it.
func _get_music_area_id() -> String:
	return "village"


func _get_village_display_name() -> String:
	return "Village"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(24 * TILE_SIZE, 18 * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(10 * TILE_SIZE, 8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(400, 400)


func _generate_map() -> void:
	push_warning("BaseVillage._generate_map() not overridden by subclass")


func _setup_transitions() -> void:
	pass


func _setup_buildings() -> void:
	pass


## Shared interior-door builder. Subclasses (Harmonia, Eldertree, ...)
## call this from _setup_buildings to drop an AreaTransition that
## warps to a BaseInterior subclass with a single line.
## Pre-extraction (tick 36) HarmoniaVillage had ~20 lines of inline
## scaffolding per door; tick 37 moved the helper up to BaseVillage so
## any village can reuse it. The interior is expected to spawn the
## player at its `entrance` spawn_point.
func _add_interior_door(node_name: String, target_map: String, label: String, pos: Vector2) -> void:
	if not buildings:
		return
	var door = AreaTransitionScript.new()
	door.name = node_name
	door.target_map = target_map
	door.target_spawn = "entrance"
	# 2026-07-13: auto-warp trigger eating row-5 promenade tiles blocked forge/blacksmith reach in Harmonia (Library door at col 3-5, Cartographer door at col 22-23 both intersect row 5 after the earlier trigger-box-shift fix). Press A/Z to enter — indicator already draws when _player_in_zone.
	door.require_interaction = true
	door.indicator_text = label
	door.show_gate_visual = true
	door.position = pos
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	# Centered on the door origin the box sits in the impassable wall row; shift it DOWN onto the walkable approach or body_entered never fires (struktured 2026-07-12: "can't enter the library even on the arrow").
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 1.5)
	collision.position = Vector2(0, TILE_SIZE * 0.75)
	collision.shape = shape
	door.add_child(collision)
	door.collision_layer = 4
	door.collision_mask = 2
	door.monitoring = true
	door.transition_triggered.connect(_on_transition_triggered)
	buildings.add_child(door)


func _setup_treasures() -> void:
	pass


func _uses_scene_lighting() -> bool:
	return true


## GameLoop asks this to hand the day/night tint to the scene instead of the fullscreen overlay
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


## A lamp post prop with its PointLight2D parked at the lamp head.
func _add_lamp_post(base_cell: Vector2i) -> VillageProp:
	var p := _add_prop(VillagePropScript.Kind.LAMP_POST, base_cell)
	_add_lamp(p.position + p.light_anchor, Color(1.0, 0.85, 0.55), 96, 0.9)
	return p


## Place a Y-sorted prop by its base cell; its footprint joins the walkability grid and the physics world.
func _add_prop(kind: int, base_cell: Vector2i) -> VillageProp:
	var p: VillageProp = VillagePropScript.create(kind, base_cell)
	p.sheet_key = tile_generator._get_sheet_key()
	for c in p.footprint_cells(base_cell):
		_prop_blocked[c] = true
	props.add_child(p)
	return p


## Give every solid block of `glyphs` a drawn face. The block keeps its WALL tiles and so keeps
## its collision; this adds the elevation above them, Y-sorted so the player walks behind the roof.
## Struktured, 2026-10-30, on a SNES town: "I want some of that feel at least" -- the feel is the
## facade, not the pixels. A top-down block of wall tiles reads as a map; a drawn face reads as a town.
## ONLY FULL RECTANGLES: an L-shaped block's bounding box would paint a face over walkable ground,
## so a ragged block is left exactly as it is today rather than guessed at.
## A block whose ART is a building -- an inn, a shop, the bar -- already HAS a face and is skipped.
## A DOOR does not claim its block: it sorts below the facade's base, so it draws on the house's front.
## Call this LAST in _setup_buildings, so every node it must defer to already exists.
func _spawn_house_facades(glyphs: Array, roof_colors: Array = [], style: String = "timber") -> int:
	if _map_rows.is_empty() or props == null:
		return 0
	var claimed: Array = []
	if buildings != null:
		for b in buildings.get_children():
			if b is Node2D and not (b is AreaTransition):
				claimed.append(_building_cells(b))
	var want := {}
	for g in glyphs:
		want[g] = true
	var seen := {}
	var built: int = 0
	for y in range(_map_rows.size()):
		var row: String = _map_rows[y]
		for x in range(row.length()):
			var cell := Vector2i(x, y)
			if seen.has(cell) or not want.has(row[x]):
				continue
			var block: Array = _flood_block(cell, want, seen)
			var minp := block[0] as Vector2i
			var maxp := block[1] as Vector2i
			var cells: int = block[2]
			var bw: int = maxp.x - minp.x + 1
			var bh: int = maxp.y - minp.y + 1
			if cells != bw * bh:
				continue
			## The GROUND ROW IS LEFT ALONE: Harmonia's chapel and library doors sit on their
			## block's bottom row, and a full-height face would paint over a real door and its
			## gate visual. The art spans one row ABOVE the block down to one row above its
			## base, so the roof rises and every entrance stays exactly as it is.
			if bh < 2 or _block_is_claimed(minp, maxp, claimed):
				continue
			var house: VillageProp = VillagePropScript.create(VillagePropScript.Kind.HOUSE, Vector2i(minp.x, maxp.y - 1))
			house.sheet_key = tile_generator._get_sheet_key()
			house.size_tiles = Vector2i(bw, bh)
			if not roof_colors.is_empty():
				house.roof_color = roof_colors[built % roof_colors.size()]
			## A different period from the colour cycle, so colour and shape do not lock together.
			house.roof_peaked = built % 2 == 1
			house.house_style = style
			props.add_child(house)
			built += 1
	return built


func _block_is_claimed(minp: Vector2i, maxp: Vector2i, claimed: Array) -> bool:
	## The facade's extent, not the block's: the roof rises one row ABOVE it, where a shop may stand.
	var block := Rect2i(minp - Vector2i(0, 1), maxp - minp + Vector2i(1, 2))
	for r in claimed:
		if block.intersects(r):
			return true
	return false


## The cells a building's ART covers, not just its origin: the bar sits beside its block and its art spans it.
func _building_cells(b: Node2D) -> Rect2i:
	var spr = b.get("sprite")
	if spr is Sprite2D and spr.texture != null:
		var r: Rect2 = spr.get_rect()
		r.position += b.position + spr.position
		var lo := Vector2i(floori(r.position.x / TILE_SIZE), floori(r.position.y / TILE_SIZE))
		var hi := Vector2i(ceili(r.end.x / TILE_SIZE), ceili(r.end.y / TILE_SIZE))
		return Rect2i(lo, hi - lo)
	return Rect2i(Vector2i(floori(b.position.x / TILE_SIZE), floori(b.position.y / TILE_SIZE)), Vector2i.ONE)


## Bounds and cell count of the contiguous run of wanted glyphs containing `start`.
func _flood_block(start: Vector2i, want: Dictionary, seen: Dictionary) -> Array:
	var minp := start
	var maxp := start
	var n: int = 0
	var stack: Array = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if seen.has(c) or c.y < 0 or c.y >= _map_rows.size():
			continue
		var r: String = _map_rows[c.y]
		if c.x < 0 or c.x >= r.length() or not want.has(r[c.x]):
			continue
		seen[c] = true
		n += 1
		minp = Vector2i(min(minp.x, c.x), min(minp.y, c.y))
		maxp = Vector2i(max(maxp.x, c.x), max(maxp.y, c.y))
		stack.append(c + Vector2i(1, 0))
		stack.append(c + Vector2i(-1, 0))
		stack.append(c + Vector2i(0, 1))
		stack.append(c + Vector2i(0, -1))
	return [minp, maxp, n]


## ---- Placement validation (live playtest 2026-07-11, msg 2360) ----
## A quest hen spawned inside Harmonia's Inn wall block and some wanderers
## pathed through building footprints. Every npcs-container child gets its
## spawn snapped to a walkable cell; wanderer patrol legs get clipped at
## the first impassable tile. Doors live in `buildings` and are exempt —
## they intentionally hug wall faces.

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


## Sheet villages draw cliff/overlay art from; "" forces the procedural palette (a village whose world sheet has manifest cliff art otherwise always wins over _get_cliff_palette()).
func _get_cliff_sheet_key() -> String:
	return tile_generator._get_sheet_key()


func get_terrain_speed_at(pos: Vector2) -> float:
	var cell := Vector2i(int(floor(pos.x / TILE_SIZE)), int(floor(pos.y / TILE_SIZE)))
	return STAIR_SPEED if _stair_cells.has(cell) else 1.0


## The world's tile generator. W1 villages keep medieval; W2-W6 override with their own.
func _get_tile_generator() -> Node:
	return TileGeneratorScript.new()


## Ground types the grass-fringe overlay creeps out from; per-world because "grass" differs.
func _get_fringe_ground_types() -> Array:
	return FRINGE_GRASS_TYPES


func _cell_salt(cell: Vector2i) -> int:
	return cell.x * 73856093 ^ cell.y * 19349663


## Atlas coords for a tile type at a cell, resolved against WHICHEVER generator this village
## uses — the per-world atlases are 4x4 with id == index in _get_tile_order(), and only the
## medieval one carries the per-cell variant table.
func _atlas_for(tile_type: int, cell: Vector2i) -> Vector2i:
	var cols: int = int(tile_generator._get_atlas_dimensions().x) if tile_generator else 5
	if tile_generator is TileGenerator:
		var id: int = TileGeneratorScript.get_tile_id_variant(tile_type, _cell_salt(cell))
		return Vector2i(id % cols, id / cols)
	var order: Array = tile_generator._get_tile_order() if tile_generator else []
	var idx: int = order.find(tile_type)
	return Vector2i(idx % cols, idx / cols) if idx >= 0 else Vector2i.ZERO


func _ground_type(cell: Vector2i) -> int:
	if tile_map == null or tile_map.get_cell_source_id(cell) == -1:
		return -1
	var ac := tile_map.get_cell_atlas_coords(cell)
	var order: Array = tile_generator._get_tile_order()
	var id: int = ac.y * tile_generator._get_atlas_dimensions().x + ac.x
	return int(order[id]) if id >= 0 and id < order.size() else -1


## Derive cliffs/stairs from the height grid and paint them; call at the end of _generate_map. Empty height rows = flat village, nothing painted.
## The exit trigger is centred on spawn_points["exit"], and every map loop set that to the FIRST 'X' — the block's
## top-left — so a 6-wide trigger missed the exit's right third, fired on the path beside it, and drew the gate off the road.
static func exit_centre_of(map_rows: Array, tile: int) -> Vector2:
	var x0 := -1
	var x1 := -1
	var y0 := -1
	for y in map_rows.size():
		var row := str(map_rows[y])
		for x in row.length():
			if row[x] != "X":
				continue
			if y0 < 0:
				y0 = y
			if y == y0:
				x0 = x if x0 < 0 else mini(x0, x)
				x1 = maxi(x1, x)
	if y0 < 0:
		return Vector2.INF
	return Vector2((x0 + x1 + 1) * tile / 2.0, y0 * tile + tile / 2.0)


func _build_derived_layers(map_rows: Array, height_rows: Array) -> void:
	_map_rows = map_rows
	var exit_at := exit_centre_of(map_rows, TILE_SIZE)
	if exit_at != Vector2.INF:
		spawn_points["exit"] = exit_at
	_stair_cells = HeightGridScript.stair_cells(map_rows)
	_height_grid = HeightGridScript.parse(height_rows)
	for c in _stair_cells:
		var id: int = EnvTileSetsScript.RAMP_ID if _stair_cells[c] == "/" else EnvTileSetsScript.STAIR_ID
		overlay_map.set_cell(c, 0, EnvTileSetsScript.atlas_coords(id))
	if _height_grid.is_empty():
		_paint_fringe()
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
		# A FACE WINS OVER AN EDGE. Both dicts can name the same cell, and this loop runs
		# second, so an edge tile replaced the face tile -- keeping only a thin edge-strip
		# collider where the face had a full-tile one. _is_cell_walkable still counted the
		# cell as a solid face, so the grid said "wall" and the player walked through it.
		# Measured on Grimhollow: 2 of 6 face cells, painted atlas (8,0) and (2,0).
		if _face_cells.has(c):
			continue
		cliff_map.set_cell(c, 0, EnvTileSetsScript.atlas_coords(int(pieces["edges"][c])))
	_paint_fringe()
	# Ledge shadows go on AFTER fringe so the shadow wins the cell under a face
	for c in _face_cells:
		var below: Vector2i = c + Vector2i(0, 1)
		if _tile_is_open(below) and not _face_cells.has(below) and not _stair_cells.has(below):
			overlay_map.set_cell(below, 0, EnvTileSetsScript.atlas_coords(EnvTileSetsScript.SHADOW_ID))


func _fringe_mask(cell: Vector2i) -> int:
	var mask := 0
	for bit in HeightGridScript.DIRS:
		if _ground_type(cell + HeightGridScript.DIRS[bit]) in _get_fringe_ground_types():
			mask |= bit
	return mask


## Grass tufts creep onto neighbouring path/dirt — the cheap half of terrain transitions.
func _paint_fringe() -> void:
	for c in tile_map.get_used_cells():
		if not _tile_is_open(c) or _face_cells.has(c) or _stair_cells.has(c):
			continue
		if _ground_type(c) in _get_fringe_ground_types():
			continue
		var m := _fringe_mask(c)
		if m != 0:
			overlay_map.set_cell(c, 0, EnvTileSetsScript.atlas_coords(m))


## Nearest walkable cell center via ring search (radius ≤ 5 tiles);
## returns the input unchanged if it is already walkable or nothing is found.
func _find_walkable_near(pos: Vector2) -> Vector2:
	var cell := Vector2i(int(floor(pos.x / TILE_SIZE)), int(floor(pos.y / TILE_SIZE)))
	if _is_cell_walkable(cell):
		return pos
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := cell + Vector2i(dx, dy)
				if _is_cell_walkable(c):
					return Vector2((c.x + 0.5) * TILE_SIZE, (c.y + 0.5) * TILE_SIZE)
	push_warning("[%s] no walkable cell within 5 tiles of %s" % [_get_area_id(), pos])
	return pos


## Placements this village had to move; authored spots should never need it.
var relocated_count: int = 0
var placements_validated: bool = false


## An OverworldNPC never sets its node name, so the relocation warning said `@Area2D@17548` and was
## unreadable — the same thing that made a shop_interior log line take twenty minutes to attribute.
func _placement_label(n: Node) -> String:
	for key in ["npc_name", "display_name"]:
		if n.get(key) != null and str(n.get(key)) != "":
			return str(n.get(key))
	return str(n.name)


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE_SIZE)), int(floor(pos.y / TILE_SIZE)))


## Who already stands on `cell`, by label, or "". Read LIVE so an NPC this same pass already moved
## counts as occupying its new cell rather than its authored one.
func _occupant_of_cell(cell: Vector2i, except: Node) -> String:
	if npcs == null:
		return ""
	for other in npcs.get_children():
		if other == except or not (other is Node2D):
			continue
		if _cell_of((other as Node2D).position) == cell:
			return _placement_label(other)
	return ""


## ⛔ THE WARNING NAMES THE OCCUPANT, AND THE SWEEP DELIBERATELY DOES NOT AVOID THEM.
## Three NPCs have been relocated onto a prop's cell — MapleHeights/Gerald (onto Neighborhood Dad's
## tile), Grimhollow/Creepy Child Wednesday, Sandrift/Sand Sage Mirage. Gerald is a quest giver and
## interaction is nearest-wins, so the far one of two NPCs on one cell may never be selected.
## All three were fixed by moving the PROP: a planter is decoration, a quest giver's position is
## content. Reserving a free cell here instead was considered and REJECTED (cowir-main 2026-10-12) —
## it would quietly produce a placement no author chose, trading a loud authoring error for a silent
## content change. So this says what happened and what to do, and leaves the fix to the author.
static func relocation_warning(area_id: String, who: String, from: Vector2, to: Vector2,
		occupant: String) -> String:
	var base: String = "[%s] relocated '%s' off impassable tile %s -> %s" % [area_id, who, from, to]
	if occupant == "":
		return base
	return base + ", ONTO '%s' — interaction is nearest-wins, so one of them may be unreachable; move the PROP, not the NPC" % occupant


func _validate_placements() -> void:
	if npcs == null:
		return
	placements_validated = true
	for n in npcs.get_children():
		if not (n is Node2D):
			continue
		if n.has_method("set_patrol"):
			_validate_patrol(n)
		else:
			var fixed := _find_walkable_near(n.position)
			if fixed != n.position:
				push_warning(relocation_warning(_get_area_id(), _placement_label(n), n.position, fixed,
					_occupant_of_cell(_cell_of(fixed), n)))
				relocated_count += 1
				n.position = fixed


## Snap patrol endpoints, then clip any leg at the last clear half-tile
## sample before it would cross an impassable cell (wanderers lerp in
## _process with no physics, so authored legs must be walkable end-to-end).
func _validate_patrol(w: Node2D) -> void:
	var raw: Array[Vector2] = w.get_patrol() if w.has_method("get_patrol") else []
	if raw.size() < 2:
		return
	var pts: Array[Vector2] = []
	for p in raw:
		pts.append(_find_walkable_near(p))
	var changed := pts != raw
	for i in range(pts.size()):
		var a: Vector2 = pts[i]
		var j := (i + 1) % pts.size()
		var b: Vector2 = pts[j]
		var steps := int(ceil(a.distance_to(b) / (TILE_SIZE * 0.5)))
		var last_clear := a
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
	if changed:
		push_warning("[%s] adjusted patrol for '%s' around impassable tiles" % [_get_area_id(), w.name])
		relocated_count += 1
		w.set_patrol(pts)


func _setup_npcs() -> void:
	pass


## ---- Shared scene/node setup ----

func _setup_scene() -> void:
	tile_generator = _get_tile_generator()
	add_child(tile_generator)

	tile_map = TileMapLayer.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = tile_generator.create_tileset()
	add_child(tile_map)

	cliff_map = TileMapLayer.new()
	cliff_map.name = "Cliffs"
	cliff_map.tile_set = EnvTileSetsScript.build_cliff_tileset(_get_cliff_palette(), _get_cliff_sheet_key())
	add_child(cliff_map)

	overlay_map = TileMapLayer.new()
	overlay_map.name = "Overlay"
	overlay_map.tile_set = EnvTileSetsScript.build_overlay_tileset(_get_cliff_palette(), _get_cliff_sheet_key())
	add_child(overlay_map)

	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)

	buildings = Node2D.new()
	buildings.name = "Buildings"
	## Y-sorted like props and NPCs: unsorted, every door and shop drew at y=0, behind every facade.
	buildings.y_sort_enabled = true
	add_child(buildings)

	treasures = Node2D.new()
	treasures.name = "Treasures"
	add_child(treasures)

	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)

	# Y-sort so the player walks BEHIND tall props and among NPCs by feet position
	y_sort_enabled = true
	npcs.y_sort_enabled = true

	props = Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	add_child(props)


func _setup_transition_collision(trans: Area2D, size: Vector2) -> void:
	trans.collision_layer = 4
	trans.collision_mask = 2
	trans.monitoring = true
	trans.monitorable = true

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	trans.add_child(collision)


func _create_npc(npc_name: String, npc_type: String, pos: Vector2, dialogue: Array) -> Area2D:
	var npc = OverworldNPCScript.new()
	npc.npc_name = npc_name
	npc.npc_type = npc_type
	npc.position = pos
	npc.dialogue_lines = dialogue
	return npc


## A "custom" objective advances ONLY via QuestSystem.notify_flag — notify_talk skips the type
## entirely — so a step with no emitter strands the quest with no in-game way to progress it.
## The interact button for a prompt, derived per device. "[A]" is correct on Nintendo pads ONLY.
func _interact_label(verb: String) -> String:
	var hint := InputProfileManager.hint_for_action("ui_accept")
	return "%s %s" % [hint, verb] if hint != "" else verb


## `verb` is the WORDS ONLY — the button is derived here, so no caller can freeze one.
func _add_quest_examine_point(qid: String, flag: String, verb: String, examined: String,
		idle: String, pos: Vector2) -> void:
	var ExamineScript = load("res://src/exploration/QuestExaminePoint.gd")
	if ExamineScript == null:
		return
	var point = ExamineScript.new()
	point.quest_id = qid
	point.flag = flag
	point.indicator_text = _interact_label(verb)
	point.examine_text = examined
	point.idle_text = idle
	point.position = pos
	npcs.add_child(point)


## One stop on a multi-point objective — `flag` fires only once ALL group_size members are examined.
func _add_quest_route_point(qid: String, flag: String, index: int, group_size: int,
		verb: String, examined: String, idle: String, pos: Vector2) -> void:
	var ExamineScript = load("res://src/exploration/QuestExaminePoint.gd")
	if ExamineScript == null:
		return
	var point = ExamineScript.new()
	point.quest_id = qid
	point.flag = flag
	point.member_index = index
	point.group_size = group_size
	point.indicator_text = _interact_label(verb)
	point.examine_text = examined
	point.idle_text = idle
	point.position = pos
	npcs.add_child(point)


## Create a WanderingNPC that patrols a small loop. Use for ambient
## villagers who should walk between landmarks. The sprite_archetype must
## match an asset in `assets/sprites/npcs/<name>/overworld.png` (one of
## the 20 GPT-Image-1 archetype sheets shipped in 1557f89). Patrol points
## describe a closed loop including the starting position.
##
## (User feedback 2026-05-02: "village characters should walk around,
## at least some of them" — head-lock constraints already satisfied by
## the bb60068 sprite pass.)
## Villagers on errands. A village returns [{name, archetype, line}, ...]; [] keeps it as authored.
func _get_ambient_walkers() -> Array:
	return []


const WALKER_MIN_RUN: int = 5
const WALKER_MAX_RUN: int = 9
## The village gate's keep-clear box around an exit, the same one test_a_village_exit_sits_on_its_exit judges.
const GATE_CLEAR := Rect2(-44.0, -76.0, 88.0, 80.0)
## Each walker's line as DERIVED, by node name: the record placement validation must leave untouched.
var ambient_walker_lines: Dictionary = {}


## Each walker's line is DERIVED from this village's own walkability, so no map edit can strand one in a wall.
func _add_ambient_walkers(roster: Array) -> int:
	if roster.is_empty() or npcs == null:
		return 0
	var runs := _walker_runs(roster.size())
	var added: int = 0
	for spec in roster:
		if added >= runs.size():
			push_warning("[%s] only %d walker line(s) fit; '%s' has nowhere to walk" % [_get_area_id(), runs.size(), spec.get("name", "?")])
			break
		var run: Array = runs[added]
		var loop: Array[Vector2] = [_cell_centre(run[0]), _cell_centre(run[1])]
		ambient_walker_lines["Walker_%s" % str(spec["name"]).validate_node_name()] = loop.duplicate()
		var w := _create_wandering_npc(spec["name"], spec["archetype"], spec["line"], loop,
			spec.get("theme", "villager"), spec.get("portrait", spec["archetype"]))
		w.name = "Walker_%s" % str(spec["name"]).validate_node_name()
		npcs.add_child(w)
		added += 1
	return added


func _cell_centre(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * TILE_SIZE, (cell.y + 0.5) * TILE_SIZE)


## Horizontal runs of steppable cells clear of doors, exits and anyone standing still; longest first,
## and never two on neighbouring rows over the same columns, so walkers do not pace on top of each other.
func _walker_runs(want: int = 0) -> Array:
	var size := _walker_grid_size()
	if size == Vector2i.ZERO:
		return []
	var avoid := {}
	for container in [npcs, buildings, treasures, transitions]:
		if container == null:
			continue
		for n in container.get_children():
			## A walker moves, so its spawn cell is no obstacle -- and skipping it keeps the derivation a pure function of the map.
			if not (n is Node2D) or n is WanderingNPC:
				continue
			for r in _keep_clear_rects(n as Node2D, container == transitions):
				_mark_cells(avoid, r)
	var margin: int = 3
	var runs: Array = []
	for y in range(margin, size.y - margin):
		var width: int = size.x
		var start: int = -1
		for x in range(margin, width - margin + 1):
			var cell := Vector2i(x, y)
			var open: bool = x < width - margin and not avoid.has(cell) and _is_cell_walkable(cell)
			if open and start >= 0 and _can_step(Vector2i(x - 1, y), cell):
				continue
			if start >= 0:
				var n: int = x - start
				if n >= WALKER_MIN_RUN:
					var take: int = mini(n, WALKER_MAX_RUN)
					var a: int = start + (n - take) / 2
					runs.append([Vector2i(a, y), Vector2i(a + take - 1, y)])
			start = x if open else -1
	runs.sort_custom(func(p, q):
		var lp: int = p[1].x - p[0].x
		var lq: int = q[1].x - q[0].x
		return lp > lq if lp != lq else (p[0].y < q[0].y if p[0].y != q[0].y else p[0].x < q[0].x))
	var chosen: Array = []
	for r in runs:
		var clash := false
		for c in chosen:
			if absi(r[0].y - c[0].y) <= 2 and r[0].x <= c[1].x and c[0].x <= r[1].x:
				clash = true
				break
		if not clash:
			chosen.append(r)
	## Vertical lines only when the rows cannot fill the roster, so a village the rows already serve is unchanged.
	if chosen.size() < want:
		for r in _walker_column_runs(size, avoid, margin):
			if not chosen.any(func(c): return _run_rect(c).grow(2).intersects(_run_rect(r))):
				chosen.append(r)
	return chosen


func _walker_column_runs(size: Vector2i, avoid: Dictionary, margin: int) -> Array:
	var runs: Array = []
	for x in range(margin, size.x - margin):
		var start: int = -1
		for y in range(margin, size.y - margin + 1):
			var cell := Vector2i(x, y)
			var open: bool = y < size.y - margin and not avoid.has(cell) and _is_cell_walkable(cell)
			if open and start >= 0 and _can_step(Vector2i(x, y - 1), cell):
				continue
			if start >= 0:
				var n: int = y - start
				if n >= WALKER_MIN_RUN:
					var take: int = mini(n, WALKER_MAX_RUN)
					var a: int = start + (n - take) / 2
					runs.append([Vector2i(x, a), Vector2i(x, a + take - 1)])
			start = y if open else -1
	runs.sort_custom(func(p, q): return (p[1] - p[0]).length() > (q[1] - q[0]).length())
	return runs


func _run_rect(r: Array) -> Rect2i:
	var lo := Vector2i(mini(r[0].x, r[1].x), mini(r[0].y, r[1].y))
	var hi := Vector2i(maxi(r[0].x, r[1].x), maxi(r[0].y, r[1].y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Map size in cells: the glyph rows when a village has them, else its declared pixel size (the strip mall, the plaza).
func _walker_grid_size() -> Vector2i:
	if not _map_rows.is_empty():
		return Vector2i((_map_rows[0] as String).length(), _map_rows.size())
	var px := _get_map_pixel_size()
	return Vector2i(px.x / TILE_SIZE, px.y / TILE_SIZE)


## World-space boxes a walker's line must stay out of: an exit's gate, a door's press zone, else the node's own cell +-1.
func _keep_clear_rects(n: Node2D, is_exit: bool) -> Array:
	var out: Array = []
	if is_exit:
		out.append(Rect2(n.position + GATE_CLEAR.position, GATE_CLEAR.size).grow(8.0))
	for c in n.get_children():
		if n is Area2D and c is CollisionShape2D and c.shape is RectangleShape2D:
			var sz: Vector2 = (c.shape as RectangleShape2D).size
			out.append(Rect2(n.position + c.position - sz * 0.5, sz).grow(8.0))
	var cell := _cell_of(n.position)
	out.append(Rect2(Vector2(cell - Vector2i.ONE) * TILE_SIZE, Vector2(3, 3) * TILE_SIZE))
	return out


## Every cell whose square touches `r`, not just those whose centre is inside: a line through a corner is still inside.
func _mark_cells(avoid: Dictionary, r: Rect2) -> void:
	for y in range(floori(r.position.y / TILE_SIZE), ceili(r.end.y / TILE_SIZE)):
		for x in range(floori(r.position.x / TILE_SIZE), ceili(r.end.x / TILE_SIZE)):
			avoid[Vector2i(x, y)] = true


func _create_wandering_npc(npc_name: String, archetype: String, dialogue: String, patrol_loop: Array[Vector2], dialogue_theme: String = "elder", dialogue_portrait: String = "elder") -> Area2D:
	var w = WanderingNPCScript.new()
	w.npc_name = npc_name
	w.dialogue = dialogue
	w.sprite_archetype = archetype
	w.dialogue_theme = dialogue_theme
	w.dialogue_portrait = dialogue_portrait
	w.set_patrol(patrol_loop)
	return w


func _setup_player() -> void:
	player = OverworldPlayerScript.new()
	player.name = "Player"
	player.position = spawn_points.get("default", _get_player_spawn_fallback())
	player.set_job("fighter")
	# Villages always use the slower interior speed (50% of overworld). The
	# parent-name keyword scan in OverworldPlayer is a defensive heuristic
	# but isn't guaranteed to fire before the first move (parent assignment
	# happens after add_child). Set the flag explicitly here so the first
	# step is at the correct speed. (User feedback 2026-05-02: "village walk
	# speed should be 50% slower (similar to how we made dungeon walk speed)".)
	player._is_interior = true
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	camera.make_current()

	camera.zoom = Vector2(2.0, 2.0)

	var map_pixel_size = _get_map_pixel_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_pixel_size.x
	camera.limit_bottom = map_pixel_size.y

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0


func _setup_controller() -> void:
	controller = OverworldControllerScript.new()
	controller.name = "Controller"
	controller.player = player
	controller.encounter_enabled = false  # villages are safe zones by default
	controller.current_area_id = _get_area_id()

	controller.set_area_config(_get_area_id(), true, 0.0, [])

	controller.battle_triggered.connect(_on_battle_triggered)
	controller.menu_requested.connect(_on_menu_requested)

	add_child(controller)


func _setup_save_point() -> void:
	var save_pt = SavePoint.new()
	save_pt.position = _get_save_point_position()
	save_pt.save_requested.connect(_on_save_requested)
	add_child(save_pt)


func _on_save_requested() -> void:
	if SaveSystem and SaveSystem.has_method("quick_save"):
		SaveSystem.quick_save()
		print("[SAVE] Quick save triggered from %s save point" % _get_village_display_name())


func _on_transition_triggered(target_map: String, spawn_point: String) -> void:
	area_transition.emit(target_map, spawn_point)


func _on_battle_triggered(enemies: Array) -> void:
	battle_triggered.emit(enemies)


func _on_menu_requested() -> void:
	pass


## ---- Public API (consumed by GameLoop/MapSystem) ----

## Spawn player at a named spawn point (does nothing if unknown)
func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name) and player:
		player.teleport(spawn_points[spawn_name])
		if player.has_method("reset_step_count"):
			player.reset_step_count()


## Weather v2 (2026-09-04): villages inherit the world's live weather — same renderer
## as the overworld, reading GameState. Interiors don't extend BaseVillage, so they skip it.
func _setup_weather() -> void:
	_weather = WeatherSystem.new()
	add_child(_weather)
	var world_num: int = GameState.current_world if GameState else 1
	_weather.setup(self, player, WeatherSystem.world_id_for(world_num))


func _process(delta: float) -> void:
	if _weather:
		_weather.process(delta)


## Resume exploration input
func resume() -> void:
	if controller and controller.has_method("resume_exploration"):
		controller.resume_exploration()


## Pause exploration input
func pause() -> void:
	if controller and controller.has_method("pause_exploration"):
		controller.pause_exploration()


## Set the player's job id
func set_player_job(job_name: String) -> void:
	if player:
		player.set_job(job_name)


## Set the player's appearance from the party leader combatant
func set_player_appearance(leader) -> void:
	if player and player.has_method("set_appearance_from_leader"):
		player.set_appearance_from_leader(leader)


func _exit_tree() -> void:
	# Stop the village loop so it does not leak into the next scene, the way BaseInterior does.
	if _get_ambient_key() != "" and SoundManager and SoundManager.has_method("stop_ambient"):
		SoundManager.stop_ambient()


## Virtual: the ambient-loop key layered UNDER this village's music, or "" for none.
## `ambient_village` is a 144.9s authored bed that had never played — nothing called
## play_ambient with it, and villages had no ambient layer at all until 2026-09-16.
## Same hook the overworld carries: weather clearing must hand the layer back to the village.
func restore_place_ambient() -> void:
	var key := _get_ambient_key()
	if key != "" and SoundManager and SoundManager.has_method("play_ambient"):
		SoundManager.play_ambient(key)


func _get_ambient_key() -> String:
	## Was a bare "ambient_village" for all 13 villages: 6 non-W1 ones layered a MEDIEVAL market.
	if SoundManager and SoundManager.has_method("village_ambient_key"):
		return SoundManager.village_ambient_key()
	return ""


## ---- Authored examines (data/examine_texts.json) ----

## `data/examine_texts.json` has been authored since 2026-04-21 and read by nobody. Eleven of its
## entries are this castle's and landed with CastleHarmonia; THESE THIRTEEN are the village half,
## and every village has been walking past its own authored prose for six months.
##
## 🔑 OFFSETS FROM THE ARRIVAL SPAWN, NOT ABSOLUTE CELLS. A village resize shifts every `.gd`
## Vector2 and touches no data file, which is the documented trap for staged-cutscene coords — and
## an absolute cell is the coincidental value this repo warns about. The spawn MOVES WITH ITS MAP,
## so an offset keeps its meaning ("three cells in from where the player arrives") when a
## coordinate would not. The resolver then degrades to the nearest walkable free cell, so the worst
## case of a regenerated map is "a few cells off", never "inside a building".
##
## ⚠️ PLACEMENT IS ON THE ARRIVAL APPROACH BY DESIGN, not a per-map thematic survey. These are
## signs, boards, wells and monuments in village squares, and the player arrives in the square;
## discoverability is the point for prose that has reached nobody. Where a map wants one somewhere
## specific, override `_examine_offset_for`.
const _EXAMINE_OFFSETS := {
	"harmonia_well": Vector2i(-2, -3),
	"harmonia_statue": Vector2i(2, -3),
	"eldertree_gravestone": Vector2i(0, -3),
	"frosthold_cairn": Vector2i(0, -3),
	"grimhollow_warning": Vector2i(0, 3),
	"sandrift_caravan_post": Vector2i(0, -3),
	"brasston_clocktower_plaque": Vector2i(0, -3),
	"ironhaven_furnace_log": Vector2i(0, -3),
	"maple_heights_hoa_board": Vector2i(0, -3),
	"rivet_row_union_board": Vector2i(0, -3),
	"node_prime_terminal": Vector2i(-2, -3),
	"node_prime_sticky": Vector2i(2, -3),
	"vertex_monolith": Vector2i(0, -3),
	## cowir-story 2026-10-13 — second looks for three villages that had one each. Offsets kept
	## clear of the first entry's cell in each village; the resolver still walks to a free cell.
	"eldertree_grafted_branch": Vector2i(-3, 1),
	"frosthold_meltwater_mark": Vector2i(3, 1),
	"grimhollow_lantern_ledger": Vector2i(-3, -1),
	## cowir-story 2026-10-13 — second looks for the remaining six. Each is an institutional
	## document, like that village's first entry, and each offset clears the first one's cell.
	"brasston_redundancy_index": Vector2i(3, -1),
	"ironhaven_strike_ledger": Vector2i(-1, 3),
	"maple_heights_appendix_form": Vector2i(1, 3),
	"rivet_row_incident_numbers": Vector2i(-3, 2),
	"sandrift_rain_tally": Vector2i(3, 2),
	"vertex_threshold_tally": Vector2i(2, 3),
}

const _EXAMINE_PACK := "res://data/examine_texts.json"
const _EXAMINE_SEARCH_RADIUS: int = 4


## Subclasses may name a different offset for one entry without touching the table.
func _examine_offset_for(examine_id: String) -> Vector2i:
	return _EXAMINE_OFFSETS.get(examine_id, Vector2i.ZERO)


## Only this village's entries, so a pack-wide key change cannot pull another scene's text in.
func _load_examine_pack() -> Dictionary:
	if not FileAccess.file_exists(_EXAMINE_PACK):
		push_warning("[%s] %s is missing — the village keeps its other props" % [_get_area_id(), _EXAMINE_PACK])
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_EXAMINE_PACK))
	if not (parsed is Dictionary):
		push_warning("[%s] %s did not parse" % [_get_area_id(), _EXAMINE_PACK])
		return {}
	var all: Dictionary = (parsed as Dictionary).get("examines", {})
	var mine: Dictionary = {}
	for k in all.keys():
		var e = all[k]
		if e is Dictionary and str((e as Dictionary).get("scene", "")) == _get_area_id():
			mine[str(k)] = e
	return mine


## Cell-CENTRED, and that is load-bearing rather than tidy: a 28px readable parked on a cell CORNER
## sits 24px off every axis-aligned probe, so it draws and cannot be pressed (HarmoniaVillage:478).
func _examine_px(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2, cell.y * TILE_SIZE + TILE_SIZE / 2)


## The cells already holding something a player can interact with — an examine may not share one,
## because interaction is nearest-wins and the loser becomes unreachable (.344, two librarians).
func _occupied_interact_cells() -> Array:
	## ⛔ WAS `npcs.get_children()`, WHICH MISSED THE SAVE CRYSTAL AND EVERY DOOR. The crystal is
	## parented to the scene root and doors sit under `transitions`, so the scan that exists to stop
	## an examine landing on a contested cell could not see the two things it most needed to.
	return InteractGeometry.occupied_cells(self, float(TILE_SIZE))


## Resolve an intended cell to the nearest walkable, unoccupied one. Returns the intended cell
## itself when it is already good, and Vector2i(-1, -1) when nothing within the radius works.
func _resolve_examine_cell(want: Vector2i, taken: Array) -> Vector2i:
	for r in range(0, _EXAMINE_SEARCH_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if max(abs(dx), abs(dy)) != r:
					continue
				var c := want + Vector2i(dx, dy)
				if c.x < 0 or c.y < 0:
					continue
				if c in taken:
					continue
				if _is_cell_walkable(c):
					return c
	return Vector2i(-1, -1)


## Place this village's authored examines. A missing entry, an empty text or a cell with nowhere to
## go is SKIPPED WITH A WARNING rather than placed — a readable with no text advertises a read it
## cannot give, which is the mute-interactable class.
func _place_authored_examines() -> void:
	var authored: Dictionary = _load_examine_pack()
	if authored.is_empty():
		return
	var spawn: Vector2 = spawn_points.get("default", Vector2.ZERO)
	var spawn_cell := Vector2i(spawn / float(TILE_SIZE))
	var taken: Array = _occupied_interact_cells()
	for examine_id in authored.keys():
		var entry: Dictionary = authored[examine_id]
		var text: String = str(entry.get("text", ""))
		if text == "":
			push_warning("[%s] examine '%s' is authored with no text" % [_get_area_id(), examine_id])
			continue
		if not _EXAMINE_OFFSETS.has(examine_id):
			push_warning("[%s] examine '%s' has no offset, so it has no cell" % [_get_area_id(), examine_id])
			continue
		var cell := _resolve_examine_cell(spawn_cell + _examine_offset_for(str(examine_id)), taken)
		if cell.x < 0:
			push_warning("[%s] examine '%s' found no walkable free cell near %s" % [
				_get_area_id(), examine_id, str(spawn_cell + _examine_offset_for(str(examine_id)))])
			continue
		taken.append(cell)
		var prop := ReadableProp.new()
		prop.name = "Examine_" + str(examine_id)
		prop.position = _examine_px(cell)
		prop.setup(str(entry.get("name", "Examine")), func(): return [text])
		npcs.add_child(prop)
