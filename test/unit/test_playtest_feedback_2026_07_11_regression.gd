extends GutTest

## struktured's live-playtest feedback 2026-07-11, all three UI verdicts:
## 1. Victory panel overlapped the party victory animations (his cap shows
##    sprites at x>800, log at x<180) — panel now sits x 200..600 with a
##    light backdrop so the animations stay visible AND lit.
## 2. "The 0.5x battle speed is the correct default. THAT should be 1x" —
##    labels rebased so engine 0.25 = "1x" = the default, everywhere
##    (battle ladder, settings menu, GameState default, save migration v3).

const BSD_PATH := "res://src/battle/BattleResultsDisplay.gd"
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")
const SettingsMenuScript := preload("res://src/ui/SettingsMenu.gd")


func test_victory_panel_clears_sprites_and_log() -> void:
	var src := FileAccess.get_file_as_string(BSD_PATH)
	assert_true("PRESET_CENTER_LEFT" in src,
		"panel must be left-anchored, not centered over the party sprites")
	assert_true("panel.offset_left = 200" in src,
		"panel starts at x=200 — right of the battle log (x<180)")
	assert_true("panel.offset_right = 200 + panel_width" in src,
		"panel ends at x=600 — left of the party sprites (x>800)")
	var backdrop_i := src.find("backdrop.color")
	assert_true("0.22" in src.substr(backdrop_i, 60),
		"full-screen dim must stay light (0.22) so victory animations remain lit")


func test_speed_ladder_rebased_engine_quarter_is_one_x() -> void:
	assert_eq(BattleSceneScript.BATTLE_SPEEDS[0], 0.25, "slot 0 = engine 0.25")
	assert_eq(BattleSceneScript.BATTLE_SPEED_LABELS[0], "1x",
		"engine 0.25 must be LABELED 1x — struktured: the old 0.5x pacing is the correct default")
	assert_eq(BattleSceneScript.BATTLE_SPEEDS.size(), BattleSceneScript.BATTLE_SPEED_LABELS.size())
	for i in range(1, BattleSceneScript.BATTLE_SPEED_LABELS.size()):
		var expect := "%dx" % int(round(BattleSceneScript.BATTLE_SPEEDS[i] * 4.0))
		assert_eq(BattleSceneScript.BATTLE_SPEED_LABELS[i], expect,
			"label at %d must be engine*4 (ladder is coherent)" % i)


func test_settings_menu_matches_battle_scale() -> void:
	assert_eq(SettingsMenuScript.BATTLE_SPEED_PRESETS[0], 0.25)
	assert_eq(SettingsMenuScript.BATTLE_SPEED_LABELS[0], "1x",
		"settings and battle must speak the same scale")
	for i in SettingsMenuScript.BATTLE_SPEED_PRESETS.size():
		assert_eq(SettingsMenuScript.BATTLE_SPEED_LABELS[i],
			"%dx" % int(round(SettingsMenuScript.BATTLE_SPEED_PRESETS[i] * 4.0)))


func test_default_speed_is_quarter_engine_scale() -> void:
	var gs_src := FileAccess.get_file_as_string("res://src/meta/GameState.gd")
	assert_true("var default_battle_speed: float = 0.25" in gs_src,
		"fresh-game default must be engine 0.25 (labeled 1x)")
	var save_src := FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	assert_true("speed_scale_v3" in save_src,
		"settings migration v3 must exist so pre-rebase files reset once to the new default")
	assert_true("BATTLE_SCENE_SCRIPT._battle_speed_index = 0" in save_src,
		"v3 one-time reset must land on index 0 (the new 1x)")
