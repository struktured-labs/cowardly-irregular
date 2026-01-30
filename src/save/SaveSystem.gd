extends Node

## SaveSystem - Manages game saves with quick save and save points
## Supports saving anywhere on overworld, at save points in dungeons/villages

signal save_started()
signal save_completed(save_slot: int)
signal save_failed(reason: String)
signal load_started()
signal load_completed(save_slot: int)
signal load_failed(reason: String)

## Save configuration
const SAVE_DIR = "user://saves/"
const MAX_SAVE_SLOTS = 3
const QUICK_SAVE_SLOT = 99  # Special slot for quick save

## Save data
var current_save_slot: int = -1
var auto_save_enabled: bool = true
var auto_save_interval: float = 300.0  # 5 minutes

## Auto-save timer
var time_since_last_auto_save: float = 0.0


func _ready() -> void:
	# Create save directory if it doesn't exist
	_ensure_save_directory()


func _process(delta: float) -> void:
	# Auto-save timer
	if auto_save_enabled:
		time_since_last_auto_save += delta
		if time_since_last_auto_save >= auto_save_interval:
			auto_save()
			time_since_last_auto_save = 0.0


## Save functions
func save_game(slot: int = -1) -> bool:
	"""Save the current game state to a slot"""
	if slot == -1:
		slot = current_save_slot

	if slot < 0:
		save_failed.emit("No save slot selected")
		return false

	save_started.emit()

	# Gather save data
	var save_data = _create_save_data()

	# Add metadata
	save_data["metadata"] = {
		"save_slot": slot,
		"save_time": Time.get_unix_time_from_system(),
		"save_date": Time.get_datetime_string_from_system(),
		"play_time": GameState.get_play_time() if GameState else 0.0,
		"play_time_formatted": GameState.get_playtime_formatted() if GameState else "00:00:00",
		"game_version": "0.1.0",
		"chapter": GameState.current_chapter if GameState and "current_chapter" in GameState else 1,
		"location_name": MapSystem.get_current_location_name() if MapSystem and MapSystem.has_method("get_current_location_name") else "Unknown",
		"party_summary": _get_party_summary()
	}

	# Write to file
	var success = _write_save_file(slot, save_data)

	if success:
		current_save_slot = slot
		save_completed.emit(slot)
		print("Game saved to slot %d" % slot)
		return true
	else:
		save_failed.emit("Failed to write save file")
		return false


func quick_save() -> bool:
	"""Quick save to dedicated slot"""
	# Check if quick save is allowed in current location
	if not can_quick_save():
		save_failed.emit("Cannot quick save here")
		print("Quick save not allowed in current location")
		return false

	print("Quick saving...")
	return save_game(QUICK_SAVE_SLOT)


func auto_save() -> bool:
	"""Auto-save (uses slot 0 by default)"""
	if not can_quick_save():
		return false

	print("Auto-saving...")
	return save_game(0)


func can_quick_save() -> bool:
	"""Check if quick save is allowed in current location"""
	var map_type = MapSystem.get_current_map_type()

	# Can quick save on overworld and in villages
	if map_type in [MapSystem.MapType.OVERWORLD, MapSystem.MapType.VILLAGE]:
		return true

	# Cannot quick save in dungeons (must use save points)
	if map_type == MapSystem.MapType.DUNGEON:
		return false

	# Cannot save during battle
	if BattleManager.is_battle_active():
		return false

	return true


func save_at_save_point(save_point_id: String) -> bool:
	"""Save at a designated save point (works anywhere)"""
	print("Saving at save point: %s" % save_point_id)

	# Save points work even in dungeons
	return save_game(current_save_slot if current_save_slot >= 0 else 1)


## Load functions
func load_game(slot: int) -> bool:
	"""Load a saved game"""
	if not save_exists(slot):
		load_failed.emit("Save file not found")
		return false

	load_started.emit()

	var save_data = _read_save_file(slot)
	if save_data.is_empty():
		load_failed.emit("Failed to read save file")
		return false

	# Apply save data
	_apply_save_data(save_data)

	current_save_slot = slot
	load_completed.emit(slot)
	print("Game loaded from slot %d" % slot)
	return true


func save_exists(slot: int) -> bool:
	"""Check if a save file exists"""
	var file_path = _get_save_path(slot)
	return FileAccess.file_exists(file_path)


func get_save_info(slot: int) -> Dictionary:
	"""Get save file metadata without loading the full save"""
	if not save_exists(slot):
		return {}

	var save_data = _read_save_file(slot)
	return save_data.get("metadata", {})


func delete_save(slot: int) -> bool:
	"""Delete a save file"""
	if not save_exists(slot):
		return false

	var file_path = _get_save_path(slot)
	var dir = DirAccess.open("user://")
	if dir:
		dir.remove(file_path)
		print("Deleted save slot %d" % slot)
		return true

	return false


## Save data creation
func _create_save_data() -> Dictionary:
	"""Create a dictionary of all save data"""
	var data = {}

	# Player data
	var player = MapSystem.get_player()
	if player and player is PlayerController:
		data["player"] = {
			"position": {
				"x": player.position.x,
				"y": player.position.y
			},
			"step_count": player.step_count
		}

	# Party data (combatants)
	data["party"] = _serialize_party()

	# Map/location data
	data["map"] = {
		"current_map_id": MapSystem.current_map_id,
		"current_location_id": MapSystem.current_location_id
	}

	# Inventory (party-wide items)
	data["inventory"] = _serialize_inventory()

	# Game state flags/variables
	if GameState:
		data["game_state"] = GameState.to_dict()

	# Autogrind/autobattle stats
	data["automation"] = {
		"region_crack_levels": AutogrindSystem.region_crack_levels if AutogrindSystem else {},
		"total_battles": BattleManager.total_battles_won if BattleManager and "total_battles_won" in BattleManager else 0
	}

	return data


func _serialize_party() -> Array:
	"""Serialize party members"""
	var party_data = []

	# For now, using test player from battle scene
	# In full game, would get from GameState party roster
	# This is a placeholder

	return party_data


func _get_party_summary() -> Array:
	"""Get summary of party members for save slot display"""
	var summary = []

	# Get party from GameState if available
	if GameState and "party" in GameState:
		for member in GameState.party:
			if member is Combatant:
				summary.append({
					"name": member.combatant_name,
					"level": member.level if "level" in member else 1,
					"job": member.job.get("name", "Fighter") if member.job else "Fighter",
					"job_id": member.job.get("id", "fighter") if member.job else "fighter",
					"hp": member.current_hp,
					"max_hp": member.max_hp,
					"customization": member.customization.to_dict() if member.customization and member.customization.has_method("to_dict") else null
				})

	return summary


func _serialize_inventory() -> Dictionary:
	"""Serialize inventory"""
	# In full game, would serialize party-wide inventory
	# For now, placeholder
	return {}


## Save data application
func _apply_save_data(data: Dictionary) -> void:
	"""Apply loaded save data to game state"""
	# Apply player position
	if data.has("player"):
		var player = MapSystem.get_player()
		if player and data["player"].has("position"):
			var pos = data["player"]["position"]
			player.teleport(Vector2(pos["x"], pos["y"]))

	# Apply map/location
	if data.has("map"):
		var map_data = data["map"]
		if map_data.has("current_map_id"):
			MapSystem.load_map(map_data["current_map_id"])

	# Apply party data
	if data.has("party"):
		_deserialize_party(data["party"])

	# Apply inventory
	if data.has("inventory"):
		_deserialize_inventory(data["inventory"])

	# Apply game state
	if data.has("game_state") and GameState:
		GameState.from_dict(data["game_state"])

	# Apply automation stats
	if data.has("automation"):
		# Restore region crack levels, etc.
		pass


func _deserialize_party(party_data: Array) -> void:
	"""Deserialize party members"""
	# Placeholder
	pass


func _deserialize_inventory(inventory_data: Dictionary) -> void:
	"""Deserialize inventory"""
	# Placeholder
	pass


## File I/O
func _write_save_file(slot: int, data: Dictionary) -> bool:
	"""Write save data to file"""
	var file_path = _get_save_path(slot)

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		print("Error: Could not open save file for writing: %s" % file_path)
		return false

	var json_string = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()

	return true


func _read_save_file(slot: int) -> Dictionary:
	"""Read save data from file"""
	var file_path = _get_save_path(slot)

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("Error: Could not open save file for reading: %s" % file_path)
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		print("Error: Failed to parse save file JSON")
		return {}

	return json.data


func _get_save_path(slot: int) -> String:
	"""Get file path for a save slot"""
	return SAVE_DIR + "save_%02d.json" % slot


func _ensure_save_directory() -> void:
	"""Create save directory if it doesn't exist"""
	var dir = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("saves"):
			dir.make_dir("saves")
			print("Created save directory: user://saves/")


## Utility
func get_all_saves() -> Array:
	"""Get info for all save slots"""
	var saves = []
	for slot in range(MAX_SAVE_SLOTS):
		var info = get_save_info(slot)
		if not info.is_empty():
			saves.append(info)
	return saves


func set_current_save_slot(slot: int) -> void:
	"""Set the active save slot"""
	current_save_slot = slot
