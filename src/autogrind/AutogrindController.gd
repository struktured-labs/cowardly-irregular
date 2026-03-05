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
var _skip_next_battle: bool = false

## Tracks whether the current running battle is a meta-boss or collapse-boss fight
var _current_battle_is_meta_boss: bool = false
var _current_battle_is_collapse_boss: bool = false
var _current_meta_boss_data: Dictionary = {}

const BETWEEN_BATTLE_DELAY: float = 1.0


func _process(delta: float) -> void:
	if _state == State.BETWEEN_BATTLES:
		_between_battle_timer -= delta
		if _between_battle_timer <= 0:
			_evaluate_and_apply_rules()
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


## Evaluate autogrind rules between battles and apply any triggered actions
func _evaluate_and_apply_rules() -> void:
	var matched_rule = AutogrindSystem.evaluate_autogrind_rules(_party)
	if matched_rule.is_empty():
		return

	var actions = matched_rule.get("actions", [])
	if actions.is_empty():
		return

	# Intercept flee_battle before passing to AutogrindSystem so the controller
	# can set its own skip flag, then remove it from the list to avoid confusion.
	var filtered_actions: Array = []
	for action in actions:
		if action.get("type", "") == "flee_battle":
			_skip_next_battle = true
			print("[AUTOGRIND] Rule triggered: flee_battle -- next battle will be skipped")
		else:
			filtered_actions.append(action)

	if not filtered_actions.is_empty():
		AutogrindSystem.apply_autogrind_actions(filtered_actions)

	# Log which rule fired (for UI rule-trigger display)
	var rule_conditions = matched_rule.get("conditions", [])
	if not rule_conditions.is_empty():
		var desc = "Rule fired: "
		for cond in rule_conditions:
			desc += "%s %s %s " % [cond.get("type", "?"), cond.get("op", ""), str(cond.get("value", ""))]
		print("[AUTOGRIND] %s" % desc.strip_edges())


## Request the next battle in the chain
func _request_next_battle() -> void:
	if _state != State.PRE_BATTLE:
		return

	# If a flee_battle rule fired, skip one battle
	if _skip_next_battle:
		_skip_next_battle = false
		print("[AUTOGRIND] Skipping battle due to flee_battle rule")
		_state = State.BETWEEN_BATTLES
		_between_battle_timer = BETWEEN_BATTLE_DELAY
		return

	# Check interrupt conditions first
	var interrupt_reason = AutogrindSystem.pre_battle_check()
	if interrupt_reason != "":
		stop_grind(interrupt_reason)
		return

	# Check for system collapse — takes priority over regular meta-boss
	if AutogrindSystem.meta_corruption_level >= AutogrindSystem.corruption_threshold:
		_launch_collapse_boss_battle()
		return

	# Check for regular meta-boss spawn
	if AutogrindSystem.should_spawn_meta_boss():
		_launch_meta_boss_battle()
		return

	# Normal battle — generate scaled enemies
	_current_battle_is_meta_boss = false
	_current_battle_is_collapse_boss = false
	_current_meta_boss_data = {}
	var enemies = _generate_scaled_enemies()
	_state = State.BATTLE_RUNNING
	grind_battle_requested.emit(enemies, _terrain)


## Launch a regular meta-boss battle
func _launch_meta_boss_battle() -> void:
	var boss_data := AutogrindSystem._spawn_meta_boss()
	if boss_data.is_empty():
		stop_grind("Meta-boss data unavailable")
		return

	_current_battle_is_meta_boss = true
	_current_battle_is_collapse_boss = false
	_current_meta_boss_data = boss_data

	print("[AUTOGRIND] Launching meta-boss battle: %s" % boss_data.get("name", "Meta-Boss"))
	_state = State.BATTLE_RUNNING
	grind_battle_requested.emit([boss_data], _terrain)


## Launch a system collapse boss battle
func _launch_collapse_boss_battle() -> void:
	AutogrindSystem._trigger_system_collapse()
	var boss_data := AutogrindSystem.build_meta_boss_enemy_data(true)

	_current_battle_is_meta_boss = true
	_current_battle_is_collapse_boss = true
	_current_meta_boss_data = boss_data

	print("[AUTOGRIND] SYSTEM COLLAPSE -- launching collapse boss: %s" % boss_data.get("name", "NULL::ENTITY"))
	_state = State.BATTLE_RUNNING
	grind_battle_requested.emit([boss_data], _terrain)


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

	if _current_battle_is_collapse_boss:
		# Win or lose: apply post-collapse penalty then continue grinding
		AutogrindSystem.apply_post_collapse_penalty()
		if victory:
			print("[AUTOGRIND] Collapse boss defeated! Corruption reset, efficiency debuffed for 10 battles.")
			AutogrindSystem.on_meta_boss_victory(_current_meta_boss_data)
		else:
			print("[AUTOGRIND] Collapse boss won. Corruption reset, penalty still applied.")
		# Reset boss tracking
		_current_battle_is_meta_boss = false
		_current_battle_is_collapse_boss = false
		_current_meta_boss_data = {}
		# Continue grinding after a longer delay
		_state = State.BETWEEN_BATTLES
		_between_battle_timer = BETWEEN_BATTLE_DELAY * 2.0
		return

	if _current_battle_is_meta_boss:
		if victory:
			print("[AUTOGRIND] Meta-boss defeated! Bonus rewards and corruption reduced.")
			AutogrindSystem.on_meta_boss_victory(_current_meta_boss_data)
		else:
			print("[AUTOGRIND] Party lost to meta-boss! Corruption increased significantly.")
			AutogrindSystem.on_meta_boss_defeat(_current_meta_boss_data)
			# Check if the defeat pushed us into collapse territory
			if AutogrindSystem.meta_corruption_level >= AutogrindSystem.corruption_threshold:
				# Collapse will be handled next _request_next_battle call
				pass
			else:
				stop_grind("Defeated by meta-boss")
				return
		# Reset boss tracking
		_current_battle_is_meta_boss = false
		_current_battle_is_collapse_boss = false
		_current_meta_boss_data = {}
		_state = State.BETWEEN_BATTLES
		_between_battle_timer = BETWEEN_BATTLE_DELAY
		return

	# Normal battle resolution
	if victory:
		AutogrindSystem.on_battle_victory(exp_gained, items_gained)
		_state = State.BETWEEN_BATTLES
		_between_battle_timer = BETWEEN_BATTLE_DELAY
	else:
		AutogrindSystem.on_battle_defeat()
		if AutogrindSystem.is_grinding:
			# on_battle_defeat may have triggered permadeath and already stopped things
			stop_grind("Party defeated")


## Stop the grind session
func stop_grind(reason: String = "Manual stop") -> void:
	if _state == State.IDLE:
		return

	_state = State.IDLE
	_current_battle_is_meta_boss = false
	_current_battle_is_collapse_boss = false
	_current_meta_boss_data = {}

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
		"total_items": _count_total_items(),
		"collapse_count": AutogrindSystem.collapse_count,
		"post_collapse_debuff_battles": AutogrindSystem.post_collapse_debuff_battles,
		"permadead": AutogrindSystem.permadead_characters.duplicate()
	}


func _count_total_items() -> int:
	var count = 0
	for key in AutogrindSystem.total_items_gained:
		count += AutogrindSystem.total_items_gained[key]
	return count


## Check if currently grinding
func is_grinding() -> bool:
	return _state != State.IDLE
