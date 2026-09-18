extends GutTest

## Tick 353 gave `dispel` an arm in _execute_support_ability and its comment names 7 abilities
## "all of which silently fizzled pre-fix". SIX are typed `support` and reach it. The seventh,
## `void_breath` — Umbraxis, 28 MP, all_enemies, 3.5x damage AND a party-wide dispel — is typed
## `magic`, so it routes to _apply_ability_status and landed an inert "dispel" key instead.
## `null_touch`'s `erase` (null_entity, pooled in abstract_overworld) is the same.
##
## ⚠️ ARM REACHABILITY IS NOT ABILITY REACHABILITY. A scan asking "can anything reach this arm"
## answers YES here — six abilities do — and is blind to the two that cannot. The question is per
## ABILITY, not per arm.
##
## ⚠️ NOT fixed, measured: the GRIND models dispel not at all (0 references in the resolver), so
## this restores both abilities in LIVE battle only.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")


func before_each() -> void:
	for n in ["AutogrindSystem", "AutobattleSystem"]:
		var sys: Node = get_node_or_null("/root/" + n)
		if sys != null and "_test_disable_persistence" in sys:
			sys._test_disable_persistence = true


func _combatant(nm: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": 100, "max_mp": 99,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func _buffed(nm: String) -> Combatant:
	var c := _combatant(nm)
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


func test_void_breath_actually_dispels() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	var ab: Dictionary = _certain("void_breath")
	if bm == null or not bm.has_method("_apply_ability_status") or ab.is_empty():
		pass_test("autoloads unavailable")
		return
	assert_eq(str(ab.get("type", "")), "magic",
		"CONTROL: void_breath is type magic — that is why it never reached the support arm")
	var target := _buffed("Party Member")
	assert_gt(target.active_buffs.size(), 0, "CONTROL: the target must start buffed")
	bm._apply_ability_status(_combatant("Umbraxis"), target, ab)
	assert_eq(target.active_buffs.size(), 0, "Umbraxis's party-wide dispel must strip buffs")
	assert_false(target.has_status("regen"), "and positive statuses")


func test_null_touch_erase_dispels_too() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	var ab: Dictionary = _certain("null_touch")
	if bm == null or not bm.has_method("_apply_ability_status") or ab.is_empty():
		pass_test("autoloads unavailable")
		return
	var target := _buffed("Party Member")
	bm._apply_ability_status(_combatant("Null Entity"), target, ab)
	assert_eq(target.active_buffs.size(), 0, "erase aliases dispel and must strip buffs")


func test_neither_leaves_an_inert_key_behind() -> void:
	## What they did before: add_status("dispel") / add_status("erase"), which nothing reads.
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null or not bm.has_method("_apply_ability_status"):
		pass_test("BattleManager autoload unavailable")
		return
	for pair in [["void_breath", "dispel"], ["null_touch", "erase"]]:
		var ab: Dictionary = _certain(pair[0])
		if ab.is_empty():
			pass_test("JobSystem autoload unavailable")
			return
		var target := _buffed("Victim " + pair[0])
		bm._apply_ability_status(_combatant("Caster"), target, ab)
		assert_false(target.has_status(pair[1]),
			"%s must not leave an inert '%s' status — nothing reads it" % [pair[0], pair[1]])


func test_a_dispel_leaves_the_debuffs_alone() -> void:
	## Dispel strips ENHANCEMENTS. Stripping the poison too would be a gift to the boss casting it.
	var bm: Node = get_node_or_null("/root/BattleManager")
	var ab: Dictionary = _certain("void_breath")
	if bm == null or ab.is_empty():
		pass_test("autoloads unavailable")
		return
	var target := _buffed("Party Member")
	assert_true(target.has_status("poison"), "CONTROL: the target starts poisoned")
	bm._apply_ability_status(_combatant("Umbraxis"), target, ab)
	assert_true(target.has_status("poison"), "a dispel must not clear the target's debuffs")


func test_both_routes_run_the_same_code() -> void:
	## One owner. The support executor calls the helper rather than holding a second copy — two
	## definitions of "what dispel means" is how the routes drift back apart.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_eq(src.count("func _dispel_target("), 1, "the dispel body must have exactly one definition")
	assert_gt(src.count("_dispel_target_and_log("), 2,
		"both routes plus the definition must reference it — a copy in either is the drift this fixes")
	assert_eq(src.count("active_buffs.clear()\n\t\tfor s in _POSITIVE_STATUSES_DISPELLABLE"), 0,
		"CONTROL: the arm must no longer carry its own inline copy")


func test_the_grind_still_does_not_model_dispel() -> void:
	## Declared, not defended — reds the day somebody models it, which is when this file needs
	## re-scoping rather than deleting.
	var src: String = FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_false(src.contains("_dispel"),
		"the grind now models dispel — re-scope this file, both engines may need parity arms")
