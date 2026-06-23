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
		push_warning("[ItemSystem] items.json not found at %s — falling back to hardcoded defaults" % file_path)
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
				push_warning("[ItemSystem] items.json parsed but root is not a Dictionary — falling back to hardcoded defaults")
				_create_default_items()
		else:
			push_warning("[ItemSystem] items.json parse error: %s — falling back to hardcoded defaults" % json.get_error_message())
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

	# Non-target-bound effects — applied once, not per-target.
	_apply_global_item_effects(item)

	item_used.emit(user, item_id, targets)
	print("%s used %s" % [user.combatant_name, item["name"]])
	return true


func _apply_global_item_effects(item: Dictionary) -> void:
	"""Apply item effects that act on world/battle state rather than a Combatant.

	These keys are NOT per-target: applying them inside the per-target loop
	would multiply the effect by the target count. Handled here exactly once.

	Caller-handled keys (escape_battle, save_point_only) are intentionally NOT
	resolved here — ItemSystem has no battle/menu reference — but they ARE
	recognized so the silent-consume class of bug is caught by the handler
	coverage regression test:
	  - escape_battle: gated by the battle caller (BattleManager._execute_item)
	    before removing the item; non-battle use is a no-op.
	  - save_point_only: gated by the menu use site, which must refuse use when
	    the party is not at a save point.
	  - all_party: redundant with target_type ALL_ALLIES (callers already expand
	    targets to the whole party); no action needed here.
	"""
	var effects = item.get("effects", {})
	if typeof(effects) != TYPE_DICTIONARY:
		return

	# Repel — suppress overworld encounters for N steps via EncounterSystem.
	# Use a /root/ lookup (NOT Engine.has_singleton, which never sees autoloads).
	if effects.has("repel_steps"):
		var encounter_system = get_node_or_null("/root/EncounterSystem")
		if encounter_system and encounter_system.has_method("use_repel"):
			encounter_system.use_repel(int(effects["repel_steps"]))
			print("  → Repel active for %d steps" % int(effects["repel_steps"]))
		else:
			push_warning("ItemSystem: repel_steps used but EncounterSystem unavailable")


func _apply_item_effects(user: Combatant, target: Combatant, item: Dictionary) -> void:
	"""Apply item effects to a target"""
	var effects = item["effects"]

	# Revive MUST come first when it's part of the effect bundle. Otherwise
	# heal_hp / heal_hp_percent below would no-op against a dead target
	# (heal() returns 0 if !is_alive), then revive() would set HP to its
	# 50% default — ignoring the heal_hp_percent the item authored.
	#
	# When revive consumes a heal value (Phoenix Down's "25% HP"), we
	# track it via _heal_consumed_by_revive so the same heal isn't applied
	# again as a bonus on top of the revived HP.
	var _heal_consumed_by_revive: bool = false

	# Revive
	if effects.has("revive") and effects["revive"]:
		if not target.is_alive:
			var revive_hp: int = 0  # 0 = revive() default of 50% max_hp
			if effects.has("heal_hp_percent"):
				revive_hp = max(1, int(target.max_hp * effects["heal_hp_percent"] / 100.0))
				_heal_consumed_by_revive = true
			elif effects.has("heal_hp"):
				revive_hp = max(1, int(effects["heal_hp"]))
				_heal_consumed_by_revive = true
			var hp_before_revive: int = target.current_hp
			target.revive(revive_hp)
			# Emit healing_done so the revived HP shows up as a popup + glow,
			# the same visual the player sees when they get healed normally.
			# Without this, revive items silently restore HP — the player has
			# to look at the bar to notice anything happened.
			var revived_amount: int = target.current_hp - hp_before_revive
			if revived_amount > 0 and BattleManager:
				BattleManager.healing_done.emit(target, revived_amount)
			if _heal_consumed_by_revive:
				print("  → %s was revived with %d HP!" % [target.combatant_name, target.current_hp])
			else:
				print("  → %s was revived!" % target.combatant_name)

	# HP healing (flat amount) — skip if revive already consumed it.
	if effects.has("heal_hp") and not _heal_consumed_by_revive:
		var heal_amount = effects["heal_hp"]
		var actual = target.heal(heal_amount)
		# Emit healing_done so BattleScene's heal popup + glow fire — without
		# this, items that heal would tick the HP bar silently.
		if actual > 0 and BattleManager:
			BattleManager.healing_done.emit(target, actual)
		print("  → %s recovered %d HP" % [target.combatant_name, actual])

	# HP healing (percentage) — skip if revive already consumed it.
	if effects.has("heal_hp_percent") and not _heal_consumed_by_revive:
		var heal_percent = effects["heal_hp_percent"]
		var heal_amount = int(target.max_hp * heal_percent / 100.0)
		var actual_p = target.heal(heal_amount)
		if actual_p > 0 and BattleManager:
			BattleManager.healing_done.emit(target, actual_p)
		print("  → %s recovered %d HP (%d%%)" % [target.combatant_name, actual_p, heal_percent])

	# MP restoration (flat amount). Surfaced through healing_done as the
	# visual proxy — same convention as the Free Move MP-restore actions
	# (Pray / Channel / Riff), per CLAUDE.md "healing_done (green popup)
	# not damage_dealt (would show as crit damage)".
	if effects.has("heal_mp"):
		var restore_amount = effects["heal_mp"]
		var actual_mp = target.restore_mp(restore_amount)
		if actual_mp > 0 and BattleManager:
			BattleManager.healing_done.emit(target, actual_mp)
		print("  → %s recovered %d MP" % [target.combatant_name, actual_mp])

	# MP restoration (percentage)
	if effects.has("heal_mp_percent"):
		var restore_percent = effects["heal_mp_percent"]
		var restore_amount = int(target.max_mp * restore_percent / 100.0)
		var actual_mp_p = target.restore_mp(restore_amount)
		if actual_mp_p > 0 and BattleManager:
			BattleManager.healing_done.emit(target, actual_mp_p)
		print("  → %s recovered %d MP (%d%%)" % [target.combatant_name, actual_mp_p, restore_percent])

	# Cure specific status effects
	if effects.has("cure_status"):
		for status in effects["cure_status"]:
			target.remove_status(status)
			print("  → %s cured of %s" % [target.combatant_name, status])

	# Cure all status effects
	# Clear both arrays to avoid stale status_durations entries that would
	# tick down indefinitely without ever being removed (remove_status()
	# short-circuits when the status isn't in status_effects).
	if effects.has("cure_all_status") and effects["cure_all_status"]:
		target.status_effects.clear()
		target.status_durations.clear()
		print("  → %s cured of all status effects" % target.combatant_name)

	# Add buff
	# Buff consumables (power_drink/speed_tonic/defense_tonic/magic_tonic) carry
	# {type: attack_up/speed_up/defense_up/magic_up, power: 1.5, duration: 3}.
	# Pre-fix this called add_status(buff["type"]) which only appended an inert
	# status string — get_buffed_stat reads ONLY active_buffs, so the item was
	# consumed for zero stat benefit. We must call add_buff() to create a real
	# entry. Use the JSON key `power` (NOT `modifier`) and a distinct per-type
	# effect name so add_buff's same-effect refresh logic doesn't collide an
	# attack buff with a defense buff.
	if effects.has("add_buff"):
		var buff = effects["add_buff"]
		var _buff_stat_map = {"attack_up": "attack", "speed_up": "speed", "defense_up": "defense", "magic_up": "magic"}
		var _buff_type = str(buff.get("type", "attack_up"))
		var _stat = _buff_stat_map.get(_buff_type, "attack")
		var _effect_name = _buff_type.capitalize()  # human-readable effect label for active_buffs
		var _power = float(buff.get("power", 1.5))
		var _duration = int(buff.get("duration", 3))
		target.add_buff(_effect_name, _stat, _power, _duration)
		print("  → %s gained %s (%.1fx %s for %d turns)" % [target.combatant_name, _buff_type, _power, _stat, _duration])

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

		# Bonus damage vs undead — items like holy_water carry this flag and
		# expect 2x damage against monsters flagged `undead: true` in the
		# bestiary (skeleton, specter, cursed_armor, pipe_phantom, data_
		# wraith). Pre-fix this flag was in items.json but use_item never
		# checked it — holy_water dealt flat damage regardless of target,
		# making the item identical to a generic damage potion.
		if effects.get("bonus_vs_undead", false) and _is_target_undead(target):
			multiplier *= 2.0

		damage = int(damage * multiplier)
		var actual_damage: int = target.take_damage(damage)
		# Emit damage_dealt so BattleScene's damage popup + screen shake
		# fire. Without this, throwing a Holy Water at a skeleton would
		# silently tick the enemy's HP bar — no number, no shake, no
		# elemental tint. Items don't crit, so is_crit is always false.
		if actual_damage > 0 and BattleManager:
			BattleManager.damage_dealt.emit(target, actual_damage, false, element, multiplier)
		print("  → %s took %d %s damage" % [target.combatant_name, actual_damage, element])


func _is_target_undead(target) -> bool:
	## Looks up the target's monster_type meta (set by BattleEnemySpawner
	## from the monsters_data JSON) and asks the bestiary whether that
	## monster has `undead: true`. Returns false safely when target is
	## null, not a monster (PC), or the bestiary doesn't know the id.
	## Used by the damage path to apply the bonus_vs_undead 2x multiplier.
	if target == null or not target.has_meta("monster_type"):
		return false
	var monster_id: String = str(target.get_meta("monster_type"))
	if monster_id == "":
		return false
	var data: Dictionary = BestiarySystem.get_monster_data(monster_id)
	return bool(data.get("undead", false))


## Effect keys that _apply_item_effects / _apply_global_item_effects act on
## directly within ItemSystem. `element` and `bonus_vs_undead` are modifiers
## read by the `damage` branch (not standalone effects).
const _LOCALLY_HANDLED_EFFECT_KEYS := [
	"revive", "heal_hp", "heal_hp_percent", "heal_mp", "heal_mp_percent",
	"cure_status", "cure_all_status", "add_buff", "damage", "element",
	"bonus_vs_undead", "repel_steps",
]

## Effect keys ItemSystem deliberately does NOT resolve itself because they
## require a battle/menu context the system has no reference to. They are
## recognized (not silently consumed) and routed to a documented caller:
##   escape_battle  -> BattleManager._execute_item gates escape before consume
##   save_point_only -> menu use site refuses use when not at a save point
##   all_party       -> redundant with target_type ALL_ALLIES (caller expands)
const _CALLER_HANDLED_EFFECT_KEYS := [
	"escape_battle", "save_point_only", "all_party",
]


func is_effect_key_handled(key: String) -> bool:
	"""True if `key` is handled by ItemSystem or routed to a documented caller.

	Used by the handler-coverage regression test to catch the silent-consume
	class of bug: a new effect key in items.json with no handler anywhere.
	"""
	return key in _LOCALLY_HANDLED_EFFECT_KEYS or key in _CALLER_HANDLED_EFFECT_KEYS


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
			if not "player_party" in BattleManager:
				return false
			if not BattleManager.player_party.has(target):
				return false
		TargetType.SINGLE_ENEMY, TargetType.ALL_ENEMIES:
			# Check if target is an enemy
			if not "enemy_party" in BattleManager:
				return false
			if not BattleManager.enemy_party.has(target):
				return false

	return true
