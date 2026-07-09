extends Node

## MapSystem — tracks the currently loaded map scene and provides
## transition helpers. Per-location metadata (villages, dungeons) is
## now managed by the individual scene scripts (BaseVillage, DragonCave,
## WhisperingCave, etc.), so MapSystem is intentionally narrow.

signal map_loaded(map_id: String)
signal map_unloaded(map_id: String)

## Map types — kept for save-format compatibility; DUNGEON is live via is_dungeon_map.
enum MapType {
	OVERWORLD,    # Main world map
	VILLAGE,      # Safe towns with NPCs, shops
	DUNGEON,      # Dangerous areas with encounters
}

## Every dungeon map id — the save_point_only gate (F3) keys off this list; completeness guarded by test_save_point_only_enforcement_regression.
const DUNGEON_MAP_IDS: PackedStringArray = [
	"whispering_cave", "fire_dragon_cave", "ice_dragon_cave",
	"lightning_dragon_cave", "shadow_dragon_cave", "castle_harmonia",
	"null_chamber", "root_process", "assembly_core",
	"steampunk_mechanism", "suburban_underground",
]


## True when map_id is a dungeon (GameLoop.get_current_map_id() is the runtime authority).
static func is_dungeon_map(map_id: String) -> bool:
	return map_id in DUNGEON_MAP_IDS

## Current state
var current_map: Node2D = null
var current_map_id: String = ""

## Loaded maps cache
var loaded_maps: Dictionary = {}  # {map_id: map_node}

## Player reference
var player: Node2D = null


## Map management
func load_map(map_id: String, spawn_point: String = "default") -> void:
	"""Load and display a map"""
	# Unload current map
	if current_map:
		unload_current_map()

	# Check cache first
	if loaded_maps.has(map_id):
		current_map = loaded_maps[map_id]
	else:
		# Load map scene
		var map_path = _get_map_path(map_id)
		if not ResourceLoader.exists(map_path):
			## Tick 182: surface missing-map failures. Pre-fix print()
			## only — load_map silently returned with current_map
			## unchanged. Callers couldn't tell whether the load
			## succeeded or whether they were still on the old map.
			## push_error matches the severity of the existing
			## load-scene-fail path at the next branch.
			push_error("[MapSystem] load_map: map not found at '%s' — load silently aborted, current_map unchanged" % map_path)
			return

		var map_scene = load(map_path)
		if not map_scene:
			push_error("MapSystem: Failed to load map scene at %s" % map_path)
			return
		current_map = map_scene.instantiate()
		loaded_maps[map_id] = current_map

	# Add to scene tree
	get_tree().root.add_child(current_map)
	current_map_id = map_id

	# Position player at spawn point
	if player:
		_position_player_at_spawn(spawn_point)

	map_loaded.emit(map_id)
	print("Map loaded: %s" % map_id)


func unload_current_map() -> void:
	"""Unload the current map"""
	if not current_map:
		return

	map_unloaded.emit(current_map_id)
	current_map.queue_free()
	current_map = null
	current_map_id = ""


func transition_to_map(map_id: String, spawn_point: String = "default") -> void:
	"""Transition to a different map. SceneTransition handles the fade —
	this just waits a frame to let it start before swapping the scene."""
	await get_tree().create_timer(0.1).timeout
	load_map(map_id, spawn_point)


func _get_map_path(map_id: String) -> String:
	"""Get resource path for a map.

	Only PackedScene (.tscn) paths are returned: load_map uses
	`scene.instantiate()` (PackedScene), not `Script.new()`, so
	pointing at a .gd file silently produces a broken instance.

	Most maps are loaded directly by GameLoop via preloaded Script
	constants + .new() (the dragon caves, the .gd-only villages, the
	Steampunk overworld). Those are NOT in this table — MapSystem's
	routing is reserved for the handful of maps that genuinely have
	a .tscn entry point and round-trip through save_data's
	current_map_id field.

	Prior to this trim, the table contained 10 entries pointing at
	.gd scripts (would have silently failed if any caller routed
	through MapSystem) plus 2 entries pointing at .tscn files that
	no longer exist (StarterVillage, Cave). All 12 were unreachable
	dead code — confirmed via grep of `MapSystem.load_map(\"...\")`
	and `MapSystem.transition_to_map(\"...\")` callers — but a
	future caller hitting any of them would have crashed silently.
	The fallback wildcard at the bottom is kept as a sane default
	but will return a path that doesn't match the real
	villages/dungeons subdir layout — callers should add explicit
	entries here when they wire MapSystem-driven loads."""
	match map_id:
		"overworld":
			return "res://src/exploration/OverworldScene.tscn"
		"harmonia_village":
			return "res://src/maps/villages/HarmoniaVillage.tscn"
		"whispering_cave":
			return "res://src/maps/dungeons/WhisperingCave.tscn"
		_:
			return "res://src/maps/%s.tscn" % map_id


func _position_player_at_spawn(spawn_point: String) -> void:
	"""Position player at spawn point marker"""
	if not current_map or not player:
		return

	# Look for spawn point marker in map
	var spawn_marker = current_map.find_child(spawn_point, true, false)
	if spawn_marker and spawn_marker is Marker2D:
		player.global_position = spawn_marker.global_position
	else:
		## Tick 182: surface missing spawn point. Pre-fix print()
		## only — player would silently spawn at the default
		## position (often 0,0 or wherever they were last) instead
		## of at the requested spawn marker. Symptom looked like
		## "the transition didn't work" with no diagnostic surface.
		push_warning("[MapSystem] _position_player_at_spawn: spawn point '%s' not found in current_map — player will remain at last position" % spawn_point)


## Player management
func set_player(player_node: Node2D) -> void:
	"""Set the player node"""
	player = player_node


func get_player() -> Node2D:
	"""Get the player node"""
	return player


