extends GutTest

## A stinger fired over AREA music must put the area back (2026-07-31).
##
## The resume path saved a bare track id: `_stinger_resume_track = _current_music`.
## But area beds (overworld, village, dungeon) are started by play_area_music,
## which routes through stop_music() and therefore leaves _current_music EMPTY —
## the area lives in _current_area instead. So the guard `!= ""` was false and the
## `finished` handler was never connected: the music simply stopped and stayed
## stopped until the next area change.
##
## Nothing caught this because the only two stingers wired at the time
## (stinger_level_up, stinger_boss_defeated) both fire in BATTLE, where music came
## from play_music("battle") and _current_music WAS set. The bug is invisible until
## a stinger is used anywhere in exploration — which is exactly what hooking
## stinger_item_found / _quest_complete / _save_point does.
##
## The fix captures the whole state (capture_music_state) above the point where
## play_music clears _current_area, and resumes via restore_music_state.

const STINGER := "stinger_quest_complete"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _settle() -> void:
	await get_tree().create_timer(0.35).timeout


func test_premise_area_music_leaves_current_music_empty() -> void:
	## The whole bug rests on this. If it ever stops being true the guard below
	## is testing nothing, so assert it rather than trusting the comment.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	var prev: Dictionary = sm.capture_music_state()
	sm.play_area_music("overworld")
	await _settle()
	assert_eq(str(sm._current_music), "",
		"play_area_music must leave _current_music empty — if this changes, the stinger resume guard needs revisiting, not this test")
	assert_ne(str(sm._current_area), "",
		"play_area_music must record the area it started")
	sm.restore_music_state(prev)


func test_stinger_over_area_music_reconnects_and_restores() -> void:
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	var prev: Dictionary = sm.capture_music_state()

	sm.play_area_music("overworld")
	await _settle()
	var area_before: String = str(sm._current_area)
	assert_ne(area_before, "", "setup: an area bed must be playing before the stinger")

	sm.play_music(STINGER)
	await _settle()
	## The regression proper: pre-fix this connection was never made, because the
	## resume value read as empty. Assert the wiring exists BEFORE asserting what
	## it does — a missing connection and a failed restore look identical downstream.
	assert_gt(sm._music_player.finished.get_connections().size(), 0,
		"a stinger over area music must connect a resume handler — zero connections is the original defect, where the music just stopped")

	sm._music_player.emit_signal("finished")
	await _settle()
	assert_eq(str(sm._current_area), area_before,
		"after the stinger ends the area bed must be back; got area=\"%s\" track=\"%s\"" % [sm._current_area, sm._current_music])

	sm.restore_music_state(prev)


func test_battle_style_stinger_still_resumes_a_plain_track() -> void:
	## The path that already worked. The fix reroutes every stinger through
	## restore_music_state, so this is the "did I break the working case" half —
	## without it, a green suite could mean the new path works and the old one
	## silently regressed.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	var prev: Dictionary = sm.capture_music_state()

	sm.play_music("battle_medieval")
	await _settle()
	assert_eq(str(sm._current_music), "battle_medieval", "setup: a plain track must be playing")

	sm.play_music(STINGER)
	await _settle()
	sm._music_player.emit_signal("finished")
	await _settle()
	assert_eq(str(sm._current_music), "battle_medieval",
		"a stinger over play_music() music must restore that track — this path worked before the fix and must keep working")

	sm.restore_music_state(prev)


func test_a_stinger_over_silence_connects_nothing() -> void:
	## Guards the other direction: restore_music_state early-returns when nothing
	## was playing, so a stinger from silence must not resurrect a stale bed.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	var prev: Dictionary = sm.capture_music_state()

	sm.stop_music()
	await _settle()
	sm.play_music(STINGER)
	await _settle()
	sm._music_player.emit_signal("finished")
	await _settle()
	assert_eq(str(sm._current_area), "",
		"a stinger played from silence must not restore an area")

	sm.restore_music_state(prev)


func test_positive_control_the_state_pair_is_reachable() -> void:
	## If capture/restore were renamed, every test above would still pass by
	## way of pass_test or a no-op, so pin that they exist and round-trip.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager unavailable")
		return
	assert_true(sm.has_method("capture_music_state"), "capture_music_state must exist — the resume path is built on it")
	assert_true(sm.has_method("restore_music_state"), "restore_music_state must exist")
	var snap: Dictionary = sm.capture_music_state()
	assert_true(snap.has("area"), "the captured state must carry the AREA — a track-only capture is the original bug")
	assert_true(snap.has("track"), "the captured state must carry the track")
