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
		push_warning("[PassiveSystem] passives.json not found at %s — falling back to hardcoded defaults" % file_path)
		_create_default_passives()
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		## Tick 165: surface the file-open failure (silent fallback
		## pre-fix). Same canonical pattern as JobSystem +
		## EquipmentSystem after this tick.
		push_warning("[PassiveSystem] passives.json exists but FileAccess.open failed — falling back to hardcoded defaults")
		_create_default_passives()
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		push_warning("[PassiveSystem] passives.json parse error: %s — falling back to hardcoded defaults" % json.get_error_message())
		_create_default_passives()
		return
	## Tick 165: Dictionary check — pre-fix `passives = json.data`
	## directly assigned without verifying shape. An Array root
	## would make passives.size() report a count but every
	## get_passive() call would fail. push_warning surfaces the
	## real cause instead of letting downstream null derefs cascade.
	if not (json.data is Dictionary):
		push_warning("[PassiveSystem] passives.json parsed but root is not a Dictionary — falling back to hardcoded defaults")
		_create_default_passives()
		return

	passives = json.data
	print("Loaded %d passives" % passives.size())


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
		# Tick 327: mp_boost was the natural pair to hp_boost (same
		# category, same +30% pattern) but was MISSING from the defaults
		# fallback. Mage-class passive selection in passives.json
		# references it. If both jobs.json and passives.json failed to
		# load, mp_boost equips silently failed (push_warning in
		# equip_passive's "passive_id not found" path), but a player who
		# DOES have passives.json loaded successfully could still hit
		# the JSON happy path — the defaults gap is a fallback-only
		# bug. Same omission class as tick 319 (encore).
		"mp_boost": {
			"id": "mp_boost",
			"name": "MP Boost",
			"category": PassiveCategory.DEFENSIVE,
			"description": "+30% max MP",
			"stat_mods": {
				"max_mp_multiplier": 1.3
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
		# Tick 319: encore is Bard's default passive (referenced by
		# JobSystem._create_default_jobs:209) but was MISSING from this
		# defaults fallback. If both jobs.json AND passives.json failed
		# to load (push_warning on each), equip_passive("encore") would
		# fire its "passive_id not found in passives table" warning and
		# the Bard's passive slot would stay empty. Mirrors data/passives.json
		# exactly: stat_mods empty, meta_effects.song_duration_bonus=1.
		"encore": {
			"id": "encore",
			"name": "Encore",
			"category": PassiveCategory.UTILITY,
			"description": "Song buffs and debuffs last 1 extra turn",
			"stat_mods": {},
			"meta_effects": {
				"song_duration_bonus": 1
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
	"""Equip a passive to a combatant."""
	if not combatant or not is_instance_valid(combatant):
		push_warning("[PassiveSystem] equip_passive: invalid combatant — equip failed")
		return false
	if not can_equip_passive(combatant, passive_id):
		if not passives.has(passive_id):
			push_warning("[PassiveSystem] equip_passive: passive_id '%s' not found in passives table — equip failed" % passive_id)
		elif combatant.equipped_passives.size() >= combatant.max_passive_slots:
			push_warning("[PassiveSystem] equip_passive: %s slot full (%d/%d) — equip of '%s' failed" % [combatant.combatant_name, combatant.equipped_passives.size(), combatant.max_passive_slots, passive_id])
		elif passive_id in combatant.equipped_passives:
			push_warning("[PassiveSystem] equip_passive: '%s' already equipped on %s — equip failed (idempotency check)" % [passive_id, combatant.combatant_name])
		else:
			push_warning("[PassiveSystem] equip_passive: '%s' cannot equip on %s (unknown reason — can_equip_passive returned false but no specific cause matched)" % [passive_id, combatant.combatant_name])
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
		push_warning("[PassiveSystem] unequip_passive: '%s' not currently equipped on %s — unequip failed" % [passive_id, combatant.combatant_name])
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
				_compose_mod(total_mods, mod_key, mod_value)

		# Apply conditional mods (like Last Stand)
		## Tick 377: generalize the condition parser. Pre-fix only
		## `hp_below_25` was recognized — any other passive condition
		## key (hp_below_50, hp_above_75, mp_below_25, etc.) was
		## silently ignored. The single-threshold limitation made
		## conditional_mods a graveyard for future authoring: write a
		## hp_below_50 conditional and watch it never fire.
		##
		## New key shape (backward-compatible with hp_below_25):
		##   <stat>_<comparator>_<threshold_int>
		## where stat ∈ {hp, mp}, comparator ∈ {below, above}, threshold
		## ∈ [0, 100]. Examples: hp_below_25, hp_above_75, mp_below_30.
		## Unknown keys are skipped silently per the old contract; the
		## generic shape just removes the hardcoded 25-only ceiling.
		if passive.has("conditional_mods"):
			var hp_pct: float = combatant.get_hp_percentage() / 100.0
			var mp_pct: float = combatant.get_mp_percentage() / 100.0 if combatant.has_method("get_mp_percentage") else 1.0
			for cond_key in passive["conditional_mods"].keys():
				if not _conditional_key_satisfied(str(cond_key), hp_pct, mp_pct):
					continue
				for mod_key in passive["conditional_mods"][cond_key]:
					var mod_value = passive["conditional_mods"][cond_key][mod_key]
					_compose_mod(total_mods, mod_key, mod_value)

	return total_mods


## Tick 377: parse a conditional_mods key like "hp_below_25" /
## "mp_above_50" and return true if the combatant satisfies the
## comparison. Returns false for unknown shape (preserves the
## silent-ignore behavior the old code had for non-hp_below_25 keys).
static func _conditional_key_satisfied(key: String, hp_pct: float, mp_pct: float) -> bool:
	var parts: PackedStringArray = key.split("_")
	if parts.size() != 3:
		return false
	var stat: String = parts[0]
	var comparator: String = parts[1]
	var threshold_raw: String = parts[2]
	if not threshold_raw.is_valid_int():
		return false
	var threshold: float = float(threshold_raw.to_int()) / 100.0
	var value: float = 1.0
	match stat:
		"hp":
			value = hp_pct
		"mp":
			value = mp_pct
		_:
			return false
	match comparator:
		"below":
			return value < threshold
		"above":
			return value > threshold
		_:
			return false


## Compose a single passive stat-mod into the accumulator dict, initializing
## any key that isn't yet present with the appropriate identity element
## (1.0 for *_multiplier keys, 0.0 for additive keys). Without this guard,
## stat_mods that introduce a new key (e.g. data/passives.json's
## `steal_boost` adds `steal_chance` — not in the initial defaults dict)
## triggered `null +=`/`null *=` runtime errors when the passive was
## equipped, because Dictionary[missing_key] returns null in Godot 4.
static func _compose_mod(total_mods: Dictionary, mod_key: String, mod_value: float) -> void:
	if mod_key.ends_with("_multiplier"):
		if not total_mods.has(mod_key):
			total_mods[mod_key] = 1.0
		total_mods[mod_key] *= mod_value
	else:
		if not total_mods.has(mod_key):
			total_mods[mod_key] = 0.0
		total_mods[mod_key] += mod_value


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
