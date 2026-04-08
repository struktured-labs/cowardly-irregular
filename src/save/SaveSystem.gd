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

## One-shot tracking records
var one_shot_records: Dictionary = {}  # {monster_id: {count: int, best_rank: String, best_setup: int}}

## Autobattle victory tracking records
var autobattle_records: Dictionary = {}  # {monster_key: {count: int, best_turns: int, best_multiplier: float}}


func _ready() -> void:
	# Create save directory if it doesn't exist
	_ensure_save_directory()
	# Load persisted settings
	load_settings()


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
		save_settings()  # Persist settings alongside save
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
	if not BattleManager:
		return false
	if BattleManager.is_battle_active():
		return false

	return true


func save_at_save_point(save_point_id: String) -> bool:
	"""Save at a designated save point (works anywhere)"""
	print("Saving at save point: %s" % save_point_id)

	# Save points work even in dungeons
	var result = save_game(current_save_slot if current_save_slot >= 0 else 1)
	if result:
		SoundManager.play_music("stinger_save_point")
	return result


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


func has_save() -> bool:
	"""Check if any save file exists (for title screen Continue button)"""
	for slot in range(MAX_SAVE_SLOTS):
		if save_exists(slot):
			return true
	if save_exists(QUICK_SAVE_SLOT):
		return true
	return false


func get_most_recent_slot() -> int:
	"""Find the most recently saved slot. Returns -1 if no saves exist."""
	var best_slot = -1
	var best_time = 0.0
	for slot in range(MAX_SAVE_SLOTS):
		var info = get_save_info(slot)
		if not info.is_empty():
			var save_time = info.get("save_time", 0.0)
			if save_time > best_time:
				best_time = save_time
				best_slot = slot
	# Also check quick save
	var qs_info = get_save_info(QUICK_SAVE_SLOT)
	if not qs_info.is_empty():
		var qs_time = qs_info.get("save_time", 0.0)
		if qs_time > best_time:
			best_slot = QUICK_SAVE_SLOT
	return best_slot


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


## One-shot record management
func record_one_shot(monster_ids: Array, rank: String, setup_turns: int) -> void:
	"""Record a one-shot achievement for the given monster types"""
	for id in monster_ids:
		if not one_shot_records.has(id):
			one_shot_records[id] = {"count": 0, "best_rank": "C", "best_setup": 999}
		one_shot_records[id]["count"] += 1
		if _rank_value(rank) > _rank_value(one_shot_records[id]["best_rank"]):
			one_shot_records[id]["best_rank"] = rank
		if setup_turns < one_shot_records[id]["best_setup"]:
			one_shot_records[id]["best_setup"] = setup_turns
	print("[SAVE] One-shot recorded for monsters: %s (rank: %s, setup: %d)" % [monster_ids, rank, setup_turns])


func _rank_value(rank: String) -> int:
	"""Convert rank letter to numeric value for comparison"""
	match rank:
		"S":
			return 4
		"A":
			return 3
		"B":
			return 2
		"C":
			return 1
		_:
			return 0


func _get_one_shot_records() -> Dictionary:
	"""Get all one-shot records"""
	return one_shot_records


func get_one_shot_record(monster_id: String) -> Dictionary:
	"""Get one-shot record for a specific monster"""
	return one_shot_records.get(monster_id, {})


## Autobattle record management
func record_autobattle_victory(monster_ids: Array, turns: int, multiplier: float) -> void:
	"""Record an autobattle victory for the given monster types"""
	var monster_key = "_".join(monster_ids) if monster_ids.size() > 0 else "unknown"
	if not autobattle_records.has(monster_key):
		autobattle_records[monster_key] = {"count": 0, "best_turns": 999, "best_multiplier": 0.0}
	autobattle_records[monster_key]["count"] += 1
	if turns < autobattle_records[monster_key]["best_turns"]:
		autobattle_records[monster_key]["best_turns"] = turns
	if multiplier > autobattle_records[monster_key]["best_multiplier"]:
		autobattle_records[monster_key]["best_multiplier"] = multiplier
	print("[SAVE] Autobattle victory recorded for monsters: %s (turns: %d, multiplier: %.1fx)" % [monster_key, turns, multiplier])


func get_autobattle_record(monster_key: String) -> Dictionary:
	"""Get autobattle record for a specific monster combination"""
	return autobattle_records.get(monster_key, {})


func _get_autobattle_records() -> Dictionary:
	"""Get all autobattle records"""
	return autobattle_records


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
		"total_battles": BattleManager.total_battles_won if BattleManager and "total_battles_won" in BattleManager else 0,
		"learned_patterns": AutogrindSystem.learned_patterns if AutogrindSystem else {}
	}

	# One-shot records
	data["one_shot_records"] = _get_one_shot_records()

	# Autobattle records
	data["autobattle_records"] = _get_autobattle_records()

	return data


func _serialize_party() -> Array:
	"""Serialize party members"""
	if GameState and "player_party" in GameState:
		return GameState.player_party.duplicate(true)
	return []


func _get_party_summary() -> Array:
	"""Get summary of party members for save slot display"""
	var summary = []

	# Get party from GameState if available
	if GameState and "player_party" in GameState:
		for member in GameState.player_party:
			if member is Dictionary:
				summary.append({
					"name": member.get("name", "Unknown"),
					"level": member.get("job_level", 1),
					"job": member.get("job", {}).get("name", "Fighter") if member.get("job") is Dictionary else "Fighter",
					"job_id": member.get("job", {}).get("id", "fighter") if member.get("job") is Dictionary else "fighter",
					"secondary_job_id": member.get("secondary_job_id", ""),
					"hp": member.get("current_hp", 0),
					"max_hp": member.get("max_hp", 1),
					"customization": member.get("customization", null)
				})

	return summary


func _serialize_inventory() -> Dictionary:
	"""Serialize inventory"""
	# TODO: serialize party-wide item inventory when InventorySystem is implemented
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
		var automation_data = data["automation"]
		# Restore region crack levels
		if automation_data.has("region_crack_levels") and AutogrindSystem:
			AutogrindSystem.region_crack_levels = automation_data["region_crack_levels"]
		# Restore learned patterns for adaptive AI
		if automation_data.has("learned_patterns") and AutogrindSystem:
			AutogrindSystem.learned_patterns = automation_data["learned_patterns"]

	# Restore one-shot records
	if data.has("one_shot_records"):
		one_shot_records = data["one_shot_records"]

	# Restore autobattle records
	if data.has("autobattle_records"):
		autobattle_records = data["autobattle_records"]


func _deserialize_party(party_data: Array) -> void:
	"""Deserialize party members"""
	if GameState and "player_party" in GameState:
		GameState.player_party = party_data.duplicate(true)


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
		print("Error: Failed to parse save file JSON: %s" % json.get_error_message())
		return {}

	# Validate that parsed data is a Dictionary
	if not json.data is Dictionary:
		print("Error: Save file data is not a valid dictionary")
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


## ═══════════════════════════════════════════════════════════════════════
## SETTINGS PERSISTENCE (global, not per-slot)
## ═══════════════════════════════════════════════════════════════════════

const SETTINGS_PATH = "user://settings.json"


func save_settings() -> void:
	"""Save global game settings (battle speed, audio, display options)."""
	var BattleSceneScript = load("res://src/battle/BattleScene.gd")
	var settings = {
		"version": 1,
		"battle_speed_index": BattleSceneScript._battle_speed_index if BattleSceneScript else 1,
		"show_controller_overlay": GameState.show_controller_overlay if GameState else true,
		"master_volume": AudioServer.get_bus_volume_db(0),
	}
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()


func load_settings() -> void:
	"""Load and apply global game settings."""
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		file.close()
		return
	file.close()

	var settings = json.data
	# Battle speed
	var BattleSceneScript = load("res://src/battle/BattleScene.gd")
	if BattleSceneScript and settings.has("battle_speed_index"):
		var idx = int(settings["battle_speed_index"])
		if idx >= 0 and idx < BattleSceneScript.BATTLE_SPEEDS.size():
			BattleSceneScript._battle_speed_index = idx

	# Controller overlay
	if GameState and settings.has("show_controller_overlay"):
		GameState.show_controller_overlay = settings["show_controller_overlay"]

	# Master volume
	if settings.has("master_volume"):
		AudioServer.set_bus_volume_db(0, settings["master_volume"])

	print("[SAVE] Settings loaded")
