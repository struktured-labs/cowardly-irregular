extends Node

## BattleManager - Singleton that orchestrates CTB (Conditional Turn-Based) combat
## All combatants select actions first, then actions execute based on computed turn order

signal battle_started()
signal battle_ended(victory: bool)
signal selection_phase_started()
signal selection_turn_started(combatant: Combatant)
signal selection_turn_ended(combatant: Combatant)
signal execution_phase_started()
signal action_executing(combatant: Combatant, action: Dictionary)
signal action_executed(combatant: Combatant, action: Dictionary, targets: Array)
signal round_started(round_num: int)
signal round_ended(round_num: int)
signal damage_dealt(target: Combatant, amount: int, is_crit: bool)
signal healing_done(target: Combatant, amount: int)
signal battle_log_message(message: String)
signal monster_summoned(monster_type: String, summoner: Combatant)
signal one_shot_achieved(rank: String, setup_turns: int)
signal autobattle_victory(multiplier: float, total_turns: int)

enum BattleState {
	INACTIVE,
	STARTING,
	SELECTION_PHASE,      # All combatants selecting actions
	PLAYER_SELECTING,     # Current player is selecting
	ENEMY_SELECTING,      # Current enemy is selecting (AI)
	EXECUTION_PHASE,      # Executing actions in turn order
	PROCESSING_ACTION,    # Currently executing an action
	VICTORY,
	DEFEAT
}

var current_state: BattleState = BattleState.INACTIVE
var current_round: int = 0

## Battle participants
var player_party: Array[Combatant] = []
var enemy_party: Array[Combatant] = []
var all_combatants: Array[Combatant] = []

## Selection phase tracking
var selection_order: Array[Combatant] = []  # Order for action selection
var selection_index: int = 0
var current_combatant: Combatant = null

## Action queue for execution
var pending_actions: Array[Dictionary] = []  # All selected actions before execution
var execution_order: Array[Dictionary] = []  # Sorted by computed turn order

## Previous round actions for repeat functionality (Y button)
var previous_round_actions: Dictionary = {}  # {combatant_id: Array[actions]}

## Battle configuration
var is_autobattle_enabled: bool = false  # Legacy global flag
var autobattle_script: Dictionary = {}  # Legacy script
var escape_allowed: bool = true

## Terrain modifiers for elemental damage
var _current_terrain: String = "plains"
var _terrain_modifiers: Dictionary = {"boost": [], "reduce": []}
const TERRAIN_MODIFIER_VALUE: float = 0.25  # +25% or -25% damage

## Autobattle toggle signal
signal autobattle_toggled(character_id: String, enabled: bool)

## One-shot tracking
var _first_damage_round: int = -1    # Round when first damage was dealt to any enemy
var _first_damage_phase: int = -1    # Execution phase when first damage was dealt
var _execution_phase_count: int = 0  # Number of execution phases so far
var _one_shot_achieved: bool = false  # Whether all enemies died in same execution phase as first damage
var _setup_turns_used: int = 0       # Turns before first damage (for rating)
var _all_enemies_initial_count: int = 0  # Total enemies at battle start

## Autobattle reward tracking
var _full_autobattle: bool = true          # False if any player turn was manual
var _autobattle_player_turns: int = 0      # Player turns handled by autobattle
var _manual_player_turns: int = 0          # Player turns handled manually

## Battle results (populated in end_battle before signal, cleared on next battle)
var _battle_results: Dictionary = {}  # {exp_per_char: int, bonuses: Array, char_results: Array}

## Adaptive AI - Action logging
var _battle_action_log: Array[Dictionary] = []  # Log every player action per battle
signal battle_actions_logged(summary: Dictionary)

## Action speed modifiers (lower = faster)
const ACTION_SPEEDS = {
	"attack": 5,
	"ability": 10,
	"item": 8,
	"defend": 0,
	"defer": 0
}


func _ready() -> void:
	pass


func set_terrain(terrain: String) -> void:
	"""Set the current terrain for elemental damage modifiers"""
	_current_terrain = terrain
	_terrain_modifiers = _get_terrain_modifiers(terrain)
	print("[TERRAIN] Battle terrain: %s (boost: %s, reduce: %s)" % [
		terrain,
		_terrain_modifiers["boost"],
		_terrain_modifiers["reduce"]
	])


func _get_terrain_modifiers(terrain: String) -> Dictionary:
	"""Get elemental modifiers for the given terrain"""
	match terrain.to_lower():
		"cave", "dungeon":
			return {"boost": ["ice", "dark"], "reduce": ["fire", "lightning"]}
		"forest", "woods":
			return {"boost": ["fire", "wind"], "reduce": ["water"]}
		"village", "town":
			return {"boost": ["holy"], "reduce": ["dark"]}
		"boss":
			return {"boost": ["dark"], "reduce": []}
		_:  # "plains" and default
			return {"boost": [], "reduce": []}


func get_terrain_damage_modifier(element: String) -> float:
	"""Get the damage modifier for an element based on current terrain"""
	if element in _terrain_modifiers["boost"]:
		return 1.0 + TERRAIN_MODIFIER_VALUE
	elif element in _terrain_modifiers["reduce"]:
		return 1.0 - TERRAIN_MODIFIER_VALUE
	return 1.0


## Battle initialization
func start_battle(players: Array[Combatant], enemies: Array[Combatant]) -> void:
	"""Initialize and start a new battle"""
	current_state = BattleState.STARTING
	current_round = 0

	player_party = players.duplicate()
	enemy_party = enemies.duplicate()
	all_combatants = players + enemies

	# Reset one-shot tracking
	_first_damage_round = -1
	_first_damage_phase = -1
	_execution_phase_count = 0
	_one_shot_achieved = false
	_setup_turns_used = 0
	_all_enemies_initial_count = enemies.size()

	# Reset autobattle tracking
	_full_autobattle = true
	_autobattle_player_turns = 0
	_manual_player_turns = 0
	_battle_results = {}

	# Connect to combatant signals
	for combatant in all_combatants:
		if not combatant.died.is_connected(_on_combatant_died):
			combatant.died.connect(_on_combatant_died.bind(combatant))

	# Clear action log for adaptive AI
	_battle_action_log.clear()

	battle_started.emit()
	_start_new_round()


func end_battle(victory: bool) -> void:
	"""End the current battle"""
	if victory:
		current_state = BattleState.VICTORY

		# Check for one-shot achievement
		_check_one_shot()

		# Calculate reward multiplier from enemies (for rare encounters like Hero Mimics)
		var reward_multiplier = _get_battle_reward_multiplier()

		# Apply one-shot bonus multiplier
		var one_shot_exp_bonus = 1.0
		var one_shot_gold_bonus = 1.0
		if _one_shot_achieved:
			var rank = _get_one_shot_rank(_setup_turns_used)
			one_shot_exp_bonus = _get_one_shot_exp_multiplier(rank)
			one_shot_gold_bonus = _get_one_shot_gold_multiplier(rank)

		# Apply autobattle bonus multiplier (stacks with one-shot)
		var autobattle_exp_bonus = 1.0
		if _full_autobattle and _autobattle_player_turns > 0:
			autobattle_exp_bonus = _get_autobattle_exp_multiplier(_autobattle_player_turns)
			autobattle_victory.emit(autobattle_exp_bonus, _autobattle_player_turns)

		# Award job EXP to player party and store results
		var base_exp = 50
		var char_results: Array = []
		for combatant in player_party:
			var exp_gained = 0
			var old_level = combatant.job_level
			if combatant.is_alive:
				exp_gained = int(base_exp * reward_multiplier * one_shot_exp_bonus * autobattle_exp_bonus)
				combatant.gain_job_exp(exp_gained)
			var leveled_up = combatant.job_level > old_level
			char_results.append({
				"name": combatant.combatant_name,
				"exp_gained": exp_gained,
				"job_level": combatant.job_level,
				"job_exp": combatant.job_exp,
				"job_name": combatant.job.get("name", "Fighter") if combatant.job else "Fighter",
				"leveled_up": leveled_up,
				"is_alive": combatant.is_alive
			})
			if exp_gained > 0:
				print("%s gained %d job EXP (Level: %d, EXP: %d/%d)%s" % [
					combatant.combatant_name, exp_gained,
					combatant.job_level, combatant.job_exp, combatant.job_level * 100,
					" LEVEL UP!" if leveled_up else ""
				])

		# Store battle results for victory screen
		var bonuses: Array = []
		if _one_shot_achieved:
			bonuses.append({"type": "one_shot", "multiplier": one_shot_exp_bonus, "rank": _get_one_shot_rank(_setup_turns_used)})
		if _full_autobattle and _autobattle_player_turns > 0:
			bonuses.append({"type": "autobattle", "multiplier": autobattle_exp_bonus, "turns": _autobattle_player_turns})
		_battle_results = {
			"char_results": char_results,
			"bonuses": bonuses,
			"base_exp": base_exp,
			"total_multiplier": reward_multiplier * one_shot_exp_bonus * autobattle_exp_bonus
		}

		# Record one-shot in save system if achieved
		var monster_ids: Array = []
		for enemy in enemy_party:
			var monster_type = enemy.get_meta("monster_type", "")
			if not monster_type.is_empty() and monster_type not in monster_ids:
				monster_ids.append(monster_type)

		if _one_shot_achieved:
			var rank = _get_one_shot_rank(_setup_turns_used)
			var save_system = get_node_or_null("/root/SaveSystem")
			if save_system and save_system.has_method("record_one_shot"):
				save_system.record_one_shot(monster_ids, rank, _setup_turns_used)

		# Record autobattle victory in save system if achieved
		if _full_autobattle and _autobattle_player_turns > 0:
			var save_system = get_node_or_null("/root/SaveSystem")
			if save_system and save_system.has_method("record_autobattle_victory"):
				save_system.record_autobattle_victory(monster_ids, _autobattle_player_turns, autobattle_exp_bonus)
	else:
		current_state = BattleState.DEFEAT

	# Emit battle action summary for adaptive AI pattern learning
	if victory:
		var summary = _summarize_battle_actions()
		battle_actions_logged.emit(summary)

	battle_ended.emit(victory)
	_cleanup_battle()


func _get_battle_reward_multiplier() -> float:
	"""Get reward multiplier from defeated enemies (for rare encounters)"""
	var max_multiplier = 1.0
	for enemy in enemy_party:
		# Check if enemy has reward_multiplier in their data
		if enemy.has_method("get") and enemy.get("_enemy_data"):
			var data = enemy.get("_enemy_data")
			if data is Dictionary and data.has("reward_multiplier"):
				max_multiplier = max(max_multiplier, data["reward_multiplier"])
	return max_multiplier


func _cleanup_battle() -> void:
	"""Clean up battle state"""
	for combatant in all_combatants:
		if combatant.died.is_connected(_on_combatant_died):
			combatant.died.disconnect(_on_combatant_died)

	player_party.clear()
	enemy_party.clear()
	all_combatants.clear()
	selection_order.clear()
	pending_actions.clear()
	execution_order.clear()
	selection_index = 0
	current_combatant = null


## Round management
func _start_new_round() -> void:
	"""Start a new round of combat"""
	current_round += 1
	selection_index = 0
	pending_actions.clear()
	execution_order.clear()

	# Reset combatants for new round
	for combatant in all_combatants:
		if combatant.is_alive:
			combatant.reset_for_new_round()

	# Calculate selection order (players first, then enemies, sorted by speed)
	_calculate_selection_order()

	round_started.emit(current_round)
	_start_selection_phase()


func _calculate_selection_order() -> void:
	"""Calculate order for action selection (players select first)"""
	var alive_players: Array[Combatant] = []
	var alive_enemies: Array[Combatant] = []

	for c in player_party:
		if c.is_alive:
			alive_players.append(c)
	for c in enemy_party:
		if c.is_alive:
			alive_enemies.append(c)

	# Sort by speed (faster selects first)
	alive_players.sort_custom(func(a, b): return a.speed > b.speed)
	alive_enemies.sort_custom(func(a, b): return a.speed > b.speed)

	# Players select first, then enemies
	selection_order.clear()
	selection_order.append_array(alive_players)
	selection_order.append_array(alive_enemies)


## Selection Phase
func _start_selection_phase() -> void:
	"""Start the selection phase where all combatants choose actions"""
	current_state = BattleState.SELECTION_PHASE
	selection_index = 0
	selection_phase_started.emit()
	_process_next_selection()


func _process_next_selection() -> void:
	"""Move to the next combatant's selection"""
	# Skip combatants with AP debt
	while selection_index < selection_order.size():
		current_combatant = selection_order[selection_index]
		if current_combatant.is_alive:
			# Check for AP debt
			if current_combatant.current_ap < 0:
				# Pay AP debt, skip selection
				current_combatant.gain_ap(1)
				print("%s is paying AP debt (%d -> %d)" % [
					current_combatant.combatant_name,
					current_combatant.current_ap - 1,
					current_combatant.current_ap
				])
				selection_index += 1
				continue
			break
		selection_index += 1

	# Check if selection is complete
	if selection_index >= selection_order.size():
		_start_execution_phase()
		return

	# Start this combatant's selection
	current_combatant.start_turn()

	# Natural AP gain: +1 AP at start of each turn
	current_combatant.gain_ap(1)
	print("%s gains +1 AP (natural gain, now AP: %d)" % [current_combatant.combatant_name, current_combatant.current_ap])

	if current_combatant in player_party:
		current_state = BattleState.PLAYER_SELECTING
	else:
		current_state = BattleState.ENEMY_SELECTING

	selection_turn_started.emit(current_combatant)

	# AI selects automatically for enemies and autobattle players
	var char_id = _get_character_id(current_combatant)
	var is_char_autobattle = AutobattleSystem.is_autobattle_enabled(char_id)

	if current_state == BattleState.ENEMY_SELECTING or is_autobattle_enabled or is_char_autobattle:
		_process_ai_selection(current_combatant)


func _end_selection_turn() -> void:
	"""End current combatant's selection turn"""
	if current_combatant:
		selection_turn_ended.emit(current_combatant)

	selection_index += 1
	_process_next_selection()


func _track_manual_player_turn() -> void:
	"""Track that a player manually selected an action (not autobattle)"""
	_full_autobattle = false
	_manual_player_turns += 1


## Player actions (called from UI)
func player_attack(target: Combatant) -> void:
	"""Queue a basic attack"""
	if current_state != BattleState.PLAYER_SELECTING:
		return
	_track_manual_player_turn()

	var action = {
		"type": "attack",
		"combatant": current_combatant,
		"target": target,
		"speed": _compute_action_speed(current_combatant, "attack")
	}
	_queue_action(action)
	_end_selection_turn()


func player_use_ability(ability_id: String, targets: Array) -> void:
	"""Queue an ability"""
	if current_state != BattleState.PLAYER_SELECTING:
		return
	_track_manual_player_turn()

	var ability = JobSystem.get_ability(ability_id)
	var action = {
		"type": "ability",
		"combatant": current_combatant,
		"ability_id": ability_id,
		"targets": targets,
		"speed": _compute_action_speed(current_combatant, "ability", ability)
	}
	_queue_action(action)
	_end_selection_turn()


func player_defer() -> void:
	"""Queue Defer action (skip turn, gain AP, defend)"""
	if current_state != BattleState.PLAYER_SELECTING:
		return
	_track_manual_player_turn()

	var action = {
		"type": "defer",
		"combatant": current_combatant,
		"speed": _compute_action_speed(current_combatant, "defer")
	}
	_queue_action(action)
	print("%s chooses to defer" % current_combatant.combatant_name)
	_end_selection_turn()


# Alias for backwards compatibility
func player_default() -> void:
	player_defer()


func player_advance(actions: Array[Dictionary]) -> void:
	"""Queue Advance action (multiple actions in sequence, each costs 1 AP)"""
	if current_state != BattleState.PLAYER_SELECTING:
		return
	_track_manual_player_turn()

	# Mark this as an advance with all actions
	# Each action will cost 1 AP when executed (first cancels natural gain, rest go to debt)
	var advance_action = {
		"type": "advance",
		"combatant": current_combatant,
		"actions": actions,
		"speed": _compute_action_speed(current_combatant, "attack")  # Use attack speed as base
	}
	_queue_action(advance_action)
	print("%s chooses to advance (%d actions, will cost %d AP)" % [current_combatant.combatant_name, actions.size(), actions.size()])
	_end_selection_turn()


# Alias for backwards compatibility
func player_brave(actions: Array[Dictionary]) -> void:
	player_advance(actions)


func go_back_to_previous_player() -> void:
	"""Go back to the previous player's selection (undo their action), skipping those in AP debt"""
	if current_state != BattleState.PLAYER_SELECTING:
		print("Cannot go back - not in player selection state")
		return

	# Undo the natural AP gain for current player (they didn't actually take their turn)
	current_combatant.spend_ap(1)
	print("%s's natural AP gain reverted (AP: %d)" % [current_combatant.combatant_name, current_combatant.current_ap])

	# Find a previous player who can actually act (not in AP debt)
	var found_player = false
	while selection_index > 0:
		selection_index -= 1
		var prev_combatant = selection_order[selection_index]

		# Skip if not a player
		if prev_combatant not in player_party:
			continue

		# Skip if in AP debt (can't act)
		if prev_combatant.current_ap < 0:
			print("Skipping %s (AP debt: %d)" % [prev_combatant.combatant_name, prev_combatant.current_ap])
			continue

		# Remove their pending action
		for i in range(pending_actions.size() - 1, -1, -1):
			var action = pending_actions[i]
			if action.get("combatant") == prev_combatant:
				pending_actions.remove_at(i)
				print("Removed %s's pending action" % prev_combatant.combatant_name)
				break

		current_combatant = prev_combatant
		print("Going back to %s (AP: %d)" % [prev_combatant.combatant_name, prev_combatant.current_ap])
		found_player = true
		break

	if not found_player:
		print("Cannot go back - no previous player available")
		# Restore current player's AP since we couldn't go back
		current_combatant.gain_ap(1)
		return

	# Re-emit the selection turn started signal (menu will be shown again)
	selection_turn_started.emit(current_combatant)


func player_item(item_id: String, targets: Array) -> void:
	"""Queue an item use"""
	if current_state != BattleState.PLAYER_SELECTING:
		return
	_track_manual_player_turn()

	var action = {
		"type": "item",
		"combatant": current_combatant,
		"item_id": item_id,
		"targets": targets,
		"speed": _compute_action_speed(current_combatant, "item")
	}
	_queue_action(action)
	_end_selection_turn()


func _queue_action(action: Dictionary) -> void:
	"""Add action to pending queue"""
	pending_actions.append(action)


func _compute_action_speed(combatant: Combatant, action_type: String, ability: Dictionary = {}) -> float:
	"""Compute action speed value (lower = executes first)"""
	var base_speed = ACTION_SPEEDS.get(action_type, 10)

	# Abilities can have custom speed modifiers
	if ability.has("speed_modifier"):
		base_speed = int(base_speed * ability["speed_modifier"])

	# Subtract combatant speed (higher speed = lower value = faster)
	var speed_value = base_speed - (combatant.speed * 0.5)

	# Add small random variance
	speed_value += randf_range(-1.0, 1.0)

	return speed_value


## AI Selection
func _process_ai_selection(combatant: Combatant) -> void:
	"""AI selects action for a combatant"""
	var is_player_controlled = combatant in player_party

	# Track autobattle turn for player combatants (for autobattle reward)
	if is_player_controlled:
		_autobattle_player_turns += 1
	var allies = player_party if is_player_controlled else enemy_party
	var enemies = enemy_party if is_player_controlled else player_party

	var alive_allies = allies.filter(func(a): return a.is_alive)
	var alive_enemies = enemies.filter(func(e): return e.is_alive)

	if alive_enemies.size() == 0:
		# No targets, defer
		var action = {
			"type": "defer",
			"combatant": combatant,
			"speed": _compute_action_speed(combatant, "defer")
		}
		_queue_action(action)
		_end_selection_turn()
		return

	# Check for per-character autobattle script (players only)
	var char_id = _get_character_id(combatant)
	if is_player_controlled and AutobattleSystem.is_autobattle_enabled(char_id):
		_process_grid_autobattle(combatant)
		return

	# AI can advance or defer too!
	var should_advance = randf() < 0.15 and combatant.current_ap >= 0  # 15% chance to advance
	var should_defer = randf() < 0.1 and combatant.current_ap < 4    # 10% chance to defer

	if should_defer:
		var action = {
			"type": "defer",
			"combatant": combatant,
			"speed": _compute_action_speed(combatant, "defer")
		}
		_queue_action(action)
		print("%s (AI) chooses to defer" % combatant.combatant_name)
		_end_selection_turn()
		return

	if should_advance and combatant.current_ap >= 1:
		# Queue multiple attacks as advance (each action costs 1 AP)
		# Max 4 actions per advance, but limited by AP (can't go below -4)
		var ap_limit = combatant.current_ap + 4  # How many actions AP allows
		var max_actions = mini(4, ap_limit)  # Cap at 4
		var num_actions = mini(randi_range(2, 3), max_actions)
		var advance_actions: Array[Dictionary] = []
		for i in range(num_actions):
			var target = _choose_target(combatant, alive_enemies, {})
			advance_actions.append({"type": "attack", "target": target})

		var advance_action = {
			"type": "advance",
			"combatant": combatant,
			"actions": advance_actions,
			"speed": _compute_action_speed(combatant, "attack")
		}
		_queue_action(advance_action)
		print("%s (AI) chooses to advance (%d actions)" % [combatant.combatant_name, num_actions])
		_end_selection_turn()
		return

	# Check if monster wants to summon reinforcements
	var can_summon = _can_monster_summon(combatant)
	if can_summon and randf() < 0.12:  # 12% chance to summon
		var summon_action = {
			"type": "summon",
			"combatant": combatant,
			"monster_type": _get_summon_type(combatant),
			"speed": _compute_action_speed(combatant, "summon")
		}
		_queue_action(summon_action)
		print("%s calls for reinforcements!" % combatant.combatant_name)
		_end_selection_turn()
		return

	# Normal AI decision
	var action = _make_ai_decision(combatant, alive_allies, alive_enemies)
	_queue_action(action)
	_end_selection_turn()


func _make_ai_decision(combatant: Combatant, alive_allies: Array, alive_enemies: Array) -> Dictionary:
	"""Make AI decision for action selection"""
	# Get available abilities
	var available_abilities = []
	if combatant.job and combatant.job.has("abilities"):
		for ability_id in combatant.job["abilities"]:
			var ability = JobSystem.get_ability(ability_id)
			if not ability.is_empty() and combatant.current_mp >= ability.get("mp_cost", 0):
				available_abilities.append(ability)

	# Check for adaptive behavior (enemy AI learns from player patterns)
	var adaptation_level = _get_current_adaptation_level()
	var counter_strategy = _get_current_counter_strategy()

	if adaptation_level > 0 and not counter_strategy.is_empty():
		var counter_chance = 0.3 * adaptation_level  # 30%/60%/90%
		if randf() < counter_chance:
			var counter_action = _get_counter_action(combatant, counter_strategy, alive_allies, alive_enemies, available_abilities)
			if not counter_action.is_empty():
				battle_log_message.emit("The enemy anticipates your strategy...")
				return counter_action

	# Check if should heal (30% chance if ally below 40% HP)
	var low_hp_allies = alive_allies.filter(func(a): return a.get_hp_percentage() < 40.0)
	if low_hp_allies.size() > 0 and randf() < 0.3:
		var healing_abilities = available_abilities.filter(func(a): return a["type"] == "healing")
		if healing_abilities.size() > 0:
			var heal = healing_abilities[randi() % healing_abilities.size()]
			return {
				"type": "ability",
				"combatant": combatant,
				"ability_id": heal["id"],
				"targets": [low_hp_allies[0]],
				"speed": _compute_action_speed(combatant, "ability", heal)
			}

	# Check if should use offensive ability (40% chance)
	if randf() < 0.4 and combatant.current_mp >= 10:
		var offensive_abilities = available_abilities.filter(
			func(a): return a["type"] in ["physical", "magic"]
		)
		if offensive_abilities.size() > 0:
			var spell = offensive_abilities[randi() % offensive_abilities.size()]
			var spell_target = _choose_target(combatant, alive_enemies, spell)
			return {
				"type": "ability",
				"combatant": combatant,
				"ability_id": spell["id"],
				"targets": [spell_target],
				"speed": _compute_action_speed(combatant, "ability", spell)
			}

	# Default to basic attack
	var target = _choose_target(combatant, alive_enemies, {})
	return {
		"type": "attack",
		"combatant": combatant,
		"target": target,
		"speed": _compute_action_speed(combatant, "attack")
	}


func _choose_target(attacker: Combatant, targets: Array, ability: Dictionary = {}) -> Combatant:
	"""Choose best target for attack/ability"""
	if targets.size() == 0:
		return null

	# Prefer lowest HP target (60% chance)
	if randf() < 0.6:
		var sorted_targets = targets.duplicate()
		sorted_targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		return sorted_targets[0]

	return targets[randi() % targets.size()]


## Execution Phase
func _start_execution_phase() -> void:
	"""Start executing all queued actions in computed turn order"""
	current_state = BattleState.EXECUTION_PHASE

	# Track execution phase count for one-shot detection
	_execution_phase_count += 1

	# Save player actions for repeat functionality (Y button)
	_save_previous_actions()

	# Sort actions by speed (lower speed value = executes first)
	execution_order = pending_actions.duplicate()
	execution_order.sort_custom(func(a, b): return a["speed"] < b["speed"])

	print("\n[color=yellow]>>> Actions executing![/color]")
	execution_phase_started.emit()

	_execute_next_action()


func _save_previous_actions() -> void:
	"""Save current round's player actions for repeat functionality"""
	previous_round_actions.clear()
	for action in pending_actions:
		var combatant = action.get("combatant") as Combatant
		if combatant and combatant in player_party:
			var combatant_id = combatant.combatant_name.to_lower()
			if not previous_round_actions.has(combatant_id):
				previous_round_actions[combatant_id] = []
			# Store action without combatant reference (will be re-bound on replay)
			var saved_action = action.duplicate()
			saved_action.erase("combatant")
			previous_round_actions[combatant_id].append(saved_action)


func repeat_previous_actions() -> bool:
	"""Queue previous round's actions for all players. Returns true if successful."""
	_track_manual_player_turn()  # Repeat is a manual action, not autobattle

	if previous_round_actions.is_empty():
		print("[REPEAT] No previous actions to repeat")
		return false

	if current_state != BattleState.SELECTION_PHASE and current_state != BattleState.PLAYER_SELECTING:
		print("[REPEAT] Can only repeat during selection phase")
		return false

	print("[REPEAT] Repeating previous round's actions for all players")

	# Queue actions for all players who haven't selected yet
	var repeated_any = false
	for combatant in selection_order:
		if combatant not in player_party:
			continue

		var combatant_id = combatant.combatant_name.to_lower()
		if not previous_round_actions.has(combatant_id):
			# No previous action for this player, use default attack
			_queue_action({
				"combatant": combatant,
				"type": "attack",
				"target": _get_alive_enemies()[0] if _get_alive_enemies().size() > 0 else null,
				"speed": ACTION_SPEEDS["attack"] + combatant.stats.speed
			})
			print("[REPEAT] %s: no previous action, using attack" % combatant.combatant_name)
			repeated_any = true
			continue

		# Replay all actions for this combatant
		var actions = previous_round_actions[combatant_id]
		for saved_action in actions:
			var action = saved_action.duplicate()
			action["combatant"] = combatant

			# Retarget if target is dead or freed
			if action.has("target"):
				var target = action["target"]
				if not is_instance_valid(target) or (target is Combatant and not target.is_alive):
					var alive_enemies = _get_alive_enemies()
					action["target"] = alive_enemies[0] if alive_enemies.size() > 0 else null

			# Retarget for abilities/items
			if action.has("targets"):
				var new_targets = []
				for target in action["targets"]:
					if is_instance_valid(target) and target is Combatant and target.is_alive:
						new_targets.append(target)
					else:
						# Replace dead/freed targets with first alive enemy
						var alive_enemies = _get_alive_enemies()
						if alive_enemies.size() > 0:
							new_targets.append(alive_enemies[0])
				action["targets"] = new_targets

			_queue_action(action)
			print("[REPEAT] %s: queued %s" % [combatant.combatant_name, action["type"]])
			repeated_any = true

	if repeated_any:
		# Skip remaining selections and start execution
		selection_index = selection_order.size()
		_process_next_selection()

	return repeated_any


func _get_alive_enemies() -> Array[Combatant]:
	"""Get list of alive enemies"""
	var alive: Array[Combatant] = []
	for enemy in enemy_party:
		if enemy.is_alive:
			alive.append(enemy)
	return alive


func _execute_next_action() -> void:
	"""Execute the next action in the queue"""
	# Check for victory/defeat
	if _check_victory_conditions():
		return

	# Get next action
	if execution_order.size() == 0:
		# Round complete
		round_ended.emit(current_round)
		_start_new_round()
		return

	var action = execution_order.pop_front()
	var combatant = action["combatant"] as Combatant

	# Skip if combatant died
	if not combatant or not combatant.is_alive:
		_execute_next_action()
		return

	current_combatant = combatant
	current_state = BattleState.PROCESSING_ACTION

	# Execute based on action type
	match action["type"]:
		"attack":
			_execute_attack(combatant, action["target"])
		"ability":
			_execute_ability(combatant, action["ability_id"], action.get("targets", []))
		"item":
			_execute_item(combatant, action["item_id"], action.get("targets", []))
		"defer":
			_execute_defer(combatant)
		"summon":
			_execute_summon(combatant, action.get("monster_type", "slime"))
		"advance":
			_execute_advance(combatant, action)
			return  # Advance handles its own continuation

	# Log player action for adaptive AI pattern detection
	_log_player_action(combatant, action)
	action_executed.emit(combatant, action, action.get("targets", [action.get("target")]))

	# Delay between actions - long enough for animations to complete
	await get_tree().create_timer(0.7).timeout
	_execute_next_action()


func _execute_defer(combatant: Combatant) -> void:
	"""Execute defer action"""
	combatant.execute_defer()
	print("%s defers (AP: %d)" % [combatant.combatant_name, combatant.current_ap])


func _can_monster_summon(combatant: Combatant) -> bool:
	"""Check if this monster can summon reinforcements"""
	# Only enemies can summon
	if combatant in player_party:
		return false

	# Limit total enemies to prevent overwhelming battles
	var alive_enemies = enemy_party.filter(func(e): return e.is_alive)
	if alive_enemies.size() >= 5:
		return false

	# Check if this monster type can summon
	var monster_type = combatant.get_meta("monster_type", "")
	var summoner_types = ["goblin", "imp", "skeleton", "wolf", "bat"]
	return monster_type in summoner_types


func _get_summon_type(combatant: Combatant) -> String:
	"""Get the type of monster to summon based on summoner"""
	var monster_type = combatant.get_meta("monster_type", "slime")

	# Each monster type summons specific allies
	match monster_type:
		"goblin":
			return ["goblin", "imp"][randi() % 2]
		"imp":
			return ["imp", "bat"][randi() % 2]
		"skeleton":
			return ["skeleton", "ghost"][randi() % 2]
		"wolf":
			return "wolf"
		"bat":
			return "bat"
		_:
			return "slime"


func _execute_summon(combatant: Combatant, monster_type: String) -> void:
	"""Execute summon action - spawn a new enemy"""
	print("  → %s summons a %s!" % [combatant.combatant_name, monster_type.capitalize()])
	monster_summoned.emit(monster_type, combatant)


func _execute_advance(combatant: Combatant, advance_action: Dictionary) -> void:
	"""Execute advance action - all queued actions in sequence (each costs 1 AP)"""
	var actions = advance_action["actions"] as Array

	# Note: Each action costs 1 AP during execution
	# The first action would normally cost 1 AP anyway (canceling natural gain)
	# Additional actions go into AP debt
	print("%s advances with %d actions!" % [combatant.combatant_name, actions.size()])

	# Execute all actions in sequence (each will spend 1 AP)
	for action in actions:
		if not combatant.is_alive:
			break

		if _check_victory_conditions():
			return

		match action["type"]:
			"attack":
				_execute_attack(combatant, action["target"])
			"ability":
				_execute_ability(combatant, action["ability_id"], action.get("targets", []))
			"item":
				_execute_item(combatant, action["item_id"], action.get("targets", []))

		# Log player action for adaptive AI pattern detection
		_log_player_action(combatant, action)
		action_executed.emit(combatant, action, action.get("targets", [action.get("target")]))
		await get_tree().create_timer(0.5).timeout  # Time for animation

	# Continue to next action
	await get_tree().create_timer(0.5).timeout
	_execute_next_action()


func _retarget_enemy(attacker: Combatant, original_target: Combatant) -> Combatant:
	"""Find a new enemy target if original is dead (auto-retarget like most JRPGs)"""
	if original_target and original_target.is_alive:
		return original_target

	# Determine which party to target
	var target_party = enemy_party if attacker in player_party else player_party
	var alive_targets = target_party.filter(func(t): return t.is_alive)

	if alive_targets.size() == 0:
		return null

	# Pick the target with lowest HP (similar to original targeting)
	alive_targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
	var new_target = alive_targets[0]

	if original_target:
		print("%s's target %s is gone, retargeting to %s" % [attacker.combatant_name, original_target.combatant_name, new_target.combatant_name])

	return new_target


func _retarget_ally(caster: Combatant, original_target: Combatant, include_dead: bool = false) -> Combatant:
	"""Find a new ally target if original is invalid"""
	if original_target and (original_target.is_alive or include_dead):
		return original_target

	# Determine which party is allies
	var ally_party = player_party if caster in player_party else enemy_party
	var valid_targets = ally_party.filter(func(t): return t.is_alive or include_dead)

	if valid_targets.size() == 0:
		return null

	# For healing, pick lowest HP ally
	valid_targets.sort_custom(func(a, b): return a.get_hp_percentage() < b.get_hp_percentage())
	return valid_targets[0]


func _execute_attack(attacker: Combatant, target: Combatant) -> void:
	"""Execute a basic physical attack (costs 1 AP)"""
	# Auto-retarget if original target is dead
	var actual_target = _retarget_enemy(attacker, target)
	if not actual_target:
		print("%s's attack fizzles - no valid targets!" % attacker.combatant_name)
		return

	# Actions cost 1 AP (cancels out natural gain for net 0)
	attacker.spend_ap(1)

	action_executing.emit(attacker, {"type": "attack", "target": actual_target})

	var base_damage = attacker.attack
	var variance = randf_range(0.85, 1.15)
	var damage = int(base_damage * variance)

	# Critical hit calculation (physical attacks can crit)
	var is_crit = false
	var crit_chance = _calculate_crit_chance(attacker)
	if randf() < crit_chance:
		is_crit = true
		var crit_multiplier = _get_crit_multiplier(attacker)
		damage = int(damage * crit_multiplier)

	var actual_damage = actual_target.take_damage(damage, false)
	damage_dealt.emit(actual_target, actual_damage, is_crit)

	# Track first damage for one-shot detection
	if actual_target in enemy_party:
		_record_first_damage()

	var crit_text = " [color=orange]CRITICAL![/color]" if is_crit else ""
	var log_msg = "[color=white]%s[/color] attacks [color=red]%s[/color] for [color=yellow]%d[/color] damage!%s" % [attacker.combatant_name, actual_target.combatant_name, actual_damage, crit_text]
	battle_log_message.emit(log_msg)
	print("%s attacks %s for %d damage!%s" % [attacker.combatant_name, actual_target.combatant_name, actual_damage, " CRIT!" if is_crit else ""])


func _execute_ability(caster: Combatant, ability_id: String, targets: Array) -> void:
	"""Execute an ability (costs 1 AP)"""
	var ability = JobSystem.get_ability(ability_id)
	if ability.is_empty():
		print("Error: Unknown ability %s" % ability_id)
		return

	if not JobSystem.can_use_ability(caster, ability_id):
		print("%s cannot use %s" % [caster.combatant_name, ability["name"]])
		return

	# Auto-retarget dead targets based on ability type
	var retargeted: Array = []
	var ability_type = ability.get("type", "")
	var is_offensive = ability_type in ["physical", "magic"]
	var is_revival = ability_type == "revival"

	for target in targets:
		if is_offensive:
			var new_target = _retarget_enemy(caster, target)
			if new_target:
				retargeted.append(new_target)
		elif is_revival:
			# Revival targets dead allies, don't retarget
			if target:
				retargeted.append(target)
		else:
			# Healing/support targets allies
			var new_target = _retarget_ally(caster, target, is_revival)
			if new_target:
				retargeted.append(new_target)

	if retargeted.size() == 0 and targets.size() > 0:
		print("%s's %s fizzles - no valid targets!" % [caster.combatant_name, ability["name"]])
		return

	var mp_cost = ability.get("mp_cost", 0)
	if not caster.spend_mp(mp_cost):
		print("%s doesn't have enough MP!" % caster.combatant_name)
		return

	# Actions cost 1 AP (cancels out natural gain for net 0)
	caster.spend_ap(1)

	action_executing.emit(caster, {"type": "ability", "ability_id": ability_id, "targets": retargeted})
	var ability_log = "[color=white]%s[/color] uses [color=aqua]%s[/color]!" % [caster.combatant_name, ability["name"]]
	battle_log_message.emit(ability_log)
	print("%s uses %s!" % [caster.combatant_name, ability["name"]])

	match ability_type:
		"physical":
			_execute_physical_ability(caster, ability, retargeted)
		"magic":
			_execute_magic_ability(caster, ability, retargeted)
		"healing":
			_execute_healing_ability(caster, ability, retargeted)
		"revival":
			_execute_revival_ability(caster, ability, retargeted)
		"support":
			_execute_support_ability(caster, ability, retargeted)
		"meta":
			_execute_meta_ability(caster, ability, retargeted)
		"escape":
			_execute_escape_ability(caster, ability)
		_:
			print("Unknown ability type: %s" % ability_type)


func _execute_physical_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var base_damage = caster.get_buffed_stat("attack", caster.attack)
	var multiplier = ability.get("damage_multiplier", 1.0)
	var crit_chance = ability.get("crit_chance", 0.0)

	for target in targets:
		if not target or not target.is_alive:
			continue

		var damage = int(base_damage * multiplier)
		var is_crit = false

		if randf() < crit_chance:
			damage = int(damage * 2.0)
			is_crit = true
			print("Critical hit!")

		damage = int(damage * randf_range(0.9, 1.1))
		var actual_damage = target.take_damage(damage, false)
		damage_dealt.emit(target, actual_damage, is_crit)

		# Track first damage for one-shot detection
		if target in enemy_party:
			_record_first_damage()

		var crit_text = " [color=orange]CRITICAL![/color]" if is_crit else ""
		var log_msg = "  → [color=red]%s[/color] takes [color=yellow]%d[/color] damage!%s" % [target.combatant_name, actual_damage, crit_text]
		battle_log_message.emit(log_msg)
		print("  → %s takes %d damage!" % [target.combatant_name, actual_damage])


func _execute_magic_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var base_damage = caster.get_buffed_stat("magic", caster.magic)
	var multiplier = ability.get("damage_multiplier", 1.0)
	var element = ability.get("element", "")
	var drain_pct = ability.get("drain_percentage", 0)

	for target in targets:
		if not target or not target.is_alive:
			continue

		var damage = int(base_damage * multiplier)
		damage = int(damage * randf_range(0.9, 1.1))

		# Apply terrain modifier for elemental damage
		var terrain_mod = 1.0
		if element:
			terrain_mod = get_terrain_damage_modifier(element)
			damage = int(damage * terrain_mod)

		var actual_damage = 0
		if element:
			actual_damage = target.take_elemental_damage(damage, element)
		else:
			actual_damage = target.take_damage(damage, true)

		damage_dealt.emit(target, actual_damage, false)

		# Track first damage for one-shot detection
		if target in enemy_party:
			_record_first_damage()

		var elem_text = element if element else "magic"
		var terrain_text = ""
		if terrain_mod > 1.0:
			terrain_text = " [color=lime](terrain +%d%%)[/color]" % int((terrain_mod - 1.0) * 100)
		elif terrain_mod < 1.0:
			terrain_text = " [color=gray](terrain -%d%%)[/color]" % int((1.0 - terrain_mod) * 100)
		var log_msg = "  → [color=red]%s[/color] takes [color=cyan]%d[/color] %s damage!%s" % [target.combatant_name, actual_damage, elem_text, terrain_text]
		battle_log_message.emit(log_msg)
		print("  → %s takes %d %s damage! (terrain: %.2fx)" % [target.combatant_name, actual_damage, elem_text, terrain_mod])

		if drain_pct > 0:
			var drained = int(actual_damage * drain_pct / 100.0)
			caster.heal(drained)
			healing_done.emit(caster, drained)
			var drain_log = "  → [color=white]%s[/color] drains [color=lime]%d[/color] HP!" % [caster.combatant_name, drained]
			battle_log_message.emit(drain_log)
			print("  → %s drains %d HP!" % [caster.combatant_name, drained])


## Critical hit system
## Physical attacks can crit, magic does NOT crit by default

func _calculate_crit_chance(attacker: Combatant) -> float:
	"""Calculate critical hit chance based on speed and equipment"""
	# Base crit chance is 5%
	var base_crit = 0.05

	# Speed adds to crit chance (each 10 speed = +1% crit)
	var speed_bonus = attacker.speed * 0.001

	# Check for crit-boosting passives
	var passive_bonus = 0.0
	if "critical_strike" in attacker.equipped_passives:
		passive_bonus += 0.10  # +10% from passive

	# Check for equipment bonuses (could add this later)
	var equip_bonus = 0.0

	# Cap at 50% crit chance
	return min(base_crit + speed_bonus + passive_bonus + equip_bonus, 0.50)


func _get_crit_multiplier(attacker: Combatant) -> float:
	"""Get critical hit damage multiplier"""
	# Base crit multiplier is 1.5x
	var base_mult = 1.5

	# Check for enhanced crit passives
	if "devastating_criticals" in attacker.equipped_passives:
		base_mult = 2.0

	return base_mult


func _execute_healing_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var heal_amount = ability.get("heal_amount", 0)
	var multiplier = GameState.get_constant("healing_multiplier")
	heal_amount = int(heal_amount * multiplier)

	for target in targets:
		if not target or not target.is_alive:
			continue

		var healed = target.heal(heal_amount)
		healing_done.emit(target, healed)
		var heal_log = "  → [color=white]%s[/color] recovers [color=lime]%d[/color] HP!" % [target.combatant_name, healed]
		battle_log_message.emit(heal_log)
		print("  → %s recovers %d HP!" % [target.combatant_name, healed])


func _execute_revival_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var revive_pct = ability.get("revive_percentage", 50)

	for target in targets:
		if not target or target.is_alive:
			continue

		var revive_hp = int(target.max_hp * revive_pct / 100.0)
		target.revive(revive_hp)
		print("  → %s is revived with %d HP!" % [target.combatant_name, revive_hp])


func _execute_support_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var effect = ability.get("effect", "")
	var duration = ability.get("duration", 3)
	var stat_modifier = ability.get("stat_modifier", 1.0)
	var success_rate = ability.get("success_rate", 1.0)

	match effect:
		"taunt":
			for target in targets:
				if target and target.is_alive:
					target.add_status("taunted_%s" % caster.combatant_name)
					print("  → %s is now targeting %s!" % [target.combatant_name, caster.combatant_name])
		"defense_up":
			for target in targets:
				if target and target.is_alive:
					target.add_buff("Protect", "defense", stat_modifier, duration)
		"attack_up":
			for target in targets:
				if target and target.is_alive:
					target.add_buff("Berserk", "attack", stat_modifier, duration)
		"defense_down":
			for target in targets:
				if target and target.is_alive and randf() < success_rate:
					target.add_debuff("Armor Break", "defense", stat_modifier, duration)
		"doom":
			var countdown = ability.get("countdown", 3)
			for target in targets:
				if target and target.is_alive:
					target.doom_counter = countdown
					print("  → %s is doomed! %d turns remaining..." % [target.combatant_name, countdown])
		_:
			print("  → Unknown support effect: %s" % effect)


func _execute_meta_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var meta_effect = ability.get("meta_effect", "")
	var corruption_risk = ability.get("corruption_risk", 0.0)
	var corruption_amount = ability.get("corruption_amount", 0.0)

	match meta_effect:
		"formula_modification":
			print("  → %s opens the formula editor..." % caster.combatant_name)
			GameState.add_corruption(corruption_risk)
		"constant_modification":
			print("  → %s accesses game constants..." % caster.combatant_name)
			GameState.add_corruption(corruption_risk)
		"code_inspection":
			print("  → %s analyzes the battle code..." % caster.combatant_name)
			print("  → [META] Revealing execution order...")
		"time_rewind":
			print("  → %s attempts to rewind time..." % caster.combatant_name)
			if GameState.rewind_to_previous_save():
				print("  → [META] Time has been rewound!")
			else:
				print("  → [META] No previous save state to rewind to")
		"add_corruption":
			print("  → %s channels corrupted power!" % caster.combatant_name)
			GameState.add_corruption(corruption_amount)
			_execute_magic_ability(caster, ability, targets)
		"permanent_death":
			print("  → %s casts PERMAKILL!" % caster.combatant_name)
			for target in targets:
				if target and target.is_alive:
					target.die()
					target.add_status("permakilled")
					print("  → %s has been PERMANENTLY KILLED!" % target.combatant_name)
			GameState.add_corruption(corruption_risk)
		_:
			print("  → Unknown meta effect: %s" % meta_effect)


func _execute_escape_ability(caster: Combatant, ability: Dictionary) -> void:
	if not escape_allowed:
		print("  → Cannot escape from this battle!")
		return

	var success_rate = ability.get("success_rate", 0.5)
	if randf() < success_rate:
		print("  → %s escaped successfully!" % caster.combatant_name)
		end_battle(false)
	else:
		print("  → %s failed to escape!" % caster.combatant_name)


func _execute_item(user: Combatant, item_id: String, targets: Array) -> void:
	"""Execute item use (costs 1 AP)"""
	if not user.has_item(item_id):
		print("%s doesn't have item: %s" % [user.combatant_name, item_id])
		return

	# Auto-retarget dead targets (most items are healing, target allies)
	# TODO: Check item type for offensive items that should target enemies
	var retargeted: Array[Combatant] = []
	for t in targets:
		if t is Combatant:
			var new_target = _retarget_ally(user, t, false)
			if new_target:
				retargeted.append(new_target)

	if retargeted.size() == 0 and targets.size() > 0:
		print("%s's item fizzles - no valid targets!" % user.combatant_name)
		return

	# Actions cost 1 AP (cancels out natural gain for net 0)
	user.spend_ap(1)

	action_executing.emit(user, {"type": "item", "item_id": item_id, "targets": retargeted})

	if ItemSystem.use_item(user, item_id, retargeted):
		user.remove_item(item_id, 1)
	else:
		print("Failed to use item: %s" % item_id)


## Victory/defeat conditions
func _check_victory_conditions() -> bool:
	var players_alive = player_party.any(func(p): return p.is_alive)
	var enemies_alive = enemy_party.any(func(e): return e.is_alive)

	if not players_alive:
		end_battle(false)
		return true
	elif not enemies_alive:
		end_battle(true)
		return true

	return false


## Signal handlers
func _on_combatant_died(combatant: Combatant) -> void:
	print("%s has been defeated!" % combatant.combatant_name)


## Utility functions
func get_alive_combatants(party: Array[Combatant]) -> Array[Combatant]:
	var alive: Array[Combatant] = []
	for combatant in party:
		if combatant.is_alive:
			alive.append(combatant)
	return alive


func is_battle_active() -> bool:
	return current_state not in [BattleState.INACTIVE, BattleState.VICTORY, BattleState.DEFEAT]


func is_selecting() -> bool:
	return current_state in [BattleState.SELECTION_PHASE, BattleState.PLAYER_SELECTING, BattleState.ENEMY_SELECTING]


func is_executing() -> bool:
	return current_state in [BattleState.EXECUTION_PHASE, BattleState.PROCESSING_ACTION]


## Autobattle control
func set_autobattle_script(script_name: String) -> void:
	autobattle_script = AutobattleSystem.load_script(script_name)
	if autobattle_script.is_empty():
		autobattle_script = AutobattleSystem.load_script("Aggressive")
	print("Autobattle script set to: %s" % autobattle_script.get("name", "Unknown"))


func toggle_autobattle(enabled: bool) -> void:
	is_autobattle_enabled = enabled
	print("Autobattle %s" % ("enabled" if enabled else "disabled"))


func execute_autobattle_for_current() -> void:
	"""Execute autobattle for the current selecting combatant (called from UI)"""
	if current_state != BattleState.PLAYER_SELECTING or not current_combatant:
		return
	# Process using AI selection which handles autobattle
	_process_ai_selection(current_combatant)


## Per-character autobattle helpers
func _get_character_id(combatant: Combatant) -> String:
	"""Get character ID for autobattle system (lowercase, underscore-separated)"""
	return combatant.combatant_name.to_lower().replace(" ", "_")


## ═══════════════════════════════════════════════════════════════════════
## ADAPTIVE AI - Action Logging & Pattern Detection
## ═══════════════════════════════════════════════════════════════════════

func _log_player_action(combatant: Combatant, action: Dictionary) -> void:
	"""Log a player action for pattern detection"""
	if combatant not in player_party:
		return  # Only log player actions

	_battle_action_log.append({
		"turn": current_round,
		"character_id": _get_character_id(combatant),
		"action_type": action.get("type", "attack"),
		"ability_id": action.get("ability_id", ""),
		"target_type": _classify_target(action),
		"ap_before": combatant.current_ap
	})


func _classify_target(action: Dictionary) -> String:
	"""Classify target type for pattern detection"""
	var target = action.get("target", null)
	if target == null:
		var targets = action.get("targets", [])
		target = targets[0] if targets.size() > 0 else null
	if target == null:
		return "none"
	if target in enemy_party:
		# Check if targeting lowest HP
		var sorted_enemies = enemy_party.filter(func(e): return e.is_alive)
		sorted_enemies.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		if sorted_enemies.size() > 0 and target == sorted_enemies[0]:
			return "lowest_hp"
		return "enemy"
	if target in player_party:
		return "ally"
	return "self"


func _summarize_battle_actions() -> Dictionary:
	"""Summarize battle actions for pattern learning"""
	var summary = {
		"ability_frequency": {},
		"action_type_frequency": {},
		"target_priority": {},
		"avg_ap_usage": 0.0,
		"common_opener": "",
		"total_actions": _battle_action_log.size()
	}

	if _battle_action_log.is_empty():
		return summary

	var total_ap = 0.0
	for entry in _battle_action_log:
		# Count action types
		var atype = entry["action_type"]
		summary["action_type_frequency"][atype] = summary["action_type_frequency"].get(atype, 0) + 1

		# Count abilities
		var ability_id = entry["ability_id"]
		if not ability_id.is_empty():
			summary["ability_frequency"][ability_id] = summary["ability_frequency"].get(ability_id, 0) + 1

		# Count target types
		var ttype = entry["target_type"]
		summary["target_priority"][ttype] = summary["target_priority"].get(ttype, 0) + 1

		total_ap += entry.get("ap_before", 0)

	summary["avg_ap_usage"] = total_ap / _battle_action_log.size()

	# Determine common opener (first action of battle)
	if _battle_action_log.size() > 0:
		var first = _battle_action_log[0]
		summary["common_opener"] = first["action_type"]
		if not first["ability_id"].is_empty():
			summary["common_opener"] = first["ability_id"]

	return summary


## ═══════════════════════════════════════════════════════════════════════
## ADAPTIVE AI - Counter Strategy Logic
## ═══════════════════════════════════════════════════════════════════════

func _get_current_adaptation_level() -> int:
	"""Get adaptation level from AutogrindSystem for current region"""
	if not AutogrindSystem:
		return 0
	return AutogrindSystem.get_adaptation_level_for_region(AutogrindSystem.current_region_id)


func _get_current_counter_strategy() -> String:
	"""Get counter strategy from AutogrindSystem for current region"""
	if not AutogrindSystem:
		return ""
	return AutogrindSystem.get_counter_strategy(AutogrindSystem.current_region_id)


func _get_counter_action(combatant: Combatant, strategy: String, allies: Array, enemies: Array, abilities: Array) -> Dictionary:
	"""Generate a counter action based on learned strategy"""
	match strategy:
		"fire_resist":
			# Use fire resistance buff if available
			var resist_abilities = abilities.filter(func(a): return "resist" in a.get("id", "") or "shield" in a.get("id", ""))
			if resist_abilities.size() > 0:
				return {
					"type": "ability",
					"combatant": combatant,
					"ability_id": resist_abilities[0]["id"],
					"targets": [combatant],
					"speed": _compute_action_speed(combatant, "ability", resist_abilities[0])
				}
		"ice_resist":
			var resist_abilities = abilities.filter(func(a): return "resist" in a.get("id", "") or "shield" in a.get("id", ""))
			if resist_abilities.size() > 0:
				return {
					"type": "ability",
					"combatant": combatant,
					"ability_id": resist_abilities[0]["id"],
					"targets": [combatant],
					"speed": _compute_action_speed(combatant, "ability", resist_abilities[0])
				}
		"lightning_resist":
			var resist_abilities = abilities.filter(func(a): return "resist" in a.get("id", "") or "shield" in a.get("id", ""))
			if resist_abilities.size() > 0:
				return {
					"type": "ability",
					"combatant": combatant,
					"ability_id": resist_abilities[0]["id"],
					"targets": [combatant],
					"speed": _compute_action_speed(combatant, "ability", resist_abilities[0])
				}
		"focus_healer":
			# Target the healer (usually Mira/white mage)
			var healers = enemies.filter(func(e):
				return e.job and e.job.get("id", "") in ["white_mage", "healer"]
			)
			if healers.size() > 0:
				return {
					"type": "attack",
					"combatant": combatant,
					"target": healers[0],
					"speed": _compute_action_speed(combatant, "attack")
				}
		"defense_boost":
			var def_abilities = abilities.filter(func(a): return "defense" in a.get("id", "") or "guard" in a.get("id", "") or "shield" in a.get("id", ""))
			if def_abilities.size() > 0:
				return {
					"type": "ability",
					"combatant": combatant,
					"ability_id": def_abilities[0]["id"],
					"targets": [combatant],
					"speed": _compute_action_speed(combatant, "ability", def_abilities[0])
				}
		"rotate_aggro":
			return {
				"type": "attack",
				"combatant": combatant,
				"target": enemies[randi() % enemies.size()],
				"speed": _compute_action_speed(combatant, "attack")
			}
		"generic_counter":
			if abilities.size() > 0:
				var strongest = abilities[0]
				for a in abilities:
					if a.get("power", 0) > strongest.get("power", 0):
						strongest = a
				var target = enemies[randi() % enemies.size()]
				return {
					"type": "ability",
					"combatant": combatant,
					"ability_id": strongest["id"],
					"targets": [target],
					"speed": _compute_action_speed(combatant, "ability", strongest)
				}

	return {}  # No counter available


func _process_grid_autobattle(combatant: Combatant) -> void:
	"""Process grid-based autobattle for a player character"""
	var is_player_controlled = combatant in player_party
	var allies = player_party if is_player_controlled else enemy_party
	var enemies = enemy_party if is_player_controlled else player_party

	var alive_allies = allies.filter(func(a): return a.is_alive)
	var alive_enemies = enemies.filter(func(e): return e.is_alive)

	# Get actions from the grid autobattle system
	# (AutobattleSystem accesses BattleManager directly for context)
	var actions = AutobattleSystem.execute_grid_autobattle(combatant)

	if actions.size() == 0:
		# No valid actions found, defer
		var action = {
			"type": "defer",
			"combatant": combatant,
			"speed": _compute_action_speed(combatant, "defer")
		}
		_queue_action(action)
		print("%s (autobattle) defers - no matching rules" % combatant.combatant_name)
		_end_selection_turn()
		return

	if actions.size() == 1:
		# Single action
		var action_data = actions[0]
		var queued_action = _convert_autobattle_action(combatant, action_data, alive_allies, alive_enemies)
		if queued_action:
			_queue_action(queued_action)
			print("%s (autobattle) queues %s" % [combatant.combatant_name, action_data.get("type", "unknown")])
		else:
			# Fallback to defer if action conversion fails
			var defer_action = {
				"type": "defer",
				"combatant": combatant,
				"speed": _compute_action_speed(combatant, "defer")
			}
			_queue_action(defer_action)
		_end_selection_turn()
		return

	# Multiple actions - use Advance
	var advance_actions: Array[Dictionary] = []
	for action_data in actions:
		var converted = _convert_autobattle_action(combatant, action_data, alive_allies, alive_enemies)
		if converted:
			# For advance, we just need type/target/ability_id
			var sub_action = {"type": converted["type"]}
			if converted.has("target"):
				sub_action["target"] = converted["target"]
			if converted.has("targets"):
				sub_action["targets"] = converted["targets"]
			if converted.has("ability_id"):
				sub_action["ability_id"] = converted["ability_id"]
			if converted.has("item_id"):
				sub_action["item_id"] = converted["item_id"]
			advance_actions.append(sub_action)

	if advance_actions.size() == 0:
		# All actions failed, defer
		var defer_action = {
			"type": "defer",
			"combatant": combatant,
			"speed": _compute_action_speed(combatant, "defer")
		}
		_queue_action(defer_action)
		_end_selection_turn()
		return

	if advance_actions.size() == 1:
		# Only one valid action, queue it normally
		var single = advance_actions[0]
		single["combatant"] = combatant
		single["speed"] = _compute_action_speed(combatant, single.get("type", "attack"))
		_queue_action(single)
	else:
		# Queue as advance
		var advance_action = {
			"type": "advance",
			"combatant": combatant,
			"actions": advance_actions,
			"speed": _compute_action_speed(combatant, "attack")
		}
		_queue_action(advance_action)
		print("%s (autobattle) advances with %d actions" % [combatant.combatant_name, advance_actions.size()])

	_end_selection_turn()


func _convert_autobattle_action(combatant: Combatant, action_data: Dictionary, allies: Array, enemies: Array) -> Dictionary:
	"""Convert autobattle action data to BattleManager action format"""
	var action_type = action_data.get("type", "attack")
	var target_data = action_data.get("target", "lowest_hp_enemy")

	# Handle case where target is already a Combatant object or a string
	var resolved_target: Combatant = null
	if target_data is Combatant:
		resolved_target = target_data
	elif target_data is String:
		resolved_target = _resolve_target(combatant, target_data, allies, enemies)
	else:
		resolved_target = _resolve_target(combatant, "lowest_hp_enemy", allies, enemies)

	# Check if targets are already provided as Combatant objects
	var action_targets = action_data.get("targets", [])
	var has_direct_targets = action_targets.size() > 0 and action_targets[0] is Combatant

	match action_type:
		"attack":
			var target = action_targets[0] if has_direct_targets else resolved_target
			if not target:
				return {}
			return {
				"type": "attack",
				"combatant": combatant,
				"target": target,
				"speed": _compute_action_speed(combatant, "attack")
			}

		"ability":
			# AutobattleSystem uses "ability_id", also check "id" for backwards compat
			var ability_id = action_data.get("ability_id", action_data.get("id", ""))
			if ability_id.is_empty():
				print("[AUTOBATTLE] No ability_id found in action: %s" % action_data)
				return {}
			var ability = JobSystem.get_ability(ability_id)
			if ability.is_empty():
				print("[AUTOBATTLE] Unknown ability: %s" % ability_id)
				return {}
			if not JobSystem.can_use_ability(combatant, ability_id):
				print("[AUTOBATTLE] Cannot use ability: %s (MP: %d)" % [ability_id, combatant.current_mp])
				return {}
			var targets_to_use = action_targets if has_direct_targets else ([resolved_target] if resolved_target else [])
			return {
				"type": "ability",
				"combatant": combatant,
				"ability_id": ability_id,
				"targets": targets_to_use,
				"speed": _compute_action_speed(combatant, "ability", ability)
			}

		"item":
			# Check both "item_id" and "id" for backwards compat
			var item_id = action_data.get("item_id", action_data.get("id", ""))
			if item_id.is_empty():
				return {}
			if not combatant.has_item(item_id):
				return {}
			var targets_to_use = action_targets if has_direct_targets else ([resolved_target] if resolved_target else [])
			return {
				"type": "item",
				"combatant": combatant,
				"item_id": item_id,
				"targets": targets_to_use,
				"speed": _compute_action_speed(combatant, "item")
			}

		"defer":
			return {
				"type": "defer",
				"combatant": combatant,
				"speed": _compute_action_speed(combatant, "defer")
			}

	return {}


func _resolve_target(combatant: Combatant, target_type: String, allies: Array, enemies: Array) -> Combatant:
	"""Resolve a target based on target type string"""
	match target_type:
		"lowest_hp_enemy":
			if enemies.size() == 0:
				return null
			var sorted_enemies = enemies.duplicate()
			sorted_enemies.sort_custom(func(a, b): return a.get_hp_percentage() < b.get_hp_percentage())
			return sorted_enemies[0]

		"highest_hp_enemy":
			if enemies.size() == 0:
				return null
			var sorted_enemies = enemies.duplicate()
			sorted_enemies.sort_custom(func(a, b): return a.get_hp_percentage() > b.get_hp_percentage())
			return sorted_enemies[0]

		"random_enemy":
			if enemies.size() == 0:
				return null
			return enemies[randi() % enemies.size()]

		"lowest_hp_ally":
			if allies.size() == 0:
				return null
			var sorted_allies = allies.duplicate()
			sorted_allies.sort_custom(func(a, b): return a.get_hp_percentage() < b.get_hp_percentage())
			return sorted_allies[0]

		"self":
			return combatant

		_:
			# Default to lowest HP enemy
			if enemies.size() == 0:
				return null
			var sorted_enemies = enemies.duplicate()
			sorted_enemies.sort_custom(func(a, b): return a.get_hp_percentage() < b.get_hp_percentage())
			return sorted_enemies[0]


## One-Shot System

func _record_first_damage() -> void:
	"""Record when first damage is dealt to an enemy (starts the one-shot timer)"""
	if _first_damage_round == -1:
		_first_damage_round = current_round
		_first_damage_phase = _execution_phase_count
		_setup_turns_used = current_round - 1  # Turns before damage = setup
		print("[ONE-SHOT] First damage recorded at round %d, execution phase %d (setup turns: %d)" % [
			_first_damage_round, _first_damage_phase, _setup_turns_used
		])


func _check_one_shot() -> void:
	"""Check if one-shot was achieved (all enemies killed in same execution phase as first damage)"""
	if _first_damage_phase == -1:
		return  # No damage was dealt

	# Check if all enemies died in the same execution phase as first damage
	var all_dead = true
	for enemy in enemy_party:
		if enemy.is_alive:
			all_dead = false
			break

	if all_dead and _execution_phase_count == _first_damage_phase:
		_one_shot_achieved = true
		var rank = _get_one_shot_rank(_setup_turns_used)
		one_shot_achieved.emit(rank, _setup_turns_used)
		print("[ONE-SHOT] Achieved! Rank: %s, Setup turns: %d, Enemies: %d" % [
			rank, _setup_turns_used, _all_enemies_initial_count
		])


func _get_one_shot_rank(setup_turns: int) -> String:
	"""Get one-shot rank based on number of setup turns used"""
	if setup_turns <= 1:
		return "S"   # Raw power overwhelm
	elif setup_turns <= 3:
		return "A"   # Efficient buff chain
	elif setup_turns <= 5:
		return "B"   # Standard setup
	else:
		return "C"   # Slow but valid


func _get_one_shot_exp_multiplier(rank: String) -> float:
	"""Get EXP multiplier for one-shot rank"""
	match rank:
		"S":
			return 3.0
		"A":
			return 2.0
		"B":
			return 1.5
		"C":
			return 1.25
		_:
			return 1.0


func _get_one_shot_gold_multiplier(rank: String) -> float:
	"""Get gold multiplier for one-shot rank"""
	match rank:
		"S":
			return 2.5
		"A":
			return 2.0
		"B":
			return 1.5
		"C":
			return 1.25
		_:
			return 1.0


func get_one_shot_achieved() -> bool:
	"""Check if one-shot was achieved in the current/last battle"""
	return _one_shot_achieved


func get_one_shot_rank() -> String:
	"""Get the one-shot rank for the current/last battle"""
	if _one_shot_achieved:
		return _get_one_shot_rank(_setup_turns_used)
	return ""


func get_one_shot_exp_multiplier() -> float:
	"""Get the one-shot EXP multiplier for the current/last battle"""
	if _one_shot_achieved:
		return _get_one_shot_exp_multiplier(_get_one_shot_rank(_setup_turns_used))
	return 1.0


## Autobattle Reward System

func _get_autobattle_exp_multiplier(total_turns: int) -> float:
	"""Get EXP multiplier for full autobattle victory based on total player turns"""
	if total_turns <= 4:
		return 1.5   # Quick fight
	elif total_turns <= 8:
		return 2.0   # Medium fight
	elif total_turns <= 16:
		return 2.5   # Long fight
	else:
		return 3.0   # Marathon


func get_autobattle_achieved() -> bool:
	"""Check if full autobattle was achieved in the current/last battle"""
	return _full_autobattle and _autobattle_player_turns > 0


func get_autobattle_exp_multiplier() -> float:
	"""Get the autobattle EXP multiplier for the current/last battle"""
	if get_autobattle_achieved():
		return _get_autobattle_exp_multiplier(_autobattle_player_turns)
	return 1.0


func get_autobattle_turns() -> int:
	"""Get the number of player turns handled by autobattle"""
	return _autobattle_player_turns


func get_battle_results() -> Dictionary:
	"""Get battle results (populated after victory, cleared on next battle start)"""
	return _battle_results
