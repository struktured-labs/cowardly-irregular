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

## Per-character scripts
var character_scripts: Dictionary = {}  # {character_id: Script}

## Autobattle enabled state per character
var autobattle_enabled: Dictionary = {}  # {character_id: bool}

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
	"defer": "Defer"
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

	if not character_scripts.has(character_id):
		return [_get_default_action(combatant)]

	var script = character_scripts[character_id]
	if not script.has("rules"):
		return [_get_default_action(combatant)]

	# Evaluate rules in order (first match wins)
	var rule_idx = 0
	for rule in script["rules"]:
		var enabled = rule.get("enabled", true)
		print("[AUTOBATTLE DEBUG] %s rule %d: enabled=%s" % [character_id, rule_idx, enabled])
		if _evaluate_grid_rule(combatant, rule):
			var actions = _rule_to_actions(combatant, rule)
			print("[AUTOBATTLE DEBUG] %s matched rule %d, actions: %s" % [character_id, rule_idx, actions])
			script_executed.emit(combatant, rule, actions)
			return actions
		rule_idx += 1

	# No rule matched, use default
	print("[AUTOBATTLE DEBUG] %s no rule matched, using default" % character_id)
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

		"turn":
			return _compare_str(BattleManager.current_round, op, value)

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

		"always":
			return true

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

	return {}


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
	if GameState and GameState.has_method("get_item_count"):
		return GameState.get_item_count(item_id)
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
	"""Get autobattle script for a character"""
	if character_scripts.has(character_id):
		return character_scripts[character_id]
	return create_default_character_script(character_id)


func set_character_script(character_id: String, script: Dictionary) -> void:
	"""Set autobattle script for a character"""
	character_scripts[character_id] = script
	_save_character_scripts()
	character_script_changed.emit(character_id)


func create_default_character_script(character_id: String) -> Dictionary:
	"""Create a default autobattle script for a character based on job class"""
	# Map character IDs to job-specific conservative scripts
	match character_id:
		"hero":
			return _create_fighter_default_script(character_id)
		"mira":
			return _create_white_mage_default_script(character_id)
		"zack":
			return _create_thief_default_script(character_id)
		"vex":
			return _create_black_mage_default_script(character_id)
		_:
			# Generic fallback - just attack
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
	"""Conservative Fighter script - basic attacks, power strike on weakened enemies"""
	return {
		"character_id": character_id,
		"name": "Fighter Default",
		"rules": [
			# Low HP - defer to recover
			{
				"conditions": [{"type": "hp_percent", "op": "<", "value": 20}],
				"actions": [{"type": "defer"}]
			},
			# Finish off weak enemy with Power Strike
			{
				"conditions": [
					{"type": "enemy_hp_percent", "op": "<", "value": 30},
					{"type": "mp_percent", "op": ">=", "value": 20}
				],
				"actions": [{"type": "ability", "id": "power_strike", "target": "lowest_hp_enemy"}]
			},
			# Default - basic attack
			{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			}
		]
	}


func _create_white_mage_default_script(character_id: String) -> Dictionary:
	"""Conservative White Mage script - heal allies, conserve MP"""
	return {
		"character_id": character_id,
		"name": "Healer Default",
		"rules": [
			# Emergency self-heal
			{
				"conditions": [
					{"type": "hp_percent", "op": "<", "value": 30},
					{"type": "mp_percent", "op": ">=", "value": 10}
				],
				"actions": [{"type": "ability", "id": "cure", "target": "self"}]
			},
			# Heal critically low ally
			{
				"conditions": [
					{"type": "ally_hp_percent", "op": "<", "value": 40},
					{"type": "mp_percent", "op": ">=", "value": 10}
				],
				"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}]
			},
			# Low MP - conserve with basic attack
			{
				"conditions": [{"type": "mp_percent", "op": "<", "value": 20}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			},
			# Default - attack if everyone healthy
			{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			}
		]
	}


func _create_thief_default_script(character_id: String) -> Dictionary:
	"""Conservative Thief script - fast attacks, steal when safe"""
	return {
		"character_id": character_id,
		"name": "Thief Default",
		"rules": [
			# Low HP - defer
			{
				"conditions": [{"type": "hp_percent", "op": "<", "value": 25}],
				"actions": [{"type": "defer"}]
			},
			# Steal from high HP enemy (safe to try)
			{
				"conditions": [
					{"type": "enemy_hp_percent", "op": ">", "value": 70},
					{"type": "mp_percent", "op": ">=", "value": 15}
				],
				"actions": [{"type": "ability", "id": "steal", "target": "highest_hp_enemy"}]
			},
			# Default - attack weakest
			{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			}
		]
	}


func _create_black_mage_default_script(character_id: String) -> Dictionary:
	"""Conservative Black Mage script - magic damage, conserve MP"""
	return {
		"character_id": character_id,
		"name": "Nuker Default",
		"rules": [
			# Low HP - defer
			{
				"conditions": [{"type": "hp_percent", "op": "<", "value": 25}],
				"actions": [{"type": "defer"}]
			},
			# Low MP - conserve with basic attack
			{
				"conditions": [{"type": "mp_percent", "op": "<", "value": 25}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			},
			# Multiple enemies - use Fire for damage
			{
				"conditions": [
					{"type": "enemy_count", "op": ">=", "value": 2},
					{"type": "mp_percent", "op": ">=", "value": 30}
				],
				"actions": [{"type": "ability", "id": "fire", "target": "lowest_hp_enemy"}]
			},
			# Single enemy - Thunder for efficiency
			{
				"conditions": [{"type": "mp_percent", "op": ">=", "value": 25}],
				"actions": [{"type": "ability", "id": "thunder", "target": "lowest_hp_enemy"}]
			},
			# Default fallback
			{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]
			}
		]
	}


func _load_character_scripts() -> void:
	"""Load all character scripts from file"""
	var save_path = "user://autobattle/characters.json"

	# Create directory if it doesn't exist
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("autobattle"):
		dir.make_dir("autobattle")

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
				print("Loaded %d character autobattle scripts" % character_scripts.size())


func _save_character_scripts() -> void:
	"""Save all character scripts to file"""
	var save_path = "user://autobattle/characters.json"

	# Create directory if it doesn't exist
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("autobattle"):
		dir.make_dir("autobattle")

	var data = {
		"scripts": character_scripts,
		"enabled": autobattle_enabled
	}

	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data, "\t")
		file.store_string(json_string)
		file.close()


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
			return _compare(BattleManager.current_round, compare_op, value)

		ConditionType.ENEMY_COUNT:
			var enemies = _get_enemies_for(combatant)
			return _compare(enemies.size(), compare_op, value)

		ConditionType.ALLY_COUNT:
			var allies = _get_allies_for(combatant)
			return _compare(allies.size(), compare_op, value)

		ConditionType.ITEM_COUNT:
			var item_id = condition.get("item_id", "")
			var count = combatant.get_item_count(item_id)
			return _compare(count, compare_op, value)

		ConditionType.ALWAYS:
			return true

		ConditionType.CUSTOM:
			# TODO: Implement custom expression parsing
			return true

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
			# TODO: Implement brave action queuing
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
	var is_player = combatant in BattleManager.player_party
	var enemy_party = BattleManager.enemy_party if is_player else BattleManager.player_party
	return enemy_party.filter(func(e): return e.is_alive)


func _get_allies_for(combatant: Combatant) -> Array[Combatant]:
	"""Get alive allies for a combatant"""
	var is_player = combatant in BattleManager.player_party
	var ally_party = BattleManager.player_party if is_player else BattleManager.enemy_party
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
