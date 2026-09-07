extends GutTest

## tick 416: two dead BattleManager signals removed:
##
##   - autobattle_toggled: declared on BattleManager but NEVER
##     emitted there. The live signal of the same name lives on
##     AutobattleToggleUI where the toggle UI actually emits it.
##     Keeping a same-named no-op signal on BattleManager confused
##     readers trying to trace toggle events.
##
##   - battle_actions_logged: emitted by end_battle but had ZERO
##     listeners. The autogrind path at GameLoop:4185 already calls
##     _summarize_battle_actions() synchronously and feeds the
##     result into AutogrindSystem.update_learned_patterns. The
##     signal emit just computed the summary a second time per
##     battle for no reader.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_autobattle_toggled_signal_removed() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# The declaration line must be gone.
	assert_false(src.contains("signal autobattle_toggled(character_id"),
		"BattleManager must NOT declare autobattle_toggled — the live signal lives on AutobattleToggleUI")


func test_battle_actions_logged_signal_removed() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_false(src.contains("signal battle_actions_logged"),
		"BattleManager must NOT declare battle_actions_logged — dead signal with no listeners")
	# The emit must also be gone.
	assert_false(src.contains("battle_actions_logged.emit"),
		"BattleManager must NOT emit battle_actions_logged — the autogrind path uses _summarize_battle_actions directly")


func test_autobattle_toggle_ui_still_has_signal() -> void:
	# Sanity: the live signal must still exist on AutobattleToggleUI.
	var src: String = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleToggleUI.gd")
	assert_true(src.contains("signal autobattle_toggled(character_id"),
		"AutobattleToggleUI must still declare autobattle_toggled (the live signal)")


func test_autogrind_summary_path_intact() -> void:
	# Sanity: GameLoop's autogrind path must still call the summary
	# function synchronously (so removing the signal doesn't lose
	# pattern-learning data).
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("BattleManager._summarize_battle_actions()"),
		"GameLoop must still call BattleManager._summarize_battle_actions() in the autogrind path")
	assert_true(src.contains("AutogrindSystem.update_learned_patterns(region_id, battle_summary)"),
		"GameLoop must still feed the summary into AutogrindSystem")
