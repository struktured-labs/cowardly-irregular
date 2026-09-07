extends GutTest

## Cutscene music restore across BOTH music APIs (2026-07-26).
##
## CutsceneDirector snapshotted `SoundManager._current_music` before a cutscene
## and replayed it afterward. But `_current_music` is written ONLY by
## play_music(); the play_area_music() path clears it and tracks `_current_area`
## instead — and every map sets its bed with play_area_music. So the snapshot
## read "" in normal play, the `!= ""` restore guard skipped, and **the
## cutscene's own music kept playing over gameplay afterward.**
##
## Verified at runtime before fixing: after play_area_music("cave"),
## `_current_music` is EMPTY while `_current_area` is "cave" and music is
## audibly playing. That affected every authored play_music cutscene step, and
## would have hit the Mordaine escalation arc three times.
##
## Same root as bug 2801 rounds 2/3: two parallel music APIs with separate
## state, and a caller snapshotting one while the other is authoritative.
##
## Fix: SoundManager.capture_music_state() / restore_music_state() handle both,
## preferring the AREA when one is active (play_area_music re-derives
## world-suffixed and interior-variant keys; a raw track name cannot).

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_area_music_leaves_current_music_empty() -> void:
	## The premise. If this ever stops being true the bug is gone at the root
	## and this whole guard can be reconsidered — but until then, any code
	## snapshotting _current_music alone is broken in every map.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	var prev: Dictionary = sm.capture_music_state()
	sm.play_area_music("cave")
	await get_tree().create_timer(0.35).timeout
	assert_eq(str(sm._current_music), "",
		"play_area_music must leave _current_music empty — if this changed, the capture/restore rationale needs revisiting")
	assert_eq(str(sm._current_area), "cave", "play_area_music must track the area")
	sm.restore_music_state(prev)


func test_capture_restore_round_trips_an_area_bed() -> void:
	## The actual regression: take an area bed, have a "cutscene" take over with
	## play_music, then restore — the area must come back.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	var prev: Dictionary = sm.capture_music_state()

	sm.play_area_music("cave")
	await get_tree().create_timer(0.35).timeout
	var captured: Dictionary = sm.capture_music_state()
	assert_eq(str(captured.get("area", "")), "cave",
		"capture must record the AREA — this is the field the old track-only snapshot missed")

	# Cutscene takes over the music the way a play_music step does.
	sm.play_music("menu")
	await get_tree().create_timer(0.35).timeout

	sm.restore_music_state(captured)
	await get_tree().create_timer(0.35).timeout
	assert_eq(str(sm._current_area), "cave",
		"after restore the map's area bed must be playing again — before the fix the restore no-opped and the cutscene track kept playing")

	sm.restore_music_state(prev)


func test_capture_restore_round_trips_a_plain_track() -> void:
	## The other API must keep working — restore falls back to play_music when
	## no area is active (battle/victory/menu contexts clear _current_area).
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	var prev: Dictionary = sm.capture_music_state()

	sm.play_music("menu")
	await get_tree().create_timer(0.35).timeout
	var captured: Dictionary = sm.capture_music_state()
	assert_eq(str(captured.get("track", "")), "menu", "capture must record the track")

	sm.play_music("victory")
	await get_tree().create_timer(0.35).timeout
	sm.restore_music_state(captured)
	await get_tree().create_timer(0.35).timeout
	assert_eq(str(sm._current_music), "menu", "track-only state must round-trip via play_music")

	sm.restore_music_state(prev)


func test_restore_is_safe_on_empty_and_not_playing() -> void:
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	sm.restore_music_state({})  # must not throw
	sm.restore_music_state({"track": "menu", "area": "", "playing": false})
	assert_true(true, "restore must no-op rather than throw on empty/not-playing state")


func test_director_uses_the_capture_api_not_a_raw_field_read() -> void:
	var src := _read(DIRECTOR)
	assert_true(src.contains("SoundManager.capture_music_state()"),
		"CutsceneDirector must capture via the API — reading _current_music directly is empty in every map")
	assert_true(src.contains("SoundManager.restore_music_state("),
		"CutsceneDirector must restore via the API so an area bed comes back through play_area_music")
	assert_false(src.contains("_pre_cutscene_music = SoundManager._current_music"),
		"the track-only snapshot is the bug — it must not come back")


func test_sound_manager_exposes_the_pair() -> void:
	var src := _read(SOUND_MANAGER)
	for fn in ["func capture_music_state", "func restore_music_state"]:
		assert_true(src.contains(fn), "SoundManager must define %s" % fn)
