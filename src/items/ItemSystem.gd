extends Node

## ItemSystem - Manages consumable items and their effects
## Items can heal, restore MP, cure status effects, and provide buffs

signal item_used(user: Combatant, item_id: String, targets: Array)

## Loaded item data
var items: Dictionary = {}

## Item categories
enum ItemCategory {
	CONSUMABLE,  # HP/MP restoration
	BUFF,        # Temporary stat boosts
	CURATIVE,    # Status effect removal
	OFFENSIVE,   # Damage items
	META         # Meta-game items
}

## Item target types
enum TargetType {
	SINGLE_ALLY,
	ALL_ALLIES,
	SINGLE_ENEMY,
	ALL_ENEMIES,
	SELF
}


func _ready() -> void:
	_load_item_data()


func _load_item_data() -> void:
	"""Load item definitions from data/items.json"""
	var file_path = "res://data/items.json"

	if not FileAccess.file_exists(file_path):
		print("Warning: items.json not found, using default items")
		_create_default_items()
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var parse_result = json.parse(json_string)

		if parse_result == OK:
			if json.data is Dictionary:
				items = json.data
				print("Loaded %d items" % items.size())
			else:
				print("Error: items.json data is not a valid dictionary")
				_create_default_items()
		else:
			print("Error parsing items.json: ", json.get_error_message())
			_create_default_items()
	else:
		_create_default_items()


func _create_default_items() -> void:
	"""Create default items if file doesn't exist"""
	items = {
		# HP restoration
		"potion": {
			"id": "potion",
			"name": "Potion",
			"category": ItemCategory.CONSUMABLE,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Restores 50 HP",
			"effects": {
				"heal_hp": 50
			},
			"cost": 50
		},
		"hi_potion": {
			"id": "hi_potion",
			"name": "Hi-Potion",
			"category": ItemCategory.CONSUMABLE,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Restores 200 HP",
			"effects": {
				"heal_hp": 200
			},
			"cost": 200
		},
		"mega_potion": {
			"id": "mega_potion",
			"name": "Mega Potion",
			"category": ItemCategory.CONSUMABLE,
			"target_type": TargetType.ALL_ALLIES,
			"description": "Restores 100 HP to all allies",
			"effects": {
				"heal_hp": 100
			},
			"cost": 400
		},
		"elixir": {
			"id": "elixir",
			"name": "Elixir",
			"category": ItemCategory.CONSUMABLE,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Fully restores HP and MP",
			"effects": {
				"heal_hp_percent": 100,
				"heal_mp_percent": 100
			},
			"cost": 1000
		},

		# MP restoration
		"ether": {
			"id": "ether",
			"name": "Ether",
			"category": ItemCategory.CONSUMABLE,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Restores 30 MP",
			"effects": {
				"heal_mp": 30
			},
			"cost": 150
		},
		"hi_ether": {
			"id": "hi_ether",
			"name": "Hi-Ether",
			"category": ItemCategory.CONSUMABLE,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Restores 100 MP",
			"effects": {
				"heal_mp": 100
			},
			"cost": 500
		},

		# Status effect cures
		"antidote": {
			"id": "antidote",
			"name": "Antidote",
			"category": ItemCategory.CURATIVE,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Cures poison",
			"effects": {
				"cure_status": ["poison"]
			},
			"cost": 80
		},
		"echo_herbs": {
			"id": "echo_herbs",
			"name": "Echo Herbs",
			"category": ItemCategory.CURATIVE,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Cures silence",
			"effects": {
				"cure_status": ["silence"]
			},
			"cost": 100
		},
		"remedy": {
			"id": "remedy",
			"name": "Remedy",
			"category": ItemCategory.CURATIVE,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Cures all status effects",
			"effects": {
				"cure_all_status": true
			},
			"cost": 300
		},
		"phoenix_down": {
			"id": "phoenix_down",
			"name": "Phoenix Down",
			"category": ItemCategory.CURATIVE,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Revives a fallen ally with 25% HP",
			"effects": {
				"revive": true,
				"heal_hp_percent": 25
			},
			"cost": 500
		},

		# Buff items
		"power_drink": {
			"id": "power_drink",
			"name": "Power Drink",
			"category": ItemCategory.BUFF,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Increases attack for 3 turns",
			"effects": {
				"add_buff": {
					"type": "attack_up",
					"power": 1.5,
					"duration": 3
				}
			},
			"cost": 200
		},
		"speed_tonic": {
			"id": "speed_tonic",
			"name": "Speed Tonic",
			"category": ItemCategory.BUFF,
			"target_type": TargetType.SINGLE_ALLY,
			"description": "Increases speed for 3 turns",
			"effects": {
				"add_buff": {
					"type": "speed_up",
					"power": 1.5,
					"duration": 3
				}
			},
			"cost": 200
		},

		# Offensive items
		"bomb_fragment": {
			"id": "bomb_fragment",
			"name": "Bomb Fragment",
			"category": ItemCategory.OFFENSIVE,
			"target_type": TargetType.SINGLE_ENEMY,
			"description": "Deals 100 fire damage",
			"effects": {
				"damage": 100,
				"element": "fire"
			},
			"cost": 150
		},
		"arctic_wind": {
			"id": "arctic_wind",
			"name": "Arctic Wind",
			"category": ItemCategory.OFFENSIVE,
			"target_type": TargetType.ALL_ENEMIES,
			"description": "Deals 80 ice damage to all enemies",
			"effects": {
				"damage": 80,
				"element": "ice"
			},
			"cost": 300
		}
	}


## Item usage
func use_item(user: Combatant, item_id: String, targets: Array[Combatant]) -> bool:
	"""Use an item on target(s)"""
	var item = get_item(item_id)
	if item.is_empty():
		print("Error: Item '%s' not found" % item_id)
		return false

	if not item.has("effects"):
		print("Error: Item has no effects")
		return false

	# Apply item effects to each target
	for target in targets:
		if not target or not is_instance_valid(target):
			continue
		_apply_item_effects(user, target, item)

	item_used.emit(user, item_id, targets)
	print("%s used %s" % [user.combatant_name, item["name"]])
	return true


func _apply_item_effects(user: Combatant, target: Combatant, item: Dictionary) -> void:
	"""Apply item effects to a target"""
	var effects = item["effects"]

	# HP healing (flat amount)
	if effects.has("heal_hp"):
		var heal_amount = effects["heal_hp"]
		target.heal(heal_amount)
		print("  → %s recovered %d HP" % [target.combatant_name, heal_amount])

	# HP healing (percentage)
	if effects.has("heal_hp_percent"):
		var heal_percent = effects["heal_hp_percent"]
		var heal_amount = int(target.max_hp * heal_percent / 100.0)
		target.heal(heal_amount)
		print("  → %s recovered %d HP (%d%%)" % [target.combatant_name, heal_amount, heal_percent])

	# MP restoration (flat amount)
	if effects.has("heal_mp"):
		var restore_amount = effects["heal_mp"]
		target.restore_mp(restore_amount)
		print("  → %s recovered %d MP" % [target.combatant_name, restore_amount])

	# MP restoration (percentage)
	if effects.has("heal_mp_percent"):
		var restore_percent = effects["heal_mp_percent"]
		var restore_amount = int(target.max_mp * restore_percent / 100.0)
		target.restore_mp(restore_amount)
		print("  → %s recovered %d MP (%d%%)" % [target.combatant_name, restore_amount, restore_percent])

	# Cure specific status effects
	if effects.has("cure_status"):
		for status in effects["cure_status"]:
			target.remove_status(status)
			print("  → %s cured of %s" % [target.combatant_name, status])

	# Cure all status effects
	if effects.has("cure_all_status") and effects["cure_all_status"]:
		target.status_effects.clear()
		print("  → %s cured of all status effects" % target.combatant_name)

	# Revive
	if effects.has("revive") and effects["revive"]:
		if not target.is_alive:
			target.revive()
			print("  → %s was revived!" % target.combatant_name)

	# Add buff
	if effects.has("add_buff"):
		var buff = effects["add_buff"]
		target.add_status(buff["type"])
		print("  → %s gained %s" % [target.combatant_name, buff["type"]])

	# Damage
	if effects.has("damage"):
		var damage = effects["damage"]
		var element = effects.get("element", "physical")

		# Apply elemental modifiers if target has weaknesses/resistances
		var multiplier = 1.0
		if target.elemental_weaknesses.has(element):
			multiplier = 1.5
		elif target.elemental_resistances.has(element):
			multiplier = 0.5

		damage = int(damage * multiplier)
		target.take_damage(damage)
		print("  → %s took %d %s damage" % [target.combatant_name, damage, element])


func get_item(item_id: String) -> Dictionary:
	"""Get item data by ID"""
	return items.get(item_id, {})


func get_items_by_category(category: ItemCategory) -> Array:
	"""Get all items of a specific category"""
	var filtered = []
	for item_id in items:
		var item = items[item_id]
		if item.get("category", ItemCategory.CONSUMABLE) == category:
			filtered.append(item)
	return filtered


func can_use_item(user: Combatant, item_id: String, target: Combatant) -> bool:
	"""Check if item can be used on target"""
	var item = get_item(item_id)
	if item.is_empty():
		return false

	# Validate BattleManager is available for party checks
	if not BattleManager:
		return false

	var target_type = item.get("target_type", TargetType.SINGLE_ALLY)

	# Can't use ally-targeting items on enemies (and vice versa)
	match target_type:
		TargetType.SINGLE_ALLY, TargetType.ALL_ALLIES, TargetType.SELF:
			# Check if target is an ally
			if not BattleManager.player_party.has(target):
				return false
		TargetType.SINGLE_ENEMY, TargetType.ALL_ENEMIES:
			# Check if target is an enemy
			if not BattleManager.enemy_party.has(target):
				return false

	return true
