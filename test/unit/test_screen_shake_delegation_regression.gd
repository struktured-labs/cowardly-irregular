extends GutTest

## Phase A: EffectSystem._trigger_screen_shake delegates to the trauma rig during battle
## but MUST keep its legacy tween path — CutsceneDirector shakes the EXPLORATION camera
## through this same function with no rig registered. Single-writer rule: when a rig
## exists, the legacy tween must never also write camera.offset.

func _src() -> String:
	return FileAccess.get_file_as_string("res://src/battle/EffectSystem.gd")


func test_delegation_branch_exists_and_returns() -> void:
	var src := _src()
	var i := src.find("func _trigger_screen_shake")
	assert_gt(i, -1, "_trigger_screen_shake must exist")
	var fn_end := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (fn_end - i) if fn_end > -1 else 4000)
	var d := body.find("BattleJuice.camera_rig != null")
	assert_gt(d, -1, "rig-registered check present")
	var after := body.substr(d, 220)
	assert_true("BattleJuice.add_trauma" in after, "delegates to trauma model")
	assert_true("return" in after, "delegation RETURNS — legacy tween must not also run (single writer)")


func test_legacy_path_and_its_state_resets_survive() -> void:
	# The pre-existing pin (test_effect_system_shake_state_regression) needs these alive; assert here too so a future cleanup can't drop the CutsceneDirector path
	var src := _src()
	var i := src.find("func _trigger_screen_shake")
	var fn_end := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (fn_end - i) if fn_end > -1 else 4000)
	assert_true("_shake_tween = create_tween()" in body, "legacy tween path kept for non-battle callers")
	assert_eq(body.count("_is_shaking = false"), 3, "both early-return resets + terminal callback still present")


func test_settings_gate_precedes_delegation() -> void:
	var src := _src()
	var i := src.find("func _trigger_screen_shake")
	var fn_end := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (fn_end - i) if fn_end > -1 else 4000)
	var gate := body.find("screen_shake_enabled")
	var deleg := body.find("BattleJuice.camera_rig")
	assert_gt(gate, -1, "settings gate present")
	assert_true(gate < deleg, "settings gate runs before delegation — disabled shake never reaches the rig from this path")


func test_cutscene_director_still_calls_through() -> void:
	var cd := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	assert_gt(cd.length(), 1000, "CONTROL: read a real file")
	assert_true("_trigger_screen_shake" in cd, "CutsceneDirector still routes through the shared entry point")
