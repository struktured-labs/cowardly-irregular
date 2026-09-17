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
	# The defect: _build_ui rebuilds the whole menu per press, and unguarded it ran at OS echo rate.
	# Either the inline guard or MenuNav.step satisfies that — the latter drops echoes AND the
	# analog ramp the inline form never covered, so it is a strictly stronger guarantee.
	var src = _read_file("res://src/ui/QuestLog.gd")
	var inline_up = src.find("event.is_action_pressed(\"ui_up\")")
	if inline_up > -1:
		assert_string_contains(src.substr(inline_up, 80), "not event.is_echo()",
			"QuestLog ui_up scroll must echo-guard")
		var inline_dn = src.find("event.is_action_pressed(\"ui_down\")")
		assert_string_contains(src.substr(inline_dn, 80), "not event.is_echo()",
			"QuestLog ui_down scroll must echo-guard")
		return
	assert_true(src.contains("MenuNav.step("),
		"QuestLog scroll must be echo-guarded, inline or through MenuNav")
	assert_true(src.contains("nav == \"ui_up\"") and src.contains("nav == \"ui_down\""),
		"QuestLog must branch on the latched step, or it is not guarded by MenuNav either")
	var nav_src = _read_file("res://src/ui/MenuNav.gd")
	assert_true(nav_src.contains("event.is_echo()"),
		"MenuNav.step must drop echoes, or routing through it guards nothing")


# Bug: WorldMapMenu navigation lacked echo + visibility guard.
func test_world_map_menu_nav_guards_echo() -> void:
	var src = _read_file("res://src/ui/WorldMapMenu.gd")
	var idx = src.find("func _input(event")
	assert_gt(idx, -1, "_input must exist")
	var rest = src.substr(idx, 1500)
	assert_string_contains(rest, "if not visible:",
		"WorldMapMenu _input must early-return when not visible " +
		"(input bleeds to underlying scene otherwise)")
	# ⛔ WAS: "at least 4 echo guards, one per nav direction". The property is that holding a
	# direction must not rapid-fire — and an inline echo check could never deliver it here, because
	# this grid navigates on the left STICK'S two axes as well as the d-pad, and an axis carries no
	# echo flag. Measured before the conversion: one downward push carried the cursor 0 -> 2 -> 4.
	# Routing through MenuNav satisfies the original property (its first line refuses echoes) AND
	# the half four inline guards never had.
	var nav := _read_file("res://src/ui/MenuNav.gd")
	assert_string_contains(rest, "MenuNav.step(event)",
		"WorldMapMenu must navigate through MenuNav — four inline echo guards cannot see an axis")
	assert_string_contains(nav, "event.is_echo()",
		"MenuNav must still refuse echo events — the property this arm has always defended")
	assert_string_contains(nav, "_h_axis_held",
		"…and must latch the two axes independently, or a held vertical swallows a horizontal step")


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
	# Snapshot in _ready. Pinned the expression `_resume_track =
	# SoundManager._current_music` until 2026-09-11 — which is the bug, not the
	# fix: play_area_music clears that field, so in every map the snapshot read
	# "" and the close faded the world out. The property is that SOMETHING is
	# snapshotted on open; capture_music_state() carries the area as well.
	assert_string_contains(src, "capture_music_state()",
		"JukeboxMenu must snapshot the playing music on open so it can be " +
		"restored on close — and a track-only snapshot is empty in every map")
	# Restore in _close_menu
	var idx = src.find("func _close_menu")
	assert_gt(idx, -1)
	## Scoped to the FUNCTION, not a char count. This was substr(idx, 600): a
	## magnitude that holds only while nobody adds a comment, and a comment is
	## what pushed the call out of it (2026-09-11).
	var rest = src.substr(idx)
	var next_fn = rest.find("\nfunc ", 1)
	var body = rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_string_contains(body, "restore_music_state(_resume_state)",
		"JukeboxMenu._close_menu must resume the snapshot instead of " +
		"unconditionally calling stop_music — pre-fix, the overworld stayed " +
		"silent until the next area transition")
