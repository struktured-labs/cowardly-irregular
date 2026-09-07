extends GutTest

## tick 114 regression: GameState.game_constants["damage_multiplier"]
## and "healing_multiplier" must be consumed by Combatant.take_damage
## and Combatant.heal respectively. Pre-fix, both keys were in the
## defaults dict + persisted via save/load, but NO code path read
## them. Scriptweaver writes to either knob were cosmetic.
##
## This closes the dead-constant cleanup arc that started with the
## tick 109/110 daemon-knob wiring. game_constants' five
## post-tick-114 LIVE multipliers (exp, gold, encounter_rate,
## damage, healing) now all affect gameplay.

const COMBATANT := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _take_damage_body() -> String:
	var src := _read(COMBATANT)
	var idx: int = src.find("func take_damage")
	assert_gt(idx, -1, "take_damage must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func _heal_body() -> String:
	var src := _read(COMBATANT)
	var idx: int = src.find("func heal(amount: int)")
	assert_gt(idx, -1, "heal must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_take_damage_reads_damage_multiplier_defensively() -> void:
	var body := _take_damage_body()
	assert_true(body.contains("game_constants.get(\"damage_multiplier\", 1.0)"),
		"take_damage must read game_constants['damage_multiplier'] with .get(default=1.0)")
	assert_true(body.contains("actual_damage = int(actual_damage * dmg_mult)"),
		"take_damage must apply dmg_mult to actual_damage")


func test_take_damage_clamps_damage_multiplier() -> void:
	var body := _take_damage_body()
	assert_true(body.contains("clampf("),
		"take_damage must clampf the multiplier")
	# Same band as the rest of the multiplier triplet.
	# Pin the band exactly so a refactor that loosens it doesn't slip past.
	assert_true(body.contains("0.1, 10.0"),
		"take_damage damage_multiplier clamp must be [0.1, 10.0] — uniform with tick 109/110/113")


func test_heal_reads_healing_multiplier_defensively() -> void:
	var body := _heal_body()
	assert_true(body.contains("game_constants.get(\"healing_multiplier\", 1.0)"),
		"heal must read game_constants['healing_multiplier'] with .get(default=1.0)")
	assert_true(body.contains("heal_amount = int(heal_amount * heal_mult)"),
		"heal must apply heal_mult to heal_amount")


func test_heal_clamps_healing_multiplier() -> void:
	var body := _heal_body()
	assert_true(body.contains("clampf("),
		"heal must clampf the multiplier")
	assert_true(body.contains("0.1, 10.0"),
		"heal healing_multiplier clamp must be [0.1, 10.0] — uniform band")


func test_both_use_runtime_gamestate_lookup() -> void:
	# Runtime lookup keeps these methods preload-safe for unit tests
	# that don't have the GameState autoload registered. Pin the
	# get_node_or_null pattern in both bodies.
	var td_body := _take_damage_body()
	var heal_body := _heal_body()
	for body in [td_body, heal_body]:
		assert_true(body.contains("get_tree().root.get_node_or_null(\"GameState\")"),
			"both methods must use runtime GameState lookup — unit-test safety")


func test_default_multipliers_preserve_vanilla_behavior() -> void:
	# Sanity: the defaults in GameState.game_constants are 1.0 for
	# both. With clampf [0.1, 10.0] guarding, vanilla play is
	# unchanged.
	var src := _read("res://src/meta/GameState.gd")
	assert_true(src.contains("\"damage_multiplier\": 1.0"),
		"damage_multiplier default must remain 1.0")
	assert_true(src.contains("\"healing_multiplier\": 1.0"),
		"healing_multiplier default must remain 1.0")


func test_damage_multiplier_applied_after_status_modifiers() -> void:
	# Ordering: the global multiplier must compose AFTER defending
	# and exposed status modifiers, so the user-facing "Defend"
	# action still does its intended 50% reduction before the
	# global scaling.
	var body := _take_damage_body()
	var defending_idx: int = body.find("if is_defending:")
	var exposed_idx: int = body.find("if has_status(\"exposed\"):")
	var mult_idx: int = body.find("actual_damage = int(actual_damage * dmg_mult)")
	assert_gt(defending_idx, -1, "is_defending check must exist")
	assert_gt(exposed_idx, -1, "exposed check must exist")
	assert_gt(mult_idx, -1, "damage_multiplier application must exist")
	assert_lt(defending_idx, mult_idx,
		"damage_multiplier must apply AFTER is_defending — defend halves base, multiplier scales the halved result")
	assert_lt(exposed_idx, mult_idx,
		"damage_multiplier must apply AFTER exposed — status modifiers stack natively, then the global scales the composed result")
