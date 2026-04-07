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
signal damage_dealt(target: Combatant, amount: int, is_crit: bool, element: String, elemental_mod: float)
signal attack_missed(target: Combatant)
signal healing_done(target: Combatant, amount: int)
signal battle_log_message(message: String)
signal monster_summoned(monster_type: String, summoner: Combatant)
signal one_shot_achieved(rank: String, setup_turns: int)
signal autobattle_victory(multiplier: float, total_turns: int)
signal group_attack_executing(participants: Array, group_type: String, targets: Array)

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

## Volatility system (instantiated per battle)
var volatility: VolatilitySystem = null

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
## Turbo mode - minimize delays between actions for fastest execution
var turbo_mode: bool = false

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

	# Initialize volatility system
	volatility = VolatilitySystem.new()
	volatility.reset_battle()

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

		# Collect gold from defeated enemies
		var total_gold = 0
		var monsters_data = {}
		if EncounterSystem and not EncounterSystem.monster_database.is_empty():
			monsters_data = EncounterSystem.monster_database
		for enemy in enemy_party:
			var mt = enemy.get_meta("monster_type", "")
			if mt in monsters_data:
				var gold = monsters_data[mt].get("gold_reward", 0)
				total_gold += int(gold * one_shot_gold_bonus)
		if total_gold > 0:
			GameState.add_gold(total_gold)
			print("Party earned %d gold!" % total_gold)

		# Award job EXP to player party and store results
		var base_exp = 50
		var char_results: Array = []
		for combatant in player_party:
			var exp_gained = 0
			var old_level = combatant.job_level
			var old_exp = combatant.job_exp
			var old_exp_max = combatant.job_level * 100
			if combatant.is_alive:
				exp_gained = int(base_exp * reward_multiplier * one_shot_exp_bonus * autobattle_exp_bonus)
				combatant.gain_job_exp(exp_gained)
			var leveled_up = combatant.job_level > old_level
			char_results.append({
				"name": combatant.combatant_name,
				"exp_gained": exp_gained,
				"job_level": combatant.job_level,
				"job_exp": combatant.job_exp,
				"job_exp_before": old_exp,
				"exp_to_next": old_exp_max,
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
			"total_gold": total_gold,
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
	volatility = null


## Round management
func _start_new_round() -> void:
	"""Start a new round of combat"""
	current_round += 1
	selection_index = 0
	pending_actions.clear()
	execution_order.clear()

	# Reset combatants for new round and tick buff/debuff durations
	for combatant in all_combatants:
		if combatant.is_alive:
			combatant.end_turn()
			combatant.reset_for_new_round()

	# Apply corruption effects from enemies that carry them
	_apply_corruption_effects_on_round_start()

	# Calculate selection order (players first, then enemies, sorted by speed)
	_calculate_selection_order()

	round_started.emit(current_round)
	_start_selection_phase()


func _apply_corruption_effects_on_round_start() -> void:
	"""Apply per-round corruption effects from enemies that carry them.
	time_distortion: randomize a corruption enemy's speed modifier each round.
	stat_drain: reduce all alive player stats by 1% per round (permanent within battle)."""
	# Collect all active corruption effects across the live enemy party
	var active_effects: Array = []
	for enemy in enemy_party:
		if enemy.is_alive and enemy.has_meta("corruption_effects"):
			var effects = enemy.get_meta("corruption_effects", [])
			for eff in effects:
				if eff not in active_effects:
					active_effects.append(eff)

	if active_effects.is_empty():
		return

	# time_distortion: enemy speed shifts ±30% each round
	if "time_distortion" in active_effects:
		for enemy in enemy_party:
			if enemy.is_alive and enemy.has_meta("corruption_effects") and \
					"time_distortion" in enemy.get_meta("corruption_effects", []):
				if not enemy.has_meta("_base_speed"):
					enemy.set_meta("_base_speed", enemy.speed)
				var base_speed = enemy.get_meta("_base_speed")
				var shift = randf_range(-0.3, 0.3)
				enemy.speed = maxi(1, int(base_speed * (1.0 + shift)))
		battle_log_message.emit("[color=cyan]Time distorts — enemy speeds fluctuate![/color]")

	# stat_drain: all living party members lose 1% of each stat per round (min 1)
	if "stat_drain" in active_effects:
		for member in player_party:
			if member.is_alive:
				member.attack = maxi(1, member.attack - maxi(1, int(member.attack * 0.01)))
				member.defense = maxi(1, member.defense - maxi(1, int(member.defense * 0.01)))
				member.magic = maxi(1, member.magic - maxi(1, int(member.magic * 0.01)))
		battle_log_message.emit("[color=purple]Corruption seeps in — party stats erode![/color]")


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
	if current_combatant.has_status("cannot_defer"):
		battle_log_message.emit("[color=red]%s cannot defer while exposed![/color]" % current_combatant.combatant_name)
		# Re-show menu instead of silently returning (prevents battle freeze)
		current_state = BattleState.PLAYER_SELECTING
		selection_turn_started.emit(current_combatant)
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


func player_group_attack(group_type: String, formation_id: String = "") -> void:
	"""Initiate a group attack — all alive party members pool AP for a combined strike.
	group_type: "all_out_attack", "limit_break", "combo_magic", or "formation"
	Limit Break requires every participant to have >= 4 AP.
	Combo Magic requires >= 2 AP each and >= 2 distinct magic elements across party.
	The calling combatant's action is queued immediately; remaining alive players are
	auto-queued as participants (their individual selection turns are skipped)."""
	if current_state != BattleState.PLAYER_SELECTING:
		return
	_track_manual_player_turn()

	var alive_players: Array[Combatant] = player_party.filter(func(c): return c.is_alive)

	# Limit Break requires full AP (>= 4) from every party member
	if group_type == "limit_break":
		for member in alive_players:
			if member.current_ap < 4:
				battle_log_message.emit("[color=red]Limit Break requires ALL party members at full AP (4)![/color]")
				print("[GROUP] Limit Break blocked — %s has AP %d" % [member.combatant_name, member.current_ap])
				current_state = BattleState.PLAYER_SELECTING
				selection_turn_started.emit(current_combatant)
				return

	# Combo Magic requires >= 2 AP each and >= 2 distinct magic elements
	if group_type == "combo_magic":
		for member in alive_players:
			if member.current_ap < 2:
				battle_log_message.emit("[color=red]Combo Magic requires ALL party members to have >= 2 AP![/color]")
				current_state = BattleState.PLAYER_SELECTING
				selection_turn_started.emit(current_combatant)
				return
		var elements = _get_party_elements(alive_players)
		if elements.size() < 2:
			battle_log_message.emit("[color=red]Combo Magic requires at least 2 different magic elements![/color]")
			current_state = BattleState.PLAYER_SELECTING
			selection_turn_started.emit(current_combatant)
			return

	# Collect participants: current combatant + remaining unselected alive players
	var participants: Array[Combatant] = []
	participants.append(current_combatant)

	# Determine remaining players who haven't selected yet (index after current)
	for i in range(selection_index + 1, selection_order.size()):
		var c = selection_order[i]
		if c in player_party and c.is_alive:
			participants.append(c)

	var action = {
		"type": "group",
		"combatant": current_combatant,
		"group_type": group_type,
		"formation_id": formation_id,
		"participants": participants,
		"speed": _compute_action_speed(current_combatant, "attack")
	}
	_queue_action(action)
	print("[GROUP] %s initiates group attack '%s' with %d participants" % [
		current_combatant.combatant_name, group_type, participants.size()])

	# Fast-forward past remaining player selections — they are committed to the group action
	while selection_index + 1 < selection_order.size():
		var next = selection_order[selection_index + 1]
		if next in player_party and next.is_alive:
			# Give them their natural AP gain and mark turn ended without queuing a new action
			next.start_turn()
			next.gain_ap(1)
			selection_turn_started.emit(next)
			selection_turn_ended.emit(next)
			selection_index += 1
		else:
			break

	_end_selection_turn()


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

	# Add random variance (scaled by volatility)
	var jitter = volatility.get_ctb_jitter() if volatility else 1.0
	speed_value += randf_range(-jitter, jitter)

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

	# AI can advance with a small random chance to pressure the party.
	# NOTE: Enemies do NOT defer. Deferring caused stall bugs (battles frozen
	# when all party members deferred and enemies also randomly deferred).
	# Enemies always attack — defer is a player-only mechanic.
	var should_advance = randf() < 0.15 and combatant.current_ap >= 0  # 15% chance to advance

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
	"""Make AI decision for action selection — behavior varies by monster archetype"""
	# Get available abilities
	var available_abilities = []
	if combatant.job and combatant.job.has("abilities"):
		for ability_id in combatant.job["abilities"]:
			var ability = JobSystem.get_ability(ability_id)
			if not ability.is_empty() and combatant.current_mp >= ability.get("mp_cost", 0):
				available_abilities.append(ability)

	# Masterite bosses use specialized AI
	if combatant.has_meta("masterite") and combatant.get_meta("masterite"):
		return _make_masterite_decision(combatant, alive_allies, alive_enemies, available_abilities)

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

	# Determine AI archetype from stats and abilities
	var archetype = _get_ai_archetype(combatant, available_abilities)
	return _execute_archetype_ai(combatant, archetype, available_abilities, alive_allies, alive_enemies)


func _get_ai_archetype(combatant: Combatant, available_abilities: Array) -> String:
	"""Derive AI behavior archetype from combatant stats and abilities"""
	var healing_abilities = available_abilities.filter(func(a): return a.get("type", "") == "healing")
	var magic_abilities = available_abilities.filter(func(a): return a.get("type", "") == "magic")
	var debuff_abilities = available_abilities.filter(func(a): return a.get("type", "") in ["debuff", "status"])

	# Check for explicit ai_pattern in monster data
	if combatant.has_meta("monster_type"):
		var mt = combatant.get_meta("monster_type", "")
		if EncounterSystem and mt in EncounterSystem.monster_database:
			var ai = EncounterSystem.monster_database[mt].get("ai_pattern", "")
			if ai != "":
				return ai

	# Healer: has healing abilities
	if healing_abilities.size() > 0:
		return "healer"
	# Caster: magic stat significantly higher than attack, has magic abilities
	if combatant.magic > combatant.attack * 1.3 and magic_abilities.size() > 0:
		return "caster"
	# Debuffer: has debuff/status abilities and isn't purely physical
	if debuff_abilities.size() > 0:
		return "debuffer"
	# Tank: high HP and defense relative to attack
	if combatant.defense > combatant.attack * 0.5 and combatant.max_hp >= 150:
		return "tank"
	# Assassin: very fast, targets wounded enemies
	if combatant.speed >= 18:
		return "assassin"
	# Brute: everything else (high attack, straightforward)
	return "brute"


func _execute_archetype_ai(combatant: Combatant, archetype: String, abilities: Array, alive_allies: Array, alive_enemies: Array) -> Dictionary:
	"""Execute AI logic based on archetype"""

	match archetype:
		"healer":
			return _ai_healer(combatant, abilities, alive_allies, alive_enemies)
		"caster":
			return _ai_caster(combatant, abilities, alive_enemies)
		"debuffer":
			return _ai_debuffer(combatant, abilities, alive_allies, alive_enemies)
		"tank":
			return _ai_tank(combatant, abilities, alive_allies, alive_enemies)
		"assassin":
			return _ai_assassin(combatant, abilities, alive_enemies)
		_:
			return _ai_brute(combatant, abilities, alive_enemies)


func _ai_healer(combatant: Combatant, abilities: Array, alive_allies: Array, alive_enemies: Array) -> Dictionary:
	"""Healer AI: prioritize healing low-HP allies, attack only when no one needs healing"""
	var healing_abilities = abilities.filter(func(a): return a.get("type", "") == "healing")
	var low_hp_allies = alive_allies.filter(func(a): return a.get_hp_percentage() < 60.0)

	# Heal the most wounded ally (70% chance when someone is hurt)
	if low_hp_allies.size() > 0 and healing_abilities.size() > 0 and randf() < 0.7:
		low_hp_allies.sort_custom(func(a, b): return a.get_hp_percentage() < b.get_hp_percentage())
		var heal = healing_abilities[randi() % healing_abilities.size()]
		return {
			"type": "ability",
			"combatant": combatant,
			"ability_id": heal.get("id", ""),
			"targets": [low_hp_allies[0]],
			"speed": _compute_action_speed(combatant, "ability", heal)
		}

	# Buff/support abilities if available
	var support_abilities = abilities.filter(func(a): return a.get("type", "") in ["buff", "support"])
	if support_abilities.size() > 0 and randf() < 0.4:
		var buff = support_abilities[randi() % support_abilities.size()]
		var ally = alive_allies[randi() % alive_allies.size()]
		return {
			"type": "ability",
			"combatant": combatant,
			"ability_id": buff.get("id", ""),
			"targets": [ally],
			"speed": _compute_action_speed(combatant, "ability", buff)
		}

	# Fallback: basic attack
	var target = _choose_target(combatant, alive_enemies, {})
	return {"type": "attack", "combatant": combatant, "target": target, "speed": _compute_action_speed(combatant, "attack")}


func _ai_caster(combatant: Combatant, abilities: Array, alive_enemies: Array) -> Dictionary:
	"""Caster AI: strongly prefer magic abilities, target weaknesses when possible"""
	var magic_abilities = abilities.filter(func(a): return a.get("type", "") == "magic")

	# 75% chance to cast a spell if MP allows
	if magic_abilities.size() > 0 and randf() < 0.75:
		# Prefer spells that exploit target weaknesses
		var best_spell = magic_abilities[0]
		var best_score = 0.0
		for spell in magic_abilities:
			var element = spell.get("element", "")
			var score = spell.get("power", 10)
			# Check if any enemy is weak to this element
			for enemy in alive_enemies:
				if element != "" and element in enemy.weaknesses:
					score *= 2.0  # Double score for weakness exploitation
			if score > best_score:
				best_score = score
				best_spell = spell

		var spell_target = _choose_target(combatant, alive_enemies, best_spell)
		return {
			"type": "ability",
			"combatant": combatant,
			"ability_id": best_spell.get("id", ""),
			"targets": [spell_target],
			"speed": _compute_action_speed(combatant, "ability", best_spell)
		}

	# Fallback: basic attack
	var target = _choose_target(combatant, alive_enemies, {})
	return {"type": "attack", "combatant": combatant, "target": target, "speed": _compute_action_speed(combatant, "attack")}


func _ai_debuffer(combatant: Combatant, abilities: Array, alive_allies: Array, alive_enemies: Array) -> Dictionary:
	"""Debuffer AI: apply status effects early, then fall back to damage"""
	var debuff_abilities = abilities.filter(func(a): return a.get("type", "") in ["debuff", "status"])
	var offensive_abilities = abilities.filter(func(a): return a.get("type", "") in ["physical", "magic"])

	# 55% chance to debuff, preferring targets without existing debuffs
	if debuff_abilities.size() > 0 and randf() < 0.55:
		var debuff = debuff_abilities[randi() % debuff_abilities.size()]
		# Pick a target that doesn't already have too many statuses
		var target = alive_enemies[0]
		var fewest_statuses = 999
		for enemy in alive_enemies:
			var status_count = enemy.active_statuses.size() if "active_statuses" in enemy else 0
			if status_count < fewest_statuses:
				fewest_statuses = status_count
				target = enemy
		return {
			"type": "ability",
			"combatant": combatant,
			"ability_id": debuff.get("id", ""),
			"targets": [target],
			"speed": _compute_action_speed(combatant, "ability", debuff)
		}

	# Use offensive ability
	if offensive_abilities.size() > 0 and randf() < 0.4:
		var spell = offensive_abilities[randi() % offensive_abilities.size()]
		var target = _choose_target(combatant, alive_enemies, spell)
		return {
			"type": "ability",
			"combatant": combatant,
			"ability_id": spell.get("id", ""),
			"targets": [target],
			"speed": _compute_action_speed(combatant, "ability", spell)
		}

	# Fallback: basic attack
	var target = _choose_target(combatant, alive_enemies, {})
	return {"type": "attack", "combatant": combatant, "target": target, "speed": _compute_action_speed(combatant, "attack")}


func _ai_tank(combatant: Combatant, abilities: Array, alive_allies: Array, alive_enemies: Array) -> Dictionary:
	"""Tank AI: use defensive abilities, protect allies, heavy single hits"""
	var defensive_abilities = abilities.filter(func(a): return a.get("type", "") in ["buff", "support", "defensive"])
	var physical_abilities = abilities.filter(func(a): return a.get("type", "") == "physical")

	# Use defensive/buff ability if available (40% chance)
	if defensive_abilities.size() > 0 and randf() < 0.4:
		var buff = defensive_abilities[randi() % defensive_abilities.size()]
		# Buff self or lowest-HP ally
		var target = combatant
		var low_hp_allies = alive_allies.filter(func(a): return a.get_hp_percentage() < 50.0)
		if low_hp_allies.size() > 0:
			low_hp_allies.sort_custom(func(a, b): return a.get_hp_percentage() < b.get_hp_percentage())
			target = low_hp_allies[0]
		return {
			"type": "ability",
			"combatant": combatant,
			"ability_id": buff.get("id", ""),
			"targets": [target],
			"speed": _compute_action_speed(combatant, "ability", buff)
		}

	# Use strongest physical ability (50% chance)
	if physical_abilities.size() > 0 and randf() < 0.5:
		physical_abilities.sort_custom(func(a, b): return a.get("power", 0) > b.get("power", 0))
		var ability = physical_abilities[0]
		var target = _choose_target(combatant, alive_enemies, ability)
		return {
			"type": "ability",
			"combatant": combatant,
			"ability_id": ability.get("id", ""),
			"targets": [target],
			"speed": _compute_action_speed(combatant, "ability", ability)
		}

	# Fallback: basic attack — tanks target the highest-threat enemy (most damage)
	var target = alive_enemies[0]
	var highest_atk = 0
	for enemy in alive_enemies:
		var threat = enemy.attack + enemy.magic
		if threat > highest_atk:
			highest_atk = threat
			target = enemy
	return {"type": "attack", "combatant": combatant, "target": target, "speed": _compute_action_speed(combatant, "attack")}


func _ai_assassin(combatant: Combatant, abilities: Array, alive_enemies: Array) -> Dictionary:
	"""Assassin AI: focus wounded targets, use abilities for burst damage"""
	var offensive_abilities = abilities.filter(func(a): return a.get("type", "") in ["physical", "magic"])

	# Target the most wounded enemy (finish them off)
	var target = alive_enemies[0]
	var lowest_hp_pct = 100.0
	for enemy in alive_enemies:
		var hp_pct = enemy.get_hp_percentage()
		if hp_pct < lowest_hp_pct:
			lowest_hp_pct = hp_pct
			target = enemy

	# Use strongest offensive ability on wounded target (60% chance)
	if offensive_abilities.size() > 0 and randf() < 0.6:
		offensive_abilities.sort_custom(func(a, b): return a.get("power", 0) > b.get("power", 0))
		var ability = offensive_abilities[0]
		return {
			"type": "ability",
			"combatant": combatant,
			"ability_id": ability.get("id", ""),
			"targets": [target],
			"speed": _compute_action_speed(combatant, "ability", ability)
		}

	return {"type": "attack", "combatant": combatant, "target": target, "speed": _compute_action_speed(combatant, "attack")}


func _ai_brute(combatant: Combatant, abilities: Array, alive_enemies: Array) -> Dictionary:
	"""Brute AI: mostly physical attacks, occasionally use abilities"""
	# 30% chance to use offensive ability
	if randf() < 0.3:
		var offensive_abilities = abilities.filter(
			func(a): return a.get("type", "") in ["physical", "magic"]
		)
		if offensive_abilities.size() > 0:
			var ability = offensive_abilities[randi() % offensive_abilities.size()]
			var target = _choose_target(combatant, alive_enemies, ability)
			return {
				"type": "ability",
				"combatant": combatant,
				"ability_id": ability.get("id", ""),
				"targets": [target],
				"speed": _compute_action_speed(combatant, "ability", ability)
			}

	# Default: basic attack, random target
	var target = _choose_target(combatant, alive_enemies, {})
	return {"type": "attack", "combatant": combatant, "target": target, "speed": _compute_action_speed(combatant, "attack")}


func _make_masterite_decision(combatant: Combatant, alive_allies: Array, alive_enemies: Array, available_abilities: Array) -> Dictionary:
	"""Specialized AI for Masterite bosses - each type fights differently.
	Phase escalation: behavior intensifies at 66% and 33% HP thresholds."""
	var masterite_type = combatant.get_meta("masterite_type", "")
	var hp_pct = combatant.get_hp_percentage()

	# Phase escalation: track and announce phase transitions
	var battle_phase = combatant.get_meta("masterite_battle_phase", 1)
	var new_phase = 1
	if hp_pct < 33.0:
		new_phase = 3
	elif hp_pct < 66.0:
		new_phase = 2
	if new_phase > battle_phase:
		combatant.set_meta("masterite_battle_phase", new_phase)
		var phase_names = {2: "enraged", 3: "desperate"}
		battle_log_message.emit("[color=red]★ %s becomes %s! ★[/color]" % [combatant.combatant_name, phase_names.get(new_phase, "?")])
		# Phase transition: refresh proclamation buff
		combatant.active_buffs.clear()

	# Helper to find ability by ID from available list
	var find_ability = func(id: String) -> Dictionary:
		for a in available_abilities:
			if a.get("id", "") == id:
				return a
		return {}

	# All Masterites open with proclamation if they have no buffs yet
	if combatant.active_buffs.is_empty():
		var proc = find_ability.call("masterite_proclamation")
		if not proc.is_empty():
			return {"type": "ability", "combatant": combatant, "ability_id": "masterite_proclamation", "targets": [combatant], "speed": _compute_action_speed(combatant, "ability", proc)}

	match masterite_type:
		"warden":
			# DEFENSIVE WALL — iron guard, endurance test, crushing blow
			# Phase 2+: guard threshold rises, judgment unlocks
			# Phase 3: advance with guard+crushing combo, endurance every turn
			var warden_guard_threshold = 60.0 if battle_phase == 1 else 80.0
			# Phase 3: advance combo — iron guard then crushing blow in one turn
			if battle_phase >= 3 and combatant.current_ap >= 1 and randf() < 0.4:
				var guard = find_ability.call("masterite_iron_guard")
				var crush = find_ability.call("masterite_crushing_blow")
				if not guard.is_empty() and not crush.is_empty():
					var target = _choose_target(combatant, alive_enemies, {})
					battle_log_message.emit("[color=gray]The Warden braces and swings...[/color]")
					return {"type": "advance", "combatant": combatant, "actions": [
						{"type": "ability", "ability_id": "masterite_iron_guard", "targets": [combatant]},
						{"type": "ability", "ability_id": "masterite_crushing_blow", "targets": [target]},
					], "speed": _compute_action_speed(combatant, "attack")}
			if hp_pct < warden_guard_threshold and not find_ability.call("masterite_iron_guard").is_empty():
				battle_log_message.emit("[color=gray]The Warden raises its shield...[/color]")
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_iron_guard", "targets": [combatant], "speed": _compute_action_speed(combatant, "ability")}
			var endurance_chance = [0.4, 0.6, 0.85][battle_phase - 1]
			if randf() < endurance_chance and not find_ability.call("masterite_endurance_test").is_empty():
				battle_log_message.emit("[color=gray]The Warden tests your resolve...[/color]")
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_endurance_test", "targets": alive_enemies, "speed": _compute_action_speed(combatant, "ability")}
			if randf() < 0.6 and not find_ability.call("masterite_crushing_blow").is_empty():
				var target = _choose_target(combatant, alive_enemies, {})
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_crushing_blow", "targets": [target], "speed": _compute_action_speed(combatant, "ability")}
			if battle_phase >= 2 and not find_ability.call("masterite_judgment").is_empty():
				battle_log_message.emit("[color=gray]The Warden passes judgment...[/color]")
				var target = _choose_target(combatant, alive_enemies, {})
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_judgment", "targets": [target], "speed": _compute_action_speed(combatant, "ability")}

		"arbiter":
			# AGGRESSIVE EXECUTIONER — counter stance, precise strike, execution on wounded
			# Phase 2+: execution threshold rises, more aggressive
			# Phase 3: advance burst combos, execution on anyone below 60%
			var has_atk_buff = combatant.active_buffs.any(func(b): return b.get("stat") == "attack")
			if not has_atk_buff and not find_ability.call("masterite_counter_stance").is_empty():
				battle_log_message.emit("[color=gray]The Arbiter assumes a fighting stance...[/color]")
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_counter_stance", "targets": [combatant], "speed": _compute_action_speed(combatant, "ability")}
			var exec_threshold = [30.0, 50.0, 60.0][battle_phase - 1]
			var low_targets = alive_enemies.filter(func(e): return e.get_hp_percentage() < exec_threshold)
			if low_targets.size() > 0 and not find_ability.call("masterite_execution").is_empty():
				low_targets.sort_custom(func(a, b): return a.get_hp_percentage() < b.get_hp_percentage())
				battle_log_message.emit("[color=gray]The Arbiter locks onto %s...[/color]" % low_targets[0].combatant_name)
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_execution", "targets": [low_targets[0]], "speed": _compute_action_speed(combatant, "ability")}
			# Phase 3: advance burst — precise strike + measured blow
			if battle_phase >= 3 and combatant.current_ap >= 1 and randf() < 0.5:
				var precise = find_ability.call("masterite_precise_strike")
				var measured = find_ability.call("masterite_measured_blow")
				if not precise.is_empty() and not measured.is_empty():
					var target = _choose_target(combatant, alive_enemies, {})
					battle_log_message.emit("[color=gray]The Arbiter unleashes a flurry![/color]")
					return {"type": "advance", "combatant": combatant, "actions": [
						{"type": "ability", "ability_id": "masterite_precise_strike", "targets": [target]},
						{"type": "ability", "ability_id": "masterite_measured_blow", "targets": alive_enemies},
					], "speed": _compute_action_speed(combatant, "attack")}
			var strike_chance = [0.5, 0.65, 0.8][battle_phase - 1]
			if randf() < strike_chance and not find_ability.call("masterite_precise_strike").is_empty():
				var target = _choose_target(combatant, alive_enemies, {})
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_precise_strike", "targets": [target], "speed": _compute_action_speed(combatant, "ability")}
			var aoe_chance = [0.4, 0.55, 0.75][battle_phase - 1]
			if randf() < aoe_chance and not find_ability.call("masterite_measured_blow").is_empty():
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_measured_blow", "targets": alive_enemies, "speed": _compute_action_speed(combatant, "ability")}

		"tempo":
			# SPEED MANIPULATOR — haste self, slow enemies, rapid strikes
			# Phase 2+: time tax more frequent, multi-slow
			# Phase 3: advance double-strike, relentless speed control
			var has_spd_buff = combatant.active_buffs.any(func(b): return b.get("stat") == "speed")
			if not has_spd_buff and not find_ability.call("masterite_haste").is_empty():
				battle_log_message.emit("[color=gray]Time warps around the Tempo...[/color]")
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_haste", "targets": [combatant], "speed": _compute_action_speed(combatant, "ability")}
			# Phase 3: advance combo — haste + double quick strike
			if battle_phase >= 3 and combatant.current_ap >= 1 and randf() < 0.45:
				var quick = find_ability.call("masterite_quick_strike")
				if not quick.is_empty():
					var t1 = _choose_target(combatant, alive_enemies, {})
					var t2 = alive_enemies[randi() % alive_enemies.size()]
					battle_log_message.emit("[color=gray]The Tempo moves in a blur![/color]")
					return {"type": "advance", "combatant": combatant, "actions": [
						{"type": "ability", "ability_id": "masterite_quick_strike", "targets": [t1]},
						{"type": "ability", "ability_id": "masterite_quick_strike", "targets": [t2]},
					], "speed": _compute_action_speed(combatant, "attack")}
			var tax_chance = [0.35, 0.5, 0.7][battle_phase - 1]
			if randf() < tax_chance and not find_ability.call("masterite_time_tax").is_empty():
				battle_log_message.emit("[color=gray]The Tempo steals your time...[/color]")
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_time_tax", "targets": alive_enemies, "speed": _compute_action_speed(combatant, "ability")}
			var slow_chance = [0.4, 0.55, 0.7][battle_phase - 1]
			if randf() < slow_chance and not find_ability.call("masterite_slow").is_empty():
				var fastest = alive_enemies.duplicate()
				fastest.sort_custom(func(a, b): return a.speed > b.speed)
				var slow_targets = [fastest[0]] if battle_phase < 3 else fastest.slice(0, mini(2, fastest.size()))
				battle_log_message.emit("[color=gray]The Tempo drags %s through molasses...[/color]" % slow_targets[0].combatant_name)
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_slow", "targets": slow_targets, "speed": _compute_action_speed(combatant, "ability")}
			if not find_ability.call("masterite_quick_strike").is_empty():
				var target = _choose_target(combatant, alive_enemies, {})
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_quick_strike", "targets": [target], "speed": _compute_action_speed(combatant, "ability")}

		"curator":
			# TACTICAL RESOURCE DENIAL — dispel buffs, drain MP, audit for damage
			# Phase 2+: targets highest-threat player, multi-dispel
			# Phase 3: advance drain+audit combo, total resource starvation
			var buffed_targets = alive_enemies.filter(func(e): return e.active_buffs.size() > 0)
			if buffed_targets.size() > 0 and not find_ability.call("masterite_dispel").is_empty():
				var dispel_targets = [buffed_targets[0]] if battle_phase < 3 else buffed_targets.slice(0, mini(3, buffed_targets.size()))
				battle_log_message.emit("[color=gray]The Curator nullifies your enhancements...[/color]")
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_dispel", "targets": dispel_targets, "speed": _compute_action_speed(combatant, "ability")}
			# Phase 3: advance combo — mana drain then audit the drained target
			if battle_phase >= 3 and combatant.current_ap >= 1 and randf() < 0.45:
				var drain = find_ability.call("masterite_mana_drain")
				var audit = find_ability.call("masterite_audit")
				if not drain.is_empty() and not audit.is_empty():
					var mp_sorted = alive_enemies.duplicate()
					mp_sorted.sort_custom(func(a, b): return a.current_mp > b.current_mp)
					battle_log_message.emit("[color=gray]The Curator drains and audits %s![/color]" % mp_sorted[0].combatant_name)
					return {"type": "advance", "combatant": combatant, "actions": [
						{"type": "ability", "ability_id": "masterite_mana_drain", "targets": [mp_sorted[0]]},
						{"type": "ability", "ability_id": "masterite_audit", "targets": [mp_sorted[0]]},
					], "speed": _compute_action_speed(combatant, "attack")}
			var drain_chance = [0.45, 0.6, 0.8][battle_phase - 1]
			if randf() < drain_chance and not find_ability.call("masterite_mana_drain").is_empty():
				var mp_sorted = alive_enemies.duplicate()
				mp_sorted.sort_custom(func(a, b): return a.current_mp > b.current_mp)
				battle_log_message.emit("[color=gray]The Curator eyes %s's mana reserves...[/color]" % mp_sorted[0].combatant_name)
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_mana_drain", "targets": [mp_sorted[0]], "speed": _compute_action_speed(combatant, "ability")}
			var cut_chance = [0.4, 0.55, 0.7][battle_phase - 1]
			if randf() < cut_chance and not find_ability.call("masterite_resource_cut").is_empty():
				var target = _choose_target(combatant, alive_enemies, {})
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_resource_cut", "targets": [target], "speed": _compute_action_speed(combatant, "ability")}
			if not find_ability.call("masterite_audit").is_empty():
				var target = _choose_target(combatant, alive_enemies, {})
				return {"type": "ability", "combatant": combatant, "ability_id": "masterite_audit", "targets": [target], "speed": _compute_action_speed(combatant, "ability")}

	# Fallback: basic attack
	var target = _choose_target(combatant, alive_enemies, {})
	return {"type": "attack", "combatant": combatant, "target": target, "speed": _compute_action_speed(combatant, "attack")}


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
			var alive = _get_alive_enemies()
			_queue_action({
				"combatant": combatant,
				"type": "attack",
				"target": alive[0] if alive.size() > 0 else null,
				"speed": ACTION_SPEEDS["attack"] + combatant.speed
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
	var combatant = action.get("combatant") as Combatant

	# Skip if combatant died or action is invalid
	if not combatant or not combatant.is_alive:
		_execute_next_action()
		return

	current_combatant = combatant
	current_state = BattleState.PROCESSING_ACTION

	# Status effect behavioral checks
	if combatant.has_status("stun"):
		combatant.remove_status("stun")
		battle_log_message.emit("[color=yellow]%s[/color] is [color=orange]stunned[/color] and cannot act!" % combatant.combatant_name)
		action_executing.emit(combatant, {"type": "stun_skip"})
		_execute_next_action()
		return

	if combatant.has_status("sleep"):
		# 30% chance to wake up each turn
		if randf() < 0.3:
			combatant.remove_status("sleep")
			battle_log_message.emit("[color=yellow]%s[/color] woke up!" % combatant.combatant_name)
		else:
			battle_log_message.emit("[color=yellow]%s[/color] is [color=cyan]asleep[/color]..." % combatant.combatant_name)
			action_executing.emit(combatant, {"type": "sleep_skip"})
			_execute_next_action()
			return

	if combatant.has_status("confuse"):
		# 40% chance to snap out each turn
		if randf() < 0.4:
			combatant.remove_status("confuse")
			battle_log_message.emit("[color=yellow]%s[/color] snapped out of confusion!" % combatant.combatant_name)
		else:
			# Attack a random target (could be ally or enemy)
			var all_alive = []
			for p in player_party:
				if p and p.is_alive:
					all_alive.append(p)
			for e in enemy_party:
				if e and e.is_alive:
					all_alive.append(e)
			if all_alive.size() > 0:
				var random_target = all_alive[randi() % all_alive.size()]
				battle_log_message.emit("[color=yellow]%s[/color] is [color=purple]confused[/color] and attacks wildly!" % combatant.combatant_name)
				_execute_attack(combatant, random_target)
				return

	if combatant.has_status("fear"):
		# 25% chance to overcome fear each turn
		if randf() < 0.25:
			combatant.remove_status("fear")
			battle_log_message.emit("[color=yellow]%s[/color] overcame their fear!" % combatant.combatant_name)
		elif randf() < 0.5:
			battle_log_message.emit("[color=yellow]%s[/color] is [color=gray]paralyzed with fear[/color]!" % combatant.combatant_name)
			action_executing.emit(combatant, {"type": "fear_skip"})
			_execute_next_action()
			return
		# If not skipping, fear still applies — attack proceeds but damage reduction handled elsewhere

	if combatant.has_status("charm"):
		# 35% chance to break free each turn
		if randf() < 0.35:
			combatant.remove_status("charm")
			battle_log_message.emit("[color=yellow]%s[/color] broke free from charm!" % combatant.combatant_name)
		else:
			battle_log_message.emit("[color=yellow]%s[/color] is [color=pink]charmed[/color] and won't act!" % combatant.combatant_name)
			action_executing.emit(combatant, {"type": "charm_skip"})
			_execute_next_action()
			return

	# Execute based on action type
	match action.get("type", ""):
		"attack":
			_execute_attack(combatant, action.get("target"))
		"ability":
			_execute_ability(combatant, action.get("ability_id", ""), action.get("targets", []))
		"item":
			_execute_item(combatant, action.get("item_id", ""), action.get("targets", []))
		"defer":
			_execute_defer(combatant)
		"summon":
			_execute_summon(combatant, action.get("monster_type", "slime"))
		"advance":
			_execute_advance(combatant, action)
			return  # Advance handles its own continuation
		"group":
			_execute_group_action(action)
			return  # Group handles its own continuation
		_:
			push_warning("BattleManager: Unknown action type '%s'" % action.get("type", ""))
			# Do NOT return here — fall through to keep the execution chain alive.
			# A stray unknown action must not freeze the whole battle.
			_execute_next_action()
			return

	# Log player action for adaptive AI pattern detection
	_log_player_action(combatant, action)
	action_executed.emit(combatant, action, action.get("targets", [action.get("target")]))

	# Delay between actions - long enough for animations to complete
	if turbo_mode:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(0.7).timeout
	if not is_instance_valid(self):
		return
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


func _execute_group_action(action: Dictionary) -> void:
	"""Execute group attack — all participants strike together"""
	var participants: Array = action.get("participants", [])
	var group_type: String = action.get("group_type", "all_out_attack")
	var alive_enemies: Array[Combatant] = enemy_party.filter(func(e): return e.is_alive)

	if alive_enemies.is_empty():
		_execute_next_action()
		return

	group_attack_executing.emit(participants, group_type, alive_enemies)
	print("[GROUP] Executing %s with %d participants vs %d enemies" % [
		group_type, participants.size(), alive_enemies.size()])

	# Determine AP cost per participant
	var ap_cost: int = 4 if group_type == "limit_break" else (2 if group_type == "combo_magic" else 1)

	if group_type == "combo_magic":
		_execute_combo_magic(participants, alive_enemies, ap_cost)
	elif group_type == "formation":
		var formation_id: String = action.get("formation_id", "")
		_execute_formation_special(participants, alive_enemies, formation_id)
	else:
		_execute_physical_group(participants, alive_enemies, group_type, ap_cost)

	# --- Vulnerability Window: all participants become exposed ---
	_apply_vulnerability_window(participants)

	_log_player_action(participants[0] if participants.size() > 0 else null, action)
	action_executed.emit(
		participants[0] if participants.size() > 0 else null,
		action,
		alive_enemies
	)

	if _check_victory_conditions():
		return

	if turbo_mode:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(0.7).timeout
	if not is_instance_valid(self):
		return
	_execute_next_action()


func _execute_physical_group(participants: Array, alive_enemies: Array[Combatant], group_type: String, ap_cost: int) -> void:
	"""Execute All-Out Attack or Limit Break — physical combined damage"""
	var total_power: float = 0.0
	for p in participants:
		if not (p is Combatant) or not p.is_alive:
			continue
		p.spend_ap(ap_cost)
		total_power += p.attack

	var scale: float = pow(participants.size(), 1.5)
	for enemy in alive_enemies:
		if not enemy.is_alive:
			continue
		var raw_damage: int = int(total_power * scale / max(1.0, float(alive_enemies.size())))
		var mitigated: int = max(1, raw_damage - enemy.defense)
		enemy.take_damage(mitigated)
		damage_dealt.emit(enemy, mitigated, false, "", 1.0)
		battle_log_message.emit("[color=orange]Group %s hits %s for %d![/color]" % [
			group_type, enemy.combatant_name, mitigated])


func _execute_combo_magic(participants: Array, alive_enemies: Array[Combatant], ap_cost: int) -> void:
	"""Execute Combo Magic — fuse party elements for massive magic damage"""
	# Spend AP and sum magic power
	var total_magic: float = 0.0
	for p in participants:
		if not (p is Combatant) or not p.is_alive:
			continue
		p.spend_ap(ap_cost)
		total_magic += p.get_buffed_stat("magic", p.magic)

	# Resolve what combo we get from the party's available elements
	var elements = _get_party_elements(participants)
	var combo = _resolve_combo_element(elements)
	var combo_name: String = combo.get("name", "Magic Burst")
	var combo_element: String = combo.get("element", "")
	var bonus: String = combo.get("bonus_effect", "")

	var scale: float = pow(participants.size(), 1.5)
	battle_log_message.emit("[color=magenta]★ %s! ★[/color]" % combo_name)

	for enemy in alive_enemies:
		if not enemy.is_alive:
			continue
		var base_damage: int = int(total_magic * scale / max(1.0, float(alive_enemies.size())))

		# Apply combo bonus effects
		var effective_def: float = float(enemy.defense)
		match bonus:
			"armor_pierce":  # Steam: halve defense
				effective_def *= 0.5
			"defense_ignore":  # Shatter: skip defense entirely
				effective_def = 0.0
			"raw_boost":  # Plasma: 1.5x raw damage
				base_damage = int(base_damage * 1.5)

		var mitigated: int = max(1, base_damage - int(effective_def))

		# Apply elemental weakness/resistance
		var elemental_mod: float = 1.0
		if bonus == "all_weakness":  # Prism: find best weakness multiplier
			var best_mod: float = 1.0
			for weakness in enemy.elemental_weaknesses:
				best_mod = max(best_mod, 1.5)
			# Stack with number of weaknesses for true one-shot potential
			if enemy.elemental_weaknesses.size() > 0:
				elemental_mod = best_mod * (1.0 + 0.25 * (enemy.elemental_weaknesses.size() - 1))
		elif not combo_element.is_empty():
			elemental_mod = enemy.calculate_elemental_modifier(combo_element)

		if elemental_mod == 0.0:
			battle_log_message.emit("[color=gray]%s is immune to %s![/color]" % [enemy.combatant_name, combo_name])
			continue

		var final_damage: int = max(1, int(mitigated * elemental_mod))
		enemy.take_damage(final_damage, true)
		damage_dealt.emit(enemy, final_damage, false, combo_element, elemental_mod)
		battle_log_message.emit("[color=magenta]%s blasts %s for %d![/color]" % [
			combo_name, enemy.combatant_name, final_damage])


func _execute_formation_special(participants: Array, alive_enemies: Array[Combatant], formation_id: String) -> void:
	"""Execute a Formation Special — unique effect based on party job composition"""
	# Spend AP (2 per participant for most formations, 3 for arcane_tempest/chaos_theory)
	var ap_cost = 3 if formation_id in ["arcane_tempest", "chaos_theory"] else 2
	for p in participants:
		if p is Combatant and p.is_alive:
			p.spend_ap(ap_cost)

	var scale: float = pow(participants.size(), 1.5)

	match formation_id:
		"four_heroes":
			# Balanced strike + party heal 25%
			var total_power = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_power += (p.attack + p.get_buffed_stat("magic", p.magic)) * 0.5
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var damage = max(1, int(total_power * scale / max(1.0, float(alive_enemies.size())) - enemy.defense * 0.5))
				enemy.take_damage(damage)
				damage_dealt.emit(enemy, damage, false, "", 1.0)
			# Heal party 25%
			for p in participants:
				if p is Combatant and p.is_alive:
					var heal_amount = int(p.max_hp * 0.25)
					p.heal(heal_amount)
					healing_done.emit(p, heal_amount)
			battle_log_message.emit("[color=cyan]★ Four Heroes — balanced strike + party healed 25%! ★[/color]")

		"arcane_tempest":
			# Massive AoE magic, ignores resistances
			var total_magic = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_magic += p.get_buffed_stat("magic", p.magic)
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				# Ignore resistance — raw magic damage
				var damage = max(1, int(total_magic * scale / max(1.0, float(alive_enemies.size()))))
				enemy.take_damage(damage, true)
				damage_dealt.emit(enemy, damage, false, "arcane", 1.0)
			battle_log_message.emit("[color=magenta]★ Arcane Tempest — raw magic storm ignores all resistances! ★[/color]")

		"blade_storm":
			# Multi-hit physical, each can crit
			var hit_count = participants.size() * 2  # 2 hits per participant
			for _hit in range(hit_count):
				var attacker = participants[randi() % participants.size()]
				if not (attacker is Combatant) or not attacker.is_alive: continue
				var target = alive_enemies[randi() % alive_enemies.size()]
				if not target.is_alive: continue
				var base_dmg = int(attacker.attack * 0.7)
				var is_crit = randf() < 0.3  # 30% crit chance per hit
				if is_crit:
					base_dmg = int(base_dmg * 1.5)
				var damage = max(1, base_dmg - target.defense / 2)
				target.take_damage(damage)
				damage_dealt.emit(target, damage, is_crit, "", 1.0)
			battle_log_message.emit("[color=orange]★ Blade Storm — %d rapid strikes! ★[/color]" % hit_count)

		"iron_wall":
			# Party-wide DEF buff + crushing AoE
			for p in participants:
				if p is Combatant and p.is_alive:
					p.add_buff("iron_wall_def", "defense", 1.5, 3)
			var total_atk = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_atk += p.attack
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var damage = max(1, int(total_atk * scale * 0.6 / max(1.0, float(alive_enemies.size())) - enemy.defense))
				enemy.take_damage(damage)
				damage_dealt.emit(enemy, damage, false, "", 1.0)
			battle_log_message.emit("[color=cyan]★ Iron Wall — party DEF +50%% (3 turns) + crushing blow! ★[/color]")

		"shadow_strike":
			# Ignores defense, 2x vs full-HP targets
			var total_atk = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_atk += p.attack
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var full_hp_bonus = 2.0 if enemy.current_hp == enemy.max_hp else 1.0
				var damage = int(total_atk * scale * full_hp_bonus / max(1.0, float(alive_enemies.size())))
				damage = max(1, damage)  # Defense ignored
				enemy.take_damage(damage)
				damage_dealt.emit(enemy, damage, false, "", 1.0)
			battle_log_message.emit("[color=purple]★ Shadow Strike — defense ignored! 2x on full HP targets! ★[/color]")

		"chaos_theory":
			# Random massive effect — could buff party, could nuke enemies, could backfire
			var roll = randf()
			if roll < 0.4:
				# Jackpot: massive damage to all enemies
				var total_power = 0.0
				for p in participants:
					if p is Combatant and p.is_alive:
						total_power += (p.attack + p.get_buffed_stat("magic", p.magic))
				for enemy in alive_enemies:
					if not enemy.is_alive: continue
					var damage = max(1, int(total_power * scale * 1.5 / max(1.0, float(alive_enemies.size()))))
					enemy.take_damage(damage, true)
					damage_dealt.emit(enemy, damage, false, "", 1.0)
				battle_log_message.emit("[color=gold]★ Chaos Theory — JACKPOT! Massive damage! ★[/color]")
			elif roll < 0.7:
				# Party buff: all stats +30% for 3 turns
				for p in participants:
					if p is Combatant and p.is_alive:
						p.add_buff("chaos_atk", "attack", 1.3, 3)
						p.add_buff("chaos_def", "defense", 1.3, 3)
						p.add_buff("chaos_spd", "speed", 1.3, 3)
				battle_log_message.emit("[color=gold]★ Chaos Theory — party buffed! ATK/DEF/SPD +30%%! ★[/color]")
			elif roll < 0.9:
				# Moderate damage + heal
				var total_power = 0.0
				for p in participants:
					if p is Combatant and p.is_alive:
						total_power += p.attack
				for enemy in alive_enemies:
					if not enemy.is_alive: continue
					var damage = max(1, int(total_power * scale * 0.8 / max(1.0, float(alive_enemies.size())) - enemy.defense))
					enemy.take_damage(damage)
					damage_dealt.emit(enemy, damage, false, "", 1.0)
				for p in participants:
					if p is Combatant and p.is_alive:
						var heal = int(p.max_hp * 0.15)
						p.heal(heal)
				battle_log_message.emit("[color=yellow]★ Chaos Theory — moderate damage + party heal! ★[/color]")
			else:
				# Backfire: damage own party lightly
				for p in participants:
					if p is Combatant and p.is_alive:
						var self_dmg = int(p.max_hp * 0.1)
						p.take_damage(self_dmg)
						damage_dealt.emit(p, self_dmg, false, "", 1.0)
				battle_log_message.emit("[color=red]★ Chaos Theory — BACKFIRE! Party takes recoil damage! ★[/color]")

		_:
			# Unknown formation — fallback to physical group
			_execute_physical_group(participants, alive_enemies, "all_out_attack", ap_cost)
			battle_log_message.emit("[color=orange]★ Formation attack! ★[/color]")


func _apply_vulnerability_window(participants: Array) -> void:
	"""After a group attack, all participants become exposed — 1.5x damage, -2 AP, can't defer"""
	for p in participants:
		if not (p is Combatant) or not p.is_alive:
			continue
		p.add_status("exposed", 1)
		p.add_status("cannot_defer", 1)
		var old_ap = p.current_ap
		p.current_ap = clampi(-2, -4, 4)
		if p.has_signal("ap_changed"):
			p.ap_changed.emit(old_ap, p.current_ap)
	battle_log_message.emit("[color=red]All participants are now exposed! (-2 AP, 1.5x damage taken)[/color]")


func _get_party_elements(participants: Array) -> Array[String]:
	"""Scan participants' magic abilities and return unique elements"""
	var elements: Array[String] = []
	for p in participants:
		if not (p is Combatant) or not p.is_alive:
			continue
		var job_id: String = p.job.get("id", "") if p.job else ""
		if job_id.is_empty():
			continue
		var ability_ids: Array = JobSystem.get_job_abilities(job_id)
		for ability_id in ability_ids:
			var ability: Dictionary = JobSystem.get_ability(ability_id)
			if ability.get("type", "") == "magic" and ability.has("element"):
				var elem: String = ability["element"]
				if elem not in elements:
					elements.append(elem)
	return elements


func _resolve_combo_element(elements: Array[String]) -> Dictionary:
	"""Resolve which combo fusion results from the party's available elements.
	Returns {name, element, bonus_effect}."""
	if elements.size() >= 3:
		return {"name": "Prism Convergence", "element": "prism", "bonus_effect": "all_weakness"}

	var has_fire = "fire" in elements
	var has_ice = "ice" in elements
	var has_lightning = "lightning" in elements

	if has_fire and has_ice:
		return {"name": "Steam Eruption", "element": "steam", "bonus_effect": "armor_pierce"}
	if has_fire and has_lightning:
		return {"name": "Plasma Storm", "element": "plasma", "bonus_effect": "raw_boost"}
	if has_ice and has_lightning:
		return {"name": "Shatter Nova", "element": "shatter", "bonus_effect": "defense_ignore"}

	# Fallback: single element or non-standard combo
	if elements.size() > 0:
		return {"name": "Arcane Burst", "element": elements[0], "bonus_effect": ""}
	return {"name": "Magic Burst", "element": "", "bonus_effect": ""}


func _execute_advance(combatant: Combatant, advance_action: Dictionary) -> void:
	"""Execute advance action - all queued actions in sequence (each costs 1 AP)"""
	var actions = advance_action.get("actions", []) as Array
	if actions.is_empty():
		return

	# Note: Each action costs 1 AP during execution.
	# Grant +1 AP upfront to represent the natural turn gain — this offsets the cost
	# of the first sub-action so only truly extra actions (2nd, 3rd, 4th) go into debt.
	combatant.gain_ap(1)
	print("%s advances with %d actions!" % [combatant.combatant_name, actions.size()])

	# Execute all actions in sequence (each will spend 1 AP)
	for action in actions:
		if not combatant.is_alive:
			break

		if _check_victory_conditions():
			return

		match action.get("type", ""):
			"attack":
				_execute_attack(combatant, action.get("target"))
			"ability":
				_execute_ability(combatant, action.get("ability_id", ""), action.get("targets", []))
			"item":
				_execute_item(combatant, action.get("item_id", ""), action.get("targets", []))

		# Log player action for adaptive AI pattern detection
		_log_player_action(combatant, action)
		action_executed.emit(combatant, action, action.get("targets", [action.get("target")]))
		if turbo_mode:
			await get_tree().process_frame
		else:
			await get_tree().create_timer(0.5).timeout  # Time for animation
		if not is_instance_valid(self):
			return

	# Continue to next action
	if turbo_mode:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(self):
		return
	if _check_victory_conditions():
		return
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
	# Auto-retarget if original target is dead/invalid
	var actual_target = _retarget_enemy(attacker, target)
	if not actual_target or not is_instance_valid(actual_target):
		print("%s's attack fizzles - no valid targets!" % attacker.combatant_name)
		return

	# Actions cost 1 AP (cancels out natural gain for net 0)
	attacker.spend_ap(1)

	action_executing.emit(attacker, {"type": "attack", "target": actual_target})

	# Miss check: base 10% miss rate, reduced by attacker speed vs target speed
	var base_miss_rate = 0.10
	if attacker.has_status("blind"):
		base_miss_rate += 0.40  # Blind adds 40% miss chance
	var speed_diff = float(attacker.speed - actual_target.speed) / max(actual_target.speed, 1)
	var miss_rate = clamp(base_miss_rate - speed_diff * 0.05, 0.02, 0.60)
	if randf() < miss_rate:
		attack_missed.emit(actual_target)
		var log_msg = "[color=white]%s[/color] attacks [color=red]%s[/color]... [color=gray]MISS![/color]" % [attacker.combatant_name, actual_target.combatant_name]
		battle_log_message.emit(log_msg)
		print("%s attacks %s... MISS!" % [attacker.combatant_name, actual_target.combatant_name])
		return

	var base_damage = attacker.get_buffed_stat("attack", attacker.attack)
	if attacker.has_status("fear"):
		base_damage = int(base_damage * 0.5)
	var vrange = volatility.get_variance_range(attacker) if volatility else Vector2(0.85, 1.15)
	var variance = randf_range(vrange.x, vrange.y)
	var damage = int(base_damage * variance)

	# Critical hit calculation (physical attacks can crit)
	var is_crit = false
	var crit_chance = _calculate_crit_chance(attacker)
	if randf() < crit_chance:
		is_crit = true
		var crit_multiplier = _get_crit_multiplier(attacker)
		damage = int(damage * crit_multiplier)

	# Market Sense passive: scaling damage bonus based on volatility band
	damage = _apply_market_sense(attacker, damage)

	# Tail event check
	if volatility and volatility.check_tail_event():
		if randf() < 0.5:
			damage *= 2
			battle_log_message.emit("[color=magenta]TAIL EVENT: Critical surge![/color]")
		else:
			damage = max(1, damage / 2)
			battle_log_message.emit("[color=cyan]TAIL EVENT: Market correction![/color]")

	# Corruption effect: reality_bending - attacker ignores target defense on hit
	var reality_bending = attacker.has_meta("corruption_effects") and \
		"reality_bending" in attacker.get_meta("corruption_effects", [])
	if reality_bending:
		# Bypass defense: add target's defense directly to damage (nullifying reduction)
		damage += actual_target.defense
		battle_log_message.emit("[color=purple]Reality bends — %s's defenses shatter![/color]" % actual_target.combatant_name)

	var actual_damage = actual_target.take_damage(damage, false)
	damage_dealt.emit(actual_target, actual_damage, is_crit, "", 1.0)

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
	if caster.has_status("fear"):
		base_damage = int(base_damage * 0.5)
	var multiplier = ability.get("damage_multiplier", 1.0)
	var crit_chance = ability.get("crit_chance", 0.0)

	for target in targets:
		if not target or not is_instance_valid(target) or not target.is_alive:
			continue

		# Blind miss check for physical abilities
		if caster.has_status("blind"):
			var blind_miss_rate = 0.40
			if randf() < blind_miss_rate:
				attack_missed.emit(target)
				battle_log_message.emit("[color=white]%s[/color]'s attack misses [color=red]%s[/color]! [color=gray](Blind)[/color]" % [caster.combatant_name, target.combatant_name])
				continue

		var damage = int(base_damage * multiplier)
		var is_crit = false

		if randf() < crit_chance:
			damage = int(damage * _get_crit_multiplier(caster))
			is_crit = true
			print("Critical hit!")

		var phys_vrange = volatility.get_variance_range(caster) if volatility else Vector2(0.9, 1.1)
		damage = int(damage * randf_range(phys_vrange.x, phys_vrange.y))
		damage = _apply_market_sense(caster, damage)
		var actual_damage = target.take_damage(damage, false)
		damage_dealt.emit(target, actual_damage, is_crit, "", 1.0)

		# Track first damage for one-shot detection
		if target in enemy_party:
			_record_first_damage()

		var crit_text = " [color=orange]CRITICAL![/color]" if is_crit else ""
		var log_msg = "  → [color=red]%s[/color] takes [color=yellow]%d[/color] damage!%s" % [target.combatant_name, actual_damage, crit_text]
		battle_log_message.emit(log_msg)
		print("  → %s takes %d damage!" % [target.combatant_name, actual_damage])

		# Apply status effect if ability has one
		var effect = ability.get("effect", "")
		var effect_chance = ability.get("effect_chance", 0.0)
		if effect != "" and effect_chance > 0.0 and randf() < effect_chance:
			target.add_status(effect)
			battle_log_message.emit("%s inflicted %s!" % [caster.combatant_name, effect.capitalize()])


func _execute_magic_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var base_damage = caster.get_buffed_stat("magic", caster.magic)
	var multiplier = ability.get("damage_multiplier", 1.0)
	var element = ability.get("element", "")
	var drain_pct = ability.get("drain_percentage", 0)

	for target in targets:
		if not target or not is_instance_valid(target) or not target.is_alive:
			continue

		var damage = int(base_damage * multiplier)
		var mag_vrange = volatility.get_variance_range(caster) if volatility else Vector2(0.9, 1.1)
		damage = int(damage * randf_range(mag_vrange.x, mag_vrange.y))
		damage = _apply_market_sense(caster, damage)

		# Apply terrain modifier for elemental damage
		var terrain_mod = 1.0
		if element:
			terrain_mod = get_terrain_damage_modifier(element)
			damage = int(damage * terrain_mod)

		var actual_damage = 0
		var elemental_mod = target.calculate_elemental_modifier(element) if element != "" else 1.0
		if element:
			actual_damage = target.take_elemental_damage(damage, element)
		else:
			actual_damage = target.take_damage(damage, true)

		damage_dealt.emit(target, actual_damage, false, element, elemental_mod)

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

		# Apply status effect if ability has one
		var effect = ability.get("effect", "")
		var effect_chance = ability.get("effect_chance", 0.0)
		if effect != "" and effect_chance > 0.0 and randf() < effect_chance:
			target.add_status(effect)
			battle_log_message.emit("%s inflicted %s!" % [caster.combatant_name, effect.capitalize()])


## Critical hit system
## Physical attacks can crit, magic does NOT crit by default

func _calculate_crit_chance(attacker: Combatant) -> float:
	"""Calculate critical hit chance based on speed and equipment"""
	# Base crit chance is 5%
	var base_crit = 0.05

	# Speed adds to crit chance (each 10 speed = +1% crit)
	var speed_bonus = attacker.speed * 0.01

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


## Market Sense passive: scaling damage bonus based on volatility band
func _apply_market_sense(combatant: Combatant, damage: int) -> int:
	"""Apply Market Sense passive bonus if equipped."""
	if not volatility or not "market_sense" in combatant.equipped_passives:
		return damage
	# Stable: +5%, Shifting: +15%, Unstable: +25%, Fractured: +40%
	var band_bonuses = [0.05, 0.15, 0.25, 0.40]
	if volatility.global_band >= 0 and volatility.global_band < band_bonuses.size():
		var bonus = band_bonuses[volatility.global_band]
		return int(damage * (1.0 + bonus))
	return damage


func _nudge_macro_volatility(amount: float) -> void:
	"""Slightly increase macro volatility when speculator abilities are used."""
	var game_state = get_node_or_null("/root/GameState")
	if game_state and "macro_volatility" in game_state:
		game_state.macro_volatility = clampf(game_state.macro_volatility + amount, 0.0, 1.0)


func _execute_healing_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var heal_amount = ability.get("heal_amount", 0)
	var multiplier = GameState.get_constant("healing_multiplier")
	heal_amount = int(heal_amount * multiplier)
	heal_amount = int(heal_amount * (1.0 + caster.get_buffed_stat("magic", caster.magic) / 20.0))

	for target in targets:
		if not target or not is_instance_valid(target) or not target.is_alive:
			continue

		var healed = target.heal(heal_amount)
		healing_done.emit(target, healed)
		var heal_log = "  → [color=white]%s[/color] recovers [color=lime]%d[/color] HP!" % [target.combatant_name, healed]
		battle_log_message.emit(heal_log)
		print("  → %s recovers %d HP!" % [target.combatant_name, healed])


func _execute_revival_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var revive_pct = ability.get("revive_percentage", 50)

	for target in targets:
		if not target or not is_instance_valid(target) or target.is_alive:
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
				if target and is_instance_valid(target) and target.is_alive:
					target.add_status("taunted_%s" % caster.combatant_name)
					print("  → %s is now targeting %s!" % [target.combatant_name, caster.combatant_name])
		"defense_up":
			for target in targets:
				if target and is_instance_valid(target) and target.is_alive:
					target.add_buff("Protect", "defense", stat_modifier, duration)
		"attack_up":
			for target in targets:
				if target and is_instance_valid(target) and target.is_alive:
					target.add_buff("Berserk", "attack", stat_modifier, duration)
		"defense_down":
			for target in targets:
				if target and is_instance_valid(target) and target.is_alive and randf() < success_rate:
					target.add_debuff("Armor Break", "defense", stat_modifier, duration)
		"doom":
			var countdown = ability.get("countdown", 3)
			for target in targets:
				if target and is_instance_valid(target) and target.is_alive:
					target.doom_counter = countdown
					print("  → %s is doomed! %d turns remaining..." % [target.combatant_name, countdown])
		"volatility_up_self":
			if volatility:
				caster.add_buff("Leveraged", "volatility", stat_modifier, duration)
				var recoil_pct = ability.get("recoil_pct", 0.1)
				var recoil_dmg = int(caster.max_hp * recoil_pct)
				caster.take_damage(recoil_dmg, false)
				battle_log_message.emit("[color=gold]%s leverages their position![/color] (-%d HP recoil)" % [caster.combatant_name, recoil_dmg])
				_nudge_macro_volatility(0.02)
		"volatility_up_enemy":
			if volatility:
				for target in targets:
					if target and is_instance_valid(target) and target.is_alive:
						target.add_debuff("Overexposed", "volatility", stat_modifier, duration)
						battle_log_message.emit("[color=gold]%s is overexposed![/color]" % target.combatant_name)
				_nudge_macro_volatility(0.02)
		"volatility_down":
			if volatility:
				for target in targets:
					if target and is_instance_valid(target) and target.is_alive:
						target.add_buff("Hedged", "volatility", stat_modifier, duration)
						battle_log_message.emit("[color=green]%s is hedged![/color]" % target.combatant_name)
		"press_the_edge":
			if volatility:
				var band = volatility.global_band
				var multipliers = [1.5, 2.5, 4.0, 6.0]
				var press_damage = int(caster.get_buffed_stat("magic", caster.magic) * multipliers[band])
				volatility.shift_band(-1)
				for target in targets:
					if target and is_instance_valid(target) and target.is_alive:
						var actual_damage = target.take_damage(press_damage, true)
						damage_dealt.emit(target, actual_damage, false, "", 1.0)
						battle_log_message.emit("[color=magenta]PRESS THE EDGE![/color] %s takes [color=yellow]%d[/color] damage! (Band consumed: %s)" % [target.combatant_name, actual_damage, VolatilitySystem.BAND_NAMES[band]])
				_nudge_macro_volatility(0.03)
		"forecast":
			if volatility:
				var band_name = volatility.get_band_name()
				var tail_pct = volatility.get_tail_event_pct()
				battle_log_message.emit("[color=gold]FORECAST: Band=%s, Tail=%.0f%%, Jitter=±%.1f[/color]" % [band_name, tail_pct, volatility.get_ctb_jitter()])
		"circuit_breaker":
			if volatility:
				volatility.shift_band(-1)
				caster.gain_ap(1)
				battle_log_message.emit("[color=green]CIRCUIT BREAKER![/color] Band reduced, %s gains +1 AP" % caster.combatant_name)
		"steal":
			for target in targets:
				if target and is_instance_valid(target) and target.is_alive:
					if randf() < success_rate:
						var gold_amount = randi_range(5, 50) * (1 + int(target.max_hp / 50.0))
						GameState.add_gold(gold_amount)
						print("  → Stole %d gold from %s!" % [gold_amount, target.combatant_name])
						battle_log_message.emit("[color=yellow]%s stole %d gold from %s![/color]" % [caster.combatant_name, gold_amount, target.combatant_name])
					else:
						print("  → %s failed to steal from %s!" % [caster.combatant_name, target.combatant_name])
						battle_log_message.emit("[color=gray]%s couldn't steal anything from %s.[/color]" % [caster.combatant_name, target.combatant_name])
		"cleanse":
			for target in targets:
				if target and is_instance_valid(target) and target.is_alive:
					var cleansed: Array[String] = []
					var negative_statuses = ["poison", "blind", "sleep", "stun", "burning", "curse", "confuse", "fear", "charm", "doom"]
					for status in negative_statuses:
						if target.has_status(status):
							cleansed.append(status)
							target.remove_status(status)
					if target.doom_counter > 0:
						target.doom_counter = 0
						if "doom" not in cleansed:
							cleansed.append("doom")
					if cleansed.size() > 0:
						battle_log_message.emit("[color=cyan]%s cleansed %s![/color] (%s)" % [caster.combatant_name, target.combatant_name, ", ".join(cleansed)])
					else:
						battle_log_message.emit("[color=gray]%s has no ailments to cleanse.[/color]" % target.combatant_name)
		"regen":
			for target in targets:
				if target and is_instance_valid(target) and target.is_alive:
					target.add_status("regen", duration)
					battle_log_message.emit("[color=green]%s gains Regen![/color] (HP restore for %d turns)" % [target.combatant_name, duration])
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
				if target and is_instance_valid(target) and target.is_alive:
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

	# Check if this is a revival item (e.g. Phoenix Down)
	var item_data = ItemSystem.get_item(item_id) if ItemSystem else {}
	var item_effects = item_data.get("effects", {})
	var is_revival_item = item_effects.get("revive", false)

	# Auto-retarget: revival items need dead allies, others need alive allies
	var retargeted: Array[Combatant] = []
	for t in targets:
		if t is Combatant:
			if is_revival_item:
				# Revival items should keep dead targets, not retarget to alive
				if not t.is_alive:
					retargeted.append(t)
			else:
				var new_target = _retarget_ally(user, t, false)
				if new_target:
					retargeted.append(new_target)

	if retargeted.size() == 0 and targets.size() > 0:
		print("%s's item fizzles - no valid targets!" % user.combatant_name)
		return

	# Actions cost 1 AP (cancels out natural gain for net 0)
	user.spend_ap(1)

	action_executing.emit(user, {"type": "item", "item_id": item_id, "targets": retargeted})

	if ItemSystem and ItemSystem.use_item(user, item_id, retargeted):
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
		"fire_resist", "ice_resist", "lightning_resist":
			# Use fire/ice/lightning resistance buff if available
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
			# Target the healer (usually Mira/cleric)
			var healers = enemies.filter(func(e):
				return e.job and e.job.get("id", "") in ["cleric", "healer"]
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
			if enemies.size() > 0:
				return {
					"type": "attack",
					"combatant": combatant,
					"target": enemies[randi() % enemies.size()],
					"speed": _compute_action_speed(combatant, "attack")
				}
		"generic_counter":
			if abilities.size() > 0 and enemies.size() > 0:
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
