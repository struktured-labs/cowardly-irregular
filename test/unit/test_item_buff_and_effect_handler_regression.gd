extends GutTest

## Regression: two ItemSystem silent-failure bugs.
##
## BUG A — Buff consumables were completely inert.
##   power_drink/speed_tonic/defense_tonic/magic_tonic carry
##   effects = {add_buff: {type: attack_up/speed_up/defense_up/magic_up,
##   power: 1.5, duration: 3}}. Pre-fix _apply_item_effects handled add_buff
##   by calling target.add_status(buff["type"]) — that only appended an inert
##   status STRING (e.g. "attack_up") and recorded a duration. get_buffed_stat
##   reads ONLY active_buffs/active_debuffs, so the buff had ZERO effect on the
##   stat. Every buff consumable was consumed (200 gold) for no benefit.
##   Post-fix: add_buff(effect_name, stat, power, duration) creates a real
##   active_buffs entry, so get_buffed_stat reflects the boost.
##
## BUG B — Orphan effect keys silently consumed.
##   escape_battle (smoke_bomb), repel_steps (repel), save_point_only (tent),
##   all_party (megalixir) had no handler. use_item returned true regardless,
##   so callers consumed the item with no/wrong effect. Post-fix:
##     - repel_steps is applied via EncounterSystem.use_repel in use_item.
##     - escape_battle / save_point_only / all_party are explicitly recognized
##       (is_effect_key_handled) and routed to a documented caller, so a new
##       unhandled key in items.json is caught here, not silently consumed.
##
## Exercises ItemSystem.gd directly with a fresh Combatant — no battle scene.


const CombatantScript = preload("res://src/battle/Combatant.gd")
const ItemSystemScript = preload("res://src/items/ItemSystem.gd")


func _make_combatant() -> Combatant:
	var c = CombatantScript.new()
	c.combatant_name = "BuffTester"
	c.max_hp = 100
	c.current_hp = 100
	c.max_mp = 30
	c.current_mp = 30
	c.attack = 20
	c.defense = 20
	c.magic = 20
	c.speed = 20
	add_child_autofree(c)
	return c


func _make_item_system() -> Node:
	# Don't add as child — _ready loads JSON which would couple to autoload
	# state. Use the methods directly.
	return ItemSystemScript.new()


# --- BUG A: buff consumables apply a real stat buff -------------------------

func test_power_drink_creates_real_attack_buff() -> void:
	var target = _make_combatant()
	var sys = _make_item_system()
	var power_drink = {
		"id": "power_drink",
		"name": "Power Drink",
		"effects": {"add_buff": {"type": "attack_up", "power": 1.5, "duration": 3}},
	}
	sys._apply_item_effects(target, target, power_drink)

	# Real active_buffs entry, not an inert status string.
	assert_eq(target.active_buffs.size(), 1,
		"Power Drink should create exactly one active_buffs entry")
	var buff = target.active_buffs[0]
	assert_eq(buff["stat"], "attack", "Buff must target the 'attack' stat")
	assert_eq(buff["modifier"], 1.5, "Buff must use JSON 'power' (1.5) as the modifier")
	assert_eq(buff["duration"], 3, "Buff must use JSON 'duration' (3)")

	# The stat read path must actually reflect the boost.
	var buffed = target.get_buffed_stat("attack", target.attack)
	assert_eq(buffed, 30,
		"attack 20 * 1.5 should read as 30 (got %d)" % buffed)
	assert_gt(buffed, target.attack,
		"Buffed attack must exceed base attack (pre-fix it did not)")

	# The inert status string must NOT be present (the old broken behavior).
	assert_false(target.has_status("attack_up"),
		"add_buff must NOT push the type as a status string")


func test_all_four_tonics_map_to_correct_stats() -> void:
	var cases = {
		"attack_up": "attack",
		"speed_up": "speed",
		"defense_up": "defense",
		"magic_up": "magic",
	}
	for buff_type in cases:
		var stat: String = cases[buff_type]
		var target = _make_combatant()
		var sys = _make_item_system()
		var item = {
			"id": "tonic",
			"name": "Tonic",
			"effects": {"add_buff": {"type": buff_type, "power": 1.5, "duration": 3}},
		}
		sys._apply_item_effects(target, target, item)

		assert_eq(target.active_buffs.size(), 1,
			"%s should create one buff" % buff_type)
		assert_eq(target.active_buffs[0]["stat"], stat,
			"%s must buff the '%s' stat" % [buff_type, stat])

		var base: int = int(target.get(stat))
		var buffed = target.get_buffed_stat(stat, base)
		assert_gt(buffed, base,
			"%s must actually raise the '%s' stat (base %d -> %d)" % [buff_type, stat, base, buffed])


func test_distinct_buff_effect_names_do_not_collide() -> void:
	# add_buff refreshes by effect name. Attack and defense buffs must use
	# distinct effect names so stacking two different tonics doesn't clobber.
	var target = _make_combatant()
	var sys = _make_item_system()
	sys._apply_item_effects(target, target, {
		"effects": {"add_buff": {"type": "attack_up", "power": 1.5, "duration": 3}},
	})
	sys._apply_item_effects(target, target, {
		"effects": {"add_buff": {"type": "defense_up", "power": 1.5, "duration": 3}},
	})

	assert_eq(target.active_buffs.size(), 2,
		"Attack and defense buffs must coexist (distinct effect names)")
	assert_gt(target.get_buffed_stat("attack", target.attack), target.attack,
		"Attack buff must remain after adding a defense buff")
	assert_gt(target.get_buffed_stat("defense", target.defense), target.defense,
		"Defense buff must remain after adding an attack buff")


# --- BUG B: orphan effect keys are handled / recognized ---------------------

func test_all_items_json_effect_keys_have_a_handler() -> void:
	# Mirrors the monster-drop audit pattern: every distinct effect key present
	# in data/items.json must be handled by ItemSystem or routed to a documented
	# caller. Catches the silent-consume class (new key with no handler).
	var sys = _make_item_system()
	var file = FileAccess.open("res://data/items.json", FileAccess.READ)
	assert_not_null(file, "items.json must be readable")
	if file == null:
		return
	var json = JSON.new()
	var parse_ok = json.parse(file.get_as_text())
	file.close()
	assert_eq(parse_ok, OK, "items.json must parse")
	if parse_ok != OK:
		return

	var data: Dictionary = json.data
	var unhandled: Array[String] = []
	for item_id in data:
		var effects = data[item_id].get("effects", {})
		if typeof(effects) != TYPE_DICTIONARY:
			continue
		for key in effects:
			if not sys.is_effect_key_handled(key):
				unhandled.append("%s.%s" % [item_id, key])

	assert_eq(unhandled.size(), 0,
		"Every items.json effect key must be handled; unhandled: %s" % str(unhandled))


func test_repel_steps_routes_to_encounter_system() -> void:
	# repel_steps must reach EncounterSystem.use_repel via the /root/ lookup in
	# _apply_global_item_effects. EncounterSystem is a real Godot autoload
	# (project.godot), so it CANNOT be shadowed by add_child-ing a same-named
	# stub at /root/ — the stub never becomes /root/EncounterSystem. Drive the
	# real autoload directly and assert it recorded the repel steps.
	assert_not_null(EncounterSystem,
		"EncounterSystem autoload must be available in the test environment")

	var prior_steps: int = EncounterSystem.repel_steps_remaining
	var sys = _make_item_system()
	# _apply_global_item_effects resolves EncounterSystem via the absolute
	# "/root/EncounterSystem" path, which only works when sys is inside the
	# scene tree (a detached ItemSystemScript.new() can't get_node /root/...).
	add_child_autofree(sys)

	sys._apply_global_item_effects({"effects": {"repel_steps": 50}})

	assert_eq(EncounterSystem.repel_steps_remaining, 50,
		"repel_steps must call EncounterSystem.use_repel(50), setting repel_steps_remaining to 50")

	# Restore so other tests / autoload state are unaffected.
	EncounterSystem.repel_steps_remaining = prior_steps


func test_known_caller_handled_keys_are_recognized() -> void:
	# These are deliberately not resolved inside ItemSystem but must be
	# recognized so they are never treated as silently-consumed unknowns.
	var sys = _make_item_system()
	for key in ["escape_battle", "save_point_only", "all_party"]:
		assert_true(sys.is_effect_key_handled(key),
			"'%s' must be recognized (routed to a caller), not unhandled" % key)
