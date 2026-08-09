extends GutTest

## Regression: entering/exiting the overworld menu in a W2+ overworld restored the wrong
## music (struktured, in-play report 2026-08-08). Root cause was the two-API hazard:
## GameLoop snapshotted the RAW SoundManager._current_music STRING, which is empty for
## area/procedural beds — so W2+ menu-exit fell through to a scene-derive that landed on
## the unsuffixed (W1) bed. W1 masked it because its track rides play_music. Fix:
## capture_music_state()/restore_music_state(), whose restore prefers the AREA and
## re-derives world-suffixed keys — built for exactly this class (see its docstring).


func after_each() -> void:
	if SoundManager:
		SoundManager.stop_music()
		SoundManager._current_area = ""


func test_procedural_worldbed_state_survives_menu_roundtrip() -> void:
	# THE DISCRIMINATING ARM: the exact state a procedural W2+ overworld bed leaves —
	# playing, area set, NO track string. The old string-snapshot captured "" here and
	# the menu theme (or W1's bed) persisted; capture/restore brings the area back.
	assert_not_null(SoundManager, "SoundManager autoload required")
	if SoundManager == null:
		return
	SoundManager._music_playing = true
	SoundManager._current_area = "futuristic_overworld"
	SoundManager._current_music = ""
	var state: Dictionary = SoundManager.capture_music_state()
	SoundManager.play_music("menu")
	assert_eq(SoundManager._current_music, "menu", "PREMISE: menu takeover happened")
	SoundManager.restore_music_state(state)
	assert_true(SoundManager._current_music != "menu",
		"menu music must not persist after restore — the old string snapshot left it playing")
	assert_eq(SoundManager._current_area, "futuristic_overworld",
		"the AREA must come back — a raw track-string snapshot cannot carry it")


func test_area_bed_menu_roundtrip_integration() -> void:
	# Full-path arm: a real area bed through the real APIs, menu over it, restore.
	assert_not_null(SoundManager, "SoundManager autoload required")
	if SoundManager == null:
		return
	SoundManager.play_area_music("futuristic_overworld")
	# play_area_music DEFERS its start one frame (and stop_music runs first) — without
	# this await the premise samples the mid-transition state, not the playing bed.
	await get_tree().process_frame
	await get_tree().process_frame
	var pre_area: String = SoundManager._current_area
	assert_true(SoundManager._music_playing, "PREMISE: area bed playing")
	var state: Dictionary = SoundManager.capture_music_state()
	SoundManager.play_music("menu")
	SoundManager.restore_music_state(state)
	assert_true(SoundManager._current_music != "menu", "bed must take the channel back")
	assert_eq(SoundManager._current_area, pre_area, "same area after the roundtrip")


func test_gameloop_menu_path_uses_state_api() -> void:
	# Wiring pin: the menu path must use the state API, never the raw string again.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true(src.contains("_pre_menu_music_state = SoundManager.capture_music_state()"),
		"menu open must snapshot via capture_music_state()")
	assert_true(src.contains("SoundManager.restore_music_state(_pre_menu_music_state)"),
		"menu teardown must restore via restore_music_state()")
	assert_false(src.contains("_pre_menu_music_track"),
		"the raw-string snapshot must be GONE — it cannot carry area beds")
