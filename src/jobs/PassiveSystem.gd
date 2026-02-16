extends Node

## PassiveSystem - Manages passive abilities and their effects
## Passives provide stat modifiers and special effects

signal passive_equipped(combatant: Combatant, passive_id: String)
signal passive_unequipped(combatant: Combatant, passive_id: String)

## Loaded passive data
var passives: Dictionary = {}

## Passive categories
enum PassiveCategory {
	OFFENSIVE,   # Damage/attack focused
	DEFENSIVE,   # Defense/survival focused
	UTILITY,     # Speed, MP, special effects
	TRADE_OFF,   # High risk, high reward
	META         # Meta-game effects
}


func _ready() -> void:
	_load_passive_data()


func _load_passive_data() -> void:
	"""Load passive definitions from data/passives.json"""
	var file_path = "res://data/passives.json"

	if not FileAccess.file_exists(file_path):
		print("Warning: passives.json not found, using default passives")
		_create_default_passives()
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var parse_result = json.parse(json_string)

		if parse_result == OK:
			passives = json.data
			print("Loaded %d passives" % passives.size())
		else:
			print("Error parsing passives.json: ", json.get_error_message())
			_create_default_passives()
	else:
		_create_default_passives()


func _create_default_passives() -> void:
	"""Create default passives if file doesn't exist"""
	passives = {
		# Offensive passives
		"weapon_mastery": {
			"id": "weapon_mastery",
			"name": "Weapon Mastery",
			"category": PassiveCategory.OFFENSIVE,
			"description": "+20% physical damage",
			"stat_mods": {
				"attack_multiplier": 1.2
			}
		},
		"magic_boost": {
			"id": "magic_boost",
			"name": "Magic Boost",
			"category": PassiveCategory.OFFENSIVE,
			"description": "+30% magic damage",
			"stat_mods": {
				"magic_multiplier": 1.3
			}
		},
		"critical_strike": {
			"id": "critical_strike",
			"name": "Critical Strike",
			"category": PassiveCategory.OFFENSIVE,
			"description": "+25% critical hit chance",
			"stat_mods": {
				"crit_chance": 0.25
			}
		},

		# Defensive passives
		"iron_skin": {
			"id": "iron_skin",
			"name": "Iron Skin",
			"category": PassiveCategory.DEFENSIVE,
			"description": "+25% defense",
			"stat_mods": {
				"defense_multiplier": 1.25
			}
		},
		"hp_boost": {
			"id": "hp_boost",
			"name": "HP Boost",
			"category": PassiveCategory.DEFENSIVE,
			"description": "+30% max HP",
			"stat_mods": {
				"max_hp_multiplier": 1.3
			}
		},
		"evasion_up": {
			"id": "evasion_up",
			"name": "Evasion Up",
			"category": PassiveCategory.DEFENSIVE,
			"description": "+20% dodge chance",
			"stat_mods": {
				"evasion": 0.2
			}
		},

		# Utility passives
		"speed_demon": {
			"id": "speed_demon",
			"name": "Speed Demon",
			"category": PassiveCategory.UTILITY,
			"description": "+40% speed",
			"stat_mods": {
				"speed_multiplier": 1.4
			}
		},
		"mp_efficiency": {
			"id": "mp_efficiency",
			"name": "MP Efficiency",
			"category": PassiveCategory.UTILITY,
			"description": "-25% MP costs",
			"stat_mods": {
				"mp_cost_multiplier": 0.75
			}
		},
		"healing_boost": {
			"id": "healing_boost",
			"name": "Healing Boost",
			"category": PassiveCategory.UTILITY,
			"description": "+50% healing power",
			"stat_mods": {
				"healing_multiplier": 1.5
			}
		},

		# Trade-off passives (high risk, high reward)
		"glass_cannon": {
			"id": "glass_cannon",
			"name": "Glass Cannon",
			"category": PassiveCategory.TRADE_OFF,
			"description": "+100% damage, -50% defense",
			"stat_mods": {
				"attack_multiplier": 2.0,
				"magic_multiplier": 2.0,
				"defense_multiplier": 0.5
			}
		},
		"berserker": {
			"id": "berserker",
			"name": "Berserker",
			"category": PassiveCategory.TRADE_OFF,
			"description": "+80% attack, cannot defend",
			"stat_mods": {
				"attack_multiplier": 1.8
			},
			"restrictions": {
				"cannot_defend": true
			}
		},
		"magic_amplifier": {
			"id": "magic_amplifier",
			"name": "Magic Amplifier",
			"category": PassiveCategory.TRADE_OFF,
			"description": "+100% magic damage, +150% MP costs",
			"stat_mods": {
				"magic_multiplier": 2.0,
				"mp_cost_multiplier": 2.5
			}
		},
		"reckless": {
			"id": "reckless",
			"name": "Reckless",
			"category": PassiveCategory.TRADE_OFF,
			"description": "+60% damage, -30% max HP",
			"stat_mods": {
				"attack_multiplier": 1.6,
				"magic_multiplier": 1.6,
				"max_hp_multiplier": 0.7
			}
		},
		"last_stand": {
			"id": "last_stand",
			"name": "Last Stand",
			"category": PassiveCategory.TRADE_OFF,
			"description": "+200% damage when HP < 25%, -20% max HP",
			"stat_mods": {
				"max_hp_multiplier": 0.8
			},
			"conditional_mods": {
				"hp_below_25": {
					"attack_multiplier": 3.0,
					"magic_multiplier": 3.0
				}
			}
		},

		# Meta passives
		"autobattle_verbs": {
			"id": "autobattle_verbs",
			"name": "Autobattle Verbs",
			"category": PassiveCategory.META,
			"description": "Unlocks advanced autobattle conditionals",
			"meta_effects": {
				"autobattle_advanced": true
			}
		},
		"formula_sight": {
			"id": "formula_sight",
			"name": "Formula Sight",
			"category": PassiveCategory.META,
			"description": "See damage formulas in battle",
			"meta_effects": {
				"show_formulas": true
			}
		},

		# Speculator passives
		"market_sense": {
			"id": "market_sense",
			"name": "Market Sense",
			"category": PassiveCategory.OFFENSIVE,
			"description": "Scaling bonuses based on global volatility band: more chaos = more power",
			"stat_mods": {},
			"meta_effects": {
				"volatility_scaling": true
			}
		}
	}


## Passive management
func equip_passive(combatant: Combatant, passive_id: String) -> bool:
	"""Equip a passive to a combatant"""
	if not combatant or not is_instance_valid(combatant):
		return false
	if not passives.has(passive_id):
		print("Error: Passive '%s' not found" % passive_id)
		return false

	if combatant.equipped_passives.size() >= combatant.max_passive_slots:
		print("Error: No passive slots available")
		return false

	if passive_id in combatant.equipped_passives:
		print("Error: Passive already equipped")
		return false

	combatant.equipped_passives.append(passive_id)
	combatant.recalculate_stats()

	passive_equipped.emit(combatant, passive_id)
	print("%s equipped %s" % [combatant.combatant_name, passives[passive_id]["name"]])
	return true


func unequip_passive(combatant: Combatant, passive_id: String) -> bool:
	"""Unequip a passive from a combatant"""
	if not combatant or not is_instance_valid(combatant):
		return false
	if not passive_id in combatant.equipped_passives:
		print("Error: Passive not equipped")
		return false

	combatant.equipped_passives.erase(passive_id)
	combatant.recalculate_stats()

	passive_unequipped.emit(combatant, passive_id)
	print("%s unequipped %s" % [combatant.combatant_name, passives[passive_id]["name"]])
	return true


func get_passive(passive_id: String) -> Dictionary:
	"""Get passive data by ID"""
	return passives.get(passive_id, {})


func get_passive_mods(combatant: Combatant) -> Dictionary:
	"""Calculate total passive modifiers for a combatant"""
	if not combatant or not is_instance_valid(combatant):
		return {}
	var total_mods = {
		"attack_multiplier": 1.0,
		"defense_multiplier": 1.0,
		"magic_multiplier": 1.0,
		"speed_multiplier": 1.0,
		"max_hp_multiplier": 1.0,
		"max_mp_multiplier": 1.0,
		"mp_cost_multiplier": 1.0,
		"healing_multiplier": 1.0,
		"crit_chance": 0.0,
		"evasion": 0.0
	}

	for passive_id in combatant.equipped_passives:
		var passive = get_passive(passive_id)
		if passive.is_empty():
			continue

		# Apply stat mods
		if passive.has("stat_mods"):
			for mod_key in passive["stat_mods"]:
				var mod_value = passive["stat_mods"][mod_key]

				# Multiplicative mods
				if mod_key.ends_with("_multiplier"):
					total_mods[mod_key] *= mod_value
				# Additive mods
				else:
					total_mods[mod_key] += mod_value

		# Apply conditional mods (like Last Stand)
		if passive.has("conditional_mods"):
			var hp_pct = combatant.get_hp_percentage() / 100.0

			if passive["conditional_mods"].has("hp_below_25") and hp_pct < 0.25:
				for mod_key in passive["conditional_mods"]["hp_below_25"]:
					var mod_value = passive["conditional_mods"]["hp_below_25"][mod_key]
					if mod_key.ends_with("_multiplier"):
						total_mods[mod_key] *= mod_value

	return total_mods


func get_passives_by_category(category: PassiveCategory) -> Array:
	"""Get all passives of a specific category"""
	var filtered = []
	for passive_id in passives:
		var passive = passives[passive_id]
		if passive.get("category", PassiveCategory.OFFENSIVE) == category:
			filtered.append(passive)
	return filtered


func can_equip_passive(combatant: Combatant, passive_id: String) -> bool:
	"""Check if combatant can equip this passive"""
	if not combatant or not is_instance_valid(combatant):
		return false
	var passive = get_passive(passive_id)
	if passive.is_empty():
		return false

	# Check slot limit
	if combatant.equipped_passives.size() >= combatant.max_passive_slots:
		return false

	# Check if already equipped
	if passive_id in combatant.equipped_passives:
		return false

	# Check job restrictions
	if passive.has("restrictions") and passive["restrictions"].has("jobs"):
		if combatant.job and combatant.job.has("id"):
			if not combatant.job["id"] in passive["restrictions"]["jobs"]:
				return false

	return true
