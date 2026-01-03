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

## Battle configuration
var is_autobattle_enabled: bool = false
var autobattle_script: Dictionary = {}
var escape_allowed: bool = true

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


## Battle initialization
func start_battle(players: Array[Combatant], enemies: Array[Combatant]) -> void:
	"""Initialize and start a new battle"""
	current_state = BattleState.STARTING
	current_round = 0

	player_party = players.duplicate()
	enemy_party = enemies.duplicate()
	all_combatants = players + enemies

	# Connect to combatant signals
	for combatant in all_combatants:
		if not combatant.died.is_connected(_on_combatant_died):
			combatant.died.connect(_on_combatant_died.bind(combatant))

	battle_started.emit()
	_start_new_round()


func end_battle(victory: bool) -> void:
	"""End the current battle"""
	if victory:
		current_state = BattleState.VICTORY

		# Award job EXP to player party
		var base_exp = 50
		for combatant in player_party:
			if combatant.is_alive:
				var exp_gained = base_exp
				combatant.gain_job_exp(exp_gained)
				print("%s gained %d job EXP (Level: %d, EXP: %d/%d)" % [
					combatant.combatant_name,
					exp_gained,
					combatant.job_level,
					combatant.job_exp,
					combatant.job_level * 100
				])
	else:
		current_state = BattleState.DEFEAT

	battle_ended.emit(victory)
	_cleanup_battle()


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

	if current_combatant in player_party:
		current_state = BattleState.PLAYER_SELECTING
	else:
		current_state = BattleState.ENEMY_SELECTING

	selection_turn_started.emit(current_combatant)

	# AI selects automatically for enemies (and autobattle players)
	if current_state == BattleState.ENEMY_SELECTING or is_autobattle_enabled:
		_process_ai_selection(current_combatant)


func _end_selection_turn() -> void:
	"""End current combatant's selection turn"""
	if current_combatant:
		selection_turn_ended.emit(current_combatant)

	selection_index += 1
	_process_next_selection()


## Player actions (called from UI)
func player_attack(target: Combatant) -> void:
	"""Queue a basic attack"""
	if current_state != BattleState.PLAYER_SELECTING:
		return

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
	"""Queue Advance action (multiple actions in sequence)"""
	if current_state != BattleState.PLAYER_SELECTING:
		return

	# Mark this as an advance with all actions
	var advance_action = {
		"type": "advance",
		"combatant": current_combatant,
		"actions": actions,
		"speed": _compute_action_speed(current_combatant, "attack"),  # Use attack speed as base
		"ap_cost": actions.size() - 1
	}
	_queue_action(advance_action)
	print("%s chooses to advance (%d actions)" % [current_combatant.combatant_name, actions.size()])
	_end_selection_turn()


# Alias for backwards compatibility
func player_brave(actions: Array[Dictionary]) -> void:
	player_advance(actions)


func player_item(item_id: String, targets: Array) -> void:
	"""Queue an item use"""
	if current_state != BattleState.PLAYER_SELECTING:
		return

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
		# Queue multiple attacks as advance
		var num_actions = mini(randi_range(2, 3), combatant.current_ap + 1)
		var advance_actions: Array[Dictionary] = []
		for i in range(num_actions):
			var target = _choose_target(combatant, alive_enemies, {})
			advance_actions.append({"type": "attack", "target": target})

		var advance_action = {
			"type": "advance",
			"combatant": combatant,
			"actions": advance_actions,
			"speed": _compute_action_speed(combatant, "attack"),
			"ap_cost": num_actions - 1
		}
		_queue_action(advance_action)
		print("%s (AI) chooses to advance (%d actions)" % [combatant.combatant_name, num_actions])
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

	# Sort actions by speed (lower speed value = executes first)
	execution_order = pending_actions.duplicate()
	execution_order.sort_custom(func(a, b): return a["speed"] < b["speed"])

	print("\n[color=yellow]>>> Actions executing![/color]")
	execution_phase_started.emit()

	_execute_next_action()


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
		"advance":
			_execute_advance(combatant, action)
			return  # Advance handles its own continuation

	action_executed.emit(combatant, action, action.get("targets", [action.get("target")]))

	# Small delay between actions for readability
	await get_tree().create_timer(0.3).timeout
	_execute_next_action()


func _execute_defer(combatant: Combatant) -> void:
	"""Execute defer action"""
	combatant.execute_defer()
	print("%s defers (AP: %d)" % [combatant.combatant_name, combatant.current_ap])


func _execute_advance(combatant: Combatant, advance_action: Dictionary) -> void:
	"""Execute advance action - all queued actions in sequence"""
	var actions = advance_action["actions"] as Array
	var ap_cost = advance_action.get("ap_cost", actions.size() - 1)

	# Spend AP for advance
	combatant.spend_ap(ap_cost)
	print("%s advances! (%d actions, AP: %d)" % [combatant.combatant_name, actions.size(), combatant.current_ap])

	# Execute all actions in sequence
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

		action_executed.emit(combatant, action, action.get("targets", [action.get("target")]))
		await get_tree().create_timer(0.2).timeout

	# Continue to next action
	await get_tree().create_timer(0.3).timeout
	_execute_next_action()


func _execute_attack(attacker: Combatant, target: Combatant) -> void:
	"""Execute a basic physical attack"""
	if not target or not target.is_alive:
		return

	action_executing.emit(attacker, {"type": "attack", "target": target})

	var base_damage = attacker.attack
	var variance = randf_range(0.85, 1.15)
	var damage = int(base_damage * variance)

	var actual_damage = target.take_damage(damage, false)
	print("%s attacks %s for %d damage!" % [attacker.combatant_name, target.combatant_name, actual_damage])


func _execute_ability(caster: Combatant, ability_id: String, targets: Array) -> void:
	"""Execute an ability"""
	var ability = JobSystem.get_ability(ability_id)
	if ability.is_empty():
		print("Error: Unknown ability %s" % ability_id)
		return

	if not JobSystem.can_use_ability(caster, ability_id):
		print("%s cannot use %s" % [caster.combatant_name, ability["name"]])
		return

	var mp_cost = ability.get("mp_cost", 0)
	if not caster.spend_mp(mp_cost):
		print("%s doesn't have enough MP!" % caster.combatant_name)
		return

	action_executing.emit(caster, {"type": "ability", "ability_id": ability_id, "targets": targets})
	print("%s uses %s!" % [caster.combatant_name, ability["name"]])

	match ability["type"]:
		"physical":
			_execute_physical_ability(caster, ability, targets)
		"magic":
			_execute_magic_ability(caster, ability, targets)
		"healing":
			_execute_healing_ability(caster, ability, targets)
		"revival":
			_execute_revival_ability(caster, ability, targets)
		"support":
			_execute_support_ability(caster, ability, targets)
		"meta":
			_execute_meta_ability(caster, ability, targets)
		"escape":
			_execute_escape_ability(caster, ability)
		_:
			print("Unknown ability type: %s" % ability["type"])


func _execute_physical_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var base_damage = caster.get_buffed_stat("attack", caster.attack)
	var multiplier = ability.get("damage_multiplier", 1.0)
	var crit_chance = ability.get("crit_chance", 0.0)

	for target in targets:
		if not target or not target.is_alive:
			continue

		var damage = int(base_damage * multiplier)

		if randf() < crit_chance:
			damage = int(damage * 2.0)
			print("Critical hit!")

		damage = int(damage * randf_range(0.9, 1.1))
		var actual_damage = target.take_damage(damage, false)
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

		var actual_damage = 0
		if element:
			actual_damage = target.take_elemental_damage(damage, element)
		else:
			actual_damage = target.take_damage(damage, true)

		print("  → %s takes %d %s damage!" % [target.combatant_name, actual_damage, element if element else "magic"])

		if drain_pct > 0:
			var drained = int(actual_damage * drain_pct / 100.0)
			caster.heal(drained)
			print("  → %s drains %d HP!" % [caster.combatant_name, drained])


func _execute_healing_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	var heal_amount = ability.get("heal_amount", 0)
	var multiplier = GameState.get_constant("healing_multiplier")
	heal_amount = int(heal_amount * multiplier)

	for target in targets:
		if not target or not target.is_alive:
			continue

		var healed = target.heal(heal_amount)
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
	if not user.has_item(item_id):
		print("%s doesn't have item: %s" % [user.combatant_name, item_id])
		return

	action_executing.emit(user, {"type": "item", "item_id": item_id, "targets": targets})

	var combatant_targets: Array[Combatant] = []
	for t in targets:
		if t is Combatant:
			combatant_targets.append(t)

	if ItemSystem.use_item(user, item_id, combatant_targets):
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
