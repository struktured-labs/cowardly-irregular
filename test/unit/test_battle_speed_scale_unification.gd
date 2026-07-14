extends GutTest

## Menu-smoke find 2026-07-03 — the REAL root of "default battle speed
## is like 4x faster than it should be": settings.json persists
## battle_speed_index and boot restores it OVER the static default, and
## the Settings row used pre-recalibration raw-engine labels (its "4x"
## = the battle scale's "8x"). The user's persisted file sat at engine
## 4.0. Fixes: Settings labels unified to the battle scale; one-time
## speed_scale_v2 migration resets stale files to the true default.

const SettingsScript = preload("res://src/ui/SettingsMenu.gd")
const BattleSceneScript = preload("res://src/battle/BattleScene.gd")


func test_settings_labels_match_battle_scale() -> void:
	for i in range(SettingsScript.BATTLE_SPEED_PRESETS.size()):
		var engine_val: float = SettingsScript.BATTLE_SPEED_PRESETS[i]
		var battle_idx: int = BattleSceneScript.BATTLE_SPEEDS.find(engine_val)
		assert_gt(battle_idx, -1, "settings preset %.2f must exist in the battle scale" % engine_val)
		assert_eq(SettingsScript.BATTLE_SPEED_LABELS[i], BattleSceneScript.BATTLE_SPEED_LABELS[battle_idx],
			"settings label for engine %.2f must MATCH the in-battle label — two definitions of '1x' is the 4x-too-fast bug" % engine_val)


func test_settings_load_migrates_pre_v2_files() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	var mig: int = src.find("settings.get(\"speed_scale_v3\"")
	assert_gt(mig, -1, "settings load must check the speed_scale_v3 marker")
	var window: String = src.substr(mig, 400)
	assert_true(window.contains("_battle_speed_index = 0"),
		"pre-v3 files must reset to the true default (index 0 = label 1x = engine 0.25)")


func test_saved_settings_carry_the_marker() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	assert_true(src.contains("\"speed_scale_v3\": true"),
		"save_settings must write the marker or the migration re-fires every boot")
