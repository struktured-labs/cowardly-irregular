extends Node

## AutobattleSystem - Manages autobattle scripts and execution
## Allows players to script combat behavior with conditionals

signal script_executed(combatant: Combatant, rule: Dictionary, action: Dictionary)
signal script_saved(script_name: String)
signal script_loaded(script_name: String)

## Loaded scripts (saved setups)
var saved_scripts: Dictionary = {}  # {script_name: AutobattleScript}

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


func _ready() -> void:
	_load_saved_scripts()


## Autobattle execution
func execute_autobattle(combatant: Combatant, script: Dictionary) -> Dictionary:
	"""Execute autobattle script for a combatant, returns action to take"""
	if not script.has("rules"):
		return _get_default_action(combatant)

	# Evaluate rules in order (first match wins)
	for rule in script["rules"]:
		if _evaluate_rule(combatant, rule):
			var action = _rule_to_action(combatant, rule)
			script_executed.emit(combatant, rule, action)
			return action

	# No rule matched, use default
	return _get_default_action(combatant)


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
