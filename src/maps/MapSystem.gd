extends Node

## MapSystem - Manages all maps and locations in the game world
## Handles transitions between overworld, villages, and dungeons

signal map_loaded(map_id: String)
signal map_unloaded(map_id: String)
signal location_entered(location_id: String, location_type: String)
signal location_exited(location_id: String)

## Map types
enum MapType {
	OVERWORLD,    # Main world map
	VILLAGE,      # Safe towns with NPCs, shops
	DUNGEON,      # Dangerous areas with encounters
	INTERIOR,     # Building interiors (shops, houses)
	SPECIAL       # Unique locations
}

## Current state
var current_map: Node2D = null
var current_map_id: String = ""
var current_location_id: String = ""

## Loaded maps cache
var loaded_maps: Dictionary = {}  # {map_id: map_node}

## Location data (villages, dungeons, etc.)
var locations: Dictionary = {}  # {location_id: LocationData}

## Player reference
var player: Node2D = null


func _ready() -> void:
	_load_location_data()


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
	"""Transition to a different map with fade effect"""
	# TODO: Add fade transition
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


## Location management
func register_location(location_id: String, data: Dictionary) -> void:
	"""Register a location (village, dungeon, etc.)"""
	locations[location_id] = data
	print("Location registered: %s (%s)" % [location_id, data.get("name", "Unknown")])


func get_location(location_id: String) -> Dictionary:
	"""Get location data"""
	return locations.get(location_id, {})


func enter_location(location_id: String) -> void:
	"""Enter a location (triggers events, music, etc.)"""
	var location = get_location(location_id)
	if location.is_empty():
		print("Warning: Unknown location: %s" % location_id)
		return

	current_location_id = location_id
	var location_type = location.get("type", "unknown")

	# Trigger location-specific effects
	match location_type:
		"village":
			_on_enter_village(location)
		"dungeon":
			_on_enter_dungeon(location)

	location_entered.emit(location_id, location_type)
	print("Entered location: %s" % location.get("name", location_id))


func exit_location() -> void:
	"""Exit current location"""
	if current_location_id.is_empty():
		return

	location_exited.emit(current_location_id)
	current_location_id = ""


func _on_enter_village(location: Dictionary) -> void:
	"""Handle entering a village"""
	# Villages are safe zones - no random encounters
	EncounterSystem.set_encounters_enabled(false)

	# Play village music
	# TODO: Implement music system
	pass


func _on_enter_dungeon(location: Dictionary) -> void:
	"""Handle entering a dungeon"""
	# Dungeons have encounters
	EncounterSystem.set_encounters_enabled(true)

	# Set encounter rate from dungeon data
	var encounter_rate = location.get("encounter_rate", 0.05)
	EncounterSystem.set_encounter_rate(encounter_rate)

	# Play dungeon music
	# TODO: Implement music system
	pass


## Player management
func set_player(player_node: Node2D) -> void:
	"""Set the player node"""
	player = player_node


func get_player() -> Node2D:
	"""Get the player node"""
	return player


## Location data loading
func _load_location_data() -> void:
	"""Load location data from file or create defaults"""
	var data_path = "res://data/locations.json"

	if FileAccess.file_exists(data_path):
		var file = FileAccess.open(data_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()

			var json = JSON.new()
			if json.parse(json_string) == OK:
				locations = json.data
				print("Loaded %d locations" % locations.size())
				return

	# Create default locations
	_create_default_locations()


func _create_default_locations() -> void:
	"""Create default location data"""
	locations = {
		"starter_village": {
			"id": "starter_village",
			"name": "Harmonia Village",
			"type": "village",
			"description": "A peaceful starting village",
			"map_id": "village_starter",
			"has_shop": true,
			"has_inn": true,
			"has_save_point": true
		},

		"cave_dungeon": {
			"id": "cave_dungeon",
			"name": "Whispering Cave",
			"type": "dungeon",
			"description": "A dark cave filled with monsters",
			"map_id": "dungeon_cave",
			"encounter_rate": 0.05,  # 5% chance per step
			"enemy_types": ["slime", "bat", "goblin"],
			"boss": "cave_guardian",
			"recommended_level": 3
		},

		"forest_dungeon": {
			"id": "forest_dungeon",
			"name": "Corrupted Forest",
			"type": "dungeon",
			"description": "A forest twisted by meta-corruption",
			"map_id": "dungeon_forest",
			"encounter_rate": 0.07,
			"enemy_types": ["wolf", "corrupted_sprite"],
			"corruption_level": 1.0,
			"recommended_level": 5
		}
	}

	print("Created %d default locations" % locations.size())


## Utility
func get_current_map_type() -> MapType:
	"""Get the type of the current map"""
	if current_location_id.is_empty():
		return MapType.OVERWORLD

	var location = get_location(current_location_id)
	var type_str = location.get("type", "overworld")

	match type_str:
		"village":
			return MapType.VILLAGE
		"dungeon":
			return MapType.DUNGEON
		"interior":
			return MapType.INTERIOR
		"special":
			return MapType.SPECIAL
		_:
			return MapType.OVERWORLD


func is_in_safe_zone() -> bool:
	"""Check if player is in a safe zone (no encounters)"""
	return get_current_map_type() in [MapType.VILLAGE, MapType.INTERIOR]
