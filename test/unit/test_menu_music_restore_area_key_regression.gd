extends GutTest

## Regression test for the 2026-07-25 playtest report:
## "also the menu music still bleeds and stays in overworld".
##
## Bug 2801's round-2 fallback was live but calling the wrong function.
## _derive_current_scene_music_key() returns an AREA key — "village",
## "interior_*", "overworld" — because all three of its sources are area keys:
##   _get_music_area_id()  → BaseVillage, consumed via play_area_music
##   _get_music_track()    → BaseInterior, ALSO consumed via play_area_music
##   "overworld"           → the hardcoded default, an area
## but the caller passed it to play_music(), which takes TRACK names.
##
## SoundManager.play_music("village") has no matching case, falls to the
## default branch, and push_warning()s "Unknown music track: village" without
## starting anything — so the menu bed kept playing. Confirmed in a real
## session log 2026-07-25.
##
## Two namespaces, similar-looking strings, and the failure is a warning rather
## than a crash — so it survived a fix that was otherwise correct.

const LOOP_PATH := "res://src/GameLoop.gd"
const SOUND_PATH := "res://src/audio/SoundManager.gd"


func _loop_src() -> String:
	return FileAccess.get_file_as_string(LOOP_PATH)


func test_scene_derived_fallback_uses_the_area_api() -> void:
	var src := _loop_src()
	var start := src.find("func _teardown_overworld_menu_widget")
	assert_gt(start, 0, "_teardown_overworld_menu_widget must exist")
	var body := src.substr(start, 2400)
	var idx := body.find("_derive_current_scene_music_key()")
	assert_gt(idx, 0, "the scene-derived fallback must still be wired")
	var after := body.substr(idx, 900)
	assert_true(
		after.contains("play_area_music(fallback)"),
		"the scene-derived key is an AREA key — it must go to play_area_music(); "
		+ "play_music() has no 'village' case and silently leaves menu music playing"
	)
	assert_false(
		after.contains("play_music(fallback)"),
		"play_music(fallback) is the regression — area keys are not track names"
	)


func test_snapshot_path_still_uses_the_track_api() -> void:
	# The OTHER branch is genuinely a track name (_current_music), so it must
	# NOT be "fixed" to play_area_music. Both calls sit two lines apart and
	# take opposite APIs; that asymmetry is the whole trap.
	var src := _loop_src()
	assert_true(
		src.contains("SoundManager.play_music(_pre_menu_music_track)"),
		"the snapshot branch holds SoundManager._current_music, a TRACK name — it must stay on play_music"
	)


func test_village_is_a_known_area_but_not_a_known_track() -> void:
	# Pins the asymmetry that made the bug possible, so if someone later adds a
	# "village" case to play_music this test explains why it mattered.
	var snd := FileAccess.get_file_as_string(SOUND_PATH)
	var area_start := snd.find("func _start_area_music_deferred")
	assert_gt(area_start, 0, "_start_area_music_deferred must exist")
	var area_body := snd.substr(area_start, 2600)
	assert_true(
		area_body.contains('"village"'),
		"'village' must remain a handled AREA key — the fallback depends on it resolving"
	)


func test_every_source_of_the_derived_key_is_an_area_key() -> void:
	# If a future source returned a real track name, routing it to
	# play_area_music would break in the opposite direction. Pin the contract.
	var src := _loop_src()
	var start := src.find("func _derive_current_scene_music_key")
	assert_gt(start, 0, "_derive_current_scene_music_key must exist")
	var body := src.substr(start, 900)
	for source in ["_get_music_area_id", "_get_music_track"]:
		assert_true(body.contains(source), "%s must remain a source of the derived key" % source)
	assert_true(body.contains('return "overworld"'),
		"the final fallback must stay an area key, not a track name")
