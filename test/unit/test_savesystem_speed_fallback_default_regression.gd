extends GutTest

## Regression: SaveSystem.save_settings() battle-speed fallback default.
##
## Bug (port of fix c956d31, lost on the feature/llm-integration branch):
## new-game default battle speed must be 1.0x, not 0.5x. BATTLE_SPEEDS is
## [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0] — index 2 is 1.0x, index 1 is 0.5x.
##
## save_settings() writes battle_speed_index from BattleScene's static, but
## has a fallback for when BattleSceneScript fails to load at save time. That
## fallback defaulted to 1 (= 0.5x), which would persist the slow default and
## clash with BattleScene's intended 1.0x default. The fallback must be 2.
##
## This is SaveSystem's half of the fix; BattleScene's static default is
## covered by its own regression guard.


const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_save_settings_speed_fallback_default_is_2() -> void:
	var text = _read(SAVE_SYSTEM_PATH)
	assert_true(text.find("BattleSceneScript._battle_speed_index if BattleSceneScript else 2") > -1,
		"save_settings() fallback for battle_speed_index must default to 2 " +
		"(= 1.0x in BATTLE_SPEEDS), matching BattleScene's static default")
	# Anti-pattern: the old 0.5x fallback (else 1) must be gone.
	assert_eq(text.find("BattleSceneScript._battle_speed_index if BattleSceneScript else 1"), -1,
		"save_settings() must NOT fall back to index 1 (= 0.5x); regression guard")
