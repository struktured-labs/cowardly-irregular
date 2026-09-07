extends GutTest

## tick 386: damage_absorb (fill_the_void ability) converts incoming
## damage to healing 1:1 while active.
##
## Pre-fix the effect fell through to `_:` push_warning default —
## fill_the_void burned 12 MP for nothing. Now applies a
## "damage_absorb" status; Combatant.take_damage intercepts incoming
## damage and converts it 1:1 to healing while the status holds.
## Duration controls wear-off.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 20, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


func test_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"damage_absorb\":")
	assert_gt(arm_idx, -1, "BattleManager dispatch must have a damage_absorb arm")
	var window: String = src.substr(arm_idx, 600)
	assert_true(window.contains("add_status(\"damage_absorb\""),
		"damage_absorb arm must apply the damage_absorb status")


func test_take_damage_intercepts_when_absorbing() -> void:
	var src := _read(COMBATANT_PATH)
	# The take_damage interceptor must check the status.
	assert_true(src.contains("has_status(\"damage_absorb\")"),
		"Combatant.take_damage must check damage_absorb status")
	# Must convert to healing via current_hp += absorbed.
	assert_true(src.contains("current_hp + absorbed"),
		"Combatant.take_damage must heal by the absorbed amount when active")


func test_data_still_authors_effect() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	assert_true(data.has("fill_the_void"))
	assert_eq(str(data["fill_the_void"].get("effect", "")), "damage_absorb")


func test_dispatch_applies_status() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("fill_the_void"):
		pending("fill_the_void ability required")
		return
	var c: Combatant = _make("Tank")
	var ability: Dictionary = js.abilities["fill_the_void"].duplicate(true)
	var typed_targets: Array[Combatant] = [c]
	bm._execute_support_ability(null, ability, typed_targets)
	assert_true("damage_absorb" in c.status_effects,
		"damage_absorb status must be present on target after fill_the_void")


func test_damage_to_absorbing_target_heals() -> void:
	# End-to-end behavioral: damage to a target with damage_absorb
	# heals instead of damaging.
	var target: Combatant = _make("Tank")
	target.current_hp = 50  # half health
	target.add_status("damage_absorb", 2)
	var ret: int = target.take_damage(30, false)
	# Return must be 0 (no damage taken) AND HP must have RISEN.
	assert_eq(ret, 0,
		"take_damage on a damage_absorb target must return 0 — no damage taken")
	assert_gt(target.current_hp, 50,
		"take_damage on a damage_absorb target must INCREASE HP (heal)")


func test_damage_without_absorb_still_normal() -> void:
	# Regression guard: without the status, damage flow is unchanged.
	var target: Combatant = _make("Vanilla")
	target.current_hp = 80
	target.status_effects.clear()
	var ret: int = target.take_damage(30, false)
	assert_gt(ret, 0,
		"take_damage without damage_absorb must return positive damage")
	assert_lt(target.current_hp, 80,
		"take_damage without damage_absorb must DECREASE HP")
