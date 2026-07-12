extends Node2D
class_name BaseInterior

## BaseInterior — shared scaffold for village interior scenes.
##
## Mirrors BaseVillage's role for villages: provides standard tilemap
## setup, player + camera + controller wiring, spawn-point helpers,
## pause/resume — so a concrete interior becomes "the data and the
## payload NPCs" rather than "200 lines of GDScript boilerplate".
##
## Concrete subclasses override the virtual hooks below. The hooks are
## intentionally minimal — overriding _setup_decorations / _setup_npcs /
## _setup_transitions is enough for most interiors. Tavern's dancer +
## piano kept their bespoke logic because they're far enough from the
## generic case that abstraction would obscure them.

signal transition_triggered(target_map: String, target_spawn: String)
signal area_transition(target_map: String, target_spawn: String)
signal battle_triggered(enemies: Array)

const TILE_SIZE: int = 32

var tilemap: TileMapLayer
var player: Node2D
var camera: Camera2D
var npcs: Node2D
var transitions: Node2D
var decorations: Node2D
var controller: Node

var spawn_points: Dictionary = {}


func _ready() -> void:
	# Interiors are never Mode 7 — clear the static so the overworld boost cannot leak in.
	Mode7Overlay.is_active = false
	Mode7Overlay.camera_angle = 0.0  # Defense-in-depth: OverworldPlayer reads this UNCONDITIONALLY, so a leaked non-zero angle would rotate interior movement.
	_init_spawn_points()
	_setup_tilemap()
	_setup_decorations()
	_setup_npcs()
	_setup_transitions()
	_setup_player()
	_setup_camera()
	_setup_controller()
	var music_track := _get_music_track()
	if music_track != "" and SoundManager:
		SoundManager.play_area_music(music_track)
	var ambient_key := _get_ambient_key()
	if ambient_key != "" and SoundManager and SoundManager.has_method("play_ambient"):
		SoundManager.play_ambient(ambient_key)


func _exit_tree() -> void:
	# Stop the room loop so it doesn't leak into the next scene.
	if _get_ambient_key() != "" and SoundManager and SoundManager.has_method("stop_ambient"):
		SoundManager.stop_ambient()


## Virtual: subclass returns an sfx_manifest ambient-loop key (e.g.
## "ambient_chapel"); "" = no room ambience.
func _get_ambient_key() -> String:
	return ""


## Virtual: subclass returns the map_id for this interior (e.g.
## "harmonia_chapel"). Used by controller.set_area_config and any
## save/load hook that wants to identify the room.
func _get_area_id() -> String:
	return "interior"


## Virtual: subclass returns the human label (e.g. "Chapel"). Surfaced
## in debug overlays + future signage; safe to leave default.
func _get_display_name() -> String:
	return "Interior"


## Virtual: subclass returns the map width (tiles).
func _get_map_width() -> int:
	return 14


## Virtual: subclass returns the map height (tiles).
func _get_map_height() -> int:
	return 10


## Virtual: subclass returns the layout strings array — one string per
## row, each row exactly _get_map_width() chars long. 'W' = wall, any
## other char = floor. Default is an empty 14x10 room.
func _get_layout() -> Array:
	var w := _get_map_width()
	var h := _get_map_height()
	var rows: Array = []
	for y in range(h):
		var s := ""
		for x in range(w):
			if y == 0 or y == h - 1 or x == 0 or x == w - 1:
				s += "W"
			else:
				s += "."
		rows.append(s)
	return rows


## Virtual: subclass populates spawn_points (entrance + any internal
## landmarks). Called before everything else so transitions / NPCs can
## reference spawn positions.
func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(_get_map_width() / 2, _get_map_height() - 2)


## Virtual: subclass returns a SoundManager music key (e.g. "village",
## "cave"). Empty string = no music change.
func _get_music_track() -> String:
	return "village"


## Virtual: subclass draws its floor tile palette. Default = plain
## stone gray.
func _draw_floor_tile(image: Image) -> void:
	var stone = Color(0.55, 0.55, 0.58)
	var stone_dark = Color(0.42, 0.42, 0.46)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam = (x % 8 == 0) or (y % 8 == 0)
			image.set_pixel(x, y, stone_dark if seam else stone)


## Virtual: subclass draws its wall tile palette. Default = plain
## stone brick.
func _draw_wall_tile(image: Image) -> void:
	var stone = Color(0.38, 0.36, 0.42)
	var stone_light = Color(0.50, 0.48, 0.54)
	var mortar = Color(0.62, 0.60, 0.55)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var row = y / 10
			var offset = 10 if row % 2 == 0 else 0
			var in_mortar_h = y % 10 == 0
			var in_mortar_v = (x + offset) % 20 == 0
			if in_mortar_h or in_mortar_v:
				image.set_pixel(x, y, mortar)
			else:
				image.set_pixel(x, y, stone_light if (x + y) % 11 == 0 else stone)


## Virtual: subclass instantiates decorations (altar, pews, shelves).
## Default = nothing.
func _setup_decorations() -> void:
	decorations = Node2D.new()
	decorations.name = "Decorations"
	add_child(decorations)


## Virtual: subclass instantiates NPCs. Default = nothing.
func _setup_npcs() -> void:
	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)


## Virtual: subclass adds AreaTransition nodes. Default = nothing.
## Most interiors override this to add the exit door.
func _setup_transitions() -> void:
	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)


## Standard tilemap setup — uses the virtual draw + layout hooks.
func _setup_tilemap() -> void:
	tilemap = TileMapLayer.new()
	tilemap.name = "TileMapLayer"
	add_child(tilemap)

	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var floor_source = TileSetAtlasSource.new()
	var floor_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_floor_tile(floor_img)
	floor_source.texture = ImageTexture.create_from_image(floor_img)
	floor_source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	floor_source.create_tile(Vector2i(0, 0))
	tileset.add_source(floor_source, 0)

	var wall_source = TileSetAtlasSource.new()
	var wall_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_wall_tile(wall_img)
	wall_source.texture = ImageTexture.create_from_image(wall_img)
	wall_source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	wall_source.create_tile(Vector2i(0, 0))
	tileset.add_source(wall_source, 1)

	tilemap.tile_set = tileset

	var layout: Array = _get_layout()
	var w := _get_map_width()
	var h := _get_map_height()
	for y in range(h):
		var row: String = str(layout[y]) if y < layout.size() else ""
		for x in range(w):
			var ch: String = row[x] if x < row.length() else "W"
			if ch == "W":
				tilemap.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))
			else:
				tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))


## Standard player setup. Interior = slower movement speed (matches
## TavernInterior + BaseVillage:202).
func _setup_player() -> void:
	var PlayerScript = load("res://src/exploration/OverworldPlayer.gd")
	if not PlayerScript:
		return
	player = PlayerScript.new()
	var entrance: Vector2 = spawn_points.get("entrance", Vector2(_get_map_width() / 2, _get_map_height() - 2))
	player.position = entrance * TILE_SIZE
	player._is_interior = true
	add_child(player)


## Standard camera setup — interior zoom + clamped to room bounds.
func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2(2.5, 2.5)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = _get_map_width() * TILE_SIZE
	camera.limit_bottom = _get_map_height() * TILE_SIZE
	if player:
		player.add_child(camera)
	else:
		add_child(camera)
		camera.position = Vector2(_get_map_width() * TILE_SIZE / 2, _get_map_height() * TILE_SIZE / 2)


## Standard controller setup. set_area_config marks the interior as
## safe (no random encounters) since interiors aren't currently a
## battleable area.
func _setup_controller() -> void:
	var ControllerScript = load("res://src/exploration/OverworldController.gd")
	if not (ControllerScript and player):
		return
	controller = ControllerScript.new()
	controller.name = "OverworldController"
	add_child(controller)
	if controller.has_method("set_player"):
		controller.set_player(player)
	if controller.has_method("set_area_config"):
		controller.set_area_config(_get_area_id(), true, 0.0, [])


## Shared helper for transition_triggered → both signals. Subclasses
## connect their AreaTransition's transition_triggered to this.
func _on_exit_triggered(target_map: String, target_spawn: String) -> void:
	transition_triggered.emit(target_map, target_spawn)
	area_transition.emit(target_map, target_spawn)


func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name) and player:
		player.position = spawn_points[spawn_name] * TILE_SIZE


## OverworldMenu (GameLoop._open_overworld_menu) calls these to
## suspend / resume player movement + transitions while a submenu is
## open. Without them, opening Equipment from an interior could leak
## the exit-door transition while the equipment UI is up.
func pause() -> void:
	if controller and controller.has_method("pause_exploration"):
		controller.pause_exploration()


func resume() -> void:
	if controller and controller.has_method("resume_exploration"):
		controller.resume_exploration()
