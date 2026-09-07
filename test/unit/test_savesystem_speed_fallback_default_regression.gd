extends GutTest

## Regression: SaveSystem.save_settings() battle-speed default.
##
## Bug (port of fix c956d31, lost on the feature/llm-integration branch):
## new-game default battle speed must be 1.0x, not 0.5x. BATTLE_SPEEDS is
## [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0] — index 2 is 1.0x, index 1 is 0.5x.
##
## save_settings() persists BattleScene's static. The original fix wired a
## runtime-load fallback `if BattleSceneScript else 2`; that was promoted
## to a preload class const (BATTLE_SCENE_SCRIPT) which guarantees the
## script is always available at save time — no fallback case can fire.
##
## This regression test pins the equivalent intent under the preload-shape:
##   • save_settings writes BATTLE_SCENE_SCRIPT._battle_speed_index directly.
##   • The fragile 0.5x literal (`else 1`) must never re-appear in any form.
## BattleScene's own static default of 2 is covered by
## test_battle_speed_default_regression.


const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_save_settings_reads_battle_speed_index_via_preload_const() -> void:
	var text = _read(SAVE_SYSTEM_PATH)
	# The preload const must exist.
	assert_true(text.find("const BATTLE_SCENE_SCRIPT := preload(\"res://src/battle/BattleScene.gd\")") > -1,
		"SaveSystem must preload BattleScene.gd as BATTLE_SCENE_SCRIPT")
	# save_settings must read battle_speed_index from the preload const.
	assert_true(text.find("BATTLE_SCENE_SCRIPT._battle_speed_index") > -1,
		"save_settings must persist BATTLE_SCENE_SCRIPT._battle_speed_index (not a literal)")


func test_no_05x_default_for_battle_speed_index() -> void:
	# Anti-pattern: the original 0.5x bug shape was a
	#   `battle_speed_index ... else 1`
	# ternary fallback. Other unrelated `else 1` patterns in the file
	# (e.g. default save slot, default volume fallback) are fine; only the
	# battle_speed_index branch matters.
	var text = _read(SAVE_SYSTEM_PATH)
	# Specifically guard against the legacy bug-shape literals: the
	# runtime-load ternary `_battle_speed_index if BattleSceneScript else 1`
	# and any hard-coded `"battle_speed_index": 1` write.
	assert_eq(text.find("_battle_speed_index if BattleSceneScript else 1"), -1,
		"SaveSystem must NOT carry the legacy `else 1` (= 0.5x) fallback for _battle_speed_index")
	assert_eq(text.find("\"battle_speed_index\": 1"), -1,
		"SaveSystem must NOT write a literal `\"battle_speed_index\": 1` (= 0.5x)")
