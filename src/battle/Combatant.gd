extends Node
class_name Combatant

## Base class for all battle participants (player characters and enemies)
## Manages stats, BP, status effects, and turn mechanics

signal hp_changed(old_value: int, new_value: int)
signal bp_changed(old_value: int, new_value: int)
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
var current_bp: int = 0  # Brave Points: -4 to +4 range
var is_defending: bool = false
var is_alive: bool = true

## Status effects
var status_effects: Array[String] = []
var permanent_injuries: Array[Dictionary] = []

## Job reference (will be set by JobSystem)
var job = null

## Turn state
var queued_actions: Array[Dictionary] = []
var turn_order_value: float = 0.0


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
func can_brave(bp_cost: int) -> bool:
	# Can go into BP debt up to -4
	return (current_bp - bp_cost) >= -4


func spend_bp(amount: int) -> bool:
	if not can_brave(amount):
		return false

	var old_bp = current_bp
	current_bp = clampi(current_bp - amount, -4, 4)
	bp_changed.emit(old_bp, current_bp)
	return true


func gain_bp(amount: int) -> void:
	var old_bp = current_bp
	current_bp = clampi(current_bp + amount, -4, 4)
	bp_changed.emit(old_bp, current_bp)


func execute_default() -> void:
	"""Default action: skip turn, gain +1 BP, reduce incoming damage"""
	is_defending = true
	gain_bp(1)


func execute_brave(actions: Array[Dictionary]) -> void:
	"""Brave action: queue multiple actions, spending BP"""
	var bp_cost = actions.size() - 1  # First action is free
	if spend_bp(bp_cost):
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
	# Process status effects, etc.
	pass


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
		"current_bp": current_bp,
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
	if data.has("current_bp"):
		current_bp = data["current_bp"]
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
