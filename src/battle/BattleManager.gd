extends Node

## BattleManager - Singleton that orchestrates turn-based combat
## Handles turn order, action resolution, and battle flow

signal battle_started()
signal battle_ended(victory: bool)
signal turn_started(combatant: Combatant)
signal turn_ended(combatant: Combatant)
signal round_started(round_num: int)
signal action_executed(combatant: Combatant, action: Dictionary, targets: Array)

enum BattleState {
	INACTIVE,
	STARTING,
	PLAYER_TURN,
	ENEMY_TURN,
	PROCESSING_ACTIONS,
	VICTORY,
	DEFEAT
}

var current_state: BattleState = BattleState.INACTIVE
var current_round: int = 0

## Battle participants
var player_party: Array[Combatant] = []
var enemy_party: Array[Combatant] = []
var all_combatants: Array[Combatant] = []

## Turn order
var turn_order: Array[Combatant] = []
var current_turn_index: int = 0
var current_combatant: Combatant = null

## Battle configuration
var is_autobattle_enabled: bool = false
var escape_allowed: bool = true


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

	# Calculate initial turn order
	_calculate_turn_order()

	battle_started.emit()
	_start_new_round()


func end_battle(victory: bool) -> void:
	"""End the current battle"""
	if victory:
		current_state = BattleState.VICTORY
	else:
		current_state = BattleState.DEFEAT

	battle_ended.emit(victory)
	_cleanup_battle()


func _cleanup_battle() -> void:
	"""Clean up battle state"""
	# Disconnect signals
	for combatant in all_combatants:
		if combatant.died.is_connected(_on_combatant_died):
			combatant.died.disconnect(_on_combatant_died)

	player_party.clear()
	enemy_party.clear()
	all_combatants.clear()
	turn_order.clear()
	current_turn_index = 0
	current_combatant = null


## Turn order management
func _calculate_turn_order() -> void:
	"""Calculate turn order based on speed stat"""
	turn_order = all_combatants.duplicate()

	# Sort by speed (descending)
	turn_order.sort_custom(func(a, b): return a.speed > b.speed)

	# Add some randomization
	for combatant in turn_order:
		combatant.turn_order_value = combatant.speed + randf_range(-2.0, 2.0)

	turn_order.sort_custom(func(a, b): return a.turn_order_value > b.turn_order_value)


func _start_new_round() -> void:
	"""Start a new round of combat"""
	current_round += 1
	current_turn_index = 0

	# Reset combatants for new round
	for combatant in all_combatants:
		if combatant.is_alive:
			combatant.reset_for_new_round()

	# Recalculate turn order each round
	_calculate_turn_order()

	round_started.emit(current_round)
	_process_next_turn()


func _process_next_turn() -> void:
	"""Process the next combatant's turn"""
	# Skip dead combatants
	while current_turn_index < turn_order.size():
		current_combatant = turn_order[current_turn_index]
		if current_combatant.is_alive:
			break
		current_turn_index += 1

	# Check if round is over
	if current_turn_index >= turn_order.size():
		_start_new_round()
		return

	# Check for battle end conditions
	if _check_victory_conditions():
		return

	# Start the turn
	_start_combatant_turn(current_combatant)


func _start_combatant_turn(combatant: Combatant) -> void:
	"""Start a specific combatant's turn"""
	combatant.start_turn()

	# Check if this combatant has AP debt (from Brave)
	if combatant.current_ap < 0:
		# Skip turn to pay AP debt
		combatant.gain_ap(1)
		print("%s is paying AP debt (%d -> %d)" % [combatant.combatant_name, combatant.current_ap - 1, combatant.current_ap])
		_end_combatant_turn(combatant)
		return

	# Determine whose turn it is
	if combatant in player_party:
		current_state = BattleState.PLAYER_TURN
	else:
		current_state = BattleState.ENEMY_TURN

	turn_started.emit(combatant)

	# Process queued actions (from Brave)
	if combatant.queued_actions.size() > 0:
		var action = combatant.queued_actions.pop_front()
		_execute_action(combatant, action)
	elif current_state == BattleState.ENEMY_TURN or is_autobattle_enabled:
		# AI or autobattle turn
		_process_ai_turn(combatant)


func _end_combatant_turn(combatant: Combatant) -> void:
	"""End the current combatant's turn"""
	combatant.end_turn()
	turn_ended.emit(combatant)

	current_turn_index += 1
	_process_next_turn()


## Player actions (called from UI)
func player_attack(target: Combatant) -> void:
	"""Execute a basic attack"""
	if current_state != BattleState.PLAYER_TURN:
		return

	var action = {
		"type": "attack",
		"target": target
	}
	_execute_action(current_combatant, action)


func player_use_ability(ability_id: String, targets: Array) -> void:
	"""Execute an ability"""
	if current_state != BattleState.PLAYER_TURN:
		return

	var action = {
		"type": "ability",
		"ability_id": ability_id,
		"targets": targets
	}
	_execute_action(current_combatant, action)


func player_default() -> void:
	"""Execute Default action (skip turn, gain AP, defend)"""
	if current_state != BattleState.PLAYER_TURN:
		return

	current_combatant.execute_default()
	print("%s uses Default (AP: %d)" % [current_combatant.combatant_name, current_combatant.current_ap])
	_end_combatant_turn(current_combatant)


func player_brave(actions: Array[Dictionary]) -> void:
	"""Execute Brave action (queue multiple actions)"""
	if current_state != BattleState.PLAYER_TURN:
		return

	current_combatant.execute_brave(actions)
	print("%s uses Brave (%d actions, AP: %d)" % [current_combatant.combatant_name, actions.size(), current_combatant.current_ap])

	# Execute first action immediately
	if current_combatant.queued_actions.size() > 0:
		var first_action = current_combatant.queued_actions.pop_front()
		_execute_action(current_combatant, first_action)


func player_item(item_id: String, targets: Array) -> void:
	"""Use an item"""
	if current_state != BattleState.PLAYER_TURN:
		return

	var action = {
		"type": "item",
		"item_id": item_id,
		"targets": targets
	}
	_execute_action(current_combatant, action)


## Action execution
func _execute_action(combatant: Combatant, action: Dictionary) -> void:
	"""Execute a combat action"""
	current_state = BattleState.PROCESSING_ACTIONS

	match action["type"]:
		"attack":
			_execute_attack(combatant, action["target"])
		"ability":
			_execute_ability(combatant, action["ability_id"], action.get("targets", []))
		"item":
			_execute_item(combatant, action["item_id"], action.get("targets", []))
		"defend":
			combatant.execute_default()

	action_executed.emit(combatant, action, action.get("targets", [action.get("target")]))

	# Check for victory/defeat after action
	if _check_victory_conditions():
		return

	_end_combatant_turn(combatant)


func _execute_attack(attacker: Combatant, target: Combatant) -> void:
	"""Execute a basic physical attack"""
	if not target or not target.is_alive:
		return

	# Basic damage formula
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

	# Check if caster can use this ability
	if not JobSystem.can_use_ability(caster, ability_id):
		print("%s cannot use %s" % [caster.combatant_name, ability["name"]])
		return

	# Spend MP
	var mp_cost = ability.get("mp_cost", 0)
	if not caster.spend_mp(mp_cost):
		print("%s doesn't have enough MP!" % caster.combatant_name)
		return

	print("%s uses %s!" % [caster.combatant_name, ability["name"]])

	# Execute based on ability type
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
	"""Execute a physical ability"""
	var base_damage = caster.get_buffed_stat("attack", caster.attack)
	var multiplier = ability.get("damage_multiplier", 1.0)
	var crit_chance = ability.get("crit_chance", 0.0)

	for target in targets:
		if not target or not target.is_alive:
			continue

		var damage = int(base_damage * multiplier)

		# Critical hit check
		if randf() < crit_chance:
			damage = int(damage * 2.0)
			print("Critical hit!")

		# Apply variance
		damage = int(damage * randf_range(0.9, 1.1))

		var actual_damage = target.take_damage(damage, false)
		print("  → %s takes %d damage!" % [target.combatant_name, actual_damage])


func _execute_magic_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	"""Execute a magic ability"""
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

		# Drain life
		if drain_pct > 0:
			var drained = int(actual_damage * drain_pct / 100.0)
			caster.heal(drained)
			print("  → %s drains %d HP!" % [caster.combatant_name, drained])


func _execute_healing_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	"""Execute a healing ability"""
	var heal_amount = ability.get("heal_amount", 0)
	var multiplier = GameState.get_constant("healing_multiplier")

	heal_amount = int(heal_amount * multiplier)

	for target in targets:
		if not target or not target.is_alive:
			continue

		var healed = target.heal(heal_amount)
		print("  → %s recovers %d HP!" % [target.combatant_name, healed])


func _execute_revival_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	"""Execute a revival ability"""
	var revive_pct = ability.get("revive_percentage", 50)

	for target in targets:
		if not target or target.is_alive:
			continue

		var revive_hp = int(target.max_hp * revive_pct / 100.0)
		target.revive(revive_hp)
		print("  → %s is revived with %d HP!" % [target.combatant_name, revive_hp])


func _execute_support_ability(caster: Combatant, ability: Dictionary, targets: Array) -> void:
	"""Execute a support ability (buffs, debuffs, status effects)"""
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
	"""Execute a meta ability (Scriptweaver, Time Mage, Necromancer)"""
	var meta_effect = ability.get("meta_effect", "")
	var corruption_risk = ability.get("corruption_risk", 0.0)
	var corruption_amount = ability.get("corruption_amount", 0.0)

	match meta_effect:
		"formula_modification":
			print("  → %s opens the formula editor..." % caster.combatant_name)
			print("  → [META] This would open a UI to edit damage formulas")
			GameState.add_corruption(corruption_risk)

		"constant_modification":
			print("  → %s accesses game constants..." % caster.combatant_name)
			print("  → [META] This would open a UI to modify game constants")
			print("  → Available constants: exp_multiplier, damage_multiplier, etc.")
			GameState.add_corruption(corruption_risk)

		"code_inspection":
			print("  → %s analyzes the battle code..." % caster.combatant_name)
			print("  → [META] Revealing internal battle logic...")
			print("  → Turn order: %s" % ", ".join(turn_order.map(func(c): return c.combatant_name)))

		"autobattle_editor":
			print("  → %s opens the autobattle scripting interface..." % caster.combatant_name)
			print("  → [META] This would open the autobattle script editor")

		"time_rewind":
			print("  → %s attempts to rewind time..." % caster.combatant_name)
			if GameState.rewind_to_previous_save():
				print("  → [META] Time has been rewound!")
			else:
				print("  → [META] No previous save state to rewind to")

		"create_save":
			print("  → %s creates a quicksave..." % caster.combatant_name)
			GameState.save_game("battle_quicksave_%d" % Time.get_ticks_msec())
			print("  → [META] Quicksave created!")

		"create_restore_point":
			print("  → %s creates a restore point..." % caster.combatant_name)
			GameState.save_game("restore_point_%d" % Time.get_ticks_msec())
			print("  → [META] Restore point created!")

		"auto_rewind_on_death":
			print("  → %s casts Temporal Shield!" % caster.combatant_name)
			for target in targets:
				if target:
					target.add_status("temporal_shield")
			print("  → [META] Party will auto-rewind on wipe!")

		"reverse_permadeath":
			print("  → %s undoes permadeath..." % caster.combatant_name)
			_execute_revival_ability(caster, ability, targets)
			print("  → [META] Permadeath has been reversed!")

		"add_corruption":
			print("  → %s channels corrupted power!" % caster.combatant_name)
			GameState.add_corruption(corruption_amount)
			# Also deal damage
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
	"""Execute an escape ability"""
	if not escape_allowed:
		print("  → Cannot escape from this battle!")
		return

	var success_rate = ability.get("success_rate", 0.5)
	if randf() < success_rate:
		print("  → %s escaped successfully!" % caster.combatant_name)
		end_battle(false)  # Escape counts as defeat for now
	else:
		print("  → %s failed to escape!" % caster.combatant_name)


func _execute_item(user: Combatant, item_id: String, targets: Array) -> void:
	"""Use an item (to be expanded with item system)"""
	print("%s uses item: %s" % [user.combatant_name, item_id])
	# TODO: Implement item system


## AI/Autobattle
func _process_ai_turn(combatant: Combatant) -> void:
	"""Process AI turn (basic AI for now)"""
	# Simple AI: attack a random alive player
	var alive_targets = []

	if combatant in player_party:
		alive_targets = enemy_party.filter(func(e): return e.is_alive)
	else:
		alive_targets = player_party.filter(func(p): return p.is_alive)

	if alive_targets.size() == 0:
		_end_combatant_turn(combatant)
		return

	# Pick random target and attack
	var target = alive_targets[randi() % alive_targets.size()]
	var action = {
		"type": "attack",
		"target": target
	}
	_execute_action(combatant, action)


## Victory/defeat conditions
func _check_victory_conditions() -> bool:
	"""Check if battle should end"""
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
	"""Handle combatant death"""
	print("%s has been defeated!" % combatant.combatant_name)


## Utility functions
func get_alive_combatants(party: Array[Combatant]) -> Array[Combatant]:
	"""Get all alive combatants from a party"""
	var alive: Array[Combatant] = []
	for combatant in party:
		if combatant.is_alive:
			alive.append(combatant)
	return alive


func is_battle_active() -> bool:
	"""Check if a battle is currently active"""
	return current_state not in [BattleState.INACTIVE, BattleState.VICTORY, BattleState.DEFEAT]
