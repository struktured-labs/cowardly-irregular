extends Node

## EquipmentSystem - Manages weapons, armor, and accessories
## Equipment provides stat bonuses and special effects

signal equipment_equipped(combatant: Combatant, slot: String, item_id: String)
signal equipment_unequipped(combatant: Combatant, slot: String)

## Loaded equipment data
var weapons: Dictionary = {}
var armors: Dictionary = {}
var accessories: Dictionary = {}

## Equipment slots
enum EquipSlot {
	WEAPON,
	ARMOR,
	ACCESSORY
}


func _ready() -> void:
	_load_equipment_data()


func _load_equipment_data() -> void:
	"""Load equipment definitions from data/equipment.json"""
	var file_path = "res://data/equipment.json"

	if not FileAccess.file_exists(file_path):
		print("Warning: equipment.json not found, using default equipment")
		_create_default_equipment()
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var parse_result = json.parse(json_string)

		if parse_result == OK:
			var data = json.data
			if data is Dictionary:
				weapons = data.get("weapons", {})
				armors = data.get("armors", {})
				accessories = data.get("accessories", {})
				print("Loaded equipment: %d weapons, %d armors, %d accessories" % [weapons.size(), armors.size(), accessories.size()])
			else:
				print("Error: equipment.json data is not a valid dictionary")
				_create_default_equipment()
		else:
			print("Error parsing equipment.json: ", json.get_error_message())
			_create_default_equipment()
	else:
		_create_default_equipment()


func _create_default_equipment() -> void:
	"""Create default equipment if file doesn't exist"""
	weapons = {
		"bronze_sword": {
			"id": "bronze_sword",
			"name": "Bronze Sword",
			"description": "A basic iron sword",
			"stat_mods": {
				"attack": 5
			}
		},
		"iron_sword": {
			"id": "iron_sword",
			"name": "Iron Sword",
			"description": "A sturdy iron blade",
			"stat_mods": {
				"attack": 12
			}
		},
		"flame_sword": {
			"id": "flame_sword",
			"name": "Flame Sword",
			"description": "A blade wreathed in flames",
			"stat_mods": {
				"attack": 18,
				"magic": 5
			},
			"special_effects": {
				"fire_damage_bonus": 1.5
			}
		},
		"wooden_staff": {
			"id": "wooden_staff",
			"name": "Wooden Staff",
			"description": "A simple wooden staff",
			"stat_mods": {
				"magic": 8,
				"attack": 2
			}
		},
		"crystal_staff": {
			"id": "crystal_staff",
			"name": "Crystal Staff",
			"description": "A staff topped with a magic crystal",
			"stat_mods": {
				"magic": 20,
				"max_mp": 15
			}
		}
	}

	armors = {
		"leather_armor": {
			"id": "leather_armor",
			"name": "Leather Armor",
			"description": "Basic leather protection",
			"stat_mods": {
				"defense": 8,
				"max_hp": 10
			}
		},
		"iron_armor": {
			"id": "iron_armor",
			"name": "Iron Armor",
			"description": "Heavy iron plating",
			"stat_mods": {
				"defense": 18,
				"max_hp": 25,
				"speed": -3
			}
		},
		"mage_robe": {
			"id": "mage_robe",
			"name": "Mage Robe",
			"description": "Enchanted cloth robes",
			"stat_mods": {
				"defense": 5,
				"magic": 10,
				"max_mp": 20
			}
		},
		"dragon_mail": {
			"id": "dragon_mail",
			"name": "Dragon Mail",
			"description": "Armor made from dragon scales",
			"stat_mods": {
				"defense": 30,
				"max_hp": 50,
				"magic": 5
			},
			"special_effects": {
				"fire_resistance": true
			}
		}
	}

	accessories = {
		"power_ring": {
			"id": "power_ring",
			"name": "Power Ring",
			"description": "Increases physical strength",
			"stat_mods": {
				"attack": 10
			}
		},
		"magic_ring": {
			"id": "magic_ring",
			"name": "Magic Ring",
			"description": "Enhances magical power",
			"stat_mods": {
				"magic": 10
			}
		},
		"speed_boots": {
			"id": "speed_boots",
			"name": "Speed Boots",
			"description": "Increases movement speed",
			"stat_mods": {
				"speed": 15
			}
		},
		"hp_amulet": {
			"id": "hp_amulet",
			"name": "HP Amulet",
			"description": "Boosts maximum health",
			"stat_mods": {
				"max_hp": 40
			}
		},
		"mp_amulet": {
			"id": "mp_amulet",
			"name": "MP Amulet",
			"description": "Boosts maximum magic",
			"stat_mods": {
				"max_mp": 30
			}
		},
		"glass_amulet": {
			"id": "glass_amulet",
			"name": "Glass Amulet",
			"description": "Immense power, but fragile - +50% damage, -30% defense",
			"stat_mods": {
				"attack": 15,
				"magic": 15,
				"defense": -10
			}
		}
	}


## Equipment management
func equip_weapon(combatant: Combatant, weapon_id: String) -> bool:
	"""Equip a weapon"""
	if not weapons.has(weapon_id):
		print("Error: Weapon '%s' not found" % weapon_id)
		return false

	combatant.equipped_weapon = weapon_id
	combatant.recalculate_stats()

	equipment_equipped.emit(combatant, "weapon", weapon_id)
	print("%s equipped %s" % [combatant.combatant_name, weapons[weapon_id]["name"]])
	return true


func equip_armor(combatant: Combatant, armor_id: String) -> bool:
	"""Equip armor"""
	if not armors.has(armor_id):
		print("Error: Armor '%s' not found" % armor_id)
		return false

	combatant.equipped_armor = armor_id
	combatant.recalculate_stats()

	equipment_equipped.emit(combatant, "armor", armor_id)
	print("%s equipped %s" % [combatant.combatant_name, armors[armor_id]["name"]])
	return true


func equip_accessory(combatant: Combatant, accessory_id: String) -> bool:
	"""Equip accessory"""
	if not accessories.has(accessory_id):
		print("Error: Accessory '%s' not found" % accessory_id)
		return false

	combatant.equipped_accessory = accessory_id
	combatant.recalculate_stats()

	equipment_equipped.emit(combatant, "accessory", accessory_id)
	print("%s equipped %s" % [combatant.combatant_name, accessories[accessory_id]["name"]])
	return true


func unequip_slot(combatant: Combatant, slot: EquipSlot) -> bool:
	"""Unequip equipment from a slot"""
	match slot:
		EquipSlot.WEAPON:
			combatant.equipped_weapon = ""
		EquipSlot.ARMOR:
			combatant.equipped_armor = ""
		EquipSlot.ACCESSORY:
			combatant.equipped_accessory = ""

	combatant.recalculate_stats()
	equipment_unequipped.emit(combatant, EquipSlot.keys()[slot].to_lower())
	return true


func get_equipment_mods(combatant: Combatant) -> Dictionary:
	"""Calculate total equipment modifiers for a combatant"""
	var total_mods = {
		"attack": 0,
		"defense": 0,
		"magic": 0,
		"speed": 0,
		"max_hp": 0,
		"max_mp": 0
	}

	# Add weapon mods
	if not combatant.equipped_weapon.is_empty() and weapons.has(combatant.equipped_weapon):
		var weapon = weapons[combatant.equipped_weapon]
		if weapon.has("stat_mods"):
			for stat in weapon["stat_mods"]:
				if total_mods.has(stat):
					total_mods[stat] += weapon["stat_mods"][stat]

	# Add armor mods
	if not combatant.equipped_armor.is_empty() and armors.has(combatant.equipped_armor):
		var armor = armors[combatant.equipped_armor]
		if armor.has("stat_mods"):
			for stat in armor["stat_mods"]:
				if total_mods.has(stat):
					total_mods[stat] += armor["stat_mods"][stat]

	# Add accessory mods
	if not combatant.equipped_accessory.is_empty() and accessories.has(combatant.equipped_accessory):
		var accessory = accessories[combatant.equipped_accessory]
		if accessory.has("stat_mods"):
			for stat in accessory["stat_mods"]:
				if total_mods.has(stat):
					total_mods[stat] += accessory["stat_mods"][stat]

	return total_mods


func get_weapon(weapon_id: String) -> Dictionary:
	return weapons.get(weapon_id, {})


func get_armor(armor_id: String) -> Dictionary:
	return armors.get(armor_id, {})


func get_accessory(accessory_id: String) -> Dictionary:
	return accessories.get(accessory_id, {})
