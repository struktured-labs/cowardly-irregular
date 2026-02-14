extends Node

## GameState - Manages save/load, game state, and meta-manipulation
## Handles save corruption, time manipulation, and game constant editing

signal save_created(save_name: String)
signal save_loaded(save_name: String)
signal save_corrupted(corruption_level: float)
signal game_constant_modified(constant_name: String, old_value, new_value)

const SAVE_DIR = "user://saves/"
const SAVE_EXTENSION = ".cowirsave"

## Current game state
var current_save_name: String = ""
var playtime_seconds: float = 0.0
var corruption_level: float = 0.0  # 0.0 to 1.0, affects save stability

## Player party state (references to Combatant nodes)
var player_party: Array[Dictionary] = []

## Economy
var party_gold: int = 500  # Starting gold

## Settings (exposed to UI)
var encounter_rate_multiplier: float = 1.0  # 0.0 to 2.0, controlled via settings menu
var debug_log_enabled: bool = true  # Show debug log overlay (default on)

## Game constants (modifiable by Scriptweaver and other meta jobs)
var game_constants: Dictionary = {
	"exp_multiplier": 1.0,
	"gold_multiplier": 1.0,
	"damage_multiplier": 1.0,
	"healing_multiplier": 1.0,
	"encounter_rate": 1.0,
	"drop_rate_multiplier": 1.0,
}

## Meta-save features (unlocked by Time Mage)
var meta_features: Dictionary = {
	"autosave_enabled": false,
	"rewind_enabled": false,
	"restore_points_enabled": false,
	"max_restore_points": 0
}

## Save history for Time Mage rewind
var save_history: Array[Dictionary] = []
var max_history_size: int = 10

## Corruption effects
var corruption_effects: Array[String] = []


func _ready() -> void:
	_ensure_save_directory()


func _process(delta: float) -> void:
	playtime_seconds += delta


## Save/Load system
func _ensure_save_directory() -> void:
	"""Create save directory if it doesn't exist"""
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)


func save_game(save_name: String = "") -> bool:
	"""Save current game state"""
	if save_name.is_empty():
		save_name = "autosave" if meta_features["autosave_enabled"] else "quicksave"

	current_save_name = save_name
	var save_path = SAVE_DIR + save_name + SAVE_EXTENSION

	var save_data = _create_save_data()

	# Apply corruption effects
	if corruption_level > 0.0:
		save_data = _apply_corruption_to_save(save_data)

	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		print("Error: Failed to create save file at %s" % save_path)
		return false

	var json_string = JSON.stringify(save_data, "\t")
	file.store_string(json_string)
	file.close()

	# Add to history for Time Mage rewind
	if meta_features["rewind_enabled"]:
		_add_to_history(save_data)

	save_created.emit(save_name)
	print("Game saved: %s (corruption: %.1f%%)" % [save_name, corruption_level * 100])
	return true


func load_game(save_name: String) -> bool:
	"""Load a saved game"""
	var save_path = SAVE_DIR + save_name + SAVE_EXTENSION

	if not FileAccess.file_exists(save_path):
		print("Error: Save file not found: %s" % save_path)
		return false

	var file = FileAccess.open(save_path, FileAccess.READ)
	if not file:
		print("Error: Failed to open save file: %s" % save_path)
		return false

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		print("Error: Failed to parse save file: %s" % json.get_error_message())
		return false

	var save_data = json.data
	_apply_save_data(save_data)

	current_save_name = save_name
	save_loaded.emit(save_name)
	print("Game loaded: %s" % save_name)
	return true


func _create_save_data() -> Dictionary:
	"""Create save data dictionary"""
	return {
		"version": "0.1.0",
		"timestamp": Time.get_unix_time_from_system(),
		"playtime": playtime_seconds,
		"corruption_level": corruption_level,
		"party_gold": party_gold,
		"player_party": player_party.duplicate(true),
		"game_constants": game_constants.duplicate(),
		"meta_features": meta_features.duplicate(),
		"corruption_effects": corruption_effects.duplicate()
	}


func _apply_save_data(save_data: Dictionary) -> void:
	"""Apply loaded save data to game state"""
	if save_data.has("playtime"):
		playtime_seconds = save_data["playtime"]
	if save_data.has("corruption_level"):
		corruption_level = save_data["corruption_level"]
	if save_data.has("party_gold"):
		party_gold = save_data["party_gold"]
	if save_data.has("player_party"):
		player_party = save_data["player_party"].duplicate(true)
	if save_data.has("game_constants"):
		game_constants = save_data["game_constants"].duplicate()
	if save_data.has("meta_features"):
		meta_features = save_data["meta_features"].duplicate()
	if save_data.has("corruption_effects"):
		corruption_effects = save_data["corruption_effects"].duplicate()


func get_save_list() -> Array[String]:
	"""Get list of available save files"""
	var saves: Array[String] = []
	var dir = DirAccess.open(SAVE_DIR)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(SAVE_EXTENSION):
				saves.append(file_name.trim_suffix(SAVE_EXTENSION))
			file_name = dir.get_next()
		dir.list_dir_end()

	return saves


func delete_save(save_name: String) -> bool:
	"""Delete a save file"""
	var save_path = SAVE_DIR + save_name + SAVE_EXTENSION
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
		print("Save deleted: %s" % save_name)
		return true
	return false


## Corruption system
func add_corruption(amount: float) -> void:
	"""Add corruption to current save"""
	var old_level = corruption_level
	corruption_level = clampf(corruption_level + amount, 0.0, 1.0)

	if corruption_level > old_level:
		save_corrupted.emit(corruption_level)
		_apply_random_corruption_effect()


func _apply_corruption_to_save(save_data: Dictionary) -> Dictionary:
	"""Apply corruption effects when saving"""
	var corrupted_data = save_data.duplicate(true)

	if randf() < corruption_level:
		# Random corruption effects
		var corruption_type = randi() % 5

		match corruption_type:
			0:  # Corrupt player HP
				if corrupted_data.has("player_party"):
					for character in corrupted_data["player_party"]:
						if randf() < 0.3:
							character["current_hp"] = int(character["current_hp"] * randf_range(0.5, 0.9))
			1:  # Corrupt stats
				if corrupted_data.has("player_party"):
					for character in corrupted_data["player_party"]:
						if randf() < 0.3:
							character["attack"] = int(character["attack"] * randf_range(0.8, 1.0))
			2:  # Corrupt BP
				if corrupted_data.has("player_party"):
					for character in corrupted_data["player_party"]:
						character["current_bp"] = randi_range(-2, 0)
			3:  # Add fake corruption effect marker
				if not corrupted_data.has("corruption_effects"):
					corrupted_data["corruption_effects"] = []
				corrupted_data["corruption_effects"].append("data_integrity_compromised")
			4:  # Corrupt game constants
				if corrupted_data.has("game_constants") and game_constants.size() > 0:
					var keys = game_constants.keys()
					var constant = keys[randi() % keys.size()]
					corrupted_data["game_constants"][constant] *= randf_range(0.7, 1.3)

	return corrupted_data


func _apply_random_corruption_effect() -> void:
	"""Apply a random corruption effect to gameplay"""
	var effects = [
		"visual_glitch",
		"stat_drain",
		"bp_instability",
		"encounter_surge",
		"ability_corruption"
	]

	var effect = effects[randi() % effects.size()]
	if not effect in corruption_effects:
		corruption_effects.append(effect)
		print("Corruption effect applied: %s" % effect)


## Game constant modification (Scriptweaver ability)
func modify_constant(constant_name: String, new_value: float) -> bool:
	"""Modify a game constant (causes corruption)"""
	if not game_constants.has(constant_name):
		print("Error: Unknown game constant: %s" % constant_name)
		return false

	var old_value = game_constants[constant_name]
	game_constants[constant_name] = new_value

	# Modifying game constants causes corruption
	var corruption_amount = abs(new_value - old_value) * 0.1
	add_corruption(corruption_amount)

	game_constant_modified.emit(constant_name, old_value, new_value)
	print("Game constant modified: %s = %s (was %s)" % [constant_name, new_value, old_value])
	return true


func get_constant(constant_name: String) -> float:
	"""Get current value of a game constant"""
	return game_constants.get(constant_name, 1.0)


## Time Mage features
func unlock_time_mage_features() -> void:
	"""Unlock meta-save features (called when Time Mage job is obtained)"""
	meta_features["autosave_enabled"] = true
	meta_features["rewind_enabled"] = true
	meta_features["restore_points_enabled"] = true
	meta_features["max_restore_points"] = 5
	print("Time Mage features unlocked!")


func _add_to_history(save_data: Dictionary) -> void:
	"""Add save state to history for rewind"""
	save_history.append(save_data.duplicate(true))

	# Keep history size limited
	while save_history.size() > max_history_size:
		save_history.pop_front()


func rewind_to_previous_save() -> bool:
	"""Rewind to previous save state (Time Mage ability)"""
	if not meta_features["rewind_enabled"]:
		print("Error: Rewind not unlocked")
		return false

	if save_history.size() < 2:
		print("Error: No previous save state to rewind to")
		return false

	# Remove current state
	save_history.pop_back()

	# Restore previous state
	var previous_state = save_history.back()
	_apply_save_data(previous_state)

	print("Rewound to previous save state")
	return true


## Economy methods
func add_gold(amount: int) -> void:
	"""Add gold to party (applies gold_multiplier)"""
	var multiplied_amount = int(amount * game_constants["gold_multiplier"])
	party_gold += multiplied_amount
	print("Gold gained: %d (base: %d)" % [multiplied_amount, amount])


func spend_gold(amount: int) -> bool:
	"""Spend gold (returns false if insufficient funds)"""
	if party_gold < amount:
		print("Error: Insufficient gold (have %d, need %d)" % [party_gold, amount])
		return false

	party_gold -= amount
	print("Gold spent: %d (remaining: %d)" % [amount, party_gold])
	return true


func get_gold() -> int:
	"""Get current party gold"""
	return party_gold


## Utility
func get_playtime_formatted() -> String:
	"""Get formatted playtime string"""
	var hours = int(playtime_seconds / 3600)
	var minutes = int((playtime_seconds - hours * 3600) / 60)
	var seconds = int(playtime_seconds - hours * 3600 - minutes * 60)
	return "%02d:%02d:%02d" % [hours, minutes, seconds]


func reset_game_state() -> void:
	"""Reset game state to defaults"""
	playtime_seconds = 0.0
	corruption_level = 0.0
	party_gold = 500
	player_party.clear()
	corruption_effects.clear()
	save_history.clear()

	# Reset game constants
	game_constants = {
		"exp_multiplier": 1.0,
		"gold_multiplier": 1.0,
		"damage_multiplier": 1.0,
		"healing_multiplier": 1.0,
		"encounter_rate": 1.0,
		"drop_rate_multiplier": 1.0,
	}


## Serialization methods for SaveSystem
func to_dict() -> Dictionary:
	"""Serialize game state for saving"""
	return _create_save_data()


func from_dict(data: Dictionary) -> void:
	"""Restore game state from saved data"""
	_apply_save_data(data)


func get_play_time() -> float:
	"""Get current playtime in seconds"""
	return playtime_seconds
