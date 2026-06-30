extends GutTest

## tick 445: bp_recovery passive's meta_effects.bp_regen_bonus now
## actually grants extra AP when deferring.
##
## Pre-fix passives.json authored:
##   bp_recovery: {meta_effects: {bp_regen_bonus: 1}}
##   description: "Recover 1 extra BP per turn when Defaulting"
## but no code path read the field. CTB-with-AP folds BP into AP
## (Defer = Default), so the bonus must hit AP at defer time. The
## "recover 1 extra" line in the menu blurb was a lie — defer gave
## only the standard natural +1 next turn.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_execute_defer_grants_bonus() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_defer")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_get_passive_meta_effect_sum(\"bp_regen_bonus\")"),
		"_execute_defer must consult the caster's bp_regen_bonus")
	assert_true(body.contains("combatant.gain_ap(bp_bonus)"),
		"_execute_defer must call gain_ap with the bonus")


func test_data_still_authors_bp_bonus() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("bp_recovery"))
	var me: Variant = data["bp_recovery"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(int(me.get("bp_regen_bonus", 0)), 0,
		"bp_recovery must still author bp_regen_bonus > 0")


func test_runtime_no_passive_no_extra_ap() -> void:
	# Regression guard: a deferring combatant WITHOUT bp_recovery
	# must NOT silently gain extra AP — fix must be passive-gated.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var c: Combatant = _make("Vanilla")
	c.current_ap = 0
	c.equipped_passives = []
	bm._execute_defer(c)
	assert_eq(c.current_ap, 0,
		"vanilla combatant must NOT gain AP from defer — fix must not silently buff baseline")
	# is_defending should still flip (the defer itself still ran).
	assert_true(c.is_defending,
		"defer must still set is_defending regardless of passive")


func test_runtime_with_passive_grants_extra_ap() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("bp_recovery"):
		pending("bp_recovery passive required")
		return
	var c: Combatant = _make("Tactician")
	c.current_ap = 0
	c.equipped_passives = ["bp_recovery"]
	bm._execute_defer(c)
	assert_gt(c.current_ap, 0,
		"bp_recovery-equipped defer must grant the authored bonus AP")


func test_runtime_clamps_at_cap() -> void:
	# Edge case: gain_ap caps at +4. Starting at 4, defer must not
	# silently re-emit ap_changed or fail; current_ap stays at 4.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("bp_recovery"):
		pending("bp_recovery passive required")
		return
	var c: Combatant = _make("Capped")
	c.current_ap = 4
	c.equipped_passives = ["bp_recovery"]
	bm._execute_defer(c)
	assert_eq(c.current_ap, 4,
		"defer at AP cap (+4) must clamp — no overflow past 4")
