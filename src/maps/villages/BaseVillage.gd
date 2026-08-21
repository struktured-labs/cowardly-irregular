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

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Tile size (consistent across all villages)
const TILE_SIZE: int = 32
const FRINGE_GRASS_TYPES := [TileGeneratorScript.TileType.VILLAGE_GRASS, TileGeneratorScript.TileType.GRASS]

## Scene components
var tile_map: TileMapLayer
var cliff_map: TileMapLayer
var overlay_map: TileMapLayer
var player: Node2D
var camera: Camera2D
var controller: Node
var tile_generator: Node

## Containers
var transitions: Node2D
var npcs: Node2D
var buildings: Node2D
var treasures: Node2D

## Spawn points (populated by subclass _generate_map)
var spawn_points: Dictionary = {}

## Elevation state, filled by _build_derived_layers (empty = flat village, today's behaviour)
var _height_grid: Array = []
var _stair_cells: Dictionary = {}
var _face_cells: Dictionary = {}
var _prop_blocked: Dictionary = {}


func _ready() -> void:
	# Villages are never Mode 7 — clear the static so the overworld boost cannot leak in.
	Mode7Overlay.is_active = false
	Mode7Overlay.camera_angle = 0.0  # Defense-in-depth: OverworldPlayer reads this UNCONDITIONALLY, so a leaked non-zero angle would rotate village movement.
	_setup_scene()
	_generate_map()
	_setup_transitions()
	_setup_buildings()
	_setup_treasures()
	_setup_npcs()
	_validate_placements()
	_setup_player()
	_setup_camera()
	_setup_controller()
	_setup_save_point()

	if SoundManager:
		SoundManager.play_area_music(_get_music_area_id())

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


func _cell_salt(cell: Vector2i) -> int:
	return cell.x * 73856093 ^ cell.y * 19349663


## Atlas coords for a tile type at a cell, variant chosen per cell (5-column TileGenerator atlas).
func _atlas_for(tile_type: int, cell: Vector2i) -> Vector2i:
	return TileGeneratorScript.get_atlas_coords_for_id(TileGeneratorScript.get_tile_id_variant(tile_type, _cell_salt(cell)))


func _ground_type(cell: Vector2i) -> int:
	if tile_map == null or tile_map.get_cell_source_id(cell) == -1:
		return -1
	var ac := tile_map.get_cell_atlas_coords(cell)
	var order: Array = tile_generator._get_tile_order()
	var id: int = ac.y * tile_generator._get_atlas_dimensions().x + ac.x
	return int(order[id]) if id >= 0 and id < order.size() else -1


## Derive cliffs/stairs from the height grid and paint them; call at the end of _generate_map. Empty height rows = flat village, nothing painted.
func _build_derived_layers(map_rows: Array, height_rows: Array) -> void:
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
		cliff_map.set_cell(c, 0, EnvTileSetsScript.atlas_coords(int(pieces["edges"][c])))
	_paint_fringe()


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


func _validate_placements() -> void:
	if npcs == null:
		return
	for n in npcs.get_children():
		if not (n is Node2D):
			continue
		if n.has_method("set_patrol"):
			_validate_patrol(n)
		else:
			var fixed := _find_walkable_near(n.position)
			if fixed != n.position:
				push_warning("[%s] relocated '%s' off impassable tile %s -> %s" % [_get_area_id(), n.name, n.position, fixed])
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
		w.set_patrol(pts)


func _setup_npcs() -> void:
	pass


## ---- Shared scene/node setup ----

func _setup_scene() -> void:
	tile_generator = TileGeneratorScript.new()
	add_child(tile_generator)

	tile_map = TileMapLayer.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = tile_generator.create_tileset()
	add_child(tile_map)

	cliff_map = TileMapLayer.new()
	cliff_map.name = "Cliffs"
	cliff_map.tile_set = EnvTileSetsScript.build_cliff_tileset(_get_cliff_palette())
	add_child(cliff_map)

	overlay_map = TileMapLayer.new()
	overlay_map.name = "Overlay"
	overlay_map.tile_set = EnvTileSetsScript.build_overlay_tileset(_get_cliff_palette())
	add_child(overlay_map)

	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)

	buildings = Node2D.new()
	buildings.name = "Buildings"
	add_child(buildings)

	treasures = Node2D.new()
	treasures.name = "Treasures"
	add_child(treasures)

	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)


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
func _add_quest_examine_point(qid: String, flag: String, indicator: String, examined: String,
		idle: String, pos: Vector2) -> void:
	var ExamineScript = load("res://src/exploration/QuestExaminePoint.gd")
	if ExamineScript == null:
		return
	var point = ExamineScript.new()
	point.quest_id = qid
	point.flag = flag
	point.indicator_text = indicator
	point.examine_text = examined
	point.idle_text = idle
	point.position = pos
	npcs.add_child(point)


## One stop on a multi-point objective — `flag` fires only once ALL group_size members are examined.
func _add_quest_route_point(qid: String, flag: String, index: int, group_size: int,
		indicator: String, examined: String, idle: String, pos: Vector2) -> void:
	var ExamineScript = load("res://src/exploration/QuestExaminePoint.gd")
	if ExamineScript == null:
		return
	var point = ExamineScript.new()
	point.quest_id = qid
	point.flag = flag
	point.member_index = index
	point.group_size = group_size
	point.indicator_text = indicator
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
