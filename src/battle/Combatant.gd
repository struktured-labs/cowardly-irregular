extends Node
class_name Combatant

## Base class for all battle participants (player characters and enemies)
## Manages stats, AP, status effects, and turn mechanics

signal hp_changed(old_value: int, new_value: int)
signal ap_changed(old_value: int, new_value: int)
signal died()
signal status_added(status: String)
signal status_removed(status: String)

## Core stats
@export var combatant_name: String = "Unknown"
@export var max_hp: int = 100
@export var max_mp: int = 50
@export var attack: int = 10
@export var defense: int = 10
@export var magic: int = 10
@export var speed: int = 10

## Current state
var current_hp: int
var current_mp: int
var current_ap: int = 0  # Action Points: -4 to +4 range
var is_defending: bool = false
var is_alive: bool = true

## Status effects and buffs
var status_effects: Array[String] = []
var permanent_injuries: Array[Dictionary] = []
var active_buffs: Array[Dictionary] = []  # {effect: String, stat: String, modifier: float, duration: int}
var active_debuffs: Array[Dictionary] = []

## Elemental affinities
var elemental_weaknesses: Array[String] = []  # Takes 1.5x damage from these
var elemental_resistances: Array[String] = []  # Takes 0.5x damage from these
var elemental_immunities: Array[String] = []   # Takes 0x damage from these

## Job reference (will be set by JobSystem)
var job = null

## Turn state
var queued_actions: Array[Dictionary] = []
var turn_order_value: float = 0.0
var doom_counter: int = -1  # Death Sentence countdown (-1 = not doomed)


func _ready() -> void:
	current_hp = max_hp
	current_mp = max_mp


## Initialize combatant with specific values
func initialize(stats: Dictionary) -> void:
	if stats.has("name"):
		combatant_name = stats["name"]
	if stats.has("max_hp"):
		max_hp = stats["max_hp"]
		current_hp = max_hp
	if stats.has("max_mp"):
		max_mp = stats["max_mp"]
		current_mp = max_mp
	if stats.has("attack"):
		attack = stats["attack"]
	if stats.has("defense"):
		defense = stats["defense"]
	if stats.has("magic"):
		magic = stats["magic"]
	if stats.has("speed"):
		speed = stats["speed"]


## Brave/Default system
func can_brave(ap_cost: int) -> bool:
	# Can go into AP debt up to -4
	return (current_ap - ap_cost) >= -4


func spend_ap(amount: int) -> bool:
	if not can_brave(amount):
		return false

	var old_ap = current_ap
	current_ap = clampi(current_ap - amount, -4, 4)
	ap_changed.emit(old_ap, current_ap)
	return true


func gain_ap(amount: int) -> void:
	var old_ap = current_ap
	current_ap = clampi(current_ap + amount, -4, 4)
	ap_changed.emit(old_ap, current_ap)


func execute_default() -> void:
	"""Default action: skip turn, gain +1 AP, reduce incoming damage"""
	is_defending = true
	gain_ap(1)


func execute_brave(actions: Array[Dictionary]) -> void:
	"""Brave action: queue multiple actions, spending AP"""
	var ap_cost = actions.size() - 1  # First action is free
	if spend_ap(ap_cost):
		queued_actions = actions.duplicate()


## Combat actions
func take_damage(amount: int, is_magical: bool = false) -> int:
	"""Apply damage considering defense/magic defense and defending state"""
	var actual_damage = amount

	if is_magical:
		actual_damage = max(1, amount - (defense / 2))
	else:
		actual_damage = max(1, amount - defense)

	# Defending reduces damage by 50%
	if is_defending:
		actual_damage = int(actual_damage * 0.5)

	var old_hp = current_hp
	current_hp = max(0, current_hp - actual_damage)
	hp_changed.emit(old_hp, current_hp)

	if current_hp <= 0:
		die()

	return actual_damage


func heal(amount: int) -> int:
	"""Heal HP, returns actual amount healed"""
	if not is_alive:
		return 0

	var old_hp = current_hp
	current_hp = min(max_hp, current_hp + amount)
	var healed = current_hp - old_hp
	hp_changed.emit(old_hp, current_hp)
	return healed


func restore_mp(amount: int) -> int:
	"""Restore MP, returns actual amount restored"""
	var old_mp = current_mp
	current_mp = min(max_mp, current_mp + amount)
	return current_mp - old_mp


func spend_mp(amount: int) -> bool:
	"""Try to spend MP, returns false if insufficient"""
	if current_mp < amount:
		return false
	current_mp -= amount
	return true


func die() -> void:
	"""Handle death"""
	is_alive = false
	current_hp = 0
	died.emit()


func revive(hp_amount: int = 0) -> void:
	"""Revive with specified HP (or 50% max if not specified)"""
	is_alive = true
	if hp_amount > 0:
		current_hp = min(hp_amount, max_hp)
	else:
		current_hp = max_hp / 2
	hp_changed.emit(0, current_hp)


## Status effects
func add_status(status: String) -> void:
	if not status in status_effects:
		status_effects.append(status)
		status_added.emit(status)


func remove_status(status: String) -> void:
	if status in status_effects:
		status_effects.erase(status)
		status_removed.emit(status)


func has_status(status: String) -> bool:
	return status in status_effects


## Buffs and Debuffs
func add_buff(effect: String, stat: String, modifier: float, duration: int) -> void:
	"""Add a temporary buff"""
	var buff = {
		"effect": effect,
		"stat": stat,
		"modifier": modifier,
		"duration": duration,
		"remaining_turns": duration
	}
	active_buffs.append(buff)
	print("%s gained %s (%.1fx %s for %d turns)" % [combatant_name, effect, modifier, stat, duration])


func add_debuff(effect: String, stat: String, modifier: float, duration: int) -> void:
	"""Add a temporary debuff"""
	var debuff = {
		"effect": effect,
		"stat": stat,
		"modifier": modifier,
		"duration": duration,
		"remaining_turns": duration
	}
	active_debuffs.append(debuff)
	print("%s suffered %s (%.1fx %s for %d turns)" % [combatant_name, effect, modifier, stat, duration])


func get_buffed_stat(stat_name: String, base_value: int) -> int:
	"""Get stat value with buffs/debuffs applied"""
	var final_value = float(base_value)

	# Apply buffs
	for buff in active_buffs:
		if buff["stat"] == stat_name:
			final_value *= buff["modifier"]

	# Apply debuffs
	for debuff in active_debuffs:
		if debuff["stat"] == stat_name:
			final_value *= debuff["modifier"]

	return int(final_value)


func update_buff_durations() -> void:
	"""Decrease buff/debuff durations, remove expired ones"""
	# Update buffs
	for i in range(active_buffs.size() - 1, -1, -1):
		active_buffs[i]["remaining_turns"] -= 1
		if active_buffs[i]["remaining_turns"] <= 0:
			print("%s's %s wore off" % [combatant_name, active_buffs[i]["effect"]])
			active_buffs.remove_at(i)

	# Update debuffs
	for i in range(active_debuffs.size() - 1, -1, -1):
		active_debuffs[i]["remaining_turns"] -= 1
		if active_debuffs[i]["remaining_turns"] <= 0:
			print("%s's %s wore off" % [combatant_name, active_debuffs[i]["effect"]])
			active_debuffs.remove_at(i)

	# Update doom counter
	if doom_counter > 0:
		doom_counter -= 1
		if doom_counter == 0:
			print("%s succumbs to Death Sentence!" % combatant_name)
			die()


## Elemental damage
func calculate_elemental_modifier(element: String) -> float:
	"""Calculate damage multiplier based on elemental affinity"""
	if element.is_empty():
		return 1.0

	if element in elemental_immunities:
		return 0.0
	elif element in elemental_weaknesses:
		return 1.5
	elif element in elemental_resistances:
		return 0.5

	return 1.0


func take_elemental_damage(base_damage: int, element: String) -> int:
	"""Take damage with elemental modifier"""
	var elemental_mod = calculate_elemental_modifier(element)
	var actual_damage = int(base_damage * elemental_mod)

	if elemental_mod == 0.0:
		print("%s is immune to %s!" % [combatant_name, element])
		return 0
	elif elemental_mod > 1.0:
		print("It's super effective!")
	elif elemental_mod < 1.0:
		print("%s resists %s" % [combatant_name, element])

	return take_damage(actual_damage, true)


## Permanent injuries (meta mechanic)
func apply_permanent_injury(injury: Dictionary) -> void:
	"""Apply a permanent stat penalty that persists across saves"""
	permanent_injuries.append(injury)

	if injury.has("stat"):
		var stat = injury["stat"]
		var penalty = injury.get("penalty", 0)

		match stat:
			"max_hp":
				max_hp = max(1, max_hp - penalty)
				current_hp = min(current_hp, max_hp)
			"attack":
				attack = max(1, attack - penalty)
			"defense":
				defense = max(1, defense - penalty)
			"magic":
				magic = max(1, magic - penalty)
			"speed":
				speed = max(1, speed - penalty)


## Turn management
func start_turn() -> void:
	"""Called at the start of this combatant's turn"""
	is_defending = false


func end_turn() -> void:
	"""Called at the end of this combatant's turn"""
	update_buff_durations()


func reset_for_new_round() -> void:
	"""Reset per-round state"""
	is_defending = false


## Utility
func get_hp_percentage() -> float:
	return float(current_hp) / float(max_hp) * 100.0


func get_mp_percentage() -> float:
	return float(current_mp) / float(max_mp) * 100.0


func to_dict() -> Dictionary:
	"""Serialize combatant state for saving"""
	return {
		"name": combatant_name,
		"max_hp": max_hp,
		"max_mp": max_mp,
		"current_hp": current_hp,
		"current_mp": current_mp,
		"current_ap": current_ap,
		"attack": attack,
		"defense": defense,
		"magic": magic,
		"speed": speed,
		"status_effects": status_effects.duplicate(),
		"permanent_injuries": permanent_injuries.duplicate(),
		"is_alive": is_alive
	}


func from_dict(data: Dictionary) -> void:
	"""Restore combatant state from saved data"""
	if data.has("name"):
		combatant_name = data["name"]
	if data.has("max_hp"):
		max_hp = data["max_hp"]
	if data.has("max_mp"):
		max_mp = data["max_mp"]
	if data.has("current_hp"):
		current_hp = data["current_hp"]
	if data.has("current_mp"):
		current_mp = data["current_mp"]
	if data.has("current_ap"):
		current_ap = data["current_ap"]
	if data.has("attack"):
		attack = data["attack"]
	if data.has("defense"):
		defense = data["defense"]
	if data.has("magic"):
		magic = data["magic"]
	if data.has("speed"):
		speed = data["speed"]
	if data.has("status_effects"):
		status_effects = data["status_effects"].duplicate()
	if data.has("permanent_injuries"):
		permanent_injuries = data["permanent_injuries"].duplicate()
	if data.has("is_alive"):
		is_alive = data["is_alive"]
