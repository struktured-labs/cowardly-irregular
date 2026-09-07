extends GutTest

## Regression tests for the 2026-04-30 UI/menu audit fixes.
##
## Each test corresponds to a bug found by the UI audit and fixed in the
## same commit. Source-level checks because runtime menu construction
## requires the full GameLoop scene context.


func _read_file(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


# Bug: CutsceneDialogue advanced on key-repeat echo, rapid-fire skipping
# multiple lines per held Enter.
func test_cutscene_dialogue_guards_echo_on_advance() -> void:
	var src = _read_file("res://src/cutscene/CutsceneDialogue.gd")
	# Find the ui_accept branch and verify it has `not event.is_echo()`.
	var idx = src.find("event.is_action_pressed(\"ui_accept\")")
	assert_gt(idx, -1, "ui_accept branch must exist")
	var snippet = src.substr(idx, 200)
	assert_string_contains(snippet, "not event.is_echo()",
		"CutsceneDialogue ui_accept must guard against echo events — " +
		"holding Enter otherwise burned through dialogue at OS key-repeat rate")


# Bug: QuestLog used ui_accept as a close action (non-standard) AND lacked
# echo guards on scroll, rebuilding the entire UI per echo.
func test_quest_log_remove_ui_accept_from_close() -> void:
	var src = _read_file("res://src/ui/QuestLog.gd")
	# The close-conditions OR'd ui_cancel/ui_back/ui_accept. ui_accept is wrong
	# (Enter is normally confirm). Verify the new condition is just cancel/back.
	var idx = src.find("closed.emit()")
	assert_gt(idx, -1)
	var snippet_before = src.substr(maxi(0, idx - 200), 200)
	assert_false(snippet_before.contains("ui_accept"),
		"QuestLog close path must not include ui_accept (Enter is confirm, not close)")


func test_quest_log_scroll_guards_echo() -> void:
	var src = _read_file("res://src/ui/QuestLog.gd")
	var up_idx = src.find("event.is_action_pressed(\"ui_up\")")
	var dn_idx = src.find("event.is_action_pressed(\"ui_down\")")
	assert_gt(up_idx, -1, "ui_up must exist")
	assert_gt(dn_idx, -1, "ui_down must exist")
	assert_string_contains(src.substr(up_idx, 80), "not event.is_echo()",
		"QuestLog ui_up scroll must echo-guard — _build_ui rebuilds the " +
		"entire menu on every press, was running per-echo at OS rate")
	assert_string_contains(src.substr(dn_idx, 80), "not event.is_echo()",
		"QuestLog ui_down scroll must echo-guard")


# Bug: WorldMapMenu navigation lacked echo + visibility guard.
func test_world_map_menu_nav_guards_echo() -> void:
	var src = _read_file("res://src/ui/WorldMapMenu.gd")
	var idx = src.find("func _input(event")
	assert_gt(idx, -1, "_input must exist")
	var rest = src.substr(idx, 1500)
	assert_string_contains(rest, "if not visible:",
		"WorldMapMenu _input must early-return when not visible " +
		"(input bleeds to underlying scene otherwise)")
	# At least 4 echo guards (one per nav direction)
	var count = rest.count("not event.is_echo()")
	assert_gte(count, 4,
		"WorldMapMenu _input must have at least 4 echo guards " +
		"(one per nav direction); found %d" % count)


# Bug: SettingsMenu boss-selected fired start_boss_battle BEFORE closed,
# leaving listener queue_free'd while emitter still calling.
func test_settings_menu_boss_emit_order() -> void:
	var src = _read_file("res://src/ui/SettingsMenu.gd")
	var idx = src.find("func _on_boss_selected")
	assert_gt(idx, -1)
	var body = src.substr(idx, 800)
	var closed_idx = body.find("closed.emit()")
	var start_idx = body.find("start_boss_battle.emit(")
	assert_gt(closed_idx, -1, "_on_boss_selected must emit closed")
	assert_gt(start_idx, -1, "_on_boss_selected must emit start_boss_battle")
	assert_lt(closed_idx, start_idx,
		"closed must emit BEFORE start_boss_battle — upstream listener " +
		"queue_free's its own menu in response to start_boss_battle, " +
		"so closed reaching that menu after the queue_free triggers " +
		"warnings on a freed instance.")


# Bug: JukeboxMenu close stopped music globally, leaving overworld silent.
func test_jukebox_menu_resumes_prior_track() -> void:
	var src = _read_file("res://src/ui/JukeboxMenu.gd")
	# Snapshot in _ready
	assert_string_contains(src, "_resume_track = SoundManager._current_music",
		"JukeboxMenu must snapshot the currently-playing track on open " +
		"so it can be restored on close")
	# Restore in _close_menu
	var idx = src.find("func _close_menu")
	assert_gt(idx, -1)
	var body = src.substr(idx, 600)
	assert_string_contains(body, "play_music(_resume_track)",
		"JukeboxMenu._close_menu must resume the snapshot track instead of " +
		"unconditionally calling stop_music — pre-fix, the overworld stayed " +
		"silent until the next area transition")
