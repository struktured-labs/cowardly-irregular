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

## Job reference and progression
var job = null
var job_level: int = 1
var job_exp: int = 0

## Character customization (appearance data)
var customization = null  # CharacterCustomization reference

## Passive system
var equipped_passives: Array[String] = []  # Passive IDs
var max_passive_slots: int = 5
var learned_passives: Array[String] = []  # All unlocked passives

## Learned abilities (purchased from magic shops, persist across job changes)
var learned_abilities: Array[String] = []

## Equipment system
var equipped_weapon: String = ""  # Weapon ID
var equipped_armor: String = ""   # Armor ID
var equipped_accessory: String = ""  # Accessory ID

## Inventory system
var inventory: Dictionary = {}  # {item_id: quantity}

## Base stats (before modifiers)
var base_max_hp: int = 100
var base_max_mp: int = 50
var base_attack: int = 10
var base_defense: int = 10
var base_magic: int = 10
var base_speed: int = 10

## Turn state
var queued_actions: Array[Dictionary] = []
var turn_order_value: float = 0.0
var doom_counter: int = -1  # Death Sentence countdown (-1 = not doomed)

## Command memory - remembers last menu selections
var last_menu_selection: String = ""  # Top-level: "attack_menu", "ability_menu", "item_menu", etc.
var last_attack_selection: String = ""  # Attack target if Attack was chosen (e.g., "attack_0")
var last_ability_selection: String = ""  # Ability submenu ID if Abilities was chosen
var last_item_selection: String = ""  # Item submenu ID if Items was chosen


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


func execute_defer() -> void:
	"""Defer action: skip turn, reduce incoming damage (no AP cost, keeps natural gain)"""
	is_defending = true
	# Note: Defer doesn't give AP directly - it just doesn't cost the 1 AP that actions cost
	# The natural +1 AP per turn is what accumulates when deferring


func execute_advance(actions: Array[Dictionary]) -> void:
	"""Advance action: queue multiple actions, spending AP"""
	var ap_cost = actions.size() - 1  # First action is free
	if spend_ap(ap_cost):
		queued_actions = actions.duplicate()


## Combat actions
func take_damage(amount: int, is_magical: bool = false) -> int:
	"""Apply damage considering defense/magic defense and defending state"""
	# Use attack^2 / (attack + defense) formula for smoother scaling
	# Defense reduces damage but never makes it negligible
	var def_value = defense if not is_magical else int(defense * 0.5)
	var actual_damage = int((amount * amount) / float(amount + def_value))
	actual_damage = max(1, actual_damage)  # Always at least 1 damage

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
		"is_alive": is_alive,
		"learned_abilities": learned_abilities.duplicate()
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
	if data.has("learned_abilities"):
		learned_abilities.clear()
		for ability_id in data["learned_abilities"]:
			learned_abilities.append(ability_id)


func learn_ability(ability_id: String) -> void:
	"""Learn a new ability (from magic shop purchase)"""
	if not ability_id in learned_abilities:
		learned_abilities.append(ability_id)
		print("%s learned ability: %s" % [combatant_name, ability_id])


func has_learned_ability(ability_id: String) -> bool:
	"""Check if this combatant has learned a specific ability"""
	return ability_id in learned_abilities


## Stat recalculation with modifiers
func recalculate_stats() -> void:
	"""Recalculate all stats based on base stats + modifiers"""
	# Start with base stats
	max_hp = base_max_hp
	max_mp = base_max_mp
	attack = base_attack
	defense = base_defense
	magic = base_magic
	speed = base_speed

	# Apply job modifiers (if JobSystem is available)
	if job and job.has("stat_modifiers"):
		var job_mods = job["stat_modifiers"]
		if job_mods.has("max_hp"):
			max_hp = job_mods["max_hp"]
		if job_mods.has("max_mp"):
			max_mp = job_mods["max_mp"]
		if job_mods.has("attack"):
			attack = job_mods["attack"]
		if job_mods.has("defense"):
			defense = job_mods["defense"]
		if job_mods.has("magic"):
			magic = job_mods["magic"]
		if job_mods.has("speed"):
			speed = job_mods["speed"]

	# Apply job level bonuses (+2% all stats per level)
	var level_mult = 1.0 + (job_level - 1) * 0.02
	max_hp = int(max_hp * level_mult)
	max_mp = int(max_mp * level_mult)
	attack = int(attack * level_mult)
	defense = int(defense * level_mult)
	magic = int(magic * level_mult)
	speed = int(speed * level_mult)

	# Apply passive modifiers (if PassiveSystem is available)
	if has_node("/root/PassiveSystem"):
		var passive_mods = get_node("/root/PassiveSystem").get_passive_mods(self)

		max_hp = int(max_hp * passive_mods.get("max_hp_multiplier", 1.0))
		max_mp = int(max_mp * passive_mods.get("max_mp_multiplier", 1.0))
		attack = int(attack * passive_mods.get("attack_multiplier", 1.0))
		defense = int(defense * passive_mods.get("defense_multiplier", 1.0))
		magic = int(magic * passive_mods.get("magic_multiplier", 1.0))
		speed = int(speed * passive_mods.get("speed_multiplier", 1.0))

	# Apply equipment modifiers (if EquipmentSystem is available)
	if has_node("/root/EquipmentSystem"):
		var equip_mods = get_node("/root/EquipmentSystem").get_equipment_mods(self)

		max_hp += equip_mods.get("max_hp", 0)
		max_mp += equip_mods.get("max_mp", 0)
		attack += equip_mods.get("attack", 0)
		defense += equip_mods.get("defense", 0)
		magic += equip_mods.get("magic", 0)
		speed += equip_mods.get("speed", 0)

	# Apply permanent injuries (reductions)
	for injury in permanent_injuries:
		if injury.has("stat") and injury.has("penalty"):
			match injury["stat"]:
				"max_hp":
					max_hp = max(1, max_hp - injury["penalty"])
				"attack":
					attack = max(1, attack - injury["penalty"])
				"defense":
					defense = max(1, defense - injury["penalty"])
				"magic":
					magic = max(1, magic - injury["penalty"])
				"speed":
					speed = max(1, speed - injury["penalty"])

	# Clamp current HP/MP to new maxes
	current_hp = min(current_hp, max_hp)
	current_mp = min(current_mp, max_mp)


func gain_job_exp(amount: int) -> void:
	"""Gain job experience and level up if threshold met"""
	job_exp += amount
	var exp_for_next_level = job_level * 100  # Simple formula: level * 100

	if job_exp >= exp_for_next_level:
		job_level += 1
		job_exp -= exp_for_next_level
		print("%s reached job level %d!" % [combatant_name, job_level])
		recalculate_stats()

		# TODO: Unlock new abilities/passives at certain levels


func learn_passive(passive_id: String) -> void:
	"""Learn a new passive ability"""
	if not passive_id in learned_passives:
		learned_passives.append(passive_id)
		print("%s learned passive: %s" % [combatant_name, passive_id])


## Inventory management
func add_item(item_id: String, quantity: int = 1) -> void:
	"""Add item(s) to inventory"""
	if inventory.has(item_id):
		inventory[item_id] += quantity
	else:
		inventory[item_id] = quantity


func remove_item(item_id: String, quantity: int = 1) -> bool:
	"""Remove item(s) from inventory. Returns false if insufficient quantity."""
	if not inventory.has(item_id) or inventory[item_id] < quantity:
		return false

	inventory[item_id] -= quantity
	if inventory[item_id] <= 0:
		inventory.erase(item_id)

	return true


func has_item(item_id: String, quantity: int = 1) -> bool:
	"""Check if inventory contains item(s)"""
	return inventory.has(item_id) and inventory[item_id] >= quantity


func get_item_count(item_id: String) -> int:
	"""Get quantity of an item in inventory"""
	return inventory.get(item_id, 0)
