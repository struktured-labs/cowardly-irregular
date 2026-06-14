extends GutTest

## Regression: new-game default battle speed must be 1.0x, not 0.5x
## (user feedback 2026-06-04).
##
## Pre-fix: BattleScene._battle_speed_index defaulted to 1 (= 0.5x in
## the BATTLE_SPEEDS array [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]). New
## games + settings.json migrations both inherited this slow default.
## Comment claimed "default '1x' = old 0.5x" — off by one.
##
## SaveSystem also had a matching fallback writing `else 1` when
## BattleSceneScript wasn't loaded. The SaveSystem surface is fixed in
## tandem so the default is consistent across new-game / cold-load /
## fallback.


const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"
const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_battle_scene_default_speed_index_is_2() -> void:
	var text = _read(BATTLE_SCENE_PATH)
	assert_true(text.find("static var _battle_speed_index: int = 2") > -1,
		"_battle_speed_index must default to 2 (= 1.0x in BATTLE_SPEEDS)")
	# Anti-pattern: ensure the old default isn't lurking.
	assert_eq(text.find("static var _battle_speed_index: int = 1 "), -1,
		"_battle_speed_index must NOT default to 1 (= 0.5x); regression guard")


func test_battle_speeds_index_2_is_one_x() -> void:
	# Pin the array shape so the index 2 mapping doesn't drift.
	var text = _read(BATTLE_SCENE_PATH)
	assert_true(text.find("const BATTLE_SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]") > -1,
		"BATTLE_SPEEDS array must keep 1.0 at index 2; default index relies on this position")


func test_save_system_fallback_default_is_2() -> void:
	var text = _read(SAVE_SYSTEM_PATH)
	# The fallback for when BattleSceneScript isn't loaded must also be 2.
	assert_true(text.find("BattleSceneScript._battle_speed_index if BattleSceneScript else 2") > -1,
		"SaveSystem.save_settings fallback must default to 2 (= 1.0x), matching BattleScene's static default")
