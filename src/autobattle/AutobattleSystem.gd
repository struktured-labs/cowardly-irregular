extends Node

## AutobattleSystem - Manages autobattle scripts and execution
## Allows players to script combat behavior with conditionals
##
## New 2D Grid Format:
## - Rules are evaluated top-to-bottom (first match wins)
## - Each rule has AND-chained conditions and up to 4 actions
## - Multiple actions = Advance mode (costs AP per action)

signal script_executed(combatant: Combatant, rule: Dictionary, actions: Array)
signal script_saved(script_name: String)
signal script_loaded(script_name: String)
signal character_script_changed(character_id: String)

## Loaded preset scripts (saved setups)
var saved_scripts: Dictionary = {}  # {script_name: Script}

## Per-character profile data
## Format: {character_id: {profiles: [{name, script}...], active: int}}
var character_profiles: Dictionary = {}

## Legacy: Per-character scripts (for migration)
var character_scripts: Dictionary = {}  # {character_id: Script}

## Autobattle enabled state per character
var autobattle_enabled: Dictionary = {}  # {character_id: bool}

## Flag to cancel all autobattle at start of next selection phase (persists across scene changes)
var cancel_all_next_turn: bool = false

## Max profiles per character (GBA-like limit)
const MAX_PROFILES_PER_CHARACTER: int = 8

## Default profile names for each job
const DEFAULT_PROFILE_TEMPLATES: Dictionary = {
	"hero": ["Aggressive", "Defensive", "Balanced"],
	"mira": ["Healer", "Support", "Offensive"],
	"zack": ["Steal First", "DPS", "Cautious"],
	"vex": ["Nuke", "Conserve MP", "AoE Focus"]
}

## Condition types
enum ConditionType {
	HP_PERCENT,        # self_hp < 50
	MP_PERCENT,        # self_mp < 25
	AP_VALUE,          # self_ap >= 2
	HAS_STATUS,        # has_status(poison)
	TARGET_HP_PERCENT, # target_hp < 30
	TURN_COUNT,        # turn >= 5
	ENEMY_COUNT,       # enemies <= 2
	ALLY_COUNT,        # allies_alive >= 3
	ITEM_COUNT,        # has_item(potion) >= 3
	ALWAYS,            # always true
	CUSTOM             # custom expression
}

## Comparison operators
enum CompareOp {
	LESS_THAN,
	LESS_EQUAL,
	EQUAL,
	GREATER_EQUAL,
	GREATER_THAN,
	NOT_EQUAL
}

## Action types
enum ActionType {
	ATTACK,
	ABILITY,
	ITEM,
	DEFAULT,
	BRAVE,
	SKIP
}

## String-based condition types for the new 2D grid format
const CONDITION_TYPES = {
	"hp_percent": "Self HP %",
	"mp_percent": "Self MP %",
	"ap": "Current AP",
	"has_status": "Has Status",
	"enemy_hp_percent": "Enemy HP %",
	"ally_hp_percent": "Ally HP %",
	"turn": "Turn Number",
	"enemy_count": "Enemy Count",
	"ally_count": "Ally Count",
	"item_count": "Has Item",
	"setup_complete": "Setup Complete",
	"ally_has_status": "Ally Has Status",
	"ally_mp_percent": "Ally MP %",
	"always": "Always"
}

## String-based operators
const OPERATORS = {
	"<": "Less Than",
	"<=": "Less or Equal",
	"==": "Equal",
	">=": "Greater or Equal",
	">": "Greater Than",
	"!=": "Not Equal"
}

## String-based action types
const ACTION_TYPES = {
	"attack": "Attack",
	"ability": "Ability",
	"item": "Item",
	"defer": "Defer",
	"all_out_attack": "All-Out Attack"
}

## Target types
const TARGET_TYPES = {
	"lowest_hp_enemy": "Lowest HP Enemy",
	"highest_hp_enemy": "Highest HP Enemy",
	"random_enemy": "Random Enemy",
	"lowest_hp_ally": "Lowest HP Ally",
	"self": "Self"
}


func _ready() -> void:
	_load_saved_scripts()
	_load_character_scripts()


## Autobattle execution (legacy - single action)
func execute_autobattle(combatant: Combatant, script: Dictionary) -> Dictionary:
	"""Execute autobattle script for a combatant, returns action to take"""
	if not script.has("rules"):
		return _get_default_action(combatant)

	# Evaluate rules in order (first match wins)
	for rule in script["rules"]:
		if _evaluate_rule(combatant, rule):
			var action = _rule_to_action(combatant, rule)
			script_executed.emit(combatant, rule, [action])
			return action

	# No rule matched, use default
	return _get_default_action(combatant)


## New 2D Grid-based execution - returns array of actions for Advance
func execute_grid_autobattle(combatant: Combatant) -> Array[Dictionary]:
	"""Execute autobattle for a combatant using their character script.
	Returns array of actions (1-4) for Advance mode."""
	var character_id = _get_character_id(combatant)

	# Use get_character_script() to properly retrieve from profiles
	var script = get_character_script(character_id)
	if script.is_empty() or not script.has("rules"):
		return [_get_default_action(combatant)]

	# Evaluate rules in order (first match wins)
	var rule_idx = 0
	for rule in script["rules"]:
		if _evaluate_grid_rule(combatant, rule):
			var actions = _rule_to_actions(combatant, rule)
			script_executed.emit(combatant, rule, actions)
			return actions
		rule_idx += 1

	# No rule matched, use default
	return [_get_default_action(combatant)]


func _evaluate_grid_rule(combatant: Combatant, rule: Dictionary) -> bool:
	"""Evaluate a grid-format rule (AND-chain of conditions)"""
	# Skip disabled rules
	if not rule.get("enabled", true):
		return false

	if not rule.has("conditions") or rule["conditions"].size() == 0:
		return true  # No conditions = always match

	# All conditions must be true (AND logic)
	for condition in rule["conditions"]:
		if not _evaluate_grid_condition(combatant, condition):
			return false

	return true


func _evaluate_grid_condition(combatant: Combatant, condition: Dictionary) -> bool:
	"""Evaluate a single grid-format condition (string-based types)"""
	var cond_type = condition.get("type", "always")
	var op = condition.get("op", "==")
	var value = condition.get("value", 0)

	match cond_type:
		"hp_percent":
			return _compare_str(combatant.get_hp_percentage(), op, value)

		"mp_percent":
			return _compare_str(combatant.get_mp_percentage(), op, value)

		"ap":
			return _compare_str(combatant.current_ap, op, value)

		"has_status":
			var status = condition.get("status", "")
			return status in combatant.status_effects

		"ally_has_status":
			# True if any living ally (including self) has the given status
			var status = condition.get("status", "")
			var allies = _get_allies_for(combatant)
			allies.append(combatant)
			for ally in allies:
				if status in ally.status_effects:
					return true
			return false

		"enemy_hp_percent":
			var target = _get_lowest_hp_enemy(combatant)
			if target:
				return _compare_str(target.get_hp_percentage(), op, value)
			return false

		"ally_hp_percent":
			var ally = _get_lowest_hp_ally(combatant)
			if ally:
				return _compare_str(ally.get_hp_percentage(), op, value)
			return false

		"ally_mp_percent":
			# True if the lowest-MP ally (including self) satisfies the comparison
			var lowest_mp_pct: float = 100.0
			var allies = _get_allies_for(combatant)
			allies.append(combatant)
			for ally in allies:
				var pct = ally.get_mp_percentage() if ally.has_method("get_mp_percentage") else 100.0
				if pct < lowest_mp_pct:
					lowest_mp_pct = pct
			return _compare_str(lowest_mp_pct, op, value)

		"turn":
			var battle_mgr = get_node_or_null("/root/BattleManager")
			if battle_mgr:
				return _compare_str(battle_mgr.current_round, op, value)
			return false

		"enemy_count":
			var enemies = _get_enemies_for(combatant)
			return _compare_str(enemies.size(), op, value)

		"ally_count":
			var allies = _get_allies_for(combatant)
			return _compare_str(allies.size(), op, value)

		"item_count":
			var item_id = condition.get("item_id", "")
			var count = _get_item_count(combatant, item_id)
			return _compare_str(count, op, value)

		"setup_complete":
			# True when combatant has buffs and max AP (ready for one-shot)
			var has_buffs = combatant.active_buffs.size() > 0 if "active_buffs" in combatant else false
			var max_ap = combatant.current_ap >= 4
			return has_buffs and max_ap

		"always":
			return true

	# Unknown condition type - log warning for debugging
	push_warning("AutobattleSystem: Unknown condition type '%s'" % cond_type)
	return false


func _compare_str(a: float, op: String, b: float) -> bool:
	"""Compare two values with a string operator"""
	match op:
		"<":
			return a < b
		"<=":
			return a <= b
		"==":
			return a == b
		">=":
			return a >= b
		">":
			return a > b
		"!=":
			return a != b
	return false


func _rule_to_actions(combatant: Combatant, rule: Dictionary) -> Array[Dictionary]:
	"""Convert a grid-format rule to an array of battle actions"""
	var actions: Array[Dictionary] = []

	if not rule.has("actions") or rule["actions"].size() == 0:
		actions.append(_get_default_action(combatant))
		return actions

	for action_def in rule["actions"]:
		var action = _action_def_to_action(combatant, action_def)
		if action.size() > 0:
			actions.append(action)

	if actions.size() == 0:
		actions.append(_get_default_action(combatant))

	return actions


func _action_def_to_action(combatant: Combatant, action_def: Dictionary) -> Dictionary:
	"""Convert a grid-format action definition to a battle action"""
	var action_type = action_def.get("type", "attack")
	var target_type = action_def.get("target", "lowest_hp_enemy")

	match action_type:
		"attack":
			return {
				"type": "attack",
				"target": _get_target_by_type(combatant, target_type)
			}

		"ability":
			var ability_id = action_def.get("id", "")
			return {
				"type": "ability",
				"ability_id": ability_id,
				"targets": [_get_target_by_type(combatant, target_type)]
			}

		"item":
			var item_id = action_def.get("id", "")
			return {
				"type": "item",
				"item_id": item_id,
				"targets": [_get_target_by_type(combatant, target_type)]
			}

		"defer":
			return {
				"type": "defer"
			}

		"all_out_attack":
			# Queue max actions on lowest HP enemy (signals advance mode)
			return {
				"type": "attack",
				"target": _get_target_by_type(combatant, "lowest_hp_enemy"),
				"force_advance": true  # Signal to queue max actions
			}
		_:
			push_warning("AutobattleSystem: Unknown action type '%s', defaulting to attack" % action_type)
			return {
				"type": "attack",
				"target": _get_target_by_type(combatant, "lowest_hp_enemy")
			}


func _get_target_by_type(combatant: Combatant, target_type: String) -> Combatant:
	"""Get target based on target type string"""
	match target_type:
		"lowest_hp_enemy":
			return _get_lowest_hp_enemy(combatant)
		"highest_hp_enemy":
			return _get_highest_hp_enemy(combatant)
		"random_enemy":
			var enemies = _get_enemies_for(combatant)
			return enemies[randi() % enemies.size()] if enemies.size() > 0 else null
		"lowest_hp_ally":
			return _get_lowest_hp_ally(combatant)
		"lowest_magic_defense_enemy":
			return _get_lowest_magic_defense_enemy(combatant)
		"self":
			return combatant
		_:
			return _get_lowest_hp_enemy(combatant)


func _get_character_id(combatant: Combatant) -> String:
	"""Get unique character ID for a combatant"""
	# Use combatant name as ID for now
	return combatant.combatant_name.to_lower().replace(" ", "_")


func _get_item_count(combatant: Combatant, item_id: String) -> int:
	"""Get count of an item in inventory"""
	# Check if combatant has get_item_count method
	if combatant.has_method("get_item_count"):
		return combatant.get_item_count(item_id)
	# Fallback: check GameState inventory
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("get_item_count"):
		return game_state.get_item_count(item_id)
	return 0


## Character script management
func is_autobattle_enabled(character_id: String) -> bool:
	"""Check if autobattle is enabled for a character"""
	return autobattle_enabled.get(character_id, false)


func set_autobattle_enabled(character_id: String, enabled: bool) -> void:
	"""Enable or disable autobattle for a character"""
	autobattle_enabled[character_id] = enabled
	character_script_changed.emit(character_id)


func toggle_autobattle(character_id: String) -> bool:
	"""Toggle autobattle for a character, returns new state"""
	var new_state = not is_autobattle_enabled(character_id)
	set_autobattle_enabled(character_id, new_state)
	return new_state


func get_character_script(character_id: String) -> Dictionary:
	"""Get active autobattle script for a character"""
	_ensure_character_profiles(character_id)
	var data = character_profiles[character_id]
	var active_idx = data.get("active", 0)
	var profiles = data.get("profiles", [])
	if active_idx < profiles.size():
		return profiles[active_idx].get("script", {})
	return create_default_character_script(character_id)


func set_character_script(character_id: String, script: Dictionary) -> void:
	"""Set active autobattle script for a character"""
	_ensure_character_profiles(character_id)
	var data = character_profiles[character_id]
	var active_idx = data.get("active", 0)
	var profiles = data.get("profiles", [])
	if active_idx < profiles.size():
		profiles[active_idx]["script"] = script
	_save_character_profiles()
	character_script_changed.emit(character_id)


## Profile Management Functions

func _ensure_character_profiles(character_id: String) -> void:
	"""Ensure character has profile data initialized"""
	if not character_profiles.has(character_id):
		# Check for legacy migration
		if character_scripts.has(character_id):
			# Migrate legacy script to first profile
			var legacy_script = character_scripts[character_id]
			character_profiles[character_id] = {
				"profiles": [{"name": "Default", "script": legacy_script}],
				"active": 0
			}
		else:
			# Create fresh default profiles
			character_profiles[character_id] = _create_default_profiles(character_id)


func _create_default_profiles(character_id: String) -> Dictionary:
	"""Create default profile set for a character"""
	var profile_names = DEFAULT_PROFILE_TEMPLATES.get(character_id, ["Default", "Custom 1", "Custom 2"])
	var profiles = []

	for i in range(profile_names.size()):
		var name = profile_names[i]
		var script = create_default_character_script(character_id) if i == 0 else _create_empty_script(character_id)
		profiles.append({"name": name, "script": script})

	return {"profiles": profiles, "active": 0}


func _create_empty_script(character_id: String) -> Dictionary:
	"""Create an empty script template"""
	return {
		"character_id": character_id,
		"name": "Empty",
		"rules": [
			{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
				"enabled": true
			}
		]
	}


func get_character_profiles(character_id: String) -> Array:
	"""Get all profiles for a character"""
	_ensure_character_profiles(character_id)
	return character_profiles[character_id].get("profiles", [])


func get_active_profile_index(character_id: String) -> int:
	"""Get index of active profile"""
	_ensure_character_profiles(character_id)
	return character_profiles[character_id].get("active", 0)


func get_active_profile_name(character_id: String) -> String:
	"""Get name of active profile"""
	_ensure_character_profiles(character_id)
	var data = character_profiles[character_id]
	var active_idx = data.get("active", 0)
	var profiles = data.get("profiles", [])
	if active_idx < profiles.size():
		return profiles[active_idx].get("name", "Default")
	return "Default"


func set_active_profile(character_id: String, index: int) -> void:
	"""Set active profile by index"""
	_ensure_character_profiles(character_id)
	var profiles = character_profiles[character_id].get("profiles", [])
	if index >= 0 and index < profiles.size():
		character_profiles[character_id]["active"] = index
		_save_character_profiles()
		character_script_changed.emit(character_id)


func create_new_profile(character_id: String, name: String = "") -> int:
	"""Create a new profile for character, returns index or -1 if at max"""
	_ensure_character_profiles(character_id)
	var profiles = character_profiles[character_id].get("profiles", [])

	if profiles.size() >= MAX_PROFILES_PER_CHARACTER:
		return -1

	if name.is_empty():
		name = "Custom %d" % (profiles.size() + 1)

	profiles.append({
		"name": name,
		"script": _create_empty_script(character_id)
	})

	_save_character_profiles()
	return profiles.size() - 1


func delete_profile(character_id: String, index: int) -> bool:
	"""Delete a profile (cannot delete last one)"""
	_ensure_character_profiles(character_id)
	var profiles = character_profiles[character_id].get("profiles", [])

	if profiles.size() <= 1 or index < 0 or index >= profiles.size():
		return false

	profiles.remove_at(index)

	# Adjust active index if needed
	var active = character_profiles[character_id].get("active", 0)
	if active >= profiles.size():
		character_profiles[character_id]["active"] = profiles.size() - 1
	elif active > index:
		character_profiles[character_id]["active"] = active - 1

	_save_character_profiles()
	return true


func rename_profile(character_id: String, index: int, new_name: String) -> bool:
	"""Rename a profile"""
	_ensure_character_profiles(character_id)
	var profiles = character_profiles[character_id].get("profiles", [])

	if index < 0 or index >= profiles.size() or new_name.is_empty():
		return false

	profiles[index]["name"] = new_name
	_save_character_profiles()
	return true


func reset_profile_to_default(character_id: String, index: int) -> bool:
	"""Reset a profile back to default values"""
	_ensure_character_profiles(character_id)
	var profiles = character_profiles[character_id].get("profiles", [])

	if index < 0 or index >= profiles.size():
		return false

	var name = profiles[index].get("name", "Default")
	profiles[index]["script"] = create_default_character_script(character_id)
	_save_character_profiles()
	return true


func copy_profile(character_id: String, source_index: int, new_name: String = "") -> int:
	"""Copy a profile, returns new index or -1 if at max"""
	_ensure_character_profiles(character_id)
	var profiles = character_profiles[character_id].get("profiles", [])

	if profiles.size() >= MAX_PROFILES_PER_CHARACTER or source_index < 0 or source_index >= profiles.size():
		return -1

	var source = profiles[source_index]
	if new_name.is_empty():
		new_name = source.get("name", "Copy") + " Copy"

	profiles.append({
		"name": new_name,
		"script": source.get("script", {}).duplicate(true)
	})

	_save_character_profiles()
	return profiles.size() - 1


func create_default_character_script(character_id: String) -> Dictionary:
	"""Create a default autobattle script for a character based on job class.
	Routing priority:
	  1. Known character names (hero/mira/zack/vex)
	  2. Job name aliases (fighter/cleric/mage/rogue/bard) — for future party members
	     or any character whose combatant_name matches their job
	  3. GameState party lookup — resolve job from saved party data
	  4. Generic attack fallback"""
	match character_id:
		# ── Named party members (primary route) ──────────────────────────────
		"hero":
			return _create_fighter_default_script(character_id)
		"mira":
			return _create_white_mage_default_script(character_id)
		"zack":
			return _create_thief_default_script(character_id)
		"vex":
			return _create_black_mage_default_script(character_id)
		# ── Job-name aliases (renamed jobs + bard, for future characters) ─────
		"fighter":
			return _create_fighter_default_script(character_id)
		"cleric", "white_mage":
			return _create_white_mage_default_script(character_id)
		"rogue", "thief":
			return _create_thief_default_script(character_id)
		"mage", "black_mage":
			return _create_black_mage_default_script(character_id)
		"bard":
			return _create_bard_default_script(character_id)
		_:
			# Job lookup via GameState: handles any named character whose primary job
			# is known but whose name doesn't match the cases above
			var game_state = get_node_or_null("/root/GameState")
			if game_state and game_state.has_method("get_character_job_id"):
				var job_id: String = game_state.get_character_job_id(character_id)
				match job_id:
					"fighter":
						return _create_fighter_default_script(character_id)
					"cleric", "white_mage":
						return _create_white_mage_default_script(character_id)
					"rogue", "thief":
						return _create_thief_default_script(character_id)
					"mage", "black_mage":
						return _create_black_mage_default_script(character_id)
					"bard":
						return _create_bard_default_script(character_id)
			# Generic fallback - basic attack
			return {
				"character_id": character_id,
				"name": "Default",
				"rules": [
					{
						"conditions": [{"type": "always"}],
						"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
					}
				]
			}


func _create_fighter_default_script(character_id: String) -> Dictionary:
	"""Fighter script - aggressive physical damage, potion safety net, Power Strike finisher"""
	return {
		"character_id": character_id,
		"name": "Fighter Default",
		"rules": [
			# Poison: use antidote before HP drain kills — higher priority than potion
			{
				"conditions": [
					{"type": "has_status", "status": "poison"},
					{"type": "item_count", "item_id": "antidote", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "antidote", "target": "self"}]
			},
			# Critical HP + has potion: use it immediately
			{
				"conditions": [
					{"type": "hp_percent", "op": "<", "value": 30},
					{"type": "item_count", "item_id": "potion", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "potion", "target": "self"}]
			},
			# Power Strike to finish off a wounded enemy
			{
				"conditions": [
					{"type": "enemy_hp_percent", "op": "<", "value": 35}
				],
				"actions": [{"type": "ability", "id": "power_strike", "target": "lowest_hp_enemy"}]
			},
			# Default - attack lowest HP enemy to kill off threats quickly
			{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			}
		]
	}


func _create_white_mage_default_script(character_id: String) -> Dictionary:
	"""Cleric script - proactive healing first, potion when dry, attack when party is healthy"""
	return {
		"character_id": character_id,
		"name": "Healer Default",
		"rules": [
			# Status priority: self poisoned and has antidote — cure it before anything else
			# (No Esuna ability exists yet; antidote handles poison on self)
			{
				"conditions": [
					{"type": "has_status", "status": "poison"},
					{"type": "item_count", "item_id": "antidote", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "antidote", "target": "self"}]
			},
			# Status priority: self blinded and has echo_herbs — clear it
			{
				"conditions": [
					{"type": "has_status", "status": "blind"},
					{"type": "item_count", "item_id": "echo_herbs", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "echo_herbs", "target": "self"}]
			},
			# Priority: any ally (including self) at or below 50% HP — heal immediately
			{
				"conditions": [
					{"type": "ally_hp_percent", "op": "<=", "value": 50},
					{"type": "mp_percent", "op": ">=", "value": 10}
				],
				"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}]
			},
			# Self at or below 50% but MP is gone: use a potion
			{
				"conditions": [
					{"type": "hp_percent", "op": "<=", "value": 50},
					{"type": "item_count", "item_id": "potion", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "potion", "target": "self"}]
			},
			# Out of MP but ally critically low: use potion on them
			{
				"conditions": [
					{"type": "ally_hp_percent", "op": "<", "value": 30},
					{"type": "item_count", "item_id": "potion", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "potion", "target": "lowest_hp_ally"}]
			},
			# Default - attack when party is safe
			{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			}
		]
	}


func _create_thief_default_script(character_id: String) -> Dictionary:
	"""Rogue script - backstab opener, steal early, potion safety net, fast finisher"""
	return {
		"character_id": character_id,
		"name": "Rogue Default",
		"rules": [
			# Poison: antidote before the DoT compounds — Rogue's HP pool is thin
			{
				"conditions": [
					{"type": "has_status", "status": "poison"},
					{"type": "item_count", "item_id": "antidote", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "antidote", "target": "self"}]
			},
			# Critical HP: use potion before deferring
			{
				"conditions": [
					{"type": "hp_percent", "op": "<", "value": 30},
					{"type": "item_count", "item_id": "potion", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "potion", "target": "self"}]
			},
			# Backstab: high-damage opener when enemy is healthy (hasn't been tagged yet)
			{
				"conditions": [
					{"type": "enemy_hp_percent", "op": ">", "value": 60}
				],
				"actions": [{"type": "ability", "id": "backstab", "target": "lowest_hp_enemy"}]
			},
			# Steal from high HP enemy at start of fight for items
			{
				"conditions": [
					{"type": "enemy_hp_percent", "op": ">", "value": 75}
				],
				"actions": [{"type": "ability", "id": "steal", "target": "highest_hp_enemy"}]
			},
			# Default - attack weakest to finish fights fast
			{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			}
		]
	}


func _create_black_mage_default_script(character_id: String) -> Dictionary:
	"""Mage script - lead with magic, target low-defense enemies, potion safety net"""
	return {
		"character_id": character_id,
		"name": "Mage Default",
		"rules": [
			# Poison: antidote immediately — poison ticks are especially punishing on low-HP Mage
			{
				"conditions": [
					{"type": "has_status", "status": "poison"},
					{"type": "item_count", "item_id": "antidote", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "antidote", "target": "self"}]
			},
			# Critical HP: use potion before anything else
			{
				"conditions": [
					{"type": "hp_percent", "op": "<", "value": 30},
					{"type": "item_count", "item_id": "potion", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "potion", "target": "self"}]
			},
			# Multiple enemies with enough MP: Fire hits all and softens the pack
			{
				"conditions": [
					{"type": "enemy_count", "op": ">=", "value": 2},
					{"type": "mp_percent", "op": ">=", "value": 25}
				],
				"actions": [{"type": "ability", "id": "fire", "target": "lowest_magic_defense_enemy"}]
			},
			# Single enemy, good MP: Thunder for solid single-target damage
			{
				"conditions": [
					{"type": "mp_percent", "op": ">=", "value": 20}
				],
				"actions": [{"type": "ability", "id": "thunder", "target": "lowest_magic_defense_enemy"}]
			},
			# MP depleted: basic attack rather than deferring dead weight
			{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			}
		]
	}


func _create_bard_default_script(character_id: String) -> Dictionary:
	"""Bard script - buff party with Battle Hymn, crowd-control with Lullaby, restore MP,
	heal self with potion when critical, fall back to basic attack"""
	return {
		"character_id": character_id,
		"name": "Bard Default",
		"rules": [
			# Survival first: critical HP, use potion immediately
			{
				"conditions": [
					{"type": "hp_percent", "op": "<", "value": 30},
					{"type": "item_count", "item_id": "potion", "op": ">", "value": 0}
				],
				"actions": [{"type": "item", "id": "potion", "target": "self"}]
			},
			# Battle Hymn: cast on turn 1 (setup phase) to get attack buff on the whole party
			# Re-cast at turn 4+ so the 3-turn buff never fully drops between fights
			{
				"conditions": [
					{"type": "turn", "op": "<=", "value": 1},
					{"type": "mp_percent", "op": ">=", "value": 20}
				],
				"actions": [{"type": "ability", "id": "battle_hymn", "target": "all_allies"}]
			},
			# Lullaby: sleep a crowd when 2+ enemies are alive and we have enough MP
			{
				"conditions": [
					{"type": "enemy_count", "op": ">=", "value": 2},
					{"type": "mp_percent", "op": ">=", "value": 20}
				],
				"actions": [{"type": "ability", "id": "lullaby", "target": "lowest_hp_enemy"}]
			},
			# Inspiring Melody: restore MP when any ally is running low (below 30%) and
			# the Bard still has enough MP to cast it (20%+ own MP)
			{
				"conditions": [
					{"type": "ally_mp_percent", "op": "<", "value": 30},
					{"type": "mp_percent", "op": ">=", "value": 20}
				],
				"actions": [{"type": "ability", "id": "inspiring_melody", "target": "all_allies"}]
			},
			# Fallback: basic attack
			{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			}
		]
	}


func _load_character_scripts() -> void:
	"""Load all character scripts from file (legacy + new profiles)"""
	var save_path = "user://autobattle/characters.json"
	var profiles_path = "user://autobattle/profiles.json"

	# Create directory if it doesn't exist
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("autobattle"):
		dir.make_dir("autobattle")

	# Load new profiles format first
	if FileAccess.file_exists(profiles_path):
		var file = FileAccess.open(profiles_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(json_string) == OK:
				var data = json.data
				if data is Dictionary:
					character_profiles = data.get("profiles", {})
					autobattle_enabled = data.get("enabled", {})
					print("Loaded profiles for %d characters" % character_profiles.size())
					return

	# Fallback: load legacy format for migration
	if not FileAccess.file_exists(save_path):
		return

	var file = FileAccess.open(save_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		if json.parse(json_string) == OK:
			var data = json.data
			if data is Dictionary:
				character_scripts = data.get("scripts", {})
				autobattle_enabled = data.get("enabled", {})
				# Migrate old format scripts to new format
				_migrate_old_format_scripts()
				print("Loaded %d character autobattle scripts (legacy)" % character_scripts.size())


func _save_character_profiles() -> void:
	"""Save all character profiles to file"""
	var save_path = "user://autobattle/profiles.json"

	# Create directory if it doesn't exist
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("autobattle"):
		dir.make_dir("autobattle")

	var data = {
		"profiles": character_profiles,
		"enabled": autobattle_enabled
	}

	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data, "\t")
		file.store_string(json_string)
		file.close()


func _migrate_old_format_scripts() -> void:
	"""Migrate old numeric format scripts to new string format"""
	var needs_save = false

	for character_id in character_scripts.keys():
		var script = character_scripts[character_id]
		if not script.has("rules"):
			continue

		for rule in script["rules"]:
			# Check if this is old format (has action_type instead of actions array)
			if rule.has("action_type") and not rule.has("actions"):
				# Old format detected - reset to default
				print("Migrating old format script for %s" % character_id)
				character_scripts[character_id] = create_default_character_script(character_id)
				needs_save = true
				break

			# Check conditions for old numeric format
			if rule.has("conditions"):
				for condition in rule["conditions"]:
					var cond_type = condition.get("type")
					# If type is a number (old enum format), reset script
					if cond_type is float or cond_type is int:
						print("Migrating old numeric condition format for %s" % character_id)
						character_scripts[character_id] = create_default_character_script(character_id)
						needs_save = true
						break

	if needs_save:
		_save_character_scripts()


func _save_character_scripts() -> void:
	"""Legacy save - redirects to profile save after migration"""
	# First migrate any legacy scripts to profiles
	for character_id in character_scripts.keys():
		if not character_profiles.has(character_id):
			var legacy_script = character_scripts[character_id]
			character_profiles[character_id] = {
				"profiles": [{"name": "Default", "script": legacy_script}],
				"active": 0
			}
	# Save using new profile format
	_save_character_profiles()


func _evaluate_rule(combatant: Combatant, rule: Dictionary) -> bool:
	"""Evaluate if a rule's conditions are met"""
	if not rule.has("conditions"):
		return true  # No conditions = always match

	var conditions = rule["conditions"]
	var logic = rule.get("logic", "AND")  # AND or OR

	var results = []
	for condition in conditions:
		results.append(_evaluate_condition(combatant, condition))

	if logic == "AND":
		return not (false in results)
	else:  # OR
		return true in results


func _evaluate_condition(combatant: Combatant, condition: Dictionary) -> bool:
	"""Evaluate a single condition"""
	var type = condition.get("type", ConditionType.ALWAYS)
	var compare_op = condition.get("compare_op", CompareOp.LESS_THAN)
	var value = condition.get("value", 0)

	match type:
		ConditionType.HP_PERCENT:
			var hp_pct = combatant.get_hp_percentage()
			return _compare(hp_pct, compare_op, value)

		ConditionType.MP_PERCENT:
			var mp_pct = combatant.get_mp_percentage()
			return _compare(mp_pct, compare_op, value)

		ConditionType.AP_VALUE:
			return _compare(combatant.current_ap, compare_op, value)

		ConditionType.HAS_STATUS:
			var status_name = condition.get("status", "")
			return status_name in combatant.status_effects

		ConditionType.TARGET_HP_PERCENT:
			# Get lowest HP enemy
			var target = _get_lowest_hp_enemy(combatant)
			if target:
				return _compare(target.get_hp_percentage(), compare_op, value)
			return false

		ConditionType.TURN_COUNT:
			var battle_mgr2 = get_node_or_null("/root/BattleManager")
			if battle_mgr2:
				return _compare(battle_mgr2.current_round, compare_op, value)
			return false

		ConditionType.ENEMY_COUNT:
			var enemies = _get_enemies_for(combatant)
			return _compare(enemies.size(), compare_op, value)

		ConditionType.ALLY_COUNT:
			var allies = _get_allies_for(combatant)
			return _compare(allies.size(), compare_op, value)

		ConditionType.ITEM_COUNT:
			var item_id = condition.get("item_id", "")
			var count = combatant.get_item_count(item_id) if combatant.has_method("get_item_count") else 0
			return _compare(count, compare_op, value)

		ConditionType.ALWAYS:
			return true

		ConditionType.CUSTOM:
			push_warning("AutobattleSystem: CUSTOM conditions not yet implemented")
			return false

	return false


func _compare(a: float, op: CompareOp, b: float) -> bool:
	"""Compare two values with an operator"""
	match op:
		CompareOp.LESS_THAN:
			return a < b
		CompareOp.LESS_EQUAL:
			return a <= b
		CompareOp.EQUAL:
			return a == b
		CompareOp.GREATER_EQUAL:
			return a >= b
		CompareOp.GREATER_THAN:
			return a > b
		CompareOp.NOT_EQUAL:
			return a != b
	return false


func _rule_to_action(combatant: Combatant, rule: Dictionary) -> Dictionary:
	"""Convert a rule to a battle action"""
	var action_type = rule.get("action_type", ActionType.ATTACK)
	var action = {
		"type": _action_type_to_string(action_type)
	}

	match action_type:
		ActionType.ATTACK:
			action["target"] = _get_target_for_rule(combatant, rule)

		ActionType.ABILITY:
			var ability_id = rule.get("ability_id", "")
			action["ability_id"] = ability_id
			action["targets"] = [_get_target_for_rule(combatant, rule)]

		ActionType.ITEM:
			var item_id = rule.get("item_id", "")
			action["item_id"] = item_id
			action["targets"] = [_get_target_for_rule(combatant, rule)]

		ActionType.DEFAULT:
			pass  # Default action needs no extra data

		ActionType.BRAVE:
			push_warning("AutobattleSystem: BRAVE action queuing not yet implemented")
			var actions = rule.get("brave_actions", [])
			action["actions"] = actions

		ActionType.SKIP:
			action["type"] = "skip"

	return action


func _get_target_for_rule(combatant: Combatant, rule: Dictionary) -> Combatant:
	"""Get target based on rule's target type"""
	var target_type = rule.get("target_type", "lowest_hp_enemy")

	match target_type:
		"lowest_hp_enemy":
			return _get_lowest_hp_enemy(combatant)
		"highest_hp_enemy":
			return _get_highest_hp_enemy(combatant)
		"random_enemy":
			var enemies = _get_enemies_for(combatant)
			return enemies[randi() % enemies.size()] if enemies.size() > 0 else null
		"lowest_hp_ally":
			return _get_lowest_hp_ally(combatant)
		"self":
			return combatant
		_:
			return _get_lowest_hp_enemy(combatant)


func _get_default_action(combatant: Combatant) -> Dictionary:
	"""Get default action when no rules match"""
	var enemies = _get_enemies_for(combatant)
	if enemies.size() > 0:
		return {
			"type": "attack",
			"target": enemies[0]
		}
	return {
		"type": "skip"
	}


func _action_type_to_string(action_type: ActionType) -> String:
	"""Convert ActionType enum to string"""
	match action_type:
		ActionType.ATTACK:
			return "attack"
		ActionType.ABILITY:
			return "ability"
		ActionType.ITEM:
			return "item"
		ActionType.DEFAULT:
			return "defend"
		ActionType.BRAVE:
			return "brave"
		ActionType.SKIP:
			return "skip"
	return "attack"


## Helper functions
func _get_enemies_for(combatant: Combatant) -> Array[Combatant]:
	"""Get alive enemies for a combatant"""
	var bm = get_node_or_null("/root/BattleManager")
	if not bm:
		return []
	var is_player = combatant in bm.player_party
	var enemy_party = bm.enemy_party if is_player else bm.player_party
	return enemy_party.filter(func(e): return e.is_alive)


func _get_allies_for(combatant: Combatant) -> Array[Combatant]:
	"""Get alive allies for a combatant"""
	var bm = get_node_or_null("/root/BattleManager")
	if not bm:
		return []
	var is_player = combatant in bm.player_party
	var ally_party = bm.player_party if is_player else bm.enemy_party
	return ally_party.filter(func(a): return a.is_alive)


func _get_lowest_hp_enemy(combatant: Combatant) -> Combatant:
	"""Get enemy with lowest HP percentage"""
	var enemies = _get_enemies_for(combatant)
	if enemies.size() == 0:
		return null

	enemies.sort_custom(func(a, b): return a.get_hp_percentage() < b.get_hp_percentage())
	return enemies[0]


func _get_highest_hp_enemy(combatant: Combatant) -> Combatant:
	"""Get enemy with highest HP"""
	var enemies = _get_enemies_for(combatant)
	if enemies.size() == 0:
		return null

	enemies.sort_custom(func(a, b): return a.current_hp > b.current_hp)
	return enemies[0]


func _get_lowest_hp_ally(combatant: Combatant) -> Combatant:
	"""Get ally with lowest HP percentage"""
	var allies = _get_allies_for(combatant)
	if allies.size() == 0:
		return combatant

	allies.sort_custom(func(a, b): return a.get_hp_percentage() < b.get_hp_percentage())
	return allies[0]


func _get_lowest_magic_defense_enemy(combatant: Combatant) -> Combatant:
	"""Get enemy with lowest defense (magic damage scales at 0.5x defense — lowest defense = best magic target)"""
	var enemies = _get_enemies_for(combatant)
	if enemies.size() == 0:
		return null

	enemies.sort_custom(func(a, b): return a.defense < b.defense)
	return enemies[0]


## Script management
func create_script(script_name: String) -> Dictionary:
	"""Create a new empty autobattle script"""
	return {
		"name": script_name,
		"rules": [],
		"description": "New autobattle script"
	}


func add_rule(script: Dictionary, rule: Dictionary) -> void:
	"""Add a rule to a script"""
	if not script.has("rules"):
		script["rules"] = []
	script["rules"].append(rule)


func create_rule(description: String, conditions: Array, action_type: ActionType, action_data: Dictionary = {}) -> Dictionary:
	"""Create a rule with conditions and action"""
	var rule = {
		"description": description,
		"conditions": conditions,
		"logic": "AND",
		"action_type": action_type
	}

	# Merge action_data into rule
	for key in action_data:
		rule[key] = action_data[key]

	return rule


func create_condition(type: ConditionType, compare_op: CompareOp, value: Variant, extra_data: Dictionary = {}) -> Dictionary:
	"""Create a condition"""
	var condition = {
		"type": type,
		"compare_op": compare_op,
		"value": value
	}

	# Merge extra_data
	for key in extra_data:
		condition[key] = extra_data[key]

	return condition


## Save/Load
func save_script(script_name: String, script: Dictionary) -> void:
	"""Save a script to file"""
	saved_scripts[script_name] = script

	var save_path = "user://autobattle_scripts.json"
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(saved_scripts, "\t")
		file.store_string(json_string)
		file.close()
		script_saved.emit(script_name)
		print("Saved autobattle script: %s" % script_name)


func load_script(script_name: String) -> Dictionary:
	"""Load a script by name"""
	if saved_scripts.has(script_name):
		script_loaded.emit(script_name)
		return saved_scripts[script_name]
	return {}


func _load_saved_scripts() -> void:
	"""Load all saved scripts from file"""
	var save_path = "user://autobattle_scripts.json"

	if not FileAccess.file_exists(save_path):
		_create_default_scripts()
		return

	var file = FileAccess.open(save_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		if json.parse(json_string) == OK:
			saved_scripts = json.data
			print("Loaded %d autobattle scripts" % saved_scripts.size())
		else:
			print("Error parsing autobattle scripts")
			_create_default_scripts()
	else:
		_create_default_scripts()


func _create_default_scripts() -> void:
	"""Create some default autobattle scripts as examples"""
	# Simple aggressive script
	var aggressive = create_script("Aggressive")
	aggressive["description"] = "Always attack, use abilities when MP available"

	add_rule(aggressive, create_rule(
		"Use Power Strike if MP >= 15",
		[create_condition(ConditionType.MP_PERCENT, CompareOp.GREATER_EQUAL, 30)],
		ActionType.ABILITY,
		{"ability_id": "power_strike", "target_type": "lowest_hp_enemy"}
	))

	add_rule(aggressive, create_rule(
		"Attack lowest HP enemy",
		[create_condition(ConditionType.ALWAYS, CompareOp.EQUAL, 0)],
		ActionType.ATTACK,
		{"target_type": "lowest_hp_enemy"}
	))

	saved_scripts["Aggressive"] = aggressive

	# Defensive/healing script
	var defensive = create_script("Defensive")
	defensive["description"] = "Heal when low, defend when healthy"

	add_rule(defensive, create_rule(
		"Use potion if HP < 40%",
		[create_condition(ConditionType.HP_PERCENT, CompareOp.LESS_THAN, 40)],
		ActionType.ITEM,
		{"item_id": "potion", "target_type": "self"}
	))

	add_rule(defensive, create_rule(
		"Default if HP < 60%",
		[create_condition(ConditionType.HP_PERCENT, CompareOp.LESS_THAN, 60)],
		ActionType.DEFAULT,
		{}
	))

	add_rule(defensive, create_rule(
		"Attack otherwise",
		[create_condition(ConditionType.ALWAYS, CompareOp.EQUAL, 0)],
		ActionType.ATTACK,
		{"target_type": "lowest_hp_enemy"}
	))

	saved_scripts["Defensive"] = defensive

	print("Created %d default autobattle scripts" % saved_scripts.size())
