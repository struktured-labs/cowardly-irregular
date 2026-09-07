extends GutTest

## tick 384: erase effect (null_touch ability) aliases dispel.
##
## Pre-fix null_touch (effect=erase, damage_multiplier=1.4) landed its
## upfront damage but the advertised "erases the target's existence
## temporarily" semantic silently fizzled — fell through to `_:`
## push_warning default. Description matches dispel's strip-all-
## enhancements behavior exactly, so we alias them in the same arm.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


func test_erase_arm_shared_with_dispel() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin the combined case label.
	assert_true(src.contains("\"erase\", \"dispel\":"),
		"erase must alias dispel in the same case label")


func test_null_touch_authors_erase() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	assert_true(data.has("null_touch"))
	assert_eq(str(data["null_touch"].get("effect", "")), "erase")


func test_erase_clears_buffs_and_positive_statuses() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("null_touch"):
		pending("null_touch ability required")
		return
	var target: Combatant = _make("Buffed")
	# Seed buffs + positive statuses on the target.
	target.add_buff("Power Up", "attack", 1.5, 3)
	target.add_status("barrier", 2)
	target.add_status("regen", 3)
	# Pre-condition.
	assert_eq(target.active_buffs.size(), 1)
	assert_true("barrier" in target.status_effects)
	assert_true("regen" in target.status_effects)

	var ability: Dictionary = js.abilities["null_touch"].duplicate(true)
	ability["success_rate"] = 1.0
	var typed_targets: Array[Combatant] = [target]
	bm._execute_support_ability(null, ability, typed_targets)

	# Post-condition: buffs gone, positive statuses gone.
	assert_eq(target.active_buffs.size(), 0,
		"erase must clear all active_buffs — pre-fix the cast silently fizzled")
	assert_false("barrier" in target.status_effects,
		"erase must remove 'barrier' positive status")
	assert_false("regen" in target.status_effects,
		"erase must remove 'regen' positive status")


func test_erase_does_not_clear_debuffs() -> void:
	# Regression guard: erase removes ENHANCEMENTS, not debuffs.
	# A confused/poisoned target struck by erase should still be
	# confused/poisoned.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("null_touch"):
		pending("null_touch ability required")
		return
	var target: Combatant = _make("Cursed")
	target.add_status("poison", 3)
	target.add_status("confuse", 2)

	var ability: Dictionary = js.abilities["null_touch"].duplicate(true)
	ability["success_rate"] = 1.0
	var typed_targets: Array[Combatant] = [target]
	bm._execute_support_ability(null, ability, typed_targets)

	assert_true("poison" in target.status_effects,
		"erase must NOT clear negative statuses like poison")
	assert_true("confuse" in target.status_effects,
		"erase must NOT clear negative statuses like confuse")
