extends Node

## MapSystem — tracks the currently loaded map scene and provides
## transition helpers. Per-location metadata (villages, dungeons) is
## now managed by the individual scene scripts (BaseVillage, DragonCave,
## WhisperingCave, etc.), so MapSystem is intentionally narrow.

signal map_loaded(map_id: String)
signal map_unloaded(map_id: String)

## Map types — kept for save-format compatibility and potential future use.
enum MapType {
	OVERWORLD,    # Main world map
	VILLAGE,      # Safe towns with NPCs, shops
	DUNGEON,      # Dangerous areas with encounters
}

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
			print("Error: Map not found: %s" % map_path)
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
	"""Get resource path for a map"""
	match map_id:
		"overworld":
			return "res://src/exploration/OverworldScene.tscn"
		"harmonia_village":
			return "res://src/maps/villages/HarmoniaVillage.tscn"
		"whispering_cave":
			return "res://src/maps/dungeons/WhisperingCave.tscn"
		"village_starter":
			return "res://src/maps/villages/StarterVillage.tscn"
		"dungeon_cave":
			return "res://src/maps/dungeons/Cave.tscn"
		# New villages
		"frosthold_village":
			return "res://src/maps/villages/FrostholdVillage.gd"
		"eldertree_village":
			return "res://src/maps/villages/EldertreeVillage.gd"
		"grimhollow_village":
			return "res://src/maps/villages/GrimhollowVillage.gd"
		"sandrift_village":
			return "res://src/maps/villages/SandriftVillage.gd"
		"ironhaven_village":
			return "res://src/maps/villages/IronhavenVillage.gd"
		# Dragon caves
		"ice_dragon_cave":
			return "res://src/maps/dungeons/IceDragonCave.gd"
		"shadow_dragon_cave":
			return "res://src/maps/dungeons/ShadowDragonCave.gd"
		"lightning_dragon_cave":
			return "res://src/maps/dungeons/LightningDragonCave.gd"
		"fire_dragon_cave":
			return "res://src/maps/dungeons/FireDragonCave.gd"
		# Steampunk overworld
		"steampunk_overworld":
			return "res://src/exploration/SteampunkOverworld.gd"
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
		print("Warning: Spawn point not found: %s" % spawn_point)


## Player management
func set_player(player_node: Node2D) -> void:
	"""Set the player node"""
	player = player_node


func get_player() -> Node2D:
	"""Get the player node"""
	return player


