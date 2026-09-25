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
	if not file:
		## Tick 166: surface the file-open failure (silent fallback
		## pre-fix). Same canonical 4-stage pattern as JobSystem +
		## EquipmentSystem + PassiveSystem from tick 165.
		push_warning("[ItemSystem] items.json exists but FileAccess.open failed — falling back to hardcoded defaults")
		_create_default_items()
		return

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
		## Tick 181: surface unknown-item failures. Pre-fix print()
		## only — a Use Item with a corrupted/missing id returned
		## false but the WHY was invisible. Catches save-format
		## drift and Scriptweaver custom items.
		push_warning("[ItemSystem] use_item: item_id '%s' not found in items table — use failed" % item_id)
		return false

	if not item.has("effects"):
		push_warning("[ItemSystem] use_item: item '%s' has no 'effects' field — authoring error in items.json" % item_id)
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


## F3 ruling (struktured, 2026-07-08): save_point_only items are FREE outside dungeons; inside a dungeon they only work beside a save crystal.
static func save_point_gate_reason(item: Dictionary, in_dungeon: bool, at_crystal: bool) -> String:
	if not item.get("effects", {}).get("save_point_only", false):
		return ""
	if not in_dungeon or at_crystal:
		return ""
	return "Too dangerous to camp here — %s only works beside a save crystal" % item.get("name", "this item")


## Field-menu gate: "" = allowed, else the refusal message. Fails open outside a running game (no GameLoop).
func field_use_blocked_reason(item_id: String) -> String:
	var item = get_item(item_id)
	if item.is_empty():
		return ""
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if game_loop == null or not game_loop.has_method("get_current_map_id"):
		return ""
	var in_dungeon: bool = MapSystem.is_dungeon_map(str(game_loop.get_current_map_id()))
	return save_point_gate_reason(item, in_dungeon, SavePoint.player_at_any(get_tree()))


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
	  - save_point_only: gated by the field-menu use sites via
	    field_use_blocked_reason (F3: free outside dungeons, crystal-gated inside).
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
			## Tick 171: emit battle_log_message so item use shows in
			## the visible log. Pre-fix only print() fired — debug
			## console only, invisible to the player.
			# Tick 297: route lime→bonus_bbcode for accessibility-mode swap.
			# Pre-fix hardcoded "lime" stayed lime in colorblind mode where
			# bonus_bbcode swaps to cyan — heal-positive lines stayed
			# inaccessible. Matches BattleManager's tick-237 pattern.
			var _bonus: String = AccessibilityPalette.bonus_bbcode()
			if _heal_consumed_by_revive:
				print("  → %s was revived with %d HP!" % [target.combatant_name, target.current_hp])
				if BattleManager:
					BattleManager.battle_log_message.emit("  → [color=%s]%s[/color] was revived with [color=%s]%d[/color] HP!" % [_bonus, target.combatant_name, _bonus, target.current_hp])
			else:
				print("  → %s was revived!" % target.combatant_name)
				if BattleManager:
					BattleManager.battle_log_message.emit("  → [color=%s]%s[/color] was revived!" % [_bonus, target.combatant_name])

	# HP healing (flat amount) — skip if revive already consumed it.
	if effects.has("heal_hp") and not _heal_consumed_by_revive:
		var heal_amount = effects["heal_hp"]
		var actual = target.heal(heal_amount)
		# Emit healing_done so BattleScene's heal popup + glow fire — without
		# this, items that heal would tick the HP bar silently.
		if actual > 0 and BattleManager:
			BattleManager.healing_done.emit(target, actual)
			BattleManager.battle_log_message.emit("  → [color=white]%s[/color] recovers [color=%s]%d[/color] HP!" % [target.combatant_name, AccessibilityPalette.bonus_bbcode(), actual])
		print("  → %s recovered %d HP" % [target.combatant_name, actual])

	# HP healing (percentage) — skip if revive already consumed it.
	if effects.has("heal_hp_percent") and not _heal_consumed_by_revive:
		var heal_percent = effects["heal_hp_percent"]
		var heal_amount = int(target.max_hp * heal_percent / 100.0)
		var actual_p = target.heal(heal_amount)
		if actual_p > 0 and BattleManager:
			BattleManager.healing_done.emit(target, actual_p)
			BattleManager.battle_log_message.emit("  → [color=white]%s[/color] recovers [color=%s]%d[/color] HP! (%d%%)" % [target.combatant_name, AccessibilityPalette.bonus_bbcode(), actual_p, heal_percent])
		print("  → %s recovered %d HP (%d%%)" % [target.combatant_name, actual_p, heal_percent])

	# MP restoration (flat amount). Surfaced through healing_done as the
	# visual proxy — same convention as the Free Move MP-restore actions
	# (Pray / Channel / Riff), per CLAUDE.md "healing_done (green popup)
	# not damage_dealt (would show as crit damage)".
	if effects.has("heal_mp"):
		var restore_amount = effects["heal_mp"]
		var actual_mp = target.restore_mp(restore_amount)
		if actual_mp > 0 and BattleManager:
			BattleManager.mp_restored.emit(target, actual_mp)
			BattleManager.battle_log_message.emit("  → [color=white]%s[/color] recovers [color=cyan]%d MP[/color]!" % [target.combatant_name, actual_mp])
		print("  → %s recovered %d MP" % [target.combatant_name, actual_mp])

	# MP restoration (percentage)
	if effects.has("heal_mp_percent"):
		var restore_percent = effects["heal_mp_percent"]
		var restore_amount = int(target.max_mp * restore_percent / 100.0)
		var actual_mp_p = target.restore_mp(restore_amount)
		if actual_mp_p > 0 and BattleManager:
			BattleManager.mp_restored.emit(target, actual_mp_p)
			BattleManager.battle_log_message.emit("  → [color=white]%s[/color] recovers [color=cyan]%d MP[/color]! (%d%%)" % [target.combatant_name, actual_mp_p, restore_percent])
		print("  → %s recovered %d MP (%d%%)" % [target.combatant_name, actual_mp_p, restore_percent])

	# Cure specific status effects
	if effects.has("cure_status"):
		for status in effects["cure_status"]:
			target.remove_status(status)
			## Tick 171: surface cure in the log. Pre-fix antidote
			## curing poison was completely invisible — no popup, no
			## log line, only the status icon disappearing (easy to
			## miss when multiple effects are active).
			if BattleManager:
				BattleManager.battle_log_message.emit("  → [color=white]%s[/color] is cured of [color=cyan]%s[/color]!" % [target.combatant_name, status])
			print("  → %s cured of %s" % [target.combatant_name, status])

	# Cure every ailment. Permadeath is not one — the battle-start helper keeps that marker, so a Remedy cannot unwrite it and let a later Raise land.
	if effects.has("cure_all_status") and effects["cure_all_status"]:
		target.clear_transient_statuses()
		if BattleManager:
			BattleManager.battle_log_message.emit("  → [color=white]%s[/color] is cured of [color=cyan]all status effects[/color]!" % target.combatant_name)
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
		if BattleManager:
			BattleManager.battle_log_message.emit("  → [color=white]%s[/color] gains [color=cyan]%s[/color]! (%s +%d%% for %d turns)" % [target.combatant_name, _effect_name, _stat.to_upper(), int((_power - 1.0) * 100), _duration])
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
			BattleManager.battle_log_message.emit("  → [color=%s]%s[/color] takes [color=yellow]%d[/color] %s damage!" % [AccessibilityPalette.penalty_bbcode(), target.combatant_name, actual_damage, element])
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
##   save_point_only -> field-menu sites gate via field_use_blocked_reason (F3)
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


## The party shares one bag in battle. Every grant lands on the leader, so reading each member's own
## inventory left four of five PCs with no Item command and made every preset's potion rule dead.
func party_item_count(party: Array, item_id: String) -> int:
	var total := 0
	for m in party:
		if m != null and is_instance_valid(m) and m.has_method("get_item_count"):
			total += int(m.get_item_count(item_id))
	return total


## item_id -> total quantity across the party, for a menu that lists the shared bag.
func party_inventory(party: Array) -> Dictionary:
	var out := {}
	for m in party:
		if m == null or not is_instance_valid(m) or not ("inventory" in m) or not (m.inventory is Dictionary):
			continue
		for id in m.inventory:
			var q := int(m.inventory[id])
			if q > 0:
				out[id] = int(out.get(id, 0)) + q
	return out


## Spend one from the user's own stock first, then from the first other member holding it.
func take_party_item(user, party: Array, item_id: String) -> bool:
	if user != null and is_instance_valid(user) and user.has_method("get_item_count") and int(user.get_item_count(item_id)) > 0:
		return user.remove_item(item_id, 1)
	for m in party:
		if m != null and is_instance_valid(m) and m != user and m.has_method("get_item_count") and int(m.get_item_count(item_id)) > 0:
			return m.remove_item(item_id, 1)
	return false


## Whether an item can be used INSIDE a battle. THE OWNER of a rule that had two copies:
## BattleCommandMenu filtered META for the player's Use Item list, and the LLM Rule
## Composer re-derived the same filter for the model — spelling ItemCategory.META as a
## literal 4 while the enum was reachable.
##
## META is boss trophies, key items and lore drops. They stack for the bestiary and the
## endgame economy and do nothing if used, so they are clutter in the player's list and a
## rule that never works in a composed one.
func is_usable_in_battle(item_id: String) -> bool:
	var item: Dictionary = get_item(item_id)
	if item.is_empty():
		return false
	return int(item.get("category", -1)) != ItemCategory.META


## "" when this use would change something. Otherwise the sentence a menu should show — and the caller must not spend the item. use_item itself still returns true for a 0 HP heal; the waste happens at the menu, which used to treat that true as success.
func ineffective_use_reason(item_id: String, targets: Array, in_battle: bool = false) -> String:
	var item := get_item(item_id)
	if item.is_empty():
		return ""
	var effects = item.get("effects", {})
	if typeof(effects) != TYPE_DICTIONARY:
		return ""
	var name := str(item.get("name", "That item"))
	for key in effects.keys():
		if not is_effect_key_handled(str(key)):
			return ""
	if effects.has("add_buff") or effects.has("damage") or effects.has("repel_steps"):
		return ""
	var heals_hp := _effect_amount(effects, "heal_hp") > 0 or _effect_amount(effects, "heal_hp_percent") > 0
	var heals_mp := _effect_amount(effects, "heal_mp") > 0 or _effect_amount(effects, "heal_mp_percent") > 0
	var cures_all := bool(effects.get("cure_all_status", false))
	var cure_list: Array = effects.get("cure_status", []) if effects.get("cure_status", []) is Array else []
	var cures_listed := not cure_list.is_empty()
	var revives := bool(effects.get("revive", false))
	if not heals_hp and not heals_mp and not cures_all and not cures_listed and not revives:
		if bool(effects.get("escape_battle", false)):
			if in_battle:
				return ""
			return "%s only works in battle" % name
		return "%s can't be used" % name
	if revives:
		# Permakilled revive() does nothing, so that corpse is not a reason to spend the item; a normal KO still is. Outside battle a bundled heal on a living ally in the same list falls through.
		if _someone_can_be_revived(targets):
			return ""
		var blocked := _permakill_block_reason(targets)
		if blocked != "":
			if in_battle or not _living_heal_would_land(targets, heals_hp, heals_mp):
				return blocked
		elif in_battle:
			var standing := _living_revive_reason(targets)
			if standing != "":
				return standing
	var seen := 0
	var living := 0
	var who := ""
	var missing_hp := false
	var missing_mp := false
	var has_ailment := false
	for t in targets:
		if not _is_item_target(t):
			continue
		seen += 1
		who = str(t.combatant_name)
		if t.is_alive:
			living += 1
			if t.current_hp < t.max_hp:
				missing_hp = true
			if t.current_mp < t.max_mp:
				missing_mp = true
		# The permadeath marker is not an ailment this tonic can lift. Counting it would spend a Remedy on a no-op, or — before the clear spared it — on a revive loophole.
		if cures_all:
			for status_id in t.status_effects:
				if str(status_id) != "permakilled":
					has_ailment = true
					break
		elif cures_listed:
			for status_id in cure_list:
				if t.has_status(str(status_id)):
					has_ailment = true
					break
	if seen == 0:
		return ""
	if (heals_hp and missing_hp) or (heals_mp and missing_mp) or ((cures_listed or cures_all) and has_ailment):
		return ""
	var many := seen > 1
	if who == "":
		who = "They"
	if not revives and living == 0 and (heals_hp or heals_mp) and not cures_listed and not cures_all:
		if many:
			return "No one left to heal"
		return "%s is knocked out" % who
	if (cures_listed or cures_all) and not heals_hp and not heals_mp:
		if cures_listed and cure_list.size() == 1 and not cures_all:
			var word := _ailment_word(str(cure_list[0]))
			if many:
				return "No one is %s" % word
			return "%s isn't %s" % [who, word]
		if many:
			return "No one has a status to cure"
		return "%s has no status to cure" % who
	if heals_hp and heals_mp:
		if many:
			return "The party is already at full HP and MP"
		return "%s is already at full HP and MP" % who
	if heals_hp:
		if many:
			return "The party is already at full HP"
		return "%s is already at full HP" % who
	if heals_mp:
		if many:
			return "The party is already at full MP"
		return "%s is already at full MP" % who
	if revives:
		var standing := _living_revive_reason(targets)
		if standing != "":
			return standing
		return "Cannot revive — no KO'd target"
	if many:
		return "It wouldn't help anyone"
	return "It wouldn't help %s" % who


## "" when someone in targets is KO'd (the revive can help) or no target could be read. Otherwise who isn't knocked out.
func _living_revive_reason(targets: Array) -> String:
	var n := 0
	var who := ""
	for t in targets:
		if not _is_item_target(t):
			continue
		if not t.is_alive:
			return ""
		n += 1
		who = str(t.combatant_name)
	if n == 0:
		return ""
	if n > 1:
		return "No one is knocked out"
	if who == "":
		who = "They"
	return "%s isn't knocked out" % who


## True when a KO'd target would actually stand back up. Permakilled revive() returns without changing HP.
func _someone_can_be_revived(targets: Array) -> bool:
	for t in targets:
		if _is_item_target(t) and not t.is_alive and not t.has_status("permakilled"):
			return true
	return false


## "" when no target is a permakilled corpse. Otherwise the sentence for a revive that revive() will refuse.
func _permakill_block_reason(targets: Array) -> String:
	var n := 0
	var who := ""
	for t in targets:
		if not _is_item_target(t) or t.is_alive or not t.has_status("permakilled"):
			continue
		n += 1
		who = str(t.combatant_name)
	if n == 0:
		return ""
	if n > 1:
		return "No one can be revived"
	if who == "":
		who = "They"
	return "%s can't be revived" % who


## True when a living ally in this list would gain HP or MP from the bundled heal. use_item still applies that outside battle.
func _living_heal_would_land(targets: Array, heals_hp: bool, heals_mp: bool) -> bool:
	if not heals_hp and not heals_mp:
		return false
	for t in targets:
		if not _is_item_target(t) or not t.is_alive:
			continue
		if heals_hp and t.current_hp < t.max_hp:
			return true
		if heals_mp and t.current_mp < t.max_mp:
			return true
	return false


func _effect_amount(effects: Dictionary, key: String) -> int:
	var v = effects.get(key, 0)
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return 0
	return int(v)


func _is_item_target(t) -> bool:
	return t != null and is_instance_valid(t) and ("is_alive" in t) and ("current_hp" in t) and t.has_method("has_status")


func _ailment_word(status_id: String) -> String:
	var known := {
		"poison": "poisoned",
		"silence": "silenced",
		"blind": "blinded",
		"petrify": "petrified",
		"stun": "stunned",
		"sleep": "asleep",
		"confuse": "confused",
		"paralysis": "paralyzed",
		"curse": "cursed",
		"burn": "burning",
		"freeze": "frozen",
	}
	var id := status_id.to_lower()
	return str(known[id]) if known.has(id) else id.replace("_", " ")

