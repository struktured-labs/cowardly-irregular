extends Node
class_name AdaptiveAI

## AdaptiveAI - Meta-boss AI controller for highly adapted enemies
## Used for bosses with corruption level >= 2 or adaptive flag
## Can read player autobattle scripts (meta-awareness) and counter them

## Reference to battle manager
var battle_manager: Node = null

## Cached player patterns
var _player_patterns: Dictionary = {}
var _adaptation_level: int = 0

## Counter cooldowns (prevent spam)
var _counter_cooldown: int = 0
const COUNTER_COOLDOWN_TURNS: int = 2


func _ready() -> void:
	battle_manager = get_node_or_null("/root/BattleManager")


func initialize(patterns: Dictionary, adaptation: int) -> void:
	"""Initialize with learned patterns and adaptation level"""
	_player_patterns = patterns
	_adaptation_level = adaptation
	_counter_cooldown = 0


func should_use_adaptive_ai(combatant: Combatant) -> bool:
	"""Check if this combatant should use adaptive AI"""
	if _adaptation_level < 2:
		return false
	# Check for adaptive flag in enemy data
	var monster_type = combatant.get_meta("monster_type", "")
	if monster_type.is_empty():
		return false
	# Bosses and minibosses with adaptation always qualify
	var is_boss = combatant.get_meta("boss", false)
	var is_miniboss = combatant.get_meta("miniboss", false)
	var is_adaptive = combatant.get_meta("adaptive", false)
	return is_boss or is_miniboss or is_adaptive


func make_adaptive_decision(combatant: Combatant, allies: Array, enemies: Array, abilities: Array) -> Dictionary:
	"""Make an adaptive AI decision based on meta-knowledge"""
	if _counter_cooldown > 0:
		_counter_cooldown -= 1
		return {}  # Fall back to normal AI

	# Try to read player autobattle scripts (meta-awareness)
	var autobattle_system = get_node_or_null("/root/AutobattleSystem")
	if autobattle_system and _adaptation_level >= 3:
		var counter = _counter_autobattle_script(combatant, enemies, abilities, autobattle_system)
		if not counter.is_empty():
			_counter_cooldown = COUNTER_COOLDOWN_TURNS
			return counter

	# Standard adaptive behavior
	var counter_strategy = _player_patterns.get("counter_strategy", "")
	if not counter_strategy.is_empty():
		_counter_cooldown = COUNTER_COOLDOWN_TURNS
		return _apply_counter_strategy(combatant, counter_strategy, allies, enemies, abilities)

	return {}


func _counter_autobattle_script(combatant: Combatant, enemies: Array, abilities: Array, autobattle: Node) -> Dictionary:
	"""Read player autobattle scripts and deliberately counter them"""
	# Check each player's script for exploitable patterns
	for player in enemies:
		var char_id = player.combatant_name.to_lower().replace(" ", "_")
		if not autobattle.is_autobattle_enabled(char_id):
			continue

		var script = autobattle.get_character_script(char_id)
		if script.is_empty() or not script.has("rules"):
			continue

		# Analyze first matching rule's conditions
		for rule in script["rules"]:
			var conditions = rule.get("conditions", [])
			for condition in conditions:
				var cond_type = condition.get("type", "")
				var value = condition.get("value", 0)

				# If script heals at HP < X%, keep party at X+1%
				if cond_type == "hp_percent" and condition.get("op", "") == "<":
					# This is a heal trigger - try to keep player just above threshold
					var heal_threshold = value
					if _should_hold_damage(player, heal_threshold):
						# Use a weak attack instead of strong one to keep HP just above threshold
						return {
							"type": "attack",
							"combatant": combatant,
							"target": player,
							"speed": 5,
							"adaptive_note": "Holding damage above heal threshold %d%%" % heal_threshold
						}

	return {}


func _should_hold_damage(target: Combatant, heal_threshold: float) -> bool:
	"""Check if we should hold damage to keep target above heal trigger"""
	var hp_pct = target.get_hp_percentage()
	return hp_pct > heal_threshold and hp_pct < heal_threshold + 15


func _apply_counter_strategy(combatant: Combatant, strategy: String, allies: Array, enemies: Array, abilities: Array) -> Dictionary:
	"""Apply a counter strategy based on learned patterns"""
	# Delegate to main counter logic in BattleManager
	if battle_manager and battle_manager.has_method("_get_counter_action"):
		return battle_manager._get_counter_action(combatant, strategy, allies, enemies, abilities)
	return {}


func get_adaptation_message() -> String:
	"""Get flavor text for adapted enemies"""
	match _adaptation_level:
		1: return "The enemy seems wary of your tactics..."
		2: return "The enemy anticipates your strategy!"
		3: return "The enemy reads your every move!"
		_: return ""


func decrement_cooldown() -> void:
	"""Call at start of each enemy turn to manage cooldowns"""
	# Cooldown is managed in make_adaptive_decision, this is for external use
	pass


func reset() -> void:
	"""Reset adaptive AI state for new battle"""
	_counter_cooldown = 0
