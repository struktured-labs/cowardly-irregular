extends GutTest

## The grind modelled dispel NOT AT ALL — zero references in the resolver — so after live was fixed
## `void_breath` (Umbraxis, 28 MP, all enemies) and `null_touch` (null_entity, POOLED in
## abstract_overworld) still stripped nothing in a grind. Declared as a gap when the live half
## shipped; this closes it.
##
## The body now lives on Combatant, which OWNS active_buffs and the statuses, and both engines call
## it. A twin in the resolver is what this file exists to prevent: the two engines drifted on
## `amplify_poison`, `memory_leak_status` and `ability_silence` for exactly that reason.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"
const HBR_PATH := "res://src/autogrind/HeadlessBattleResolver.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()
	for n in ["AutogrindSystem", "AutobattleSystem"]:
		var sys: Node = get_node_or_null("/root/" + n)
		if sys != null and "_test_disable_persistence" in sys:
			sys._test_disable_persistence = true


func _buffed(nm: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": 200, "max_mp": 99,
		"attack": 20, "defense": 10, "magic": 20, "speed": 10})
	add_child_autofree(c)
	c.add_buff("Protect", "defense", 1.5, 3)
	c.add_status("regen", 3)
	c.add_status("poison", 3)
	return c


func _certain(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	var ab: Dictionary = js.get_ability(ability_id).duplicate(true)
	if ab.is_empty():
		return {}
	ab["effect_chance"] = 1.0
	return ab


func test_the_grind_strips_buffs_for_void_breath() -> void:
	var ab: Dictionary = _certain("void_breath")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var target := _buffed("Party Member")
	assert_gt(target.active_buffs.size(), 0, "CONTROL: the target must start buffed")
	_res._maybe_inflict_status(_buffed("Umbraxis"), target, ab, "void_breath")
	assert_eq(target.active_buffs.size(), 0, "a grind must strip buffs for a dispel, as live does")
	assert_false(target.has_status("regen"), "and positive statuses")


func test_the_grind_strips_for_null_touch_too() -> void:
	## erase rides on the same arm, and null_entity is POOLED — a grind meets this one.
	var ab: Dictionary = _certain("null_touch")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var target := _buffed("Party Member")
	_res._maybe_inflict_status(_buffed("Null Entity"), target, ab, "null_touch")
	assert_eq(target.active_buffs.size(), 0, "erase must strip in a grind too")


func test_the_grind_leaves_debuffs_alone() -> void:
	## Dispel strips ENHANCEMENTS. Clearing the poison would be a gift to the caster.
	var ab: Dictionary = _certain("void_breath")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var target := _buffed("Party Member")
	assert_true(target.has_status("poison"), "CONTROL: the target starts poisoned")
	_res._maybe_inflict_status(_buffed("Umbraxis"), target, ab, "void_breath")
	assert_true(target.has_status("poison"), "a dispel must not clear the target's debuffs")


func test_no_inert_key_is_left_behind() -> void:
	for pair in [["void_breath", "dispel"], ["null_touch", "erase"]]:
		var ab: Dictionary = _certain(pair[0])
		if ab.is_empty():
			pass_test("JobSystem autoload unavailable")
			return
		var target := _buffed("Victim " + pair[0])
		_res._maybe_inflict_status(_buffed("Caster"), target, ab, pair[0])
		assert_false(target.has_status(pair[1]),
			"%s must not leave an inert '%s' status — nothing reads it" % [pair[0], pair[1]])


func test_both_engines_agree_on_what_a_dispel_clears() -> void:
	## The same numbers from the same code, driven through each engine's own applier.
	var bm: Node = get_node_or_null("/root/BattleManager")
	var ab: Dictionary = _certain("void_breath")
	if bm == null or not bm.has_method("_apply_ability_status") or ab.is_empty():
		pass_test("autoloads unavailable")
		return
	var live_target := _buffed("Live")
	var grind_target := _buffed("Grind")
	bm._apply_ability_status(_buffed("Umbraxis"), live_target, ab)
	_res._maybe_inflict_status(_buffed("Umbraxis"), grind_target, ab, "void_breath")
	assert_eq(grind_target.active_buffs.size(), live_target.active_buffs.size(),
		"both engines must clear the same buffs")
	assert_eq(grind_target.has_status("regen"), live_target.has_status("regen"),
		"and the same positive statuses")
	assert_eq(grind_target.has_status("poison"), live_target.has_status("poison"),
		"and spare the same debuffs")


func test_neither_engine_keeps_a_twin_of_the_body() -> void:
	## The drift this file exists to prevent. Three effects diverged between these two engines today
	## because each held its own copy of a decision; the body lives on Combatant and both call it.
	var combatant: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	assert_eq(combatant.count("func dispel("), 1, "exactly one definition, on the class that owns the state")
	assert_gt(combatant.count("DISPELLABLE_POSITIVE_STATUSES"), 1, "and it reads its own list")
	## ⚠️ NOT keyed on `active_buffs.clear()` — I tried that and it is a FALSE POSITIVE: the clear has
	## five legitimate uses across the two engines (battle start, a boss face swap, a masterite
	## decision, the resolver's own setup, and dispel_and_self_buff, which strips an ALLY as a
	## sacrifice and is a different effect). The property is one DEFINITION and two CALLERS.
	for path in [BM_PATH, HBR_PATH]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_eq(src.count("func dispel("), 0, "%s must not define its own dispel" % path)
		assert_gt(src.count(".dispel()"), 0, "%s must call the shared one" % path)
