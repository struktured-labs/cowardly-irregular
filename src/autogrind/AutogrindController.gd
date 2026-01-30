extends Node

## AutogrindController - Orchestrates battle chaining between GameLoop and AutogrindSystem
## State machine: IDLE -> PRE_BATTLE -> BATTLE_RUNNING -> POST_BATTLE -> BETWEEN_BATTLES -> loop

signal grind_battle_requested(enemies: Array, terrain: String)
signal grind_complete(reason: String)

enum State {
	IDLE,
	PRE_BATTLE,
	BATTLE_RUNNING,
	POST_BATTLE,
	BETWEEN_BATTLES
}

var _state: State = State.IDLE
var _party: Array = []
var _config: Dictionary = {}
var _saved_autobattle_states: Dictionary = {}
var _terrain: String = "plains"
var _between_battle_timer: float = 0.0

const BETWEEN_BATTLE_DELAY: float = 1.0


func _process(delta: float) -> void:
	if _state == State.BETWEEN_BATTLES:
		_between_battle_timer -= delta
		if _between_battle_timer <= 0:
			_state = State.PRE_BATTLE
			_request_next_battle()


## Start a grinding session
func start_grind(party: Array, config: Dictionary, terrain: String = "plains") -> void:
	if _state != State.IDLE:
		print("[AUTOGRIND] Already grinding!")
		return

	_party = party
	_config = config
	_terrain = terrain

	# Save and force autobattle states
	_save_autobattle_states()
	_force_autobattle_on()

	# Initialize AutogrindSystem
	var typed_party: Array[Combatant] = []
	for member in _party:
		if member is Combatant:
			typed_party.append(member)

	AutogrindSystem.start_autogrind(typed_party, {}, config)

	# Set region
	var region = config.get("region", "")
	if region != "":
		AutogrindSystem.set_current_region(region)

	# Speed up battles
	Engine.time_scale = 2.0

	print("[AUTOGRIND] Controller started, requesting first battle")
	_state = State.PRE_BATTLE
	_request_next_battle()


## Request the next battle in the chain
func _request_next_battle() -> void:
	if _state != State.PRE_BATTLE:
		return

	# Check interrupt conditions
	var interrupt_reason = AutogrindSystem.pre_battle_check()
	if interrupt_reason != "":
		stop_grind(interrupt_reason)
		return

	# Check for meta-boss spawn
	if AutogrindSystem.should_spawn_meta_boss():
		# For now, meta-boss stops the grind (as in original behavior)
		AutogrindSystem._spawn_meta_boss()
		stop_grind("Meta-boss appeared")
		return

	# Generate scaled enemies
	var enemies = _generate_scaled_enemies()

	_state = State.BATTLE_RUNNING
	grind_battle_requested.emit(enemies, _terrain)


## Generate enemies with adaptation scaling
func _generate_scaled_enemies() -> Array:
	# Pick random enemies from BattleScene.MONSTER_TYPES
	var BattleSceneScript = load("res://src/battle/BattleScene.gd")
	var monster_types = BattleSceneScript.MONSTER_TYPES

	var num_enemies = randi_range(2, 3)
	var selected: Array = []

	for i in range(num_enemies):
		var base_type = monster_types[randi() % monster_types.size()]
		var base_data = {
			"id": base_type["id"],
			"name": base_type["name"],
			"color": base_type.get("color", Color.WHITE),
			"stats": base_type["stats"].duplicate(true),
			"weaknesses": base_type.get("weaknesses", []).duplicate(),
			"resistances": base_type.get("resistances", []).duplicate()
		}

		# Apply AutogrindSystem scaling
		var scaled = AutogrindSystem.create_scaled_enemy_data(base_data)
		selected.append(scaled)

	return selected


## Called when a battle ends
func on_battle_ended(victory: bool, exp_gained: int = 0, items_gained: Dictionary = {}) -> void:
	if _state != State.BATTLE_RUNNING:
		return

	_state = State.POST_BATTLE

	if victory:
		AutogrindSystem.on_battle_victory(exp_gained, items_gained)
		# Transition to between-battles delay
		_state = State.BETWEEN_BATTLES
		_between_battle_timer = BETWEEN_BATTLE_DELAY
	else:
		AutogrindSystem.on_battle_defeat()
		stop_grind("Party defeated")


## Stop the grind session
func stop_grind(reason: String = "Manual stop") -> void:
	if _state == State.IDLE:
		return

	_state = State.IDLE

	# Restore autobattle states
	_restore_autobattle_states()

	# Reset engine speed
	Engine.time_scale = 1.0

	# Stop the autogrind system
	AutogrindSystem.stop_autogrind(reason)

	print("[AUTOGRIND] Controller stopped: %s" % reason)
	grind_complete.emit(reason)


## Save current autobattle toggle states for all party members
func _save_autobattle_states() -> void:
	_saved_autobattle_states.clear()
	for member in _party:
		if member is Combatant:
			var char_id = member.combatant_name.to_lower().replace(" ", "_")
			_saved_autobattle_states[char_id] = AutobattleSystem.is_autobattle_enabled(char_id)


## Force autobattle ON for all party members
func _force_autobattle_on() -> void:
	for member in _party:
		if member is Combatant:
			var char_id = member.combatant_name.to_lower().replace(" ", "_")
			AutobattleSystem.set_autobattle_enabled(char_id, true)
	print("[AUTOGRIND] Forced autobattle ON for all party members")


## Restore autobattle states to what they were before grinding
func _restore_autobattle_states() -> void:
	for char_id in _saved_autobattle_states:
		AutobattleSystem.set_autobattle_enabled(char_id, _saved_autobattle_states[char_id])
	_saved_autobattle_states.clear()
	print("[AUTOGRIND] Restored autobattle states")


## Get current grind stats for UI update
func get_grind_stats() -> Dictionary:
	return {
		"efficiency": AutogrindSystem.efficiency_multiplier,
		"corruption": AutogrindSystem.meta_corruption_level,
		"adaptation": AutogrindSystem.monster_adaptation_level,
		"region_crack": AutogrindSystem.region_crack_levels.get(AutogrindSystem.current_region_id, 0),
		"meta_boss_chance": AutogrindSystem.meta_boss_spawn_chance,
		"consecutive_wins": AutogrindSystem.consecutive_wins,
		"battles_won": AutogrindSystem.battles_completed,
		"total_exp": AutogrindSystem.total_exp_gained,
		"total_items": _count_total_items()
	}


func _count_total_items() -> int:
	var count = 0
	for key in AutogrindSystem.total_items_gained:
		count += AutogrindSystem.total_items_gained[key]
	return count


## Check if currently grinding
func is_grinding() -> bool:
	return _state != State.IDLE
